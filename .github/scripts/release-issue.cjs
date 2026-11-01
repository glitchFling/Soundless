// Treat issue text as data, never as executable JavaScript.
function parseReleaseIssue(title, body) {
  const versionPattern = '(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)';
  const titleMatch = new RegExp(`^v(${versionPattern})$`).exec(title.trim());
  if (!titleMatch) return null;
  let text = (body || '').trim();
  if (text.startsWith('```')) {
    const fence = /^```(?:javascript|js)?\r?\n([\s\S]*?)\r?\n```$/.exec(text);
    if (!fence) throw new Error('Use one JavaScript code block or two plain-text lines.');
    text = fence[1];
  }
  const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const assignment = new RegExp(`^version\\s*=\\s*(${versionPattern});?$`).exec(lines[0] || '');
  if (lines.length !== 2 || !assignment || lines[1] !== 'stable;') {
    throw new Error('Expected exactly: version = X.Y.Z followed by stable;');
  }
  if (assignment[1] !== titleMatch[1]) throw new Error('Title and body versions must match.');
  if (assignment[1] === '0.0.0') throw new Error('Versions start at 0.0.1.');
  return { version: assignment[1], tag: `v${assignment[1]}` };
}

async function completeReleaseIssue({ github, context, issueNumber, version, release }) {
  const repo = context.repo;
  if (!release) {
    ({ data: release } = await github.rest.repos.getReleaseByTag({ ...repo, tag: `v${version}` }));
  }
  const required = [`MathBeatStudio-${version}-unsigned.ipa`, 'SHA256SUMS.txt'];
  if (release.tag_name !== `v${version}` || release.draft || release.prerelease ||
      !required.every(name => release.assets?.some(asset => asset.name === name && asset.state === 'uploaded' && asset.size > 0))) {
    return false;
  }
  // Re-read the issue in case the version request changed while the IPA was building.
  const { data: issue } = await github.rest.issues.get({ ...repo, issue_number: issueNumber });
  if (issue.pull_request || parseReleaseIssue(issue.title, issue.body)?.version !== version) {
    throw new Error(`Issue #${issueNumber} no longer requests v${version}; leaving it unchanged.`);
  }
  try {
    await github.rest.issues.getLabel({ ...repo, name: 'releasedabot' });
  } catch (error) {
    if (error.status !== 404) throw error;
    try {
      await github.rest.issues.createLabel({ ...repo, name: 'releasedabot', color: '91F8BA', description: 'Version released by ReleaseDaBot' });
    } catch (createError) {
      // Another release may have created the shared label in the meantime.
      if (createError.status !== 422) throw createError;
      await github.rest.issues.getLabel({ ...repo, name: 'releasedabot' });
    }
  }
  await github.rest.issues.addLabels({ ...repo, issue_number: issueNumber, labels: ['releasedabot'] });
  await github.rest.issues.update({ ...repo, issue_number: issueNumber, state: 'closed', state_reason: 'completed' });
  return true;
}

async function scan({ github, context, core }) {
  const repo = context.repo;
  const canRelease = async username => {
    try {
      const { data } = await github.rest.repos.getCollaboratorPermissionLevel({ ...repo, username });
      return ['admin', 'maintain', 'write'].includes(data.permission);
    } catch (error) {
      if (error.status === 404) return false;
      throw error;
    }
  };
  if (!await canRelease(context.actor)) throw new Error('Release scans require repository write access.');
  const issues = await github.paginate(github.rest.issues.listForRepo, {
    ...repo, state: 'open', per_page: 100,
  });
  const releases = [];
  const seen = new Set();
  for (const issue of issues) {
    if (issue.pull_request) continue;
    let request;
    try { request = parseReleaseIssue(issue.title, issue.body); }
    catch (error) { core.warning(`Issue #${issue.number}: ${error.message}`); continue; }
    if (!request) continue;
    if (!await canRelease(issue.user.login)) {
      core.warning(`Issue #${issue.number}: author needs repository write access.`);
      continue;
    }
    let release;
    try {
      ({ data: release } = await github.rest.repos.getReleaseByTag({ ...repo, tag: request.tag }));
    } catch (error) { if (error.status !== 404) throw error; }
    if (release) {
      const completed = await completeReleaseIssue({ github, context, issueNumber: issue.number, version: request.version, release });
      core.info(`Issue #${issue.number}: existing release ${completed ? 'verified; labeled and closed' : 'incomplete; issue remains open'}.`);
      continue;
    }
    if (seen.has(request.version)) continue;
    seen.add(request.version);
    releases.push({ version: request.version, issue: issue.number });
  }
  releases.sort((a, b) => {
    const av = a.version.split('.').map(BigInt), bv = b.version.split('.').map(BigInt);
    for (let i = 0; i < 3; i++) { if (av[i] !== bv[i]) return av[i] < bv[i] ? -1 : 1; }
    return 0;
  });
  if (releases.length > 256) throw new Error('Too many release requests for one scan (maximum 256).');
  core.setOutput('releases', JSON.stringify(releases));
  core.setOutput('has_releases', releases.length > 0 ? 'true' : 'false');
  await core.summary.addHeading('ReleaseDaBot').addRaw(
    releases.length ? releases.map(r => `Issue #${r.issue}: v${r.version} — stable`).join('\n') : 'No pending stable version issues.'
  ).write();
}

module.exports = { parseReleaseIssue, scan, completeReleaseIssue };
