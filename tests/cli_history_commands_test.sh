#!/usr/bin/env bash
set -euo pipefail

cli=$1
seed=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-history.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
"$seed" "$database"
common=(--database "$database" --format json --scope exercise-integration)

"$cli" "${common[@]}" workout start --command-id history-start --workout history-workout --started-at 2026-07-26T12:00:00Z --occurred-at 2026-07-26T12:00:00Z >/dev/null
"$cli" "${common[@]}" workout add-exercise bench-press --workout history-workout --command-id history-add --membership-id history-membership --occurred-at 2026-07-26T12:01:00Z >/dev/null
"$cli" "${common[@]}" set log --workout history-workout --exercise history-membership --set history-set --command-id history-log --occurred-at 2026-07-26T12:02:00Z 8r @8rpe >/dev/null
"$cli" "${common[@]}" workout finish --workout history-workout --command-id history-finish --occurred-at 2026-07-26T12:03:00Z >/dev/null

listed=$("$cli" "${common[@]}" history list --from 2026-07-26T12:00:00Z --through 2026-07-26T12:04:00Z)
grep -q '"kind":"caudex.history.list"' <<<"$listed"
grep -q 'history-workout' <<<"$listed"
shown=$("$cli" "${common[@]}" history show history-workout)
grep -q '"kind":"caudex.history.show"' <<<"$shown"
exercise=$("$cli" "${common[@]}" history exercise bench-press --limit 10)
grep -q 'history-workout' <<<"$exercise"
last=$("$cli" "${common[@]}" history last bench-press)
test "$last" = '{"schemaVersion":1,"kind":"caudex.history.last","data":{"workouts":[{"workoutId":"history-workout","revision":5,"completedAt":"2026-07-26T12:03:00Z","exerciseCount":1}]}}'

set +e
"$cli" "${common[@]}" history correct-set --workout history-workout --exercise history-membership --set history-set --command-id history-correct --occurred-at 2026-07-26T12:04:00Z 9r >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 2
corrected=$("$cli" "${common[@]}" history correct-set --yes --workout history-workout --exercise history-membership --set history-set --command-id history-correct --occurred-at 2026-07-26T12:04:00Z 9r)
grep -q '"kind":"caudex.history.set_corrected"' <<<"$corrected"
grep -q '"revision":6' <<<"$corrected"
