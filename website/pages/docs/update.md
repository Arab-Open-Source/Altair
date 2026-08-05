# Updating Altair

The `altair` binary updates itself from the latest GitHub release, with
checksum verification and an atomic swap — no Crystal toolchain required.

## One command

```bash
altair update
```

It downloads the binary for your platform, verifies its SHA-256 digest
against the published `SHA256SUMS`, and replaces the running executable
via a temporary file, so a failed download never leaves a broken `altair`
behind.

## Checking without installing

```bash
altair update --check
```

Reports whether a newer version exists and installs nothing. Safe for
automation: it exits `0` when the installed binary is current and `1`
when an update is available.

## Forcing a reinstall

```bash
altair update --force
```

Downloads and reinstalls even when you already run the latest version —
handy for repairing a corrupted install or re-pinning a release.

## Manual paths

- **Re-run the installer** — `curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh -s -- --force` (or `iex (irm ...)` / `curl ... | cmd` on Windows) downloads the prebuilt binary again.
- **From a source checkout** — `shards build altair && ./bin/altair install --force` builds the current source and copies it onto your `PATH`.

## Updating a project's framework copy

Updating the `altair` binary is separate from updating the framework a
project depends on. Inside a project:

```bash
shards update altair   # bump lib/altair to the newest release
```

A fresh `shards install` after removing `shard.lock` and `lib/` resolves
from scratch. Either way, projects resolve shards to the latest published
git tag.
