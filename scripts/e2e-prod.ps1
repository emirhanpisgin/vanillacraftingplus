#requires -Version 7.0
<#
    Production-jar smoke test: installs a real loader + the built mod jar into an
    isolated game dir (no Gradle dev runtime) and boots a dedicated server.

    Recipes are server-side data, so the assertion is headless:
      - the server reaches "Done ("
      - the mod initialized ("Initializing VanillaCrafting+!")
      - no recipe parse errors in logs/latest.log
    The server is fed `datapack list` + `stop` on stdin and shuts itself down.

    Usage:
        pwsh -File scripts/e2e-prod.ps1 -Node 1.16.5-forge -Mc 1.19        # range test
        pwsh -File scripts/e2e-prod.ps1 -Node 1.20.4-neoforge -Mc 1.21.11  # range test
        pwsh -File scripts/e2e-prod.ps1 -Node 26.1-forge -Mc 26.3
        pwsh -File scripts/e2e-prod.ps1 -Node 1.16.5-fabric -Mc 1.16.5 -KeepDir
#>
param(
    [Parameter(Mandatory = $true)][string]$Node,
    [Parameter(Mandatory = $true)][string]$Mc,
    [int]$TimeoutSec = 420,
    [switch]$KeepDir
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$parts = $Node -split '-'
$Loader = $parts[-1]
$NodeMc = ($parts[0..($parts.Count - 2)] -join '-')
$McV = [version]$Mc
$Label = "$Node@$Mc"

$javaHome = if ($McV -ge [version]"26.1") { "C:\Program Files\Java\jdk-25.0.2" }
    elseif ($McV -ge [version]"1.20.5") { "C:\Program Files\Java\jdk-21" }
    elseif ($McV -ge [version]"1.17") { "C:\Program Files\Java\jdk-17" }
    else { "C:\Program Files\Java\jdk-8" } # real 1.16-era runtime; install a JDK 8 for these targets
$java = Join-Path $javaHome "bin\java.exe"
if (-not (Test-Path $java)) { throw "Missing JDK: $java" }

$Dir = Join-Path $Root "build\prod\$Label"
$ModsDir = Join-Path $Dir "mods"

function Get-Prop([string]$name) {
    $line = Select-String -Path (Join-Path $Root "stonecutter.properties.toml") -Pattern ("^\s*" + [regex]::Escape($name) + "\s*=\s*""?([^""]+)""?\s*$") | Select-Object -First 1
    if ($line) { return ($line.Matches[0].Groups[1].Value) }
    return $null
}

function Get-NodeProp([string]$loader, [string]$mc, [string]$key) {
    $section = $loader + '.' + [char]34 + $mc + [char]34
    $inSection = $false
    foreach ($l in Get-Content (Join-Path $Root "stonecutter.properties.toml")) {
        if ($l -match '^\[([^\]]+)\]') { $inSection = ($Matches[1] -eq $section); continue }
        if ($inSection -and $l -match ('^\s*' + [regex]::Escape($key) + '\s*=\s*"?([^"\s]+)"?\s*$')) { return $Matches[1] }
    }
    return $null
}

$ModVersion = Get-Prop "mod.version"
$jar = Join-Path $Root "build\libs\$ModVersion\vanillacraftingplus-$Loader-$ModVersion+$NodeMc.jar"
if (-not (Test-Path $jar)) { throw "Missing built jar: $jar (run :$Node`:buildAndCollect)" }

if (-not $KeepDir -and (Test-Path $Dir)) { Remove-Item -Recurse -Force $Dir }
New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null
Copy-Item $jar $ModsDir -Force
Set-Content -LiteralPath (Join-Path $Dir "eula.txt") -Value "eula=true"
@"
online-mode=false
enforce-secure-profile=false
white-list=false
enforce-whitelist=false
difficulty=peaceful
level-type=minecraft\:flat
generate-structures=false
spawn-protection=0
view-distance=4
simulation-distance=4
sync-chunk-writes=false
enable-rcon=false
motd=VCP prod smoke
"@ | Set-Content -LiteralPath (Join-Path $Dir "server.properties")

function Save-File([string]$url, [string]$target) {
    if (Test-Path $target) { return $target }
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Invoke-WebRequest $url -OutFile $target -TimeoutSec 900
    return $target
}

function Get-FabricApiJar([string]$mc, [string]$modsDir) {
    $query = 'https://api.modrinth.com/v2/project/P7dR8mSH/version?game_versions=%5B%22' + $mc + '%22%5D&loaders=%5B%22fabric%22%5D'
    $versions = Invoke-RestMethod $query -TimeoutSec 60
    if (-not $versions -or $versions.Count -eq 0) { throw "No Fabric API on Modrinth for $mc" }
    $v = $versions[0]
    $file = $v.files | Where-Object { $_.primary } | Select-Object -First 1
    if (-not $file) { $file = $v.files[0] }
    $target = Join-Path $modsDir $file.filename
    if (-not (Test-Path $target)) { Save-File $file.url $target | Out-Null }
    return $target
}

function Get-ForgeVersion([string]$mc) {
    $xml = [xml](Invoke-WebRequest "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml" -UseBasicParsing -TimeoutSec 60).Content
    $versions = @($xml.metadata.versioning.versions.version | Where-Object { $_ -match ('^' + [regex]::Escape($mc) + '-') })
    if ($versions.Count -eq 0) { throw "No Forge build for $mc" }
    return $versions[-1]
}

function Get-NeoForgeVersion([string]$mc) {
    $xml = [xml](Invoke-WebRequest "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" -UseBasicParsing -TimeoutSec 60).Content
    # "1.21.11" -> "21.11"; 26.x keeps its own prefix ("26.3").
    $short = if ($mc -like "1.*") { (($mc -split '\.')[1..2] -join '.') } else { $mc }
    $versions = @($xml.metadata.versioning.versions.version | Where-Object { $_ -match ('^' + [regex]::Escape($short) + '(\.|$)') })
    if ($versions.Count -eq 0) { throw "No NeoForge build for $mc" }
    return $versions[-1]
}

function Get-VersionJson([string]$mc) {
    $cache = Join-Path $Root "build\.cache\version-$mc.json"
    if (-not (Test-Path $cache)) {
        $manifest = Invoke-RestMethod "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" -TimeoutSec 30
        $entry = $manifest.versions | Where-Object { $_.id -eq $mc } | Select-Object -First 1
        if (-not $entry) { throw "Unknown Minecraft version $mc" }
        Save-File $entry.url $cache | Out-Null
    }
    return (Get-Content $cache -Raw | ConvertFrom-Json)
}

$loaderVer = $null
if ($Loader -eq "fabric") {
    $loaderVer = Get-Prop "deps.fabric_loader"
    $launcher = Join-Path $Dir "fabric-server-launch.jar"
    if (-not (Test-Path $launcher)) {
        $installerMeta = [xml](Invoke-WebRequest "https://maven.fabricmc.net/net/fabricmc/fabric-installer/maven-metadata.xml" -UseBasicParsing -TimeoutSec 60).Content
        $installerVer = $installerMeta.metadata.versioning.release
        $installer = Save-File "https://maven.fabricmc.net/net/fabricmc/fabric-installer/$installerVer/fabric-installer-$installerVer.jar" (Join-Path $Root "build\.cache\fabric-installer-$installerVer.jar")
        "running fabric installer for $Label ($loaderVer, installer $installerVer)..."
        & $java -jar $installer server -mcversion $Mc -loader $loaderVer -downloadMinecraft -dir $Dir 2>&1 | Select-Object -Last 4
        if (-not (Test-Path $launcher)) { throw "Fabric installer produced no fabric-server-launch.jar" }
    }
    Get-FabricApiJar $Mc $ModsDir | Out-Null
    $exe = $java
    $launch = @("-Xmx2G", "-jar", "fabric-server-launch.jar", "nogui")
} else {
    $loaderVer = if ($Mc -eq $NodeMc) {
        Get-NodeProp $Loader $NodeMc $(if ($Loader -eq "forge") { "deps.forge_loader" } else { "deps.neo_loader" })
    } elseif ($Loader -eq "forge") { Get-ForgeVersion $Mc } else { Get-NeoForgeVersion $Mc }

    if ($Loader -eq "forge") {
        $fullVer = if ($Mc -eq $NodeMc) { "$Mc-$loaderVer" } else { $loaderVer }
        $installerUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$fullVer/forge-$fullVer-installer.jar"
    } else {
        $installerUrl = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$loaderVer/neoforge-$loaderVer-installer.jar"
    }
    $installer = Save-File $installerUrl (Join-Path $Root "build\.cache\installer-$Label.jar")
    if (-not (Test-Path (Join-Path $Dir "launcher_profiles.json"))) { Set-Content -LiteralPath (Join-Path $Dir "launcher_profiles.json") -Value "{}" -NoNewline }
    $installed = (Test-Path (Join-Path $Dir "run.bat")) -or ((Get-ChildItem $Dir -Filter "forge-*.jar" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "installer" }).Count -gt 0) -or ((Get-ChildItem $Dir -Filter "neoforge-*.jar" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "installer" }).Count -gt 0)
    if (-not $installed) {
        "running $Loader installer for $Label ($loaderVer)..."
        & $java -jar $installer --installServer $Dir 2>&1 | Select-Object -Last 6
    }

    if (Test-Path (Join-Path $Dir "run.bat")) {
        $exe = "cmd.exe"
        $launch = @("/c", "run.bat", "nogui")
    } else {
        $launcherJar = Get-ChildItem $Dir -Filter "forge-*.jar" | Where-Object { $_.Name -notmatch "installer" } | Select-Object -First 1
        if (-not $launcherJar) { $launcherJar = Get-ChildItem $Dir -Filter "neoforge-*.jar" | Where-Object { $_.Name -notmatch "installer" } | Select-Object -First 1 }
        if (-not $launcherJar) { throw "installer produced no server launcher in $Dir" }
        $exe = $java
        $launch = @("-Xmx2G", "-jar", $launcherJar.Name, "nogui")
    }
}

# --- run -----------------------------------------------------------------------
$cmds = Join-Path $Dir "commands.txt"
Set-Content -LiteralPath $cmds -Value "datapack list`nstop"
$outLog = Join-Path $Dir "console.out.log"
$errLog = Join-Path $Dir "console.err.log"
$env:JAVA_HOME = $javaHome
$env:PATH = (Join-Path $javaHome "bin") + ";" + $env:PATH

"starting $Label (java: $java, loader: $loaderVer)..."
$p = Start-Process -FilePath $exe -ArgumentList $launch -WorkingDirectory $Dir -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -RedirectStandardInput $cmds

$gameLog = Join-Path $Dir "logs\latest.log"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ((Test-Path $gameLog) -and (Select-String -Path $gameLog -SimpleMatch "Done (" -Quiet -ErrorAction SilentlyContinue)) { break }
    if ($p.HasExited) { break }
}
if (-not $p.HasExited) { $p.WaitForExit(90000) | Out-Null }
if (-not $p.HasExited) { taskkill /PID $p.Id /T /F 2>&1 | Out-Null }

# --- assert --------------------------------------------------------------------
$log = if (Test-Path $gameLog) { Get-Content $gameLog -Raw } else { "" }
$modInit = $log -match [regex]::Escape("Initializing VanillaCrafting+!")
$doneSeen = $log -match [regex]::Escape("Done (")
$parseErrors = @()
$loadedLine = ""
if (Test-Path $gameLog) {
    $parseErrors = @(Select-String -Path $gameLog -Pattern "Parsing error loading recipe|Couldn't parse recipe|Failed to parse recipe|Error parsing recipe|Exception loading recipe|Failed to load datapacks|Couldn't load tag|Failed to reload data|Unknown recipe type" -ErrorAction SilentlyContinue)
    $loadedLine = (Select-String -Path $gameLog -Pattern "Loaded \d+ recipes" -ErrorAction SilentlyContinue | Select-Object -Last 1).Line
    if (-not $loadedLine) { $loadedLine = (Select-String -Path $gameLog -Pattern "Loaded \d+ recipe" -ErrorAction SilentlyContinue | Select-Object -Last 1).Line }
}
$datapackLine = (Select-String -Path $gameLog -Pattern "Fabric Mods|vanillacraftingplus" -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { $_.Line }) -join " | "
$result = if ($doneSeen -and $modInit -and $parseErrors.Count -eq 0) { "PASS" } else { "FAIL" }

$report = @(
    "===== VCP prod smoke: $Label ====="
    "date:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "java:    $java"
    "jar:     $jar"
    "loader:  $loaderVer"
    "result:  $result"
    "mod init:            $modInit"
    "server done:         $doneSeen"
    "recipe parse errors: $($parseErrors.Count)"
    "loaded line:         $loadedLine"
    "datapack lines:      $datapackLine"
    "game dir:            $Dir"
)
$reportPath = Join-Path $Root "build\prod\$Label.log"
$report | Set-Content -LiteralPath $reportPath
$report | ForEach-Object { $_ }
if ($parseErrors.Count -gt 0) { $parseErrors | Select-Object -First 5 | ForEach-Object { "  ERR: $($_.Line)" } }

if ($result -ne "PASS") { exit 1 }
