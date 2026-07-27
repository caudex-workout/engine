#!/usr/bin/env bash
set -euo pipefail

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-resolution.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --format json --scope resolution)

set +e
zero_error=$("$cli" "${common[@]}" workout show 2>&1)
zero_status=$?
set -e
test "$zero_status" = 4
test "$zero_error" = '{"schemaVersion":1,"kind":"caudex.error","error":{"code":"tracking.workout_not_found","category":"not_found","message":"No active workout matched; pass --workout with a stable ID."}}'

"$cli" "${common[@]}" workout start \
  --command-id command-one --workout workout-one \
  --started-at 2026-07-26T12:00:00Z \
  --occurred-at 2026-07-26T12:00:00Z >/dev/null
one=$("$cli" "${common[@]}" workout show)
test "$one" = '{"schemaVersion":1,"kind":"caudex.workout.show","data":{"workoutId":"workout-one","hostScopeKey":"resolution","revision":1,"status":"active","startedAt":"2026-07-26T12:00:00Z"}}'

"$cli" "${common[@]}" workout start \
  --command-id command-two --workout workout-two \
  --started-at 2026-07-26T12:01:00Z \
  --occurred-at 2026-07-26T12:01:00Z >/dev/null
set +e
many_error=$("$cli" "${common[@]}" workout show 2>&1)
many_status=$?
set -e
test "$many_status" = 5
test "$many_error" = '{"schemaVersion":1,"kind":"caudex.error","error":{"code":"client.active_workout_ambiguous","category":"ambiguity","message":"Multiple active workouts matched; pass --workout with one candidate ID.","details":{"candidateIds":["workout-one","workout-two"]}}}'
