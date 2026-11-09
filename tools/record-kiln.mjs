// Record kiln's live API into a directory, for building fixtures and for looking at
// real shapes without the game.
//
//   node tools/record-kiln.mjs <output directory>
//
// Pairs with the running kiln as a temporary device, writes /v1/sessions,
// /v1/directories and a few /view responses, then revokes the device.

import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_KILN_URL, DEVICE_FILE, TOKEN_FILE, pair, unpair } from '../bridge/src/auth.js';

const out = process.argv[2];
if (!out) {
  console.error('usage: node tools/record-kiln.mjs <output directory>');
  process.exit(1);
}
const baseUrl = process.env.KILN_URL || DEFAULT_KILN_URL;

// Recording must not unpair the bridge that is already installed here: remember its
// files, pair a temporary device, and put them back afterwards.
const saved = {
  token: fs.existsSync(TOKEN_FILE) ? fs.readFileSync(TOKEN_FILE, 'utf8') : null,
  device: fs.existsSync(DEVICE_FILE) ? fs.readFileSync(DEVICE_FILE, 'utf8') : null,
};
function restore() {
  for (const [file, value] of [[TOKEN_FILE, saved.token], [DEVICE_FILE, saved.device]]) {
    if (value === null) fs.rmSync(file, { force: true });
    else fs.writeFileSync(file, value, { mode: 0o600 });
  }
}

const paired = await pair({ baseUrl, name: 'kiln-forever record' });
try {
  const headers = { Authorization: `Bearer ${paired.token}` };
  const get = async (pathname) => {
    const res = await fetch(new URL(pathname, baseUrl), { headers });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`${pathname}: ${body.error || `HTTP ${res.status}`}`);
    return body;
  };

  const sessions = await get('/v1/sessions');
  const directories = await get('/v1/directories');
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'sessions.json'), JSON.stringify(sessions, null, 2) + '\n');
  fs.writeFileSync(path.join(out, 'directories.json'), JSON.stringify(directories, null, 2) + '\n');

  const wanted = (sessions.sessions || [])
    .filter((row) => row.where === 'kiln' || row.activity === 'waiting' || row.activity === 'working')
    .slice(0, 4);
  const views = {};
  for (const row of wanted) {
    views[row.id] = await get(`/v1/sessions/${encodeURIComponent(row.id)}/view`);
  }
  fs.writeFileSync(path.join(out, 'views.json'), JSON.stringify(views, null, 2) + '\n');
  console.log(`wrote ${out}: ${(sessions.sessions || []).length} sessions, ${Object.keys(views).length} views`);
} finally {
  try {
    await unpair({ deviceId: paired.device?.id, baseUrl });
  } finally {
    restore();
  }
}
