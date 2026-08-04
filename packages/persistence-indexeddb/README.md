# `@caudex/persistence-indexeddb`

Optional IndexedDB implementation of the Caudex persistence capabilities. It
is packaged separately and is never imported or linked by
`@caudex-workout/engine`.

## Private schema v1

| Store | Compound key | Indexes |
| --- | --- | --- |
| `catalog` | `[hostScopeKey, exerciseId]` | `by_scope(hostScopeKey)` |
| `history` | `[hostScopeKey, completedAt, workoutId]` | `by_scope_completed(hostScopeKey, completedAt)` |
| `methodology_state` | `[key.hostScopeKey, key.methodologyId]` | none |
| `recommendation_journal` | `[hostScopeKey, acceptedAt, id]` | `by_scope_accepted(hostScopeKey, acceptedAt)` |

The database version is `1`. Future released schema changes must increment the
version and upgrade stores in `onupgradeneeded`; released upgrade steps are
forward-only. This physical schema is adapter-private and is not the canonical
Caudex computation schema.

`compareAndSetState` reads the current record, validates the opaque revision,
and writes the next revision in one IndexedDB readwrite transaction.

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
