# Tracking contract architecture review

Status: accepted for CWE-103

Scope: minimum host-owned workout start, mutation, completion, and read
contracts

## Decision

The public package name is `caudex_tracking`. Tracking is not added to the
stateless `caudex` recommendation package and is not folded into
`caudex_persistence`.

`caudex_tracking` is an engine-owned application contract containing borrowed
command, query, state, issue, and result values. It depends only on public
`caudex` types. It has no repository interface and performs no allocation,
storage, transaction, terminal, clock, random, network, environment, or
filesystem operation.

The dependency direction is:

```text
host or optional adapter
    └── caudex_tracking
            └── public caudex
```

This preserves ADR-0002's stateless recommendation core and ADR-0003's rule
that persistence is optional and downstream. A SQLite adapter may later
execute these contracts, but the contract neither requires nor describes a
database.

## Minimum contract

The initial surface defines:

- A host scope with an optional athlete ID, without inventing athlete storage
- Caller-supplied stable workout, membership, set, exercise, and command IDs
- Caller-supplied timestamps
- Monotonic workout revisions used by mutation commands
- Active and completed workout state
- Stable exercise membership and non-numeric ordering keys
- Logged set metrics and status
- Start, add-exercise, log-set, and complete command values
- Read-workout and bounded active-workout query values
- Accepted and rejected results with structured issues
- Explicit zero, one, and ambiguous active-workout selection

These are borrowed values. An executor documents allocation for any returned
owned copy. CWE-103 defines no executor and hides no allocation.

## Idempotency and conflicts

Every command carries a caller-supplied `command_id`. An implementation records
the complete outcome atomically with an accepted transition.

- Retrying the same command ID with the same command kind and payload returns
  the original accepted result with disposition `replayed`.
- Reusing a command ID with a different kind or payload rejects with
  `tracking.command_payload_conflict` and performs no transition.
- Mutation commands after start carry `expected_revision`.
- A revision mismatch rejects with `tracking.revision_conflict` and performs
  no transition.
- Adapter availability, transaction, allocation, corruption, and migration
  failures are execution errors, not tracking issues.

The contract does not prescribe receipt tables, hashes, serialization, or a
transaction API.

## Completion and workout length

Workout length is not a validity invariant. `CompleteWorkoutCommand` may
complete an active workout with zero exercises, zero completed sets, or a
duration a client considers short.

An implementation may return the warning
`tracking.short_workout_completed` in an accepted result. It must not reject
solely because the workout is short. User confirmation and human wording are
client concerns and are not fields in the public command.

## Active-workout ambiguity

The model permits multiple active workouts in one scope. The bounded active
query returns an `ActiveWorkoutSelection`:

- `none`
- `one`
- `ambiguous`, containing the matching stable workout values

Hosts must request an explicit workout ID after an ambiguous result. Neither
the contract nor an adapter stores a hidden current-workout pointer or guesses.

## Correction prerequisites and deferred capabilities

Stable set IDs, workout revisions, explicit command IDs, and timestamps are
present now so a later audited correction command can target an exact
historical value and detect stale writes. CWE-103 does not define correction
semantics.

The following Phase 4 or later capabilities remain unsupported and are not
implied by this contract:

- Historical set correction or deletion
- Workout cancellation, reopening, deletion, or archival
- Exercise membership removal or reordering
- Set reordering
- Athlete, equipment, or exercise catalog CRUD
- Notes, aliases, templates, routines, supersets, rest timers, or plates
- Bulk import, synchronization, event sourcing, or conflict reconciliation
- History search, last-performance queries, or pagination

Those operations require focused contracts and tests before a client or
adapter exposes them.

## Compatibility

`contract_version` versions this Zig surface independently from the
recommendation engine, canonical JSON schema, persistence capability contract,
and database schema. Breaking command/result or semantic changes increment the
contract version and require migration guidance.

No serialized wire format is approved by CWE-103. Field names are public Zig
source API, not a promise of JSON compatibility.

## Subsequent implementation

CWE-104 subsequently adds deterministic start and query calculations to this
package. They operate only on explicit `LifecycleSnapshot` values and
caller-owned buffers; the dependency and effect boundaries approved here are
unchanged.
