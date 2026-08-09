#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init cli-add-exercise

cli=$1
seed=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-exercise.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
"$seed" "$database"
common=(--database "$database" --format json --scope exercise-integration)

"$cli" "${common[@]}" workout start \
  --command-id command-start --workout workout-exercise \
  --started-at 2026-07-26T12:00:00Z \
  --occurred-at 2026-07-26T12:00:00Z >/dev/null

added=$("$cli" "${common[@]}" workout add-exercise "Bench Press" \
  --workout workout-exercise \
  --command-id command-add-bench \
  --membership-id membership-bench \
  --occurred-at 2026-07-26T12:01:00Z)
test "$added" = '{"schemaVersion":1,"kind":"caudex.workout.exercise_added","data":{"commandId":"command-add-bench","disposition":"applied","workoutId":"workout-exercise","hostScopeKey":"exercise-integration","revision":2,"status":"active","startedAt":"2026-07-26T12:00:00Z","exercises":[{"membershipId":"membership-bench","exerciseId":"bench-press","setCount":0}]}}'

shown=$("$cli" "${common[@]}" workout show --workout workout-exercise)
test "$shown" = '{"schemaVersion":1,"kind":"caudex.workout.show","data":{"workoutId":"workout-exercise","hostScopeKey":"exercise-integration","revision":2,"status":"active","startedAt":"2026-07-26T12:00:00Z","exercises":[{"membershipId":"membership-bench","exerciseId":"bench-press","setCount":0}]}}'

human=$("$cli" --database "$database" --scope exercise-integration \
  workout show --workout workout-exercise)
test "${#human}" -lt 400
grep -q '^Exercises:$' <<<"$human"
grep -q 'bench-press  membership=membership-bench  sets=0' <<<"$human"
