import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const versions = JSON.parse(fs.readFileSync(path.join(root, "tools/support/versions.json"), "utf8"));
const zon = fs.readFileSync(path.join(root, "build.zig.zon"), "utf8");
const packageJson = JSON.parse(fs.readFileSync(path.join(root, "packages/npm/workout-engine/package.json"), "utf8"));
const lockJson = JSON.parse(fs.readFileSync(path.join(root, "packages/npm/workout-engine/package-lock.json"), "utf8"));
const zigPackageManifests = [
  "packages/zig/core/build.zig.zon",
  "packages/zig/sqlite/build.zig.zon",
  "packages/zig/exercise-catalog/build.zig.zon",
  "packages/zig/cli/build.zig.zon",
];

function fail(message) {
  console.error(`repository validation: ${message}`);
  process.exitCode = 1;
}

if (!zon.includes(`.minimum_zig_version = "${versions.zig}"`)) fail(`build.zig.zon is not pinned to Zig ${versions.zig}`);
if (!zon.includes(`.version = "${packageJson.version}"`)) fail("package and Zig package versions drifted");
for (const manifest of zigPackageManifests) {
  const source = fs.readFileSync(path.join(root, manifest), "utf8");
  if (!source.includes(`.version = "${packageJson.version}"`)) fail(`${manifest} version drifted`);
}
if (lockJson.version !== packageJson.version || lockJson.packages?.[""]?.version !== packageJson.version) fail("npm lockfile version drifted");
if (Number(packageJson.engines?.node?.match(/\d+/)?.[0]) !== Number(versions.node_min)) fail("npm engine and supported Node minimum drifted");

for (const file of [
  "README.md",
  "CONTRIBUTING.md",
  "docs/development/setup.md",
  "docs/development/testing.md",
  "docs/development/repository-map.md",
  "docs/development/engineering-style.md",
]) {
  if (!fs.existsSync(path.join(root, file))) fail(`required contributor file is missing: ${file}`);
}

const styleExceptionsPath = path.join(
  root,
  "docs/development/engineering-style-exceptions.json",
);
const styleExceptions = JSON.parse(fs.readFileSync(styleExceptionsPath, "utf8"));
if (!Array.isArray(styleExceptions)) {
  fail("engineering-style exceptions must be a JSON array");
} else {
  const exceptionKeys = new Set();
  for (const exception of styleExceptions) {
    const { rule, file, symbol, reason } = exception ?? {};
    if (
      ![rule, file, symbol, reason].every(
        (value) => typeof value === "string" && value.trim().length > 0,
      )
    ) {
      fail("every engineering-style exception must name a rule, file, symbol, and reason");
      continue;
    }
    const key = `${rule}:${file}:${symbol}`;
    if (exceptionKeys.has(key)) fail(`duplicate engineering-style exception: ${key}`);
    exceptionKeys.add(key);
    const sourcePath = path.join(root, file);
    if (!fs.existsSync(sourcePath)) {
      fail(`engineering-style exception references a missing file: ${file}`);
      continue;
    }
    if (!fs.readFileSync(sourcePath, "utf8").includes(symbol)) {
      fail(`engineering-style exception references a stale symbol: ${file}:${symbol}`);
    }
  }
}

for (const file of fs.readdirSync(path.join(root, ".github/workflows"))) {
  if (!file.endsWith(".yml") && !file.endsWith(".yaml")) continue;
  const source = fs.readFileSync(path.join(root, ".github/workflows", file), "utf8");
  for (const match of source.matchAll(/uses:\s*([^\s#]+)/g)) {
    const ref = match[1].split("@")[1] ?? "";
    if (!/^[0-9a-f]{40}$/.test(ref)) fail(`${file} uses an unpinned action: ${match[1]}`);
  }
}

for (const file of fs.readdirSync(path.join(root, "schemas"), { withFileTypes: true })) {
  void file;
}
function walk(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(target);
    else if (entry.name.endsWith(".schema.json")) JSON.parse(fs.readFileSync(target, "utf8"));
  }
}
walk(path.join(root, "schemas"));

if (process.exitCode) process.exit(1);
console.log("repository validation: version, documentation, action-pin, and schema checks passed");
