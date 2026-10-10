param(
    [string]$Token = $env:MODRINTH_TOKEN,
    [string]$Version = "1.1.0",
    [ValidateSet("fabric", "forge", "neoforge", "datapack")]
    [string]$Loader = "fabric",
    [string]$ProjectSlug = "vanillacraftingplus",
    [string]$ArtifactsDir = "",
    [string]$Changelog = "",
    [switch]$IncludeSources,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$api = "https://api.modrinth.com/v2"
$fabricApiProjectId = "P7dR8mSH"

if (-not $ArtifactsDir) {
    $ArtifactsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "build\libs\$Version"
}
$ArtifactsDir = (Resolve-Path $ArtifactsDir).Path

if (-not $Changelog) { $Changelog = "Release $Version" }

# game_versions each node's jar claims. Keep these in sync with mod.mc_compat in
# stonecutter.properties.toml and with the node list in settings.gradle.kts.
# Loader gaps: no Forge/NeoForge build for 1.20.5, no NeoForge for 1.20.5/21.2.
$targets = switch ($Loader) {
    "fabric" {
        @(
            @{ Mc = "1.16.5"; Games = @("1.16.5", "1.17", "1.17.1", "1.18", "1.18.1") }
            @{ Mc = "1.18.2"; Games = @("1.18.2", "1.19", "1.19.1", "1.19.2", "1.19.3", "1.19.4", "1.20", "1.20.1", "1.20.2", "1.20.3", "1.20.4", "1.20.5", "1.20.6", "1.21", "1.21.1", "1.21.2", "1.21.3", "1.21.4", "1.21.5", "1.21.6", "1.21.7", "1.21.8", "1.21.9", "1.21.10", "1.21.11", "26.1", "26.1.1", "26.1.2") }
            @{ Mc = "26.2"; Games = @("26.2", "26.3") }
        )
    }
    "forge" {
        @(
            @{ Mc = "1.16.5"; Games = @("1.16.5", "1.17", "1.17.1", "1.18", "1.18.1", "1.18.2", "1.19", "1.19.1", "1.19.2", "1.19.3", "1.19.4", "1.20", "1.20.1", "1.20.2", "1.20.3", "1.20.4") }
            @{ Mc = "1.20.6"; Games = @("1.20.6", "1.21", "1.21.1", "1.21.2", "1.21.3", "1.21.4", "1.21.5", "1.21.6", "1.21.7", "1.21.8", "1.21.9", "1.21.10", "1.21.11") }
            @{ Mc = "26.1"; Games = @("26.1", "26.1.1", "26.1.2", "26.2", "26.3") }
        )
    }
    "neoforge" {
        @(
            @{ Mc = "1.20.4"; Games = @("1.20.4") }
            @{ Mc = "1.20.6"; Games = @("1.20.6", "1.21", "1.21.1", "1.21.3", "1.21.4", "1.21.5", "1.21.6", "1.21.7", "1.21.8", "1.21.9", "1.21.10", "1.21.11") }
            @{ Mc = "26.1"; Games = @("26.1", "26.1.1", "26.1.2", "26.2", "26.3") }
        )
    }
    "datapack" {
        @(
            @{ Mc = "1.16.5"; Games = @("1.16.5") }
            @{ Mc = "1.18.2"; Games = @("1.18.2") }
            @{ Mc = "1.20.4"; Games = @("1.20.3", "1.20.4") }
            @{ Mc = "1.20.6"; Games = @("1.20.5", "1.20.6") }
            @{ Mc = "1.21"; Games = @("1.21", "1.21.1") }
            @{ Mc = "1.21.2"; Games = @("1.21.2", "1.21.3") }
            @{ Mc = "1.21.4"; Games = @("1.21.4") }
            @{ Mc = "1.21.5"; Games = @("1.21.5") }
            @{ Mc = "1.21.6"; Games = @("1.21.6") }
            @{ Mc = "1.21.9"; Games = @("1.21.9", "1.21.10") }
            @{ Mc = "1.21.11"; Games = @("1.21.11") }
            @{ Mc = "26.1"; Games = @("26.1", "26.1.1", "26.1.2") }
            @{ Mc = "26.2"; Games = @("26.2") }
            @{ Mc = "26.3"; Games = @("26.3") }
        )
    }
    default { throw "Unknown loader '$Loader'" }
}

$headers = @{ "User-Agent" = "$ProjectSlug-publish/$Version" }
if ($Token) { $headers["Authorization"] = $Token }

function Get-Json([string]$path) {
    $r = Invoke-WebRequest "$api$path" -Headers $headers -UseBasicParsing
    return $r.Content | ConvertFrom-Json
}

"== Validating project =="
try {
    $project = Get-Json "/project/$ProjectSlug"
    "Project: $($project.title) ($($project.id))"
} catch {
    throw "Project '$ProjectSlug' not found or not accessible: $_"
}

$tags = @((Get-Json "/tag/game_version") | ForEach-Object { $_.version })
foreach ($t in $targets) {
    foreach ($g in $t.Games) {
        if ($tags -notcontains $g) { Write-Warning "Game version tag '$g' does not exist on Modrinth" }
    }
}

if (-not $Token) {
    Write-Warning "No token provided - running in dry-run mode. Set `$env:MODRINTH_TOKEN or pass -Token."
    $DryRun = $true
}

$allVersions = @(Get-Json "/project/$ProjectSlug/version")

foreach ($t in $targets) {
    $mc = $t.Mc
    $isDatapack = $Loader -eq "datapack"
    $jarName = if ($isDatapack) { "$ProjectSlug-$Version-$mc.zip" } else { "$ProjectSlug-$Loader-$Version+$mc.jar" }
    $jarPath = Join-Path $ArtifactsDir $jarName
    $srcName = "$ProjectSlug-$Loader-$Version+$mc-sources.jar"
    $srcPath = Join-Path $ArtifactsDir $srcName
    $versionNumber = if ($isDatapack) { "$Version-$mc" } else { "$Version+$mc" }

    if (-not (Test-Path $jarPath)) { throw "Missing artifact: $jarPath" }
    $jarBytes = [System.IO.File]::ReadAllBytes($jarPath)
    $sha1 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData($jarBytes)).Replace("-", "").ToLower()

    $deps = @()
    if ($Loader -eq "fabric") {
        $fapiVersions = @(Get-Json "/project/$fabricApiProjectId/version?game_versions=%5B%22$mc%22%5D&loaders=%5B%22fabric%22%5D")
        if ($fapiVersions.Count -eq 0) { throw "No Fabric API version on Modrinth for $mc" }
        $deps = @(@{ project_id = $fabricApiProjectId; dependency_type = "required" })
    }

    $name = if ($isDatapack) { "$ProjectSlug $Version datapack for $mc" } else { "$ProjectSlug $Version for $mc ($Loader)" }

    if (@($allVersions | Where-Object { $_.version_number -eq $versionNumber -and $_.loaders -contains $Loader }).Count -gt 0) {
        "SKIP $versionNumber ($Loader already exists)"
        continue
    }

    $data = @{
        name             = $name
        version_number   = $versionNumber
        changelog        = $Changelog
        dependencies     = $deps
        game_versions    = $t.Games
        version_type     = "release"
        loaders          = @($Loader)
        featured         = $false
        status           = "listed"
        requested_status = "listed"
        project_id       = $project.id
        file_parts       = @("file1")
        primary_file     = "file1"
        environment      = "server_only_client_optional"
        file_types       = @{}
    }
    if ($IncludeSources -and -not $isDatapack -and (Test-Path $srcPath)) {
        $data.file_parts = @("file1", "sources1")
        $data.file_types = @{ sources1 = "sources-jar" }
    }

    $dataJson = $data | ConvertTo-Json -Depth 6

    if ($DryRun) {
        "[DRY-RUN] would publish $versionNumber ($jarName, sha1=$sha1) games=[$($t.Games -join ',')] loaders=[$Loader] deps=$($deps.Count)"
        continue
    }

    try {
        $client = [System.Net.Http.HttpClient]::new()
        $client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "$ProjectSlug-publish/$Version") | Out-Null
        $client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", $Token) | Out-Null

        $form = [System.Net.Http.MultipartFormDataContent]::new()
        $form.Add([System.Net.Http.StringContent]::new($dataJson, [System.Text.Encoding]::UTF8, "application/json"), "data")
        $jarPart = [System.Net.Http.ByteArrayContent]::new($jarBytes)
        $fileType = if ($isDatapack) { "application/zip" } else { "application/java-archive" }
        $jarPart.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($fileType)
        $form.Add($jarPart, "file1", $jarName)
        if ($IncludeSources -and -not $isDatapack -and (Test-Path $srcPath)) {
            $srcBytes = [System.IO.File]::ReadAllBytes($srcPath)
            $srcPart = [System.Net.Http.ByteArrayContent]::new($srcBytes)
            $srcPart.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/java-archive")
            $form.Add($srcPart, "sources1", $srcName)
        }

        $resp = $client.PostAsync("$api/version", $form).Result
        $body = $resp.Content.ReadAsStringAsync().Result
        if ($resp.IsSuccessStatusCode) {
            $created = $body | ConvertFrom-Json
            "PUBLISHED $versionNumber -> https://modrinth.com/mod/$ProjectSlug/version/$($created.id)"
        } else {
            Write-Warning "FAILED $versionNumber ($($resp.StatusCode)): $body"
        }
        $client.Dispose()
    } catch {
        Write-Warning "FAILED $versionNumber : $_"
    }
}
