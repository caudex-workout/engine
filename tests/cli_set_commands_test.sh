#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init cli-set-commands

cli=$1
seed=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-sets.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
"$seed" "$database"
common=(--database "$database" --scope exercise-integration)

"$cli" "${common[@]}" workout start --command-id start-set-test \
  --workout workout-sets --started-at 2026-07-26T12:00:00Z \
  --occurred-at 2026-07-26T12:00:00Z >/dev/null
"$cli" "${common[@]}" workout add-exercise bench-press \
  --workout workout-sets --command-id add-exercise-set-test \
  --membership-id membership-bench --occurred-at 2026-07-26T12:01:00Z >/dev/null

logged=$("$cli" "${common[@]}" --format json set log 70kg 8r @2rir \
  --workout workout-sets --exercise membership-bench --set set-1 \
  --command-id log-set-test --occurred-at 2026-07-26T12:02:00Z)
grep -q '"kind":"caudex.set.logged"' <<<"$logged"
grep -q '"commandId":"log-set-test"' <<<"$logged"
grep -q '"revision":4' <<<"$logged"

"$cli" "${common[@]}" --quiet set reopen --workout workout-sets \
  --exercise membership-bench --set set-1 --command-id reopen-set-test \
  --occurred-at 2026-07-26T12:03:00Z | test ! -s /dev/stdin

skipped=$("$cli" "${common[@]}" --format json set skip --workout workout-sets \
  --exercise membership-bench --set set-1 --command-id skip-set-test \
  --occurred-at 2026-07-26T12:04:00Z)
grep -q '"kind":"caudex.set.skipped"' <<<"$skipped"

set +e
conflict=$("$cli" "${common[@]}" --format json set log 8r --reps 8 \
  --workout workout-sets --exercise membership-bench 2>&1 >/dev/null)
status=$?
set -e
test "$status" -eq 2
grep -q '"code":"client.invalid_arguments"' <<<"$conflict"

set +e
invalid_transition=$("$cli" "${common[@]}" --format json set log --reps 8 \
  --workout workout-sets --exercise membership-bench --set set-1 \
  --command-id invalid-transition --occurred-at 2026-07-26T12:05:00Z 2>&1 >/dev/null)
status=$?
set -e
test "$status" -eq 6
grep -q '"code":"tracking.invalid_set_transition"' <<<"$invalid_transition"
