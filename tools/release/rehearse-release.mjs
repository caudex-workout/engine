import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { validateRelease, repositoryRoot } from "./validate-release.mjs";

const release = await validateRelease(`v${JSON.parse(await fs.readFile(
  path.join(repositoryRoot, "packages/npm/workout-engine/package.json"),
  "utf8",
)).version}`);
const output = path.join(repositoryRoot, "zig-out", "release-check");
await fs.rm(output, { recursive: true, force: true });
await fs.mkdir(path.join(output, "npm"), { recursive: true });

run("zig", ["build", "package-npm"]);
const pack = run("npm", [
  "pack",
  "packages/npm/workout-engine",
  "--json",
  "--ignore-scripts",
  "--pack-destination",
  path.join(output, "npm"),
], false);
const tarballName = JSON.parse(pack.stdout)[0].filename;
const tarball = path.join(output, "npm", tarballName);
run("node", ["tests/npm_clean_smoke.mjs", "--tarball", tarball]);
run("npm", ["publish", tarball, "--dry-run", "--ignore-scripts", "--access", "public", "--tag", release.npmTag]);

run("node", ["tools/release/build-zig-packages.mjs", path.join(output, "zig")]);
run("node", [
  "tools/release/package_release_sources.mjs",
  "--version", release.version,
  "--kind", "zig",
  "--source", path.join(output, "zig"),
  "--output", path.join(output, "assets"),
]);
run("node", ["tools/release/build-c-artifacts.mjs", path.join(output, "c"), "--host-only", "--test"]);
run("node", [
  "tools/release/package_release_sources.mjs",
  "--version", release.version,
  "--kind", "c",
  "--source", path.join(output, "c"),
  "--output", path.join(output, "assets"),
]);

if (process.platform === "linux" || process.platform === "darwin") {
  run("zig", ["build", "-Doptimize=ReleaseSafe", "caudex-cli"]);
  const target = `${process.arch === "arm64" ? "aarch64" : "x86_64"}-${process.platform === "darwin" ? "macos" : "linux-gnu"}`;
  const binary = path.join(repositoryRoot, "zig-out", "bin", "caudex");
  const sqlite = findSqlite(binary);
  await fs.mkdir(path.join(output, "cli"), { recursive: true });
  run("node", [
    "tools/release/package_cli.mjs",
    "--version", release.version,
    "--target", target,
    "--archive", "tar.gz",
    "--binary", binary,
    "--output", path.join(output, "cli", `caudex-workout-cli-${release.version}-${target}.tar.gz`),
    "--sqlite-version", run("sqlite3", ["--version"], false).stdout.trim().split(/\s+/)[0],
    "--sqlite-linkage", "dynamic system library",
    "--sqlite-source", `local system SQLite (${sqlite})`,
    "--sqlite-library", sqlite,
  ]);
} else {
  console.log("local release rehearsal: Windows CLI packaging remains covered by the GitHub matrix");
}

console.log(`local release rehearsal passed for ${release.tag}`);
console.log("CI-only remainder: cross-platform CLI matrix, complete C matrix, provenance attestations, and final external publication.");

function findSqlite(binary) {
  const command = process.platform === "darwin" ? "otool" : "ldd";
  const args = process.platform === "darwin" ? ["-L", binary] : [binary];
  const result = run(command, args, false).stdout;
  const line = result.split("\n").find((value) => value.includes("sqlite3"));
  const candidate = line?.trim().split(/\s+/)[0];
  if (candidate && path.isAbsolute(candidate) && exists(candidate)) return candidate;
  if (process.platform === "darwin" && exists("/usr/bin/sqlite3")) return "/usr/bin/sqlite3";
  throw new Error(`could not resolve a host SQLite library from ${command}`);
}

function exists(file) {
  return existsSync(file);
}

function run(command, args, inherit = true) {
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    stdio: inherit ? "inherit" : "pipe",
    timeout: 15 * 60 * 1000,
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}\n${result.stderr ?? ""}`);
  }
  return result;
}
