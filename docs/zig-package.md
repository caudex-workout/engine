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
        },
    }),
});
```

Application code then imports only the public module:

```zig
const caudex = @import("caudex");
```

The complete [`examples/zig/consumer`](../examples/zig/consumer) package
registers a host-defined methodology without importing private source files.

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

## Persistence package status

The v0.1 tagged Zig source package exports only the `caudex` module. The
repository's Zig persistence contracts and SQLite implementation are currently
build-local adapter modules: they are not included in `build.zig.zon`'s package
paths and are not supported through repository-relative imports.

[ADR-0004](adr/ADR-0004-first-party-zig-reference-client.md) and the
[reference-client implementation plan](implementation-plan.md) require named,
clean-consumer-tested public Zig persistence and SQLite package roots before
`caudex-cli` may depend on them. Until that work is complete, external Zig hosts
should treat `adapters/` as implementation source rather than a published
package contract.

## Zig version policy

Caudex v0.1 supports exactly Zig 0.16.x and declares 0.16.0 as its minimum.
Zig does not promise source compatibility across minor releases, so a future
Caudex release may move to a newer Zig minor version. Such a change is recorded
in the changelog and never made in a patch release.

CI builds the checked-in consumer from a fresh temporary package containing
only `build.zig.zon`'s declared paths. This verifies package completeness,
module import wiring, the supported compiler, and custom-methodology use without
workspace-relative source imports.
