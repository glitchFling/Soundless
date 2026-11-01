const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseReleaseIssue, scan } = require('./release-issue.cjs');

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
          getReleaseByTag: async ({ tag }) => { if (tag !== 'v0.0.1') throw Object.assign(new Error('Missing'), { status: 404 }); },
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
