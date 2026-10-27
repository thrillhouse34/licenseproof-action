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

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi
echo "$FAILURES CHECK(S) FAILED"
exit 1
