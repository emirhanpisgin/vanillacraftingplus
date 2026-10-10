#requires -Version 7.0
<#
    Validates every collected permanent-node jar in build/libs/<Version>/ against
    stonecutter.properties.toml:

      - jar + sources jar exist (and the node's datapack zip)
      - embedded minecraft range == mod.mc_compat (no unresolved ${...})
      - loader metadata file name/format for the era (NeoForge mods.toml < 1.20.6)
      - fabric.mod.json depends on the era-correct Fabric API id
        (`fabric` < 1.18.2, `fabric-resource-loader-v0` from 1.18.2)
      - pack.mcmeta schema: pack_format below resource 65, min/max_format from 65
      - expected entrypoint class present, no leaked loader metadata
      - class-file major version matches the era's Java release
      - no leftover mixin config

    Usage: pwsh -File scripts/validate-jars.ps1 [-Version 1.0.2]
#>
param(
    [string]$Version = "1.0.2"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
Add-Type -AssemblyName System.IO.Compression.FileSystem

$propsPath = Join-Path $Root "stonecutter.properties.toml"
$lines = Get-Content -LiteralPath $propsPath

$sections = [System.Collections.Generic.List[object]]::new()
$current = $null
foreach ($line in $lines) {
    if ($line -match '^\[(fabric|forge|neoforge)\.\"([^\"]+)\"\]') {
        if ($current) { $sections.Add($current) }
        $current = [pscustomobject]@{ Loader = $Matches[1]; Mc = $Matches[2]; Props = @{} }
        continue
    }
    if ($line -match '^\[([^\]]+)\]') { if ($current) { $sections.Add($current) }; $current = $null; continue }
    if ($current -and $line -match '^\s*([A-Za-z0-9_.]+)\s*=\s*(.+?)\s*(#.*)?$') {
        $current.Props[$Matches[1]] = $Matches[2].Trim('"')
    }
}
if ($current) { $sections.Add($current) }

function Get-ClassMajor {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName)
    $e = $Zip.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
    if (-not $e) { return $null }
    $s = $e.Open()
    try {
        $buf = New-Object byte[] 8
        $read = 0
        while ($read -lt 8) { $n = $s.Read($buf, $read, 8 - $read); if ($n -le 0) { break }; $read += $n }
        if ($read -lt 8) { return $null }
        return [int]$buf[6] * 256 + [int]$buf[7]
    } finally { $s.Dispose() }
}

function Read-ZipText {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName)
    $e = $Zip.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
    if (-not $e) { return $null }
    $r = New-Object System.IO.StreamReader($e.Open())
    try { return $r.ReadToEnd() } finally { $r.Dispose() }
}

function Get-ExpectedJava([string]$loader, [version]$mc) {
    if ($loader -eq "fabric") {
        if ($mc -ge [version]"26.1") { return 25 }
        if ($mc -ge [version]"1.20.5") { return 21 }
        if ($mc -ge [version]"1.18") { return 17 }
        return 8
    }
    if ($loader -eq "neoforge") {
        if ($mc -ge [version]"26.1") { return 25 }
        if ($mc -ge [version]"1.20.5") { return 21 }
        return 17
    }
    # forge
    if ($mc -ge [version]"26.1") { return 25 }
    if ($mc -ge [version]"1.20.5") { return 21 }
    if ($mc -ge [version]"1.18") { return 17 }
    if ($mc -ge [version]"1.17") { return 16 }
    return 8
}

$majorToJava = @{ 52 = 8; 60 = 16; 61 = 17; 65 = 21; 69 = 25 }
$failures = 0
$warnings = 0

foreach ($s in ($sections | Sort-Object Loader, Mc)) {
    $fail = [System.Collections.Generic.List[string]]::new()
    $warn = [System.Collections.Generic.List[string]]::new()
    $mc = $s.Mc
    $mcV = [version]$mc
    $range = $s.Props["mod.mc_compat"]
    $packFields = ($s.Props["pack_fields"]) -replace '\\"', '"'
    $expectedJava = Get-ExpectedJava $s.Loader $mcV

    $jarName = "vanillacraftingplus-$($s.Loader)-$Version+$mc.jar"
    $jarPath = Join-Path $Root "build\libs\$Version\$jarName"
    $srcPath = Join-Path $Root "build\libs\$Version\vanillacraftingplus-$($s.Loader)-$Version+$mc-sources.jar"
    $zipPath = Join-Path $Root "build\libs\$Version\vanillacraftingplus-$Version-$mc.zip"
    if (-not (Test-Path $jarPath)) { $fail.Add("missing $jarName"); Write-Host ("{0,-9} {1,-8} FAIL  {2}" -f $s.Loader, $mc, ($fail -join "; ")); $failures++; continue }
    if (-not (Test-Path $srcPath)) { $fail.Add("missing sources jar") }
    if (-not (Test-Path $zipPath)) { $fail.Add("missing datapack zip") }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
    try {
        $entryPoint = if ($s.Loader -eq "fabric") { "com/kryparnold/vanillacraftingplus/VanillaCraftingPlusFabric.class" }
            elseif ($s.Loader -eq "forge") { "com/kryparnold/vanillacraftingplus/VanillaCraftingPlusForge.class" }
            else { "com/kryparnold/vanillacraftingplus/VanillaCraftingPlusNeoForge.class" }
        $classMajor = Get-ClassMajor -Zip $zip -EntryName $entryPoint
        if ($classMajor -eq $null) { $fail.Add("missing $entryPoint") }
        elseif (-not $majorToJava.ContainsKey($classMajor)) { $warn.Add("unknown class major $classMajor") }
        elseif ($majorToJava[$classMajor] -ne $expectedJava) { $warn.Add("java $($majorToJava[$classMajor]) (expected $expectedJava)") }

        if ($zip.Entries | Where-Object { $_.FullName -eq "vanillacraftingplus.mixins.json" }) { $fail.Add("leftover mixin config") }

        $packText = Read-ZipText -Zip $zip -EntryName "pack.mcmeta"
        if ($packText) {
            try { $packObj = ($packText | ConvertFrom-Json).pack } catch { $packObj = $null }
            if (-not $packObj) { $fail.Add("pack.mcmeta does not parse") }
            else {
                try { $expectedPack = "{ $packFields }" | ConvertFrom-Json } catch { $expectedPack = $null }
                if (-not $expectedPack) { $fail.Add("cannot parse pack_fields: $packFields") }
                elseif ($expectedPack.PSObject.Properties["pack_format"]) {
                    if ("$($packObj.pack_format)" -ne "$($expectedPack.pack_format)") { $fail.Add("pack_format=$($packObj.pack_format) want $($expectedPack.pack_format)") }
                    if ($packObj.min_format -or $packObj.max_format) { $fail.Add("legacy schema but min/max_format present") }
                } else {
                    if (-not $packObj.min_format) { $fail.Add("min_format missing") }
                    if (-not $packObj.max_format) { $fail.Add("max_format missing") }
                    if ($packObj.PSObject.Properties["pack_format"]) { $fail.Add("pack_format not allowed with new schema") }
                }
            }
        } else { $fail.Add("missing pack.mcmeta") }

        if ($s.Loader -eq "fabric") {
            $meta = Read-ZipText -Zip $zip -EntryName "fabric.mod.json"
            if (-not $meta) { $fail.Add("missing fabric.mod.json") }
            else {
                if ($meta -match '\$\{') { $fail.Add("unresolved macro in fabric.mod.json") }
                $j = $meta | ConvertFrom-Json
                if ($j.environment -ne "*") { $fail.Add("environment=$($j.environment) want *") }
                if ($j.depends.minecraft -ne $range) { $fail.Add("range='$($j.depends.minecraft)' want '$range'") }
                if ($j.depends.java -ne ">=$expectedJava") { $fail.Add("java dep '$($j.depends.java)' want '>=$expectedJava'") }
                foreach ($dep in @("fabricloader", "minecraft", "java")) {
                    if (-not $j.depends.PSObject.Properties[$dep]) { $fail.Add("dep missing: $dep") }
                }
                if ($mcV -ge [version]"1.18.2") {
                    if (-not $j.depends.PSObject.Properties["fabric-resource-loader-v0"]) { $fail.Add("dep missing: fabric-resource-loader-v0") }
                    if ($j.depends.PSObject.Properties["fabric"]) { $fail.Add("unexpected monolithic fabric dep") }
                } else {
                    if (-not $j.depends.PSObject.Properties["fabric"]) { $fail.Add("dep missing: fabric (monolithic era)") }
                }
                if (-not ($j.entrypoints.main -contains "com.kryparnold.vanillacraftingplus.VanillaCraftingPlusFabric")) { $fail.Add("entrypoint missing") }
                if ($zip.Entries | Where-Object { $_.FullName -eq "META-INF/mods.toml" -or $_.FullName -eq "META-INF/neoforge.mods.toml" }) { $fail.Add("leaked toml metadata") }
            }
        }
        else {
            $tomlName = if ($s.Loader -eq "neoforge" -and $mcV -lt [version]"1.20.5") { "META-INF/mods.toml" } elseif ($s.Loader -eq "neoforge") { "META-INF/neoforge.mods.toml" } else { "META-INF/mods.toml" }
            $meta = Read-ZipText -Zip $zip -EntryName $tomlName
            if (-not $meta) { $fail.Add("missing $tomlName") }
            else {
                if ($meta -match '\$\{') { $fail.Add("unresolved macro in $tomlName") }
                if ($meta -notmatch [regex]::Escape($range)) { $fail.Add("range '$range' not in $tomlName") }
                if (([regex]::Matches($meta, 'side\s*=\s*"BOTH"')).Count -lt 1) { $fail.Add("side=BOTH missing") }
                if ($meta -notmatch 'license\s*=\s*"MIT"') { $fail.Add("license missing") }
                $entryClass = if ($s.Loader -eq "forge") { "com/kryparnold/vanillacraftingplus/VanillaCraftingPlusForge.class" } else { "com/kryparnold/vanillacraftingplus/VanillaCraftingPlusNeoForge.class" }
                if (-not ($zip.Entries | Where-Object { $_.FullName -eq $entryClass })) { $fail.Add("entrypoint class missing") }
                if ($zip.Entries | Where-Object { $_.FullName -eq "fabric.mod.json" }) { $fail.Add("leaked fabric.mod.json") }
                if ($s.Loader -eq "forge") {
                    $fml = $s.Props["deps.forge_fml"]
                    if ($fml -and $meta -notmatch "loaderVersion`?=\s*`"\[$fml,") { $fail.Add("loaderVersion floor != $fml") }
                }
            }
        }
    } finally { $zip.Dispose() }

    $status = if ($fail.Count) { "FAIL" } else { "PASS" }
    if ($fail.Count) { $failures++ }
    if ($warn.Count) { $warnings++ }
    $extra = if ($fail.Count) { "  " + ($fail -join "; ") } elseif ($warn.Count) { "  (" + ($warn -join "; ") + ")" } else { "" }
    Write-Host ("{0,-9} {1,-8} {2}  range={3}{4}" -f $s.Loader, $mc, $status, $range, $extra)
}

Write-Host ""
Write-Host "validated $($sections.Count) node jars: $($sections.Count - $failures) pass, $failures fail, $warnings warnings"
if ($failures -gt 0) { exit 1 }
