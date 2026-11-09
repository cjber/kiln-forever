# Architecture

```
 WoW: Forever (Wine/Proton)                            kiln-forever bridge (Node, user service)
 ┌──────────────────────────────┐   pixels   ┌────────────────────────────────────────┐
 │ KilnForever addon            │──────────▶│ capture.js  grim -T/region, import      │
 │  Transport.lua  strip, queue │            │             or gamescopectl             │
 │  Store.lua      snapshot     │◀──────────│ bridge.js   commands, pacing, snapshots │
 │  UI/*           window,      │   files    │ slots.js   Inbox.lua → KilnForever_S### │
 │                 tracker      │            │             Signals/NNNNN.wav           │
 │                              │            │ kiln.js     WebSocket + HTTP to kiln ──┼──▶ kiln (local phone API)
 └──────────────────────────────┘            └────────────────────────────────────────┘
```

## Constraints this is built around

Measured on live Forever 1.60.1 clients (TOC 16001) by
[wow-forever-codex](https://github.com/0xinuarashi/wow-forever-codex) and
[wow-ai](https://github.com/chelinho139/wow-ai). The approach here builds on that work:

1. Addons can't use sockets or read files. They can draw pixels.
2. The client indexes addon files **at launch**. Files that exist then can be loaded later. `LoadAddOn` reads a load-on-demand addon's Lua from disk when it loads, and each addon loads once per UI session (`/reload` resets that). New files need a full restart.
3. `PlaySoundFile` always reports `willPlay = true`, even for empty or garbage files, so its answer is useless. Whether a bell rang is judged with `C_Sound.IsPlaying` a moment later. A file over the cacheable size is re-read from disk on every play.
4. SavedVariables are only written on `/reload` or logout, and `ReloadUI()` needs a key press or click.

## Install layout

`./install.sh` runs from a clone and copies `bridge/` and `addon/` to `${XDG_DATA_HOME:-~/.local/share}/kiln-forever`. `kiln-forever install` finds the game, checks and pairs with kiln, then writes the addon, every slot folder and the Signals bells under that folder's `addons/` directory. It symlinks each of those folders into `_forever_/Interface/AddOns/<same name>`; addon managers skip symlinked folders, so the slots stay out of their lists. The bridge's `SlotBank` uses the configured `addonsHome`, never the game folder.

A real folder at one of those names is never overwritten. An existing symlink is replaced only when it already points into our addons home. `kiln-forever uninstall` removes only links that point there, then deletes the data, state and config folders after unpairing. The bridge service (`~/.config/systemd/user/kiln-forever.service`) starts after `kiln-serve.service` and `graphical-session.target`.

The addon's `tests/`, `tools/` and `types/` folders are for development only. `syncAddon` in `bridge/src/install.js` skips them, and the TOC never lists them, so neither the specs nor the LuaLS declarations reach the game.

## Shared Forever UI

Kiln Forever uses the Forever family's shared UI rather than its own copies. Each file is vendored byte for byte from [Forever Core](https://github.com/cjber/forever-core) at the same path, and is never edited here:

- `UI/TrackerHost.lua`, `UI/TrackerLock.lua`, `UI/TrackerOrder.lua`, `UI/TrackerQuestie.lua` and `UI/TrackerEqot.lua` build the one tracker column every Forever addon docks into.
- `UI/SettingsPage.lua` draws the Settings > AddOns page and registers its category.
- `Core/MinimapButton.lua` places one button in the suite's minimap ring.
- `Core/SafeCall.lua`, `Core/Log.lua` and `UI/Report.lua` hold error capture, the saved debug log and the report window.

Everything addon specific arrives through the namespace: `ns.TrackerHostSettings` returns the saved column settings, `ns.ReportTitle` names the report window, `ns.L` is the English passthrough for the phrases the shared files draw, and `ns.Art` is the one art helper. The tracker section reports itself with `ForeverTrackerHost.Attach` and `uiOrder = -5`, after Legacy Forever (0, -1), SkillUp Forever (-2), Shortest Path Forever (-3) and Adventure Guide Forever (-4).

The TOC loads the shared files before the addon's own ones, in the order their dependencies need: locale, `Core/Init.lua`, `Core/SafeCall.lua`, `Core/Log.lua`, `Core/MinimapButton.lua`, `UI/Art.lua`, `UI/SettingsPage.lua`, the Questie and EQOT readers, then the tracker lock, order and host, then `UI/Report.lua`. `ns.AttachErrorJournal(KilnForeverDB.errors)` and `ns.AttachLog(KilnForeverDB.log)` run when the saved variables load.

Every texture and atlas is set in `UI/Art.lua`; each atlas is sized from `C_Texture.GetAtlasInfo` so nothing is stretched. The bridge's slot addons point their `## IconTexture` at `Interface\AddOns\KilnForever\media\Icon`, the same icon the TOC and window portrait use.

## Game to bridge: the strip

`Codec.lua` and `codec.js` share one frame format:

```
'T' '3' version  seq(2)  len(2)  payload...  fletcher16(2)
```

**Encryption.** The strip is on screen, so streams and recordings capture it. Version 2 frames (all of them, once the addon has its keys) carry

```
nonce(12)  ChaCha20(records)  HMAC-SHA-256(version, seq, nonce, ciphertext)[0..8]
```

- The bridge makes a random master key per install (`~/.local/state/kiln-forever/strip.key`, mode 0600) and derives an encryption key and a MAC key from it. Both go into every snapshot it writes to the slots. Slot files are never on screen.
- The addon keeps the keys in file-local variables in `Transport.lua`. They aren't on the exported `KilnForever` table and aren't saved. The slot global is cleared on load.
- Nonces are a per-load prefix (time and random bytes) plus a counter, and a frame is re-sealed only when its content changes.
- Version 1 (plaintext) frames are only ever a bare hello with no session id. The addon sends one before it has keys, and the bridge answers it with a snapshot carrying them. The bridge never runs commands from a plaintext frame and drops any encrypted frame that fails the tag.
- Replays are harmless: the bridge only runs command ids above the last one it ran for that session.
- `Crypto.lua` implements ChaCha20 and SHA-256 on the client's `bit` library; the bridge uses Node's. `bridge/test/crypto.test.js` checks they agree under both signed (LuaJIT) and unsigned (WoW-style) `bit` results, and that a strip the addon draws decrypts only with the right keys. Cost in game: about 0.2 ms per frame, a few ms for a full 2,000-character message.

This keeps out viewers and anything else that can draw on the screen. It can't stop another addon in the same game: addons share one Lua state, so a malicious addon could drive Kiln Forever's UI directly. Only install addons you trust.

The frame is packed into 3-bit cells. Each cell is a 3x3-pixel square with R, G and B each fully on or off. The strip is 160 cells per row and up to 40 rows (about 2.4 KB), scaled so one UI unit is one physical pixel. It is anchored at the top-left of `UIParent` on the TOOLTIP strata. The bridge searches cell sizes 2 to 8 and small offsets, so a border or scaling quirk doesn't break it.

**Capture.** On Hyprland the bridge captures the game's own toplevel with `grim -t ppm -T <stableId> -`, so the game keeps working on a hidden workspace or under another window. It probes support once from `grim -h` (a line starting with `-T`) and falls back to the region capture when it is missing or fails; with `-T` the image starts at the window's top-left, so no offset is added. Only the PPM header and the corner rows the decoder needs are kept, and the rest of the stream is drained. X11 uses ImageMagick's `import`. For headless tests, `KILN_FOREVER_CAPTURE=gamescope` (or `kiln-forever run --capture gamescope`) reads `${XDG_STATE_HOME:-~/.local/state}/forever-client/session.json`, runs `gamescopectl screenshot` with `GAMESCOPE_WAYLAND_DISPLAY` set, then crops it to the corner with `magick` or `convert` and feeds the PPM to the same decoder.

The payload is records separated by `RS` (0x1E), with fields separated by `US` (0x1F):

```
H  1  session  ui  nextSlot  sigNext  gen  flags  viewThreadId  addonVersion
C  id  verb  args...                    (one per queued command)
```

- `session` is persistent (SavedVariables). `ui` is new every load, so the bridge can tell a `/reload` happened.
- `flags`:
  - `o`: window open
  - `t`: tracker on
  - `s`: sound signals unavailable
  - `q`: quiet (combat or a quiet instance)
  - `a`: attending (the player is using the window)
- Verbs:
  - `send`, `new`, `stop`, `read`
  - `answer`, `ping`

The strip is drawn only while something is unacknowledged. "Something" means a status change such as opening the window or switching sessions, or a queued command. It is redrawn when content changes and hidden as soon as a snapshot acknowledges its sequence number, usually in under a second. If nothing answers for 20 s, it hides and retries with backoff.

## Bridge to game: slots and signals

`KilnForever_S001...S1200` (1,200 by default) are load-on-demand addons grouped under KilnForever in the addon list (`## Group`). They deliberately have no `## Dependencies`: WowUp hides an unrecognised load-on-demand folder only when all its dependencies are recognised, and KilnForever isn't on CurseForge, so a dependency on it made every slot its own "Unknown" row (1,200 rows, measured with WowUp 2.24). Without it WowUp shows one "Kiln Forever" entry.

Addon managers also fingerprint each folder (a 32-bit hash of the `.toc` and the files it lists) and look it up across all of CurseForge. A slot that listed `Inbox.lua` directly produced a fresh hash with every update, and one collided: WowUp took a slot for a Minecraft modpack, which an "update" would have installed over it. So every slot's TOC is identical and lists a static `Slot.xml`, which loads `Inbox.lua` with `<Script file="Inbox.lua"></Script>`. The scanners only follow self-closing `<Script/>` tags, so all slots share one fixed fingerprint that matches nothing on CurseForge (checked with WowUp's own hashing code and a rescan). Each contains `Inbox.lua`, which assigns `KilnForever_Inbox = { ... }`. The bridge serializes plain data with `luaser.js`, so session text can never become code. All text is escaped for WoW markup (`|` to `||`), then markdown is turned into colors and bullets.

A publish works like this:

1. Build the snapshot: sessions, directories and agents, the viewed session's messages, a pending question, bridge status, command results and the ack.
2. Write it to the slots the addon will load next (from its last confirmed position to a little past the bridge's prediction) and to slots 1 to 3 (what a `/reload` bootstraps from).
3. Ring the next **bell**.

**Bells (the "new update" signal).** Measured on this client:

- `PlaySoundFile` returns `willPlay = true` for *every* file, even empty or garbage ones, so its answer is useless.
- `C_Sound.IsPlaying(handle)` a fraction of a second later is reliable: real sounds play and empty files don't.
- Sound files bigger than `Sound_MaxCacheableSizeInBytes` (174,762 bytes here) are streamed and re-opened from disk on every play (confirmed by watching file access), so they're never stuck in the cache.

So a bell is a 10-second silent WAV (441 KB), and those ten files are all of `Signals/`. The bridge rings bell `k` by writing that sound and empties bell `k-4`. The addon plays bells `sigNext` to `sigNext+3` every 0.5 s, checks which is really playing 0.15 s later, stops them all, and loads one slot if one rang. Eight bells rotate forever, with no per-session limit. They live at `Signals/03991` to `03998.wav`; `03999` (always long) and `04000` (always empty) are the self-test controls. These names already existed when the client started, which matters because the client only knows files that existed at launch.

If game sound is entirely off, the self-test fails and the addon falls back to loading a slot on a timer (3 s while you're using the window, 20 s open, 90 s closed).

Measured in game: a 1.2 s round trip from strip to update, 1 slot per 2 idle minutes with the window closed, and 2 per minute with it open.

**Pacing.** Each publish costs one slot, so the bridge paces by what you're doing:

| Situation | Interval |
| --- | --- |
| Acks and command results | ~0.5 s |
| Viewing a working session | 2 s |
| Window open | 1.5 to 3 s |
| Window closed, status changes | 3 s |
| Window closed, minor changes | 20 s |
| Heartbeat (window open / closed) | 90 s / 240 s |

When few slots remain, intervals stretch 2 to 4 times. When they run out, the addon offers `/reload`.

## kiln side

`src/kiln.js` talks to kiln's local phone API on `http://127.0.0.1:7437`:

- **Auth:** `kiln pair` prints a one-time code, `POST /v1/pair` trades it for a device token, and the token lives at `~/.config/kiln-forever/token` (0600). `kiln revoke <device-id>` unpairs; the bridge treats close code 4001 as "unpaired" and stops reconnecting. `KILN_FOREVER_TOKEN` overrides the file.
- **Live data:** `GET /v1/events` is a read-only WebSocket that sends the full `/v1/sessions` snapshot on open and every 2 seconds. The bridge diffs it into session changes, and reconnects with backoff on any close except 4001.
- **Session detail:** `GET /v1/sessions/:id/view` with a per-session cursor, fetched only for the viewed session and sessions waiting on the player (`activity: "waiting"`). A returned `prompt` becomes the addon's question UI.
- **Directories:** `GET /v1/directories` fills the addon's repository list and agent choices for a new session.
- **Writes:** `POST /v1/sessions/:id/messages` (with an id made from the bridge command id, so retries are idempotent), `/prompt` for a menu answer, `/interrupt`, and `POST /v1/sessions` to start one. `write: false` in the snapshot or a `403` means kiln's `[phone] write` is off; the addon then offers view only.

`src/model.js` is the only module that knows kiln's shapes: session status and unread, the addon's row, transcript messages, the single-question prompt and the tracker's activity label.

## CI and releases

`.github/workflows/ci.yml` runs three jobs on every push to main and every pull request, with no path filters: `bridge` (Node 22, `lua5.1`, `luajit`, then `cd bridge && npm test`), `addon` (the smoke test under both Lua 5.1 and LuaJIT, then the vendored Forever Core specs from `addon/KilnForever` after `tools/fetch_tracker_ui.py`) and `lint` (`luacheck addon tools`, the shared asset blacklist and the art lint). The two art gates run from a Forever Core checkout pinned to one commit SHA. Actions are pinned by commit SHA, checkout uses `persist-credentials: false`, and the workflow has read-only `contents` permission.

`.github/workflows/release.yml` runs on a `v*` tag, checks that the tag matches `bridge/package.json` and the TOC `## Version`, builds `kiln-forever-<version>.tar.gz` from `addon/` (without the addon's `tests/`, `tools/` and `types/` folders), `bridge/` (without tests), `install.sh`, `LICENSE`, `README.md` and `CHANGELOG.md`, and publishes it with the notes from that version's CHANGELOG section. It needs `contents: write`.
