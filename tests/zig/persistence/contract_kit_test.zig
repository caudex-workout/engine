const std = @import("std");
const persistence = @import("caudex_persistence");
const testing = @import("caudex_persistence_testing");

const exercises = [_]persistence.canonical.Exercise{
    .{ .id = "incline-dumbbell-press" },
};
const workouts = [_]persistence.canonical.CompletedWorkout{
    .{
        .id = "later",
        .startedAt = "2026-07-25T12:00:00Z",
        .completedAt = "2026-07-25T13:00:00Z",
        .exercises = &.{},
    },
    .{
        .id = "earlier",
        .startedAt = "2026-07-24T12:00:00Z",
        .completedAt = "2026-07-24T13:00:00Z",
        .exercises = &.{},
    },
};
const fixture: testing.Fixture = .{
    .host_scope_key = "athlete-1",
    .catalog = &exercises,
    .history = .{ .workouts = &workouts },
};
const methodology_state: persistence.canonical.MethodologyState = .{
    .schemaVersion = 1,
    .data = .{ .object = .empty },
};

test "reusable source suite covers loading ordering and missing scopes" {
    var adapter: testing.InMemoryAdapter = .{ .fixture = fixture };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try testing.verifySources(
        arena.allocator(),
        adapter.catalogSource(),
        adapter.historySource(),
        fixture,
    );
}

test "reusable state suite covers round trips and optimistic conflicts" {
    var adapter: testing.InMemoryAdapter = .{ .fixture = fixture };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try testing.verifyStateStore(
        arena.allocator(),
        adapter.stateStore(),
        .{
            .host_scope_key = "athlete-1",
            .methodology_id = "caudex.double-progression",
        },
        methodology_state,
    );
}

test "reusable workflow suite covers templates and recovery records" {
    var adapter: testing.InMemoryAdapter = .{ .fixture = fixture };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testing.verifyTemplateStore(allocator, adapter.templateStore(), .{
        .host_scope_key = "athlete-1",
        .template = .{
            .schemaVersion = 1,
            .id = "template-1",
            .displayName = "Strength day",
            .revision = 1,
            .exercises = &.{.{ .exerciseId = "incline-dumbbell-press" }},
        },
    });
    try testing.verifyRecoveryStore(allocator, adapter.recoveryStore(), .{
        .key = .{ .host_scope_key = "athlete-1", .workflow_id = "workflow-1" },
        .kind = "recommendation_instantiation",
        .status = .pending,
        .idempotency_key = "accepted-1",
        .payload_json = "{\"workoutId\":\"workout-1\"}",
        .updated_at = "2026-08-04T12:00:00Z",
    });
}

test "canonical adapter assembly equals direct snapshot mode" {
    var adapter: testing.InMemoryAdapter = .{ .fixture = fixture };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const request: persistence.canonical.RecommendationRequest = .{
        .schemaVersion = 1,
        .asOf = "2026-07-26T12:00:00Z",
        .methodology = .{
            .id = "caudex.double-progression",
            .configVersion = 1,
            .config = .{ .object = .empty },
        },
        .catalog = &exercises,
        .history = .{ .workouts = &.{
            workouts[1],
            workouts[0],
        } },
    };
    try testing.verifyCanonicalEquivalence(
        arena.allocator(),
        fixture.host_scope_key,
        request,
        adapter.catalogSource(),
        adapter.historySource(),
    );
}

test "rollback is checked only for adapters that advertise it" {
    var adapter: testing.InMemoryAdapter = .{ .fixture = fixture };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try testing.verifyRollbackWhenAdvertised(
        arena.allocator(),
        adapter.stateStore(),
        null,
        .{
            .host_scope_key = "athlete-1",
            .methodology_id = "caudex.double-progression",
        },
        methodology_state,
    );
    try testing.verifyRollbackWhenAdvertised(
        arena.allocator(),
        adapter.stateStore(),
        .{
            .context = &adapter,
            .begin_fn = begin,
            .rollback_fn = rollback,
        },
        .{
            .host_scope_key = "athlete-1",
            .methodology_id = "caudex.double-progression",
        },
        methodology_state,
    );
}

fn begin(context: *anyopaque) void {
    const adapter: *testing.InMemoryAdapter = @ptrCast(@alignCast(context));
    adapter.beginTransaction();
}

fn rollback(context: *anyopaque) void {
    const adapter: *testing.InMemoryAdapter = @ptrCast(@alignCast(context));
    adapter.rollback();
}
