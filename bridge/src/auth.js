// Pairing with kiln. The bridge is one device in kiln's phone API: `kiln pair`
// prints a one-time code, POST /v1/pair trades it for a token, and the token and
// device id stay under ~/.config/kiln-forever (0600). `kiln revoke` removes it.

import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const CONFIG_DIR = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'kiln-forever');
export const TOKEN_FILE = path.join(CONFIG_DIR, 'token');
export const DEVICE_FILE = path.join(CONFIG_DIR, 'device.json');
export const DEFAULT_KILN_URL = 'http://127.0.0.1:7437';

export function findKilnCli() {
  const candidates = [
    process.env.KILN_CLI,
    path.join(os.homedir(), '.local/bin/kiln'),
    path.join(os.homedir(), 'go/bin/kiln'),
    '/usr/bin/kiln',
    '/usr/local/bin/kiln',
  ];
  for (const c of candidates) if (c && fs.existsSync(c)) return c;
  for (const dir of (process.env.PATH || '').split(':')) {
    const p = path.join(dir, 'kiln');
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function writePrivate(file, value) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  fs.writeFileSync(file, value, { mode: 0o600 });
  try {
    fs.chmodSync(file, 0o600);
  } catch {}
}

export function readToken() {
  if (process.env.KILN_FOREVER_TOKEN) return process.env.KILN_FOREVER_TOKEN;
  try {
    return fs.readFileSync(TOKEN_FILE, 'utf8').trim() || null;
  } catch {
    return null;
  }
}

export function readDevice() {
  try {
    return JSON.parse(fs.readFileSync(DEVICE_FILE, 'utf8'));
  } catch {
    return null;
  }
}

function run(cli, args, timeout = 120000) {
  return new Promise((resolve, reject) => {
    execFile(cli, args, { timeout, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(`\`${path.basename(cli)} ${args.join(' ')}\` failed: ${(stderr || err.message).trim()}`));
        return;
      }
      resolve(String(stdout || ''));
    });
  });
}

function pairingCode(stdout) {
  for (const line of String(stdout).split('\n')) {
    const text = line.trim();
    if (!text.startsWith('kiln://pair')) continue;
    try {
      const code = new URL(text).searchParams.get('code');
      if (code) return code;
    } catch {}
  }
  return null;
}

// Runs `kiln pair`, trades its code for a device token, and saves both. Returns
// { device, token, host } from kiln, plus the code that was used.
export async function pair({ name = 'kiln-forever', baseUrl = DEFAULT_KILN_URL, cli = findKilnCli() } = {}) {
  if (!cli) throw new Error('could not find the `kiln` command; install kiln or put it on PATH');
  const stdout = await run(cli, ['pair', 'https://localhost']);
  const code = pairingCode(stdout);
  if (!code) throw new Error('`kiln pair` printed no pairing code');
  const res = await fetch(new URL('/v1/pair', baseUrl), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, name }),
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {}
  if (!res.ok) throw new Error(`kiln pairing failed: ${body?.error || `HTTP ${res.status}`}`);
  if (!body?.token) throw new Error('kiln pairing returned no token');
  writePrivate(TOKEN_FILE, body.token);
  writePrivate(DEVICE_FILE, JSON.stringify({
    id: body.device?.id,
    name: body.device?.name || name,
    createdAt: body.device?.createdAt,
    host: body.host,
  }, null, 2) + '\n');
  return { ...body, code };
}

// Revokes this bridge's device (or the given one) and deletes its files.
export async function unpair({ deviceId, cli = findKilnCli() } = {}) {
  const device = readDevice();
  const id = deviceId || device?.id;
  let revoked = false;
  if (id) {
    if (!cli) throw new Error('could not find the `kiln` command to revoke the bridge device');
    await run(cli, ['revoke', String(id)], 60000);
    revoked = true;
  }
  fs.rmSync(TOKEN_FILE, { force: true });
  fs.rmSync(DEVICE_FILE, { force: true });
  return { id, revoked };
}
