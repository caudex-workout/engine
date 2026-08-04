# Optional workflow orchestration

`createCaudex({ persistence })` can compose narrow host capabilities without
making persistence part of the deterministic engine. `recommendFromPersistence`
and `evaluateCompletionFromPersistence` load the catalog, history, and optional
methodology state, construct a complete canonical request, and then invoke the
same low-level WASM operations available without persistence.

The host remains responsible for scope authorization and for deciding whether
to accept recommendations and methodology-state proposals. Caudex never writes
methodology state during recommendation or evaluation.

## Atomicity and recovery

| Operation | Portable guarantee | Stronger adapter option |
| --- | --- | --- |
| Tracking command | Revision checked; retry uses its command ID | Snapshot and replay receipt in one database transaction |
| Recommendation instantiation | Multi-step, idempotent by accepted-recommendation ID | Journal, provenance, and active workout in one composite transaction |
| Workout completion | Multi-step, idempotent by workout ID | Active transition, canonical completion, and recovery record in one composite transaction |
| Methodology-state acceptance | Explicit compare-and-set | Atomic compare-and-set in the state store |

Before a non-atomic recommendation-start or completion workflow performs its
first durable write, the npm orchestrator stores a `pending` recovery record.
The record includes the canonical payload needed to resume and changes to
`completed` after every required write succeeds. Interrupted retries reuse:

- `recommendation:<acceptedRecommendationId>` for recommendation acceptance;
- `completion:<workoutId>` for workout completion.

Acceptance journals and completed-workout sinks must treat those IDs as
idempotency keys. An active-workout store continues to enforce its revision;
revision conflicts are surfaced and are never silently overwritten.

Custom capabilities backed by unrelated services do not share a universal
transaction. A host can provide a composite adapter operation when records are
co-located, but must otherwise retain recovery records until reconciliation has
completed.

## Capability selection

The convenience facade accepts a structural subset of the optional persistence
contracts. Direct deterministic calls remain usable when no persistence is
configured. Request assembly needs catalog and history loaders; state loading is
optional. Recommendation journaling, completion storage, recovery, active
workout storage, and state compare-and-set are independently optional.
