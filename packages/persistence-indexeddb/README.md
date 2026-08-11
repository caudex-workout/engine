# `@caudex-workout/persistence-indexeddb`

Optional IndexedDB implementation of the Caudex persistence capabilities. It
is packaged separately and is never imported or linked by
`@caudex-workout/engine`.

## Private schema v6

| Store | Compound key | Indexes |
| --- | --- | --- |
| `catalog` | `[hostScopeKey, exerciseId]` | `by_scope(hostScopeKey)` |
| `history` | `[hostScopeKey, completedAt, workoutId]` | `by_scope_completed(hostScopeKey, completedAt)` |
| `methodology_state` | `[key.hostScopeKey, key.methodologyId]` | none |
| `recommendation_journal` | `[hostScopeKey, acceptedAt, id]` | `by_scope_accepted(hostScopeKey, acceptedAt)`, unique `by_scope_id(hostScopeKey, id)` |
| `active_workouts` | `[hostScopeKey, workoutId]` | none |
| `workout_templates` | `[hostScopeKey, template.id]` | none |
| `workflow_recovery` | `[hostScopeKey, workflowId]` | none |
| `portable_catalog_references` | `[hostScopeKey, exerciseId]` | none |
| `athlete_profiles` | `[hostScopeKey, athleteProfileId]` | none |
| `program_definitions` | `[key.hostScopeKey, key.definitionId, key.definitionVersion]` | none |
| `program_instances` | `[key.hostScopeKey, key.instanceId]` | none |
| `program_occurrences` | `[key.hostScopeKey, key.instanceId, key.occurrenceId]` | none |

The database version is `6`. Version 2 added active tracking snapshots,
templates, and workflow recovery records without rewriting v1 stores. Version
3 adds scoped portable catalog references. Future
released schema changes must increment the
version and upgrade stores in `onupgradeneeded`; released upgrade steps are
forward-only. This physical schema is adapter-private and is not the canonical
Caudex computation schema.

Version 4 adds a unique journal index so accepted-recommendation IDs are true
idempotency keys. Reusing an ID with a different payload is rejected; an exact
retry succeeds without another row.

Version 5 adds scoped athlete profiles. Version 6 adds immutable program
definition versions and occurrence entries, along with atomically persisted
program instances and their accepted planning state.

`compareAndSetState` reads the current record, validates the opaque revision,
and writes the next revision in one IndexedDB readwrite transaction.
`saveActiveWorkout` and `saveTemplate` likewise keep their read/compare/write
sequence in one transaction and expose revision conflicts.
`compareAndSetProgramInstance` keeps definition lookup, planning-revision
comparison, and the instance/state write in one transaction. Definition and
occurrence writes use insert-only semantics.

## Lifecycle and quota

- Create one adapter per database and call `close()` when its page or worker is
  finished.
- A version upgrade can be blocked while another tab holds an older connection.
  The adapter closes its connection on `versionchange`; hosts should retry or
  prompt users to close stale tabs.
- IndexedDB data may be evicted under browser storage pressure, especially in
  non-persistent or private browsing contexts. Hosts should treat
  `QuotaExceededError` as storage unavailability and maintain synchronization
  or export strategies when data is important.
- Transactions become inactive across unrelated asynchronous work. Adapter
  methods keep compare-and-set reads and writes inside one transaction.
- Browser implementations impose different value, transaction, and quota
  limits. This adapter does not promise durable cloud storage or cross-device
  synchronization.

`deleteDatabase()` is intended for explicit host reset and tests. It closes the
adapter before deletion and makes that adapter instance unusable afterward.
