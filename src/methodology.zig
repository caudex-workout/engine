const std = @import("std");
const diagnostics = @import("diagnostics.zig");
const primitives = @import("primitives.zig");

pub const Id = primitives.Id;

/// An exact methodology implementation version.
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn eql(left: Version, right: Version) bool {
        return left.major == right.major and
            left.minor == right.minor and
            left.patch == right.patch;
    }
};

pub const Metadata = struct {
    id: Id,
    version: Version,
    config_version: u32,
};

/// An implementation-owned configuration view.
pub const ConfigView = struct {
    context: *const anyopaque,
};

/// An implementation-owned recommendation request view.
pub const RecommendationView = struct {
    context: *const anyopaque,
};

/// An implementation-owned performance-evaluation request view.
pub const EvaluationView = struct {
    context: *const anyopaque,
};

/// Caller-owned scratch memory available to a methodology calculation.
pub const Scratch = struct {
    bytes: []u8,
};

/// An implementation-owned recommendation output handle.
pub const RecommendationWriter = struct {
    context: *anyopaque,
};

/// An implementation-owned evaluation output handle.
pub const EvaluationWriter = struct {
    context: *anyopaque,
};

pub const MethodologyError = error{
    InvalidInput,
    OutputLimitReached,
};

pub const ValidateConfigFn = *const fn (
    config: ConfigView,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void;

pub const RecommendSessionFn = *const fn (
    request: RecommendationView,
    scratch: *Scratch,
    out: *RecommendationWriter,
) MethodologyError!void;

pub const EvaluatePerformanceFn = *const fn (
    request: EvaluationView,
    scratch: *Scratch,
    out: *EvaluationWriter,
) MethodologyError!void;

/// A methodology implementation compiled into a host.
pub const Methodology = struct {
    metadata: Metadata,
    validate_config: ValidateConfigFn,
    recommend_session: RecommendSessionFn,
    evaluate_performance: EvaluatePerformanceFn,
};

/// A deterministic borrowed view over compiled methodology implementations.
pub const Registry = struct {
    methodologies: []const Methodology,

    pub const InitError = error{DuplicateId};

    pub fn init(methodologies: []const Methodology) InitError!Registry {
        for (methodologies, 0..) |candidate, candidate_index| {
            for (methodologies[0..candidate_index]) |prior| {
                if (prior.metadata.id.eql(candidate.metadata.id)) {
                    return error.DuplicateId;
                }
            }
        }
        return .{ .methodologies = methodologies };
    }

    /// Creates a static registry and fails compilation when IDs are duplicated.
    pub fn initComptime(comptime methodologies: []const Methodology) Registry {
        for (methodologies, 0..) |candidate, candidate_index| {
            for (methodologies[0..candidate_index]) |prior| {
                if (candidate.metadata.id.eql(prior.metadata.id)) {
                    @compileError("duplicate methodology ID: " ++ candidate.metadata.id.bytes);
                }
            }
        }
        return .{ .methodologies = methodologies };
    }

    /// Finds the one registered methodology with the requested ID and version.
    pub fn find(
        self: Registry,
        id: Id,
        version: ?Version,
    ) ?*const Methodology {
        for (self.methodologies) |*candidate| {
            if (!candidate.metadata.id.eql(id)) continue;
            if (version) |required| {
                if (!candidate.metadata.version.eql(required)) continue;
            }
            return candidate;
        }
        return null;
    }
};

const TestConfig = struct {
    valid: bool,
};

const TestOutput = struct {
    calls: usize = 0,
};

fn validateTestConfig(
    view: ConfigView,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const config: *const TestConfig = @ptrCast(@alignCast(view.context));
    if (!config.valid) {
        try issues.append(.{
            .code = "methodology.config_invalid",
            .path = "/methodology/config",
            .message = "The methodology configuration is invalid.",
            .severity = .@"error",
        });
    }
}

fn recommendTestSession(
    request: RecommendationView,
    scratch: *Scratch,
    out: *RecommendationWriter,
) MethodologyError!void {
    _ = request;
    _ = scratch;
    const output: *TestOutput = @ptrCast(@alignCast(out.context));
    output.calls += 1;
}

fn evaluateTestPerformance(
    request: EvaluationView,
    scratch: *Scratch,
    out: *EvaluationWriter,
) MethodologyError!void {
    _ = request;
    _ = scratch;
    const output: *TestOutput = @ptrCast(@alignCast(out.context));
    output.calls += 1;
}

fn testMethodology(id: []const u8, version: Version) Methodology {
    return .{
        .metadata = .{
            .id = .{ .bytes = id },
            .version = version,
            .config_version = 1,
        },
        .validate_config = validateTestConfig,
        .recommend_session = recommendTestSession,
        .evaluate_performance = evaluateTestPerformance,
    };
}

test "registry lookup is stable by ID and version" {
    const first = testMethodology(
        "caudex.double-progression",
        .{ .major = 0, .minor = 1, .patch = 0 },
    );
    const second = testMethodology(
        "caudex.rpe-top-set-backoff",
        .{ .major = 0, .minor = 2, .patch = 0 },
    );
    const entries = [_]Methodology{ first, second };
    const registry = try Registry.init(&entries);

    const found = registry.find(
        try Id.parse("caudex.rpe-top-set-backoff"),
        .{ .major = 0, .minor = 2, .patch = 0 },
    ).?;
    try std.testing.expectEqualStrings(
        "caudex.rpe-top-set-backoff",
        found.metadata.id.bytes,
    );
    try std.testing.expect(registry.find(
        try Id.parse("caudex.rpe-top-set-backoff"),
        .{ .major = 0, .minor = 1, .patch = 0 },
    ) == null);
}

test "registry rejects duplicate IDs deterministically" {
    const entries = [_]Methodology{
        testMethodology("vendor.same", .{ .major = 1, .minor = 0, .patch = 0 }),
        testMethodology("vendor.same", .{ .major = 2, .minor = 0, .patch = 0 }),
    };
    try std.testing.expectError(error.DuplicateId, Registry.init(&entries));
}

test "static registry accepts unique compiled methodologies" {
    const registry = Registry.initComptime(&.{
        testMethodology("vendor.first", .{ .major = 1, .minor = 0, .patch = 0 }),
        testMethodology("vendor.second", .{ .major = 1, .minor = 0, .patch = 0 }),
    });
    try std.testing.expectEqual(@as(usize, 2), registry.methodologies.len);
}

test "methodology callbacks are explicit and callable" {
    const implementation = testMethodology(
        "vendor.callback-test",
        .{ .major = 1, .minor = 0, .patch = 0 },
    );
    const invalid_config = TestConfig{ .valid = false };
    var issue_storage: [1]@import("canonical.zig").ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try implementation.validate_config(
        .{ .context = &invalid_config },
        &issues,
    );
    try std.testing.expectEqual(@as(usize, 1), issues.items().len);

    var request_context: u8 = 0;
    var scratch_bytes: [16]u8 = undefined;
    var scratch = Scratch{ .bytes = &scratch_bytes };
    var recommendation_output = TestOutput{};
    var recommendation_writer = RecommendationWriter{
        .context = &recommendation_output,
    };
    try implementation.recommend_session(
        .{ .context = &request_context },
        &scratch,
        &recommendation_writer,
    );
    try std.testing.expectEqual(@as(usize, 1), recommendation_output.calls);

    var evaluation_output = TestOutput{};
    var evaluation_writer = EvaluationWriter{ .context = &evaluation_output };
    try implementation.evaluate_performance(
        .{ .context = &request_context },
        &scratch,
        &evaluation_writer,
    );
    try std.testing.expectEqual(@as(usize, 1), evaluation_output.calls);
}
