const std = @import("std");
const persistence = @import("caudex_persistence");
const tracking = @import("caudex_tracking");

pub const ExerciseResolution = union(enum) {
    found: persistence.canonical.Exercise,
    not_found,
    ambiguous: []const persistence.canonical.Exercise,
};

/// Resolves ID, then exact alias/name, then case-insensitive substring search.
pub fn resolveExercise(
    exercises: []const persistence.canonical.Exercise,
    reference: []const u8,
    output: []persistence.canonical.Exercise,
) error{OutputBufferTooSmall}!ExerciseResolution {
    for (exercises) |exercise| {
        if (std.mem.eql(u8, exercise.id, reference)) return .{ .found = exercise };
    }
    if (try collectExerciseMatches(exercises, reference, output, exactFriendlyMatch)) |resolution| return resolution;
    if (try collectExerciseMatches(exercises, reference, output, searchMatch)) |resolution| return resolution;
    return .not_found;
}

fn collectExerciseMatches(
    exercises: []const persistence.canonical.Exercise,
    reference: []const u8,
    output: []persistence.canonical.Exercise,
    match: *const fn (persistence.canonical.Exercise, []const u8) bool,
) error{OutputBufferTooSmall}!?ExerciseResolution {
    var count: usize = 0;
    var first: ?persistence.canonical.Exercise = null;
    for (exercises) |exercise| {
        if (!match(exercise, reference)) continue;
        if (first == null) first = exercise;
        if (count >= output.len) return error.OutputBufferTooSmall;
        output[count] = exercise;
        count += 1;
    }
    if (count == 0) return null;
    if (count == 1) return .{ .found = first.? };
    return .{ .ambiguous = output[0..count] };
}

fn exactFriendlyMatch(
    exercise: persistence.canonical.Exercise,
    reference: []const u8,
) bool {
    if (exercise.name) |name| {
        if (std.mem.eql(u8, name, reference)) return true;
    }
    for (exercise.aliases) |alias| {
        if (std.mem.eql(u8, alias, reference)) return true;
    }
    return false;
}

fn searchMatch(
    exercise: persistence.canonical.Exercise,
    reference: []const u8,
) bool {
    if (containsIgnoreCase(exercise.id, reference)) return true;
    if (exercise.name) |name| {
        if (containsIgnoreCase(name, reference)) return true;
    }
    for (exercise.aliases) |alias| {
        if (containsIgnoreCase(alias, reference)) return true;
    }
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        var equal = true;
        for (haystack[start .. start + needle.len], needle) |left, right| {
            if (std.ascii.toLower(left) != std.ascii.toLower(right)) {
                equal = false;
                break;
            }
        }
        if (equal) return true;
    }
    return false;
}

pub const WorkoutResolution = union(enum) {
    found: tracking.Workout,
    not_found,
    ambiguous: []const tracking.Workout,
};

pub fn resolveActiveWorkout(
    explicit_id: ?tracking.Id,
    explicit_result: ?tracking.ReadWorkoutResult,
    active: tracking.ActiveWorkoutSelection,
) WorkoutResolution {
    if (explicit_id != null) {
        const result = explicit_result orelse return .not_found;
        return switch (result) {
            .found => |workout| .{ .found = workout },
            .not_found => .not_found,
        };
    }
    return switch (active) {
        .none => .not_found,
        .one => |workout| .{ .found = workout },
        .ambiguous => |workouts| .{ .ambiguous = workouts },
    };
}

test "exercise references resolve by documented precedence" {
    const exercises = [_]persistence.canonical.Exercise{
        .{ .id = "bench", .name = "Bench Press", .aliases = &.{"press"} },
        .{ .id = "incline-bench", .name = "Incline Bench", .aliases = &.{"press"} },
    };
    var output: [2]persistence.canonical.Exercise = undefined;
    try std.testing.expectEqualStrings(
        "bench",
        (try resolveExercise(&exercises, "bench", &output)).found.id,
    );
    try std.testing.expectEqualStrings(
        "bench",
        (try resolveExercise(&exercises, "Bench Press", &output)).found.id,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        (try resolveExercise(&exercises, "press", &output)).ambiguous.len,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        (try resolveExercise(&exercises, "BENCH", &output)).ambiguous.len,
    );
}
