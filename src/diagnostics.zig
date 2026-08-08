const std = @import("std");
const canonical = @import("canonical.zig");

pub const max_issues: usize = 64;
pub const max_explanations: usize = 128;
pub const max_evidence_per_explanation: usize = 32;

/// Collects validation issues into caller-owned storage.
pub const IssueWriter = struct {
    storage: []canonical.ValidationIssue,
    len: usize = 0,

    pub const AppendError = error{LimitReached};

    pub fn init(storage: []canonical.ValidationIssue) IssueWriter {
        return .{ .storage = storage };
    }

    pub fn append(
        self: *IssueWriter,
        issue: canonical.ValidationIssue,
    ) AppendError!void {
        if (self.len >= self.storage.len or self.len >= max_issues) {
            return error.LimitReached;
        }
        self.storage[self.len] = issue;
        self.len += 1;
        std.debug.assert(self.len <= self.storage.len);
        std.debug.assert(self.len <= max_issues);
    }

    pub fn items(self: *const IssueWriter) []const canonical.ValidationIssue {
        return self.storage[0..self.len];
    }
};

/// Collects explanations into caller-owned storage.
pub const ExplanationWriter = struct {
    storage: []canonical.Explanation,
    len: usize = 0,

    pub const AppendError = error{
        LimitReached,
        EvidenceLimitReached,
        DuplicateId,
    };

    pub fn init(storage: []canonical.Explanation) ExplanationWriter {
        return .{ .storage = storage };
    }

    pub fn append(
        self: *ExplanationWriter,
        explanation: canonical.Explanation,
    ) AppendError!void {
        if (self.len >= self.storage.len or self.len >= max_explanations) {
            return error.LimitReached;
        }
        if (explanation.evidence.len > max_evidence_per_explanation) {
            return error.EvidenceLimitReached;
        }
        for (self.items()) |existing| {
            if (std.mem.eql(u8, existing.id, explanation.id)) {
                return error.DuplicateId;
            }
        }
        self.storage[self.len] = explanation;
        self.len += 1;
        std.debug.assert(self.len <= self.storage.len);
        std.debug.assert(self.len <= max_explanations);
    }

    pub fn items(self: *const ExplanationWriter) []const canonical.Explanation {
        return self.storage[0..self.len];
    }
};

/// A stable serialization view over collected issues and explanations.
pub const DiagnosticBundle = struct {
    issues: []const canonical.ValidationIssue,
    explanations: []const canonical.Explanation,

    pub fn writeJson(
        self: DiagnosticBundle,
        out: []u8,
    ) std.Io.Writer.Error![]const u8 {
        var writer: std.Io.Writer = .fixed(out);
        try std.json.Stringify.value(
            self,
            .{ .emit_null_optional_fields = false },
            &writer,
        );
        return writer.buffered();
    }
};

test "multiple issues collect in caller storage and stop at capacity" {
    var storage: [2]canonical.ValidationIssue = undefined;
    var writer: IssueWriter = .init(&storage);
    const first = canonical.ValidationIssue{
        .code = "catalog.duplicate_exercise_id",
        .path = "/catalog/1/id",
        .message = "The catalog repeats an exercise ID.",
        .severity = .@"error",
    };
    const second = canonical.ValidationIssue{
        .code = "history.insufficient_evidence",
        .path = "/history",
        .message = "Less history was supplied than the methodology prefers.",
        .severity = .warning,
    };

    try writer.append(first);
    try writer.append(second);
    try std.testing.expectEqual(@as(usize, 2), writer.items().len);
    try std.testing.expectError(error.LimitReached, writer.append(first));
}

test "issue count has a hard limit independent of caller capacity" {
    var storage: [max_issues + 1]canonical.ValidationIssue = undefined;
    var writer: IssueWriter = .init(&storage);
    const issue = canonical.ValidationIssue{
        .code = "history.insufficient_evidence",
        .path = "/history",
        .message = "Less history was supplied than the methodology prefers.",
        .severity = .warning,
    };

    for (0..max_issues) |_| try writer.append(issue);
    try std.testing.expectError(error.LimitReached, writer.append(issue));
}

test "explanations retain subjects and evidence with bounded unique IDs" {
    var storage: [2]canonical.Explanation = undefined;
    var writer: ExplanationWriter = .init(&storage);
    const evidence = [_]canonical.EvidenceRef{
        .{ .path = "/session/availableEquipmentIds" },
    };
    const explanation = canonical.Explanation{
        .id = "explanation-1",
        .code = "exercise.selected.available_equipment",
        .category = "selection",
        .summary = "Available equipment supported the exercise selection.",
        .subject = .{ .exerciseId = "incline-dumbbell-press" },
        .evidence = &evidence,
        .severity = .info,
    };

    try writer.append(explanation);
    try std.testing.expectEqualStrings(
        "incline-dumbbell-press",
        writer.items()[0].subject.?.exerciseId.?,
    );
    try std.testing.expectEqualStrings(
        "/session/availableEquipmentIds",
        writer.items()[0].evidence[0].path,
    );
    try std.testing.expectError(error.DuplicateId, writer.append(explanation));

    const excessive_evidence =
        [_]canonical.EvidenceRef{.{ .path = "/@derived/history" }} **
        (max_evidence_per_explanation + 1);
    var second_storage: [1]canonical.Explanation = undefined;
    var second_writer: ExplanationWriter = .init(&second_storage);
    try std.testing.expectError(
        error.EvidenceLimitReached,
        second_writer.append(.{
            .id = "explanation-2",
            .code = "progression.held.insufficient_evidence",
            .category = "progression",
            .summary = "Evidence was insufficient to advance progression.",
            .evidence = &excessive_evidence,
            .severity = .warning,
        }),
    );
}
