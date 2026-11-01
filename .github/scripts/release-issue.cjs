const fs = require('node:fs');
const VERSION_PATTERN = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;

function readVersion(text = fs.readFileSync('VERSION', 'utf8')) {
  const version = text.trim();
  if (!VERSION_PATTERN.test(version) || version === '0.0.0') throw new Error('VERSION must contain a version such as 0.0.3 (no v prefix).');
  return version;
}

function parseCommand(text) {
  const match = /^\s*[@/]?release(?:da|a)bot(?:\s+(stable|nightly))?;?\s*$/i.exec(text || '');
  return match ? { channel: match[1]?.toLowerCase() } : null;
}

// Issue text is configuration only; never evaluate it as JavaScript.
function parseReleaseIssue(title, body, versionText, channelOverride) {
  const version = readVersion(versionText);
  if (channelOverride) {
    if (!['stable', 'nightly'].includes(channelOverride)) throw new Error('Unsupported release channel.');
    return { version, channel: channelOverride, tag: `v${version}${channelOverride === 'nightly' ? '-nightly' : ''}` };
  }
  let text = (body || '').trim();
  if (text.startsWith('```')) {
    const fence = /^```(?:javascript|js)?\r?\n([\s\S]*?)\r?\n```$/.exec(text);
    if (!fence) throw new Error('Use one code block containing stable; or nightly;');
    text = fence[1];
  }
  const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  // Accept old templates, but VERSION always wins over title/body version numbers.
  if (/^version\s*=\s*\d+\.\d+\.\d+;?$/.test(lines[0] || '')) lines.shift();
  if (lines.length !== 1 || !/^(stable|nightly);$/.test(lines[0])) throw new Error('Expected stable; or nightly; in the issue body. Version comes from ./VERSION.');
  const channel = channelOverride || lines[0].slice(0, -1);
  if (!['stable', 'nightly'].includes(channel)) throw new Error('Unsupported release channel.');
  return { version, channel, tag: `v${version}${channel === 'nightly' ? '-nightly' : ''}` };
}

async function ensureLabel(github, repo) {
  try { await github.rest.issues.getLabel({ ...repo, name: 'releasedabot' }); }
  catch (error) {
    if (error.status !== 404) throw error;
    try { await github.rest.issues.createLabel({ ...repo, name: 'releasedabot', color: '91F8BA', description: 'ReleaseDaBot release request' }); }
    catch (error) {
      if (error.status !== 422) throw error;
      await github.rest.issues.getLabel({ ...repo, name: 'releasedabot' });
    }
  }
}

async function completeReleaseIssue({ github, context, issueNumber, version, channel = 'stable', release }) {
  const repo = context.repo;
  const tag = `v${version}${channel === 'nightly' ? '-nightly' : ''}`;
  if (!release) ({ data: release } = await github.rest.repos.getReleaseByTag({ ...repo, tag }));
  const required = [`MathBeatStudio-${version}-unsigned.ipa`, 'SHA256SUMS.txt'];
  if (release.tag_name !== tag || release.draft || Boolean(release.prerelease) !== (channel === 'nightly') ||
      !required.every(name => release.assets?.some(a => a.name === name && a.state === 'uploaded' && a.size > 0))) return false;
  const { data: issue } = await github.rest.issues.get({ ...repo, issue_number: issueNumber });
  if (issue.pull_request) throw new Error('Release requests must be issues, not pull requests.');
  // Version is pinned by the initiating workflow, not mutable issue text.
  await ensureLabel(github, repo);
  await github.rest.issues.addLabels({ ...repo, issue_number: issueNumber, labels: ['releasedabot'] });
  await github.rest.issues.update({ ...repo, issue_number: issueNumber, state: 'closed', state_reason: 'completed' });
  return true;
}

async function scan({ github, context, core, versionText }) {
  const repo = context.repo;
  const version = readVersion(versionText);
  const releases = [];
  const notes = [`Version source: ./VERSION → ${version}`];
  const finish = async () => {
    core.setOutput('releases', JSON.stringify(releases));
    core.setOutput('has_releases', releases.length ? 'true' : 'false');
    await core.summary.addHeading('ReleaseDaBot').addRaw(notes.join('\n\n')).write();
  };
  const isComment = context.eventName === 'issue_comment';
  const command = isComment ? parseCommand(context.payload.comment?.body) : null;
  if (isComment && (!command || context.payload.issue?.pull_request)) {
    notes.push('No release command on an issue; nothing to do.');
    return finish();
  }
  const canRelease = async username => {
    try {
      const { data } = await github.rest.repos.getCollaboratorPermissionLevel({ ...repo, username });
      return ['admin', 'maintain', 'write'].includes(data.permission);
    } catch (error) { if (error.status === 404) return false; throw error; }
  };
  if (!await canRelease(context.actor)) throw new Error('Release commands require repository write access.');
  let issues;
  if (context.payload?.issue) {
    const { data } = await github.rest.issues.get({ ...repo, issue_number: context.payload.issue.number });
    issues = [data];
  } else {
    issues = await github.paginate(github.rest.issues.listForRepo, { ...repo, state: 'open', per_page: 100 });
  }
  const seen = new Set();
  for (const issue of issues) {
    if (issue.pull_request || issue.state === 'closed') continue;
    if (!isComment && !issue.labels?.some(l => (typeof l === 'string' ? l : l.name) === 'releasedabot')) continue;
    if (!isComment && !await canRelease(issue.user.login)) {
      notes.push(`Issue #${issue.number}: author needs write access.`); continue;
    }
    let request;
    try { request = parseReleaseIssue(issue.title, issue.body, version, command?.channel); }
    catch (error) {
      core.warning(`Issue #${issue.number}: ${error.message}`);
      notes.push(`Issue #${issue.number}: ${error.message}`);
      if (context.payload?.issue) core.setFailed(error.message);
      continue;
    }
    await ensureLabel(github, repo);
    await github.rest.issues.addLabels({ ...repo, issue_number: issue.number, labels: ['releasedabot'] });
    let release;
    try { ({ data: release } = await github.rest.repos.getReleaseByTag({ ...repo, tag: request.tag })); }
    catch (error) { if (error.status !== 404) throw error; }
    if (release) {
      const completed = await completeReleaseIssue({ github, context, issueNumber: issue.number, ...request, release });
      notes.push(`Issue #${issue.number}: ${request.tag} ${completed ? 'already published; issue closed.' : 'has incomplete assets; issue remains open.'}`);
      continue;
    }
    if (seen.has(request.tag)) { notes.push(`Issue #${issue.number}: duplicate request; retry after publication to close it.`); continue; }
    seen.add(request.tag);
    releases.push({ ...request, issue: issue.number });
    notes.push(`Issue #${issue.number}: building ${request.tag} (${request.channel}).`);
  }
  if (!releases.length) notes.push('No new release build requested. See reasons above.');
  await finish();
}

module.exports = { readVersion, parseCommand, parseReleaseIssue, completeReleaseIssue, scan };
