# Public tracking coverage audit (CWE-183)

This review covers the public `caudex_tracking` operations and the optional
SQLite implementation as of tracking contract 6 and schema 7.

## Demonstrated operations

| Public operation | Reference-client coverage |
| --- | --- |
| `startWorkout`, `completeWorkout`, `cancelWorkout` | Line commands, TUI session actions, subprocess and fake-terminal E2E tests |
| `readWorkout`, `listActiveWorkouts` | Line `workout show`, safe TUI dashboard zero/one/ambiguous states |
| `addExercise`, `reorderExercise` | Line add command; shared TUI add/reorder actions and screen tests |
| `addSet`, `completeSet`/`logSet`, `skipSet`, `reopenSet` | Line set commands; exact-metric TUI set screen; E2E harness |
| `listHistory`, `lastPerformance`, `correctSet` | Line history commands; bounded TUI history/detail/correction flows |
| `createExercise`, `editExercise`, `archiveExercise`, `restoreExercise` | Line catalog commands and typed TUI catalog actions |
| `readManagedExercise`, `searchExercises`, `listExercises` | Public resolution/search/list use cases and catalog/exercise picker tests |

## Intentional exclusions

- `removeExercise`, `removeSet`, and `reorderSet` remain public and tested at
  the tracking/adapter layer. They are intentionally absent from the current
  reference-client grammar because no reviewed destructive/removal UX or set
  ordering grammar has been approved.
- `replaceCatalog`, `appendCompletedWorkout`, catalog/history capability
  sources, and methodology state compare-and-set are host integration APIs,
  not interactive tracking commands. Public adapter tests demonstrate them.
- Metadata, integrity, backup, restore, and close are adapter lifecycle APIs;
  they are covered by database commands and the local-data TUI, not tracking
  screens.

## Desired but absent features

1. **Engine/application contract:** workout notes, catalog annotations/external
   IDs, stable history export, and any future reviewed remove/reorder command
   semantics must begin in public typed contracts.
2. **SQLite adapter:** encrypted storage or additional indexed query support
   would require explicit adapter APIs and migrations.
3. **Client:** richer filtering, layouts, and optional pointing-device input
   may be added without changing domain semantics.
4. **Out of scope:** recommendation generation inside the tracker, automatic
   workout generation, full periodization calendars, and inferred recovery or
   fatigue features are not invented by the reference client.

No client screen uses SQL, private tables, or duplicate workout rules to fill a
category 1 or category 2 gap.
