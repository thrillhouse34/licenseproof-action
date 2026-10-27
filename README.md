# LicenseProof Action

Know every license in your dependency tree — before your customer's lawyer asks.

This action runs the [`licenseproof`](https://www.npmjs.com/package/licenseproof) CLI
against your checked-out repository, writes the result to the job summary, uploads it
as a build artifact, and fails the job when it finds something you said you cared about.

It is a **composite** action: `licenseproof` is already published to npm, so the action
is a thin wrapper that `npx`-runs a pinned version (`0.3.3`). No bundled `node_modules`
to keep in sync, and the thing the action runs is byte-for-byte the release you can run
locally yourself.

LicenseProof is **source-available** under the [Elastic License 2.0](LICENSE).
Its output is informational and is not legal advice.

## Usage

```yaml
name: licenses

on: [push, pull_request]

permissions:
  contents: read

jobs:
  licenses:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: thrillhouse34/licenseproof-action@v1
```

That's the whole thing. The defaults scan the repository root, ignore
`devDependencies`, and fail the job only on a real conflict with your own project
license.

### Fail on anything that needs a human

```yaml
      - uses: thrillhouse34/licenseproof-action@v1
        with:
          fail-on: review        # conflicts, copyleft to review, and unknown licenses
```

### Report without ever failing the build

```yaml
      - uses: thrillhouse34/licenseproof-action@v1
        with:
          fail-on: never
```

### Also generate the paid report

If you have a licenseproof key, put it in a repository secret and pass it in.
The free scan runs exactly as before; the full report is generated on top and
uploaded as its own artifact.

```yaml
      - uses: thrillhouse34/licenseproof-action@v1
        with:
          license-key: ${{ secrets.LICENSEPROOF_LICENSE_KEY }}
```

Never paste the key in as a literal — always a secret. See
[The paid report](#the-paid-report) below for what you get and how it fails.

### Scan a subdirectory, include dev dependencies, use the outputs

```yaml
      - id: licenses
        uses: thrillhouse34/licenseproof-action@v1
        with:
          path: packages/api
          include-dev: 'true'
          project-license: 'Apache-2.0'   # your manifest says UNLICENSED, you ship Apache
          fail-on: never
      - run: echo "${{ steps.licenses.outputs.conflict-count }} conflicts in the API package"
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Project path to scan, relative to the workspace. Needs a `package.json`/lockfile (npm) or a Python manifest (PyPI). |
| `fail-on` | `conflict` | When to fail the job: `conflict`, `review`, or `never`. Any other value is rejected with exit 2 rather than silently defaulted. |
| `include-dev` | `false` | `true` to include `devDependencies`. Production dependencies only otherwise. |
| `project-license` | _(empty)_ | SPDX id or expression for your own project, overriding `package.json`. Set it when your manifest says `UNLICENSED` but you ship under something real — the conflict rules key off this. |
| `version` | `0.3.3` | Version of the `licenseproof` npm package to run. Pinned; override only to try a newer release. |
| `out` | _(empty)_ | Directory for `report.json` and `summary.md`. Defaults to a directory under the runner temp dir, so your checkout stays clean. |
| `summary` | `true` | `false` to skip writing to the job summary. |
| `upload-artifact` | `true` | `false` to skip the artifact upload. |
| `artifact-name` | `licenseproof-report` | Name of the uploaded artifact. Give each job a distinct name if you run the action more than once in one workflow. |
| `artifact-retention-days` | `0` | Days before the uploaded artifact expires. `0` uses the repository default. |
| `license-key` | _(empty)_ | Your paid licenseproof key, which also generates the full report. Pass it from a secret, never as a literal. Empty means free scan only — which is the supported, normal configuration, not a degraded one. |
| `report-formats` | `html,pdf,notices,sbom-cyclonedx,sbom-spdx` | Paid report formats to generate, comma-separated. Only read when `license-key` is set. |
| `report-out` | _(empty)_ | Directory for the paid report artifacts. Defaults to a directory under the runner temp dir. |
| `report-artifact-name` | `licenseproof-full-report` | Name of the uploaded paid-report artifact. Separate from `artifact-name` so the free report and the paid pack download independently. |

## Outputs

| Output | Description |
|---|---|
| `outcome` | `pass` or `fail` — whether the scan tripped the `fail-on` threshold. Written before the action exits, so pair the step with `continue-on-error: true` if you want to read it on a failing scan. |
| `total-packages` | Number of packages scanned. |
| `conflict-count` | Packages whose license conflicts with your project license. |
| `review-count` | Packages needing a human look (not counting unknowns). |
| `unknown-count` | Packages whose license could not be resolved. |
| `agpl-count` | Packages carrying an AGPL networked-use obligation. |
| `report-path` | Absolute path to the machine-readable `report.json`. |
| `summary-path` | Absolute path to the Markdown summary. |
| `report-generated` | `true` when the paid report was generated. Empty when no `license-key` was supplied. |
| `report-dir` | Absolute path to the directory holding the paid report artifacts. Empty when no `license-key` was supplied. |

## What the report looks like

The job summary gets a verdict line, a counts table, and a row per package that needs
a decision:

> ## ❌ LicenseProof — acme-sample-app
>
> Failed on `--fail-on review`. 2 package(s) below need a decision.
>
> | | |
> |---|---|
> | Project license | `MIT` |
> | Packages scanned | 3 (3 npm) |
> | Conflicts | 0 |
> | Needs review | 1 |
> | Unknown license | 1 |
> | AGPL networked use | 0 |
>
> ### Packages to look at
>
> | Package | Version | License | Category | Level | Reason |
> |---|---|---|---|---|---|
> | `copyleft-tool` | 2.1.0 | GPL-3.0-or-later | strong-copyleft | REVIEW | `copyleft-in-permissive-project` |
> | `mystery-lib` | 0.1.2 | UNKNOWN | unknown | REVIEW | `unknown-review` |

The `Reason` column is the report's stable reason code. The sentence that explains each
code is in the HTML report from `licenseproof report`, and in the CLI's own terminal
output when you run `licenseproof scan` locally.

Clean runs get the same thing with a ✅ and no package table. Trees with more than 50
flagged packages get the first 50 in the table and a line saying how many were left out
— the full set is always in `report.json`.

The uploaded artifact holds both files:

- `report.json` — the full `licenseproof scan --format json` report (`schemaVersion: 1`):
  every package with its resolved license, SPDX ids, category, confidence, resolution
  source, conflict verdict, and dependency paths, plus the summary counts and any
  warnings.
- `summary.md` — the Markdown above, for pasting into a ticket.

## The paid report

The free scan answers "is there a problem". The paid report is the document you
hand to the customer's lawyer: `report.html`, `report.pdf`, a
`THIRD_PARTY_NOTICES.txt`, and an SPDX SBOM, all regenerated from the same scan.
It needs a licenseproof key — one perpetual purchase, no subscription, from
[licenseproof.dev](https://licenseproof.dev).

```yaml
      - uses: thrillhouse34/licenseproof-action@v1
        with:
          license-key: ${{ secrets.LICENSEPROOF_LICENSE_KEY }}
          report-formats: html,pdf        # narrow it if you don't want all five
```

It is **one extra input on the same action**, not a second action. That is a
deliberate choice: the paid artifacts are rendered from the same dependency scan
the free step already did, so a separate action would have to redo that work and
could then disagree with the step above it about what is in your tree. One
`uses:` line, one scan, one source of truth.

### How it behaves

- **No key is the normal case.** Leave `license-key` empty, or point it at a
  secret that isn't set, and the action is exactly the free scan — no paid step,
  no warning, no failure. The job summary gets a one-line pointer to the paid
  report, which disappears as soon as a key is configured.
- **A rejected key fails the job**, with a message naming the likely causes and
  nothing written. It does not silently fall back to the free scan: you asked
  for the report, and a release going out without the pack you thought you had
  generated is worse than a red build. Put `continue-on-error: true` on the step
  if you would rather it were advisory.
- **The free verdict is never affected.** The scan runs first and publishes its
  outputs and job summary before the report step is reached, so a key problem
  can't change, hide, or invalidate the free result.
- **The report runs even when the scan failed the build.** A tripped `fail-on`
  threshold is the run you most want the full report for.

### What happens to your key

- It is passed to the action in an `env:` block, which the runner does not log,
  and it is read from `$LICENSEPROOF_KEY` — never put on a command line, where
  any process on the runner could read it out of `ps`.
- `::add-mask::` is emitted before any other output, so the runner redacts the
  value from the log even if something later were to print it.
- It is never written to the job summary, to any action output, or to any
  uploaded artifact. The generated artifacts are searched for the key, and the
  upload is refused outright if it is found — a check, not an assumption.
- Keys live in repository secrets. A secret is not readable by workflows from
  forked pull requests, which is the behaviour you want here.

## Exit codes

The action exits with the CLI's own code, so the job status follows it:

| Code | Meaning |
|---|---|
| 0 | Nothing crossed the `fail-on` threshold. |
| 1 | Something did. `outcome` is `fail`; the report is still written and uploaded. |
| 2 | Usage or tool error — no project found at `path`, a bad `fail-on` value, an unreadable manifest. The CLI's message is on stderr. |
| 3 | A `license-key` was supplied and rejected. No paid artifacts were written. The free scan's result still stands. |

A failing scan still produces the artifact. That's the run you want it for.

## Notes

- Scanning is fully offline. The only network call is `npx` fetching the pinned
  `licenseproof` package from npm.
- `licenseproof scan` needs no license key. The paid `report` command (HTML, PDF,
  third-party notices, SPDX SBOM) is wrapped too, but only runs when you supply
  one — see [The paid report](#the-paid-report).
- Pin the action by tag (`@v1`) or by commit SHA, and pin the CLI with `version:` if you
  want the scan frozen across releases.

## Testing this action

`./scripts/simulate.sh` runs the action's real `scripts/run.sh` against
`fixtures/sample-repo` with a faked runner environment and asserts on the exit codes,
the job summary, and every output. It also drives `scripts/report.sh` with a
deliberately invalid key, asserting that the refusal is clean, that nothing is
written, and that the key reaches no output other than the `::add-mask::` line
that exists to redact it. If [`act`](https://github.com/nektos/act) is installed
it also runs `.github/workflows/test.yml` for real. CI runs the same script plus
the action itself four ways: passing, failing, with a bad key, and with no key.

## Maintainer notes

Not for users of the action — for whoever maintains it.

### Bumping the pinned CLI version

The npm version is pinned in five places: `action.yml`'s `version` input
default, `scripts/run.sh`'s fallback, `scripts/report.sh`'s fallback, and this
README (twice). Don't edit them by hand:

```sh
./scripts/bump.sh 0.3.4
```

It reads the current version out of `action.yml` (the single source of truth),
refuses to proceed unless `licenseproof@<new>` is actually published to npm,
rewrites all four places, warns about any stale pin it didn't know about, and
then prints the commit, release and tag commands. It never pushes, tags or
publishes anything itself.

### If the Marketplace name is taken

An action's `name:` has to be unique across the whole GitHub Marketplace, and
must not collide with an existing GitHub user or organisation. GitHub only tells
you at release time. If `LicenseProof` is rejected, the fallback is one line in
`action.yml`:

```yaml
name: 'LicenseProof License Scan'
```

Nothing else changes — the name is a display label, not the `uses:` path, which
comes from the repository name. The README's usage examples stay correct.

## License

Elastic License 2.0 — see [LICENSE](LICENSE). Source-available, not open source.
