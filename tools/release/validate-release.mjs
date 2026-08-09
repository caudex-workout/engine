import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);

const semverPattern =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?$/;

export function parseReleaseTag(tag) {
  if (typeof tag !== "string" || !tag.startsWith("v")) {
    throw new Error("release tag must start with v and contain a SemVer version");
  }
  const version = tag.slice(1);
  const match = semverPattern.exec(version);
  if (!match) throw new Error(`invalid release tag: ${tag}`);
  return {
    tag,
    version,
    prerelease: Boolean(match[4]),
    npmTag: match[4] ? "next" : "latest",
  };
}

export async function readReleasePolicy(root = repositoryRoot) {
  return JSON.parse(
    await fs.readFile(
      path.join(root, "tools/release/release-metadata.json"),
      "utf8",
    ),
  );
}

export async function validateRelease(tag, options = {}) {
  const release = parseReleaseTag(tag);
  const root = options.root ?? repositoryRoot;
  const packagePath = path.join(
    root,
    "packages/npm/workout-engine/package.json",
  );
  const lockPath = path.join(
    root,
    "packages/npm/workout-engine/package-lock.json",
  );
  const packageMetadata = JSON.parse(await fs.readFile(packagePath, "utf8"));
  const lockMetadata = JSON.parse(await fs.readFile(lockPath, "utf8"));
  const rootZon = await fs.readFile(path.join(root, "build.zig.zon"), "utf8");
  const changelog = await fs.readFile(
    path.join(root, "CHANGELOG.md"),
    "utf8",
  );
  const policy = await readReleasePolicy(root);
  const errors = [];

  const assert = (condition, message) => {
    if (!condition) errors.push(message);
  };
  const expectedVersion = release.version;
  assert(packageMetadata.version === expectedVersion,
    `packages/npm/workout-engine/package.json version must be ${expectedVersion}, found ${String(packageMetadata.version)}`);
  assert(lockMetadata.version === expectedVersion,
    `package-lock.json version must be ${expectedVersion}, found ${String(lockMetadata.version)}`);
  assert(lockMetadata.packages?.[""]?.version === expectedVersion,
    `package-lock.json root package version must be ${expectedVersion}`);
  assert(rootZon.includes(`.version = "${expectedVersion}"`),
    `build.zig.zon version must be ${expectedVersion}`);

  const zigManifests = [
    "packages/zig/core/build.zig.zon",
    "packages/zig/sqlite/build.zig.zon",
    "packages/zig/exercise-catalog/build.zig.zon",
    "packages/zig/cli/build.zig.zon",
  ];
  for (const manifest of zigManifests) {
    const source = await fs.readFile(path.join(root, manifest), "utf8");
    assert(source.includes(`.version = "${expectedVersion}"`),
      `${manifest} version must be ${expectedVersion}`);
  }

  const cliSource = await fs.readFile(
    path.join(root, "apps/caudex-cli/src/main.zig"),
    "utf8",
  );
  assert(cliSource.includes(`const version = "${expectedVersion}"`),
    `CLI version must be ${expectedVersion}`);

  const escapedVersion = expectedVersion.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const heading = new RegExp(
    `^## \\[${escapedVersion}\\] - (\\d{4}-\\d{2}-\\d{2})$`,
    "m",
  );
  const match = heading.exec(changelog);
  assert(Boolean(match), `CHANGELOG.md must contain ## [${expectedVersion}] - YYYY-MM-DD`);
  let notes = "";
  let releaseDate;
  if (match) {
    releaseDate = match[1];
    const parsedDate = new Date(`${releaseDate}T00:00:00Z`);
    assert(!Number.isNaN(parsedDate.valueOf()) && parsedDate.toISOString().startsWith(releaseDate),
      `CHANGELOG.md release date is invalid: ${releaseDate}`);
    const notesStart = match.index + match[0].length;
    const nextHeading = changelog.indexOf("\n## ", notesStart);
    notes = changelog.slice(notesStart, nextHeading === -1 ? undefined : nextHeading).trim();
    assert(/^### /m.test(notes), `CHANGELOG.md release ${expectedVersion} must contain a subsection`);
    assert(/^- /m.test(notes), `CHANGELOG.md release ${expectedVersion} must contain a list item`);
  }

  assert(policy.checksumAlgorithm === "sha256", "release checksum algorithm must be sha256");
  assert(Array.isArray(policy.cliTargets) && new Set(policy.cliTargets).size === policy.cliTargets.length,
    "release CLI target matrix must be a non-empty unique list");
  assert(Array.isArray(policy.cTargets) && new Set(policy.cTargets).size === policy.cTargets.length,
    "release C target matrix must be a non-empty unique list");

  if (errors.length) {
    throw new Error(`release validation failed:\n- ${errors.join("\n- ")}`);
  }
  const result = {
    ...release,
    packageName: packageMetadata.name,
    releaseDate,
    notes,
    policy,
  };
  if (options.output) {
    await fs.writeFile(options.output, `${JSON.stringify(result, null, 2)}\n`);
  }
  return result;
}

async function main() {
  const tag = process.argv[2] ?? `v${JSON.parse(await fs.readFile(
    path.join(repositoryRoot, "packages/npm/workout-engine/package.json"),
    "utf8",
  )).version}`;
  const outputIndex = process.argv.indexOf("--output");
  const output = outputIndex === -1 ? undefined : path.resolve(process.argv[outputIndex + 1]);
  const result = await validateRelease(tag, { output });
  console.log(`release metadata validated: ${result.tag} (${result.packageName})`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
