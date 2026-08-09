#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI history commands" "test-cli-history"

cli=$1
seed=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-history.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
test_diagnostics_run_capture "fixture creation" "$seed" "$database"
test_diagnostics_assert_status "fixture creation" 0 "$test_diagnostics_last_status"
common=(--database "$database" --format json --scope exercise-integration)

test_diagnostics_run_capture "start history workout" "$cli" "${common[@]}" workout start \
  --command-id history-start --workout history-workout \
  --started-at 2026-07-26T12:00:00Z --occurred-at 2026-07-26T12:00:00Z
test_diagnostics_assert_status "start history workout" 0 "$test_diagnostics_last_status"

test_diagnostics_run_capture "add history exercise" "$cli" "${common[@]}" workout add-exercise bench-press \
  --workout history-workout --command-id history-add --membership-id history-membership \
  --occurred-at 2026-07-26T12:01:00Z
test_diagnostics_assert_status "add history exercise" 0 "$test_diagnostics_last_status"

test_diagnostics_run_capture "log history set" "$cli" "${common[@]}" set log \
  --workout history-workout --exercise history-membership --set history-set \
  --command-id history-log --occurred-at 2026-07-26T12:02:00Z 8r @8rpe
test_diagnostics_assert_status "log history set" 0 "$test_diagnostics_last_status"

test_diagnostics_run_capture "complete history workout" "$cli" "${common[@]}" workout finish \
  --workout history-workout --command-id history-finish --occurred-at 2026-07-26T12:03:00Z
test_diagnostics_assert_status "complete history workout" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "completion event kind" '"kind":"caudex.workout.finished"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "completion status" '"status":"completed"' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "history list" "$cli" "${common[@]}" history list \
  --from 2026-07-26T12:00:00Z --through 2026-07-26T12:04:00Z
test_diagnostics_assert_status "history list" 0 "$test_diagnostics_last_status"
listed=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "history list event kind" '"kind":"caudex.history.list"' "$listed"
test_diagnostics_assert_contains "history list workout" 'history-workout' "$listed"

test_diagnostics_run_capture "history show" "$cli" "${common[@]}" history show history-workout
test_diagnostics_assert_status "history show" 0 "$test_diagnostics_last_status"
shown=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "history show event kind" '"kind":"caudex.history.show"' "$shown"

test_diagnostics_run_capture "history exercise lookup" "$cli" "${common[@]}" history exercise bench-press --limit 10
test_diagnostics_assert_status "history exercise lookup" 0 "$test_diagnostics_last_status"
exercise=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "history exercise workout" 'history-workout' "$exercise"

test_diagnostics_run_capture "history last lookup" "$cli" "${common[@]}" history last bench-press
test_diagnostics_assert_status "history last lookup" 0 "$test_diagnostics_last_status"
last=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "history last result" \
  '{"schemaVersion":1,"kind":"caudex.history.last","data":{"workouts":[{"workoutId":"history-workout","revision":5,"completedAt":"2026-07-26T12:03:00Z","exerciseCount":1}]}}' \
  "$last"

test_diagnostics_run_capture "correction confirmation guard" "$cli" "${common[@]}" history correct-set \
  --workout history-workout --exercise history-membership --set history-set \
  --command-id history-correct --occurred-at 2026-07-26T12:04:00Z 9r
test_diagnostics_assert_status "correction confirmation guard" 2 "$test_diagnostics_last_status"

test_diagnostics_run_capture "correct history set" "$cli" "${common[@]}" history correct-set --yes \
  --workout history-workout --exercise history-membership --set history-set \
  --command-id history-correct --occurred-at 2026-07-26T12:04:00Z 9r
test_diagnostics_assert_status "correct history set" 0 "$test_diagnostics_last_status"
corrected=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "correction event kind" '"kind":"caudex.history.set_corrected"' "$corrected"
test_diagnostics_assert_contains "correction revision" '"revision":6' "$corrected"
