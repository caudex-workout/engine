const std = @import("std");
const caudex = @import("caudex");
const caudex_persistence = @import("caudex_persistence");
const caudex_exercise_catalog = @import("caudex_exercise_catalog");
const caudex_portable = @import("caudex_portable");
const caudex_sqlite = @import("caudex_sqlite");
const caudex_tracking = @import("caudex_tracking");

const Config = struct {
    working_sets: u8,
};

const Output = struct {
    recommendations: usize = 0,
    evaluations: usize = 0,
};

fn validateConfig(
    view: caudex.methodology.ConfigView,
    issues: *caudex.diagnostics.IssueWriter,
) caudex.diagnostics.IssueWriter.AppendError!void {
    const config: *const Config = @ptrCast(@alignCast(view.context));
    if (config.working_sets == 0) {
        try issues.append(.{
            .code = "vendor.simple.config_invalid",
            .path = "/methodology/config/workingSets",
            .message = "Working sets must be positive.",
            .severity = .@"error",
        });
    }
}

fn validateState(
    config: caudex.methodology.ConfigView,
    state: caudex.methodology.StateView,
    issues: *caudex.diagnostics.IssueWriter,
) caudex.diagnostics.IssueWriter.AppendError!void {
    _ = config;
    _ = state;
    _ = issues;
}

fn recommend(
    request: caudex.methodology.RecommendationView,
    scratch: *caudex.methodology.Scratch,
    writer: *caudex.methodology.RecommendationWriter,
) caudex.methodology.MethodologyError!void {
    _ = request;
    _ = scratch;
    const output: *Output = @ptrCast(@alignCast(writer.context));
    output.recommendations += 1;
}

fn evaluate(
    request: caudex.methodology.EvaluationView,
    scratch: *caudex.methodology.Scratch,
    writer: *caudex.methodology.EvaluationWriter,
) caudex.methodology.MethodologyError!void {
    _ = request;
    _ = scratch;
    const output: *Output = @ptrCast(@alignCast(writer.context));
    output.evaluations += 1;
}

const simple_methodology = caudex.methodology.Methodology{
    .metadata = .{
        .id = .{ .bytes = "vendor.simple-progression" },
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .config_version = 1,
        .state_schema_version = 1,
    },
    .validate_config = validateConfig,
    .validate_state = validateState,
    .recommend_session = recommend,
    .evaluate_performance = evaluate,
};

pub fn main() !void {
    try verifyMultiExerciseRecommendation();
    if (caudex_persistence.contract_version != 3)
        return error.UnsupportedPersistenceContract;
    if (caudex_persistence.canonical != caudex.canonical)
        return error.PersistenceUsesDifferentCanonicalContract;
    if (caudex_tracking.contract_version != 6)
        return error.UnsupportedTrackingContract;
    if (caudex_portable.schema_version != 1)
        return error.UnsupportedPortableSchema;
    const database = try caudex_sqlite.openInMemory(.{});
    defer database.close();
    const database_metadata = try database.metadata();
    if (database_metadata.schema_version != caudex_sqlite.schema_version)
        return error.UnexpectedSqliteSchema;
    const catalog = try caudex_exercise_catalog.load(std.heap.page_allocator);
    defer catalog.deinit();
    if (catalog.value.records.len != 873) return error.UnexpectedCatalog;

    const registry = caudex.methodology.Registry.initComptime(
        &.{simple_methodology},
    );
    const id = try caudex.primitives.Id.parse("vendor.simple-progression");
    const implementation = registry.find(
        id,
        .{ .major = 1, .minor = 0, .patch = 0 },
    ) orelse return error.MethodologyNotFound;

    const config = Config{ .working_sets = 3 };
    var issue_storage: [4]caudex.canonical.ValidationIssue = undefined;
    var issues = caudex.diagnostics.IssueWriter.init(&issue_storage);
    try implementation.validate_config(.{ .context = &config }, &issues);
    if (issues.items().len != 0) return error.InvalidConfig;

    var output = Output{};
    var scratch = caudex.methodology.Scratch{ .bytes = &.{} };
    var writer = caudex.methodology.RecommendationWriter{
        .context = &output,
    };
    const TypedRequest = caudex.methodology.TypedRecommendationRequest(
        Config,
        Config,
        Config,
    );
    try caudex.methodology.recommendTyped(
        implementation,
        TypedRequest{ .config = config, .payload = config },
        &issues,
        &scratch,
        &writer,
    );
    if (output.recommendations != 1) return error.UnexpectedOutput;

    std.debug.print(
        "{s} registered; persistence contract v{d}, tracking contract v{d}, SQLite schema v{d}, and catalog {s} imported\n",
        .{
            implementation.metadata.id.bytes,
            caudex_persistence.contract_version,
            caudex_tracking.contract_version,
            database_metadata.schema_version,
            catalog.value.fingerprint,
        },
    );
}

fn verifyMultiExerciseRecommendation() !void {
    const exercises = [_]caudex.training.Exercise{
        .{ .id = try .parse("squat") },
        .{ .id = try .parse("bench-press") },
    };
    var output: caudex.engine.Output = .{};
    const result = try caudex.engine.recommendSession(.{
        .as_of = try .parse("2026-08-10T12:00:00Z"),
        .methodology_id = try .parse(caudex.double_progression.methodology_id),
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
        .available_equipment_ids = &.{},
    }, &output);
    if (result.recommendation.?.exercises.len != 2)
        return error.UnexpectedExerciseCount;
}
