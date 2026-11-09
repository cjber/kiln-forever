// The bridge: watches the addon's pixel strip, keeps the game's live-update slots
// fed with a snapshot of kiln, and runs the addon's commands against kiln's phone API.
//
// Protocol (see docs/ARCHITECTURE.md):
//   game -> bridge   pixel frame: records split by RS, fields by US
//       H  proto session ui slot sig gen flags view version     (always first)
//       C  id verb args...                                      (pending commands)
//   bridge -> game   KilnForever_Inbox = { gen, nextSig, ack = { ui, seq }, threads, view, ... }
//                    written into the next slots the addon will load, then signal
//                    `nextSig - 1` is raised so the addon loads exactly one slot.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { RS, US } from './codec.js';
import { StripCapture } from './capture.js';
import { SlotBank } from './slots.js';
import { KilnClient, DEFAULT_BASE_URL } from './kiln.js';
import { readDevice } from './auth.js';
import { findWowProcess, processKey } from './wow.js';
import { markdownToWow, escapeWow } from './format.js';
import * as model from './model.js';
import { loadOrCreateKey, deriveKeys, open as openSealed, ENCRYPTED_VERSION } from './strip-crypto.js';

export const VERSION = '0.1.0';
export const STATE_DIR = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'kiln-forever');

const STATUS_ORDER = { input: 0, working: 1, open: 2, done: 3 };

// A stable id for a message command, so a retry of the same command is the same
// message in kiln. kiln accepts [A-Za-z0-9-]{8,64}.
export function messageId(sessionId, commandId) {
  const clean = (String(sessionId).replace(/[^A-Za-z0-9-]/g, '') || 'session').slice(0, 24).padEnd(6, '0');
  return `kf-${commandId}-${clean}`.slice(0, 64);
}

export function parseFrame(payload) {
  const records = payload.toString('utf8').split(RS).map((r) => r.split(US));
  const out = { hello: null, commands: [] };
  for (const f of records) {
    if (f[0] === 'H' && !out.hello) {
      out.hello = {
        proto: Number(f[1]),
        session: f[2] || '',
        ui: f[3] || '',
        slot: Number(f[4]) || 1,
        sig: Number(f[5]) || 1,
        gen: Number(f[6]) || 0,
        flags: f[7] || '',
        view: f[8] || '',
        version: f[9] || '',
        slots: Number(f[10]) || 0,
      };
    } else if (f[0] === 'C') {
      out.commands.push({ id: Number(f[1]), verb: f[2], args: f.slice(3) });
    }
  }
  return out;
}

function formatMessage(msg) {
  if (msg.r === 'assistant') return { ...msg, t: markdownToWow(msg.t, { maxChars: 4000 }) };
  if (msg.r === 'user') return { ...msg, t: markdownToWow(msg.t, { maxChars: 1500 }) };
  return { ...msg, t: escapeWow(msg.t) };
}

export class Bridge {
  constructor({ addonsDir, config = {}, log = console.log, stateDir = STATE_DIR }) {
    this.addonsDir = addonsDir;
    this.config = config;
    this.log = (...a) => {
      const line = `[${new Date().toISOString().slice(11, 19)}] ${a.join(' ')}`;
      this.logs.push(line);
      if (this.logs.length > 200) this.logs.shift();
      log(line);
    };
    this.logs = [];
    this.bank = new SlotBank(addonsDir, { slots: config.slots || 1200 });
    const installed = this.bank.installedSlotCount();
    if (installed > 0) this.bank.slots = installed;
    this.capture = new StripCapture({ log: this.log, backend: config.capture?.backend || 'auto', region: config.capture?.region || null });
    this.kiln = new KilnClient({
      baseUrl: config.kilnUrl || DEFAULT_BASE_URL,
      log: this.log,
    });
    this.stateDir = stateDir;
    this.stateFile = path.join(stateDir, 'state.json');
    this.statusFile = path.join(stateDir, 'status.json');
    this.persist = this.loadState();
    // Keys for the encrypted strip; the addon gets them in every snapshot.
    this.stripKeys = deriveKeys(loadOrCreateKey(stateDir));
    this.rejected = { forged: 0, plainCommands: 0, loggedAt: 0 };
    this.client = null; // what we know about the addon
    this.proc = null;
    this.views = new Map(); // sessionId -> { view, fetchedAt, inflight, again, contentKey }
    this.directories = { directories: [], agents: [] };
    this.dirFetchedAt = 0;
    this.device = readDevice();
    this.results = [];
    this.lastPublishAt = 0;
    this.lastGen = this.persist.gen || 0;
    this.lastDigest = null;
    this.dirty = { important: false, minor: false, view: false };
    this.publishTimer = null;
    this.stopped = false;
    this.captureState = 'starting';
  }

  loadState() {
    try {
      return JSON.parse(fs.readFileSync(this.stateFile, 'utf8'));
    } catch {
      return { processKey: null, sigCounter: 1, raised: [], handled: {}, slotGuess: 1, gen: 0, seen: {} };
    }
  }

  saveState() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      fs.mkdirSync(this.stateDir, { recursive: true });
      const tmp = this.stateFile + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(this.persist));
      fs.renameSync(tmp, this.stateFile);
    }, 250);
  }

  // ---------------------------------------------------------------------------

  async start() {
    this.log(`kiln-forever bridge ${VERSION}; addons: ${this.addonsDir}; slots: ${this.bank.slots}`);
    try {
      this.bank.prepareBells();
    } catch (err) {
      this.log(`couldn't prepare the update bells: ${err.message}`);
    }
    this.log(`capture: ${this.capture.resolveBackend()}`);
    this.kiln.on('state', (s, e) => {
      this.log(`kiln: ${s}${e ? ` (${e})` : ''}`);
      if (s === 'connected') this.loadDirectories();
      this.markDirty('important');
    });
    this.kiln.on('change', (ev) => this.onKilnChange(ev));
    this.kiln.start();
    this.checkProcess();
    this.procTimer = setInterval(() => this.checkProcess(), 4000);
    this.statusTimer = setInterval(() => this.writeStatus(), 3000);
    this.dirTimer = setInterval(() => this.loadDirectories(), 300000);
    this.captureLoop();
  }

  stop() {
    this.stopped = true;
    clearInterval(this.procTimer);
    clearInterval(this.statusTimer);
    clearInterval(this.dirTimer);
    clearTimeout(this.publishTimer);
    this.kiln.stop();
  }

  async loadDirectories() {
    try {
      const data = await this.kiln.directories();
      if (data && Array.isArray(data.directories)) {
        this.directories = { directories: data.directories, agents: Array.isArray(data.agents) ? data.agents : [] };
        this.dirFetchedAt = Date.now();
        this.markDirty('minor');
      }
    } catch (err) {
      this.log(`couldn't read kiln's directories: ${err.message}`);
    }
  }

  checkProcess() {
    const proc = findWowProcess();
    const key = processKey(proc);
    const was = this.proc;
    this.proc = proc;
    if (key && key !== this.persist.processKey) {
      // A new client process: its sound cache is empty, so every signal file is
      // reusable. Reset them and start counting again.
      this.log(`WoW client started (pid ${proc.pid}); resetting live-update signals`);
      this.bank.resetSignals();
      this.persist.processKey = key;
      this.persist.sigCounter = 1;
      this.persist.raised = [];
      this.persist.slotGuess = 1;
      this.client = null;
      this.saveState();
      this.publishNow('client start');
    } else if (!proc && was) {
      this.log('WoW client exited');
      this.client = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Capture loop

  async captureLoop() {
    while (!this.stopped) {
      let delay = 400;
      if (!this.proc) {
        this.captureState = 'no-client';
        delay = 2000;
      } else {
        const res = await this.capture.poll(this.proc.pid);
        if (res.status === 'frame') {
          this.captureState = 'ok';
          this.onFrame(res.frame);
          delay = 150;
        } else {
          this.captureState = res.status === 'empty' ? (this.client ? 'idle' : 'waiting') : res.status;
          if (res.status === 'error' && this.capture.stats.captures % 50 === 1) this.log(`capture: ${res.error}`);
          if (res.status === 'hidden' || res.status === 'no-window') delay = 1000;
          if (Date.now() - this.capture.lastSeenAt < 4000) delay = 150;
          else if (this.client?.flags.includes('o') && res.status === 'empty') delay = 200;
          else if (this.client && res.status === 'empty') delay = 700; // window closed: nothing urgent
        }
      }
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  onFrame(frame) {
    // Encrypted frames must authenticate. A plaintext frame is only a bare hello from
    // an addon that doesn't have our keys yet; we answer it (the snapshot carries the
    // keys) but never run commands from it.
    let payload = frame.payload;
    const sealed = frame.version === ENCRYPTED_VERSION;
    if (sealed) {
      payload = openSealed(this.stripKeys, frame.seq, frame.payload);
      if (!payload) {
        this.rejected.forged++;
        this.noteRejected('ignored a strip frame that failed authentication (an old key? the addon fetches the current one)');
        return;
      }
    }
    const { hello, commands } = parseFrame(payload);
    if (!hello || hello.proto !== 1) return;
    if (!sealed && commands.length) {
      this.rejected.plainCommands += commands.length;
      this.noteRejected(`ignored ${commands.length} unencrypted command(s); the addon resends them once it has the keys`);
    }
    let c = this.client;
    if (!c || c.ui !== hello.ui || c.session !== hello.session) {
      this.log(`addon connected (ui ${hello.ui}, slot ${hello.slot}, signal ${hello.sig}, addon ${hello.version})`);
      c = this.client = { session: hello.session, ui: hello.ui, ackedSeq: -1, flags: '', view: '' };
      c.slotNext = hello.slot;
      this.persist.sigCounter = Math.max(this.persist.sigCounter, hello.sig);
      this.markDirty('important');
    } else if (hello.gen >= this.lastGen) {
      // The addon has applied our latest publish, so its pointers are authoritative.
      c.slotNext = hello.slot;
      if (hello.sig > this.persist.sigCounter) this.persist.sigCounter = hello.sig;
    }
    c.encrypted = sealed;
    if (c.flags !== hello.flags) {
      c.flags = hello.flags;
      this.markDirty('minor');
    }
    if (hello.slots) c.slotCount = hello.slots;
    if (c.view !== hello.view) {
      c.view = hello.view;
      if (c.view) this.refreshView(c.view, true);
      this.markDirty('view');
    }
    c.seq = frame.seq;
    c.pollSig = hello.sig;
    // Where the addon really is: it hasn't loaded past this slot yet.
    c.confirmedSlot = hello.slot;
    c.confirmedAt = Date.now();
    this.persist.confirmedSlot = hello.slot;
    c.version = hello.version;
    c.lastSeen = Date.now();
    this.persist.slotGuess = c.slotNext;

    const handled = this.persist.handled[c.session] || 0;
    const fresh = (sealed ? commands : []).filter((cmd) => cmd.id > handled).sort((a, b) => a.id - b.id);
    if (fresh.length) {
      this.persist.handled[c.session] = fresh.at(-1).id;
      this.saveState();
      for (const cmd of fresh) this.runCommand(cmd);
    }
    if (c.ackedSeq !== frame.seq) this.schedulePublish();
  }

  noteRejected(msg) {
    if (Date.now() - this.rejected.loggedAt < 30000) return;
    this.rejected.loggedAt = Date.now();
    this.log(msg);
  }

  // ---------------------------------------------------------------------------
  // Commands from the game

  async runCommand(cmd) {
    const [a0, a1, a2, a3] = cmd.args;
    this.log(`command ${cmd.id}: ${cmd.verb} ${cmd.verb === 'send' || cmd.verb === 'new' ? a0 : cmd.args.join(' ').slice(0, 80)}`);
    let ok = true;
    let msg = null;
    try {
      switch (cmd.verb) {
        case 'send': {
          const res = await this.kiln.sendMessage(a0, a1, messageId(a0, cmd.id));
          if (res && res.delivered === false) msg = `Queued${res.reason ? `: ${res.reason}` : ''}`;
          else msg = 'Sent';
          break;
        }
        case 'new': {
          const res = await this.kiln.newSession(a0, a1, a2 || '');
          msg = res?.terminal ? `Started in ${res.terminal}` : 'Started';
          break;
        }
        case 'stop':
          await this.kiln.interrupt(a0);
          msg = 'Stopped';
          break;
        case 'answer':
          try {
            await this.kiln.answerPrompt(a0, a1, Number(a2), a3 || undefined);
            msg = 'Answered';
          } catch (err) {
            if (err.status !== 409) throw err;
            this.refreshView(a0, true);
            ok = false;
            msg = 'The menu changed';
          }
          break;
        case 'read':
          this.persist.seen = this.persist.seen || {};
          this.persist.seen[a0] = Date.now();
          this.saveState();
          ok = null; // silent
          break;
        case 'ping':
          ok = null;
          break;
        default:
          throw new Error(`unknown command ${cmd.verb}`);
      }
    } catch (err) {
      ok = false;
      msg = String(err.message || 'failed').split('\n')[0].slice(0, 200);
      this.log(`command ${cmd.id} failed: ${err.message}`);
    }
    if (ok !== null) this.results.push({ id: cmd.id, ok, msg: msg ? escapeWow(msg) : undefined });
    if (this.results.length > 12) this.results.splice(0, this.results.length - 12);
    this.markDirty('important');
  }

  // ---------------------------------------------------------------------------
  // Session detail

  // Only the viewed session and sessions waiting on the player need a view: the
  // first for the transcript, the others so the tracker can show their question.
  refreshView(id, force = false) {
    if (!id) return null;
    let v = this.views.get(id);
    if (!v) {
      v = { view: null, fetchedAt: 0, inflight: null, again: false, contentKey: null };
      this.views.set(id, v);
    }
    const minGap = id === this.client?.view ? 1200 : 5000;
    if (v.inflight) {
      v.again = true;
      return v.inflight;
    }
    const wait = force ? 0 : Math.max(0, minGap - (Date.now() - v.fetchedAt));
    v.inflight = new Promise((r) => setTimeout(r, wait))
      .then(() => this.kiln.view(id))
      .then((data) => {
        const prev = v.contentKey;
        v.view = data;
        v.fetchedAt = Date.now();
        const items = data.items || [];
        const last = items.at(-1);
        // New text, a new question or a new ability reason is worth a quicker update;
        // a new tool line alone can wait for the slower pace.
        v.contentKey = [items.length, last?.id, data.prompt?.key, data.abilities?.reply || ''].join('|');
        if (id === this.client?.view) this.markDirty(v.contentKey !== prev ? 'view' : 'minor');
        else this.markDirty('minor');
      })
      .catch((err) => this.log(`session ${String(id).slice(0, 12)}: ${err.message}`))
      .finally(() => {
        v.inflight = null;
        if (v.again) {
          v.again = false;
          this.refreshView(id);
        }
      });
    // Forget details of sessions nobody needs to see.
    if (this.views.size > 24) {
      for (const [vid] of this.views) {
        if (vid !== this.client?.view && this.views.size > 16) this.views.delete(vid);
      }
    }
    return v.inflight;
  }

  onKilnChange(ev) {
    if (ev.kind === 'session') {
      const before = ev.prev ? model.status(ev.prev) : undefined;
      const after = model.status(ev.row);
      const changed = !ev.prev
        || ev.prev.lastActiveAt !== ev.row.lastActiveAt
        || ev.prev.activity !== ev.row.activity;
      if (changed && (ev.id === this.client?.view || after === 'input')) this.refreshView(ev.id);
      if (before !== after) this.markDirty('important');
      else this.markDirty('minor');
      return;
    }
    if (ev.kind === 'removed') {
      this.views.delete(ev.id);
      this.markDirty('important');
      return;
    }
    for (const row of this.kiln.sessions.values()) {
      if (row.id === this.client?.view || model.status(row) === 'input') this.refreshView(row.id);
    }
    this.markDirty('important');
  }

  // ---------------------------------------------------------------------------
  // Snapshot

  buildSnapshot() {
    const kiln = this.kiln;
    const seen = this.persist.seen || {};
    const rows = [...kiln.sessions.values()];
    rows.sort((a, b) => {
      const d = STATUS_ORDER[model.status(a)] - STATUS_ORDER[model.status(b)];
      return d || (Number(b.lastActiveAt) || 0) - (Number(a.lastActiveAt) || 0);
    });
    const list = rows.slice(0, 90).map((row) => {
      const view = this.views.get(row.id)?.view || null;
      const reply = view ? model.replyReason(view.abilities, kiln.write) : null;
      return model.threadRow(row, seen[row.id], { write: kiln.write !== false, reply, view });
    });

    // Directories kiln offers for new sessions, plus any a running session uses.
    const used = new Set(list.map((t) => t.p));
    const byId = new Map();
    for (const dir of this.directories.directories || []) {
      byId.set(dir, { id: dir, name: escapeWow(model.projectName({ repository: dir })), act: used.has(dir) || undefined });
    }
    for (const row of rows) {
      const dir = model.directoryOf(row);
      if (dir && !byId.has(dir)) byId.set(dir, { id: dir, name: escapeWow(model.projectName(row)), act: true });
    }
    const projects = [...byId.values()]
      .sort((a, b) => (b.act ? 1 : 0) - (a.act ? 1 : 0) || a.name.localeCompare(b.name));

    let view;
    const viewId = this.client?.view;
    if (viewId) {
      const v = this.views.get(viewId);
      const row = kiln.sessions.get(viewId);
      if (v?.view) {
        const data = v.view;
        const msgs = model.messages(data.items).map(formatMessage);
        let budget = 60000;
        const out = [];
        for (let i = msgs.length - 1; i >= 0 && out.length < 40; i--) {
          const msg = msgs[i];
          budget -= msg.t.length;
          if (budget < 0 && out.length > 0) break;
          out.unshift(msg);
        }
        const reason = model.replyReason(data.abilities, kiln.write);
        view = {
          id: viewId,
          msgs: out,
          more: msgs.length > out.length || undefined,
          pending: model.pending(data.prompt) || undefined,
          act: row && model.status(row) === 'working' ? escapeWow(model.activity(row, data)) : undefined,
          reply: reason ? escapeWow(reason) : undefined,
        };
      } else {
        view = { id: viewId, loading: true };
      }
    }

    return {
      bridge: {
        version: VERSION,
        kiln: kiln.state,
        kilnerr: kiln.error ? escapeWow(kiln.error) : undefined,
        host: kiln.host ? escapeWow(kiln.host) : undefined,
        write: kiln.write !== false,
        slots: this.bank.slots,
      },
      projects,
      agents: this.directories.agents || [],
      threads: list,
      view,
      results: this.results.slice(-8).map(({ id, ok, msg }) => ({ id, ok, msg })),
    };
  }

  // ---------------------------------------------------------------------------
  // Publishing

  markDirty(kind) {
    this.dirty[kind] = true;
    this.schedulePublish();
  }

  remainingSlots() {
    const next = this.client?.slotNext ?? this.persist.slotGuess ?? 1;
    const total = Math.min(this.bank.slots, this.client?.slotCount || this.bank.slots);
    return total - next + 1;
  }

  // When should the next publish happen? Slots are the scarce resource (one per
  // publish, a few hundred per UI session), so pace by what the player is doing.
  // How much to stretch non-urgent intervals as the session's slots run down.
  static budgetFactor(remaining, total) {
    const frac = remaining / Math.max(1, total);
    if (frac > 0.5) return 1;
    if (frac > 0.25) return 1.5;
    if (frac > 0.1) return 2.5;
    return 5;
  }

  // When should the next publish happen? Each publish costs the game one slot, so:
  //  * things the player is waiting on (acks, command results) go now;
  //  * a session finishing or needing the player goes within a few seconds;
  //  * new reply text goes fast only while the player is actually reading (flag "a");
  //  * activity-label churn and keep-alives are slow, slower still as slots run low;
  //  * the last RESERVE slots are kept for acks and alerts only.
  nextPublishDelay() {
    const RESERVE = 20;
    const BATCH = 300; // let a burst of changes land in one update
    const c = this.client;
    const since = Date.now() - this.lastPublishAt;
    const open = c?.flags.includes('o');
    const attending = open && c.flags.includes('a');
    const total = Math.min(this.bank.slots, c?.slotCount || this.bank.slots);
    const remaining = this.remainingSlots();
    const needAck = c && c.ackedSeq !== c.seq;
    const resultsPending = this.results.some((r) => !r.sent);
    if (remaining <= 0) return null;
    if (needAck || resultsPending) return Math.max(0, 400 - since);
    const reserve = remaining <= RESERVE;
    const f = Bridge.budgetFactor(remaining, total);
    if (this.dirty.important) return Math.max(BATCH, (reserve ? 30000 : (attending ? 1000 : 3000) * f) - since);
    if (reserve) return null;
    if (this.dirty.view && open) return Math.max(BATCH, (attending ? 1500 : 5000) * f - since);
    if (this.dirty.minor) return Math.max(BATCH, (attending ? 5000 : open ? 15000 : 60000) * f - since);
    if (c) return Math.max(0, (open ? 90000 : 600000) - since); // keep-alive
    return null;
  }

  schedulePublish() {
    const delay = this.nextPublishDelay();
    if (delay === null) return;
    const due = Date.now() + delay;
    if (this.publishTimer && this.publishDue <= due) return;
    clearTimeout(this.publishTimer);
    this.publishDue = due;
    this.publishTimer = setTimeout(() => {
      this.publishTimer = null;
      this.publishNow();
      // Something may still be dirty (e.g. results) or a heartbeat is due later.
      if (this.client) this.schedulePublish();
    }, delay);
  }

  publishNow(reason) {
    if (!this.proc && !reason) return false;
    const snapshot = this.buildSnapshot();
    const digest = createHash('sha1').update(JSON.stringify(snapshot)).digest('hex');
    const c = this.client;
    const needAck = c && c.ackedSeq !== c.seq;
    const heartbeatDue = c && Date.now() - this.lastPublishAt > (c.flags.includes('o') ? 85000 : 595000);
    this.dirty = { important: false, minor: false, view: false };
    if (digest === this.lastDigest && !needAck && !heartbeatDue && !reason) return false;

    const gen = Math.max(Date.now(), this.lastGen + 1);
    // Signals: raise the next number in sequence, never skipping any. If the addon
    // is waiting on an earlier number (we restarted, say), raise that too. We never
    // ring ahead to an addon that claims to be past our counter: the fresh snapshot
    // this publish writes carries the real next bell, and ringing ahead would alias
    // bells that are still rung.
    const counter = this.persist.sigCounter;
    const toRaise = [];
    const sig = counter;
    // An addon that reports its sound signals don't work (flag "s") isn't listening.
    if (this.proc && !c?.flags.includes('s')) {
      for (let k = counter; k <= sig; k++) toRaise.push(k);
      // Waiting on an earlier bell (we restarted, say)? Bells are reusable: ring it too.
      if (c?.pollSig && c.pollSig < counter) toRaise.push(c.pollSig);
    }
    const raise = toRaise.length > 0;
    // Slots: write the snapshot to every slot from the addon's last confirmed position
    // to a little past our prediction, so whichever one it loads next is current
    // even if our prediction drifted (e.g. while the game window was hidden).
    let predicted = c?.slotNext ?? this.persist.slotGuess ?? 1;
    const confirmed = c?.confirmedSlot ?? this.persist.confirmedSlot ?? predicted;
    // Without sound signals the addon loads slots on its own timer (3s while the
    // player uses the window, 20s open, 90s closed), so advance our guess by clock.
    if (c?.flags.includes('s') && c.confirmedAt) {
      const every = c.flags.includes('a') ? 3000 : c.flags.includes('o') ? 20000 : 90000;
      predicted = Math.max(predicted, confirmed + Math.floor((Date.now() - c.confirmedAt) / every));
      c.slotNext = predicted;
    }
    let from = Math.max(1, Math.min(confirmed, predicted));
    const to = Math.min(this.bank.slots, Math.max(confirmed, predicted) + (c?.flags.includes('s') ? 8 : 4));
    if (to - from > 80) from = to - 80;
    const content = {
      v: 1,
      gen,
      now: Math.floor(Date.now() / 1000),
      nextSig: raise ? sig + 1 : counter,
      ack: c ? { ui: c.ui, seq: c.seq } : undefined,
      key: this.stripKeys.hex,
      ...snapshot,
    };
    const targets = new Set([1, 2, 3]);
    for (let i = from; i <= to; i++) targets.add(i);
    let bytes = 0;
    try {
      bytes = this.bank.write([...targets], content);
      if (raise) {
        for (const k of toRaise) this.bank.raise(k);
        this.persist.sigCounter = Math.max(counter, sig + 1);
        if (c) c.slotNext = predicted + 1;
        this.persist.slotGuess = predicted + 1;
      }
    } catch (err) {
      this.log(`publish failed: ${err.message}`);
      return false;
    }
    for (const r of this.results) r.sent = true;
    this.lastGen = gen;
    this.persist.gen = gen;
    this.lastDigest = digest;
    this.lastPublishAt = Date.now();
    if (c) c.ackedSeq = c.seq;
    this.saveState();
    this.publishCount = (this.publishCount || 0) + 1;
    if (this.config.verbose) this.log(`published gen ${gen} (${bytes} bytes) slots ${from}-${to} signals ${toRaise.join(',') || '-'}`);
    return true;
  }

  writeStatus() {
    const status = {
      version: VERSION,
      pid: process.pid,
      at: new Date().toISOString(),
      kiln: {
        state: this.kiln.state,
        error: this.kiln.error,
        host: this.kiln.host,
        write: this.kiln.write !== false,
        sessions: this.kiln.sessions.size,
        url: this.kiln.baseUrl,
        device: this.device ? { id: this.device.id, name: this.device.name } : null,
      },
      wow: this.proc ? { pid: this.proc.pid } : null,
      capture: { state: this.captureState, backend: this.capture.resolveBackend(), ...this.capture.stats, lastSeenAt: this.capture.lastSeenAt, lastError: this.capture.lastError },
      addon: this.client
        ? { ui: this.client.ui, version: this.client.version, flags: this.client.flags, view: this.client.view, slotNext: this.client.slotNext, lastSeen: this.client.lastSeen, encrypted: !!this.client.encrypted }
        : null,
      slots: { total: this.bank.slots, remaining: this.remainingSlots() },
      signals: { next: this.persist.sigCounter },
      rejected: { forged: this.rejected.forged, plainCommands: this.rejected.plainCommands },
      publishes: this.publishCount || 0,
      log: this.logs.slice(-30),
    };
    try {
      fs.mkdirSync(this.stateDir, { recursive: true });
      fs.writeFileSync(this.statusFile, JSON.stringify(status, null, 1));
    } catch {}
  }
}
