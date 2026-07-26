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
        .name = "caudex",
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

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_library_tests.step);
    test_step.dependOn(&run_contract_tests.step);
    test_step.dependOn(&run_architecture_tests.step);
    test_step.dependOn(&run_c_api_tests.step);
    test_step.dependOn(&c_header_test.step);
    test_step.dependOn(&cpp_header_test.step);
    test_step.dependOn(&run_c_conformance.step);
    test_step.dependOn(&wasm_library.step);
}
