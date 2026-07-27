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
