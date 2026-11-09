# kiln-wow

Kiln is a World of Warcraft: Forever addon plus a small Node bridge that lets you watch and steer your kiln agent sessions from inside the game. It is built from Blizzard's own UI templates, so it looks and plays like the rest of the interface.

## Requirements

- Linux with Hyprland and `grim`. The bridge reads the addon's pixel strip with `grim`.
- `kiln` installed, with `kiln serve` running.
- World of Warcraft: Forever, installed with Battle.net under Proton.
- Node.js 22 or newer.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/cjber/kiln-wow/main/install.sh | bash
```

The installer puts the addon in the game, copies the bridge to `~/.local/share/kiln-wow`, and starts it as the `kiln-wow` user service. The first time, fully quit and restart World of Warcraft: the game only finds new addon folders when it starts. After that, an update only needs `/reload`.

To install from a clone, run `./install.sh` in it. Run the same install command again to update.

## Using it

- `/kiln` opens or closes the window. You can also click the minimap button or use the game menu.
- `/kiln new` starts a thread, `/kiln settings` opens the settings, `/kiln selftest` checks the link step by step.
- `/kiln report` fills the message box with diagnostics for a bug report.
- `kiln-wow status --log` shows what the bridge sees.

## How it works

Addons can't open network connections or read files, so the addon and the bridge talk through what the game does allow. The game sends a small strip of coloured squares in the top-left corner, which the bridge reads with `grim`. The bridge sends snapshots back through load-on-demand slot addons, and signals a new snapshot with large silent sound files. The strip is encrypted and authenticated, so a stream or recording shows only noise. Details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Coding agents should start with [AGENTS.md](AGENTS.md).

## Credits

This is a fork of [t3code-wow](https://github.com/ryanrhughes/t3code-wow) by Ryan Hughes, used under the MIT license.

- [wow-ai](https://github.com/chelinho139/wow-ai) and [wow-forever-codex](https://github.com/0xinuarashi/wow-forever-codex) measured how the Forever client loads files, plays sounds and handles the gamepad. The strip-and-slot approach builds on their work.
- [Bellular](https://www.youtube.com/@BellularGaming) ([@BellularGaming](https://x.com/BellularGaming)) gave the idea of making this an in-game addon instead of a desktop overlay.

## License

[MIT](LICENSE). This is a fan project, not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment. Use it at your own discretion.
