#!/usr/bin/env bash
#
# Local test. Runs scripts/run.sh — the same script action.yml runs — against
# fixtures/sample-repo with a faked runner environment ($GITHUB_STEP_SUMMARY,
# $GITHUB_OUTPUT, $RUNNER_TEMP), then asserts on what it wrote.
#
#   ./scripts/simulate.sh
#
# Needs node and network access on the first run (npx fetches the pinned
# licenseproof from npm; later runs hit the npx cache). The only thing it cannot
# cover is the actions/upload-artifact step, which has no local equivalent.
#
# Prefers `act` when it is installed, since that runs the real action.yml.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
FAILURES=0

if command -v act >/dev/null 2>&1; then
  echo "== act detected: running the real workflow =="
  act -W .github/workflows/test.yml || FAILURES=$((FAILURES + 1))
  echo
fi

TMP="$(mktemp -d)" || exit 1
echo "scratch: $TMP"

ok()   { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1"; FAILURES=$((FAILURES + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else fail "$1: expected '$3', got '$2'"; fi; }

# ── case 0: no ${{ }} in action.yml outside runs: and outputs.*.value
#
# The runner evaluates the expressions in action.yml's metadata before the
# action runs, and `secrets` is not in scope there. So a `${{ secrets.X }}`
# written into an input description as documentation is not an example — it is
# an expression the runner tries and cannot resolve, and the action then fails
# to load for every user ("Unrecognized named-value: 'secrets'"). That shipped
# once. This catches it before a commit does.
#
# Valid: anything under `runs:`, and the `value:` of each output. Everywhere
# else in the file, a `${{` is a bug — quote the expression as plain text.
echo "== case 0: action.yml has no \${{ }} outside runs: and outputs.*.value =="
STRAY=$(awk '
  /^outputs:/ { section = "outputs"; next }
  /^runs:/    { section = "runs";    next }
  section == "runs"                             { next }
  index($0, "${{") == 0                         { next }
  section == "outputs" && $0 ~ /^    value: /   { next }
  { printf "%d: %s\n", NR, $0 }
' "$ROOT/action.yml")
if [ -z "$STRAY" ]; then
  ok "no expressions outside runs: and outputs.*.value"
else
  fail "action.yml has \${{ }} where the runner cannot evaluate it:"
  echo "$STRAY" | sed 's/^/         /'
fi
echo

# ── case 1: fail-on review — the fixture has 1 review + 1 unknown, so this fails
echo "== case 1: fail-on review (expect the job to fail) =="
RUN_DIR="$TMP/review"
mkdir -p "$RUN_DIR"
export GITHUB_STEP_SUMMARY="$RUN_DIR/step-summary.md"
export GITHUB_OUTPUT="$RUN_DIR/outputs.txt"
export RUNNER_TEMP="$RUN_DIR"
: > "$GITHUB_STEP_SUMMARY"
: > "$GITHUB_OUTPUT"

INPUT_PATH="fixtures/sample-repo" \
INPUT_FAIL_ON="review" \
  bash "$ROOT/scripts/run.sh" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt"
RC=$?
sed 's/^/    | /' "$RUN_DIR/stderr.txt"

get() { grep -m1 "^$1=" "$GITHUB_OUTPUT" | cut -d= -f2-; }

check "exit code" "$RC" "1"
check "outcome output" "$(get outcome)" "fail"
check "total-packages output" "$(get total-packages)" "3"
check "conflict-count output" "$(get conflict-count)" "0"
check "review-count output" "$(get review-count)" "1"
check "unknown-count output" "$(get unknown-count)" "1"

REPORT_PATH="$(get report-path)"
if [ -s "$REPORT_PATH" ]; then ok "report.json written ($REPORT_PATH)"; else fail "report.json missing at '$REPORT_PATH'"; fi
if [ -s "$(get summary-path)" ]; then ok "summary.md written"; else fail "summary.md missing"; fi

if [ -s "$GITHUB_STEP_SUMMARY" ]; then ok "job summary written"; else fail "job summary is empty"; fi
for want in "LicenseProof" "copyleft-tool" "mystery-lib" "Needs review"; do
  if grep -q "$want" "$GITHUB_STEP_SUMMARY"; then ok "job summary mentions $want"; else fail "job summary is missing '$want'"; fi
done
if grep -q '^## ❌' "$GITHUB_STEP_SUMMARY"; then ok "job summary marked failed"; else fail "job summary not marked failed"; fi

# ── case 2: fail-on conflict (the default) — no conflicts, so this passes
echo
echo "== case 2: fail-on conflict (expect the job to pass) =="
RUN_DIR="$TMP/conflict"
mkdir -p "$RUN_DIR"
export GITHUB_STEP_SUMMARY="$RUN_DIR/step-summary.md"
export GITHUB_OUTPUT="$RUN_DIR/outputs.txt"
export RUNNER_TEMP="$RUN_DIR"
: > "$GITHUB_STEP_SUMMARY"
: > "$GITHUB_OUTPUT"

INPUT_PATH="fixtures/sample-repo" \
  bash "$ROOT/scripts/run.sh" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt"
RC=$?
check "exit code" "$RC" "0"
check "outcome output" "$(get outcome)" "pass"
if grep -q '^## ✅' "$GITHUB_STEP_SUMMARY"; then ok "job summary marked passed"; else fail "job summary not marked passed"; fi

# ── case 3: a bad fail-on value is rejected, not silently defaulted
echo
echo "== case 3: invalid fail-on (expect exit 2) =="
INPUT_PATH="fixtures/sample-repo" INPUT_FAIL_ON="whenever" \
  bash "$ROOT/scripts/run.sh" > /dev/null 2>&1
check "exit code" "$?" "2"

# ── case 4: a path with no project at all is a tool error, not a false pass
echo
echo "== case 4: path with no project (expect a non-zero tool error) =="
RUN_DIR="$TMP/empty"
mkdir -p "$RUN_DIR/nothing-here"
export RUNNER_TEMP="$RUN_DIR"
unset GITHUB_STEP_SUMMARY GITHUB_OUTPUT
INPUT_PATH="$RUN_DIR/nothing-here" \
  bash "$ROOT/scripts/run.sh" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt"
RC=$?
if [ "$RC" -ne 0 ]; then ok "exit code non-zero ($RC)"; else fail "a project-less path exited 0"; fi

# ── case 5: the upsell appears for someone with no key, and only for them
echo
echo "== case 5: upsell in the job summary (no license key) =="
RUN_DIR="$TMP/upsell"
mkdir -p "$RUN_DIR"
export GITHUB_STEP_SUMMARY="$RUN_DIR/step-summary.md"
export GITHUB_OUTPUT="$RUN_DIR/outputs.txt"
export RUNNER_TEMP="$RUN_DIR"
: > "$GITHUB_STEP_SUMMARY"
: > "$GITHUB_OUTPUT"

INPUT_PATH="fixtures/sample-repo" INPUT_FAIL_ON="never" \
  bash "$ROOT/scripts/run.sh" > /dev/null 2>&1

if grep -q "Get the full report" "$GITHUB_STEP_SUMMARY"; then ok "upsell shown without a key"; else fail "upsell missing from the job summary"; fi
if grep -q "licenseproof.dev" "$GITHUB_STEP_SUMMARY"; then ok "upsell links the existing purchase page"; else fail "upsell has no licenseproof.dev link"; fi

echo
echo "== case 6: no upsell once a key is configured =="
RUN_DIR="$TMP/no-upsell"
mkdir -p "$RUN_DIR"
export GITHUB_STEP_SUMMARY="$RUN_DIR/step-summary.md"
export GITHUB_OUTPUT="$RUN_DIR/outputs.txt"
export RUNNER_TEMP="$RUN_DIR"
: > "$GITHUB_STEP_SUMMARY"
: > "$GITHUB_OUTPUT"

# A boolean, not a key — this is exactly what action.yml passes run.sh.
INPUT_PATH="fixtures/sample-repo" INPUT_FAIL_ON="never" INPUT_HAS_LICENSE_KEY="true" \
  bash "$ROOT/scripts/run.sh" > /dev/null 2>&1

if grep -q "Get the full report" "$GITHUB_STEP_SUMMARY"; then fail "a paid customer was shown the upsell"; else ok "upsell suppressed with a key configured"; fi
if grep -q "Packages scanned" "$GITHUB_STEP_SUMMARY"; then ok "the rest of the summary is unchanged"; else fail "the summary lost its counts table"; fi

# ── case 7: the paid path refuses a bad key cleanly, and never echoes it
echo
echo "== case 7: paid report with an invalid key (expect exit 3, nothing written, no key leak) =="
RUN_DIR="$TMP/badkey"
mkdir -p "$RUN_DIR"
export RUNNER_TEMP="$RUN_DIR"
export GITHUB_OUTPUT="$RUN_DIR/outputs.txt"
unset GITHUB_STEP_SUMMARY
: > "$GITHUB_OUTPUT"

# Deliberately not a real key, and not a real key's shape beyond being a
# plausible-looking string. Nothing in this repo ever holds a working key.
FAKE_KEY="not-a-real-licenseproof-key-cafef00d"
REPORT_OUT="$RUN_DIR/full-report"

LICENSEPROOF_KEY="$FAKE_KEY" INPUT_PATH="fixtures/sample-repo" INPUT_REPORT_OUT="$REPORT_OUT" \
  bash "$ROOT/scripts/report.sh" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt"
RC=$?
sed 's/^/    | /' "$RUN_DIR/stderr.txt"

check "exit code" "$RC" "3"
if grep -q "license key was not accepted" "$RUN_DIR/stderr.txt"; then ok "the refusal says what went wrong"; else fail "the refusal message is missing"; fi
if grep -q "licenseproof.dev" "$RUN_DIR/stderr.txt"; then ok "the refusal points at the purchase page"; else fail "the refusal has no purchase link"; fi

# The one thing that must never happen. The ::add-mask:: line is the single
# deliberate exception and is excluded here: that line HAS to carry the key
# verbatim — it is how the runner learns what string to redact — and the runner
# strips it from the visible log. Every OTHER occurrence would be a real leak.
grep -v "^::add-mask::" "$RUN_DIR/stdout.txt" > "$RUN_DIR/stdout-unmasked.txt"
if grep -qF "$FAKE_KEY" "$RUN_DIR/stdout-unmasked.txt" "$RUN_DIR/stderr.txt" "$GITHUB_OUTPUT" 2>/dev/null; then
  fail "THE KEY LEAKED into stdout, stderr or \$GITHUB_OUTPUT"
else
  ok "the key appears nowhere but the ::add-mask:: line"
fi
if [ -n "$(ls -A "$REPORT_OUT" 2>/dev/null)" ]; then fail "artifacts were written despite the bad key"; else ok "nothing written on refusal"; fi
if grep -q "^report-generated=" "$GITHUB_OUTPUT" 2>/dev/null; then fail "report-generated was set despite the refusal"; else ok "report-generated not set"; fi

# The masking directive has to be the first thing the runner sees, before any
# other line exists that could contain the key.
if [ "$(head -1 "$RUN_DIR/stdout.txt")" = "::add-mask::$FAKE_KEY" ]; then
  ok "::add-mask:: is emitted first, before any other output"
else
  fail "::add-mask:: is not the first line of stdout (got: $(head -1 "$RUN_DIR/stdout.txt"))"
fi

# ── case 8: report.sh called with no key at all is a bug, not a silent pass
echo
echo "== case 8: report.sh with an empty key (expect exit 2) =="
LICENSEPROOF_KEY="" INPUT_PATH="fixtures/sample-repo" INPUT_REPORT_OUT="$TMP/nokey-out" \
  bash "$ROOT/scripts/report.sh" > /dev/null 2>&1
check "exit code" "$?" "2"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi
echo "$FAILURES CHECK(S) FAILED"
exit 1
