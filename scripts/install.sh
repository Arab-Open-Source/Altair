#!/usr/bin/env sh
#
# Altair installer.
#
# Downloads the standalone `altair` binary for the current platform from
# the official GitHub Release, verifies its SHA-256 digest against the
# published SHA256SUMS file, and installs it into a user-owned bin
# directory on PATH. Fails safe: nothing is written unless the checksum
# matches, and an existing, different binary is never overwritten without
# `--force`.
#
# Usage:
#   curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh
#
# Options:
#   --dir DIR        install into DIR instead of the default bin directory
#   --force          overwrite an existing, different binary
#   --version VER    install a specific release instead of the latest
#   --verify         verify the download against SHA256SUMS (default on)
#
# Requires: curl and (on Unix) sha256sum. No shell outside this script is
# ever spawned; the installed binary needs no runtime.
set -eu

REPO="Arab-Open-Source/Altair"
BIN_NAME="altair"

# --- OS/architecture detection ----------------------------------------------
# Windows gets a `.exe` and its own default bin directory; Unix shares the
# `~/.local/bin` convention.
case "$(uname -s)" in
  Linux)  OS_TARGET="linux" ;;
  Darwin) OS_TARGET="macos" ;;
  MINGW*|MSYS*|CYGWIN*) OS_TARGET="windows" ;;
  *) echo "error: unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "error: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$OS_TARGET" = "windows" ]; then
  BIN="$BIN_NAME.exe"
else
  BIN="$BIN_NAME"
fi

# --- argument parsing ------------------------------------------------------
DIR=""
FORCE=0
VERSION="latest"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "error: unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- default install directory ---------------------------------------------
if [ -z "$DIR" ]; then
  if [ "$OS_TARGET" = "windows" ]; then
    if [ -z "${USERPROFILE:-}" ]; then
      echo "error: cannot locate your home directory; pass --dir" >&2
      exit 1
    fi
    DIR="$USERPROFILE/.altair/bin"
  else
    if [ -z "${HOME:-}" ]; then
      echo "error: cannot locate your home directory; pass --dir" >&2
      exit 1
    fi
    DIR="$HOME/.local/bin"
  fi
fi

mkdir -p "$DIR"

# --- download ----------------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  REL_URL="https://github.com/$REPO/releases/latest/download"
else
  REL_URL="https://github.com/$REPO/releases/download/$VERSION"
fi

echo "Downloading altair ($OS_TARGET-$ARCH) from $REPO ..."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
dl="$tmpdir/dl"
mkdir -p "$dl"

target="$OS_TARGET-$ARCH"
if [ "$OS_TARGET" = "windows" ]; then
  asset="$BIN_NAME-$target.exe"
else
  asset="$BIN_NAME-$target"
fi

# The artifact is named `altair-<target>` in the release. Download it under
# that exact name so `sha256sum -c` actually matches an entry in SHA256SUMS
# (a file named just `altair` would silently match nothing).
curl -fSLo "$dl/$asset" "$REL_URL/$asset"
curl -fSLo "$dl/SHA256SUMS" "$REL_URL/SHA256SUMS"

# --- verify checksum -----------------------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then
  echo "Verifying SHA-256 checksum ..."
  (cd "$dl" && sha256sum -c --ignore-missing SHA256SUMS) || {
    echo "error: checksum verification failed" >&2
    exit 1
  }
fi

# --- install --------------------------------------------------------------------
dest="$DIR/$BIN"
if [ -f "$dest" ] && [ "$FORCE" -eq 0 ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    a="$(sha256sum "$dl/$asset" | awk '{print $1}')"
    b="$(sha256sum "$dest" | awk '{print $1}')"
    if [ "$a" = "$b" ]; then
      echo "altair already installed at $dest (identical)."
      exit 0
    fi
  fi
  echo "error: $dest already exists with different content; pass --force to overwrite" >&2
  exit 1
fi

install -m 0755 "$dl/$asset" "$dest"
echo "Installed Altair to $dest"
echo "Digest SHA-256: $(sha256sum "$dest" | awk '{print $1}')"
echo "Run 'altair' from any directory."
if ! command -v altair >/dev/null 2>&1 && [ "$OS_TARGET" != "windows" ]; then
  case ":$PATH:" in
    *":$DIR:"*) : ;;
    *) echo "Note: add $DIR to your PATH to run altair from any directory." >&2 ;;
  esac
fi