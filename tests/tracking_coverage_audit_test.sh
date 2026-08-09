#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init tracking-coverage-audit
audit=docs/tracking/coverage-audit-cwe-183.md
for operation in startWorkout completeWorkout cancelWorkout readWorkout listActiveWorkouts addExercise reorderExercise addSet completeSet logSet skipSet reopenSet listHistory lastPerformance correctSet createExercise editExercise archiveExercise restoreExercise readManagedExercise searchExercises listExercises removeExercise removeSet reorderSet; do
  grep -Fq "\`$operation\`" "$audit"
done
for category in 'Engine/application contract' 'SQLite adapter' 'Client' 'Out of scope'; do
  grep -Fq "**$category:**" "$audit"
done
grep -Fq 'recommendation generation inside the tracker' "$audit"
grep -Fq 'full periodization calendars' "$audit"
