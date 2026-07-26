# Implementing custom persistence capabilities

Caudex always supports direct snapshot mode. A host may load catalog, history,
and methodology state using its existing repositories and pass the resulting
canonical values directly to `@caudex/workout-engine`; implementing these
interfaces is optional.

The primary contract is the Zig module
[`adapters/persistence.zig`](../../adapters/persistence.zig). It uses explicit
context/function tables and caller-supplied allocators. Loaded values borrow
storage allocated from that allocator, so an arena is a convenient ownership
boundary for assembling one request snapshot. The TypeScript package mirrors
the same capabilities for npm hosts. The executable
[`examples/custom-repository`](../../examples/custom-repository/README.md)
sample applies those capabilities to deliberately non-canonical legacy records
and verifies that only methodology state is written.

## Choose only the capabilities you need

Implement `CatalogSource`, `HistorySource`, and `MethodologyStateStore`
independently. A host whose catalog and history already live in application
services may implement only `MethodologyStateStore`.

Do not combine them into a general repository. Keep authentication, tenancy,
connection management, transactions, and database-specific query options in
host code.

In Zig, expose only the capability being implemented:

```zig
const persistence = @import("caudex_persistence");

fn loadCatalog(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    scope: persistence.CatalogScope,
) persistence.CapabilityError![]const persistence.canonical.Exercise {
    const repository: *ApplicationRepository = @ptrCast(@alignCast(context));
    return repository.loadCanonicalExercises(allocator, scope);
}

const catalog_source: persistence.CatalogSource = .{
    .context = &repository,
    .load_fn = loadCatalog,
};
```

The allocator owns the returned snapshot and all nested slices. Adapter
allocation failure remains `error.OutOfMemory`; storage failures use
`AdapterError`. `MethodologyStateStore.compareAndSet` additionally returns
`error.Conflict`.

The TypeScript mirror follows the same boundary:

```ts
import {
  PersistenceConflictError,
  type MethodologyStateStore,
} from "@caudex/persistence";

export class ExistingStateStore implements MethodologyStateStore {
  constructor(private readonly repository: ApplicationRepository) {}

  async loadState(key) {
    const row = await this.repository.findState(key);
    return row === null ? null : mapStateRecord(row);
  }

  async compareAndSetState(change) {
    const row = await this.repository.updateStateWhenRevisionMatches(change);
    if (row === null) {
      const current = await this.repository.findState(change.key);
      throw new PersistenceConflictError(
        change.key,
        change.expectedRevision,
        current?.revision ?? null,
      );
    }
    return mapStateRecord(row);
  }
}
```

## Mapping requirements

- Return canonical `Exercise` and `CompletedWorkout` values, not ORM entities.
- Return history in deterministic chronological order.
- Treat methodology state as an opaque value paired with its methodology and
  schema versions.
- Use stable host scope keys; the contract does not prescribe user or tenant
  models.
- Interpret `asOf` and `through` as inclusive RFC 3339 snapshot boundaries.
- Reject unsupported stored versions explicitly instead of silently coercing
  them.

Storage tables and documents are adapter-private. They do not need to resemble
the canonical computation schema.

## Errors and concurrency

Throw `PersistenceAdapterError` for inability to load or store data. Throw
`PersistenceConflictError` only when a compare-and-set revision no longer
matches. These are adapter/application failures; do not translate them into
Caudex validation issues or methodology issues.

Use `expectedRevision: null` to mean “create only if absent.” Revisions are
opaque strings. A store may use integer versions, entity tags, or database
tokens internally, but callers only compare the returned value.

## Explicit acceptance

Recommendation calculation returns a proposal. Do not write
`nextMethodologyState`, journal a recommendation, or append a workout during a
read or calculation call. After the host explicitly accepts a result, it may:

1. append an optional accepted-recommendation record;
2. compare-and-set the proposed methodology state;
3. append an optional completed workout.

If the backing system supports transactions, the host may group those writes.
The common contract does not claim transaction behavior.

## Contract tests

Zig adapters should run the reusable functions in
[`adapters/persistence/testing.zig`](../../adapters/persistence/testing.zig).
The suite checks loading, deterministic chronological history ordering, missing
scopes, state round trips, optimistic conflicts, and canonical equivalence with
direct snapshot assembly.

Pass a `TransactionProbe` only when the adapter advertises transactional
rollback. Adapters without that guarantee omit it and are not tested against a
behavior they do not claim. `InMemoryAdapter` is a database-independent test
double suitable for host integration tests.
