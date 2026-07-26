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

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_library_tests.step);
    test_step.dependOn(&run_contract_tests.step);
    test_step.dependOn(&run_architecture_tests.step);
    test_step.dependOn(&run_c_api_tests.step);
    test_step.dependOn(&c_header_test.step);
    test_step.dependOn(&cpp_header_test.step);
    test_step.dependOn(&run_c_conformance.step);
    test_step.dependOn(&wasm_library.step);
    test_step.dependOn(&wasm_conformance.step);
    test_step.dependOn(&typescript_loader_test.step);
    test_step.dependOn(&methodology_factory_test.step);
    test_step.dependOn(&npm_package_test.step);
    test_step.dependOn(&npm_clean_smoke.step);
    test_step.dependOn(&npm_release_test.step);
    test_step.dependOn(&docs_quickstart_test.step);
    test_step.dependOn(&methodology_guides_test.step);
    test_step.dependOn(&data_mapping_guide_test.step);
    test_step.dependOn(&testing_utilities_test.step);
    test_step.dependOn(&npm_examples_test.step);
    test_step.dependOn(&zig_package_consumer_test.step);
}
