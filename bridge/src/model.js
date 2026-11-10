// The only module that knows kiln's shapes. Everything the addon reads is built
// here from kiln's session rows, view items and prompts, so the rest of the bridge
// never has to.

import { escapeWow, firstLine, fitFont } from './format.js';

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

// Why kiln cannot type into a session at all, or null when it can. A session whose
// messages wait in kiln's mailbox reports that reason as `abilities.inbox` instead.
export function replyReason(abilities, write) {
  if (write === false) return 'kiln write access is off on the computer';
  const reply = sessionAbilities(abilities).reply;
  return reply ? String(reply) : null;
}

// Why a message to this session waits in kiln's mailbox, or null when it goes straight in.
export function inboxReason(abilities) {
  const inbox = sessionAbilities(abilities).inbox;
  return inbox ? String(inbox) : null;
}

// kiln's refusal for a session it can never type into, the one `reply` it keeps.
const NEVER_REPLY = 'kiln can only write to a running session that reports its id';

// kiln 0.24 and earlier sent the mailbox reason in `reply` and had no `inbox`. Its only
// true refusal is NEVER_REPLY, so any other `reply` from it is the mailbox reason.
export function sessionAbilities(abilities) {
  const a = abilities || {};
  if (a.inbox !== undefined || !a.reply || a.reply === NEVER_REPLY) return a;
  return { ...a, reply: undefined, inbox: a.reply };
}

// The flags the addon uses to decide which actions to offer:
//   r  reply, x  stop, a  answer a question.
export function canFlags(row, { write = true, view = null } = {}) {
  if (!write) return '';
  const s = status(row);
  const abilities = view ? sessionAbilities(view.abilities) : null;
  let can = '';
  // `reply` means kiln can never type into this session. A mailbox reason (`inbox`)
  // only says the message will wait, so replying is still offered.
  if (!abilities?.reply) can += 'r';
  const stop = view
    ? Boolean(abilities?.stop)
    : row?.where === 'kiln' && row?.agent !== 'opencode' && s === 'working';
  if (stop) can += 'x';
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
export function threadRow(row, seenLocal, { write = true, view = null } = {}) {
  const s = status(row);
  const label = activity(row, view);
  const last = s === 'open' || s === 'done' ? lastAgentText(view) : null;
  return {
    id: row.id,
    title: fitFont(escapeWow(row.title || 'Untitled')),
    p: directoryOf(row),
    s,
    l: fitFont(escapeWow(label)),
    // A working session changes lastActiveAt with every tool call but the game shows
    // elapsed time, so leave it out and avoid a publish for each one.
    u: s === 'working' ? undefined : sec(Number(row.lastActiveAt)),
    st: sec(Number(row.startedAt)),
    un: unread(row, seenLocal) || undefined,
    br: row.branch ? fitFont(escapeWow(row.branch)) : undefined,
    m: row.agent || undefined,
    w: row.where || undefined,
    can: canFlags(row, { write, view }),
    last: last ? fitFont(escapeWow(firstLine(last, 160))) : undefined,
  };
}

const ROLE = { you: 'user', agent: 'assistant', notice: 'system' };

// Kiln's mailbox: messages it has accepted but not delivered yet, oldest first.
// A queued message is a user message that has not reached the conversation yet.
export function queuedMessages(queued) {
  if (!Array.isArray(queued)) return [];
  return queued.map((item) => ({
    r: 'user',
    t: fitFont(String(item?.text || '')),
    at: sec(Number(item?.at)),
    q: true,
  }));
}

// The transcript the addon shows. A delivered message appears once from the
// conversation; kiln stops listing it as queued when that happens.
export function messages(items, queued) {
  const out = [];
  const byId = new Map();
  for (const item of items || []) {
    if (item.kind === 'you' || item.kind === 'agent' || item.kind === 'notice') {
      const msg = { r: ROLE[item.kind], t: fitFont(String(item.text || '')), at: sec(Number(item.at)) };
      out.push(msg);
      if (item.id) byId.set(item.id, msg);
    } else if (item.kind === 'tool') {
      const msg = { r: 'tool', t: fitFont(`Tool: ${String(item.text || item.tool || 'tool')}`), at: sec(Number(item.at)) };
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
  out.push(...queuedMessages(queued));
  return out.slice(-60).map(({ r, t, at, q }) => ({ r, t, at, q: q || undefined }));
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
      h: context.length ? fitFont(escapeWow(context.join('\n'))) : undefined,
      q: fitFont(escapeWow(prompt.question || '')),
      multi: false,
      custom: custom || undefined,
      opts: options.map((o) => ({
        l: fitFont(escapeWow(o.label || '')),
        d: o.detail ? fitFont(escapeWow(o.detail)) : undefined,
        v: String(o.number),
        t: o.typed || undefined,
      })),
    }],
  };
}
