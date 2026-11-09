# Agents guide

Read [CONTRIBUTING.md](CONTRIBUTING.md) for how changes are reviewed, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the addon and bridge talk. This file lists what you must not break and how to check your work.

## Layout

- `addon/KilnForever/`: the WoW: Forever addon (Lua 5.1, Blizzard UI templates). `Core/` holds the link to the bridge (`Transport.lua`, `Codec.lua`, `Crypto.lua`) and state; `UI/` holds the window, notices and art helper plus the Forever Core files vendored byte for byte (tracker host, settings page, report window, error journal and debug log). `tests/`, `tools/` and `types/` are development only and never ship.
- `bridge/`: the Node bridge (`kiln-forever`), with no npm dependencies. `src/bridge.js` handles commands, pacing and snapshots, the `kiln.js` module talks to kiln's local phone API, `src/model.js` maps kiln's session rows to the addon's shapes, `src/slots.js` writes slots and bells, `src/install.js` writes the addons home and its symlinks, `src/capture.js` reads the strip, `src/wow.js` finds the game.
- `tools/`: the WoW API stub, headless addon tests and the snapshot fixture.

## Platform

Linux only: Omarchy (Hyprland), with the game under Proton. Keep platform differences inside the module that owns them: `wow.js` finds install folders and the running client through Wine prefixes and `/proc`, `capture.js` reads the strip with `grim` (Hyprland region or the game's own `-T` toplevel), `import` (X11) or `gamescopectl` (headless gamescope), and the service in `bin/kiln-forever.js` is a systemd user unit.

## Install layout

`install.sh` runs from a clone and copies `bridge/` and `addon/` to `${XDG_DATA_HOME:-~/.local/share}/kiln-forever`. `kiln-forever install` then writes the addon, every slot folder and the Signals bells under that folder's `addons/` directory, and symlinks each folder into `_forever_/Interface/AddOns/<same name>`. The bridge's `SlotBank` reads and writes `addonsHome` (that `addons/` directory), never the game's AddOns folder. The symlinks keep the folders out of addon managers, which skip symlinked folders.

Never overwrite a real folder in AddOns: stop and report it. Replace an existing symlink only when it already points into our addons home. `kiln-forever uninstall` removes only symlinks that point there, then deletes the data, state and config folders after unpairing.

## CI

GitHub Actions runs three jobs on every push to main and every pull request, with no path filters: `bridge` (Node 22 plus `lua5.1` and `luajit`, then `cd bridge && npm test`), `addon` (the smoke test under both Lua 5.1 and LuaJIT, then the vendored specs from `addon/KilnForever` after `python3 tools/fetch_tracker_ui.py`) and `lint` (`luacheck addon tools`, then the shared asset blacklist and art lint from a Forever Core checkout pinned to one commit SHA). Actions are pinned by commit SHA, checkout leaves credentials behind (`persist-credentials: false`) and the workflow has read-only contents permission. Releases are built by `.github/workflows/release.yml` on a `v*` tag after checking the tag matches `bridge/package.json` and the TOC version.

## Measured limits of the game client

These come from measurements on live Forever clients. They look like bugs or workarounds; they aren't.

- **No sockets or file reads in addons.** The addon talks out through the pixel strip and in through load-on-demand slot addons and "bell" sounds. Don't propose a different channel without measuring it in game.
- **The client indexes addon folders at launch.** New slot folders and new addons need a full game restart. New files inside `KilnForever/` and changed TOCs do load on `/reload`.
- **Each slot loads once per UI session.** Every publish costs a slot, which is why the bridge paces updates.
- **`PlaySoundFile` always reports `willPlay = true`.** Whether a bell rang is judged by `C_Sound.IsPlaying(handle)` a moment later. Bells are over the cacheable sound size, so the client re-reads them on every play.
- **Bell positions.** There are 8 rotating bells. The addon moves its bell position only from a fresh snapshot's `nextSig`, never from "the bell I heard", and the bridge never rings ahead of its own counter. Breaking either rule makes the addon alias still-rung bells and burn every slot.
- **Taint.** Follow WFA-38: never touch Blizzard's Lua state, meaning no hooks on a Blizzard object's methods, no writes to its tables, and no calls into its layout or lazy-cache code. The tracker section attaches through `ForeverTrackerHost.Attach`, which keeps the sections outside Blizzard's secure module collection. WFA-36 requires Blizzard's Menu API (`MenuUtil`) for list menus, which is what the shared host's header menu uses; `UIDropDownMenu_AddButton` cannot scroll, so lists never go through it. Art and section order follow WFA-4 and WFA-5. Keep insecure code out of secure call paths.

## Security invariants

- The strip is encrypted and authenticated (`Crypto.lua` to `bridge/src/strip-crypto.js`). Keys stay in file-local variables in `Transport.lua`. Never put them on `ns`, which is exported as the `KilnForever` global, or in SavedVariables.
- The bridge never runs commands from an unencrypted frame, and drops frames that fail authentication.
- The bridge's kiln device is paired for kiln's phone API only. Don't widen it without a reason stated in the PR.
- Never commit tokens, keys, hostnames or personal paths.

## Slot manifests

Every `KilnForever_S###` folder has an identical TOC with no `## Dependencies`, and loads `Inbox.lua` through `Slot.xml` with `<Script file="Inbox.lua"></Script>`. Addon managers fingerprint folders against all of CurseForge. This layout keeps all slots on one fixed fingerprint that matches nothing, and keeps them out of WowUp's list. Any change to the slot TOC or `Slot.xml` text changes that fingerprint: check it against WowUp (a rescan should list only "Kiln Forever") before shipping.

## Kiln API

The bridge uses kiln's local phone API on `http://127.0.0.1:7437`. Pairing is a one-time `kiln pair` code traded at `POST /v1/pair`; the token is a device token, not a session. Every request except pairing carries `Authorization: Bearer`, and no request may carry an `Origin` header (kiln answers 403). Errors are `{error}` with a 4xx or 5xx status. The session list arrives over `GET /v1/events` as a full snapshot each time, so the bridge diffs it; close code 4001 means the device was revoked and must not be retried.

## Testing

Run what covers your change, once, and read the output:

- `cd bridge && npm test` for anything in `bridge/`, including protocol and crypto. The crypto tests run the addon's Lua under both `lua5.1` (with `tools/bitstub.lua`, unsigned like WoW) and `luajit` (signed), and must agree with Node.
- `lua5.1 tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua` and `luajit tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua` for anything in `addon/`.
- From `addon/KilnForever`, `python3 tools/fetch_tracker_ui.py` once, then `TRACKER_UI_ROOT=tools/.cache/tracker-ui luajit tests/tracker_host_spec.lua` and each `tests/*_spec.lua` under LuaJIT, for the vendored Forever Core files.
- `luacheck addon tools --no-color -q` for the Lua style; CI runs `luacheck addon tools`.
- The shared asset blacklist (`forever_tools.assets`) and art lint (`forever_tools.art`, helper `UI/Art.lua`) from a Forever Core checkout, over the addon's Lua and XML without `tests/`, `tools/` or `types/`.
- Bridge tests must pass a temporary `stateDir`; never let a test touch `~/.local/state/kiln-forever`.
- The stub's widget methods come from the client's API documentation. If a real method is missing, add it to the stub; don't call methods the client doesn't have.

When to add a test: only for logic that could regress unnoticed (parsing, the bell rules, crypto agreement). Don't add tests that restate a string or config value.

## Verifying UI changes

Tests don't show what the player sees. Anything visible must be checked in game: `./install.sh` from the checkout, `/reload`, then look. (`kiln-forever sync` re-copies the installed addon, not your edits.) Attach screenshots or a short recording to the PR, as CONTRIBUTING.md describes. `kiln-forever probe` captures the strip corner when the link itself is in question.

## Style

- Lua: tabs. JavaScript: two spaces, ES modules, Node built-ins only.
- In Markdown, write full lines with no hard wrapping.
- Text people see is plain and specific: say what happened and what to do.
- Commits are atomic, with short messages that describe the change.
