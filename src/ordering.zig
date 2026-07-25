const std = @import("std");
const primitives = @import("primitives.zig");

pub const max_alternatives: u16 = 100;

/// A methodology-owned contribution retained for explainability.
pub const PriorityReason = struct {
    code: []const u8,
    score_contribution: i64 = 0,
    priority_contribution: i32 = 0,
};

/// A filtered candidate with methodology-supplied ranking values.
pub const Candidate = struct {
    exercise_id: primitives.Id,
    score: i64,
    priority: i32 = 0,
    reasons: []const PriorityReason = &.{},
};

pub const TieBreakPolicy = union(enum) {
    stable_id,
    seeded: []const u8,
};

pub const TieBreakDetail = struct {
    policy: enum { stable_id, seeded },
    key: ?u64 = null,
    reason_code: []const u8 = "alternative.ranked.stable_tiebreak",
};

/// A borrowed ranked view. Candidate reasons and score details remain visible.
pub const RankedCandidate = struct {
    candidate: *const Candidate,
    tie_break: ?TieBreakDetail = null,
};

pub const Result = struct {
    primary: ?RankedCandidate,
    alternatives: []const RankedCandidate,
};

pub const OrderError = error{
    AlternativeLimitExceeded,
    DuplicateId,
    EmptySeed,
    OutputLimitReached,
};

/// Orders filtered candidates without allocation or input-order dependence.
///
/// Higher score wins, followed by higher priority. Equal candidates use the
/// selected deterministic tie policy. A seed is data, not hidden randomness.
pub fn rank(
    candidates: []const Candidate,
    alternative_limit: u16,
    tie_policy: TieBreakPolicy,
    index_storage: []usize,
    alternative_storage: []RankedCandidate,
) OrderError!Result {
    if (alternative_limit > max_alternatives) {
        return error.AlternativeLimitExceeded;
    }
    const seed = switch (tie_policy) {
        .stable_id => null,
        .seeded => |value| if (value.len == 0) return error.EmptySeed else value,
    };
    if (index_storage.len < candidates.len) return error.OutputLimitReached;
    for (candidates, 0..) |candidate, candidate_index| {
        for (candidates[0..candidate_index]) |prior| {
            if (candidate.exercise_id.eql(prior.exercise_id)) {
                return error.DuplicateId;
            }
        }
        index_storage[candidate_index] = candidate_index;
    }

    // Stable insertion sort with a total comparator; original positions never
    // participate in ordering.
    for (index_storage[0..candidates.len], 0..) |candidate_index, position| {
        if (position == 0) continue;
        var insertion = position;
        while (insertion > 0 and comesBefore(
            candidates[candidate_index],
            candidates[index_storage[insertion - 1]],
            seed,
        )) {
            index_storage[insertion] = index_storage[insertion - 1];
            insertion -= 1;
        }
        index_storage[insertion] = candidate_index;
    }

    if (candidates.len == 0) {
        return .{ .primary = null, .alternatives = alternative_storage[0..0] };
    }
    const alternative_count = @min(
        @as(usize, alternative_limit),
        candidates.len - 1,
    );
    if (alternative_storage.len < alternative_count) {
        return error.OutputLimitReached;
    }

    const primary = rankedView(candidates, index_storage[0..candidates.len], 0, seed);
    for (0..alternative_count) |alternative_index| {
        alternative_storage[alternative_index] = rankedView(
            candidates,
            index_storage[0..candidates.len],
            alternative_index + 1,
            seed,
        );
    }
    return .{
        .primary = primary,
        .alternatives = alternative_storage[0..alternative_count],
    };
}

fn rankedView(
    candidates: []const Candidate,
    ordered_indices: []const usize,
    position: usize,
    seed: ?[]const u8,
) RankedCandidate {
    const candidate = &candidates[ordered_indices[position]];
    const tied_with_neighbor =
        (position > 0 and sameRank(
            candidate.*,
            candidates[ordered_indices[position - 1]],
        )) or
        (position + 1 < ordered_indices.len and sameRank(
            candidate.*,
            candidates[ordered_indices[position + 1]],
        ));
    return .{
        .candidate = candidate,
        .tie_break = if (tied_with_neighbor)
            if (seed) |value|
                .{ .policy = .seeded, .key = seededKey(value, candidate.exercise_id) }
            else
                .{ .policy = .stable_id }
        else
            null,
    };
}

fn comesBefore(left: Candidate, right: Candidate, seed: ?[]const u8) bool {
    if (left.score != right.score) return left.score > right.score;
    if (left.priority != right.priority) return left.priority > right.priority;
    if (seed) |value| {
        const left_key = seededKey(value, left.exercise_id);
        const right_key = seededKey(value, right.exercise_id);
        if (left_key != right_key) return left_key < right_key;
    }
    return std.mem.order(u8, left.exercise_id.bytes, right.exercise_id.bytes) == .lt;
}

fn sameRank(left: Candidate, right: Candidate) bool {
    return left.score == right.score and left.priority == right.priority;
}

fn seededKey(seed: []const u8, exercise_id: primitives.Id) u64 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("caudex:candidate-tiebreak:v1\x00");
    hash.update(seed);
    hash.update("\x00");
    hash.update(exercise_id.bytes);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.mem.readInt(u64, digest[0..8], .big);
}

fn rankedIds(result: Result, out: [][]const u8) []const []const u8 {
    var len: usize = 0;
    if (result.primary) |primary| {
        out[len] = primary.candidate.exercise_id.bytes;
        len += 1;
    }
    for (result.alternatives) |alternative| {
        out[len] = alternative.candidate.exercise_id.bytes;
        len += 1;
    }
    return out[0..len];
}

test "score priority and stable ID define a total order" {
    const reasons = [_]PriorityReason{.{
        .code = "exercise.preferred",
        .score_contribution = 10,
        .priority_contribution = 1,
    }};
    const candidates = [_]Candidate{
        .{ .exercise_id = try .parse("charlie"), .score = 10 },
        .{ .exercise_id = try .parse("alpha"), .score = 10, .priority = 1, .reasons = &reasons },
        .{ .exercise_id = try .parse("bravo"), .score = 10 },
        .{ .exercise_id = try .parse("delta"), .score = 5 },
    };
    var indices: [4]usize = undefined;
    var alternatives: [3]RankedCandidate = undefined;
    const result = try rank(
        &candidates,
        3,
        .stable_id,
        &indices,
        &alternatives,
    );
    var ids: [4][]const u8 = undefined;
    try std.testing.expectEqualDeep(
        &[_][]const u8{ "alpha", "bravo", "charlie", "delta" },
        rankedIds(result, &ids),
    );
    try std.testing.expectEqualStrings(
        "exercise.preferred",
        result.primary.?.candidate.reasons[0].code,
    );
    try std.testing.expectEqual(@as(i64, 10), result.primary.?.candidate.score);
    try std.testing.expectEqual(@as(i32, 1), result.primary.?.candidate.priority);
    try std.testing.expectEqualStrings(
        "alternative.ranked.stable_tiebreak",
        result.alternatives[0].tie_break.?.reason_code,
    );
}

test "input order does not determine output" {
    const forward = [_]Candidate{
        .{ .exercise_id = try .parse("alpha"), .score = 10 },
        .{ .exercise_id = try .parse("bravo"), .score = 20 },
        .{ .exercise_id = try .parse("charlie"), .score = 10 },
    };
    const reverse = [_]Candidate{ forward[2], forward[1], forward[0] };
    var forward_indices: [3]usize = undefined;
    var forward_alternatives: [2]RankedCandidate = undefined;
    const forward_result = try rank(
        &forward,
        2,
        .stable_id,
        &forward_indices,
        &forward_alternatives,
    );
    var reverse_indices: [3]usize = undefined;
    var reverse_alternatives: [2]RankedCandidate = undefined;
    const reverse_result = try rank(
        &reverse,
        2,
        .stable_id,
        &reverse_indices,
        &reverse_alternatives,
    );
    var forward_ids: [3][]const u8 = undefined;
    var reverse_ids: [3][]const u8 = undefined;
    try std.testing.expectEqualDeep(
        rankedIds(forward_result, &forward_ids),
        rankedIds(reverse_result, &reverse_ids),
    );
}

test "explicit seed tie breaking repeats across input order" {
    const forward = [_]Candidate{
        .{ .exercise_id = try .parse("alpha"), .score = 10 },
        .{ .exercise_id = try .parse("bravo"), .score = 10 },
        .{ .exercise_id = try .parse("charlie"), .score = 10 },
    };
    const reverse = [_]Candidate{ forward[2], forward[1], forward[0] };
    var first_indices: [3]usize = undefined;
    var first_alternatives: [2]RankedCandidate = undefined;
    const first = try rank(
        &forward,
        2,
        .{ .seeded = "host-seed-1" },
        &first_indices,
        &first_alternatives,
    );
    var second_indices: [3]usize = undefined;
    var second_alternatives: [2]RankedCandidate = undefined;
    const second = try rank(
        &reverse,
        2,
        .{ .seeded = "host-seed-1" },
        &second_indices,
        &second_alternatives,
    );
    var first_ids: [3][]const u8 = undefined;
    var second_ids: [3][]const u8 = undefined;
    try std.testing.expectEqualDeep(
        rankedIds(first, &first_ids),
        rankedIds(second, &second_ids),
    );
    try std.testing.expect(first.primary.?.tie_break.?.key != null);
    try std.testing.expectError(
        error.EmptySeed,
        rank(&forward, 0, .{ .seeded = "" }, &first_indices, &.{}),
    );
}

test "alternative count is bounded by request and canonical maximum" {
    const candidates = [_]Candidate{
        .{ .exercise_id = try .parse("alpha"), .score = 3 },
        .{ .exercise_id = try .parse("bravo"), .score = 2 },
        .{ .exercise_id = try .parse("charlie"), .score = 1 },
    };
    var indices: [3]usize = undefined;
    var alternatives: [1]RankedCandidate = undefined;
    const result = try rank(
        &candidates,
        1,
        .stable_id,
        &indices,
        &alternatives,
    );
    try std.testing.expectEqual(@as(usize, 1), result.alternatives.len);
    try std.testing.expectError(
        error.AlternativeLimitExceeded,
        rank(
            &candidates,
            max_alternatives + 1,
            .stable_id,
            &indices,
            &alternatives,
        ),
    );
}
