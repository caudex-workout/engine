# `adapters/` instructions

Adapters are optional outer layers. They load snapshots and persist explicitly
accepted results; they must not move recommendation or tracking semantics out
of the core or make the core depend on repositories, transactions, or SQL.

- Keep persistence capability contracts narrow and concrete. Distinguish
  adapter conflicts, corrupt data, unavailable resources, and transaction or
  serialization failures from core validation and methodology issues.
- Preserve atomicity and advertised transaction behavior. Use prepared SQL and
  bound parameters; never interpolate caller values into SQL. Check rollback,
  commit, compare-and-set, idempotency, and read/write invariants on all
  relevant paths.
- Bound decoded rows, collections, strings, portable payloads, and query
  results before allocation. Treat corrupt or oversized persisted data as an
  explicit adapter failure; do not partially accept it.
- Released SQLite migrations under `adapters/sqlite/migrations/` are immutable
  and forward-only. Add a new migration for a schema change. Physical schema
  details remain adapter-owned unless a public contract explicitly says
  otherwise.
- Extend the persistence contract kit and failure-injection/rollback tests for
  new capabilities. Verify canonical equivalence so an adapter cannot change
  engine semantics. Keep SQLite-specific behavior and diagnostics in this
  subtree rather than leaking SQL assumptions into clients.

See `adapters/sqlite/README.md`, `docs/persistence/`, and the persistence
contract tests before changing adapter behavior.
