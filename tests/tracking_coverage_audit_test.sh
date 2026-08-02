#!/usr/bin/env bash
set -euo pipefail
audit=docs/tracking/coverage-audit-cwe-183.md
for operation in startWorkout completeWorkout cancelWorkout readWorkout listActiveWorkouts addExercise reorderExercise addSet completeSet logSet skipSet reopenSet listHistory lastPerformance correctSet createExercise editExercise archiveExercise restoreExercise readManagedExercise searchExercises listExercises removeExercise removeSet reorderSet; do
  grep -Fq "\`$operation\`" "$audit"
done
for category in 'Engine/application contract' 'SQLite adapter' 'Client' 'Out of scope'; do
  grep -Fq "**$category:**" "$audit"
done
grep -Fq 'recommendation generation inside the tracker' "$audit"
grep -Fq 'full periodization calendars' "$audit"
