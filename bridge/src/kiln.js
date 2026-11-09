// Client for kiln's local phone API: the session list over one read-only WebSocket,
// and reads and writes over HTTP on the same base URL.
//
// Auth is the token written by `kiln-forever install` after pairing (see auth.js).
// Never send an Origin header: kiln answers 403 to any request that carries one.
// Kiln's errors come back as { error } with a 4xx or 5xx status.

import { EventEmitter } from 'node:events';
import { readToken } from './auth.js';

export const DEFAULT_BASE_URL = 'http://127.0.0.1:7437';

const MAX_BACKOFF = 15000;

function httpError(pathname, res, body) {
  const message = body && body.error ? String(body.error) : `HTTP ${res.status}`;
  const err = new Error(`${pathname}: ${message}`);
  err.status = res.status;
  err.body = body;
  return err;
}

const sameRow = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export class KilnClient extends EventEmitter {
  constructor({ tokenProvider = readToken, baseUrl = DEFAULT_BASE_URL, log = () => {} } = {}) {
    super();
    this.tokenProvider = tokenProvider;
    this.baseUrl = String(baseUrl || DEFAULT_BASE_URL).replace(/\/+$/, '');
    this.log = log;
    this.state = 'connecting';
    this.error = null;
    this.sessions = new Map(); // id -> row
    this.write = true;
    this.host = null;
    this.problem = null;
    this.sequence = null;
    this.views = new Map(); // id -> { cursor, items, prompt, abilities }
    this.ws = null;
    this.backoff = 1000;
    this.stopped = false;
    this.everConnected = false;
  }

  setState(state, error = null) {
    if (this.state === state && this.error === error) return;
    this.state = state;
    this.error = error;
    this.emit('state', state, error);
  }

  start() {
    this.stopped = false;
    this.connect();
  }

  stop() {
    this.stopped = true;
    const ws = this.ws;
    this.ws = null;
    try {
      ws?.close();
    } catch {}
  }

  async connect() {
    if (this.stopped) return;
    let token;
    try {
      token = await this.tokenProvider();
    } catch (err) {
      this.setState('unpaired', err.message);
      return;
    }
    if (!token) {
      this.setState('unpaired', 'not paired with kiln');
      return;
    }
    if (this.stopped) return;
    this.setState('connecting');
    const url = new URL('/v1/events', this.baseUrl);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    try {
      await this.open(url, token);
    } catch (err) {
      this.setState('offline', err.message);
      this.scheduleReconnect();
    }
  }

  scheduleReconnect() {
    if (this.stopped) return;
    const delay = this.backoff;
    this.backoff = Math.min(this.backoff * 2, MAX_BACKOFF);
    setTimeout(() => this.connect(), delay);
  }

  open(url, token) {
    return new Promise((resolve, reject) => {
      let ws;
      try {
        ws = new WebSocket(url, { headers: { Authorization: `Bearer ${token}` } });
      } catch (err) {
        reject(err);
        return;
      }
      this.ws = ws;
      let opened = false;
      ws.onopen = () => {
        opened = true;
        this.backoff = 1000;
        this.everConnected = true;
        this.setState('connected');
        resolve();
      };
      ws.onmessage = (ev) => this.onMessage(ev.data);
      ws.onerror = (ev) => {
        if (opened) return;
        this.ws = null;
        try {
          ws.close();
        } catch {}
        reject(new Error(ev.message || 'kiln WebSocket error'));
      };
      ws.onclose = (ev) => {
        if (this.ws !== ws) return;
        this.ws = null;
        if (ev.code === 4001) {
          this.setState('unpaired', 'this device was revoked in kiln');
          return;
        }
        if (this.stopped) return;
        this.setState('offline', ev.reason || (ev.code === 1013 ? 'kiln is too slow; retrying' : 'connection closed'));
        this.scheduleReconnect();
      };
    });
  }

  onMessage(data) {
    let snap;
    try {
      snap = JSON.parse(typeof data === 'string' ? data : Buffer.from(data).toString('utf8'));
    } catch {
      return;
    }
    if (snap && Array.isArray(snap.sessions)) this.applySnapshot(snap);
  }

  applySnapshot(snap) {
    const first = !this.everConnected || this.sequence === null;
    const before = this.sessions;
    const next = new Map();
    for (const row of snap.sessions) if (row && row.id) next.set(row.id, row);
    const metaChanged = this.host !== (snap.host ?? this.host)
      || this.write !== (snap.write !== false)
      || this.problem !== (snap.problem ?? null);
    this.sessions = next;
    this.host = snap.host ?? this.host;
    this.write = snap.write !== false;
    this.problem = snap.problem ?? null;
    this.sequence = snap.sequence ?? this.sequence;

    if (first || metaChanged) this.emit('change', { kind: 'snapshot' });
    if (first) return;
    for (const [id, row] of next) {
      const prev = before.get(id);
      if (!prev || !sameRow(prev, row)) this.emit('change', { kind: 'session', id, row, prev });
    }
    for (const id of before.keys()) {
      if (!next.has(id)) this.emit('change', { kind: 'removed', id });
    }
  }

  async request(method, pathname, body) {
    const token = await this.tokenProvider();
    if (!token) {
      this.setState('unpaired', 'not paired with kiln');
      throw new Error('not paired with kiln');
    }
    const headers = { Authorization: `Bearer ${token}` };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let res;
    try {
      res = await fetch(new URL(pathname, this.baseUrl), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      });
    } catch (err) {
      throw new Error(`kiln: ${err.message}`);
    }
    const text = await res.text();
    let parsed = null;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {}
    if (res.status === 401 || res.status === 403) {
      if (res.status === 401) this.setState('unpaired', 'kiln rejected the device token');
    }
    if (!res.ok) throw httpError(pathname, res, parsed);
    return parsed;
  }

  async directories() {
    return this.request('GET', '/v1/directories');
  }

  // Reads a session's view, keeping its cursor so repeated calls only fetch new items.
  async view(id) {
    let st = this.views.get(id);
    if (!st) {
      st = { cursor: null, items: [], prompt: null, abilities: {} };
      this.views.set(id, st);
    }
    const q = st.cursor ? `?cursor=${encodeURIComponent(st.cursor)}` : '';
    const data = await this.request('GET', `/v1/sessions/${encodeURIComponent(id)}/view${q}`);
    if (data.reset) {
      st.items = [];
    }
    const known = new Set(st.items.map((i) => i.id));
    for (const item of data.items || []) {
      if (!item || !item.id || known.has(item.id)) continue;
      known.add(item.id);
      st.items.push(item);
    }
    if (st.items.length > 600) st.items = st.items.slice(-600);
    st.cursor = data.cursor || st.cursor;
    st.prompt = data.prompt || null;
    st.abilities = data.abilities || {};
    return {
      ...data,
      items: st.items,
      prompt: st.prompt,
      abilities: st.abilities,
    };
  }

  sendMessage(id, text, msgId) {
    const body = { text };
    if (msgId) body.id = msgId;
    return this.request('POST', `/v1/sessions/${encodeURIComponent(id)}/messages`, body);
  }

  answerPrompt(id, key, option, text) {
    const body = { key, option: Number(option) };
    if (text) body.text = String(text);
    return this.request('POST', `/v1/sessions/${encodeURIComponent(id)}/prompt`, body);
  }

  interrupt(id) {
    return this.request('POST', `/v1/sessions/${encodeURIComponent(id)}/interrupt`, {});
  }

  newSession(agent, directory, prompt) {
    return this.request('POST', '/v1/sessions', { agent, directory, prompt });
  }
}
