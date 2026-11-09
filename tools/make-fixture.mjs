// Build tools/fixtures/snapshot.lua from a hand-written T3 state, using the bridge's
// own snapshot builder and Lua serializer so the fixture keeps exactly the shape the
// bridge publishes. Deterministic: rerunning it rewrites the same bytes.
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
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kiln-fixture-'));

const bridge = new Bridge({ addonsDir: tmp, config: {}, log: () => {}, stateDir: tmp });
// A fixed master key, so the fixture's link keys are stable.
bridge.stripKeys = deriveKeys(Buffer.alloc(32, 7));

const t = (over) => ({
  projectId: 'p1',
  createdAt: '2026-11-09T09:00:00.000Z',
  updatedAt: '2026-11-09T11:55:00.000Z',
  ...over,
});

bridge.t3.state = 'connected';
bridge.t3.config = { environment: { serverVersion: '0.1.7-nightly', label: 'this computer' } };

bridge.t3.projects.set('p1', { id: 'p1', title: 'kiln-wow', repositoryIdentity: { displayName: 'kiln-wow' } });
bridge.t3.projects.set('p2', { id: 'p2', title: 'website' });

bridge.t3.threads.set('t1', t({
  id: 't1',
  title: 'Fix the build',
  status: 'running',
  activityRunStatus: 'running',
  activeRunId: 'r1',
  activityRunStartedAt: '2026-11-09T11:50:00.000Z',
  modelSelection: { model: 'gpt-5-codex' },
}));
bridge.t3.threads.set('t2', t({
  id: 't2',
  title: 'Plan the release',
  status: 'completed',
  pendingRuntimeRequest: { id: 'q1', kind: 'user_input' },
  latestRunCompletedAt: '2026-11-09T11:54:00.000Z',
  lastVisitedAt: '2026-11-09T11:40:00.000Z',
  branch: 'release/0.2',
  modelSelection: { model: 'gpt-5-codex' },
}));
bridge.t3.threads.set('t3', t({
  id: 't3',
  title: 'Update the docs',
  projectId: 'p2',
  status: 'completed',
  pendingRuntimeRequest: { id: 'a1', kind: 'command' },
  latestRunCompletedAt: '2026-11-09T11:53:00.000Z',
  lastVisitedAt: '2026-11-09T11:30:00.000Z',
}));
bridge.t3.threads.set('t4', t({
  id: 't4',
  title: 'Try the new layout',
  projectId: 'p2',
  status: 'completed',
  hasActionableProposedPlan: true,
  updatedAt: '2026-11-09T11:52:00.000Z',
}));
bridge.t3.threads.set('t5', t({
  id: 't5',
  title: 'Write the changelog',
  status: 'completed',
  latestRunCompletedAt: '2026-11-09T11:51:00.000Z',
  lastVisitedAt: '2026-11-09T11:20:00.000Z',
  latestVisibleMessage: { role: 'assistant', text: 'The changelog is ready.' },
}));
bridge.t3.threads.set('t6', t({
  id: 't6',
  title: 'Old experiment',
  status: 'completed',
  settledOverride: 'settled',
  updatedAt: '2026-11-08T16:00:00.000Z',
}));
bridge.t3.threads.set('t7', t({
  id: 't7',
  title: 'Broken import',
  status: 'failed',
  lastError: 'Could not read the config',
  updatedAt: '2026-11-09T11:10:00.000Z',
}));

const view = (projection) => ({ projection, fetchedAt: Date.now(), inflight: null, again: false });

bridge.views.set('t1', view({
  runs: [{ id: 'r1', startedAt: '2026-11-09T11:50:00.000Z' }],
  turnItems: [
    { runId: 'r1', type: 'command_execution', status: 'running', input: 'npm test' },
  ],
  messages: [],
  runtimeRequests: [],
}));

bridge.views.set('t2', view({
  runs: [{ id: 'r2', startedAt: '2026-11-09T11:45:00.000Z', completedAt: '2026-11-09T11:54:00.000Z' }],
  turnItems: [
    { runId: 'r2', type: 'command_execution', status: 'completed', input: 'npm test' },
    { runId: 'r2', type: 'file_change', status: 'completed', fileName: '/home/me/kiln-wow/README.md', additions: 12, deletions: 3 },
    { runId: 'r2', type: 'user_input_request', status: 'pending', requestId: 'q1', questions: [{ id: 'channel', header: 'Release channel', question: 'Which channel should 0.2 go to?', options: [{ label: 'Stable', description: 'Everyone', value: 'stable' }, { label: 'Beta', description: 'Early testers', value: 'beta' }] }] },
  ],
  runtimeRequests: [{ id: 'q1', kind: 'user_input', status: 'pending' }],
  messages: [
    { role: 'user', text: 'Prepare the 0.2 release and tell me which channel to use.', createdAt: '2026-11-09T11:45:00.000Z' },
    { role: 'assistant', text: 'I have the release notes ready. **One question** before I publish.', createdAt: '2026-11-09T11:54:00.000Z' },
  ],
}));

bridge.views.set('t3', view({
  runs: [{ id: 'r3', startedAt: '2026-11-09T11:48:00.000Z' }],
  turnItems: [
    { runId: 'r3', nodeId: 'n1', type: 'command_execution', status: 'pending', input: 'git push origin main' },
  ],
  messages: [],
  runtimeRequests: [{ id: 'a1', kind: 'command', status: 'pending', nodeId: 'n1' }],
}));

bridge.client = {
  session: 'fixture',
  ui: 'fixture',
  seq: 1,
  ackedSeq: -1,
  flags: 'o',
  view: 't2',
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
fs.writeFileSync(out, luaAssignment('KilnWoW_Inbox', snap));
console.log(`wrote ${path.relative(root, out)}: ${snap.threads.length} threads, view ${snap.view.id} (${snap.view.msgs.length} messages)`);

bridge.t3.stop();
fs.rmSync(tmp, { recursive: true, force: true });
