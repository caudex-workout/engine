import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const metadata = JSON.parse(fs.readFileSync(path.join(root, "tools/release/release-metadata.json"), "utf8"));
const zon = fs.readFileSync(path.join(root, "build.zig.zon"), "utf8");
const npm = JSON.parse(fs.readFileSync(path.join(root, "packages/npm/workout-engine/package.json"), "utf8"));
const lock = JSON.parse(fs.readFileSync(path.join(root, "packages/npm/workout-engine/package-lock.json"), "utf8"));
const changelog = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8");

const errors = [];
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(metadata.version)) errors.push("version is not semver");
if (metadata.tag !== `v${metadata.version}`) errors.push("tag/version mismatch");
if (!zon.includes(`.version = \"${metadata.version}\"`)) errors.push("build.zig.zon version drift");
if (npm.version !== metadata.version || lock.version !== metadata.version || lock.packages?.[""]?.version !== metadata.version) errors.push("npm metadata drift");
if (!changelog.includes(`## [${metadata.version}]`)) errors.push("missing changelog section");
if (metadata.checksumAlgorithm !== "sha256") errors.push("unsupported checksum algorithm");
if (new Set(metadata.cliTargets).size !== metadata.cliTargets.length) errors.push("duplicate CLI target");
if (errors.length) {
  console.error(`release metadata validation failed:\n- ${errors.join("\n- ")}`);
  process.exit(1);
}
console.log(`release metadata validated: ${metadata.tag} (${metadata.optimize})`);
