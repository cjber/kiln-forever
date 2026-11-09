# Agents guide

Read [CONTRIBUTING.md](CONTRIBUTING.md) for how changes are reviewed, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the addon and bridge talk. This file lists what you must not break and how to check your work.

## Layout

- `addon/KilnWoW/`: the WoW: Forever addon (Lua 5.1, Blizzard UI templates). `Core/` holds the link to the bridge (`Transport.lua`, `Codec.lua`, `Crypto.lua`) and state; `UI/` holds the window, tracker, notices and minimap button.
- `bridge/`: the Node bridge (`kiln-wow`), with no npm dependencies. `src/bridge.js` handles commands, pacing and snapshots, the `t3.js` module talks to T3 Code, `src/slots.js` writes slots and bells, `src/capture.js` reads the strip, `src/wow.js` finds the game.
- `tools/`: the WoW API stub, headless addon tests and the snapshot fixture.

## Platform

Linux only: Omarchy (Hyprland), with the game under Proton. Keep platform differences inside the module that owns them: `wow.js` finds install folders and the running client through Wine prefixes and `/proc`, `capture.js` reads the strip with `grim` (Hyprland) or `import` (X11), and the service in `bin/kiln-wow.js` is a systemd user unit.

## Measured limits of the game client

These come from measurements on live Forever clients. They look like bugs or workarounds; they aren't.

- **No sockets or file reads in addons.** The addon talks out through the pixel strip and in through load-on-demand slot addons and "bell" sounds. Don't propose a different channel without measuring it in game.
- **The client indexes addon folders at launch.** New slot folders and new addons need a full game restart. New files inside `KilnWoW/` and changed TOCs do load on `/reload`.
- **Each slot loads once per UI session.** Every publish costs a slot, which is why the bridge paces updates.
- **`PlaySoundFile` always reports `willPlay = true`.** Whether a bell rang is judged by `C_Sound.IsPlaying(handle)` a moment later. Bells are over the cacheable sound size, so the client re-reads them on every play.
- **Bell positions.** There are 8 rotating bells. The addon moves its bell position only from a fresh snapshot's `nextSig`, never from "the bell I heard", and the bridge never rings ahead of its own counter. Breaking either rule makes the addon alias still-rung bells and burn every slot.
- **Taint.** Don't use Blizzard's `Menu` API (it caused "blocked action" errors), and don't register anything into the objective tracker (the Kiln section only anchors to it). Keep insecure code out of secure call paths.

## Security invariants

- The strip is encrypted and authenticated (`Crypto.lua` to `bridge/src/strip-crypto.js`). Keys stay in file-local variables in `Transport.lua`. Never put them on `ns`, which is exported as the `KilnWoW` global, or in SavedVariables.
- The bridge never runs commands from an unencrypted frame, and drops frames that fail authentication.
- The bridge's T3 Code session is scoped to reading and running threads. Don't widen it without a reason stated in the PR.
- Never commit tokens, keys, hostnames or personal paths.

## Slot manifests

Every `KilnWoW_S###` folder has an identical TOC with no `## Dependencies`, and loads `Inbox.lua` through `Slot.xml` with `<Script file="Inbox.lua"></Script>`. Addon managers fingerprint folders against all of CurseForge. This layout keeps all slots on one fixed fingerprint that matches nothing, and keeps them out of WowUp's list. Any change to the slot TOC or `Slot.xml` text changes that fingerprint: check it against WowUp (a rescan should list only "Kiln") before shipping.

## T3 Code Nightly API

The bridge uses T3 Code's own WebSocket RPC, which changes between nightlies. When a command fails with a schema error ("Missing key ..."), check the running server's definitions instead of guessing. For example, `thread.unsettle` needs `reason: "user"`, and projects are created with the `projects.mutate` RPC, not `dispatchCommand`.

## Testing

Run what covers your change, once, and read the output:

- `cd bridge && npm test` for anything in `bridge/`, including protocol and crypto. The crypto tests run the addon's Lua under both `lua5.1` (with `tools/bitstub.lua`, unsigned like WoW) and `luajit` (signed), and must agree with Node.
- `lua5.1 tools/smoke.lua addon/KilnWoW tools/fixtures/snapshot.lua` and `luajit tools/smoke.lua addon/KilnWoW tools/fixtures/snapshot.lua` for anything in `addon/`.
- Bridge tests must pass a temporary `stateDir`; never let a test touch `~/.local/state/kiln-wow`.
- The stub's widget methods come from the client's API documentation. If a real method is missing, add it to the stub; don't call methods the client doesn't have.

When to add a test: only for logic that could regress unnoticed (parsing, the bell rules, crypto agreement). Don't add tests that restate a string or config value.

## Verifying UI changes

Tests don't show what the player sees. Anything visible must be checked in game: `./install.sh` from the checkout, `/reload`, then look. (`kiln-wow sync` re-copies the installed addon, not your edits.) Attach screenshots or a short recording to the PR, as CONTRIBUTING.md describes. `kiln-wow probe` captures the strip corner when the link itself is in question.

## Style

- Lua: tabs. JavaScript: two spaces, ES modules, Node built-ins only.
- In Markdown, write full lines with no hard wrapping.
- Text people see is plain and specific: say what happened and what to do.
- Commits are atomic, with short messages that describe the change.
