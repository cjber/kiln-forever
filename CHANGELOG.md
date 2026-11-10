# Changelog

## [Unreleased]

- **Quick replies are gone.** The transcript offers buttons only when kiln has a real question or permission menu.
- **Transcripts read like the text agents write.** Paragraph lines rejoin with spaces, hard breaks stay, and headings, emphasis, inline and fenced code, nested lists, task items, quotes, tables, links and rules are drawn. Italic and strikethrough get their own colours because the game font has neither. Characters the font cannot draw become plain substitutes or are dropped, from a list generated from the client's own font.
- **Queued messages show while they wait.** When kiln holds a reply in a session's mailbox, the transcript shows it with a dim `Queued` label after the conversation, and the header explains the wait without closing the reply box.
- **Kiln Forever now uses the shared Forever UI.** The tracker section, Settings > AddOns page, minimap button and report window are the same files the other Forever addons use, so the tracker stacks in one column, the options live where the game already puts addon settings, and a bug report opens in the family's report window instead of filling the message box.
- **The tracker keeps your sessions in the shared column.** Sessions that need you come first, then working sessions with live timers, and the section takes its own place after the other Forever addons. Right-click its header to move or hide it.
- **Settings and reports follow the Forever family.** `/kiln settings` opens the Kiln Forever page under Settings > AddOns, `/kiln report` opens a report you can copy, and `/kiln issue` opens a ready-made GitHub issue.
- **The debug log is shared too.** `/kiln debug` turns on the Forever debug log for this session, keeps it on, turns it off or shows its latest lines, and `/kiln errors` reads the same journal the report window does.
- **The addon has one icon family, and the game wears the client's art.** The kiln flame icon is the addon-list, report window and store icon, and every generated live-update slot points at it. In game the window portrait, side tab, minimap button and notices draw the client's own fire spell icon, `Interface\Icons\spell_fire_fire`, whole and with its own bevel.
- **The addon uses only approved art.** Buttons, toasts, dropdowns and status marks now use the client's own templates and atlases, and all art goes through one helper so nothing is stretched.
- **Notices wear the client's own alert toast.** A finished or waiting session now uses the scenario alert the game already shows when a scenario completes, queued through the client's AlertFrame system, with the kiln icon and no achievement shield or points.
- **Tests and tools stay out of the game.** The bridge installer now skips the addon's `tests/`, `tools/` and `types/` folders, and the TOC lists none of them.
- **The session list holds still under the pointer.** A snapshot that reorders a group no longer moves the row you are about to click, and the new order appears when the pointer leaves the list.

## 0.1.0

The first release of Kiln Forever, bringing [kiln](https://github.com/cjber/kiln) agent sessions into World of Warcraft: Forever.

- **Every session in one list.** The window shows what Claude, Codex, OpenCode and Pi sessions are doing, grouped into Working, Needs you, Open and Done, with each session's agent, repository, branch and latest activity.
- **The tracker follows along.** Running sessions sit under the quest tracker with live timers, so you can see progress without opening the window.
- **Read the transcript and reply.** Open a session to read its messages and send a reply from the game. Kiln delivers the reply with its usual phone header when the turn ends.
- **Answer approvals and stop a run.** Permission and question menus from sessions kiln started in tmux can be answered in the window, and those sessions can be stopped.
- **Start a new session.** Pick one of kiln's directories and an agent, write a prompt, and the session starts without leaving the game.
- **Toasts and sounds.** A toast and a sound tell you when a session finishes or needs you, and they wait until combat ends.
- **Encrypted screen link.** The bridge reads the addon's pixel strip and writes live updates into load-on-demand slot addons, with every frame authenticated and encrypted.
