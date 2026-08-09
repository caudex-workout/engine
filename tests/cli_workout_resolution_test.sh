#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI workout resolution"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-resolution.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --format json --scope resolution)

test_diagnostics_run_capture "zero-workout resolution guard" "$cli" "${common[@]}" workout show
test_diagnostics_assert_status "zero-workout resolution guard" 4 "$test_diagnostics_last_status"
test_diagnostics_assert_equal "zero-workout resolution error" \
  '{"schemaVersion":1,"kind":"caudex.error","error":{"code":"tracking.workout_not_found","category":"not_found","message":"No active workout matched; pass --workout with a stable ID."}}' \
  "$test_diagnostics_last_stderr"

test_diagnostics_run_capture "start first resolution workout" "$cli" "${common[@]}" workout start \
  --command-id command-one --workout workout-one \
  --started-at 2026-07-26T12:00:00Z \
  --occurred-at 2026-07-26T12:00:00Z
test_diagnostics_assert_status "start first resolution workout" 0 "$test_diagnostics_last_status"
test_diagnostics_run_capture "resolve first workout" "$cli" "${common[@]}" workout show
test_diagnostics_assert_status "resolve first workout" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_equal "first workout resolution" \
  '{"schemaVersion":1,"kind":"caudex.workout.show","data":{"workoutId":"workout-one","hostScopeKey":"resolution","revision":1,"status":"active","startedAt":"2026-07-26T12:00:00Z","exercises":[]}}' \
  "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "start second resolution workout" "$cli" "${common[@]}" workout start \
  --command-id command-two --workout workout-two \
  --started-at 2026-07-26T12:01:00Z \
  --occurred-at 2026-07-26T12:01:00Z
test_diagnostics_assert_status "start second resolution workout" 0 "$test_diagnostics_last_status"
test_diagnostics_run_capture "ambiguous workout resolution guard" "$cli" "${common[@]}" workout show
test_diagnostics_assert_status "ambiguous workout resolution guard" 5 "$test_diagnostics_last_status"
test_diagnostics_assert_equal "ambiguous workout resolution error" \
  '{"schemaVersion":1,"kind":"caudex.error","error":{"code":"client.active_workout_ambiguous","category":"ambiguity","message":"Multiple active workouts matched; pass --workout with one candidate ID.","details":{"candidateIds":["workout-one","workout-two"]}}}' \
  "$test_diagnostics_last_stderr"
