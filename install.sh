#!/bin/bash
# Install or update Kiln Forever for World of Warcraft.
#
#   gh repo clone cjber/kiln-forever
#   cd kiln-forever
#   ./install.sh
#
# Run the same command again to update. Options: --wow "/path/to/World of Warcraft" --slots N --no-service
#
# Copies the bridge and addon from this clone to ~/.local/share/kiln-forever, puts
# `kiln-forever` on your PATH, then runs `kiln-forever install`, which writes the addon
# and its live-update slots under that same folder, links them into the game, pairs the
# bridge with kiln as a device, starts it as a user service and walks you through the
# first launch.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "$here/bridge" || ! -d "$here/addon" ]]; then
  echo "Run ./install.sh from a clone of cjber/kiln-forever (gh repo clone cjber/kiln-forever)." >&2
  exit 1
fi

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

mkdir -p "$dest" "$bin"
rm -rf "$dest/bridge.new" "$dest/addon.new"
cp -r "$here/bridge" "$dest/bridge.new"
cp -r "$here/addon" "$dest/addon.new"
rm -rf "$dest/bridge" "$dest/addon"
mv "$dest/bridge.new" "$dest/bridge"
mv "$dest/addon.new" "$dest/addon"
chmod +x "$dest/bridge/bin/kiln-forever.js"
ln -sf "$dest/bridge/bin/kiln-forever.js" "$bin/kiln-forever"
if [[ ":$PATH:" != *":$bin:"* ]]; then
  echo "Note: $bin isn't on your PATH, so run kiln-forever as $bin/kiln-forever (or add $bin to PATH in your shell profile)." >&2
fi

node "$dest/bridge/bin/kiln-forever.js" install "$@"
