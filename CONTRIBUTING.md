# Contributing

Contributions are welcome. This is an early, experimental release, so bug reports from real use are just as valuable as code.

The supported setup is **Omarchy 4.5.0**, **kiln** with `kiln serve` running, and **World of Warcraft: Forever** under Proton. Changes that make other setups work are welcome, as long as they don't break that.

## Issues

Open an issue for a bug you can reproduce, or for a specific idea. Keep it detailed but straightforward: say what happened, plainly, and leave out the essay.

For a bug, include:

- **Versions**: Omarchy (`omarchy-version`), kiln (`kiln --version`), kiln-forever (`kiln-forever status`).
- **What you did, what you expected, what happened instead.** Steps to reproduce if you have them.
- **`kiln-forever status --log`** output, and the text from `/kiln report` in game.
- **A screenshot or short video** for anything you can see: a layout problem, a wrong state, a notice that didn't appear. It's often the fastest way to explain the problem.

One problem per issue. If you're not sure it's a bug, say so and describe what you saw.

## Pull requests

- **One problem per PR.** Small, focused changes get reviewed and merged faster.
- **Say what changes and why**, in plain terms. Link the issue if there is one.
- **Say how you verified it**: the tests you ran and what you checked in game, with what you saw. Mention anything you couldn't check. "Tests pass" alone isn't enough.
- **Show UI changes.** Anything you can see in game needs before and after screenshots, and a short recording when motion or timing is part of the change. Drag them into the PR description so GitHub hosts them; never commit screenshots or recordings to the repo. If nothing visible changes, one line saying why is enough.
- **Commits** should be atomic, with short messages that describe the change.
- AI-assisted contributions are fine. You're responsible for having read, run and checked the result, the same as any other change.

## Development

```bash
git clone https://github.com/cjber/kiln-forever
cd kiln-forever
./install.sh                 # installs the addon and the bridge from your checkout
```

`./install.sh` copies this checkout to `${XDG_DATA_HOME:-~/.local/share}/kiln-forever`, runs `kiln-forever install`, and that writes the addon, its live-update slots and the signal bells under that folder's `addons/` directory. Each folder is symlinked into `_forever_/Interface/AddOns`, so addon managers skip them and the bridge never writes into the game folder. A real folder with one of those names stops the install instead of being overwritten.

After editing, run `./install.sh` from your checkout, then `/reload` in game. It copies your checkout over the installed copy, refreshes the links and restarts the bridge. (`kiln-forever sync` only re-copies the *installed* addon, so it won't pick up your edits.) New files inside the addon load on `/reload`; new addon folders (such as live-update slots) need a full game restart.

Tests:

```bash
cd bridge && npm test                                        # bridge, protocol, crypto, Lua/Node agreement
node tools/make-fixture.mjs                                  # rebuild the committed fixture from bridge/test/fixtures
node tools/record-kiln.mjs /tmp/kiln-record                  # capture the live API (pairs a temporary device, then revokes it)
lua5.1 tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua             # drive the addon headlessly
luajit tools/smoke.lua addon/KilnForever tools/fixtures/snapshot.lua             # same, with signed bit ops
luacheck addon tools                                        # the Lua style CI checks
```

CI runs three jobs on every push to main and every pull request: the bridge tests under Node 22, the addon smoke test under both `lua5.1` and `luajit`, and `luacheck addon tools`. Releases are cut from a `v*` tag after the tag, `bridge/package.json` and the TOC version match.

For a headless Forever client under gamescope, run `kiln-forever run --capture gamescope` (or set `KILN_FOREVER_CAPTURE=gamescope`). That backend reads `${XDG_STATE_HOME:-~/.local/state}/forever-client/session.json`, screenshots with `gamescopectl` and crops the corner with ImageMagick; the normal Hyprland path uses `grim`, trying the game's own `-T` toplevel before the screen region.

`tools/wowstub.lua` stands in for the WoW API. Its widget methods come from the client's own API documentation, so calling a method that doesn't exist fails in tests the way it would in game.

Before changing how the addon and bridge talk, read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [AGENTS.md](AGENTS.md): several things that look like workarounds are deliberate, measured limits of the game client.

## Style

- Lua: tabs. JavaScript: two spaces, ES modules, no dependencies beyond Node itself.
- Text people see (in game, in the CLI, in docs) is plain and specific: say what happened and what to do, without jargon.

## Security

If you find a security problem, such as a way to send commands to someone's agents or read what they're sending, please report it privately through [GitHub's security advisories](https://github.com/cjber/kiln-forever/security/advisories/new) rather than a public issue.
