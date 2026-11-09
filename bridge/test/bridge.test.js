import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Bridge, parseFrame, messageId } from '../src/bridge.js';
import { SlotBank } from '../src/slots.js';
import { luaValue } from '../src/luaser.js';
import { markdownToWow, markdownToPlain } from '../src/format.js';
import { RS, US } from '../src/codec.js';
import { seal } from '../src/strip-crypto.js';
import crypto from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(here, 'fixtures', name), 'utf8'));
const sessions = fixture('sessions.json').sessions;
const views = fixture('views.json');
const INPUT = sessions.find((row) => row.title === 'Plan the release');
const WORKING = sessions.find((row) => row.title === 'Fix the build');

let currentKeys = null; // the latest fakeBridge's strip keys: frame() seals with them

const LUA = ['lua5.1', 'luajit', 'lua'].find((bin) => {
  try {
    execFileSync(bin, ['-v'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
});

function tempAddons(slots = 8) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-addons-'));
  fs.mkdirSync(path.join(dir, 'KilnForever'));
  new SlotBank(dir, { slots }).install();
  return dir;
}

function fakeBridge(slots = 8) {
  const dir = tempAddons(slots);
  const b = new Bridge({ addonsDir: dir, config: { slots }, log: () => {}, stateDir: fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-state-')) });
  b.proc = { pid: 1, startTicks: 1 };
  currentKeys = b.stripKeys;
  b.persist = { processKey: '1:1', sigCounter: 1, raised: [], handled: {}, slotGuess: 1, gen: 0, seen: {} };
  const calls = [];
  const view = { abilities: { read: true, stop: true }, prompt: null, items: [], cursor: 'c', reset: true };
  b.kiln = {
    sessions: new Map(),
    state: 'connected',
    error: null,
    write: true,
    host: 'this computer',
    start() {},
    stop() {},
    async directories() {
      return { directories: ['/home/user/src/demo'], agents: ['claude', 'codex', 'opencode', 'pi'] };
    },
    async view(id) {
      calls.push(['view', id]);
      return view;
    },
    async sendMessage(...a) {
      calls.push(['send', ...a]);
      return { delivered: true };
    },
    async newSession(...a) {
      calls.push(['new', ...a]);
      return { terminal: 'kitty-1' };
    },
    async interrupt(...a) {
      calls.push(['interrupt', ...a]);
      return { stopped: true };
    },
    async answerPrompt(...a) {
      calls.push(['answer', ...a]);
      return { answered: true };
    },
  };
  b.directories = { directories: ['/home/user/src/demo'], agents: ['claude', 'codex', 'opencode', 'pi'] };
  b.kiln.sessions.set('claude:t1', {
    id: 'claude:t1',
    agent: 'claude',
    title: 'Fix | the build',
    cwd: '/home/user/src/demo',
    repository: '/home/user/src/demo',
    branch: 'fix/build',
    activity: 'working',
    startedAt: 1794225000000,
    lastActiveAt: 1794225299000,
    where: 'kiln',
    resumable: true,
  });
  return { b, dir, calls, view };
}

function loadSlot(dir, i) {
  const file = path.join(dir, `KilnForever_S${String(i).padStart(3, '0')}`, 'Inbox.lua');
  const out = execFileSync(LUA, ['-e', `dofile(${JSON.stringify(file)}) print(KilnForever_Inbox and KilnForever_Inbox.gen or "nil", KilnForever_Inbox and KilnForever_Inbox.nextSig or "nil", KilnForever_Inbox and KilnForever_Inbox.threads and KilnForever_Inbox.threads[1] and KilnForever_Inbox.threads[1].title or "")`]);
  const [gen, nextSig, title] = out.toString().trim().split('\t');
  return { gen: Number(gen), nextSig: Number(nextSig), title };
}

// Size of the bell file that signal k rings (0 if empty or not created yet).
function rung(dir, k) {
  const file = path.join(dir, 'KilnForever', 'Signals', String(3991 + ((k - 1) % 8)).padStart(5, '0') + '.wav');
  try {
    return fs.statSync(file).size;
  } catch {
    return 0;
  }
}

function plainFrame(seq, records) {
  return { version: 1, seq, payload: Buffer.from(records.map((r) => r.join(US)).join(RS)) };
}

// What the addon draws once it has the keys.
function frame(seq, records) {
  const plain = plainFrame(seq, records).payload;
  return { version: 2, seq, payload: seal(currentKeys, seq, crypto.randomBytes(12), plain) };
}

test('unencrypted frames: the hello is answered, commands are never run', async () => {
  const { b, dir, calls } = fakeBridge();
  b.onFrame(plainFrame(1, [['H', 1, 'sess', 'ui1', 2, 1, 0, 'o', '', '0.2.0'], ['C', 1, 'send', 'claude:t1', 'forged']]));
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(calls.length, 0);
  assert.ok(b.client && !b.client.encrypted, 'hello accepted');
  b.publishNow('test');
  const lua = fs.readFileSync(path.join(dir, 'KilnForever_S001', 'Inbox.lua'), 'latin1');
  assert.match(lua, new RegExp(`key="${b.stripKeys.hex}"`), 'snapshot carries the keys');
  // A forged "encrypted" frame (wrong keys) is dropped entirely.
  const other = { ...frame(2, [['H', 1, 'sess', 'ui1', 2, 1, 0, 'o', '', '0.2.0'], ['C', 2, 'send', 'claude:t1', 'forged']]) };
  other.payload = Buffer.from(other.payload);
  other.payload[20] ^= 0xff;
  b.onFrame(other);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(calls.length, 0);
  assert.equal(b.rejected.forged, 1);
  // The real thing runs.
  b.onFrame(frame(3, [['H', 1, 'sess', 'ui1', 2, 1, 0, 'o', '', '0.2.0'], ['C', 3, 'send', 'claude:t1', 'real']]));
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(calls[0][2], 'real');
  assert.ok(b.client.encrypted);
});

test('parseFrame reads hello and commands', () => {
  const f = parseFrame(Buffer.from(['H', 1, 'sess', 'ui1', 5, 9, 123, 'o', 'claude:t1', '0.2.0'].join(US) + RS + ['C', 3, 'send', 'claude:t1', 'hi there'].join(US)));
  assert.equal(f.hello.slot, 5);
  assert.equal(f.hello.sig, 9);
  assert.equal(f.hello.view, 'claude:t1');
  assert.deepEqual(f.commands[0], { id: 3, verb: 'send', args: ['claude:t1', 'hi there'] });
});

test('publish writes the next slots and bootstrap slots, then raises one signal', () => {
  const { b, dir } = fakeBridge();
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 2, 1, 0, 'o', '', '0.2.0']]));
  assert.ok(b.publishNow());
  const s2 = loadSlot(dir, 2);
  const s1 = loadSlot(dir, 1);
  assert.equal(s2.nextSig, 2);
  assert.equal(s1.gen, s2.gen);
  assert.equal(s2.title, 'Fix || the build', 'pipes are escaped for WoW');
  assert.ok(rung(dir, 1) > 174762, 'bell 1 rung with a sound too big for the client to cache');
  assert.equal(rung(dir, 2), 0);
  assert.equal(b.client.slotNext, 3, 'predicts the addon loads one slot');
  // Nothing changed: no publish.
  assert.equal(b.publishNow(), false);
  b.stop();
});

test('commands run once, in order, and results are published', async () => {
  const { b, dir, calls } = fakeBridge();
  const id = 'claude:t1';
  const f = frame(2, [
    ['H', 1, 'sess', 'ui1', 1, 1, 0, 'o', '', '0.2.0'],
    ['C', 1, 'send', id, 'hello'],
    ['C', 2, 'new', 'claude', '/home/user/src/demo', 'start it'],
    ['C', 3, 'stop', id],
    ['C', 4, 'answer', id, 'prompt-7', '2', 'my text'],
  ]);
  b.onFrame(f);
  b.onFrame(f); // seen again: not re-run
  await new Promise((r) => setTimeout(r, 20));
  assert.deepEqual(calls.map((c) => c[0]), ['send', 'new', 'interrupt', 'answer']);
  assert.equal(calls[0][1], id);
  assert.equal(calls[0][2], 'hello');
  assert.match(calls[0][3], /^kf-1-/);
  assert.equal(calls[0][3], messageId(id, 1));
  assert.deepEqual(calls[1].slice(1), ['claude', '/home/user/src/demo', 'start it']);
  assert.deepEqual(calls[3].slice(1), [id, 'prompt-7', 2, 'my text']);
  b.publishNow();
  const lua = fs.readFileSync(path.join(dir, 'KilnForever_S001', 'Inbox.lua'), 'latin1');
  assert.match(lua, /results=\{\{id=1,ok=true,msg="Sent"\},\{id=2,ok=true,msg="Started in kitty-1"\},\{id=3,ok=true,msg="Stopped"\},\{id=4,ok=true,msg="Answered"\}/);
  assert.match(lua, /ack=\{ui="ui1",seq=2\}/);
  b.stop();
});

test('a queued message waits in kiln and says why', async () => {
  const { b } = fakeBridge();
  b.kiln.sendMessage = async () => ({ delivered: false, reason: 'kiln is busy' });
  await b.runCommand({ id: 9, verb: 'send', args: ['claude:t1', 'hello'] });
  assert.deepEqual(b.results.at(-1), { id: 9, ok: true, msg: 'Queued: kiln is busy' });
});

test('a prompt that changed under us refetches the view and says so', async () => {
  const { b, calls } = fakeBridge();
  b.kiln.answerPrompt = async () => {
    const err = new Error('the menu changed');
    err.status = 409;
    throw err;
  };
  await b.runCommand({ id: 10, verb: 'answer', args: ['claude:t1', 'prompt-7', '2'] });
  await new Promise((r) => setTimeout(r, 30));
  const result = b.results.at(-1);
  assert.equal(result.id, 10);
  assert.equal(result.ok, false);
  assert.equal(result.msg, 'The menu changed');
  assert.ok(calls.some((c) => c[0] === 'view' && c[1] === 'claude:t1'), 'view was fetched again');
});

test('read records when the player looked at a session', async () => {
  const { b } = fakeBridge();
  await b.runCommand({ id: 11, verb: 'read', args: ['claude:t1'] });
  assert.equal(typeof b.persist.seen['claude:t1'], 'number');
  assert.equal(b.results.length, 0, 'read is silent');
});

test('the snapshot carries kiln state, directories, agents and the viewed session', () => {
  const { b } = fakeBridge();
  b.client = { ui: 'ui1', view: INPUT.id };
  b.kiln.sessions = new Map(sessions.map((row) => [row.id, row]));
  b.views.set(INPUT.id, { view: views[INPUT.id], fetchedAt: Date.now(), inflight: null, again: false });
  const snap = b.buildSnapshot();
  assert.equal(snap.bridge.kiln, 'connected');
  assert.equal(snap.bridge.write, true);
  assert.equal(snap.bridge.host, 'this computer');
  assert.deepEqual(snap.agents, ['claude', 'codex', 'opencode', 'pi']);
  assert.deepEqual(snap.projects.find((p) => p.id === '/home/user/src/demo'), { id: '/home/user/src/demo', name: 'demo', act: true });
  const input = snap.threads.find((t) => t.id === INPUT.id);
  assert.equal(input.s, 'input');
  assert.equal(input.un, true);
  assert.equal(input.m, 'claude');
  assert.equal(input.can, 'ra');
  assert.equal(snap.threads.find((t) => t.id === WORKING.id).s, 'working');
  assert.equal(snap.view.id, INPUT.id);
  assert.deepEqual(snap.view.msgs.map((m) => m.r), ['user', 'tool', 'assistant']);
  assert.match(snap.view.msgs[1].t, /npm test \(failed\)/);
  assert.equal(snap.view.pending.id, 'prompt-7');
  assert.equal(snap.view.pending.questions[0].opts[1].t, 'inline');
});

test('a reload (new ui token) resets the slot pointer; stale beacons do not', () => {
  const { b } = fakeBridge();
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 6, 4, 0, 'o', '', '0.2.0']]));
  assert.equal(b.client.slotNext, 6);
  assert.equal(b.persist.sigCounter, 4);
  b.publishNow('test');
  assert.equal(b.client.slotNext, 7);
  // An old frame still on screen (gen older than our publish) must not rewind us.
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 6, 4, 0, 'o', '', '0.2.0']]));
  assert.equal(b.client.slotNext, 7);
  // /reload: new ui, addon bootstrapped slot 1, now at 2.
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui2', 2, 5, b.lastGen, 'o', '', '0.2.0']]));
  assert.equal(b.client.slotNext, 2);
  b.stop();
});

test('an addon waiting on a stale signal gets that signal raised too', () => {
  const { b, dir } = fakeBridge();
  b.persist.sigCounter = 9;
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 2, 4, 0, 'o', '', '0.2.0']]));
  b.persist.sigCounter = 9; // e.g. restored from a restarted bridge
  b.client.slotNext = 2;
  b.publishNow('test');
  assert.ok(rung(dir, 4) > 0, 'bell the addon listens for is rung');
  assert.ok(rung(dir, 9) > 0);
  assert.equal(loadSlot(dir, 2).nextSig, 10);
  b.stop();
});

test('signals are never skipped, and never rung ahead of our counter', () => {
  const { b, dir } = fakeBridge();
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 2, 5, 0, 'o', '', '0.2.0']]));
  b.persist.sigCounter = 5;
  b.client.pollSig = 8; // an addon that ran ahead (bells it listens to would alias rung ones)
  b.publishNow('test');
  assert.ok(rung(dir, 5) > 0, 'our next bell rung');
  for (const k of [6, 7, 8]) assert.equal(rung(dir, k), 0, `bell ${k} not rung ahead`);
  assert.equal(b.persist.sigCounter, 6);
  b.stop();
});

test('a drifted slot prediction still covers the slot the addon will load', () => {
  const { b, dir } = fakeBridge(120);
  b.onFrame(frame(1, [['H', 1, 'sess', 'ui1', 40, 5, 0, 'o', '', '0.2.0']]));
  b.client.slotNext = 101; // we kept predicting while the game didn't load anything
  b.publishNow('test');
  const gen = loadSlot(dir, 40).gen;
  assert.ok(gen > 0, 'confirmed slot written');
  assert.equal(loadSlot(dir, 70).gen, gen);
  assert.equal(loadSlot(dir, 105).gen, gen);
  b.stop();
});

test('bells rotate: ringing k empties the bell four behind it', () => {
  const dir = tempAddons(2);
  const bank = new SlotBank(dir, { slots: 2 });
  for (let k = 1; k <= 12; k++) bank.raise(k);
  // 9..12 rung (the addon's look-ahead window), 5..8 emptied again.
  for (const k of [9, 10, 11, 12]) assert.ok(rung(dir, k) > 0, `bell ${k}`);
  for (const k of [13, 14, 15, 16]) assert.equal(rung(dir, k), 0, `bell ${k} (same files as 5..8)`);
  bank.prepareBells();
  assert.ok(fs.statSync(path.join(dir, 'KilnForever', 'Signals', '03999.wav')).size > 174762, 'self-test control is long');
  assert.equal(fs.statSync(path.join(dir, 'KilnForever', 'Signals', '04000.wav')).size, 0);
  bank.resetSignals();
  for (let k = 1; k <= 8; k++) assert.equal(rung(dir, k), 0);
});

test('lua serializer escapes strings and keeps utf-8', () => {
  const s = luaValue({ a: 'x"y\\z\n\u0001', b: ['é', 1.5, true], 'not ident': 1, end: 2 });
  const file = path.join(os.tmpdir(), `kiln-ser-${process.pid}.lua`);
  fs.writeFileSync(file, Buffer.from(`local t = ${s}; io.write(t.a, "|", t.b[1], "|", t["not ident"], "|", t["end"])`, 'latin1'));
  const out = execFileSync(LUA, [file]);
  fs.rmSync(file);
  assert.equal(out.toString('utf8'), 'x"y\\z\n\u0001|é|1|2');
});

test('markdown formatting', () => {
  const w = markdownToWow('# Title\n- item with `code` and **bold** | pipe\n```\nfn()\n```');
  assert.match(w, /\|cffffd100Title\|r/);
  assert.match(w, /•/);
  assert.match(w, /\|\| pipe/);
  assert.match(w, /fn\(\)/);
  assert.equal(markdownToPlain('**Done**: see [docs](http://x)'), 'Done : see docs');
});

test('pacing: fast while reading, patient otherwise, reserve kept for alerts', () => {
  const { b } = fakeBridge(600);
  const hello = (flags, seq = 1) => frame(seq, [['H', 1, 'sess', 'ui1', 2, 1, 0, flags, 'claude:t1', '0.2.0', '600']]);
  b.onFrame(hello('oa'));
  b.publishNow('test'); // ack the hello
  b.lastPublishAt = Date.now();
  b.dirty = { important: false, minor: false, view: true };
  assert.ok(b.nextPublishDelay() <= 1500, 'reading: new reply text within 1.5s');
  b.client.flags = 'o';
  assert.ok(b.nextPublishDelay() >= 4500, 'window open but idle: ~5s');
  b.dirty = { important: false, minor: true, view: false };
  b.client.flags = '';
  assert.ok(b.nextPublishDelay() >= 55000, 'window closed: activity churn waits ~a minute');
  b.dirty = { important: true, minor: false, view: false };
  assert.ok(b.nextPublishDelay() <= 3000, 'window closed: a session finishing still goes within 3s');
  // Low on slots: intervals stretch; at the reserve only alerts go.
  b.client.slotNext = 560; // 41 left of 600
  b.dirty = { important: false, minor: false, view: true };
  b.client.flags = 'oa';
  assert.ok(b.nextPublishDelay() >= 3500, 'scarce: reading updates stretch');
  b.client.slotNext = 590; // 11 left
  assert.equal(b.nextPublishDelay(), null, 'reserve: no view updates');
  b.dirty = { important: true, minor: false, view: false };
  assert.ok(b.nextPublishDelay() !== null, 'reserve: alerts still go');
  b.client.seq = 99; // an unacknowledged command
  assert.ok(b.nextPublishDelay() <= 400, 'acks always go right away');
  b.stop();
});

test('slot manifests are identical and keep the live data out of addon-manager fingerprints', () => {
  const dir = tempAddons(3);
  const read = (i, f) => fs.readFileSync(path.join(dir, `KilnForever_S00${i}`, f), 'utf8');
  assert.equal(read(1, 'KilnForever_S001.toc'), read(3, 'KilnForever_S003.toc'));
  assert.doesNotMatch(read(1, 'KilnForever_S001.toc'), /Dependencies|Inbox\.lua/);
  // WowUp/CurseForge follow only self-closing <Script file="..."/> includes.
  const xml = read(1, 'Slot.xml');
  assert.match(xml, /<Script file="Inbox\.lua"><\/Script>/);
  assert.doesNotMatch(xml, /<(?:Include|Script)\s+file=["']((?:(?<!\.\.).)+)["']\s*\/>/is);
});

test('message ids are stable per command and safe for kiln', () => {
  assert.equal(messageId('claude:0b7c', 12), messageId('claude:0b7c', 12));
  assert.notEqual(messageId('claude:0b7c', 12), messageId('claude:0b7c', 13));
  assert.match(messageId('claude:0b7c', 1), /^[A-Za-z0-9-]{8,64}$/);
  assert.match(messageId('a', 1), /^[A-Za-z0-9-]{8,64}$/);
});
