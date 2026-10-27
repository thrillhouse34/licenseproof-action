#!/usr/bin/env node
//
// Renders licenseproof's `scan --format json` report into the Markdown that
// goes to $GITHUB_STEP_SUMMARY, and writes the action's key=value outputs.
//
//   node summary.js <report.json> <scan-exit-code> <fail-on> <outputs-file>
//
// Markdown goes to stdout. No dependencies: it runs on the runner's bundled
// node, same as the CLI.
'use strict';
const fs = require('fs');

const [reportPath, exitCodeArg, failOn, outputsPath] = process.argv.slice(2);
if (!reportPath || !outputsPath) {
  console.error('usage: summary.js <report.json> <scan-exit-code> <fail-on> <outputs-file>');
  process.exit(2);
}

const r = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const s = r.summary;
const failed = Number(exitCodeArg) !== 0;

// Only the rows a human has to act on. A 2000-package tree would blow past the
// 1 MiB job-summary limit, so cap the table and say so.
const ROW_CAP = 50;
const flagged = r.packages.filter(
  (p) => p.conflict.level === 'CONFLICT' || p.conflict.level === 'REVIEW' || p.category === 'unknown',
);

const esc = (v) => String(v == null ? '' : v).replace(/\|/g, '\\|');
const out = [];

out.push(`## ${failed ? '❌' : '✅'} LicenseProof — ${esc(r.projectName)}`);
out.push('');
out.push(
  failed
    ? `Failed on \`--fail-on ${esc(failOn)}\`. ${flagged.length} package(s) below need a decision.`
    : `Passed on \`--fail-on ${esc(failOn)}\`.`,
);
out.push('');
out.push('| | |');
out.push('|---|---|');
out.push(`| Project license | \`${esc(r.projectLicense.id)}\`${r.projectLicense.wasUnspecified ? ' _(not declared — assumed)_' : ''} |`);
out.push(`| Packages scanned | ${s.totalPackages}${Object.keys(s.byEcosystem).length ? ` (${Object.entries(s.byEcosystem).map(([k, v]) => `${v} ${k}`).join(', ')})` : ''} |`);
out.push(`| Conflicts | ${s.conflictCount} |`);
out.push(`| Needs review | ${s.reviewCount} |`);
out.push(`| Unknown license | ${s.unknownCount} |`);
out.push(`| AGPL networked use | ${s.agplCount} |`);
out.push('');

if (flagged.length) {
  out.push('### Packages to look at');
  out.push('');
  out.push('| Package | Version | License | Category | Level | Reason |');
  out.push('|---|---|---|---|---|---|');
  for (const p of flagged.slice(0, ROW_CAP)) {
    // The report carries a stable reason code, not prose — the sentence for it
    // lives in the licenseproof package's own data file and in the HTML report.
    // Printing the code keeps this renderer honest and free of a copied copy of
    // that wording.
    const reason = [p.conflict.explanationKey, p.conflict.agplNetworkedUse ? 'agpl-networked-use' : null]
      .filter(Boolean)
      .join(', ');
    out.push(
      `| \`${esc(p.name)}\` | ${esc(p.version)} | ${esc(p.license)} | ${esc(p.category)} | ${esc(p.conflict.level)} | ${reason ? `\`${esc(reason)}\`` : ''} |`,
    );
  }
  out.push('');
  if (flagged.length > ROW_CAP) {
    out.push(`_${flagged.length - ROW_CAP} more flagged package(s) omitted from this table — see the uploaded \`report.json\` for all of them._`);
    out.push('');
  }
}

if (r.warnings && r.warnings.length) {
  out.push('### Warnings');
  out.push('');
  for (const w of r.warnings) out.push(`- ${w}`);
  out.push('');
}

out.push(
  `<sub>licenseproof ${esc(r.toolVersion)} · license data ${esc(r.dataVersion)} · scanned ${esc(r.scanTimestamp)} · informational, not legal advice</sub>`,
);
out.push('');

process.stdout.write(out.join('\n'));

fs.writeFileSync(
  outputsPath,
  [
    `outcome=${failed ? 'fail' : 'pass'}`,
    `total-packages=${s.totalPackages}`,
    `conflict-count=${s.conflictCount}`,
    `review-count=${s.reviewCount}`,
    `unknown-count=${s.unknownCount}`,
    `agpl-count=${s.agplCount}`,
    '',
  ].join('\n'),
);
