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

## Verify the installation

```sh
altair version
```

You should see something like `Altair 0.1.2`.

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
