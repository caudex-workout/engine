import fs from "node:fs/promises";
import { mkdtemp, cp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { releaseAssetManifest } from "../tools/release/artifact-manifest.mjs";
import { parseReleaseTag, validateRelease } from "../tools/release/validate-release.mjs";

const workflow = await fs.readFile(".github/workflows/release.yml", "utf8");
const parsed = [
  ["v0.1.0", "0.1.0", false, "latest"],
  ["v0.1.1", "0.1.1", false, "latest"],
  ["v1.0.0", "1.0.0", false, "latest"],
  ["v0.2.0-rc.1", "0.2.0-rc.1", true, "next"],
];
for (const [tag, version, prerelease, npmTag] of parsed) {
  const result = parseReleaseTag(tag);
  if (result.version !== version || result.prerelease !== prerelease || result.npmTag !== npmTag) {
    throw new Error(`release tag parsing failed for ${tag}`);
  }
}
for (const invalid of ["0.1.0", "vfoo", "v0.1", "v01.2.3", "v1.2.3-"]) {
  try {
    parseReleaseTag(invalid);
    throw new Error(`invalid release tag was accepted: ${invalid}`);
  } catch (error) {
    if (error.message.startsWith("invalid release tag was accepted")) throw error;
  }
}

const fixtureRoot = await mkdtemp(path.join(tmpdir(), "caudex-release-validator-"));
try {
  for (const relative of [
    "packages/npm/workout-engine/package.json",
    "packages/npm/workout-engine/package-lock.json",
    "build.zig.zon",
    "packages/zig/core/build.zig.zon",
    "packages/zig/sqlite/build.zig.zon",
    "packages/zig/exercise-catalog/build.zig.zon",
    "packages/zig/cli/build.zig.zon",
    "apps/caudex-cli/src/main.zig",
    "CHANGELOG.md",
    "tools/release/release-metadata.json",
  ]) {
    await fs.mkdir(path.dirname(path.join(fixtureRoot, relative)), { recursive: true });
    await cp(relative, path.join(fixtureRoot, relative), { recursive: true });
  }
  await validateRelease("v0.1.0", { root: fixtureRoot });
  const packagePath = path.join(fixtureRoot, "packages/npm/workout-engine/package.json");
  const packageMetadata = JSON.parse(await fs.readFile(packagePath, "utf8"));
  packageMetadata.version = "0.1.1";
  await fs.writeFile(packagePath, `${JSON.stringify(packageMetadata)}\n`);
  await expectFailure(() => validateRelease("v0.1.0", { root: fixtureRoot }), "package.json version");
  packageMetadata.version = "0.1.0";
  await fs.writeFile(packagePath, `${JSON.stringify(packageMetadata)}\n`);
  await fs.writeFile(path.join(fixtureRoot, "CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n");
  await expectFailure(() => validateRelease("v0.1.0", { root: fixtureRoot }), "CHANGELOG.md must contain");
} finally {
  await rm(fixtureRoot, { recursive: true, force: true });
}

const assets = await releaseAssetManifest("1.2.3");
const names = new Set(assets.map((asset) => asset.name));
for (const required of [
  "caudex-workout-engine-1.2.3.tgz",
  "caudex-workout-cli-1.2.3-x86_64-linux-gnu.tar.gz",
  "caudex-c-1.2.3-aarch64-windows-gnu.tar.gz",
  "caudex-zig-1.2.3-core.tar.gz",
  "SHA256SUMS",
  "release-manifest.json",
]) {
  if (!names.has(required)) throw new Error(`asset manifest is missing ${required}`);
}

for (const phrase of [
  'tags:\n      - "v*"',
  "workflow_dispatch:",
  "validate-release.mjs",
  "npm publish",
  "--dry-run",
  "--provenance",
  "gh release create",
  "--draft",
  "attest-build-provenance",
  "CAUDEX_NPM_AUTH_MODE",
  "cancel-in-progress: false",
]) {
  if (!workflow.includes(phrase)) throw new Error(`release orchestrator is missing ${phrase}`);
}
if (workflow.includes("v0.1.0") || workflow.includes("gh release edit v0.1.0")) {
  throw new Error("release orchestrator contains a hard-coded release version");
}
if (!workflow.includes("if: github.event_name == 'push'")) {
  throw new Error("workflow dispatch must remain rehearsal-only");
}
for (const obsolete of [".github/workflows/npm-release.yml", ".github/workflows/cli-release.yml", ".github/workflows/c-release.yml"]) {
  try {
    await fs.access(obsolete);
    throw new Error(`obsolete release workflow remains: ${obsolete}`);
  } catch (error) {
    if (error.message.startsWith("obsolete release workflow remains")) throw error;
  }
}
for (const helper of ["tools/release/package_cli.mjs", "tools/release/package_release_sources.mjs", "tools/release/verify-cli-release.mjs"]) {
  const source = await fs.readFile(helper, "utf8");
  const forbiddenRuntime = ["py", "thon"].join("");
  if (source.includes("0.1.0") || new RegExp(forbiddenRuntime, "i").test(source)) throw new Error(`${helper} contains a forbidden release-tool reference`);
}
console.log("release workflow, tag parsing, and asset manifest contracts passed");

async function expectFailure(operation, message) {
  try {
    await operation();
    throw new Error(`expected release validation failure containing ${message}`);
  } catch (error) {
    if (error.message.startsWith("expected release validation failure")) throw error;
    if (!error.message.includes(message)) throw error;
  }
}
