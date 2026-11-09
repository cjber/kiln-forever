<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark-dark.svg">
  <img src="assets/wordmark.svg" alt="Kiln Forever" width="420">
</picture>

**Your kiln agent sessions, inside WoW: Forever.**

See what every Claude, Codex, OpenCode and Pi session is doing from the quest tracker, read and answer them in a
window built from Blizzard's own templates, and answer their questions without leaving the game.

![platform](https://img.shields.io/badge/platform-linux%20%2B%20hyprland-475569?style=flat-square)
![game](https://img.shields.io/badge/wow-forever%2016001-475569?style=flat-square)
![license](https://img.shields.io/badge/license-MIT-475569?style=flat-square)

</div>

---

## Why Kiln Forever

- **One list for every agent.** The window shows each session [kiln](https://github.com/cjber/kiln) knows about, grouped
  into Working, Needs you, Open and Done, with its agent, repository and branch.
- **The tracker tells you when to look.** Running sessions sit under your quests with live timers. A toast and a sound
  fire when one finishes or asks for you, and they wait until combat ends.
- **Answer without alt-tabbing.** Read the transcript, send a reply, stop a run, start a new session in any directory
  kiln offers, and pick an option on a permission or question menu.
- **Nothing to trust but your own machine.** The addon never talks to Blizzard or the network. The bridge talks to
  kiln on `127.0.0.1` with its own paired device token, and everything the game shows on screen is encrypted.

## Install

You need [kiln](https://github.com/cjber/kiln) with its phone server running (`kiln setup`, or `kiln serve --local`)
and `[phone] write = true` in kiln's settings, Node.js 22, `grim`, and WoW: Forever installed through Battle.net.

```sh
curl -fsSL https://raw.githubusercontent.com/cjber/kiln-forever/main/install.sh | bash
```

The installer pairs the bridge with kiln, installs the addon, and starts the `kiln-forever` user service. The first
time, quit and restart the game: the client only finds new addon folders at launch. After that, updates need only a
`/reload`. Run the same command again to update, or `./install.sh` from a clone.

## Using it

| Command | What it does |
| --- | --- |
| `/kiln` | Open or close the window. The minimap button and the game menu do the same. |
| `/kiln new` | Start a session: pick an agent and a directory, then write the prompt. |
| `/kiln settings` | Tracker, toasts, sounds and the minimap button. |
| `/kiln selftest` | Check each step between the game and kiln, and name the one that fails. |
| `/kiln report` | Fill the message box with diagnostics for a bug report. |
| `/kiln unlock` | Drag the tracker section somewhere else. Settings has a reset. |

On the desktop:

```sh
kiln-forever status         # kiln, the game, the screen link and the addon, one line each
kiln-forever status --log   # the same, with recent log lines
kiln-forever uninstall      # remove the addon, the service and the paired device
```

## How it works

Addons can't open connections or read files, so the addon and the bridge talk through what the game does allow:

| Direction | How |
| --- | --- |
| Game to bridge | A small strip of coloured squares in the top-left corner for about a second after you act. The bridge reads it with `grim`. |
| Bridge to game | Load-on-demand slot addons. The game reads a slot's Lua from disk when it loads, so the bridge writes a fresh snapshot there first. |
| "New data" signal | Large silent sound files. The game re-reads big sounds on every play, so the addon knows when to load the next slot. |

The bridge follows kiln's live session feed, reads transcripts for the session you are viewing and any session that is
waiting on you, and sends your replies, stops and answers through kiln's API. Every frame on the strip is encrypted
and authenticated (ChaCha20 and HMAC-SHA-256), so a stream or recording shows only noise. The details and the client
measurements behind them are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Limits

- **Approvals and stop need kiln's tmux.** Kiln reads a permission or question menu from the session's pane, so only
  sessions kiln started can be answered or stopped. Other sessions show kiln's reason and stay read-only.
- **Replies wait for a turn to end.** A message to a busy Claude or Codex session is delivered once it is idle, and
  arrives with kiln's `[kiln message from phone:kiln-forever]` header.
- **Updates have a budget.** The game loads each slot once per session, 1,200 by default, which lasts many hours.
  When the tracker says live updates are paused, `/reload`.

## Requirements

- Linux with Hyprland and `grim`.
- [kiln](https://github.com/cjber/kiln) with its phone server running.
- World of Warcraft: Forever (interface 16001) through Battle.net under Wine.
- Node.js 22 or newer, with no npm dependencies.
- Game sound on: the addon falls back to slower polling without it.

## Credits

Kiln Forever is a fork of [t3code-wow](https://github.com/ryanrhughes/t3code-wow) by Ryan Hughes, which built the
strip, slot and bell link this runs on. [wow-ai](https://github.com/chelinho139/wow-ai) and
[wow-forever-codex](https://github.com/0xinuarashi/wow-forever-codex) first measured how the Forever client loads
files and plays sounds.

## License

[MIT](LICENSE).
