# Canonical Tracking Protocol v1

Canonical tracking v1 exposes the typed pure Zig tracking lifecycle to other
languages without making JSON the domain model. The public Zig boundary module
is `caudex_tracking_protocol`; the reducer remains `caudex_tracking`.

## Documents

- `SnapshotDocument` carries a standalone versioned tracking snapshot for
  deterministic interchange and persistence boundaries.
- `CommandRequest` applies one explicitly discriminated command to a supplied
  snapshot.
- `AtomicBatchRequest` applies 1–128 commands sequentially as one proposal.
- `CommandResult` contains an accepted or rejected structured outcome.
- `AtomicBatchResult` contains every accepted intermediate outcome and the final
  snapshot, or one rejection and the unchanged original snapshot.

Schema version 1 rejects unknown versions. The JSON schemas are under
`schemas/tracking/v1/` and deterministic fixtures are under
`fixtures/tracking/`.

## Determinism and ownership

Snapshots contain workouts, start-command replay receipts, and the explicit
active/archived exercise-catalog projection needed to validate membership
changes. IDs, timestamps,
revisions, command IDs, ordering, target values, actual values, and units are
explicit. Decimal amounts are canonical base-10 strings and never pass through
floating point.

Every single-command result includes the resulting snapshot. A rejection
returns the unchanged snapshot; an accepted start includes its replay receipt,
so the next deterministic call can retry the same command idempotently.

Recommendation/template origin, provenance, and the immutable original
prescription are also snapshot data. Live edits never overwrite prescription
targets; workflow consumers can derive structured modifications.

The typed batch reducer allocates nothing and writes only to caller workspace.
Workspace contents are unspecified after rejection, but are never returned;
the original input snapshot is immutable and remains the result snapshot. Hosts
persist only an accepted final snapshot.

## Bounds

Default transport limits are 1 MiB input, nesting depth 32, 4,096 structural
items, and 64 KiB per string. Domain document limits are 128 commands per
batch, 256 workouts and replay receipts, 128 exercise memberships per workout,
256 sets per membership, 32 target or actual metrics per set, and 32 tags per
prescribed exercise. Bounds apply equally to workouts embedded in replay
receipts. Callers also provide explicit output capacity.

Malformed UTF-8/JSON, excessive documents, and unsupported schema versions are
transport errors. Valid commands rejected for revision, lifecycle, reference,
or validation reasons return stable structured tracking issues.
