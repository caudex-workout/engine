# History and correction contract

Status: accepted for CWE-133.

`caudex_tracking.HistoryQuery` reads completed tracked workouts in ascending
`(completed_at, workout_id)` order. It requires a limit of 1–100 and supports
optional inclusive `from`/`through` bounds, an exercise filter, and an
exclusive cursor. SQLite serves it from the completed-workout index; it does
not deserialize the full history before applying the page bound.

`LastPerformanceQuery` uses the same indexed completed-workout projection and
returns one newest matching workout without loading all history.

`CorrectSetCommand` is the only first-party mutation of a completed tracked
set. It requires the workout revision, a command ID, and an explicit timestamp
and replacement metrics. The adapter records the command payload in an audit
receipt: identical retries replay, while command-ID payload reuse conflicts.
Corrections increment the workout revision. They neither delete workouts or
sets nor create tombstones; archive semantics remain limited to exercises.

The public correction result is a tracking-record update. It does not apply,
rewrite, or infer methodology state. Hosts must decide separately whether a
historical correction requires a new recommendation or methodology-state
transition. Canonical direct-snapshot history remains host-owned and unchanged.
