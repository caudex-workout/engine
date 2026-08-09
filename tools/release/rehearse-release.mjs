import fs from "node:fs/promises";
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
  // The focused caudex-cli step compiles the executable but does not install
  // it into zig-out/bin. The rehearsal inspects and packages that installed
  // path, so use the install step explicitly for clean checkouts.
  run("zig", ["build", "-Doptimize=ReleaseSafe", "install"]);
  const target = `${process.arch === "arm64" ? "aarch64" : "x86_64"}-${process.platform === "darwin" ? "macos" : "linux-gnu"}`;
  const binary = path.join(repositoryRoot, "zig-out", "bin", "caudex");
  await fs.mkdir(path.join(output, "cli"), { recursive: true });
  run("node", [
    "tools/release/package_cli.mjs",
    "--version", release.version,
    "--target", target,
    "--archive", "tar.gz",
    "--binary", binary,
    "--output", path.join(output, "cli", `caudex-workout-cli-${release.version}-${target}.tar.gz`),
    "--sqlite-version", "3.49.1",
    "--sqlite-linkage", "bundled official SQLite amalgamation",
    "--sqlite-source", "https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip",
    "--sqlite-source-file", "vendor/sqlite/sqlite3.c",
  ]);
} else {
  console.log("local release rehearsal: Windows CLI packaging remains covered by the GitHub matrix");
}

console.log(`local release rehearsal passed for ${release.tag}`);
console.log("CI-only remainder: cross-platform CLI matrix, complete C matrix, provenance attestations, and final external publication.");

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
