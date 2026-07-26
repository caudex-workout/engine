# Zig package

Caudex supports direct source-package consumption with Zig 0.16.0. Tagged
releases include `build.zig.zon`, the public `caudex` module, license and
changelog files, module documentation, and the checked-in Zig consumer.

## Add a tagged release

From a Zig 0.16.0 consumer project, add the release archive:

```bash
zig fetch --save \
  https://github.com/OWNER/caudex/archive/refs/tags/v0.1.0.tar.gz
```

`zig fetch --save` records the content hash calculated by Zig. Do not copy a
hash from an untrusted source or replace it merely because a remote archive
changed. Replace `OWNER` with the repository owner; a released tag is
immutable.

Expose the package module from the consumer's `build.zig`:

```zig
const caudex_dependency = b.dependency("caudex", .{
    .target = target,
    .optimize = optimize,
});

const executable = b.addExecutable(.{
    .name = "workout-host",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "caudex",
                .module = caudex_dependency.module("caudex"),
            },
            .{
                .name = "caudex_persistence",
                .module = caudex_dependency.module("caudex_persistence"),
            },
            .{
                .name = "caudex_tracking",
                .module = caudex_dependency.module("caudex_tracking"),
            },
            .{
                .name = "caudex_sqlite",
                .module = caudex_dependency.module("caudex_sqlite"),
            },
        },
    }),
});
```

Application code imports the public modules it needs:

```zig
const caudex = @import("caudex");
const caudex_persistence = @import("caudex_persistence");
const caudex_tracking = @import("caudex_tracking");
const caudex_sqlite = @import("caudex_sqlite");
```

The complete [`examples/zig/consumer`](../examples/zig/consumer) package
registers a host-defined methodology and inspects the persistence contract
without importing repository-relative source files.

## Tracking contract

`caudex_tracking` defines the public, database-independent command, query,
workout-state, and structured-issue values for host-owned workout tracking. It
depends only on `caudex`. Its minimal start and read calculations consume
explicit borrowed snapshots and caller-owned buffers; they perform no
allocation, persistence, clock access, or terminal behavior.

The accepted [CWE-103 architecture review](tracking/architecture-review-cwe-103.md)
documents package ownership, idempotency, revisions, short-workout completion,
active-workout ambiguity, correction prerequisites, deferred features, and
compatibility.

## Public module map

- `engine`: typed recommendation and performance-evaluation entry points
- `training`: borrowed exercise catalogs and completed-workout snapshots
- `primitives`: validated IDs, timestamps, exact decimals, and measurements
- `methodology`: implementation interface and deterministic registry
- `diagnostics`: caller-provided issue and explanation writers
- `double_progression` and `rpe_top_set_backoff`: first-party contracts
- `canonical` and `canonical_json`: canonical boundary models and JSON codec
- `filtering`, `ordering`, `history`, `duration`, and `load_math`: reusable
  deterministic calculations

Public declarations reachable from `@import("caudex")` are the supported Zig
surface. Files elsewhere in `src` must not be imported by path.

## Persistence contract

`caudex_persistence` is the public, database-independent contract for optional
Zig persistence adapters. It depends only on the public `caudex` module and
re-exports that module's canonical types as `caudex_persistence.canonical`.
Importing it does not link SQLite, expose migrations, or add persistence to the
engine.

The contract has these ownership and allocation rules:

- Inputs, contexts, and all slices nested in input values are borrowed for the
  duration of the capability call. An adapter that retains an input must copy
  it into adapter-owned storage.
- `CatalogSource.load`, `HistorySource.load`, `MethodologyStateStore.load`, and
  `MethodologyStateStore.compareAndSet` return values whose returned slices and
  nested values live in the allocator supplied to that call. The caller owns
  those allocations and must release them according to its allocator strategy.
- Write-only capabilities receive borrowed values and do not transfer
  ownership. Their implementations copy any data retained after the call.
- Capability implementations may allocate only through an explicit allocator
  parameter or their documented adapter-owned storage. The contract does not
  hide a process-global allocator.

Errors distinguish execution from concurrency:

- `AdapterError` reports adapter availability, invalid stored data, unsupported
  versions, or an operation failure.
- `CapabilityError` adds explicit allocator failure.
- `StateStoreError` adds `error.Conflict` for a compare-and-set revision
  mismatch. A conflict is an adapter/application outcome, not a core
  validation or methodology issue.

`contract_version` versions this Zig capability surface independently of the
engine, canonical schema, methodology state schema, and database schema.
Adapters must reject unsupported stored versions rather than reinterpret them.
Additive source-compatible changes may retain the contract version; a breaking
capability or semantic change increments it and requires adapter and host
migration guidance. Normal Zig semantic-version compatibility and the exact
Zig 0.16.x support policy also apply.

The reusable implementation in `adapters/persistence/testing.zig` is registered
only as the build-local `caudex_persistence_testing` module for repository
contract tests. It is not a public module and is excluded from the published
source-package paths. External adapters may implement the public capabilities
but must not depend on that test utility.

## SQLite adapter

`caudex_sqlite` is the optional public SQLite package. Consumers wire it from
the same dependency:

```zig
const caudex_sqlite = @import("caudex_sqlite");

const database = try caudex_sqlite.openInMemory(.{});
defer database.close();
const metadata = try database.metadata();
```

The package links the platform SQLite library. Its `Adapter` is opaque, and its
raw handle, prepared statements, SQL, tables, and migration bodies remain
private. File databases use `open(path, options)`; `create_if_missing` controls
creation and supported forward migrations run automatically.

Open lifecycle failures distinguish busy, corrupt, migration-failed,
unsupported-newer-schema, and general open errors. Metadata reports adapter
version, schema compatibility bounds, current schema, and memory/file kind.
The adapter also exposes typed `startWorkout` and `readWorkout` operations using
`caudex_tracking`; accepted workout state and its idempotency receipt are
committed atomically, and all returned owned values use the caller's allocator.
See the [SQLite adapter guide](../adapters/sqlite/README.md) for the complete
lifecycle and error contract.

## Zig version policy

Caudex v0.1 supports exactly Zig 0.16.x and declares 0.16.0 as its minimum.
Zig does not promise source compatibility across minor releases, so a future
Caudex release may move to a newer Zig minor version. Such a change is recorded
in the changelog and never made in a patch release.

CI builds the checked-in consumer from a fresh temporary package containing
only `build.zig.zon`'s declared paths. This verifies package completeness,
module import wiring, the supported compiler, and custom-methodology use without
workspace-relative source imports.
