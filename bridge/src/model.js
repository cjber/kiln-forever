// The only module that knows kiln's shapes. Everything the addon reads is built
// here from kiln's session rows, view items and prompts, so the rest of the bridge
// never has to.

import { escapeWow, firstLine } from './format.js';

const sec = (ms) => (Number.isFinite(ms) ? Math.floor(ms / 1000) : undefined);

export function basename(value) {
  const s = String(value ?? '').replace(/[\\/]+$/, '');
  if (!s) return '';
  const at = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'));
  return at >= 0 ? s.slice(at + 1) : s;
}

// The project a session belongs to: its repository, else the folder it runs in.
export function directoryOf(row) {
  return row?.repository || row?.cwd || '';
}

export function projectName(row) {
  return basename(directoryOf(row)) || 'Sessions';
}

// The addon's four states: working, input, open, done.
export function status(row) {
  if (!row) return 'open';
  if (row.lifecycle === 'completed' || row.lifecycle === 'stopped') return 'done';
  if (row.activity === 'working') return 'working';
  if (row.activity === 'waiting') return 'input';
  return 'open';
}

export function unread(row, seenLocal) {
  if (!row) return false;
  if (status(row) === 'working') return false;
  const last = Number(row.lastActiveAt) || 0;
  return last > Math.max(Number(row.seenAt) || 0, Number(seenLocal) || 0);
}

// Why kiln cannot type into a session now, or null when it can.
export function replyReason(abilities, write) {
  if (write === false) return 'kiln write access is off on the computer';
  if (abilities && abilities.reply) return String(abilities.reply);
  return null;
}

// The flags the addon uses to decide which actions to offer:
//   r  reply, x  stop, a  answer a question.
export function canFlags(row, { write = true, reply = null } = {}) {
  const s = status(row);
  let can = '';
  if (write && !reply) can += 'r';
  if (row?.where === 'kiln' && s === 'working') can += 'x';
  if (row?.where === 'kiln') can += 'a';
  return can;
}

// A short label for the tracker: the last tool line, or what the session waits on.
export function activity(row, view) {
  const s = status(row);
  if (s === 'input') {
    const question = String(view?.prompt?.question || '').replace(/\s+/g, ' ').trim();
    if (question) return question.length > 70 ? `${question.slice(0, 69)}…` : question;
    return 'Waiting on you';
  }
  const items = view?.items || [];
  for (let i = items.length - 1; i >= 0; i--) {
    const item = items[i];
    if (item.kind !== 'tool') continue;
    const text = String(item.text || '').replace(/\s+/g, ' ').trim();
    if (text) return text.length > 60 ? `${text.slice(0, 59)}…` : text;
    return `Using ${item.tool || 'a tool'}`;
  }
  if (s === 'working') return 'Working';
  if (s === 'done') return 'Done';
  return 'Open';
}

function lastAgentText(view) {
  const items = view?.items || [];
  for (let i = items.length - 1; i >= 0; i--) {
    const item = items[i];
    if (item.kind === 'agent' && item.text?.trim()) return item.text;
  }
  return null;
}

// One session row as the addon reads it.
export function threadRow(row, seenLocal, { write = true, reply = null, view = null } = {}) {
  const s = status(row);
  const label = activity(row, view);
  const last = s === 'open' || s === 'done' ? lastAgentText(view) : null;
  return {
    id: row.id,
    title: escapeWow(row.title || 'Untitled'),
    p: directoryOf(row),
    s,
    l: escapeWow(label),
    // A working session changes lastActiveAt with every tool call but the game shows
    // elapsed time, so leave it out and avoid a publish for each one.
    u: s === 'working' ? undefined : sec(Number(row.lastActiveAt)),
    st: sec(Number(row.startedAt)),
    un: unread(row, seenLocal) || undefined,
    br: row.branch ? escapeWow(row.branch) : undefined,
    m: row.agent || undefined,
    w: row.where || undefined,
    can: canFlags(row, { write, reply }),
    last: last ? escapeWow(firstLine(last, 160)) : undefined,
  };
}

const ROLE = { you: 'user', agent: 'assistant', notice: 'system' };

// The transcript the addon shows.
export function messages(items) {
  const out = [];
  const byId = new Map();
  for (const item of items || []) {
    if (item.kind === 'you' || item.kind === 'agent' || item.kind === 'notice') {
      const msg = { r: ROLE[item.kind], t: String(item.text || ''), at: sec(Number(item.at)) };
      out.push(msg);
      if (item.id) byId.set(item.id, msg);
    } else if (item.kind === 'tool') {
      const msg = { r: 'tool', t: `Tool: ${String(item.text || item.tool || 'tool')}`, at: sec(Number(item.at)) };
      out.push(msg);
      if (item.id) byId.set(item.id, msg);
    }
  }
  // A failed result folds into the tool line it belongs to; a successful one says
  // nothing the tool line doesn't already say.
  for (const item of items || []) {
    if (item.kind !== 'result' || !item.error) continue;
    const msg = byId.get(item.of);
    if (msg) msg.t = `${msg.t} (failed)`;
  }
  return out.slice(-60).map(({ r, t, at }) => ({ r, t, at }));
}

// A kiln prompt as the addon's single-question shape. Options carry kiln's number
// as `v`; `t` marks an option that also takes typed text.
export function pending(prompt) {
  if (!prompt || !prompt.key) return null;
  const options = Array.isArray(prompt.options) ? prompt.options : [];
  const custom = options.some((o) => o.typed);
  const context = Array.isArray(prompt.context) ? prompt.context.filter((l) => l) : [];
  return {
    id: prompt.key,
    kind: 'question',
    questions: [{
      id: 'q',
      h: context.length ? escapeWow(context.join('\n')) : undefined,
      q: escapeWow(prompt.question || ''),
      multi: false,
      custom: custom || undefined,
      opts: options.map((o) => ({
        l: escapeWow(o.label || ''),
        d: o.detail ? escapeWow(o.detail) : undefined,
        v: String(o.number),
        t: o.typed || undefined,
      })),
    }],
  };
}
