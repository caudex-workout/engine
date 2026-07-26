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

    const c_library = b.addLibrary(.{
        .name = "caudex_c",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    c_library.installHeader(b.path("include/caudex.h"), "caudex.h");
    b.installArtifact(c_library);

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

    const persistence_module = b.addModule("caudex_persistence", .{
        .root_source_file = b.path("adapters/persistence.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
        },
    });
    const tracking_module = b.addModule("caudex_tracking", .{
        .root_source_file = b.path("tracking/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = module },
        },
    });
    const tracking_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tracking_contract_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
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
    const tracking_contract_step = b.step(
        "test-tracking-contract",
        "Test the public host-owned tracking contract",
    );
    tracking_contract_step.dependOn(&run_tracking_contract_tests.step);
    tracking_contract_step.dependOn(&run_tracking_lifecycle_tests.step);
    tracking_contract_step.dependOn(&run_tracking_architecture_tests.step);

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
        }),
    });
    const run_c_api_tests = b.addRunArtifact(c_api_tests);

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
    run_c_conformance.addFileArg(b.path("fixtures/requests/recommendation.json"));
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
        }),
    });
    wasm_runtime.entry = .disabled;
    wasm_runtime.rdynamic = true;
    wasm_runtime.export_memory = true;
    b.installArtifact(wasm_runtime);

    const wasm_conformance = b.addSystemCommand(&.{ "node", "tests/wasm_conformance.mjs" });
    wasm_conformance.addArtifactArg(wasm_runtime);
    wasm_conformance.addFileArg(b.path("fixtures/requests/recommendation.json"));
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
    typescript_loader_test.addArtifactArg(wasm_runtime);
    typescript_loader_test.addFileArg(
        b.path("fixtures/requests/recommendation.json"),
    );
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

    const cli_help = b.addRunArtifact(cli);
    cli_help.addArg("--help");
    cli_help.expectStdOutEqual(
        \\Caudex Workout Engine reference client
        \\
        \\Usage:
        \\  caudex [--database PATH] [--format human|json] [--color auto|always|never] database info
        \\  caudex [global options] workout start [start options]
        \\  caudex [global options] workout show --workout ID
        \\  caudex --help
        \\  caudex version
        \\
        \\Environment:
        \\  CAUDEX_DATABASE  Database path used when --database is omitted
        \\
        \\Global options:
        \\  --scope ID        Host scope (default: local)
        \\  --athlete ID      Optional athlete within the host scope
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
    cli_version.expectStdOutEqual("caudex 0.1.0\n");

    const cli_database_human = b.addRunArtifact(cli);
    cli_database_human.addArgs(&.{ "--database", ":memory:", "database", "info" });
    cli_database_human.expectStdOutEqual(
        \\Database: :memory:
        \\Kind: memory
        \\Adapter version: 0.1.0
        \\Schema version: 3
        \\Supported schema: 1-3
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
            "\"adapterVersion\":\"0.1.0\",\"databaseSchemaVersion\":3," ++
            "\"minimumSchemaVersion\":1,\"latestSchemaVersion\":3," ++
            "\"compatibility\":\"current\"}}\n",
    );

    const cli_invalid = b.addRunArtifact(cli);
    cli_invalid.addArgs(&.{ "database", "unknown" });
    cli_invalid.expectExitCode(2);
    cli_invalid.expectStdOutEqual("");
    cli_invalid.expectStdErrEqual(
        "error: Invalid arguments; run 'caudex --help'.\n",
    );

    const cli_invalid_json = b.addRunArtifact(cli);
    cli_invalid_json.addArgs(&.{ "--format", "json", "database", "unknown" });
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
            "\"databaseSchemaVersion\":3,\"minimumSchemaVersion\":1," ++
            "\"latestSchemaVersion\":3,\"compatibility\":\"current\"}}\n",
    );

    const cli_workout_start_test = b.addSystemCommand(&.{
        "bash",
        "tests/cli_workout_start_test.sh",
    });
    cli_workout_start_test.addArtifactArg(cli);

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
    cli_test_step.dependOn(&cli_help.step);
    cli_test_step.dependOn(&cli_version.step);
    cli_test_step.dependOn(&cli_database_human.step);
    cli_test_step.dependOn(&cli_database_json.step);
    cli_test_step.dependOn(&cli_invalid.step);
    cli_test_step.dependOn(&cli_invalid_json.step);
    cli_test_step.dependOn(&cli_after_broken_pipe.step);
    cli_test_step.dependOn(&cli_workout_start_test.step);
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
    test_step.dependOn(&run_tracking_lifecycle_tests.step);
    test_step.dependOn(&run_tracking_architecture_tests.step);
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
    test_step.dependOn(&cli_help.step);
    test_step.dependOn(&cli_version.step);
    test_step.dependOn(&cli_database_human.step);
    test_step.dependOn(&cli_database_json.step);
    test_step.dependOn(&cli_invalid.step);
    test_step.dependOn(&cli_invalid_json.step);
    test_step.dependOn(&cli_after_broken_pipe.step);
    test_step.dependOn(&cli_workout_start_test.step);
    test_step.dependOn(&private_import_check.step);
    test_step.dependOn(&npm_clean_smoke.step);
    test_step.dependOn(&npm_release_test.step);
    test_step.dependOn(&docs_quickstart_test.step);
    test_step.dependOn(&methodology_guides_test.step);
    test_step.dependOn(&data_mapping_guide_test.step);
    test_step.dependOn(&custom_repository_test.step);
    test_step.dependOn(&testing_utilities_test.step);
    test_step.dependOn(&npm_examples_test.step);
    test_step.dependOn(&zig_package_consumer_test.step);
    test_step.dependOn(&c_release_test.step);
}
