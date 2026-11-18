# Kiln Forever

Kiln agent sessions inside WoW: Forever: an addon (`addon/KilnForever/`, Lua 5.1) and a Node bridge (`bridge/`, no npm
dependencies) that talks to kiln's local phone API. The addon talks to the bridge through an encrypted pixel strip it
draws and load-on-demand slot addons the bridge writes; it never uses sockets. Read [CONTRIBUTING.md](CONTRIBUTING.md) for review and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the two talk. It ships on GitHub releases only, no store.

## Gate

```sh
scripts/gate.sh            # luacheck, smoke test and specs under LuaJIT (and Lua 5.1 when installed), bridge tests
scripts/gate.sh --changed  # only what the files changed against origin/main reach
```

`FOREVER_CORE` names a ForeverCore checkout at `tools/forever-core.txt`'s ref (default `../forever-core`; always set
it from a worktree). CI also runs the asset blacklist and art lint (`forever_tools.assets`, `forever_tools.art`,
helper `UI/Art.lua`), workflows and secrets, and requires its five jobs by name: rename a job and its required check
together. The bridge tests must use a temporary `stateDir`, never `~/.local/state/kiln-forever`. The stub's widget
methods come from the client's API docs: add a real missing method to the stub, never call one the client lacks.
Visible changes need a look in game (`./install.sh`, `/reload`) with screenshots on the PR; `kiln-forever probe`
captures the strip corner when the link is in question. Release: `.agents/skills/release`.

## Forever Core

The addon requires ForeverCore (`## Dependencies: ForeverCore`): one copy of each shared file loads. Never add a copy of
a core file here; change it in ForeverCore. `kiln-forever install` downloads and links ForeverCore only when the game
has none, and leaves a CurseForge copy or an existing link alone. Tracker sections attach through
`ForeverCore.TrackerHost.Attach`.

## Platform and install

Linux only (Omarchy, Hyprland, game under Proton). Keep platform differences inside their module: `wow.js` finds
installs through Wine prefixes and `/proc`, `capture.js` reads the strip (`grim`, `import`, `gamescopectl`),
`bin/kiln-forever.js` is a systemd user unit.

`kiln-forever install` writes the addon, every slot folder and the Signals bells under `addonsHome` and symlinks each
into `_forever_/Interface/AddOns/<same name>`; the symlinks keep them out of addon managers. The bridge's `SlotBank`
reads and writes `addonsHome`, never the game's AddOns folder. Never overwrite a real
folder in AddOns: stop and report it. Replace a symlink only when it already points into our addons home.
`uninstall` removes only symlinks pointing there, then the data, state and config folders after unpairing.

## Measured limits of the game client

Measured on live Forever clients. They look like bugs or workarounds; they are not.

- No sockets or file reads in addons: the channel is the pixel strip out and slot addons plus "bell" sounds in. Do not
  propose another without measuring it in game.
- The client indexes addon folders at launch: new slot folders and addons need a full restart; new files in
  `KilnForever/` and changed TOCs load on `/reload`. Each slot loads once per UI session, so every publish costs a
  slot, which is why the bridge paces updates.
- `PlaySoundFile` always reports `willPlay = true`: judge a bell by `C_Sound.IsPlaying(handle)` a moment later. Bells
  exceed the cacheable sound size so the client re-reads them on every play; keep them that large.
- 8 rotating bells. The addon moves its bell position only from a fresh snapshot's `nextSig`, never from "the bell I
  heard", and the bridge never rings ahead of its own counter; breaking either aliases still-rung bells and burns slots.
- Taint (WFA-38): no hooks on a Blizzard object's methods, no writes to its tables, no calls into its layout code.
  List menus use `MenuUtil` (WFA-36), never `UIDropDownMenu_AddButton`.

## Security invariants

- The strip is encrypted and authenticated (`Crypto.lua` to `bridge/src/strip-crypto.js`; the crypto tests run the
  addon's Lua under Lua 5.1 with `tools/bitstub.lua` and LuaJIT and must agree with Node). Keys stay in file-local
  variables in `Transport.lua`: never on `ns` (exported as the `KilnForever` global) or in SavedVariables.
- The bridge never runs commands from an unencrypted frame and drops frames that fail authentication.
- The bridge's kiln device is paired for the phone API only; do not widen it without a reason in the PR.
- Never commit tokens, keys, hostnames or personal paths.

## Slot manifests

Every `KilnForever_S###` folder has an identical TOC with no `## Dependencies` and loads `Inbox.lua` through `Slot.xml`
with `<Script file="Inbox.lua"></Script>`: addon managers fingerprint folders against all of CurseForge, and this layout
keeps every slot on one fixed fingerprint that matches nothing. Any change to the slot TOC or `Slot.xml` text changes
it: check against WowUp (a rescan lists only "Kiln Forever") before shipping.

## Kiln API

`http://127.0.0.1:7437`. Pairing is a one-time `kiln pair` code traded at `POST /v1/pair`; the token is a device token.
Every other request carries `Authorization: Bearer`, and none may carry an `Origin` header (kiln answers 403). The
session list arrives as a full snapshot over `GET /v1/events`, so the bridge diffs it; close code 4001 means the
device was revoked and must not be retried.

## Style

Lua: tabs. JavaScript: two-space ES modules, Node built-ins only. Markdown: full lines, no hard wrapping. Add a test
only for logic that could regress unnoticed (parsing, bell rules, crypto agreement).

## Standards

- `repo-standards`: the RS-* requirements every cjber and agent-labs-dev repo meets; its `audit.py` checks this repo.
- `wow-forever-addon`: the WFA-* addon requirements (UI, assets, CI and release) that apply to the addon; wins where
  stricter.
