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
    test_step.dependOn(&wasm_library.step);
}
