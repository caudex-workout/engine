#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI workout completion" "test-cli-workout-end"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-end.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --scope end-integration --format json)

test_diagnostics_run_capture "start workout" "$cli" "${common[@]}" workout start \
  --command-id start-finish --workout workout-finish \
  --started-at 2026-07-26T12:00:00Z --occurred-at 2026-07-26T12:00:00Z
test_diagnostics_assert_status "start workout" 0 "$test_diagnostics_last_status"

test_diagnostics_run_capture "finish workout" "$cli" "${common[@]}" workout finish \
  --workout workout-finish --command-id finish-short --occurred-at 2026-07-26T12:01:00Z
test_diagnostics_assert_status "finish workout" 0 "$test_diagnostics_last_status"
finished=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "completion event kind" '"kind":"caudex.workout.finished"' "$finished"
test_diagnostics_assert_contains "completion status" '"status":"completed"' "$finished"

test_diagnostics_run_capture "start cancellation fixture" "$cli" "${common[@]}" workout start \
  --command-id start-cancel --workout workout-cancel \
  --started-at 2026-07-26T12:02:00Z --occurred-at 2026-07-26T12:02:00Z
test_diagnostics_assert_status "start cancellation fixture" 0 "$test_diagnostics_last_status"

test_diagnostics_run_capture "cancel without confirmation" "$cli" "${common[@]}" workout cancel \
  --workout workout-cancel
test_diagnostics_assert_status "cancel without confirmation" 2 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "confirmation rejection" '"code":"client.confirmation_required"' "$test_diagnostics_last_stderr"

test_diagnostics_run_capture "show cancelled workout before confirmation" "$cli" "${common[@]}" workout show \
  --workout workout-cancel
test_diagnostics_assert_status "show cancelled workout before confirmation" 0 "$test_diagnostics_last_status"
still_active=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "workout remains active" '"status":"active"' "$still_active"

test_diagnostics_run_capture "confirm cancellation" "$cli" "${common[@]}" workout cancel \
  --workout workout-cancel --yes \
  --command-id cancel-confirmed --occurred-at 2026-07-26T12:03:00Z
test_diagnostics_assert_status "confirm cancellation" 0 "$test_diagnostics_last_status"
cancelled=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "cancellation event kind" '"kind":"caudex.workout.cancelled"' "$cancelled"
test_diagnostics_assert_contains "cancellation status" '"status":"cancelled"' "$cancelled"
