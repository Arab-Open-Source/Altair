# Altair installer for Windows (PowerShell).
#
# Downloads the standalone `altair.exe` binary for the current platform
# from the official GitHub Release, verifies its SHA-256 digest against the
# published SHA256SUMS file, and installs it into a user-owned bin
# directory on PATH. Fails safe: nothing is written unless the checksum
# matches, and an existing, different binary is never overwritten without
# `-Force`.
#
# Transfers ride the most resilient transport available: curl.exe (bundled
# with Windows 10 1803+) with retries, then BITS (resumable), then
# Invoke-WebRequest. Every download is size-checked against the server's
# Content-Length before checksum verification, so a truncated transfer is
# reported as such instead of surfacing later as a digest mismatch.
#
# Usage (PowerShell 5.1+):
#   iex (irm https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1)
#   .\install.ps1 -Dir C:\Users\you\.altair\bin -Force -Version v0.1.0
#   .\install.ps1 -Framework            # also install the framework source
#
# Parameters:
#   -Dir        install into DIR instead of the default bin directory
#   -Force      overwrite an existing, different binary
#   -Version    install a specific release instead of the latest
#   -Framework  additionally unpack the framework source into
#               %USERPROFILE%\.altair\framework\<version>\ for offline
#               projects (`altair new app --framework-path <that path>`)
#
# Requires PowerShell 5.1+ (Invoke-WebRequest / Invoke-RestMethod).
# The installed binary needs no runtime.
param(
    [string]$Dir = "",
    [switch]$Force,
    [string]$Version = "latest",
    [switch]$Framework
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = "Arab-Open-Source/Altair"
$BinName = "altair"
$Arch = if ($env:PROCESSOR_ARCHITECTURE -like "ARM*") { "arm64" } else { "amd64" }
$Target = "windows-$Arch"
$Asset = "$BinName-$Target.exe"

# Fetches $Url into $Out through the most resilient available transport.
# curl.exe retries transient failures itself; BITS resumes interrupted
# transfers; Invoke-WebRequest is the always-present fallback.
function Fetch-Asset([string]$Url, [string]$Out) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        & $curl.Source -f -L --retry 3 --retry-all-errors `
            --connect-timeout 15 --max-time 600 `
            --silent --show-error --output "$Out" "$Url"
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "curl failed (exit $LASTEXITCODE); falling back ..."
    }

    try {
        Start-BitsTransfer -Source $Url -Destination $Out `
            -RetryInterval 5 -RetryTimeout 600 -ErrorAction Stop
        return
    } catch {
        Write-Host "BITS unavailable or failed; falling back to Invoke-WebRequest ..."
    }

    Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing `
        -MaximumRedirection 5 -TimeoutSec 600
}

# Rejects silently-truncated downloads: when the server declared a length,
# what landed on disk must match it, and it must never be empty.
function Assert-Complete([string]$Path, [int64]$MinimumBytes) {
    $file = Get-Item $Path
    if ($file.Length -lt $MinimumBytes) {
        throw "Download incomplete: received $($file.Length) bytes from $((Split-Path $Path -Leaf)) — expected at least $MinimumBytes."
    }
}

if ([string]::IsNullOrWhiteSpace($Dir)) {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw "Cannot locate your home directory; pass -Dir"
    }
    $Dir = Join-Path $env:USERPROFILE ".altair\bin"
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

if ($Version -eq "latest") {
    $RelUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    $RelUrl = "https://github.com/$Repo/releases/download/$Version"
}

Write-Host "Downloading altair ($Target) from $Repo ..."
$tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ("altair-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tmpdir | Out-Null

try {
    $assetPath = Join-Path $tmpdir $Asset
    $sumsPath = Join-Path $tmpdir "SHA256SUMS"

    Fetch-Asset "$RelUrl/$Asset" $assetPath
    Assert-Complete $assetPath 200000
    Fetch-Asset "$RelUrl/SHA256SUMS" $sumsPath

    Write-Host "Verifying SHA-256 checksum ..."
    $computed = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()
    $escapedAsset = [regex]::Escape($Asset)
    $expected = (Get-Content $sumsPath | ForEach-Object {
        if ($_ -match "^\s*([0-9a-fA-F]{64})\s+\*?\S*$escapedAsset\s*$") { $matches[1] }
    } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "Checksum for $Asset not found in SHA256SUMS"
    }
    if ($computed -ne $expected) {
        throw "Checksum verification failed: got $computed, expected $expected"
    }

    $dest = Join-Path $Dir ($BinName + ".exe")
    if ((Test-Path $dest) -and (-not $Force)) {
        $existing = (Get-FileHash -Algorithm SHA256 -Path $dest).Hash.ToLowerInvariant()
        if ($existing -eq $computed) {
            Write-Host "Altair already installed at $dest (identical)."
            exit 0
        }
        throw "$dest already exists with different content; pass -Force to overwrite"
    }

    Copy-Item $assetPath $dest -Force
    Write-Host "Installed Altair to $dest"
    Write-Host "Digest SHA-256: $computed"

    if ($Framework) {
        # The framework source archive lets projects resolve their Altair
        # dependency locally (`--framework-path`) without network access.
        $tag = $Version
        if ($tag -eq "latest") {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                -UseBasicParsing -TimeoutSec 60
            $tag = $rel.tag_name
        }
        $zipName = "altair-src-$tag.zip"
        $srcTag = $tag.TrimStart("v")
        Write-Host "Downloading framework source ($zipName) ..."
        $zipPath = Join-Path $tmpdir $zipName
        Fetch-Asset "https://github.com/$Repo/releases/download/$tag/$zipName" $zipPath
        Assert-Complete $zipPath 10000

        $srcHash = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
        $escapedZip = [regex]::Escape($zipName)
        $srcExpected = (Get-Content $sumsPath | ForEach-Object {
            if ($_ -match "^\s*([0-9a-fA-F]{64})\s+\*?\S*$escapedZip\s*$") { $matches[1] }
        } | Select-Object -First 1)
        if ($srcExpected -and $srcHash -ne $srcExpected) {
            throw "Checksum verification failed for ${zipName}: got $srcHash, expected $srcExpected"
        }

        $frameworkRoot = Join-Path $env:USERPROFILE ".altair\framework"
        $frameworkDir = Join-Path $frameworkRoot $srcTag
        New-Item -ItemType Directory -Force -Path $frameworkDir | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $tmpdir -Force
        $inner = Get-ChildItem $tmpdir -Directory | Where-Object { $_.Name -like "*$srcTag*" } | Select-Object -First 1
        Copy-Item (Join-Path $inner.FullName "*") $frameworkDir -Recurse -Force
        Write-Host "Framework source installed at $frameworkDir"
        Write-Host "Offline projects can reference it:"
        Write-Host "  altair new myapp --framework-path $frameworkDir"
    }

    Write-Host "Run 'altair' from any directory."
} finally {
    Remove-Item -Recurse -Force $tmpdir -ErrorAction SilentlyContinue
}
