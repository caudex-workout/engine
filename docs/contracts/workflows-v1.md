# Canonical Workflow Protocol v1

Workflow v1 is the pure cross-language bridge between programming results,
templates, tracked workouts, and evaluation input. Its public Zig types live in
`caudex_workflows`; JSON schemas live under `schemas/workflows/v1/`.

The protocol supports recommendation instantiation, template instantiation,
and completed tracked-workout conversion. Every instantiation supplies the
catalog, scope, stable workout/membership/set IDs, and creation timestamp
explicitly. Recommendation acceptance additionally supplies its own stable ID
and optional methodology-state revision or fingerprint.

Instantiation returns either a provenance-bearing active tracked workout or
structured workflow issues. Completion conversion returns either the canonical
`CompletedWorkout` accepted by evaluation or structured issues. Neither
operation persists data, reads a clock, generates IDs, or accepts proposed
methodology state.

Documents are bounded by the canonical 1 MiB transport limit, 128 exercises,
256 sets, 32 tags per exercise, and the canonical tracking/catalog limits.
Unknown schema versions and malformed transport fail before domain execution.
