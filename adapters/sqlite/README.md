# SQLite persistence adapter

The Zig module [`../sqlite.zig`](../sqlite.zig) implements the optional Caudex
persistence capabilities over a host-supplied SQLite database path. It links
the platform SQLite library; neither the Caudex core nor the core npm package
links SQLite.

The module is currently wired only as a build-local test dependency. It is not
included in the v0.1 Zig source-package allowlist and is not yet a supported
external package root. The first-party reference-client plan requires a named
public SQLite package, clean-consumer tests, metadata and compatibility
inspection, and narrower error reporting before application code depends on it.
Monorepo-relative importability does not make this file public API.

## Schema and migrations

[`migrations/001_initial.sql`](migrations/001_initial.sql) is the adapter-private
reference schema. The adapter records applied versions in
`schema_migrations`. Released migrations are immutable and future changes add a
higher-numbered file; migrations run forward inside an immediate transaction.
The physical tables are not canonical Caudex schemas.
Clients must not read or mutate them directly; supported integration occurs
through the adapter's eventual public host-facing API.

Canonical exercises, workouts, and methodology state are stored as JSON
payloads alongside narrow relational keys used for deterministic retrieval.

## SQL and concurrency

All production SQL is prepared with `sqlite3_prepare_v2`. Host values are bound
with `sqlite3_bind_*`; no host value is interpolated into SQL. Bound text stays
alive through the synchronous `sqlite3_step` call and uses SQLite's static
lifetime mode.

`busy_timeout_ms` defaults to 250 milliseconds. `SQLITE_BUSY` and
`SQLITE_LOCKED` become `error.Unavailable`, allowing hosts to retry explicitly.
Methodology-state compare-and-set uses `BEGIN IMMEDIATE`, verifies the expected
opaque revision, writes the next revision, and commits atomically. A mismatch
rolls back and returns `error.Conflict`.

Use `:memory:` for isolated tests or a filesystem path for durable storage.
The host owns backup, file permissions, encryption, WAL policy, and connection
lifecycle.
