#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI workout start"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-start.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"

common=(
  --database "$database"
  --format json
  --scope integration
)
start=(
  workout start
  --command-id command-integration-start
  --workout workout-integration
  --started-at 2026-07-26T12:00:00Z
  --occurred-at 2026-07-26T12:00:00Z
)

expected_applied='{"schemaVersion":1,"kind":"caudex.workout.start","data":{"commandId":"command-integration-start","disposition":"applied","workoutId":"workout-integration","hostScopeKey":"integration","revision":1,"status":"active","startedAt":"2026-07-26T12:00:00Z"}}'
expected_show='{"schemaVersion":1,"kind":"caudex.workout.show","data":{"workoutId":"workout-integration","hostScopeKey":"integration","revision":1,"status":"active","startedAt":"2026-07-26T12:00:00Z","exercises":[]}}'
expected_replayed='{"schemaVersion":1,"kind":"caudex.workout.start","data":{"commandId":"command-integration-start","disposition":"replayed","workoutId":"workout-integration","hostScopeKey":"integration","revision":1,"status":"active","startedAt":"2026-07-26T12:00:00Z"}}'

test_diagnostics_run_capture "start applied" "$cli" "${common[@]}" "${start[@]}"
test_diagnostics_assert_status "start applied" 0 "$test_diagnostics_last_status"
actual_applied=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "start applied response" "$expected_applied" "$actual_applied"

test_diagnostics_run_capture "show started workout" "$cli" "${common[@]}" workout show --workout workout-integration
test_diagnostics_assert_status "show started workout" 0 "$test_diagnostics_last_status"
actual_show=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "show started workout response" "$expected_show" "$actual_show"

test_diagnostics_run_capture "replay start command" "$cli" "${common[@]}" "${start[@]}"
test_diagnostics_assert_status "replay start command" 0 "$test_diagnostics_last_status"
actual_replayed=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "replayed start response" "$expected_replayed" "$actual_replayed"

test_diagnostics_run_capture "show workout after retry" "$cli" "${common[@]}" workout show --workout workout-integration
test_diagnostics_assert_status "show workout after retry" 0 "$test_diagnostics_last_status"
actual_show_after_retry=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "show workout after retry response" "$expected_show" "$actual_show_after_retry"
