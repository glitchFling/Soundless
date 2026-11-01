const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readVersion, parseCommand, parseReleaseIssue, scan, completeReleaseIssue } = require('./release-issue.cjs');

test('VERSION is the version source, including old templates and unrelated issue titles', () => {
  for (const [title, body] of [['Release please', 'stable;'], ['v9.9.9', '```javascript\nversion = 9.9.9\nstable;\n```']]) {
    assert.deepEqual(parseReleaseIssue(title, body, '0.0.3\n'), { version: '0.0.3', channel: 'stable', tag: 'v0.0.3' });
  }
  for (const version of ['0.0.0', 'v0.0.3', '1.02.3', '0.0.3\n0.0.4', '$(exit)']) assert.throws(() => readVersion(version));
});

test('recognizes exact commands, optional channel, and both spellings', () => {
  for (const command of ['releaseabot', 'releasedabot', '/releasedabot', '@ReleaseDaBot;']) assert.deepEqual(parseCommand(command), { channel: undefined });
  assert.deepEqual(parseCommand('releaseabot nightly'), { channel: 'nightly' });
  for (const text of ['please releaseabot', 'releaseabot nightly; rm -rf /', 'releaseabot beta']) assert.equal(parseCommand(text), null);
});

test('nightly requests are prerelease tags; unknown or extra lines are rejected', () => {
  assert.deepEqual(parseReleaseIssue('anything', 'nightly;', '0.0.3'), { version: '0.0.3', channel: 'nightly', tag: 'v0.0.3-nightly' });
  assert.equal(parseReleaseIssue('', 'stable;', '0.0.3', 'nightly').channel, 'nightly');
  for (const body of ['beta;', 'stable;\nnightly;', 'stable;\nprocess.exit()', 'version = 1.0.0']) assert.throws(() => parseReleaseIssue('', body, '0.0.3'));
});

function fixture({ eventName = 'workflow_dispatch', command, actor = 'maintainer', labeled = true, existing = false } = {}) {
  const calls = [];
  const outputs = {};
  const issue = { number: 3, title: 'Old title v0.0.9', body: 'nightly;', state: 'open', labels: labeled ? [{ name: 'releasedabot' }] : [], user: { login: 'maintainer' } };
  const release = { tag_name: 'v0.0.3-nightly', draft: false, prerelease: true, assets: [
    { name: 'MathBeatStudio-0.0.3-unsigned.ipa', state: 'uploaded', size: 100 },
    { name: 'SHA256SUMS.txt', state: 'uploaded', size: 80 },
  ] };
  const context = { repo: { owner: 'owner', repo: 'repo' }, actor, eventName, payload: eventName === 'workflow_dispatch' ? {} : { issue, comment: { body: command } } };
  const github = { paginate: async () => [issue], rest: {
    repos: {
      getCollaboratorPermissionLevel: async ({ username }) => ({ data: { permission: username === 'maintainer' ? 'admin' : 'read' } }),
      getReleaseByTag: async () => { if (!existing) throw Object.assign(new Error('Missing'), { status: 404 }); return { data: release }; },
    },
    issues: {
      listForRepo() {},
      get: async () => ({ data: issue }),
      getLabel: async () => ({}),
      createLabel: async () => { calls.push('create'); },
      addLabels: async () => { calls.push('label'); },
      update: async args => { calls.push(['close', args]); },
    },
  } };
  return { github, context, issue, release, calls, outputs, versionText: '0.0.3', core: {
    setOutput: (key, value) => { outputs[key] = value; }, warning() {}, setFailed: message => { outputs.failure = message; },
    summary: { addHeading() { return this; }, addRaw() { return this; }, async write() {} },
  } };
}

test('manual scan uses VERSION and labeled issues', async () => {
  const f = fixture(); await scan(f);
  assert.deepEqual(JSON.parse(f.outputs.releases), [{ version: '0.0.3', channel: 'nightly', tag: 'v0.0.3-nightly', issue: 3 }]);
  const untagged = fixture({ labeled: false }); await scan(untagged);
  assert.equal(untagged.outputs.has_releases, 'false');
});

test('command targets its issue and works without a pre-existing label', async () => {
  const f = fixture({ eventName: 'issue_comment', command: 'releaseabot', labeled: false });
  f.github.paginate = async () => { throw new Error('Must target the command issue only'); };
  await scan(f);
  assert.equal(f.outputs.has_releases, 'true');
  assert.deepEqual(f.calls, ['label']);
});

test('explicit command channel works on a prose issue and ignores body version', async () => {
  const f = fixture({ eventName: 'issue_comment', command: '/releaseabot stable' });
  f.issue.body = 'Please publish the latest version.';
  await scan(f);
  assert.deepEqual(JSON.parse(f.outputs.releases), [{ version: '0.0.3', channel: 'stable', tag: 'v0.0.3', issue: 3 }]);
});

test('invalid targeted requests explain the failure and invalid VERSION blocks release', async () => {
  const f = fixture({ eventName: 'issues' }); f.issue.body = 'beta;';
  await scan(f);
  assert.match(f.outputs.failure, /Expected stable/);
  assert.equal(f.outputs.has_releases, 'false');
  const invalid = fixture(); invalid.versionText = 'oops';
  await assert.rejects(scan(invalid), /VERSION must contain/);
});

test('unrelated comments, PR comments, closed issues, and unauthorized commands cannot release', async () => {
  for (const f of [fixture({ eventName: 'issue_comment', command: 'hello' }), fixture({ eventName: 'issue_comment', command: 'releasedabot' })]) {
    if (f.context.payload.comment.body === 'releasedabot') f.issue.pull_request = {};
    await scan(f); assert.equal(f.outputs.has_releases, 'false'); assert.deepEqual(f.calls, []);
  }
  const closed = fixture({ eventName: 'issue_comment', command: 'releaseabot' }); closed.issue.state = 'closed';
  await scan(closed); assert.equal(closed.outputs.has_releases, 'false');
  await assert.rejects(scan(fixture({ eventName: 'issue_comment', command: 'releaseabot', actor: 'outsider' })), /write access/);
});

test('existing nightly release closes and labels its issue without another build', async () => {
  const f = fixture({ existing: true }); await scan(f);
  assert.equal(f.outputs.has_releases, 'false');
  assert.equal(f.calls.at(-1)[0], 'close');
  assert.equal(f.calls.at(-1)[1].state_reason, 'completed');
});

test('incomplete, draft, wrong-channel, or failed releases leave the issue open', async () => {
  for (const kind of ['missing', 'draft', 'stable', 'empty', 'unfinished']) {
    const f = fixture({ existing: true });
    if (kind === 'missing') f.release.assets.pop();
    if (kind === 'draft') f.release.draft = true;
    if (kind === 'stable') f.release.prerelease = false;
    if (kind === 'empty') f.release.assets[0].size = 0;
    if (kind === 'unfinished') f.release.assets[0].state = 'new';
    assert.equal(await completeReleaseIssue({ ...f, issueNumber: 3, version: '0.0.3', channel: 'nightly' }), false);
    assert.deepEqual(f.calls, []);
  }
});

test('creates missing releasedabot label before completing and keeps issue open if labeling fails', async () => {
  const f = fixture({ existing: true });
  f.github.rest.issues.getLabel = async () => { throw Object.assign(new Error('Missing'), { status: 404 }); };
  assert.equal(await completeReleaseIssue({ ...f, issueNumber: 3, version: '0.0.3', channel: 'nightly' }), true);
  assert.deepEqual(f.calls.slice(0, 2), ['create', 'label']);
  const denied = fixture({ existing: true });
  denied.github.rest.issues.addLabels = async () => { throw new Error('Denied'); };
  await assert.rejects(completeReleaseIssue({ ...denied, issueNumber: 3, version: '0.0.3', channel: 'nightly' }), /Denied/);
  assert.deepEqual(denied.calls, []);
});
