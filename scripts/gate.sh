#!/usr/bin/env bash
# The fast local gate: luacheck, the addon smoke test and specs, and the bridge tests.
#   scripts/gate.sh            the whole set
#   scripts/gate.sh --changed  only what the files changed against origin/main reach
# FOREVER_CORE names a ForeverCore checkout at tools/forever-core.txt's ref (default: the sibling ../forever-core).
# The asset blacklist, art lint, workflows and secrets checks stay CI's.
set -euo pipefail

cd "$(dirname "$0")/.."
export FOREVER_CORE
FOREVER_CORE=$(realpath "${FOREVER_CORE:-../forever-core}")

# Print a step's output only when it fails.
quiet() {
    local out
    out=$("$@" 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
}

lint=1 addon=1 bridge=1
case "${1:-}" in
    "") ;;
    --changed)
        base=$(git merge-base origin/main HEAD)
        files=$({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)
        lint=0 addon=0 bridge=0
        grep -qE '^(addon|tools)/.*\.lua$' <<<"$files" && lint=1
        grep -qE '^(addon|tools)/' <<<"$files" && addon=1
        # The bridge's crypto tests run the addon's Lua, so an addon or tools change reaches them too.
        grep -qE '^(bridge|addon|tools)/' <<<"$files" && bridge=1
        ;;
    *) echo "usage: scripts/gate.sh [--changed]" >&2; exit 2 ;;
esac

if ((lint)); then luacheck --no-color -q addon tools; fi
if ((addon)); then
    quiet luajit tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua
    if command -v lua5.1 >/dev/null; then quiet lua5.1 tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua; fi
    (cd addon/KilnForever && for spec in tests/*_spec.lua; do quiet luajit "$spec" || exit 1; done)
fi
if ((bridge)); then (cd bridge && quiet npm test); fi
