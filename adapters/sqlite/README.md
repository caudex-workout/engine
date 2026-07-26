# SQLite persistence adapter

The Zig module [`../sqlite.zig`](../sqlite.zig) implements the optional Caudex
persistence capabilities over a host-supplied SQLite database path. It links
the platform SQLite library; neither the Caudex core nor the core npm package
links SQLite.

The module is published from the Zig source package as `caudex_sqlite`.
Consumers obtain it with `dependency.module("caudex_sqlite")` and import it as
`@import("caudex_sqlite")`. Its `Adapter` is opaque: raw SQLite handles,
statements, SQL, tables, and migration bodies are not public API.

Use `open(path, options)` for file databases or `openInMemory(options)` for an
isolated in-memory database. Opening creates a missing file by default and runs
supported forward migrations. Set `create_if_missing = false` to require an
existing file. `metadata()` reports adapter version, current/minimum/latest
schema versions, compatibility, and whether the database is in memory or
file-backed. `close()` ends the connection.

Lifecycle errors are intentionally distinct:

- `error.Busy`: lock contention exceeded `busy_timeout_ms`
- `error.Corrupt`: corrupt content or a non-SQLite file
- `error.MigrationFailed`: a supported migration could not complete
- `error.UnsupportedSchema`: the database uses a newer schema
- `error.OpenFailed`: another open/create failure

## Schema and migrations

Migration files are packaged so the public module can embed them, but remain
adapter-private resources rather than importable modules or schema contracts.
The adapter records applied versions in
`schema_migrations`. Released migrations are immutable and future changes add a
higher-numbered file; migrations run forward inside an immediate transaction.
The physical tables are not canonical Caudex schemas.
Clients must not read or mutate them directly; supported integration occurs
through the adapter's eventual public host-facing API.

Canonical exercises, workouts, and methodology state are stored as JSON
payloads alongside narrow relational keys used for deterministic retrieval.

Schema version 2 adds the minimal public tracking vertical slice. The opaque
adapter exposes:

```zig
const result = try database.startWorkout(allocator, command);
const loaded = try database.readWorkout(allocator, query);
```

The allocator owns strings and issue slices returned by these operations.
Starting a workout loads any prior receipt or conflicting workout, invokes the
deterministic `caudex_tracking` decision, and stores the accepted workout plus
its command receipt in one `BEGIN IMMEDIATE` transaction. An identical command
ID and payload returns the stored result as `replayed`. Reusing the ID with a
different payload returns `tracking.command_payload_conflict`. Rejected
commands store neither a workout nor a receipt.

Schema version 3 adds atomic exercise membership ordering. `addExercise`,
`removeExercise`, and `reorderExercise` accept semantic anchors (`beginning`,
`end`, `before`, or `after`); the physical ordinal is private. Catalog entries
omitted by a later `replaceCatalog` call remain archived so adding an archived
exercise can be distinguished from adding an ID that never existed. Catalog
loads return active entries only.

Schema version 4 adds atomic set lifecycle persistence. `addSet`, `completeSet`,
`skipSet`, `reopenSet`, `removeSet`, and `reorderSet` share the deterministic
tracking rules. Targets and actuals retain exact decimal measurements and
explicit units. Accepted set commands store idempotency receipts in the same
transaction; payload reuse conflicts and rejected transitions do not mutate
the workout.

Workout completion and broader history queries remain later capabilities.

## SQL and concurrency

All production SQL is prepared with `sqlite3_prepare_v2`. Host values are bound
with `sqlite3_bind_*`; no host value is interpolated into SQL. Bound text stays
alive through the synchronous `sqlite3_step` call and uses SQLite's static
lifetime mode.

`busy_timeout_ms` defaults to 250 milliseconds. Open-time `SQLITE_BUSY` and
`SQLITE_LOCKED` become `error.Busy`. Persistence capability calls preserve the
database-independent contract and return `error.Unavailable`, allowing hosts
to retry explicitly.
Methodology-state compare-and-set uses `BEGIN IMMEDIATE`, verifies the expected
opaque revision, writes the next revision, and commits atomically. A mismatch
rolls back and returns `error.Conflict`.

Use `:memory:` for isolated tests or a filesystem path for durable storage.
The host owns backup, file permissions, encryption, WAL policy, and connection
lifecycle.
