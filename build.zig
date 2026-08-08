const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("caudex", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const library = b.addLibrary(.{
        .name = "caudex",
        .root_module = module,
    });
    b.installArtifact(library);

    const library_tests = b.addTest(.{
        .root_module = module,
    });
    const run_library_tests = b.addRunArtifact(library_tests);

    const test_core_step = b.step(
        "test-core",
        "Run isolated core tests without adapters or system libraries",
    );
    test_core_step.dependOn(&run_library_tests.step);

    const contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("contract_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
            },
        }),
    });
    const run_contract_tests = b.addRunArtifact(contract_tests);

    const architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("architecture_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
            },
        }),
    });
    const run_architecture_tests = b.addRunArtifact(architecture_tests);

    const tracking_module = b.addModule("caudex_tracking", .{
        .root_source_file = b.path("tracking/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
        },
    });
    const tracking_protocol_module = b.addModule("caudex_tracking_protocol", .{
        .root_source_file = b.path("tracking/protocol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_tracking", .module = tracking_module },
        },
    });
    const workflows_module = b.addModule("caudex_workflows", .{
        .root_source_file = b.path("workflows/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_tracking", .module = tracking_module },
            .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
        },
    });
    const exercise_catalog_module = b.addModule("caudex_exercise_catalog", .{
        .root_source_file = b.path("catalog/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "caudex", .module = module }},
    });
    const portable_module = b.addModule("caudex_portable", .{
        .root_source_file = b.path("portable/protocol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_tracking", .module = tracking_module },
            .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
        },
    });
    const persistence_module = b.addModule("caudex_persistence", .{
        .root_source_file = b.path("adapters/persistence.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_portable", .module = portable_module },
        },
    });
    const portable_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("portable_protocol_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "caudex_portable", .module = portable_module }},
        }),
    });
    const run_portable_tests = b.addRunArtifact(portable_tests);
    const portable_test_step = b.step("test-portable", "Test bounded adapter-independent portable import and export");
    portable_test_step.dependOn(&run_portable_tests.step);
    const exercise_catalog_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("catalog/catalog_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_exercise_catalog", .module = exercise_catalog_module },
            },
        }),
    });
    const run_exercise_catalog_tests = b.addRunArtifact(exercise_catalog_tests);
    const verify_exercise_catalog = b.addSystemCommand(&.{ "node", "catalog/tools/generate.mjs", "--check" });
    const exercise_catalog_generator_tests = b.addSystemCommand(&.{ "node", "tests/exercise_catalog_generator_test.mjs" });
    const exercise_catalog_types = b.addSystemCommand(&.{
        "node",
        "packages/npm/workout-engine/node_modules/typescript/bin/tsc",
        "--noEmit",
        "--strict",
        "--allowImportingTsExtensions",
        "--resolveJsonModule",
        "--target",
        "ES2022",
        "--module",
        "NodeNext",
        "--moduleResolution",
        "NodeNext",
        "tests/exercise_catalog_test.ts",
    });
    const exercise_catalog_runtime = b.addSystemCommand(&.{ "node", "--experimental-strip-types", "--disable-warning=ExperimentalWarning", "tests/exercise_catalog_test.ts" });
    exercise_catalog_runtime.step.dependOn(&exercise_catalog_types.step);
    const exercise_catalog_package = b.addSystemCommand(&.{ "node", "packages/exercise-catalog/scripts/build-package.mjs" });
    const exercise_catalog_clean = b.addSystemCommand(&.{ "node", "tests/exercise_catalog_clean_smoke.mjs" });
    exercise_catalog_clean.step.dependOn(&exercise_catalog_package.step);
    const exercise_catalog_step = b.step("test-exercise-catalog", "Verify and test the pinned optional exercise catalog");
    exercise_catalog_step.dependOn(&run_exercise_catalog_tests.step);
    exercise_catalog_step.dependOn(&verify_exercise_catalog.step);
    exercise_catalog_step.dependOn(&exercise_catalog_generator_tests.step);
    exercise_catalog_step.dependOn(&exercise_catalog_runtime.step);
    exercise_catalog_step.dependOn(&exercise_catalog_clean.step);

    const catalog_commit = b.option([]const u8, "catalog-commit", "Exact free-exercise-db commit for the explicit network update command") orelse "missing-commit";
    const update_exercise_catalog = b.addSystemCommand(&.{ "node", "catalog/tools/update.mjs", catalog_commit });
    const update_exercise_catalog_step = b.step("update-exercise-catalog", "Fetch and regenerate the catalog from -Dcatalog-commit=<40-hex-sha>");
    update_exercise_catalog_step.dependOn(&update_exercise_catalog.step);
    const c_api_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_tracking", .module = tracking_module },
            .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
            .{ .name = "caudex_workflows", .module = workflows_module },
            .{ .name = "caudex_portable", .module = portable_module },
        },
    });
    const c_library = b.addLibrary(.{ .name = "caudex_c", .root_module = c_api_module });
    c_library.installHeader(b.path("include/caudex.h"), "caudex.h");
    b.installArtifact(c_library);
    const tracking_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tracking_contract_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_tracking", .module = tracking_module },
            },
        }),
    });
    const run_tracking_contract_tests = b.addRunArtifact(tracking_contract_tests);
    const tracking_lifecycle_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tracking_lifecycle_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_tracking", .module = tracking_module },
            },
        }),
    });
    const run_tracking_lifecycle_tests =
        b.addRunArtifact(tracking_lifecycle_tests);
    const tracking_architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tracking_architecture_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex_tracking", .module = tracking_module },
            },
        }),
    });
    const run_tracking_architecture_tests =
        b.addRunArtifact(tracking_architecture_tests);
    const tracking_protocol_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tracking_protocol_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
                .{ .name = "caudex_workflows", .module = workflows_module },
                .{ .name = "caudex_tracking", .module = tracking_module },
                .{ .name = "caudex", .module = module },
            },
        }),
    });
    const run_tracking_protocol_tests = b.addRunArtifact(tracking_protocol_tests);
    const tracking_model_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tracking_model_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "caudex_tracking", .module = tracking_module }},
    }) });
    const run_tracking_model_tests = b.addRunArtifact(tracking_model_tests);
    const tracking_model_step = b.step("test-tracking-model", "Compare bounded command sequences with an independent reference model");
    tracking_model_step.dependOn(&run_tracking_model_tests.step);
    const tracking_contract_step = b.step(
        "test-tracking-contract",
        "Test the public host-owned tracking contract",
    );
    tracking_contract_step.dependOn(&run_tracking_contract_tests.step);
    tracking_contract_step.dependOn(&run_tracking_lifecycle_tests.step);
    tracking_contract_step.dependOn(&run_tracking_architecture_tests.step);
    tracking_contract_step.dependOn(&run_tracking_protocol_tests.step);
    tracking_contract_step.dependOn(&run_tracking_model_tests.step);

    const workflow_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("workflow_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_tracking", .module = tracking_module },
                .{ .name = "caudex_workflows", .module = workflows_module },
            },
        }),
    });
    const run_workflow_tests = b.addRunArtifact(workflow_tests);
    const workflow_architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("workflow_architecture_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "caudex_workflows", .module = workflows_module }},
        }),
    });
    const run_workflow_architecture_tests = b.addRunArtifact(workflow_architecture_tests);
    const workflow_test_step = b.step("test-workflows", "Test pure programming, template, tracking, and evaluation workflows");
    workflow_test_step.dependOn(&run_workflow_tests.step);
    workflow_test_step.dependOn(&run_workflow_architecture_tests.step);

    const persistence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("persistence_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "caudex_persistence",
                    .module = persistence_module,
                },
            },
        }),
    });
    const run_persistence_tests = b.addRunArtifact(persistence_tests);
    const persistence_test_step = b.step(
        "test-persistence-contracts",
        "Test optional Zig persistence capability contracts",
    );
    persistence_test_step.dependOn(&run_persistence_tests.step);

    const persistence_testing_module = b.createModule(.{
        .root_source_file = b.path("adapters/persistence/testing.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "caudex_persistence",
                .module = persistence_module,
            },
        },
    });
    const persistence_contract_kit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("persistence_contract_kit_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "caudex_persistence",
                    .module = persistence_module,
                },
                .{
                    .name = "caudex_persistence_testing",
                    .module = persistence_testing_module,
                },
            },
        }),
    });
    const run_persistence_contract_kit_tests =
        b.addRunArtifact(persistence_contract_kit_tests);
    const persistence_contract_kit_step = b.step(
        "test-persistence-contract-kit",
        "Run the reusable persistence adapter contract suite",
    );
    persistence_contract_kit_step.dependOn(
        &run_persistence_contract_kit_tests.step,
    );

    const persistence_typescript_check = b.addSystemCommand(&.{
        "node",
        "packages/npm/workout-engine/node_modules/typescript/bin/tsc",
        "--project",
        "tests/persistence_contracts_tsconfig.json",
    });
    const persistence_typescript_test = b.addSystemCommand(&.{
        "node",
        "--experimental-strip-types",
        "--disable-warning=ExperimentalWarning",
        "tests/persistence_contracts_test.ts",
    });
    persistence_typescript_test.step.dependOn(&persistence_typescript_check.step);
    persistence_test_step.dependOn(&persistence_typescript_test.step);

    const c_api_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("c_api_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_tracking", .module = tracking_module },
                .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
                .{ .name = "caudex_workflows", .module = workflows_module },
                .{ .name = "caudex_portable", .module = portable_module },
            },
        }),
    });
    const run_c_api_tests = b.addRunArtifact(c_api_tests);
    const test_c_api_step = b.step("test-c-api", "Test the native C ABI execution boundary");
    test_c_api_step.dependOn(&run_c_api_tests.step);

    const c_header_test = b.addObject(.{
        .name = "caudex_c_header_test",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    c_header_test.root_module.addIncludePath(b.path("include"));
    c_header_test.root_module.addCSourceFile(.{
        .file = b.path("tests/c_header_smoke.c"),
        .flags = &.{ "-std=c11", "-Werror" },
    });

    const cpp_header_test = b.addObject(.{
        .name = "caudex_cpp_header_test",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    cpp_header_test.root_module.addIncludePath(b.path("include"));
    cpp_header_test.root_module.addCSourceFile(.{
        .file = b.path("tests/cpp_header_smoke.cpp"),
        .flags = &.{ "-std=c++17", "-Werror" },
    });

    const c_conformance = b.addExecutable(.{
        .name = "caudex_c_conformance",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    c_conformance.root_module.addIncludePath(b.path("include"));
    c_conformance.root_module.addCSourceFile(.{
        .file = b.path("examples/c/conformance.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    c_conformance.root_module.linkLibrary(c_library);
    c_conformance.root_module.link_libc = true;
    const run_c_conformance = b.addRunArtifact(c_conformance);
    run_c_conformance.addFileArg(b.path("fixtures/operations/recommendation-v1.json"));
    const c_example_step = b.step(
        "example-c",
        "Run the C canonical-request conformance example",
    );
    c_example_step.dependOn(&run_c_conformance.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_library = b.addLibrary(.{
        .name = "caudex_core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = wasm_target,
            .optimize = optimize,
        }),
    });

    const check_wasm_step = b.step(
        "check-wasm",
        "Compile the library for wasm32-freestanding",
    );
    check_wasm_step.dependOn(&wasm_library.step);

    const wasm_runtime = b.addExecutable(.{
        .name = "caudex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm_api.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "caudex", .module = module },
                .{ .name = "caudex_tracking", .module = tracking_module },
                .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
                .{ .name = "caudex_workflows", .module = workflows_module },
                .{ .name = "caudex_portable", .module = portable_module },
            },
        }),
    });
    wasm_runtime.entry = .disabled;
    wasm_runtime.rdynamic = true;
    wasm_runtime.export_memory = true;
    b.installArtifact(wasm_runtime);

    const wasm_conformance = b.addSystemCommand(&.{ "node", "tests/wasm_conformance.mjs" });
    wasm_conformance.addArtifactArg(wasm_runtime);
    wasm_conformance.addFileArg(b.path("fixtures/operations/recommendation-v1.json"));
    const wasm_step = b.step(
        "wasm",
        "Build and test the freestanding release WebAssembly runtime",
    );
    wasm_step.dependOn(&wasm_conformance.step);

    const typescript_loader_test = b.addSystemCommand(&.{
        "node",
        "--experimental-strip-types",
        "--disable-warning=ExperimentalWarning",
        "tests/typescript_loader_test.ts",
    });
    const npm_source_typecheck = b.addSystemCommand(&.{
        "node",
        "packages/npm/workout-engine/node_modules/typescript/bin/tsc",
        "--noEmit",
        "--strict",
        "--allowImportingTsExtensions",
        "--target",
        "ES2022",
        "--module",
        "NodeNext",
        "--moduleResolution",
        "NodeNext",
        "--lib",
        "ES2023,DOM",
        "packages/npm/workout-engine/src/index.ts",
    });
    typescript_loader_test.addArtifactArg(wasm_runtime);
    typescript_loader_test.addFileArg(
        b.path("fixtures/requests/recommendation.json"),
    );
    typescript_loader_test.addFileArg(b.path("fixtures/portable/export-v1.json"));
    typescript_loader_test.step.dependOn(&npm_source_typecheck.step);
    const typescript_step = b.step(
        "test-typescript",
        "Run the TypeScript WebAssembly loader and facade tests",
    );
    typescript_step.dependOn(&typescript_loader_test.step);

    const methodology_factory_test = b.addSystemCommand(&.{
        "node",
        "--experimental-strip-types",
        "--disable-warning=ExperimentalWarning",
        "tests/methodology_factories_test.ts",
    });
    methodology_factory_test.addArtifactArg(wasm_runtime);
    methodology_factory_test.addFileArg(
        b.path("fixtures/requests/recommendation.json"),
    );
    methodology_factory_test.addFileArg(
        b.path("fixtures/methodologies/double-progression-config-v1.json"),
    );
    methodology_factory_test.addFileArg(
        b.path("fixtures/methodologies/rpe-top-set-backoff-config-v1.json"),
    );
    const methodology_factory_step = b.step(
        "test-methodology-factories",
        "Run TypeScript methodology factory tests",
    );
    methodology_factory_step.dependOn(&methodology_factory_test.step);

    const npm_package_build = b.addSystemCommand(&.{
        "node",
        "--disable-warning=ExperimentalWarning",
        "packages/npm/workout-engine/scripts/build-package.mjs",
    });
    npm_package_build.addArtifactArg(wasm_runtime);

    const persistence_package_build = b.addSystemCommand(&.{
        "node",
        "packages/npm/workout-engine/node_modules/typescript/bin/tsc",
        "--project",
        "packages/persistence/tsconfig.json",
    });
    const indexeddb_package_build = b.addSystemCommand(&.{
        "npm",
        "run",
        "build",
        "--prefix",
        "packages/persistence-indexeddb",
    });
    indexeddb_package_build.step.dependOn(&persistence_package_build.step);
    const indexeddb_adapter_test = b.addSystemCommand(&.{
        "node",
        "--experimental-strip-types",
        "--disable-warning=ExperimentalWarning",
        "tests/indexeddb_adapter_test.ts",
    });
    indexeddb_adapter_test.step.dependOn(&indexeddb_package_build.step);
    const indexeddb_clean_smoke = b.addSystemCommand(&.{
        "node",
        "tests/indexeddb_clean_smoke.mjs",
    });
    indexeddb_clean_smoke.step.dependOn(&npm_package_build.step);
    indexeddb_clean_smoke.step.dependOn(&indexeddb_package_build.step);
    const indexeddb_test_step = b.step(
        "test-persistence-indexeddb",
        "Build and test the optional IndexedDB persistence adapter",
    );
    indexeddb_test_step.dependOn(&indexeddb_adapter_test.step);
    indexeddb_test_step.dependOn(&indexeddb_clean_smoke.step);

    const sqlite_module = b.addModule("caudex_sqlite", .{
        .root_source_file = b.path("adapters/sqlite.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{
                .name = "caudex_persistence",
                .module = persistence_module,
            },
            .{ .name = "caudex_tracking", .module = tracking_module },
            .{ .name = "caudex_tracking_protocol", .module = tracking_protocol_module },
            .{ .name = "caudex_portable", .module = portable_module },
        },
    });
    sqlite_module.link_libc = true;
    sqlite_module.linkSystemLibrary("sqlite3", .{});
    const sqlite_adapter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("sqlite_adapter_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "caudex_persistence",
                    .module = persistence_module,
                },
                .{ .name = "caudex_sqlite", .module = sqlite_module },
            },
        }),
    });
    const run_sqlite_adapter_tests = b.addRunArtifact(sqlite_adapter_tests);
    const sqlite_tracking_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("sqlite_tracking_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "caudex_persistence",
                    .module = persistence_module,
                },
                .{ .name = "caudex_tracking", .module = tracking_module },
                .{ .name = "caudex_sqlite", .module = sqlite_module },
            },
        }),
    });
    const run_sqlite_tracking_tests = b.addRunArtifact(sqlite_tracking_tests);
    const sqlite_test_step = b.step(
        "test-persistence-sqlite",
        "Build and test the optional SQLite persistence adapter",
    );
    sqlite_test_step.dependOn(&run_sqlite_adapter_tests.step);
    sqlite_test_step.dependOn(&run_sqlite_tracking_tests.step);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("apps/caudex-cli/src/main.zig"),
        .target = target,
        .optimize = optimize,
        // Keep development diagnostics, but do not ship unnecessary symbols.
        .strip = if (optimize == .Debug) null else true,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_persistence", .module = persistence_module },
            .{ .name = "caudex_sqlite", .module = sqlite_module },
            .{ .name = "caudex_tracking", .module = tracking_module },
        },
    });
    const cli = b.addExecutable(.{
        .name = "caudex",
        .root_module = cli_module,
    });
    b.installArtifact(cli);

    const cli_build_step = b.step("caudex-cli", "Build the caudex reference client");
    cli_build_step.dependOn(&cli.step);

    const run_cli = b.addRunArtifact(cli);
    if (b.args) |args| run_cli.addArgs(args);
    const run_cli_step = b.step("run-caudex-cli", "Run the caudex reference client");
    run_cli_step.dependOn(&run_cli.step);

    const cli_tests = b.addTest(.{
        .root_module = cli_module,
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    const fuzz_driver_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_c_api", .module = c_api_module },
            .{ .name = "caudex_cli", .module = cli_module },
            .{ .name = "caudex_sqlite", .module = sqlite_module },
        },
    });
    const fuzz_steps = [_][]const u8{
        "fuzz-json",
        "fuzz-decimal",
        "fuzz-c-abi",
        "fuzz-cli-args",
        "fuzz-sqlite",
        "fuzz-methodology-config",
    };
    const fuzz_targets = [_][]const u8{ "json", "decimal", "c_abi", "cli_args", "sqlite", "methodology_config" };
    for (fuzz_steps, fuzz_targets) |step_name, fuzz_target| {
        const fuzz_executable = b.addExecutable(.{ .name = step_name, .root_module = fuzz_driver_module });
        const run_fuzz = b.addRunArtifact(fuzz_executable);
        run_fuzz.addArg(b.fmt("--target={s}", .{fuzz_target}));
        run_fuzz.addArg("--iterations=10000");
        if (b.args) |args| run_fuzz.addArgs(args);
        const step = b.step(step_name, "Run a bounded seeded fuzz target with a reproducible input stream");
        step.dependOn(&run_fuzz.step);
    }

    const fuzz_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz/smoke.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
            .{ .name = "caudex_c_api", .module = c_api_module },
            .{ .name = "caudex_cli", .module = cli_module },
            .{ .name = "caudex_sqlite", .module = sqlite_module },
        },
    });
    const fuzz_smoke_tests = b.addTest(.{ .name = "fuzz-smoke", .root_module = fuzz_smoke_module });
    const run_fuzz_smoke = b.addRunArtifact(fuzz_smoke_tests);
    const fuzz_smoke_step = b.step("fuzz-smoke", "Run deterministic bounded smoke cases for every fuzz driver");
    fuzz_smoke_step.dependOn(&run_fuzz_smoke.step);

    const mutation_smoke = b.addSystemCommand(&.{ "node", "tools/mutation/run.mjs", "--smoke" });
    const mutation_smoke_step = b.step("mutation-smoke", "Run the representative bounded mutation subset");
    mutation_smoke_step.dependOn(&mutation_smoke.step);
    const mutation_test = b.addSystemCommand(&.{ "node", "tools/mutation/run.mjs" });
    if (b.args) |args| mutation_test.addArgs(args);
    const mutation_test_step = b.step("mutation-test", "Run the curated methodology mutation suite");
    mutation_test_step.dependOn(&mutation_test.step);

    const tui_lifecycle_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("apps/caudex-cli/src/tui/terminal.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_tui_lifecycle_tests = b.addRunArtifact(tui_lifecycle_tests);
    const tui_lifecycle_step = b.step("test-tui-lifecycle", "Test terminal lifecycle with a fake terminal");
    tui_lifecycle_step.dependOn(&run_tui_lifecycle_tests.step);
    const tui_model_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/model.zig"), .target = target, .optimize = optimize }) });
    const run_tui_model_tests = b.addRunArtifact(tui_model_tests);
    const tui_model_step = b.step("test-tui-model", "Test deterministic TUI update and render model");
    tui_model_step.dependOn(&run_tui_model_tests.step);
    const tui_dashboard_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/dashboard.zig"), .target = target, .optimize = optimize }) });
    const run_tui_dashboard_tests = b.addRunArtifact(tui_dashboard_tests);
    const tui_dashboard_step = b.step("test-tui-dashboard", "Test safe current-workout dashboard states");
    tui_dashboard_step.dependOn(&run_tui_dashboard_tests.step);
    const tui_workout_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/workout_screen.zig"), .target = target, .optimize = optimize }) });
    const run_tui_workout_tests = b.addRunArtifact(tui_workout_tests);
    const tui_workout_step = b.step("test-tui-workout", "Test exercise ordering and set logging screens");
    tui_workout_step.dependOn(&run_tui_workout_tests.step);
    const tui_session_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/session.zig"), .target = target, .optimize = optimize }) });
    const run_tui_session_tests = b.addRunArtifact(tui_session_tests);
    const tui_session_step = b.step("test-tui-session", "Test completion, cancellation, and recovery states");
    tui_session_step.dependOn(&run_tui_session_tests.step);
    const tui_harness = b.addExecutable(.{ .name = "caudex-tui-e2e-harness", .root_module = b.createModule(.{ .root_source_file = b.path("tests/tui_live_workout_harness.zig"), .target = target, .optimize = optimize, .imports = &.{ .{ .name = "caudex_persistence", .module = persistence_module }, .{ .name = "caudex_sqlite", .module = sqlite_module }, .{ .name = "caudex_tracking", .module = tracking_module }, .{ .name = "caudex_tui", .module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/root.zig") }) } } }) });
    const tui_e2e = b.addSystemCommand(&.{ "bash", "tests/tui_live_workout_test.sh" });
    tui_e2e.addArtifactArg(cli);
    tui_e2e.addArtifactArg(tui_harness);
    const tui_e2e_step = b.step("test-tui-e2e", "Run fake-terminal live workout end to end");
    tui_e2e_step.dependOn(&tui_e2e.step);
    const tui_catalog_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/catalog_screen.zig"), .target = target, .optimize = optimize }) });
    const run_tui_catalog_tests = b.addRunArtifact(tui_catalog_tests);
    const tui_catalog_step = b.step("test-tui-catalog", "Test public catalog-management TUI screens");
    tui_catalog_step.dependOn(&run_tui_catalog_tests.step);
    const tui_history_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/history_screen.zig"), .target = target, .optimize = optimize }) });
    const run_tui_history_tests = b.addRunArtifact(tui_history_tests);
    const tui_history_step = b.step("test-tui-history", "Test bounded history and correction TUI flows");
    tui_history_step.dependOn(&run_tui_history_tests.step);
    const tui_data_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/data_screen.zig"), .target = target, .optimize = optimize }) });
    const run_tui_data_tests = b.addRunArtifact(tui_data_tests);
    const tui_data_step = b.step("test-tui-data", "Test local-data diagnostics and safe switching UI");
    tui_data_step.dependOn(&run_tui_data_tests.step);
    const tracking_coverage_audit = b.addSystemCommand(&.{ "bash", "tests/tracking_coverage_audit_test.sh" });
    const tracking_coverage_step = b.step("test-tracking-coverage-audit", "Check public tracking coverage audit completeness");
    tracking_coverage_step.dependOn(&tracking_coverage_audit.step);
    const tui_compatibility_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("apps/caudex-cli/src/tui/compatibility.zig"), .target = target, .optimize = optimize }) });
    const run_tui_compatibility_tests = b.addRunArtifact(tui_compatibility_tests);
    const tui_compatibility_step = b.step("test-tui-compatibility", "Test TUI terminal compatibility and accessibility");
    tui_compatibility_step.dependOn(&run_tui_compatibility_tests.step);

    const cli_help = b.addRunArtifact(cli);
    cli_help.addArg("--help");
    cli_help.expectStdOutEqual(
        \\Caudex Workout Engine reference client
        \\
        \\Usage:
        \\  caudex [--database PATH] [--format human|json] [--color auto|always|never] database info|check
        \\  caudex [global options] database backup DESTINATION
        \\  caudex [global options] database restore SOURCE --yes
        \\  caudex [global options] doctor
        \\  caudex [global options] workout start [start options]
        \\  caudex [global options] workout add-exercise EXERCISE [options]
        \\  caudex [global options] workout show [--workout ID]
        \\  caudex [global options] set log [--workout ID] [--exercise ID] [--set ID] [METRICS...]
        \\  caudex [global options] set skip [--workout ID] [--exercise ID] [--set ID]
        \\  caudex [global options] set reopen [--workout ID] [--exercise ID] --set ID
        \\  caudex [global options] workout finish [--workout ID]
        \\  caudex [global options] workout cancel [--workout ID] [--yes]
        \\  caudex [global options] exercise create ID --name NAME [exercise options]
        \\  caudex [global options] exercise edit EXERCISE [exercise options]
        \\  caudex [global options] exercise show EXERCISE
        \\  caudex [global options] exercise list [--limit N] [--include-archived]
        \\  caudex [global options] exercise search TEXT [--limit N] [--include-archived]
        \\  caudex [global options] exercise archive|restore EXERCISE [command options]
        \\  caudex [global options] history list [--from TIME] [--through TIME] [--limit N]
        \\  caudex [global options] history show WORKOUT
        \\  caudex [global options] history exercise EXERCISE [--limit N]
        \\  caudex [global options] history last EXERCISE
        \\  caudex [global options] history correct-set --workout ID --exercise ID --set ID METRICS... [--yes]
        \\  caudex [global options] config path|show|set (color|table) VALUE
        \\  caudex batch FILE
        \\  caudex completion bash|zsh|fish
        \\  caudex command-reference
        \\  caudex --help
        \\  caudex version
        \\
        \\Environment:
        \\  CAUDEX_DATABASE  Database path used when --database is omitted
        \\
        \\Global options:
        \\  --scope ID        Host scope (default: local)
        \\  --athlete ID      Optional athlete within the host scope
        \\  --quiet           Suppress successful command output
        \\
        \\Set log metrics:
        \\  --reps N  --load N UNIT  --rir N  --rpe N  --duration N UNIT
        \\  Shorthand examples: 70kg 8r @2rir
        \\
        \\Workout start options:
        \\  --command-id ID   Idempotency key (generated when omitted)
        \\  --workout ID      Workout ID (generated when omitted)
        \\  --started-at TIME RFC 3339 start time (current UTC time when omitted)
        \\  --occurred-at TIME RFC 3339 command time (defaults to started-at)
        \\
    );

    const cli_version = b.addRunArtifact(cli);
    cli_version.addArg("version");
    cli_version.expectStdOutEqual(
        "caudex 0.1.0\nengine: 0.1.0 (schema 1)\npersistence contract: 3\n" ++
            "tracking contract: 6\nsqlite adapter: 0.1.0 (schema 1-9)\n",
    );

    const cli_database_human = b.addRunArtifact(cli);
    cli_database_human.addArgs(&.{ "--database", ":memory:", "database", "info" });
    cli_database_human.expectStdOutEqual(
        \\Database: :memory:
        \\Kind: memory
        \\Adapter version: 0.1.0
        \\Schema version: 9
        \\Supported schema: 1-9
        \\Compatibility: current
        \\
    );

    const cli_database_json = b.addRunArtifact(cli);
    cli_database_json.addArgs(&.{
        "--database",
        ":memory:",
        "--format",
        "json",
        "database",
        "info",
    });
    cli_database_json.expectStdOutEqual(
        "{\"schemaVersion\":1,\"kind\":\"caudex.database.info\",\"data\":{" ++
            "\"databasePath\":\":memory:\",\"databaseKind\":\"memory\"," ++
            "\"adapterVersion\":\"0.1.0\",\"databaseSchemaVersion\":9," ++
            "\"minimumSchemaVersion\":1,\"latestSchemaVersion\":9," ++
            "\"compatibility\":\"current\"}}\n",
    );

    const cli_invalid = b.addRunArtifact(cli);
    cli_invalid.addArgs(&.{ "--database", ":memory:", "database", "unknown" });
    cli_invalid.expectExitCode(2);
    cli_invalid.expectStdOutEqual("");
    cli_invalid.expectStdErrEqual(
        "error: Invalid arguments; run 'caudex --help'.\n",
    );

    const cli_invalid_json = b.addRunArtifact(cli);
    cli_invalid_json.addArgs(&.{ "--database", ":memory:", "--format", "json", "database", "unknown" });
    cli_invalid_json.expectExitCode(2);
    cli_invalid_json.expectStdOutEqual("");
    cli_invalid_json.expectStdErrEqual(
        "{\"schemaVersion\":1,\"kind\":\"caudex.error\",\"error\":{" ++
            "\"code\":\"client.invalid_arguments\",\"category\":\"syntax\"," ++
            "\"message\":\"Invalid arguments; run 'caudex --help'.\"}}\n",
    );

    const cli_broken_pipe = b.addSystemCommand(&.{
        "bash",
        "-o",
        "pipefail",
        "-c",
        "\"$1\" --database .zig-cache/cwe112-broken-pipe.sqlite database info | true",
        "_",
    });
    cli_broken_pipe.addArtifactArg(cli);
    const cli_after_broken_pipe = b.addRunArtifact(cli);
    cli_after_broken_pipe.addArgs(&.{
        "--database",
        ".zig-cache/cwe112-broken-pipe.sqlite",
        "--format",
        "json",
        "database",
        "info",
    });
    cli_after_broken_pipe.step.dependOn(&cli_broken_pipe.step);
    cli_after_broken_pipe.expectStdOutEqual(
        "{\"schemaVersion\":1,\"kind\":\"caudex.database.info\",\"data\":{" ++
            "\"databasePath\":\".zig-cache/cwe112-broken-pipe.sqlite\"," ++
            "\"databaseKind\":\"file\",\"adapterVersion\":\"0.1.0\"," ++
            "\"databaseSchemaVersion\":9,\"minimumSchemaVersion\":1," ++
            "\"latestSchemaVersion\":9,\"compatibility\":\"current\"}}\n",
    );

    const cli_workout_start_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_workout_start_test.sh",
    });
    cli_workout_start_test.addArtifactArg(cli);

    const cli_workout_resolution_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_workout_resolution_test.sh",
    });
    cli_workout_resolution_test.addArtifactArg(cli);

    const cli_catalog_seed = b.addExecutable(.{
        .name = "caudex-cli-catalog-seed",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cli_catalog_seed.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "caudex_persistence",
                    .module = persistence_module,
                },
                .{ .name = "caudex_sqlite", .module = sqlite_module },
            },
        }),
    });
    const cli_add_exercise_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_add_exercise_test.sh",
    });
    cli_add_exercise_test.addArtifactArg(cli);
    cli_add_exercise_test.addArtifactArg(cli_catalog_seed);

    const cli_set_commands_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_set_commands_test.sh",
    });
    cli_set_commands_test.addArtifactArg(cli);
    cli_set_commands_test.addArtifactArg(cli_catalog_seed);

    const cli_workout_end_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_workout_end_test.sh",
    });
    cli_workout_end_test.addArtifactArg(cli);

    const cli_catalog_commands_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_catalog_commands_test.sh",
    });
    cli_catalog_commands_test.addArtifactArg(cli);

    const cli_history_commands_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_history_commands_test.sh",
    });
    cli_history_commands_test.addArtifactArg(cli);
    cli_history_commands_test.addArtifactArg(cli_catalog_seed);

    const cli_ergonomics_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_ergonomics_test.sh",
    });
    cli_ergonomics_test.addArtifactArg(cli);

    const cli_batch_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_batch_test.sh",
    });
    cli_batch_test.addArtifactArg(cli);

    const cli_completion_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_completion_test.sh",
    });
    cli_completion_test.addArtifactArg(cli);

    const cli_shell_smoke_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_shell_smoke_test.sh",
    });
    cli_shell_smoke_test.addArtifactArg(cli);

    const cli_database_diagnostics_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_database_diagnostics_test.sh",
    });
    cli_database_diagnostics_test.addArtifactArg(cli);

    const cli_benchmark = b.addSystemCommand(&.{ "bash", "tests/cli_benchmark.sh" });
    cli_benchmark.addArtifactArg(cli);
    const cli_benchmark_step = b.step("benchmark-caudex-cli", "Measure repeatable caudex CLI baselines");
    cli_benchmark_step.dependOn(&cli_benchmark.step);

    const architecture_probe_files = b.addWriteFiles();
    const private_import_probe = architecture_probe_files.add("caudex_private_import.zig",
        \\const private = @import("caudex_private_root");
        \\pub fn main() void {
        \\    _ = private;
        \\}
        \\
    );
    const private_import_check = b.addSystemCommand(&.{
        "zig",
        "build-exe",
        "-fno-emit-bin",
    });
    private_import_check.addFileArg(private_import_probe);
    private_import_check.expectExitCode(1);

    const cli_test_step = b.step("test-caudex-cli", "Test the caudex reference client");
    cli_test_step.dependOn(&run_cli_tests.step);
    cli_test_step.dependOn(&run_tui_lifecycle_tests.step);
    cli_test_step.dependOn(&cli_help.step);
    cli_test_step.dependOn(&cli_version.step);
    cli_test_step.dependOn(&cli_database_human.step);
    cli_test_step.dependOn(&cli_database_json.step);
    cli_test_step.dependOn(&cli_invalid.step);
    cli_test_step.dependOn(&cli_invalid_json.step);
    cli_test_step.dependOn(&cli_after_broken_pipe.step);
    cli_test_step.dependOn(&cli_workout_start_test.step);
    cli_test_step.dependOn(&cli_workout_resolution_test.step);
    cli_test_step.dependOn(&cli_add_exercise_test.step);
    cli_test_step.dependOn(&cli_set_commands_test.step);
    cli_test_step.dependOn(&cli_workout_end_test.step);
    cli_test_step.dependOn(&cli_catalog_commands_test.step);
    cli_test_step.dependOn(&cli_history_commands_test.step);
    cli_test_step.dependOn(&cli_ergonomics_test.step);
    cli_test_step.dependOn(&cli_batch_test.step);
    cli_test_step.dependOn(&cli_completion_test.step);
    cli_test_step.dependOn(&cli_shell_smoke_test.step);
    cli_test_step.dependOn(&cli_database_diagnostics_test.step);
    cli_test_step.dependOn(&private_import_check.step);

    const npm_package_test = b.addSystemCommand(&.{
        "node",
        "tests/npm_package_artifact_test.mjs",
        "packages/npm/workout-engine",
    });
    npm_package_test.step.dependOn(&npm_package_build.step);
    const npm_package_step = b.step(
        "package-npm",
        "Build and inspect the packed npm artifact",
    );
    npm_package_step.dependOn(&npm_package_test.step);

    const npm_clean_smoke = b.addSystemCommand(&.{
        "node",
        "tests/npm_clean_smoke.mjs",
    });
    npm_clean_smoke.step.dependOn(&npm_package_build.step);
    const npm_smoke_step = b.step(
        "test-npm-clean",
        "Test the packed npm artifact from a clean temporary project",
    );
    npm_smoke_step.dependOn(&npm_clean_smoke.step);

    const npm_release_test = b.addSystemCommand(&.{
        "node",
        "tests/npm_release_test.mjs",
    });
    const npm_release_step = b.step(
        "test-npm-release",
        "Test npm release metadata validation",
    );
    npm_release_step.dependOn(&npm_release_test.step);

    const docs_quickstart_test = b.addSystemCommand(&.{
        "node",
        "tests/docs_quickstart_test.mjs",
    });
    docs_quickstart_test.step.dependOn(&npm_package_build.step);
    const docs_quickstart_step = b.step(
        "test-docs-quickstart",
        "Compile and run the packaged TypeScript quickstart",
    );
    docs_quickstart_step.dependOn(&docs_quickstart_test.step);

    const cli_documentation_test = b.addSystemCommand(&.{
        "node",
        "tests/cli_documentation_test.mjs",
    });
    const cli_documentation_step = b.step(
        "test-cli-documentation",
        "Check reference-client and Zig integrator documentation coverage",
    );
    cli_documentation_step.dependOn(&cli_documentation_test.step);

    const cli_release_workflow_test = b.addSystemCommand(&.{
        "node",
        "tests/cli_release_workflow_test.mjs",
    });
    const cli_release_workflow_step = b.step(
        "test-cli-release-workflow",
        "Check CLI release targets, packaging, attestation, and publication gates",
    );
    cli_release_workflow_step.dependOn(&cli_release_workflow_test.step);

    const methodology_guides_test = b.addSystemCommand(&.{
        "node",
        "tests/methodology_guides_test.mjs",
    });
    const methodology_guides_step = b.step(
        "test-methodology-guides",
        "Check first-party methodology guide coverage",
    );
    methodology_guides_step.dependOn(&methodology_guides_test.step);

    const data_mapping_guide_test = b.addSystemCommand(&.{
        "node",
        "tests/data_mapping_guide_test.mjs",
    });
    data_mapping_guide_test.step.dependOn(&npm_package_build.step);
    const data_mapping_guide_step = b.step(
        "test-data-mapping-guide",
        "Compile and run the host data mapping example",
    );
    data_mapping_guide_step.dependOn(&data_mapping_guide_test.step);

    const custom_repository_test = b.addSystemCommand(&.{
        "node",
        "tests/custom_repository_example_test.mjs",
    });
    custom_repository_test.step.dependOn(&npm_package_build.step);
    custom_repository_test.step.dependOn(&persistence_package_build.step);
    const custom_repository_step = b.step(
        "test-custom-repository",
        "Compile and run the custom repository integration example",
    );
    custom_repository_step.dependOn(&custom_repository_test.step);

    const testing_utilities_test = b.addSystemCommand(&.{
        "node",
        "tests/testing_utilities_test.mjs",
    });
    testing_utilities_test.step.dependOn(&npm_package_build.step);
    const testing_utilities_step = b.step(
        "test-testing-utilities",
        "Test the public framework-neutral npm testing utilities",
    );
    testing_utilities_step.dependOn(&testing_utilities_test.step);

    const npm_examples_test = b.addSystemCommand(&.{
        "node",
        "tests/npm_examples_test.mjs",
    });
    npm_examples_test.step.dependOn(&npm_package_build.step);
    const npm_examples_step = b.step(
        "test-npm-examples",
        "Compile and run the packed Node and browser examples",
    );
    npm_examples_step.dependOn(&npm_examples_test.step);

    const zig_package_consumer_test = b.addSystemCommand(&.{
        "node",
        "tests/zig_package_consumer_test.mjs",
    });
    const zig_package_archive = b.addSystemCommand(&.{
        "node",
        "tools/release/build-zig-packages.mjs",
        "zig-out/zig-packages",
    });
    const zig_package_archive_step = b.step(
        "package-zig",
        "Generate separate publishable Zig source packages",
    );
    zig_package_archive_step.dependOn(&zig_package_archive.step);
    const zig_package_step = b.step(
        "test-zig-package",
        "Test direct Zig consumption from declared package paths",
    );
    zig_package_step.dependOn(&zig_package_consumer_test.step);

    const c_release_package = b.addSystemCommand(&.{
        "node",
        "tools/release/build-c-artifacts.mjs",
        "zig-out/c-release",
    });
    const c_release_package_step = b.step(
        "package-c",
        "Build the complete native C release matrix",
    );
    c_release_package_step.dependOn(&c_release_package.step);

    const c_release_test = b.addSystemCommand(&.{
        "node",
        "tools/release/build-c-artifacts.mjs",
        "zig-out/c-release-host",
        "--host-only",
        "--test",
    });
    const c_release_test_step = b.step(
        "test-c-release",
        "Build and link-test host C release artifacts",
    );
    c_release_test_step.dependOn(&c_release_test.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_library_tests.step);
    test_step.dependOn(&run_contract_tests.step);
    test_step.dependOn(&run_architecture_tests.step);
    test_step.dependOn(&run_tracking_contract_tests.step);
    test_step.dependOn(&run_tracking_model_tests.step);
    test_step.dependOn(&run_tracking_lifecycle_tests.step);
    test_step.dependOn(&run_tracking_architecture_tests.step);
    test_step.dependOn(&run_workflow_tests.step);
    test_step.dependOn(&run_workflow_architecture_tests.step);
    test_step.dependOn(&run_exercise_catalog_tests.step);
    test_step.dependOn(&run_portable_tests.step);
    test_step.dependOn(&verify_exercise_catalog.step);
    test_step.dependOn(&exercise_catalog_generator_tests.step);
    test_step.dependOn(&exercise_catalog_runtime.step);
    test_step.dependOn(&exercise_catalog_clean.step);
    test_step.dependOn(&run_persistence_tests.step);
    test_step.dependOn(&run_persistence_contract_kit_tests.step);
    test_step.dependOn(&persistence_typescript_test.step);
    test_step.dependOn(&run_c_api_tests.step);
    test_step.dependOn(&c_header_test.step);
    test_step.dependOn(&cpp_header_test.step);
    test_step.dependOn(&run_c_conformance.step);
    test_step.dependOn(&wasm_library.step);
    test_step.dependOn(&wasm_conformance.step);
    test_step.dependOn(&typescript_loader_test.step);
    test_step.dependOn(&methodology_factory_test.step);
    test_step.dependOn(&npm_package_test.step);
    test_step.dependOn(&indexeddb_adapter_test.step);
    test_step.dependOn(&indexeddb_clean_smoke.step);
    test_step.dependOn(&run_sqlite_adapter_tests.step);
    test_step.dependOn(&run_sqlite_tracking_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_tui_lifecycle_tests.step);
    test_step.dependOn(&run_tui_model_tests.step);
    test_step.dependOn(&run_tui_dashboard_tests.step);
    test_step.dependOn(&run_tui_workout_tests.step);
    test_step.dependOn(&run_tui_session_tests.step);
    test_step.dependOn(&run_tui_catalog_tests.step);
    test_step.dependOn(&run_tui_history_tests.step);
    test_step.dependOn(&run_tui_data_tests.step);
    test_step.dependOn(&tracking_coverage_audit.step);
    test_step.dependOn(&run_tui_compatibility_tests.step);
    test_step.dependOn(&tui_e2e.step);
    test_step.dependOn(&cli_help.step);
    test_step.dependOn(&cli_version.step);
    test_step.dependOn(&cli_database_human.step);
    test_step.dependOn(&cli_database_json.step);
    test_step.dependOn(&cli_invalid.step);
    test_step.dependOn(&cli_invalid_json.step);
    test_step.dependOn(&cli_after_broken_pipe.step);
    test_step.dependOn(&cli_workout_start_test.step);
    test_step.dependOn(&cli_workout_resolution_test.step);
    test_step.dependOn(&cli_add_exercise_test.step);
    test_step.dependOn(&cli_set_commands_test.step);
    test_step.dependOn(&cli_workout_end_test.step);
    test_step.dependOn(&cli_catalog_commands_test.step);
    test_step.dependOn(&cli_history_commands_test.step);
    test_step.dependOn(&cli_ergonomics_test.step);
    test_step.dependOn(&cli_batch_test.step);
    test_step.dependOn(&cli_completion_test.step);
    test_step.dependOn(&cli_shell_smoke_test.step);
    test_step.dependOn(&cli_database_diagnostics_test.step);
    test_step.dependOn(&private_import_check.step);
    test_step.dependOn(&npm_clean_smoke.step);
    test_step.dependOn(&npm_release_test.step);
    test_step.dependOn(&docs_quickstart_test.step);
    test_step.dependOn(&cli_documentation_test.step);
    test_step.dependOn(&cli_release_workflow_test.step);
    test_step.dependOn(&methodology_guides_test.step);
    test_step.dependOn(&data_mapping_guide_test.step);
    test_step.dependOn(&custom_repository_test.step);
    test_step.dependOn(&testing_utilities_test.step);
    test_step.dependOn(&npm_examples_test.step);
    test_step.dependOn(&zig_package_consumer_test.step);
    test_step.dependOn(&c_release_test.step);

    const format_check = b.addSystemCommand(&.{ "zig", "fmt", "--check", "." });
    const diff_check = b.addSystemCommand(&.{ "git", "diff", "--check" });
    const repository_validation = b.addSystemCommand(&.{ "node", "tools/repo/validate-repository.mjs" });
    const public_contract_validation = b.addSystemCommand(&.{ "node", "tools/repo/public-contract-snapshot.mjs" });
    const fast_check = b.step(
        "check-fast",
        "Run fast local checks: formatting, repository metadata, and core tests",
    );
    fast_check.dependOn(&format_check.step);
    fast_check.dependOn(&diff_check.step);
    fast_check.dependOn(&repository_validation.step);
    fast_check.dependOn(&public_contract_validation.step);
    fast_check.dependOn(&run_library_tests.step);

    const check = b.step(
        "check",
        "Run the canonical pull-request verification suite",
    );
    check.dependOn(fast_check);
    check.dependOn(test_step);

    const release_validation = b.addSystemCommand(&.{ "node", "tools/release/validate-npm-release.mjs", "v0.1.0" });
    const release_metadata_validation = b.addSystemCommand(&.{ "node", "tools/release/validate-release-metadata.mjs" });
    const release_workflow_validation = b.addSystemCommand(&.{ "node", "tests/cli_release_workflow_test.mjs" });
    const compatibility_validation = b.addSystemCommand(&.{ "node", "tools/repo/compatibility-check.mjs" });
    const check_release = b.step(
        "check-release",
        "Run canonical checks plus release metadata and artifact workflow validation",
    );
    check_release.dependOn(check);
    check_release.dependOn(&release_validation.step);
    check_release.dependOn(&release_metadata_validation.step);
    check_release.dependOn(&release_workflow_validation.step);
    check_release.dependOn(&compatibility_validation.step);
    check_release.dependOn(fuzz_smoke_step);
    check_release.dependOn(mutation_smoke_step);

    const release_validate_step = b.step(
        "release-validate",
        "Validate release metadata, compatibility records, and release workflow expectations without publishing",
    );
    release_validate_step.dependOn(check_release);

    const release_stage_step = b.step(
        "release-stage",
        "Build release candidate packages and artifacts after release validation; never publish",
    );
    release_stage_step.dependOn(release_validate_step);
    release_stage_step.dependOn(npm_package_step);
    release_stage_step.dependOn(zig_package_archive_step);
    release_stage_step.dependOn(&c_release_package.step);

    const clean = b.addSystemCommand(&.{ "rm", "-rf", ".zig-cache", "zig-out" });
    const clean_step = b.step("clean", "Remove generated Zig cache and build output");
    clean_step.dependOn(&clean.step);

    const clean_all = b.addSystemCommand(&.{ "rm", "-rf", ".zig-cache", "zig-out", "packages/npm/workout-engine/dist", "packages/exercise-catalog/dist", "packages/persistence/dist", "packages/persistence-indexeddb/dist" });
    const clean_all_step = b.step("clean-all", "Remove all repository-generated build and package output");
    clean_all_step.dependOn(&clean_all.step);
}
