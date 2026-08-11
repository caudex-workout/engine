const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const assets = @import("repository_test_assets");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const exercises = [_]persistence.canonical.Exercise{
    .{ .id = "squat" },
    .{ .id = "bench-press" },
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
const state: persistence.canonical.MethodologyState = .{
    .schemaVersion = 1,
    .data = .{ .object = .empty },
};
const key: persistence.MethodologyStateKey = .{
    .host_scope_key = "athlete-1",
    .methodology_id = "caudex.double-progression",
};
const athlete_profile_key: persistence.AthleteProfileKey = .{
    .host_scope_key = "host-1",
    .athlete_profile_id = "athlete-profile-1",
};
const athlete_profile: persistence.canonical.AthleteProfile = .{
    .id = "athlete-profile-1",
};
const program_reference: persistence.canonical.ProgramDefinitionReference = .{
    .id = "host.upper-lower",
    .version = "1",
    .configurationFingerprint = "definition-fingerprint",
};
const program_definition_record: persistence.ProgramDefinitionRecord = .{
    .key = .{
        .host_scope_key = "scope-1",
        .definition_id = program_reference.id,
        .definition_version = program_reference.version,
    },
    .definition = .{
        .id = program_reference.id,
        .version = program_reference.version,
        .displayName = "Upper/lower",
        .strategy = .{ .id = "caudex.fixed-session", .configVersion = 1, .config = .null },
        .configurationFingerprint = program_reference.configurationFingerprint,
        .source = .{ .kind = .host_custom },
        .blocks = &.{.{
            .id = "block-1",
            .microcycleCount = 4,
            .schedule = .{ .rotation = .{ .roleIds = &.{"upper"} } },
            .sessionRoles = &.{.{
                .id = "upper",
                .items = &.{.{ .fixed = .{
                    .id = "bench",
                    .exerciseId = "bench-press",
                    .progression = .{
                        .stateId = "bench-lane",
                        .methodology = .{
                            .id = "caudex.double-progression",
                            .configVersion = 1,
                            .config = .null,
                        },
                    },
                } }},
            }},
        }},
    },
};
const program_initial_instance: persistence.ProgramInstanceRecord = .{
    .key = .{ .host_scope_key = "scope-1", .instance_id = "run-1" },
    .instance = .{
        .id = "run-1",
        .athleteId = "athlete-1",
        .definition = program_reference,
        .lifecycle = .active,
        .configuration = .null,
    },
    .planning_state = .{
        .instanceId = "run-1",
        .definition = program_reference,
        .revision = 0,
        .blockIndex = 0,
        .microcycleIndex = 0,
        .sessionCursor = 0,
        .completedOccurrenceCount = 0,
    },
};
const program_next_instance: persistence.ProgramInstanceRecord = .{
    .key = program_initial_instance.key,
    .instance = program_initial_instance.instance,
    .planning_state = .{
        .instanceId = "run-1",
        .definition = program_reference,
        .revision = 1,
        .blockIndex = 0,
        .microcycleIndex = 1,
        .sessionCursor = 0,
        .completedOccurrenceCount = 1,
    },
};
const program_occurrence_record: persistence.ProgramOccurrenceRecord = .{
    .key = .{ .host_scope_key = "scope-1", .instance_id = "run-1", .occurrence_id = "occurrence-1" },
    .occurrence = .{
        .instanceId = "run-1",
        .definition = program_reference,
        .blockId = "block-1",
        .roleId = "upper",
        .occurrenceId = "occurrence-1",
        .status = .completed,
        .beforeRevision = 0,
        .afterRevision = 1,
    },
};

test "athlete profiles compare-and-set independently from methodology state" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect((try adapter.athleteProfileStore().load(
        allocator,
        athlete_profile_key,
    )) == null);
    const first = try adapter.athleteProfileStore().compareAndSet(allocator, .{
        .key = athlete_profile_key,
        .expected_revision = null,
        .next_profile = athlete_profile,
    });
    try std.testing.expectEqual(@as(u64, 1), first.profile.revision);
    try std.testing.expectError(
        error.Conflict,
        adapter.athleteProfileStore().compareAndSet(allocator, .{
            .key = athlete_profile_key,
            .expected_revision = null,
            .next_profile = athlete_profile,
        }),
    );
    const second = try adapter.athleteProfileStore().compareAndSet(allocator, .{
        .key = athlete_profile_key,
        .expected_revision = first.profile.revision,
        .next_profile = athlete_profile,
    });
    try std.testing.expectEqual(@as(u64, 2), second.profile.revision);
    const loaded = (try adapter.athleteProfileStore().load(
        allocator,
        athlete_profile_key,
    )).?;
    try std.testing.expectEqual(@as(u64, 2), loaded.profile.revision);
    try std.testing.expectEqualStrings("athlete-profile-1", loaded.profile.id);
}

test "in-memory adapter loads canonical snapshots and compare-and-sets state" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    const metadata = try adapter.metadata();
    try std.testing.expectEqual(sqlite.DatabaseKind.memory, metadata.database_kind);
    try std.testing.expectEqual(sqlite.Compatibility.current, metadata.compatibility);
    try std.testing.expectEqual(sqlite.schema_version, metadata.schema_version);
    try std.testing.expectEqualStrings(sqlite.adapter_version, metadata.adapter_version);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try adapter.replaceCatalog(allocator, .{
        .host_scope_key = "athlete-1",
        .as_of = "2026-07-26T12:00:00Z",
    }, &exercises);
    const catalog = try adapter.catalogSource().load(allocator, .{
        .host_scope_key = "athlete-1",
        .as_of = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("bench-press", catalog[0].id);
    try std.testing.expectEqualStrings("squat", catalog[1].id);

    try adapter.appendCompletedWorkout(allocator, "athlete-1", workouts[0]);
    try adapter.appendCompletedWorkout(allocator, "athlete-1", workouts[1]);
    const history = try adapter.historySource().load(allocator, .{
        .host_scope_key = "athlete-1",
        .through = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("earlier", history.workouts[0].id);
    try std.testing.expectEqualStrings("later", history.workouts[1].id);

    const first = try adapter.stateStore().compareAndSet(allocator, .{
        .key = key,
        .expected_revision = null,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("1", first.revision);
    try std.testing.expectError(
        error.Conflict,
        adapter.stateStore().compareAndSet(allocator, .{
            .key = key,
            .expected_revision = null,
            .methodology_version = "0.1.0",
            .next_state = state,
            .updated_at = "2026-07-26T12:01:00Z",
        }),
    );
    const second = try adapter.stateStore().compareAndSet(allocator, .{
        .key = key,
        .expected_revision = first.revision,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:02:00Z",
    });
    try std.testing.expectEqualStrings("2", second.revision);
}

test "file adapter persists state across connections" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/caudex.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);

    {
        const first = try sqlite.open(database_path, .{});
        defer first.close();
        const metadata = try first.metadata();
        try std.testing.expectEqual(sqlite.DatabaseKind.file, metadata.database_kind);
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        _ = try first.stateStore().compareAndSet(arena.allocator(), .{
            .key = key,
            .expected_revision = null,
            .methodology_version = "0.1.0",
            .next_state = state,
            .updated_at = "2026-07-26T12:00:00Z",
        });
    }
    {
        const second = try sqlite.open(database_path, .{});
        defer second.close();
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const loaded = (try second.stateStore().load(
            arena.allocator(),
            key,
        )).?;
        try std.testing.expectEqualStrings("1", loaded.revision);
    }
}

test "open without create rejects a missing file" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/missing.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);
    try std.testing.expectError(
        error.OpenFailed,
        sqlite.open(database_path, .{ .create_if_missing = false }),
    );
}

test "newer schema is rejected distinctly" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "newer.sqlite");
    defer std.testing.allocator.free(database_path);
    const database = try openRaw(database_path);
    defer _ = c.sqlite3_close(database);
    try execRaw(
        database,
        "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY)",
    );
    const newer_version_sql = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "INSERT INTO schema_migrations (version) VALUES ({d})",
        .{sqlite.schema_version + 1},
        0,
    );
    defer std.testing.allocator.free(newer_version_sql);
    try execRaw(database, newer_version_sql);

    try std.testing.expectError(
        error.UnsupportedSchema,
        sqlite.open(database_path, .{}),
    );
}

test "integrity report is available through the public adapter" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    const report = try adapter.integrity();
    try std.testing.expectEqual(sqlite.IntegrityStatus.ok, report.status);
}

test "templates and workflow recovery persist through public capabilities" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const template: persistence.canonical.WorkoutTemplate = .{
        .schemaVersion = 1,
        .id = "template-1",
        .displayName = "Squat day",
        .exercises = &.{.{ .exerciseId = "squat" }},
        .revision = 1,
    };
    const saved = try adapter.templateStore().put(allocator, .{
        .record = .{ .host_scope_key = "scope-1", .template = template },
        .expected_revision = null,
    });
    try std.testing.expectEqualStrings("Squat day", saved.template.displayName);
    try std.testing.expectError(error.Conflict, adapter.templateStore().put(allocator, .{
        .record = .{ .host_scope_key = "scope-1", .template = template },
        .expected_revision = null,
    }));
    try adapter.recoveryStore().put(.{
        .key = .{ .host_scope_key = "scope-1", .workflow_id = "workflow-1" },
        .kind = "workout_completion",
        .status = .pending,
        .idempotency_key = "completion-1",
        .payload_json = "{\"workoutId\":\"workout-1\"}",
        .updated_at = "2026-08-04T12:00:00Z",
    });
    const recovery = (try adapter.recoveryStore().load(allocator, .{ .host_scope_key = "scope-1", .workflow_id = "workflow-1" })).?;
    try std.testing.expectEqualStrings("completion-1", recovery.idempotency_key);
}

test "program definitions instances and occurrence history use public capabilities" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expect((try adapter.programDefinitionStore().load(allocator, program_definition_record.key)) == null);
    _ = try adapter.programDefinitionStore().put(allocator, program_definition_record);
    try std.testing.expectError(error.Conflict, adapter.programDefinitionStore().put(allocator, program_definition_record));
    const definition = (try adapter.programDefinitionStore().load(allocator, program_definition_record.key)).?;
    try std.testing.expectEqualStrings(program_reference.configurationFingerprint, definition.definition.configurationFingerprint);

    _ = try adapter.programInstanceStore().compareAndSet(allocator, .{
        .record = program_initial_instance,
        .expected_revision = null,
    });
    _ = try adapter.programInstanceStore().compareAndSet(allocator, .{
        .record = program_next_instance,
        .expected_revision = 0,
    });
    try std.testing.expectError(error.Conflict, adapter.programInstanceStore().compareAndSet(allocator, .{
        .record = program_next_instance,
        .expected_revision = 0,
    }));
    const instance = (try adapter.programInstanceStore().load(allocator, program_initial_instance.key)).?;
    try std.testing.expectEqual(@as(u64, 1), instance.planning_state.?.revision);

    _ = try adapter.programOccurrenceStore().append(allocator, program_occurrence_record);
    try std.testing.expectError(error.Conflict, adapter.programOccurrenceStore().append(allocator, program_occurrence_record));
    const occurrence = (try adapter.programOccurrenceStore().load(allocator, program_occurrence_record.key)).?;
    try std.testing.expectEqual(@as(u64, 1), occurrence.occurrence.afterRevision);
}

test "portable data dry-runs and round trips across independent SQLite databases" {
    const source = try sqlite.openInMemory(.{});
    defer source.close();
    const destination = try sqlite.openInMemory(.{});
    defer destination.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try source.replaceCatalog(allocator, .{ .host_scope_key = "scope-1", .as_of = "2026-08-04T12:00:00Z" }, &.{.{ .id = "squat", .name = "Back Squat" }});
    try source.appendCompletedWorkout(allocator, "scope-1", .{
        .id = "completed-1",
        .startedAt = "2026-08-04T11:00:00Z",
        .completedAt = "2026-08-04T12:00:00Z",
        .exercises = &.{.{ .exerciseId = "squat", .sets = &.{.{
            .id = "set-1",
            .kind = "working",
            .actualMetrics = &.{.{ .code = "load", .value = .{ .amount = "185.00", .unit = "lb" } }},
            .status = .completed,
        }} }},
    });
    _ = try source.stateStore().compareAndSet(allocator, .{
        .key = .{ .host_scope_key = "scope-1", .methodology_id = "caudex.double-progression" },
        .expected_revision = null,
        .methodology_version = "1.0.0",
        .next_state = state,
        .updated_at = "2026-08-04T12:00:00Z",
    });
    _ = try source.templateStore().put(allocator, .{
        .record = .{ .host_scope_key = "scope-1", .template = .{ .schemaVersion = 1, .id = "template-1", .displayName = "Squat day", .exercises = &.{.{ .exerciseId = "squat" }}, .revision = 2 } },
        .expected_revision = null,
    });
    try source.recoveryStore().put(.{
        .key = .{ .host_scope_key = "scope-1", .workflow_id = "workflow-1" },
        .kind = "workout_completion",
        .status = .pending,
        .idempotency_key = "completion-1",
        .payload_json = "{\"amount\":\"185.00\"}",
        .updated_at = "2026-08-04T12:00:00Z",
    });
    try source.recommendationJournal().append(.{
        .id = "accepted-1",
        .host_scope_key = "scope-1",
        .accepted_at = "2026-08-04T12:00:00Z",
        .result = .{
            .ok = false,
            .metadata = .{
                .engineVersion = "0.1.0",
                .schemaVersion = 1,
                .methodology = .{ .id = "caudex.double-progression", .version = "1.0.0", .configVersion = 1 },
                .inputFingerprint = "input",
                .resultFingerprint = "result",
            },
        },
    });
    _ = try source.athleteProfileStore().compareAndSet(allocator, .{
        .key = .{ .host_scope_key = "scope-1", .athlete_profile_id = "profile-1" },
        .expected_revision = null,
        .next_profile = .{ .id = "profile-1" },
    });
    _ = try source.programDefinitionStore().put(allocator, program_definition_record);
    _ = try source.programInstanceStore().compareAndSet(allocator, .{
        .record = program_next_instance,
        .expected_revision = null,
    });
    _ = try source.programOccurrenceStore().append(allocator, program_occurrence_record);
    const empty_data = std.json.Value{ .object = try .init(allocator, &.{}, &.{}) };
    const programming_records: persistence.portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = "2026-08-04T12:00:00Z",
        .acceptedProgramRecommendations = &.{.{
            .id = "accepted-program-1",
            .hostScopeKey = "scope-1",
            .acceptedAt = "2026-08-04T12:00:00Z",
            .result = .{
                .ok = false,
                .metadata = .{
                    .engineVersion = "0.1.0",
                    .schemaVersion = 1,
                    .programStrategy = .{ .id = "caudex.fixed-session", .version = "0.1.0", .configVersion = 1 },
                    .inputFingerprint = "program-input",
                    .resultFingerprint = "program-result",
                },
            },
        }},
        .progressionStates = &.{.{
            .hostScopeKey = "scope-1",
            .stateId = "block-1-accessory",
            .progressionId = "caudex.double-progression",
            .progressionVersion = "0.1.0",
            .state = .{ .schemaVersion = 1, .data = empty_data },
            .revision = "progression-revision-1",
            .updatedAt = "2026-08-04T12:00:00Z",
        }},
        .programStates = &.{.{
            .hostScopeKey = "scope-1",
            .programId = "program-1",
            .strategyId = "caudex.fixed-session",
            .strategyVersion = "0.1.0",
            .state = .{ .schemaVersion = 1, .data = empty_data },
            .revision = "program-revision-1",
            .updatedAt = "2026-08-04T12:00:00Z",
        }},
    };
    const seeded_programming = try source.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .dryRun = false, .document = programming_records });
    try std.testing.expect(seeded_programming.valid);

    const exported = try source.portableStore().exportData(allocator, .{ .host_scope_key = "scope-1", .exported_at = "2026-08-04T12:00:00Z" });
    try std.testing.expectEqualStrings("accepted-1", exported.acceptedRecommendations[0].id);
    try std.testing.expectEqualStrings("accepted-program-1", exported.acceptedProgramRecommendations[0].id);
    try std.testing.expectEqualStrings("progression-revision-1", exported.progressionStates[0].revision);
    try std.testing.expectEqualStrings("program-revision-1", exported.programStates[0].revision);
    try std.testing.expectEqualStrings("profile-1", exported.athleteProfiles[0].profile.id);
    try std.testing.expectEqualStrings("Upper/lower", exported.programDefinitions[0].definition.displayName);
    try std.testing.expectEqual(@as(u64, 1), exported.programInstances[0].planningState.?.revision);
    try std.testing.expectEqualStrings("occurrence-1", exported.programOccurrences[0].occurrence.occurrenceId);
    try std.testing.expectEqualStrings("185.00", exported.completedWorkouts[0].workout.exercises[0].sets[0].actualMetrics[0].value.amount);
    const dry_run = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .dryRun = true, .document = exported });
    try std.testing.expect(dry_run.valid);
    try std.testing.expect((try destination.templateStore().load(allocator, .{ .host_scope_key = "scope-1", .template_id = "template-1" })) == null);

    const applied = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .dryRun = false, .document = exported });
    try std.testing.expect(applied.valid);
    try std.testing.expectEqualStrings("Squat day", (try destination.templateStore().load(allocator, .{ .host_scope_key = "scope-1", .template_id = "template-1" })).?.template.displayName);
    const imported_history = try destination.historySource().load(allocator, .{ .host_scope_key = "scope-1", .through = "2026-08-04T12:00:00Z" });
    try std.testing.expectEqualStrings("185.00", imported_history.workouts[0].exercises[0].sets[0].actualMetrics[0].value.amount);
    const reexported = try destination.portableStore().exportData(allocator, .{ .host_scope_key = "scope-1", .exported_at = "2026-08-04T12:00:00Z" });
    try std.testing.expectEqualStrings("program-result", reexported.acceptedProgramRecommendations[0].result.metadata.resultFingerprint);
    try std.testing.expectEqualStrings("block-1-accessory", reexported.progressionStates[0].stateId);
    try std.testing.expectEqualStrings("program-1", reexported.programStates[0].programId);
    try std.testing.expectEqualStrings("profile-1", reexported.athleteProfiles[0].profile.id);
    try std.testing.expectEqualStrings("host.upper-lower", reexported.programDefinitions[0].definition.id);
    try std.testing.expectEqualStrings("run-1", reexported.programInstances[0].instance.id);
    try std.testing.expectEqual(@as(u64, 1), reexported.programOccurrences[0].occurrence.afterRevision);
    const conflict = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .dryRun = false, .document = exported });
    try std.testing.expect(!conflict.valid);
    try std.testing.expectEqualStrings("portable.conflict", conflict.issues[0].code);
    const programming_only: persistence.portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = exported.exportedAt,
        .acceptedProgramRecommendations = exported.acceptedProgramRecommendations,
        .progressionStates = exported.progressionStates,
        .programStates = exported.programStates,
    };
    const programming_conflict = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .dryRun = false, .document = programming_only });
    try std.testing.expect(!programming_conflict.valid);
    try std.testing.expectEqualStrings("/document/acceptedProgramRecommendations", programming_conflict.issues[0].path);

    const replacement_program_state = [_]persistence.portable.ProgramStateRecord{.{
        .hostScopeKey = "scope-1",
        .programId = "program-1",
        .strategyId = "caudex.fixed-session",
        .strategyVersion = "0.1.0",
        .state = .{ .schemaVersion = 1, .data = empty_data },
        .revision = "program-revision-2",
        .updatedAt = "2026-08-04T13:00:00Z",
    }};
    const replaced = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .replace, .conflictPolicy = .overwrite, .dryRun = false, .document = .{
        .schemaVersion = 1,
        .exportedAt = "2026-08-04T13:00:00Z",
        .programStates = &replacement_program_state,
    } });
    try std.testing.expect(replaced.valid);
    const replacement_export = try destination.portableStore().exportData(allocator, .{ .host_scope_key = "scope-1", .exported_at = "2026-08-04T13:00:00Z" });
    try std.testing.expectEqual(@as(usize, 0), replacement_export.acceptedProgramRecommendations.len);
    try std.testing.expectEqual(@as(usize, 0), replacement_export.progressionStates.len);
    try std.testing.expectEqual(@as(usize, 0), replacement_export.programDefinitions.len);
    try std.testing.expectEqual(@as(usize, 0), replacement_export.programInstances.len);
    try std.testing.expectEqual(@as(usize, 0), replacement_export.programOccurrences.len);
    try std.testing.expectEqualStrings("program-revision-2", replacement_export.programStates[0].revision);
}

test "shared portable fixture preserves canonical meaning in SQLite" {
    const fixture = assets.portable_export;
    const parsed = try persistence.portable.decodeDocument(std.testing.allocator, fixture);
    defer parsed.deinit();
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const applied = try adapter.portableStore().importData(allocator, .{
        .schemaVersion = 1,
        .mode = .replace,
        .conflictPolicy = .overwrite,
        .dryRun = false,
        .document = parsed.value,
    });
    try std.testing.expect(applied.valid);
    const exported = try adapter.portableStore().exportData(allocator, .{ .host_scope_key = "scope-1", .exported_at = "2026-08-04T12:00:00Z" });
    try std.testing.expectEqualStrings("host.catalog", exported.catalogReferences[0].catalogId.?);
    try std.testing.expectEqualStrings("185.00", exported.completedWorkouts[0].workout.exercises[0].sets[0].actualMetrics[0].value.amount);
}

test "schema version one migrates forward to current metadata" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "version-one.sqlite");
    defer std.testing.allocator.free(database_path);
    {
        const database = try openRaw(database_path);
        defer _ = c.sqlite3_close(database);
        try execRaw(
            database,
            "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY)",
        );
        try execRaw(
            database,
            assets.sqlite_migration,
        );
        try execRaw(
            database,
            "INSERT INTO schema_migrations (version) VALUES (1)",
        );
        try execRaw(
            database,
            "INSERT INTO catalog (host_scope_key, exercise_id, payload) VALUES ('legacy', 'bench', '{\"id\":\"bench\",\"name\":\"Bench Press\",\"aliases\":[\"press\"]}')",
        );
    }

    const migrated = try sqlite.open(database_path, .{});
    defer migrated.close();
    const metadata = try migrated.metadata();
    try std.testing.expectEqual(sqlite.schema_version, metadata.schema_version);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const search = try migrated.searchExercises(arena.allocator(), .{
        .host_scope_key = .{ .bytes = "legacy" },
        .text = "pre",
        .max_results = 10,
    });
    try std.testing.expectEqual(@as(usize, 1), search.found.len);
    try std.testing.expect((try migrated.templateStore().load(arena.allocator(), .{
        .host_scope_key = "legacy",
        .template_id = "missing",
    })) == null);
    try std.testing.expect((try migrated.recoveryStore().load(arena.allocator(), .{
        .host_scope_key = "legacy",
        .workflow_id = "missing",
    })) == null);
}

test "corrupt database is rejected distinctly" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "corrupt.sqlite");
    defer std.testing.allocator.free(database_path);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "corrupt.sqlite",
        .data = "this is not a sqlite database",
    });

    try std.testing.expectError(error.Corrupt, sqlite.open(database_path, .{}));
}

test "migration failure is distinct from corruption" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "migration.sqlite");
    defer std.testing.allocator.free(database_path);
    const database = try openRaw(database_path);
    defer _ = c.sqlite3_close(database);
    try execRaw(database, "CREATE TABLE schema_migrations (wrong INTEGER)");

    try std.testing.expectError(
        error.MigrationFailed,
        sqlite.open(database_path, .{}),
    );
}

test "busy timeout maps lock contention to unavailable" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/busy.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);
    const adapter = try sqlite.open(database_path, .{
        .busy_timeout_ms = 1,
    });
    defer adapter.close();

    var locking_database: ?*c.sqlite3 = null;
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_open(database_path.ptr, &locking_database),
    );
    defer _ = c.sqlite3_close(locking_database);
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            locking_database,
            "BEGIN EXCLUSIVE",
            null,
            null,
            null,
        ),
    );
    defer _ = c.sqlite3_exec(
        locking_database,
        "ROLLBACK",
        null,
        null,
        null,
    );

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.Unavailable,
        adapter.stateStore().load(arena.allocator(), key),
    );
}

test "open-time lock contention is a distinct busy error" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "open-busy.sqlite");
    defer std.testing.allocator.free(database_path);
    const initialized = try sqlite.open(database_path, .{});
    initialized.close();

    const locking_database = try openRaw(database_path);
    defer _ = c.sqlite3_close(locking_database);
    try execRaw(locking_database, "BEGIN EXCLUSIVE");
    defer execRaw(locking_database, "ROLLBACK") catch {};

    try std.testing.expectError(
        error.Busy,
        sqlite.open(database_path, .{ .busy_timeout_ms = 1 }),
    );
}

test "public adapter handle and declarations expose no SQLite internals" {
    try std.testing.expect(@typeInfo(sqlite.Adapter) == .@"opaque");
    inline for (.{
        "db",
        "raw",
        "prepare",
        "execute",
        "migrate",
        "schema_migrations",
        "CREATE TABLE",
    }) |name| {
        try std.testing.expect(!@hasDecl(sqlite, name));
        try std.testing.expect(!@hasDecl(sqlite.Adapter, name));
    }
}

fn databasePath(
    temporary: std.testing.TmpDir,
    name: []const u8,
) ![:0]u8 {
    return std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/{s}",
        .{ temporary.sub_path, name },
        0,
    );
}

fn openRaw(path: [:0]const u8) !*c.sqlite3 {
    var database: ?*c.sqlite3 = null;
    try std.testing.expectEqual(c.SQLITE_OK, c.sqlite3_open(path.ptr, &database));
    return database orelse error.RawDatabaseUnavailable;
}

fn execRaw(database: *c.sqlite3, sql: [*:0]const u8) !void {
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(database, sql, null, null, null),
    );
}
