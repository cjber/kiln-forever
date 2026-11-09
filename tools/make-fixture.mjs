// Build tools/fixtures/snapshot.lua from the kiln fixtures in bridge/test/fixtures,
// using the bridge's own snapshot builder and Lua serializer so the fixture keeps
// exactly the shape the bridge publishes. Deterministic: rerunning it rewrites the
// same bytes.
//   node tools/make-fixture.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Bridge } from '../bridge/src/bridge.js';
import { deriveKeys } from '../bridge/src/strip-crypto.js';
import { luaAssignment } from '../bridge/src/luaser.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'tools/fixtures/snapshot.lua');
const fixtures = path.join(root, 'bridge/test/fixtures');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-fixture-'));

const read = (name) => JSON.parse(fs.readFileSync(path.join(fixtures, name), 'utf8'));
const sessions = read('sessions.json');
const directories = read('directories.json');
const views = read('views.json');

const bridge = new Bridge({ addonsDir: tmp, config: {}, log: () => {}, stateDir: tmp });
// A fixed master key, so the fixture's link keys are stable.
bridge.stripKeys = deriveKeys(Buffer.alloc(32, 7));

bridge.kiln = {
  state: 'connected',
  error: null,
  write: sessions.write !== false,
  host: sessions.host,
  sessions: new Map(sessions.sessions.map((row) => [row.id, row])),
  stop() {},
};
bridge.directories = directories;
for (const [id, view] of Object.entries(views)) {
  bridge.views.set(id, { view, fetchedAt: 0, inflight: null, again: false, contentKey: null });
}

// Show the session that is waiting on the player: transcript plus a typed question.
const viewed = sessions.sessions.find((row) => row.activity === 'waiting')?.id
  || sessions.sessions[0]?.id;

bridge.client = {
  session: 'fixture',
  ui: 'fixture',
  seq: 1,
  ackedSeq: -1,
  flags: 'o',
  view: viewed,
  slotNext: 1,
  slotCount: 1200,
  version: '0.2.0',
};

const snap = {
  v: 1,
  gen: 1794225300000,
  now: 1794225300,
  nextSig: 2,
  ack: { ui: 'fixture', seq: 1 },
  key: bridge.stripKeys.hex,
  ...bridge.buildSnapshot(),
};

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, luaAssignment('KilnForever_Inbox', snap));
console.log(`wrote ${path.relative(root, out)}: ${snap.threads.length} sessions, view ${snap.view.id} (${snap.view.msgs.length} messages)`);

bridge.kiln.stop();
fs.rmSync(tmp, { recursive: true, force: true });
