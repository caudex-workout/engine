const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const caudex = b.dependency("caudex", .{
        .target = target,
        .optimize = optimize,
    });
    const executable = b.addExecutable(.{
        .name = "caudex-zig-consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "caudex", .module = caudex.module("caudex") },
                .{ .name = "caudex_exercise_catalog", .module = caudex.module("caudex_exercise_catalog") },
                .{
                    .name = "caudex_persistence",
                    .module = caudex.module("caudex_persistence"),
                },
                .{
                    .name = "caudex_tracking",
                    .module = caudex.module("caudex_tracking"),
                },
                .{
                    .name = "caudex_sqlite",
                    .module = caudex.module("caudex_sqlite"),
                },
            },
        }),
    });
    b.installArtifact(executable);

    const run = b.addRunArtifact(executable);
    const run_step = b.step("run", "Run the direct Zig consumer");
    run_step.dependOn(&run.step);
}
