// The outbound channel (game -> bridge): screen-capture the top-left corner of the
// game window and decode the addon's pixel strip.
//
// Hyprland (and other wlroots compositors) allow screencopy, so `grim` can read the
// game's pixels on Wayland. Grim can capture the game's own toplevel (`-T`), which
// keeps working while the window is hidden or covered; older grim builds fall back to
// a region capture. X11 sessions use ImageMagick's `import`. Headless Forever clients
// use gamescope, whose screenshot tool writes a PNG the bridge crops with ImageMagick.

import { execFile, spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { decodeImage, parsePPM, CELLS_PER_ROW, MAX_ROWS } from './codec.js';

// A service may start before the session exports WAYLAND_DISPLAY; find the socket.
function captureEnv() {
  if (process.env.WAYLAND_DISPLAY) return process.env;
  const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;
  try {
    const sock = fs.readdirSync(runtime).find((f) => /^wayland-\d+$/.test(f));
    if (sock) return { ...process.env, XDG_RUNTIME_DIR: runtime, WAYLAND_DISPLAY: sock };
  } catch {}
  return process.env;
}

// Read a whole command's stdout. `head` switches to streaming and keeps only the
// start of the stream: a full window is larger than the strip corner needs.
function run(cmd, args, { maxBuffer = 32 * 1024 * 1024, timeout = 4000, env, head = false, keepHeight = 0 } = {}) {
  if (head) return runHead(cmd, args, { timeout, env, keepHeight });
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { encoding: 'buffer', maxBuffer, timeout, env: env || captureEnv() }, (err, stdout, stderr) => {
      if (err) {
        err.stderr = stderr?.toString();
        reject(err);
      } else resolve(stdout);
    });
  });
}

// Only the PPM header and the top rows are buffered; the rest is read and discarded
// so the child can finish without a broken pipe.
function runHead(cmd, args, { timeout = 5000, env, keepHeight = 0 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { env: env || captureEnv(), stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    let have = 0;
    let need = Infinity;
    let stderr = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
    child.stdout.on('data', (chunk) => {
      if (have >= need) return; // drain the rest
      chunks.push(chunk);
      have += chunk.length;
      if (need === Infinity) {
        const n = ppmHeadLength(Buffer.concat(chunks), keepHeight);
        if (n !== null) need = n;
      }
    });
    child.stderr.on('data', (chunk) => {
      if (stderr.length < 500) stderr += chunk.toString();
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      if (signal) return reject(new Error(`${path.basename(cmd)} killed (${signal}) after ${timeout} ms`));
      if (code !== 0) return reject(new Error(`${path.basename(cmd)} exit ${code}: ${stderr.trim()}`));
      const buf = Buffer.concat(chunks);
      resolve(need !== Infinity && need < buf.length ? buf.subarray(0, need) : buf);
    });
  });
}

// Byte length of the PPM header plus `keepHeight` rows, or null until the header is
// complete. Rows keep their full width; the caller crops the width afterwards.
function ppmHeadLength(buf, keepHeight) {
  let pos = 0;
  const tokens = [];
  while (tokens.length < 4) {
    while (pos < buf.length && /\s/.test(String.fromCharCode(buf[pos]))) pos++;
    if (pos >= buf.length) return null;
    if (buf[pos] === 0x23) {
      while (pos < buf.length && buf[pos] !== 0x0a) pos++;
      continue;
    }
    const start = pos;
    while (pos < buf.length && !/\s/.test(String.fromCharCode(buf[pos]))) pos++;
    if (pos >= buf.length) return null;
    tokens.push(buf.toString('latin1', start, pos));
  }
  const width = Number(tokens[1]);
  const height = Number(tokens[2]);
  if (!(width > 0) || !(height > 0)) return null;
  const rows = keepHeight > 0 ? Math.min(height, keepHeight) : height;
  return pos + 1 + width * 3 * rows;
}

// Keep the top-left part of an image, the area the decoder searches.
export function cropImage(img, maxWidth, maxHeight) {
  const rowsAvailable = Math.floor(img.data.length / (img.width * 3));
  const width = Math.min(img.width, maxWidth);
  const height = Math.min(img.height, maxHeight, rowsAvailable);
  if (width === img.width && height === img.height) return img;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y++) {
    const from = y * img.width * 3;
    img.data.copy(data, y * width * 3, from, from + width * 3);
  }
  return { width, height, data };
}

function which(bin) {
  for (const dir of (process.env.PATH || '').split(':')) {
    const p = path.join(dir, bin);
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch {}
  }
  return null;
}

// Command lines, kept separate so tests can check them without running anything.
export function grimToplevelArgs(stableId) {
  return ['-t', 'ppm', '-T', stableId, '-'];
}

export function grimRegionArgs(x, y, width, height) {
  return ['-t', 'ppm', '-g', `${x},${y} ${width}x${height}`, '-'];
}

export function gamescopeScreenshotArgs(file) {
  return ['screenshot', file];
}

export function magickCropArgs(png, width, height) {
  return [png, '-crop', `${width}x${height}+0+0`, '+repage', 'ppm:-'];
}

// Written by forever-core's headless client while a gamescope session is up.
export function foreverSessionFile() {
  const stateHome = process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state');
  return path.join(stateHome, 'forever-client', 'session.json');
}

// ---------------------------------------------------------------------------
// Hyprland IPC (no hyprctl spawn needed)

function hyprSocket() {
  const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;
  const base = path.join(runtime, 'hypr');
  const sig = process.env.HYPRLAND_INSTANCE_SIGNATURE;
  if (sig && fs.existsSync(path.join(base, sig, '.socket.sock'))) return path.join(base, sig, '.socket.sock');
  // Running as a systemd service the variable may be missing: use the newest instance.
  try {
    const dirs = fs
      .readdirSync(base)
      .map((d) => path.join(base, d, '.socket.sock'))
      .filter((p) => fs.existsSync(p))
      .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    return dirs[0] || null;
  } catch {
    return null;
  }
}

function hyprRequest(sock, cmd) {
  return new Promise((resolve, reject) => {
    const c = net.createConnection(sock);
    const chunks = [];
    c.on('connect', () => c.write(cmd));
    c.on('data', (d) => chunks.push(d));
    c.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    c.on('error', reject);
    c.setTimeout(2000, () => {
      c.destroy();
      reject(new Error('hyprland ipc timeout'));
    });
  });
}

async function hyprWindow(pid) {
  const sock = hyprSocket();
  if (!sock) return null;
  const [clients, monitors] = await Promise.all([
    hyprRequest(sock, 'j/clients').then(JSON.parse),
    hyprRequest(sock, 'j/monitors').then(JSON.parse),
  ]);
  const win =
    clients.find((c) => pid && c.pid === pid) ||
    clients.find((c) => c.title === 'World of Warcraft') ||
    clients.find((c) => /^World of Warcraft/.test(c.title || ''));
  if (!win) return { found: false };
  const mon = monitors.find((m) => m.id === win.monitor) || monitors[0];
  const visible =
    !win.hidden &&
    mon &&
    (mon.activeWorkspace?.id === win.workspace?.id || mon.specialWorkspace?.id === win.workspace?.id);
  return {
    found: true,
    visible,
    x: win.at[0],
    y: win.at[1],
    width: win.size[0],
    height: win.size[1],
    scale: mon?.scale || 1,
    stableId: String(win.stableId || win.address || ''),
    address: String(win.address ?? ''),
    focused: undefined,
  };
}

// ---------------------------------------------------------------------------

export class StripCapture {
  constructor({ log = () => {}, backend = 'auto', region = null, exec = run, has = which, sessionFile = null, windowFn = hyprWindow } = {}) {
    this.log = log;
    this.backend = backend && backend !== 'auto' ? backend : (process.env.KILN_FOREVER_CAPTURE || 'auto');
    this.manualRegion = region; // { x, y, width, height } in compositor (logical) coordinates
    this.exec = exec;
    this.has = has;
    this.sessionFile = sessionFile;
    this.hyprWindow = windowFn;
    this.hint = null;
    this.lastError = null;
    this.lastSeenAt = 0;
    this.stats = { captures: 0, decoded: 0, rejected: 0, notVisible: 0 };
    this.lastImage = null;
    this.toplevel = null; // undefined unknown, true/false once probed
  }

  resolveBackend() {
    if (this.backend !== 'auto') return this.backend;
    if (process.env.WAYLAND_DISPLAY || hyprSocket()) {
      if (hyprSocket() && this.has('grim')) return 'hyprland';
      if (this.has('grim')) return 'grim';
    }
    if (process.env.DISPLAY && this.has('import')) return 'x11';
    if (this.has('grim')) return 'grim';
    return 'none';
  }

  // Size of the region to grab, in physical pixels: the largest strip plus slack for
  // window borders and offset search.
  static stripPixels(cell = 4) {
    return { width: CELLS_PER_ROW * cell + 32, height: MAX_ROWS * cell + 32 };
  }

  // Whether this grim can capture a foreign toplevel (`-T`), probed once from its help.
  async toplevelSupported() {
    if (this.toplevel !== null) return this.toplevel;
    try {
      const help = String(await this.exec('grim', ['-h'], {}));
      this.toplevel = help.split('\n').some((line) => line.trimStart().startsWith('-T'));
    } catch {
      this.toplevel = false;
    }
    return this.toplevel;
  }

  async grabGamescope() {
    const file = this.sessionFile || foreverSessionFile();
    let session;
    try {
      session = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (err) {
      throw new Error(`gamescope: couldn't read ${file}: ${err.message}`);
    }
    const socket = session.gamescope_socket;
    if (!socket) throw new Error(`gamescope: ${file} has no gamescope_socket`);
    const px = StripCapture.stripPixels(4);
    const runtime = process.env.XDG_RUNTIME_DIR || os.tmpdir();
    const tmp = path.join(runtime, `kiln-forever-${process.pid}-${Date.now()}.png`);
    const env = { ...captureEnv(), GAMESCOPE_WAYLAND_DISPLAY: String(socket) };
    try {
      await this.exec('gamescopectl', gamescopeScreenshotArgs(tmp), { env, timeout: 5000 });
      await waitForFile(tmp, 5000);
      const magick = this.has('magick') ? 'magick' : this.has('convert') ? 'convert' : 'magick';
      const buf = await this.exec(magick, magickCropArgs(tmp, px.width, px.height), { env, timeout: 5000 });
      return { status: 'ok', image: cropImage(parsePPM(buf), px.width, px.height) };
    } finally {
      fs.rmSync(tmp, { force: true });
    }
  }

  async grab(wowPid) {
    const backend = this.resolveBackend();
    this.stats.captures++;
    if (backend === 'none') throw new Error('no capture backend: install grim (Wayland/wlroots) or ImageMagick (X11)');
    if (backend === 'gamescope') return this.grabGamescope();
    const px = StripCapture.stripPixels(4);
    if (backend === 'hyprland' || backend === 'grim') {
      let region = this.manualRegion;
      let scale = 1;
      if (!region && backend === 'hyprland') {
        const win = await this.hyprWindow(wowPid);
        if (!win?.found) return { status: 'no-window' };
        scale = win.scale;
        // The window's own toplevel capture starts at its top-left and keeps working
        // when the game is hidden or another window covers it.
        if (win.stableId && await this.toplevelSupported()) {
          try {
            const buf = await this.exec('grim', grimToplevelArgs(win.stableId), {
              head: true,
              keepHeight: px.height,
              timeout: 5000,
            });
            return { status: 'ok', image: cropImage(parsePPM(buf), px.width, px.height) };
          } catch (err) {
            this.lastError = `toplevel capture failed, using the screen region: ${err.message}`;
            this.log(this.lastError);
          }
        }
        if (!win.visible) {
          this.stats.notVisible++;
          return { status: 'hidden' };
        }
        region = { x: win.x, y: win.y };
      }
      region = region || { x: 0, y: 0 };
      const w = Math.ceil(px.width / scale);
      const h = Math.ceil(px.height / scale);
      const buf = await this.exec('grim', grimRegionArgs(region.x, region.y, w, h));
      return { status: 'ok', image: cropImage(parsePPM(buf), px.width, px.height) };
    }
    if (backend === 'x11') {
      const r = this.manualRegion || { x: 0, y: 0 };
      const buf = await this.exec('import', [
        '-silent', '-window', 'root',
        '-crop', `${px.width}x${px.height}+${r.x}+${r.y}`,
        '-depth', '8', 'ppm:-',
      ]);
      return { status: 'ok', image: cropImage(parsePPM(buf), px.width, px.height) };
    }
    throw new Error(`unknown capture backend ${backend}`);
  }

  // One capture + decode. Returns { status, frame? }.
  async poll(wowPid) {
    let res;
    try {
      res = await this.grab(wowPid);
    } catch (err) {
      this.lastError = err.message;
      return { status: 'error', error: err.message };
    }
    if (res.status !== 'ok') return res;
    this.lastImage = res.image;
    const out = decodeImage(res.image, this.hint);
    if (!out) return { status: 'empty' };
    this.hint = out.geo;
    if (out.error) {
      this.stats.rejected++;
      return { status: 'rejected', error: out.error };
    }
    this.stats.decoded++;
    this.lastSeenAt = Date.now();
    return { status: 'frame', frame: out };
  }
}

async function waitForFile(file, timeout) {
  const until = Date.now() + timeout;
  for (;;) {
    try {
      if (fs.statSync(file).size > 0) return;
    } catch {}
    if (Date.now() >= until) throw new Error(`gamescope: no screenshot appeared at ${file}`);
    await new Promise((r) => setTimeout(r, 50));
  }
}
