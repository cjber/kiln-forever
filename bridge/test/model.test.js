import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as model from '../src/model.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(here, 'fixtures', name), 'utf8'));
const sessions = fixture('sessions.json').sessions;
const views = fixture('views.json');
const byTitle = (title) => sessions.find((row) => row.title === title);
const INPUT = byTitle('Plan the release');
const WORKING = byTitle('Fix the build');
const DONE = byTitle('Write the changelog');
const CLOUD = byTitle('Update the docs');
const INBOX = views['claude:0b7c2a3e-7777-4a2b-8c3d-000000000007'];
const BLOCKED = views['codex:0b7c2a3e-8888-4a2b-8c3d-000000000008'];

test('status maps kiln activity and lifecycle to the addon states', () => {
  assert.equal(model.status(WORKING), 'working');
  assert.equal(model.status(INPUT), 'input');
  assert.equal(model.status(DONE), 'done');
  assert.equal(model.status(CLOUD), 'done');
  assert.equal(model.status({ activity: 'idle' }), 'open');
  assert.equal(model.status({ activity: 'working', lifecycle: 'stopped' }), 'done');
  assert.equal(model.status({ activity: 'waiting' }), 'input');
});

test('unread compares lastActiveAt with both kiln seenAt and the game seen time', () => {
  assert.equal(model.unread(INPUT, 0), true, 'newer than seenAt');
  assert.equal(model.unread(INPUT, INPUT.lastActiveAt), false, 'read here since');
  assert.equal(model.unread(WORKING, 0), false, 'working is never unread');
  assert.equal(model.unread(DONE, DONE.lastActiveAt + 1000), false, 'seen after the last activity');
  assert.equal(model.unread({ activity: 'idle', lastActiveAt: 2000, seenAt: 3000 }, 0), false);
});

test('items become addon messages, with a failed result folded into its tool line', () => {
  const msgs = model.messages(views['claude:0b7c2a3e-1111-4a2b-8c3d-000000000001'].items);
  assert.deepEqual(msgs.map((m) => m.r), ['user', 'tool', 'assistant']);
  assert.equal(msgs[1].t, 'Tool: npm test (failed)');
  assert.equal(msgs[0].t, 'Prepare the 0.2 release and tell me which channel to use.');
  assert.equal(msgs[2].r, 'assistant');
  assert.equal(msgs[0].at, 1794224700);

  const many = Array.from({ length: 70 }, (_, i) => ({ id: `m${i}`, at: i, kind: 'you', text: `line ${i}` }));
  const kept = model.messages(many);
  assert.equal(kept.length, 60);
  assert.equal(kept[0].t, 'line 10');
});

test('queued mailbox messages follow the conversation as user messages', () => {
  const msgs = model.messages(INBOX.items, INBOX.queued);
  assert.deepEqual(msgs.map((m) => m.r), ['user', 'assistant', 'user', 'user']);
  assert.equal(msgs.at(-1).t, 'Then tag 0.2');
  assert.equal(msgs.at(-1).q, true);
  assert.equal(msgs.at(-1).at, 1794225450);
  assert.equal(msgs[0].q, undefined, 'delivered messages are not queued');
  // kiln stops listing a queued message once it is delivered: it is gone here and
  // the delivered copy comes once from the conversation.
  assert.equal(model.messages(INBOX.items).some((m) => m.q), false);
  assert.deepEqual(model.messages(INBOX.items, undefined), model.messages(INBOX.items));
  assert.deepEqual(model.messages(INBOX.items, []), model.messages(INBOX.items));
});

test('a prompt becomes one question with a typed option', () => {
  const p = model.pending(views['claude:0b7c2a3e-1111-4a2b-8c3d-000000000001'].prompt);
  assert.equal(p.id, 'prompt-7');
  assert.equal(p.kind, 'question');
  assert.equal(p.questions.length, 1);
  const q = p.questions[0];
  assert.equal(q.id, 'q');
  assert.equal(q.q, 'Which channel should 0.2 go to?');
  assert.equal(q.h, 'Release channel\nThe release notes are ready.');
  assert.equal(q.multi, false);
  assert.equal(q.custom, true);
  assert.deepEqual(q.opts.map((o) => o.v), ['1', '2']);
  assert.equal(q.opts[0].l, 'Stable');
  assert.equal(q.opts[1].t, 'inline');
  assert.equal(model.pending(null), null);
});

test('a thread row carries what the addon reads, and can flags follow kiln', () => {
  const row = model.threadRow(WORKING, 0, { write: true, view: views[WORKING.id] });
  assert.equal(row.p, '/home/user/src/demo');
  assert.equal(row.s, 'working');
  assert.equal(row.m, 'codex');
  assert.equal(row.w, 'kiln');
  assert.equal(row.br, 'fix/build');
  assert.equal(row.u, undefined, 'working rows leave out lastActiveAt');
  assert.equal(row.st, 1794225000);
  assert.equal(row.can, 'rxa');
  assert.equal(row.l, 'npm test');

  const done = model.threadRow(DONE, 0, { write: true, view: views[DONE.id] });
  assert.equal(done.can, 'ra', 'not working: no stop; still reply and answer');
  assert.equal(done.un, true);
  assert.equal(done.last, 'The changelog is ready.');

  const cloud = model.threadRow(CLOUD, 0, { write: true });
  assert.equal(cloud.can, 'r', 'not in kiln: reply only');
  assert.equal(model.threadRow(WORKING, 0, { write: false }).can, '', 'write off: no actions at all');
  assert.equal(model.threadRow(CLOUD, 0, { write: false }).can, '', 'write off outside kiln: nothing to offer');
  assert.equal(model.threadRow(WORKING, 0, { write: true }).can, 'rxa', 'no view: kiln stop rule');
});

test('action flags come from kiln abilities, not just the row', () => {
  const working = { ...WORKING };
  assert.equal(model.canFlags(working, { write: false, view: views[WORKING.id] }), '', 'write off: no flags');

  const opencode = { ...WORKING, agent: 'opencode' };
  assert.equal(model.canFlags(opencode, { write: true }), 'ra', 'no view: kiln never stops OpenCode');

  const unstoppable = { abilities: { read: true, stop: false } };
  assert.equal(model.canFlags(working, { write: true, view: unstoppable }), 'ra', 'the view says stop is unavailable');

  const stoppable = { abilities: { read: true, stop: true } };
  assert.equal(model.canFlags(DONE, { write: true, view: stoppable }), 'rxa', 'the view says stop is available');

  const waiting = { abilities: { read: true, stop: false, inbox: 'messages wait in the mailbox' } };
  assert.equal(model.canFlags(working, { write: true, view: waiting }), 'ra', 'a mailbox reply is still offered');

  const never = { abilities: { read: true, stop: false, reply: 'kiln can only write to a running session that reports its id' } };
  assert.equal(model.canFlags(working, { write: true, view: never }), 'a', 'a reply reason closes the box');

  assert.equal(model.canFlags({ ...WORKING, where: 'cloud' }, { write: true }), 'r', 'answer only in kiln');
});

test('reply and inbox reasons are different: one closes the box, one explains the wait', () => {
  assert.equal(model.replyReason(INBOX.abilities, true), null);
  assert.equal(model.inboxReason(INBOX.abilities), "kiln holds messages until this session's turn ends");
  assert.equal(model.replyReason(BLOCKED.abilities, true), 'kiln can only write to a running session that reports its id');
  assert.equal(model.inboxReason(BLOCKED.abilities), null);
  assert.equal(model.replyReason({}, true), null);
  assert.equal(model.inboxReason({}), null);
  assert.equal(model.inboxReason(undefined), null);
  assert.match(model.replyReason({}, false), /write access is off/);
});

test('activity is the last tool line, the question, or what the session waits on', () => {
  assert.equal(model.activity(INPUT, views[INPUT.id]), 'Which channel should 0.2 go to?');
  assert.equal(model.activity(INPUT, null), 'Waiting on you');
  assert.equal(model.activity(WORKING, views[WORKING.id]), 'npm test');
  assert.equal(model.activity({ activity: 'working' }, { items: [] }), 'Working');
  assert.equal(model.activity({ activity: 'idle' }, { items: [] }), 'Open');
});

test('projects are named from the repository, else the working directory', () => {
  assert.equal(model.projectName(WORKING), 'demo');
  assert.equal(model.projectName({ cwd: '/home/user/src/site/pages' }), 'pages');
  assert.equal(model.projectName({}), 'Sessions');
});

test('kiln 0.24 mailbox reason in reply still offers a reply', () => {
  const old = { reply: 'kiln can only type into Claude sessions it started', stop: false };
  assert.equal(model.replyReason(old, true), null);
  assert.equal(model.inboxReason(old), 'kiln can only type into Claude sessions it started');
  assert.ok(model.canFlags({ activity: 'idle' }, { view: { abilities: old } }).includes('r'));
  const never = { reply: 'kiln can only write to a running session that reports its id' };
  assert.equal(model.replyReason(never, true), never.reply);
  assert.ok(!model.canFlags({ activity: 'idle' }, { view: { abilities: never } }).includes('r'));
});
