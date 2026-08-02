const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const tracking = @import("caudex_tracking");
const resolution = @import("resolution.zig");

pub fn resolveWorkout(
    adapter: *sqlite.Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    explicit_id: ?tracking.Id,
) !resolution.WorkoutResolution {
    const explicit_result: ?tracking.ReadWorkoutResult = if (explicit_id) |id|
        try adapter.readWorkout(allocator, .{ .scope = scope, .workout_id = id })
    else
        null;
    const active: tracking.ActiveWorkoutSelection = if (explicit_id == null)
        try adapter.listActiveWorkouts(allocator, .{
            .scope = scope,
            .max_results = 32,
        })
    else
        .none;
    return resolution.resolveActiveWorkout(explicit_id, explicit_result, active);
}

pub fn loadActiveWorkouts(adapter: *sqlite.Adapter, allocator: std.mem.Allocator, scope: tracking.Scope) !tracking.ActiveWorkoutSelection {
    return adapter.listActiveWorkouts(allocator, .{ .scope = scope, .max_results = 32 });
}

pub fn loadLastPerformance(adapter: *sqlite.Adapter, allocator: std.mem.Allocator, scope: tracking.Scope, exercise_id: tracking.Id) !tracking.LastPerformanceResult {
    return adapter.lastPerformance(allocator, .{ .scope = scope, .exercise_id = exercise_id });
}

pub fn resolveExercise(
    adapter: *sqlite.Adapter,
    allocator: std.mem.Allocator,
    host_scope_key: []const u8,
    as_of: []const u8,
    reference: []const u8,
) !resolution.ExerciseResolution {
    const catalog = try adapter.catalogSource().load(allocator, .{
        .host_scope_key = host_scope_key,
        .as_of = as_of,
    });
    const output = try allocator.alloc(
        persistence.canonical.Exercise,
        catalog.len,
    );
    return resolution.resolveExercise(catalog, reference, output);
}

pub const ManagedExerciseResolution = union(enum) {
    found: tracking.ManagedExercise,
    not_found,
    ambiguous: []const tracking.ManagedExercise,
};

pub fn resolveManagedExercise(adapter: *sqlite.Adapter, allocator: std.mem.Allocator, scope: tracking.Id, reference: []const u8) !ManagedExerciseResolution {
    if (tracking.Id.parse(reference)) |id| {
        switch (try adapter.readManagedExercise(allocator, .{ .host_scope_key = scope, .exercise_id = id })) {
            .found => |value| return .{ .found = value },
            .not_found => {},
        }
    } else |_| {}
    const searched = try adapter.searchExercises(allocator, .{ .host_scope_key = scope, .text = reference, .max_results = 100, .include_archived = true });
    const values = switch (searched) {
        .found => |found| found,
        .rejected => return .not_found,
    };
    if (values.len == 0) return .not_found;
    const canonical_values = try allocator.alloc(persistence.canonical.Exercise, values.len);
    const matches = try allocator.alloc(persistence.canonical.Exercise, values.len);
    for (values, 0..) |value, index| canonical_values[index] = value.exercise;
    return switch (try resolution.resolveExercise(canonical_values, reference, matches)) {
        .found => |exercise| for (values) |value| {
            if (std.mem.eql(u8, value.exercise.id, exercise.id)) return .{ .found = value };
        } else unreachable,
        .not_found => .not_found,
        .ambiguous => |exercises| blk: {
            const managed = try allocator.alloc(tracking.ManagedExercise, exercises.len);
            for (exercises, 0..) |exercise, index| for (values) |value| if (std.mem.eql(u8, value.exercise.id, exercise.id)) {
                managed[index] = value;
                break;
            };
            break :blk .{ .ambiguous = managed };
        },
    };
}
