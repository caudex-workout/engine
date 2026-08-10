# Zig integrator guide

This guide is for a third-party Zig application that wants to use Caudex
without depending on repository-relative source files or copying the reference
client's presentation logic. It is tested against Zig 0.16.0 and the staged
source package. No public release tag is currently available.

## Add the public package

When a release tag is deliberately published, fetch the immutable release
archive and let Zig record the content hash:

```sh
zig fetch --save \
  https://github.com/caudex-workout/engine/archive/refs/tags/vX.Y.Z.tar.gz
```

Until then, maintainers can validate the same consumer path without a public
release by running `zig build package-zig` in the checkout and using the
generated package under `zig-out/zig-packages/core` as a local dependency. A
local path is a staging/test mechanism, not the external installation path.

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

The following is a complete minimal recommendation using the first-party
double-progression implementation. `exercises` may contain as many as
`caudex.engine.max_recommended_exercises` entries; all result storage remains
caller-owned and statically bounded:

```zig
const std = @import("std");
const caudex = @import("caudex");

pub fn main() !void {
    const exercise_id = try caudex.primitives.Id.parse("incline-dumbbell-press");
    const dumbbell = try caudex.primitives.Id.parse("dumbbell");
    const bench = try caudex.primitives.Id.parse("adjustable-bench");
    const equipment = [_]caudex.primitives.Id{ dumbbell, bench };
    const exercises = [_]caudex.training.Exercise{.{
        .id = exercise_id,
        .equipment_ids = &equipment,
    }};
    const request = caudex.engine.RecommendationRequest{
        .as_of = try caudex.primitives.Timestamp.parse("2026-07-25T14:00:00Z"),
        .methodology_id = try caudex.primitives.Id.parse(
            caudex.double_progression.methodology_id,
        ),
        .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
        .config = .{
            .repRange = .{ .min = 8, .max = 12 },
            .workingSets = 3,
            .advancementCriteria = .{
                .minimumSuccessfulSets = 3,
                .minimumRepetitions = 12,
            },
            .initialLoad = .{ .amount = "45", .unit = "lb" },
            .loadIncrement = .{ .amount = "5", .unit = "lb" },
            .failurePolicy = .{
                .onPartial = .hold,
                .onFailure = .regress,
                .regressionAmount = .{ .amount = "5", .unit = "lb" },
            },
            .rounding = .{
                .mode = .nearest,
                .quantum = .{ .amount = "2.5", .unit = "lb" },
            },
        },
        .catalog = .{ .exercises = &exercises },
        .available_equipment_ids = &equipment,
    };
    var output = caudex.engine.Output{};
    const result = try caudex.engine.recommendSession(request, &output);
    const recommendation = result.recommendation.?;
    const exercise = recommendation.exercises[0];
    const set = exercise.sets[0];
    std.debug.print("{s}: {s} reps x {s} {s}\n", .{
        exercise.exerciseId,
        set.targetMetrics[1].value.amount,
        set.targetMetrics[0].value.amount,
        set.targetMetrics[0].value.unit,
    });
}
```

The request, catalog backing arrays, and output are caller-owned. Keep them
alive while reading the result. The engine does not allocate, persist, read a
clock, or accept the proposal on the host's behalf.

`recommendSession` returns `error.CatalogLimitReached` only when the catalog
exceeds `max_recommended_exercises`. Multi-exercise catalogs and distinct
equipment lists are supported without a canonical JSON escape hatch. Other
validation failures return `error.InvalidRequest`, while an unknown
methodology/version returns `error.UnsupportedMethodology`.

For a tracking client, use the public `caudex_tracking` commands and the
optional `caudex_sqlite` adapter. The adapter owns migrations and transactions;
the engine remains stateless. A host using a different database can implement
the public `caudex_persistence` capabilities instead.

## Dispatch a host-defined methodology with typed values

`caudex.methodology.TypedRecommendationRequest` and `recommendTyped` provide a
generic direct path without changing the specialized first-party engine API.
The request owns typed configuration, optional typed state, and a typed payload;
the caller still supplies issue storage, scratch bytes, and the output writer:

```zig
const Request = caudex.methodology.TypedRecommendationRequest(Config, State, Payload);
var issue_storage: [16]caudex.canonical.ValidationIssue = undefined;
var issues = caudex.diagnostics.IssueWriter.init(&issue_storage);
var scratch = caudex.methodology.Scratch{ .bytes = scratch_bytes };
var writer = caudex.methodology.RecommendationWriter{ .context = &output };

try caudex.methodology.recommendTyped(
    implementation,
    Request{ .config = config, .state = state, .payload = payload },
    &issues,
    &scratch,
    &writer,
);
```

This helper performs validation and callback dispatch only. It does not
allocate, select a methodology, interpret configuration, or define output
ownership.

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
