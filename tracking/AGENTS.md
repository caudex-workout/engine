# `tracking/` instructions

`tracking/` is the persistence-independent public active-workout and catalog
tracking package. It consumes core types but must not acquire a database or
adapter implementation dependency.

- Keep command application, queries, replay, corrections, and lifecycle
  transitions deterministic. Every command has explicit metadata and host
  scope; do not infer identity, time, or acceptance from process state.
- Preserve command/result semantics for accepted, rejected, duplicate, and
  conflict cases. Revisions, command IDs, idempotency, ordering, and replay
  behavior are part of the tracking contract; use checked revision arithmetic.
- Keep proposed, accepted, and rejected state distinct. A host or adapter
  chooses whether an accepted result is persisted; tracking code does not
  write storage or silently mutate a host snapshot.
- Enforce bounded command batches, snapshots, collections, strings, and
  history queries before allocation or traversal. Return the established
  structured issue/error rather than asserting on caller data.
- Preserve protocol versions, issue codes, canonical JSON shapes, athlete/host
  scope, and stable tie-breaking. Update `schemas/tracking`, tracking fixtures,
  contract tests, and compatibility records together for intentional changes.

Use the tracking contract and architecture documents under
`docs/contracts/tracking-v1.md` and `docs/tracking/`, plus the focused tracking
build/test steps in `build.zig`.
