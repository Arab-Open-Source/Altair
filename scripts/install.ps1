# Altair installer for Windows (PowerShell).
#
# Downloads the standalone `altair.exe` binary for the current platform
# from the official GitHub Release, verifies its SHA-256 digest against the
# published SHA256SUMS file, and installs it into a user-owned bin
# directory on PATH. Fails safe: nothing is written unless the checksum
# matches, and an existing, different binary is never overwritten without
# `-Force`.
#
# Usage (PowerShell 5.1+):
#   iex (irm https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1)
#   .\install.ps1 -Dir C:\Users\you\.altair\bin -Force -Version v0.1.0
#
# Parameters:
#   -Dir      install into DIR instead of the default bin directory
#   -Force    overwrite an existing, different binary
#   -Version  install a specific release instead of the latest
#
# Requires PowerShell 5.1+ (Invoke-WebRequest / Invoke-RestMethod).
# The installed binary needs no runtime.
param(
    [string]$Dir = "",
    [switch]$Force,
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = "Arab-Open-Source/Altair"
$BinName = "altair"
$Arch = if ($env:PROCESSOR_ARCHITECTURE -like "ARM*") { "arm64" } else { "amd64" }
$Target = "windows-$Arch"
$Asset = "$BinName-$Target.exe"

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
    try {
        Invoke-WebRequest -Uri "$RelUrl/$Asset" -OutFile $assetPath -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30
    } catch {
        throw "Failed to download $Asset from $RelUrl : $_"
    }
    try {
        Invoke-WebRequest -Uri "$RelUrl/SHA256SUMS" -OutFile $sumsPath -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30
    } catch {
        throw "Failed to download SHA256SUMS from $RelUrl : $_"
    }

    Write-Host "Verifying SHA-256 checksum ..."
    $computed = (Get-FileHash -Algorithm SHA256 -Path $assetPath).Hash.ToLowerInvariant()
    $expected = (Get-Content $sumsPath | ForEach-Object {
        if ($_ -match "^\s*([0-9a-fA-F]{64})\s+\*?\S*$Asset\s*$") { $matches[1] }
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
    Write-Host "Run 'altair' from any directory."
} finally {
    Remove-Item -Recurse -Force $tmpdir -ErrorAction SilentlyContinue
}