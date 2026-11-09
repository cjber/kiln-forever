#!/bin/bash
# Install or update Kiln Forever for World of Warcraft.
#
#   curl -fsSL https://raw.githubusercontent.com/cjber/kiln-forever/main/install.sh | bash
#
# Run the same command again to update. From a clone, ./install.sh installs that copy.
# Options (after `bash -s --` when piping): --wow "/path/to/World of Warcraft" --slots N --no-service
#
# Copies the bridge and addon to ~/.local/share/kiln-forever, puts `kiln-forever` on your
# PATH, then runs `kiln-forever install`, which installs the addon into the game, pairs
# the bridge with kiln as a device, starts it as a user service and walks you through the
# first launch.
set -euo pipefail

repo="cjber/kiln-forever"
ref="${KILNFOREVER_REF:-main}"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/kiln-forever"
bin="$HOME/.local/bin"

if ! command -v node >/dev/null 2>&1; then
  echo "Kiln Forever for World of Warcraft needs Node.js 22 or newer: mise use -g node@lts (or pacman -S nodejs)." >&2
  exit 1
fi
major="$(node -p 'process.versions.node.split(".")[0]')"
if (( major < 22 )); then
  echo "Kiln Forever for World of Warcraft needs Node.js 22 or newer; found $(node --version)." >&2
  exit 1
fi

if [[ ${XDG_SESSION_TYPE:-} == "wayland" ]] && ! command -v grim >/dev/null 2>&1; then
  echo "Note: install grim so the bridge can see the game (pacman -S grim)." >&2
fi

# Install from this checkout, or download the latest version when piped from curl.
src=""
here="${BASH_SOURCE[0]:-}"
if [[ -n $here && -f $here ]]; then
  here="$(cd "$(dirname "$here")" && pwd)"
  if [[ -d "$here/bridge" && -d "$here/addon" ]]; then
    src="$here"
  fi
fi
if [[ -z $src ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading Kiln Forever for World of Warcraft ($ref)…"
  url="${KILNFOREVER_TARBALL:-https://codeload.github.com/$repo/tar.gz/$ref}"
  if ! curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1; then
    echo "Couldn't download $url." >&2
    exit 1
  fi
  src="$tmp"
fi

mkdir -p "$dest" "$bin"
rm -rf "$dest/bridge.new" "$dest/addon.new"
cp -r "$src/bridge" "$dest/bridge.new"
cp -r "$src/addon" "$dest/addon.new"
rm -rf "$dest/bridge" "$dest/addon"
mv "$dest/bridge.new" "$dest/bridge"
mv "$dest/addon.new" "$dest/addon"
chmod +x "$dest/bridge/bin/kiln-forever.js"
ln -sf "$dest/bridge/bin/kiln-forever.js" "$bin/kiln-forever"
if [[ ":$PATH:" != *":$bin:"* ]]; then
  echo "Note: $bin isn't on your PATH, so run kiln-forever as $bin/kiln-forever (or add $bin to PATH in your shell profile)." >&2
fi

# When piped from curl, stdin is this script; give the guided setup the keyboard.
if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
  node "$dest/bridge/bin/kiln-forever.js" install "$@" </dev/tty
else
  node "$dest/bridge/bin/kiln-forever.js" install "$@"
fi
