#!/usr/bin/env node
// kiln-forever: install and run the Kiln Forever bridge for World of Warcraft: Forever.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Bridge, STATE_DIR, VERSION } from '../src/bridge.js';
import { CONFIG_DIR, DEFAULT_KILN_URL, pair, unpair, readToken, readDevice, findKilnCli } from '../src/auth.js';
import { findWowInstalls, addonsDir as addonsDirOf, findWowProcess } from '../src/wow.js';
import { ADDON } from '../src/slots.js';
import { addonsHomeFor, installAddons, syncAddon, removeOwnedLinks } from '../src/install.js';
import { StripCapture } from '../src/capture.js';
import { decodeImage } from '../src/codec.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BRIDGE_ROOT = path.resolve(HERE, '..');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');
const DATA_DIR = path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local/share'), 'kiln-forever');
const BIN_LINK = path.join(os.homedir(), '.local/bin/kiln-forever');
const DEFAULT_SLOTS = 1200;

const C = process.stdout.isTTY
  ? { b: (s) => `\x1b[1m${s}\x1b[0m`, g: (s) => `\x1b[32m${s}\x1b[0m`, y: (s) => `\x1b[33m${s}\x1b[0m`, r: (s) => `\x1b[31m${s}\x1b[0m`, d: (s) => `\x1b[2m${s}\x1b[0m` }
  : { b: String, g: String, y: String, r: String, d: String };

function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      if (v !== undefined) out[k] = v;
      else if (argv[i + 1] && !argv[i + 1].startsWith('--')) out[k] = argv[++i];
      else out[k] = true;
    } else out._.push(a);
  }
  return out;
}

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function writeConfig(cfg) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2) + '\n');
}

// The addon ships next to the bridge (repo layout) or inside it (installed layout).
function addonSource() {
  for (const p of [path.join(BRIDGE_ROOT, '..', 'addon', ADDON), path.join(BRIDGE_ROOT, 'addon', ADDON)]) {
    if (fs.existsSync(path.join(p, `${ADDON}.toc`))) return p;
  }
  throw new Error('could not find the addon sources next to the bridge');
}

function resolveWowDir(args, cfg) {
  if (args.wow) {
    const dir = path.resolve(String(args.wow));
    if (fs.existsSync(path.join(dir, '_forever_'))) return path.join(dir, '_forever_');
    return dir;
  }
  if (cfg.wowDir && fs.existsSync(cfg.wowDir)) return cfg.wowDir;
  const { forever, wowOnly, prefixes } = findWowInstalls();
  if (forever.length > 1) console.log(C.y(`Found several WoW: Forever installs, using the first (pick one with --wow):\n  ${forever.join('\n  ')}`));
  if (forever.length) return forever[0];
  const where = '\nIf it\'s somewhere else, pass --wow "/path/to/World of Warcraft".';
  if (wowOnly.length) {
    throw new Error(`found World of Warcraft at ${wowOnly[0]}, but not WoW: Forever. Install Forever from Battle.net (it's a separate game version), launch it once, then run ./install.sh again.${where}`);
  }
  if (prefixes.length) {
    throw new Error(`found Battle.net (${prefixes[0]}) but no World of Warcraft. Install WoW: Forever from Battle.net, launch it once, then run ./install.sh again.${where}`);
  }
  throw new Error(`couldn't find Battle.net. On Omarchy, install it with omarchy-install-gaming-battlenet, install WoW: Forever from it and launch it once, then run ./install.sh again.${where}`);
}

// The bridge runs as a systemd user service. Commands are quiet unless they fail
// (enabling prints "Created symlink …", which isn't news).
function quiet(cmd, args, { warn = true } = {}) {
  const r = spawnSync(cmd, args, { encoding: 'utf8' });
  if (r.status !== 0 && warn) process.stderr.write(r.stderr || `${cmd} ${args.join(' ')} failed\n`);
  return r.status === 0;
}

function bridgeCommand() {
  return [process.execPath, path.join(BRIDGE_ROOT, 'bin', 'kiln-forever.js'), 'run'];
}

const systemd = {
  name: 'kiln-forever.service',
  file: path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'systemd/user', 'kiln-forever.service'),
  kind: 'user service',
  install() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(this.file, [
      '[Unit]',
      'Description=Kiln Forever bridge for World of Warcraft',
      'After=kiln-serve.service graphical-session.target',
      'Wants=kiln-serve.service',
      '',
      '[Service]',
      `ExecStart=${bridgeCommand().join(' ')}`,
      'Restart=always',
      'RestartSec=3',
      `Environment=PATH=${process.env.PATH}`,
      '',
      '[Install]',
      'WantedBy=default.target',
      '',
    ].join('\n'));
    quiet('systemctl', ['--user', 'daemon-reload']);
    quiet('systemctl', ['--user', 'enable', this.name]);
    return quiet('systemctl', ['--user', 'restart', this.name]);
  },
  restart() {
    quiet('systemctl', ['--user', 'restart', this.name]);
  },
  remove() {
    quiet('systemctl', ['--user', 'disable', '--now', this.name], { warn: false });
    fs.rmSync(this.file, { force: true });
    quiet('systemctl', ['--user', 'daemon-reload'], { warn: false });
  },
};

const service = systemd;

function kilnUrl(args, cfg) {
  return String(args.kiln || cfg.kilnUrl || DEFAULT_KILN_URL).replace(/\/+$/, '');
}

// Kiln's phone server answers its root with plain text. Anything else means the
// bridge has nothing to talk to yet.
async function kilnAnswers(baseUrl) {
  try {
    const res = await fetch(new URL('/', baseUrl), { signal: AbortSignal.timeout(3000) });
    await res.text();
    return res.ok;
  } catch {
    return false;
  }
}

// null when it couldn't be read; otherwise whether kiln accepts writes.
async function kilnWriteEnabled(baseUrl) {
  try {
    const token = readToken();
    if (!token) return null;
    const res = await fetch(new URL('/v1/sessions', baseUrl), {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;
    const body = await res.json();
    return body?.write !== false;
  } catch {
    return null;
  }
}

async function cmdInstall(args) {
  const cfg = readConfig();
  const wowDir = resolveWowDir(args, cfg);
  const gameAddons = addonsDirOf(wowDir);
  const baseUrl = kilnUrl(args, cfg);
  console.log(`${C.b('World of Warcraft:')} ${wowDir}`);

  if (!(await kilnAnswers(baseUrl))) {
    throw new Error('kiln\'s phone server is not running: run `kiln setup` (or `kiln serve --local`) first.');
  }
  console.log(`${C.g('✓')} kiln is answering at ${baseUrl}`);

  if (!readToken() || !readDevice()) {
    if (!findKilnCli()) throw new Error('the `kiln` command was not found; install kiln or put it on PATH, then run install again.');
    process.stdout.write('… Pairing with kiln (allow the request that appears there)\r');
    try {
      const paired = await pair({ baseUrl });
      console.log(`${C.g('✓')} Paired with kiln as ${C.b(paired.device?.name || 'kiln-forever')} ${C.d('(revoke with `kiln revoke <device-id>`)')}`);
    } catch (err) {
      throw new Error(`couldn't pair with kiln: ${err.message}\n  Start kiln, then run the install command again.`);
    }
  } else {
    const device = readDevice();
    console.log(`${C.g('✓')} kiln device ready ${C.d(`(${device?.name || 'kiln-forever'})`)}`);
  }

  if ((await kilnWriteEnabled(baseUrl)) === false) {
    console.log(C.y('! Turn on `[phone] write = true` in kiln\'s config.toml so replies, stops and answers work.'));
  }

  const slots = Number(args.slots || cfg.slots || DEFAULT_SLOTS);
  const dataDir = args['data-dir'] ? path.resolve(String(args['data-dir'])) : DATA_DIR;
  // The game only discovers new addon folders and sound files when it starts.
  const freshAddon = !fs.existsSync(path.join(gameAddons, ADDON, `${ADDON}.toc`));
  const result = installAddons({ sourceAddon: addonSource(), dataDir, gameAddons, slots });
  console.log(`${C.g('✓')} Addon, ${slots} live-update slots and signals in ${result.addonsHome} ${C.d(`(${result.made} files written${result.pruned ? `, ${result.pruned} unused signal files removed` : ''})`)}`);
  console.log(`${C.g('✓')} Linked ${result.links.length} folders into ${gameAddons} ${C.d('(addon managers skip symlinks)')}`);

  const { signals: _legacySignals, ...rest } = cfg;
  const next = { ...rest, wowDir, addonsDir: gameAddons, addonsHome: result.addonsHome, slots };
  writeConfig(next);

  if (!args['no-service']) {
    if (!service.install()) {
      console.log(C.r(`✗ The bridge's ${service.kind} didn't start (the error is above). Fix that, then run \`kiln-forever install\` again.`));
      process.exitCode = 1;
      return;
    }
    console.log(`${C.g('✓')} Bridge running as the ${service.name} ${service.kind}`);
  }

  console.log('');
  await firstLaunch({
    restart: freshAddon || result.had < slots || result.bellsMissing,
    running: !!findWowProcess(),
    waiting: !args['no-service'] && process.stdin.isTTY && process.stdout.isTTY,
    since: Date.now(),
  });
}

function readStatus() {
  try {
    return JSON.parse(fs.readFileSync(path.join(STATE_DIR, 'status.json'), 'utf8'));
  } catch {
    return null;
  }
}

// After installing: say exactly what to do in the game, then wait (Enter skips) until
// the addon checks in, so you know it works before you go looking for it.
async function firstLaunch({ restart, running, waiting, since }) {
  let step;
  if (restart) step = running ? 'Quit World of Warcraft completely and start it again, then log in to a character.' : 'Start World of Warcraft: Forever and log in to a character.';
  else step = running ? 'Type /reload in game.' : 'Start World of Warcraft: Forever and log in to a character.';
  console.log(`${C.b('Next:')} ${step}`);
  if (restart && running) console.log(C.d('  The game only finds new addon files when it starts, so a /reload isn\'t enough this time.'));

  let connected = null;
  if (waiting) {
    let skipped = false;
    process.stdin.resume();
    process.stdin.once('data', () => {
      skipped = true;
    });
    let shown = '';
    const until = Date.now() + 20 * 60 * 1000;
    while (!skipped && Date.now() < until) {
      const st = readStatus();
      if (st?.addon && st.addon.lastSeen >= since) {
        connected = st;
        break;
      }
      const msg = st?.wow ? 'World of Warcraft is running. Waiting for you to log in… (Enter to skip)' : 'Waiting for World of Warcraft to start… (Enter to skip)';
      if (msg !== shown) {
        process.stdout.write(`\r\x1b[2K${C.d(msg)}`);
        shown = msg;
      }
      await new Promise((r) => setTimeout(r, 1000));
    }
    process.stdin.pause();
    process.stdout.write('\r\x1b[2K');
    if (connected) {
      // The first hello can arrive before the addon has its link keys; give it a moment.
      for (let i = 0; i < 8 && !readStatus()?.addon?.encrypted; i++) await new Promise((r) => setTimeout(r, 1000));
      const enc = readStatus()?.addon?.encrypted;
      console.log(`${C.g('✓')} Connected: the game and the bridge are talking${enc ? ' over an encrypted link' : ''}.`);
    } else if (!skipped) {
      console.log(C.y('The game hasn\'t checked in yet. Once you\'re in, `kiln-forever status` shows whether it connected.'));
    }
  }
  console.log(`
${C.b('In game')}
  /kiln                     open or close Kiln Forever (or click the Kiln Forever button on the minimap)
  /kiln selftest            check the link step by step if something seems off

${C.b('From here')}
  kiln-forever status       what the bridge sees
  ./install.sh from your clone   update, then /reload in game
  kiln-forever uninstall    remove everything`);
}

function cmdSync(args) {
  const cfg = readConfig();
  const addonsHome = cfg.addonsHome || addonsHomeFor(DATA_DIR);
  const dst = syncAddon(addonSource(), addonsHome);
  console.log(`${C.g('✓')} Addon code copied to ${dst}. Type /reload in game.`);
}

async function cmdRun(args) {
  const cfg = readConfig();
  const addonsHome = cfg.addonsHome || addonsHomeFor(DATA_DIR);
  const capture = { ...(cfg.capture || {}) };
  if (args.capture) capture.backend = String(args.capture);
  else if (!capture.backend && process.env.KILN_FOREVER_CAPTURE) capture.backend = process.env.KILN_FOREVER_CAPTURE;
  const bridge = new Bridge({ addonsDir: addonsHome, config: { ...cfg, capture, verbose: args.verbose || cfg.verbose } });
  const stop = () => {
    bridge.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  await bridge.start();
}

function ago(ms) {
  const s = Math.round(ms / 1000);
  return s < 60 ? `${s}s ago` : s < 3600 ? `${Math.round(s / 60)}m ago` : `${Math.round(s / 3600)}h ago`;
}

function cmdStatus(args) {
  let st;
  try {
    st = JSON.parse(fs.readFileSync(path.join(STATE_DIR, 'status.json'), 'utf8'));
  } catch {
    console.log(C.r('The bridge has not run yet.'), 'Start it with `kiln-forever install` or `kiln-forever run`.');
    process.exitCode = 1;
    return;
  }
  if (args.json) return console.log(JSON.stringify(st, null, 2));
  const age = Date.now() - Date.parse(st.at);
  const alive = age < 10000;
  const ok = (b) => (b ? C.g('●') : C.r('●'));
  console.log(`${ok(alive)} Bridge ${st.version} ${alive ? `running (pid ${st.pid})` : `not running (last seen ${ago(age)})`}`);
  const k = st.kiln || {};
  console.log(`${ok(k.state === 'connected')} kiln: ${k.state || 'unknown'}${k.error ? ` - ${k.error}` : ''} ${C.d(`(${k.host || 'host unknown'}, write ${k.write === false ? 'off' : 'on'})`)}`);
  const device = k.device?.id ? k.device : readDevice();
  console.log(`${ok(!!device?.id)} pairing: ${device?.id ? `${device.id}${device.name ? ` (${device.name})` : ''}` : 'not paired'}`);
  const wow = st.wow || findWowProcess();
  console.log(`${ok(!!wow)} game: ${wow?.pid ? `running (pid ${wow.pid})` : 'not running'}`);
  const cap = st.capture || {};
  const last = cap.lastSeenAt ? `last decoded ${ago(Date.now() - cap.lastSeenAt)}` : 'nothing decoded yet';
  console.log(`${ok(cap.state === 'ok' || cap.state === 'idle')} screen link: ${cap.backend || 'unknown'} (${cap.state || 'unknown'}, ${last})${cap.lastError ? `\n    ${C.y(cap.lastError)}` : ''}`);
  const addon = st.addon;
  if (addon) console.log(`${ok(true)} addon: ${addon.version}, last hello ${ago(Date.now() - addon.lastSeen)}`);
  else console.log(`${ok(false)} addon: not heard from yet ${C.d('(log in, then /kiln)')}`);
  const slots = st.slots || { total: 0, remaining: 0 };
  console.log(`  slots: ${Math.max(0, slots.total - slots.remaining)}/${slots.total} used`);
  if (args.log || args.v) {
    console.log('');
    for (const l of st.log || []) console.log(C.d(l));
  }
}

async function cmdProbe(args) {
  const proc = findWowProcess();
  const cap = new StripCapture({ backend: args.capture || 'auto' });
  console.log(`backend: ${cap.resolveBackend()}; WoW pid: ${proc?.pid ?? 'not running'}`);
  const res = await cap.grab(proc?.pid);
  if (res.status !== 'ok') return console.log(`capture: ${res.status}`);
  const out = path.join(os.tmpdir(), 'kiln-forever-probe.ppm');
  const img = res.image;
  fs.writeFileSync(out, Buffer.concat([Buffer.from(`P6\n${img.width} ${img.height}\n255\n`), Buffer.from(img.data)]));
  let png = out;
  try {
    execFileSync('magick', [out, out.replace(/\.ppm$/, '.png')]);
    png = out.replace(/\.ppm$/, '.png');
  } catch {}
  const dec = decodeImage(img, null);
  console.log(`captured ${img.width}x${img.height} -> ${png}`);
  if (!dec) console.log('no strip visible (open the Kiln Forever window in game, or send something)');
  else if (dec.error) console.log(`strip found but unreadable: ${dec.error} (cell ${dec.geo.cell}px at ${dec.geo.ox},${dec.geo.oy})`);
  else console.log(`strip decoded: seq ${dec.seq}, ${dec.payload.length} bytes, cell ${dec.geo.cell}px at ${dec.geo.ox},${dec.geo.oy}`);
}

async function ask(question) {
  if (!process.stdin.isTTY) return false;
  const rl = (await import('node:readline/promises')).createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question(question);
  rl.close();
  return /^y(es)?$/i.test(answer.trim());
}

// Remove everything install put on this computer, and revoke the bridge's sessions.
async function cmdUninstall(args) {
  const cfg = readConfig();
  if (!args.yes) {
    console.log('This removes Kiln Forever for World of Warcraft: the addon and its update folders, its settings in the game,');
    console.log('the bridge service, its kiln device and its files.');
    if (!(await ask('Remove it? [y/N] '))) {
      console.log(process.stdin.isTTY ? 'Nothing removed.' : 'Nothing removed. Run `kiln-forever uninstall --yes` to remove without asking.');
      return;
    }
  }
  const done = (msg) => console.log(`${C.g('✓')} ${msg}`);
  const warn = (msg) => console.log(`${C.y('!')} ${msg}`);

  if (fs.existsSync(service.file)) {
    service.remove();
    done('Stopped and removed the bridge service');
  }

  let wowDir = cfg.wowDir;
  if (!wowDir) {
    try {
      wowDir = findWowInstalls().forever[0];
    } catch {}
  }
  const gameAddons = cfg.addonsDir || (wowDir && addonsDirOf(wowDir));
  const addonsHome = cfg.addonsHome || addonsHomeFor(DATA_DIR);
  if (gameAddons) {
    const removed = removeOwnedLinks({ addonsHome, gameAddons });
    if (removed.length) done(`Removed ${removed.length} Kiln Forever links from the game's AddOns folder`);
  }
  if (wowDir) {
    // The addon's saved settings (account-wide SavedVariables).
    let removed = 0;
    const accounts = path.join(wowDir, 'WTF', 'Account');
    try {
      for (const acct of fs.readdirSync(accounts)) {
        for (const f of [`${ADDON}.lua`, `${ADDON}.lua.bak`]) {
          const p = path.join(accounts, acct, 'SavedVariables', f);
          if (fs.existsSync(p)) {
            fs.rmSync(p);
            removed++;
          }
        }
      }
    } catch {}
    if (removed) done('Removed its saved settings from the game');
  }

  // Revoke the device the bridge was given, before its token is deleted.
  try {
    const { revoked } = await unpair();
    if (revoked) done('Revoked the bridge\'s kiln device');
  } catch (err) {
    warn(`Couldn't revoke the bridge's kiln device; remove it with \`kiln devices\` (${err.message})`);
  }

  fs.rmSync(DATA_DIR, { recursive: true, force: true });
  fs.rmSync(STATE_DIR, { recursive: true, force: true });
  fs.rmSync(CONFIG_DIR, { recursive: true, force: true });
  done('Removed the bridge\'s files, settings and state');

  try {
    if (fs.lstatSync(BIN_LINK).isSymbolicLink() && fs.readlinkSync(BIN_LINK).startsWith(DATA_DIR)) fs.rmSync(BIN_LINK);
  } catch {}
  done('Removed the kiln-forever command');

  if (findWowProcess()) console.log(`\nWorld of Warcraft is running: ${C.b('/reload')} or restart it to finish unloading Kiln Forever.`);
}

function help() {
  console.log(`${C.b('kiln-forever')} ${VERSION} - Kiln Forever inside World of Warcraft: Forever

  kiln-forever install [--wow DIR] [--slots N] [--no-service]
                 Install the addon and its slots under ~/.local/share, link
                 them into the game and start the bridge service
  kiln-forever status [--log] [--json]
                 Show what the bridge sees
  kiln-forever sync    Re-copy the installed addon (to update, rerun the install command)
  kiln-forever run [--verbose] [--capture hyprland|grim|x11|gamescope]
                 Run the bridge in the foreground (the service runs this)
  kiln-forever probe [--capture BACKEND]
                 Capture the corner of the game window and try to read the strip
  kiln-forever uninstall [--yes]
                 Remove the addon, its links, settings, the service, the
                 bridge's kiln device and its files`);
}

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0];
const commands = { install: cmdInstall, run: cmdRun, status: cmdStatus, sync: cmdSync, probe: cmdProbe, uninstall: cmdUninstall };
if (!cmd || args.help || !commands[cmd]) {
  help();
  if (cmd && !commands[cmd]) process.exitCode = 1;
} else {
  Promise.resolve(commands[cmd](args)).catch((err) => {
    console.error(C.r(`✗ ${err.message}`));
    process.exitCode = 1;
  });
}
