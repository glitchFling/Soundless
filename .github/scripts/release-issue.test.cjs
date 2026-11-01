const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseReleaseIssue, scan, completeReleaseIssue } = require('./release-issue.cjs');

test('accepts plain text and fenced version requests', () => {
  for (const body of ['version = 2.3.3\nstable;', '```javascript\nversion = 2.3.3\nstable;\n```', 'version = 2.3.3;\r\nstable;']) {
    assert.deepEqual(parseReleaseIssue('v2.3.3', body), { version: '2.3.3', tag: 'v2.3.3' });
  }
  assert.equal(parseReleaseIssue('Bug report', ''), null);
});

test('rejects mismatches, unsupported channels, extra commands, and duplicate declarations', () => {
  for (const body of ['version = 2.3.4\nstable;', 'version = 2.3.3\nbeta;', 'version = 2.3.3\nstable;\nprocess.exit()', 'version = 2.3.3\nversion = 2.3.3\nstable;', 'version = 02.3.3\nstable;']) {
    assert.throws(() => parseReleaseIssue('v2.3.3', body));
  }
  assert.throws(() => parseReleaseIssue('v0.0.0', 'version = 0.0.0\nstable;'));
});

function fixture(actor = 'maintainer') {
  const outputs = {};
  const issue = (number, version, login = 'maintainer') => ({ number, title: `v${version}`, body: `version = ${version}\nstable;`, user: { login } });
  return {
    outputs,
    context: { repo: { owner: 'owner', repo: 'repo' }, actor },
    github: {
      paginate: async () => [issue(1, '0.0.1'), issue(2, '0.0.2'), issue(3, '0.0.2'), issue(4, '0.0.3', 'outsider'), issue(5, '0.0.10'), { ...issue(6, '0.0.4'), pull_request: {} }],
      rest: {
        issues: { listForRepo() {} },
        repos: {
          getCollaboratorPermissionLevel: async ({ username }) => ({ data: { permission: username === 'maintainer' ? 'write' : 'read' } }),
          getReleaseByTag: async ({ tag }) => {
            if (tag !== 'v0.0.1') throw Object.assign(new Error('Missing'), { status: 404 });
            return { data: { tag_name: tag, draft: true, assets: [] } };
          },
        },
      },
    },
    core: { setOutput: (key, value) => { outputs[key] = value; }, info() {}, warning() {}, summary: { addHeading() { return this; }, addRaw() { return this; }, async write() {} } },
  };
}

test('scan skips existing releases, PRs, duplicates and unauthorized authors; sorts versions', async () => {
  const f = fixture();
  await scan(f);
  assert.deepEqual(JSON.parse(f.outputs.releases), [{ version: '0.0.2', issue: 2 }, { version: '0.0.10', issue: 5 }]);
  assert.equal(f.outputs.has_releases, 'true');
});

test('unauthorized actors cannot initiate a scan', async () => {
  await assert.rejects(scan(fixture('outsider')), /write access/);
});

function completionFixture() {
  const calls = [];
  const release = { tag_name: 'v0.0.2', draft: false, prerelease: false, assets: [
    { name: 'MathBeatStudio-0.0.2-unsigned.ipa', state: 'uploaded', size: 100 },
    { name: 'SHA256SUMS.txt', state: 'uploaded', size: 80 },
  ] };
  return {
    calls, release, context: fixture().context, issueNumber: 2, version: '0.0.2',
    github: { rest: { issues: {
      get: async () => ({ data: { title: 'v0.0.2', body: 'version = 0.0.2\nstable;' } }),
      getLabel: async () => { calls.push('getLabel'); throw Object.assign(new Error('Missing'), { status: 404 }); },
      createLabel: async args => { calls.push(['create', args]); },
      addLabels: async args => { calls.push(['label', args]); },
      update: async args => { calls.push(['close', args]); },
    } } },
  };
}

test('creates releasedabot, labels the issue, then closes it after uploaded assets are verified', async () => {
  const f = completionFixture();
  assert.equal(await completeReleaseIssue(f), true);
  assert.deepEqual(f.calls.slice(1).map(call => call[0]), ['create', 'label', 'close']);
  assert.equal(f.calls[1][1].name, 'releasedabot');
  assert.deepEqual(f.calls[2][1].labels, ['releasedabot']);
  assert.equal(f.calls[3][1].state, 'closed');
  assert.equal(f.calls[3][1].state_reason, 'completed');
});

test('does not close or label missing, draft, prerelease, empty, or unfinished release assets', async () => {
  for (const kind of ['missing', 'draft', 'prerelease', 'empty', 'unfinished']) {
    const f = completionFixture();
    if (kind === 'missing') f.release.assets.pop();
    if (kind === 'draft') f.release.draft = true;
    if (kind === 'prerelease') f.release.prerelease = true;
    if (kind === 'empty') f.release.assets[0].size = 0;
    if (kind === 'unfinished') f.release.assets[0].state = 'new';
    assert.equal(await completeReleaseIssue(f), false);
    assert.deepEqual(f.calls, []);
  }
});

test('leaves a changed version issue untouched', async () => {
  const f = completionFixture();
  f.github.rest.issues.get = async () => ({ data: { title: 'v0.0.3', body: 'version = 0.0.3\nstable;' } });
  await assert.rejects(completeReleaseIssue(f), /no longer requests/);
  assert.deepEqual(f.calls, []);
});

test('leaves the issue open when labeling fails', async () => {
  const f = completionFixture();
  f.github.rest.issues.getLabel = async () => ({});
  f.github.rest.issues.addLabels = async () => { throw new Error('Permission denied'); };
  await assert.rejects(completeReleaseIssue(f), /Permission denied/);
  assert.deepEqual(f.calls, []);
});

test('rescans finish issue cleanup for already published releases without rebuilding', async () => {
  const f = fixture();
  const completion = completionFixture();
  f.github.paginate = async () => [{ number: 2, title: 'v0.0.2', body: 'version = 0.0.2\nstable;', user: { login: 'maintainer' } }];
  f.github.rest.repos.getReleaseByTag = async () => ({ data: completion.release });
  f.github.rest.issues = completion.github.rest.issues;
  await scan(f);
  assert.deepEqual(JSON.parse(f.outputs.releases), []);
  assert.equal(completion.calls.at(-1)[0], 'close');
});
