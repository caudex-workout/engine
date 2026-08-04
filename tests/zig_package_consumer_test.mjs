import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(".");
const temporary = await mkdtemp(join(tmpdir(), "caudex-zig-consumer-"));
const packaged = join(temporary, "packages");
const cache = join(temporary, "cache");
const globalCache = join(temporary, "global-cache");

try {
  const generated = spawnSync("node", [join(root, "tools/release/build-zig-packages.mjs"), packaged], { encoding: "utf8" });
  if (generated.status !== 0) throw new Error(generated.stdout + generated.stderr);

  for (const name of ["core", "sqlite", "exercise-catalog", "cli"]) {
    runZigBuild(join(packaged, name), ["build"], cache, globalCache);
  }

  for (const forbidden of ["apps", "catalog", "adapters/sqlite.zig"]) {
    try {
      await access(join(packaged, "core", forbidden));
      throw new Error(`core package unexpectedly contains ${forbidden}`);
    } catch (error) {
      if (error.message?.startsWith("core package unexpectedly")) throw error;
    }
  }
  const coreManifest = await readFile(join(packaged, "core", "build.zig.zon"), "utf8");
  if (coreManifest.includes("vaxis") || coreManifest.includes("sqlite.zig")) {
    throw new Error("core package manifest contains application or SQLite dependencies");
  }

  const consumer = join(temporary, "consumer");
  await mkdir(join(consumer, "src"), { recursive: true });
  await writeFile(join(consumer, "build.zig.zon"), `.forbidden\n`.replace(".forbidden", `.{
    .name = .clean_consumer,
    .version = "0.0.0",
    .fingerprint = 0xe359b05add76bf69,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .core = .{ .path = "../packages/core" },
        .sqlite = .{ .path = "../packages/sqlite" },
        .catalog = .{ .path = "../packages/exercise-catalog" },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}`));
  await writeFile(join(consumer, "build.zig"), `const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("core", .{ .target = target, .optimize = optimize });
    const sqlite = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
    const catalog = b.dependency("catalog", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "consumer", .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = core.module("caudex") },
        .{ .name = "caudex_tracking", .module = core.module("caudex_tracking") },
        .{ .name = "caudex_sqlite", .module = sqlite.module("caudex_sqlite") },
        .{ .name = "caudex_exercise_catalog", .module = catalog.module("caudex_exercise_catalog") },
    } }) });
    b.installArtifact(exe);
}`);
  await writeFile(join(consumer, "src/main.zig"), `const std = @import("std");
const caudex = @import("caudex");
const tracking = @import("caudex_tracking");
const sqlite = @import("caudex_sqlite");
const catalog = @import("caudex_exercise_catalog");
pub fn main() void { std.debug.print("{d} {d} {d} {d}\\n", .{ caudex.engine.schema_version, tracking.contract_version, sqlite.schema_version, catalog.schema_version }); }
`);
  runZigBuild(consumer, ["build"], cache, globalCache);
  console.log("caudex clean Zig package consumers passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function runZigBuild(cwd, args, cacheDirectory, globalCacheDirectory) {
  const result = spawnSync(
    "zig",
    [
      ...args,
      "--cache-dir",
      cacheDirectory,
      "--global-cache-dir",
      globalCacheDirectory,
    ],
    {
      cwd,
      encoding: "utf8",
      stdio: "pipe",
      timeout: 30_000,
    },
  );
  if (result.status !== 0) {
    throw new Error(
      `clean Zig build failed (${result.status})\n${result.stdout}${result.stderr}`,
    );
  }
  return result;
}
