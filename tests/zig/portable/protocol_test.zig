const std = @import("std");
const portable = @import("caudex_portable");
const assets = @import("repository_test_assets");

test "portable fixture preserves exact decimals and deterministic bytes" {
    const fixture = assets.portable_export;
    const parsed = try portable.decodeDocument(std.testing.allocator, fixture);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("185.00", parsed.value.completedWorkouts[0].workout.exercises[0].sets[0].actualMetrics[0].value.amount);
    var output: [8192]u8 = undefined;
    try std.testing.expectEqualStrings(std.mem.trimEnd(u8, fixture, "\r\n"), try portable.encode(parsed.value, &output));
    var issues: [portable.max_issues]portable.Issue = undefined;
    const plan = try portable.planImport(.{
        .schemaVersion = 1,
        .mode = .merge,
        .conflictPolicy = .reject,
        .dryRun = true,
        .document = parsed.value,
    }, &issues);
    try std.testing.expect(plan.valid);
    try std.testing.expect(plan.dryRun);
    try std.testing.expectEqual(@as(usize, 1), plan.counts.completedWorkouts);
}

test "portable validation returns structured duplicate and reference issues" {
    const references = [_]portable.CatalogReference{
        .{ .hostScopeKey = "scope-1", .exerciseId = "z" },
        .{ .hostScopeKey = "scope-1", .exerciseId = "z" },
    };
    const active = [_]portable.ActiveWorkoutRecord{.{
        .hostScopeKey = "scope-1",
        .workoutId = "workout-1",
        .snapshot = .{ .workouts = &.{.{
            .id = "workout-1",
            .scope = .{ .hostScopeKey = "scope-1" },
            .revision = 1,
            .status = .active,
            .startedAt = "2026-08-04T12:00:00Z",
            .exercises = &.{.{ .id = "membership-1", .exerciseId = "missing" }},
        }} },
    }};
    var issues: [8]portable.Issue = undefined;
    const plan = try portable.planImport(.{
        .schemaVersion = 1,
        .mode = .replace,
        .conflictPolicy = .overwrite,
        .document = .{
            .schemaVersion = 1,
            .exportedAt = "2026-08-04T12:00:00Z",
            .catalogReferences = &references,
            .activeWorkouts = &active,
        },
    }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expectEqualStrings("portable.duplicate_id", plan.issues[0].code);
    try std.testing.expectEqualStrings("portable.catalog_reference_missing", plan.issues[1].code);
}

test "portable protocol rejects unsupported versions and byte limits" {
    const fixture = assets.portable_export;
    var unsupported = try std.testing.allocator.dupe(u8, fixture);
    defer std.testing.allocator.free(unsupported);
    unsupported[17] = '2';
    try std.testing.expectError(error.UnsupportedVersion, portable.decodeDocument(std.testing.allocator, unsupported));
    const oversized = try std.testing.allocator.alloc(u8, portable.max_input_bytes + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, ' ');
    try std.testing.expectError(error.InputTooLarge, portable.decodeDocument(std.testing.allocator, oversized));
}

test "portable document round-trips mixed progression provenance and isolated states" {
    const input =
        \\{"schemaVersion":1,"exportedAt":"2026-08-10T14:00:00Z","catalogReferences":[],"customExercises":[],"templates":[],"activeWorkouts":[],"completedWorkouts":[],"acceptedRecommendations":[],"acceptedProgramRecommendations":[{"id":"accepted-mixed","hostScopeKey":"scope-1","acceptedAt":"2026-08-10T14:00:00Z","result":{"ok":true,"recommendation":{"exercises":[{"exerciseId":"a","sets":[],"programming":{"slotId":"slot-a","stateId":"state-a","progression":{"id":"caudex.double-progression","version":"0.1.0","configVersion":1},"config":{}}},{"exerciseId":"b","sets":[],"programming":{"slotId":"slot-b","stateId":"state-b","progression":{"id":"caudex.rpe-top-set-backoff","version":"0.1.0","configVersion":1},"config":{}}}],"programming":{"strategy":{"id":"caudex.fixed-session","version":"0.1.0","configVersion":1},"config":{}}},"metadata":{"engineVersion":"0.1.0","schemaVersion":1,"programStrategy":{"id":"caudex.fixed-session","version":"0.1.0","configVersion":1},"inputFingerprint":"input","resultFingerprint":"result"}}}],"methodologyStates":[],"progressionStates":[{"hostScopeKey":"scope-1","stateId":"state-a","progressionId":"caudex.double-progression","progressionVersion":"0.1.0","state":{"schemaVersion":1,"data":{}},"revision":"1","updatedAt":"2026-08-10T14:00:00Z"},{"hostScopeKey":"scope-1","stateId":"state-b","progressionId":"caudex.rpe-top-set-backoff","progressionVersion":"0.1.0","state":{"schemaVersion":1,"data":{}},"revision":"1","updatedAt":"2026-08-10T14:00:00Z"}],"programStates":[],"workflowRecovery":[]}
    ;
    const parsed = try portable.decodeDocument(std.testing.allocator, input);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.acceptedProgramRecommendations.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.progressionStates.len);
    const recommendation = parsed.value.acceptedProgramRecommendations[0].result.recommendation.?;
    try std.testing.expectEqualStrings("state-a", recommendation.exercises[0].programming.?.stateId);
    try std.testing.expectEqualStrings("caudex.rpe-top-set-backoff", recommendation.exercises[1].programming.?.progression.id);
    var output: [8192]u8 = undefined;
    const encoded = try portable.encode(parsed.value, &output);
    const replayed = try portable.decodeDocument(std.testing.allocator, encoded);
    defer replayed.deinit();
    try std.testing.expectEqualStrings("state-b", replayed.value.progressionStates[1].stateId);
    var replay_output: [8192]u8 = undefined;
    try std.testing.expectEqualStrings(encoded, try portable.encode(replayed.value, &replay_output));
}

test "portable semantic validation returns stable timestamp decimal and unit issues" {
    const document: portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = "not-a-time",
        .catalogReferences = &.{.{ .hostScopeKey = "scope-1", .exerciseId = "squat" }},
        .completedWorkouts = &.{.{
            .hostScopeKey = "scope-1",
            .workout = .{
                .id = "workout-1",
                .startedAt = "invalid",
                .completedAt = "also-invalid",
                .exercises = &.{.{ .exerciseId = "squat", .sets = &.{.{
                    .kind = "working",
                    .actualMetrics = &.{.{ .code = "load", .value = .{ .amount = "01.0", .unit = "stone" } }},
                    .status = .completed,
                }} }},
            },
        }},
    };
    var issues: [16]portable.Issue = undefined;
    const plan = try portable.planImport(.{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .document = document }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expect(hasIssue(plan.issues, "portable.timestamp_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.decimal_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.unit_unknown"));
}

test "portable athlete profiles are sorted, counted, and validated" {
    const profiles = [_]portable.AthleteProfileRecord{
        .{ .hostScopeKey = "scope-1", .profile = .{ .id = "profile-b", .revision = 2 } },
        .{ .hostScopeKey = "scope-1", .profile = .{ .id = "profile-a", .revision = 1 } },
        .{ .hostScopeKey = "scope-2", .profile = .{ .id = "", .schemaVersion = 2 } },
    };
    var issues: [8]portable.Issue = undefined;
    const plan = try portable.planImport(.{
        .schemaVersion = 1,
        .mode = .merge,
        .conflictPolicy = .reject,
        .document = .{
            .schemaVersion = 1,
            .exportedAt = "2026-08-10T14:00:00Z",
            .athleteProfiles = &profiles,
        },
    }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expectEqual(@as(usize, 3), plan.counts.athleteProfiles);
    try std.testing.expect(hasIssue(plan.issues, "portable.order_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.profile_version_unsupported"));
    try std.testing.expect(hasIssue(plan.issues, "portable.profile_id_invalid"));
}

test "portable program records round-trip custom definitions and active planning state" {
    const definitions = [_]portable.ProgramDefinitionRecord{.{
        .hostScopeKey = "scope-1",
        .definition = .{
            .id = "host.custom.upper-lower",
            .version = "7",
            .displayName = "My upper/lower",
            .strategy = .{ .id = "caudex.fixed-session", .configVersion = 1, .config = .null },
            .configurationFingerprint = "definition-fingerprint",
            .source = .{ .kind = .host_custom, .id = "host-program-7" },
            .blocks = &.{.{
                .id = "accumulation",
                .microcycleCount = 4,
                .phase = .accumulation,
                .schedule = .{ .rotation = .{ .roleIds = &.{"upper-a"} } },
                .sessionRoles = &.{.{
                    .id = "upper-a",
                    .items = &.{.{ .fixed = .{
                        .id = "bench",
                        .exerciseId = "bench-press",
                        .progression = .{
                            .stateId = "bench-lane",
                            .methodology = .{ .id = "caudex.double-progression", .configVersion = 1, .config = .null },
                        },
                    } }},
                }},
            }},
        },
    }};
    const instances = [_]portable.ProgramInstanceRecord{.{
        .hostScopeKey = "scope-1",
        .instance = .{
            .id = "program-run-1",
            .athleteId = "athlete-1",
            .definition = .{ .id = "host.custom.upper-lower", .version = "7", .configurationFingerprint = "definition-fingerprint" },
            .startedOn = "2026-08-10",
            .lifecycle = .active,
            .configuration = .null,
        },
        .planningState = .{
            .instanceId = "program-run-1",
            .definition = .{ .id = "host.custom.upper-lower", .version = "7", .configurationFingerprint = "definition-fingerprint" },
            .revision = 9,
            .blockIndex = 0,
            .microcycleIndex = 1,
            .sessionCursor = 0,
            .completedOccurrenceCount = 8,
        },
    }};
    const occurrences = [_]portable.ProgramOccurrenceRecord{.{
        .hostScopeKey = "scope-1",
        .occurrence = .{
            .instanceId = "program-run-1",
            .definition = .{ .id = "host.custom.upper-lower", .version = "7", .configurationFingerprint = "definition-fingerprint" },
            .blockId = "accumulation",
            .roleId = "upper-a",
            .occurrenceId = "occurrence-9",
            .status = .completed,
            .beforeRevision = 8,
            .afterRevision = 9,
        },
    }};
    const document: portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = "2026-08-10T14:00:00Z",
        .programDefinitions = &definitions,
        .programInstances = &instances,
        .programOccurrences = &occurrences,
    };
    var issues: [16]portable.Issue = undefined;
    const plan = try portable.planImport(.{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .document = document }, &issues);
    try std.testing.expect(plan.valid);
    try std.testing.expectEqual(@as(usize, 1), plan.counts.programDefinitions);
    try std.testing.expectEqual(@as(usize, 1), plan.counts.programInstances);
    try std.testing.expectEqual(@as(usize, 1), plan.counts.programOccurrences);

    var output: [16 * 1024]u8 = undefined;
    const encoded = try portable.encode(document, &output);
    const parsed = try portable.decodeDocument(std.testing.allocator, encoded);
    defer parsed.deinit();
    try std.testing.expectEqual(.host_custom, parsed.value.programDefinitions[0].definition.source.?.kind);
    try std.testing.expectEqual(@as(u64, 9), parsed.value.programInstances[0].planningState.?.revision);
    try std.testing.expectEqualStrings("upper-a", parsed.value.programOccurrences[0].occurrence.roleId);
}

test "portable program validation covers ordering references revisions and nested bounds" {
    const definitions = [_]portable.ProgramDefinitionRecord{
        .{
            .hostScopeKey = "scope-1",
            .definition = .{
                .id = "z-definition",
                .version = "1",
                .displayName = "Z",
                .strategy = .{ .id = "caudex.fixed-session", .configVersion = 1, .config = .null },
                .configurationFingerprint = "z-fingerprint",
                .blocks = &.{.{ .id = "block", .microcycleCount = 1, .schedule = .{ .rotation = .{ .roleIds = &.{"role"} } }, .sessionRoles = &.{.{ .id = "role", .items = &.{.{ .fixed = .{
                    .id = "slot",
                    .exerciseId = "exercise",
                    .progression = .{ .stateId = "state", .methodology = .{ .id = "method", .configVersion = 1, .config = .null } },
                } }} }} }},
            },
        },
        .{
            .hostScopeKey = "scope-1",
            .definition = .{
                .id = "a-definition",
                .version = "1",
                .displayName = "A",
                .strategy = .{ .id = "caudex.fixed-session", .configVersion = 1, .config = .null },
                .configurationFingerprint = "a-fingerprint",
                .blocks = &.{.{ .id = "block", .microcycleCount = 1, .schedule = .{ .rotation = .{ .roleIds = &.{"role"} } }, .sessionRoles = &.{.{ .id = "role", .items = &.{.{ .fixed = .{
                    .id = "slot",
                    .exerciseId = "exercise",
                    .progression = .{ .stateId = "state", .methodology = .{ .id = "method", .configVersion = 1, .config = .null } },
                } }} }} }},
            },
        },
    };
    const instances = [_]portable.ProgramInstanceRecord{.{
        .hostScopeKey = "scope-1",
        .instance = .{
            .id = "instance-1",
            .athleteId = "athlete-1",
            .definition = .{ .id = "missing", .version = "1", .configurationFingerprint = "missing-fingerprint" },
            .startedOn = "2026-02-30",
            .lifecycle = .active,
            .configuration = .null,
        },
    }};
    const occurrences = [_]portable.ProgramOccurrenceRecord{.{
        .hostScopeKey = "scope-1",
        .occurrence = .{
            .instanceId = "instance-1",
            .definition = .{ .id = "missing", .version = "1", .configurationFingerprint = "missing-fingerprint" },
            .blockId = "missing-block",
            .roleId = "missing-role",
            .occurrenceId = "occurrence-1",
            .status = .upcoming,
            .beforeRevision = 4,
            .afterRevision = 9,
        },
    }};
    const document: portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = "2026-08-10T14:00:00Z",
        .programDefinitions = &definitions,
        .programInstances = &instances,
        .programOccurrences = &occurrences,
    };
    var issues: [16]portable.Issue = undefined;
    const plan = try portable.planImport(.{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .document = document }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expect(hasIssue(plan.issues, "portable.order_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.program_started_on_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.program_definition_missing"));
    try std.testing.expect(hasIssue(plan.issues, "portable.program_active_state_missing"));
    try std.testing.expect(hasIssue(plan.issues, "portable.program_occurrence_revision_invalid"));

    const Block = @TypeOf(definitions[0].definition.blocks[0]);
    const oversized_blocks = try std.testing.allocator.alloc(Block, portable.max_program_blocks + 1);
    defer std.testing.allocator.free(oversized_blocks);
    @memset(oversized_blocks, definitions[0].definition.blocks[0]);
    var oversized_definition = definitions[0];
    oversized_definition.definition.blocks = oversized_blocks;
    try std.testing.expectError(error.RecordLimitExceeded, portable.validateDocumentBounds(.{
        .schemaVersion = 1,
        .exportedAt = "2026-08-10T14:00:00Z",
        .programDefinitions = &.{oversized_definition},
    }));
}

fn hasIssue(issues: []const portable.Issue, code: []const u8) bool {
    for (issues) |issue| if (std.mem.eql(u8, issue.code, code)) return true;
    return false;
}
