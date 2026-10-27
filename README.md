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

## Exit codes

The action exits with the CLI's own code, so the job status follows it:

| Code | Meaning |
|---|---|
| 0 | Nothing crossed the `fail-on` threshold. |
| 1 | Something did. `outcome` is `fail`; the report is still written and uploaded. |
| 2 | Usage or tool error — no project found at `path`, a bad `fail-on` value, an unreadable manifest. The CLI's message is on stderr. |

A failing scan still produces the artifact. That's the run you want it for.

## Notes

- Scanning is fully offline. The only network call is `npx` fetching the pinned
  `licenseproof` package from npm.
- `licenseproof scan` needs no license key. The paid `report` command (HTML, PDF,
  third-party notices, SPDX SBOM) is not wrapped by this action.
- Pin the action by tag (`@v1`) or by commit SHA, and pin the CLI with `version:` if you
  want the scan frozen across releases.

## Testing this action

`./scripts/simulate.sh` runs the action's real `scripts/run.sh` against
`fixtures/sample-repo` with a faked runner environment and asserts on the exit codes,
the job summary, and every output. If [`act`](https://github.com/nektos/act) is
installed it also runs `.github/workflows/test.yml` for real. CI runs the same script
plus the action itself, both the passing and the failing path.

## License

Elastic License 2.0 — see [LICENSE](LICENSE). Source-available, not open source.
