#!/usr/bin/env bash
set -euo pipefail

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

actual_applied=$("$cli" "${common[@]}" "${start[@]}")
test "$actual_applied" = "$expected_applied"

actual_show=$("$cli" "${common[@]}" workout show --workout workout-integration)
test "$actual_show" = "$expected_show"

actual_replayed=$("$cli" "${common[@]}" "${start[@]}")
test "$actual_replayed" = "$expected_replayed"

actual_show_after_retry=$("$cli" "${common[@]}" workout show --workout workout-integration)
test "$actual_show_after_retry" = "$expected_show"
