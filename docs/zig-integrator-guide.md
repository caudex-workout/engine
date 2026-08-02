# Zig integrator guide

This guide is for a third-party Zig application that wants to use Caudex
without depending on repository-relative source files or copying the reference
client's presentation logic. It is tested against Zig 0.16.0 and the v0.1.0
source package.

## Add the public package

Fetch the immutable release archive from the tagged source release and let Zig
record the content hash:

```sh
zig fetch --save \
  https://github.com/OWNER/caudex/archive/refs/tags/v0.1.0.tar.gz
```

In `build.zig`, expose only the public modules required by the application:

```zig
const dependency = b.dependency("caudex", .{
    .target = target,
    .optimize = optimize,
});

const app = b.addExecutable(.{
    .name = "workout-host",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = dependency.module("caudex") },
            .{ .name = "caudex_persistence", .module = dependency.module("caudex_persistence") },
            .{ .name = "caudex_tracking", .module = dependency.module("caudex_tracking") },
            .{ .name = "caudex_sqlite", .module = dependency.module("caudex_sqlite") },
        },
    }),
});
```

The SQLite import is optional. An engine-only consumer needs only `caudex`;
an application with its own persistence can add `caudex_persistence` and
`caudex_tracking` without linking SQLite.

The corresponding application imports are ordinary public package imports:

```zig
const caudex = @import("caudex");
const caudex_persistence = @import("caudex_persistence");
const caudex_tracking = @import("caudex_tracking");
const caudex_sqlite = @import("caudex_sqlite");
```

## Build another client

The host owns command parsing, storage, synchronization, authentication,
presentation, and accepted-result policy. A minimal application can use the
typed engine directly:

```zig
const caudex = @import("caudex");

pub fn recommend(request: caudex.engine.RecommendationRequest) !void {
    var output = caudex.engine.Output{};
    const result = caudex.engine.recommendSession(request, &output) catch |err| {
        // Map execution failures to the host's own runtime error policy.
        _ = err;
        return error.EngineFailed;
    };
    if (!result.ok) {
        // Map stable issue codes to the host's own UI or protocol.
        return error.RequestRejected;
    }
    // Render or persist only after the host explicitly accepts the proposal.
    _ = result.recommendation;
}
```

The exact typed request/result declarations are available from the public
module documentation and canonical contracts. Use explicit timestamps,
decimal measurements, catalog snapshots, history snapshots, and methodology
state. Do not make the engine read a clock, database, environment, or network.

For a tracking client, use the public `caudex_tracking` commands and the
optional `caudex_sqlite` adapter. The adapter owns migrations and transactions;
the engine remains stateless. A host using a different database can implement
the public `caudex_persistence` capabilities instead.

## Keep presentation separate

Do not import `apps/caudex-cli`, `apps/caudex-cli/src/tui`, migration files, or
any repository-relative path. Do not copy CLI table formatting, TUI lifecycle
code, or private SQL. Convert typed results into the host's own JSON, GUI,
HTTP, or terminal presentation layer. Stable issue codes and explanation codes
are the machine-facing boundary; human summaries may be localized.

The reference CLI demonstrates one possible shell and output policy. It is not
a required framework, runtime dependency, or presentation library for an
integrator.

## Verify a clean consumer

The repository's third-party-style consumer under
[`examples/zig/consumer`](../examples/zig/consumer) imports only the four
public modules shown above, registers a host-defined methodology, and exercises
the optional SQLite adapter. Run its clean package verification with:

```sh
zig build test-zig-package
```

This copies only the declared source-package paths into a temporary directory,
builds there, and runs the consumer. If a client needs a module that is not in
the public module map, treat that as an API gap and raise an issue rather than
reaching into a private path.
