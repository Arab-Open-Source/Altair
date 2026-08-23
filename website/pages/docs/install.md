# Installation

Altair ships prebuilt binaries for Linux, macOS and Windows (both amd64 and arm64). The installer downloads the right build, verifies its SHA-256 checksum against the published `SHA256SUMS`, and copies it onto your `PATH`.

## Linux and macOS

The POSIX installer works with `sh` (requires `curl` and `sha256sum`):

```sh
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh
```

The binary is installed to `~/.local/bin`. If that directory is not on your `PATH`, add it:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Windows

PowerShell (requires `irm`):

```powershell
iex (irm https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1)
```

Or from the classic command prompt:

```cmd
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.cmd | cmd
```

The binary is installed to `%USERPROFILE%\.altair\bin`. You may need to restart your terminal for the `PATH` update to take effect.

Downloads are resilient by design: the installers ride curl's own retries (bundled with Windows 10 1803+), fall back to resumable BITS, then to `Invoke-WebRequest` with a 10-minute ceiling — and every file is size-checked before checksum verification, so a truncated transfer is reported with exact byte counts instead of a mysterious digest failure.

## Verify the installation

```sh
altair version
```

You should see something like `Altair 0.2.0`.

## Offline installs (--framework)

Every release ships the framework source itself as checksummed assets (`altair-src-v<version>.tar.gz` / `.zip`). Pass the framework switch and the installer unpacks it next to the binary:

```powershell
.\install.ps1 -Framework            # Windows: %USERPROFILE%\.altair\framework\<version>\
curl ... | sh -s -- --framework     # Unix:    ~/.altair/framework/<version>/
```

A machine without GitHub access can then scaffold projects against that local copy — no network needed at dependency-resolution time:

```sh
altair new myapp --framework-path "$HOME/.altair/framework/0.3.1"
```

## Installing to a custom directory

```sh
altair install --dir /usr/local/bin
```

The installer refuses to overwrite an unrelated file without `--force`:

```sh
altair install --dir /usr/local/bin --force
```

## Install from source

Inside a checkout of the repository:

```sh
shards install
shards build altair
./bin/altair version
```
