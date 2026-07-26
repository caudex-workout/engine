import { appendFile, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(
  fileURLToPath(new URL("../..", import.meta.url)),
);
const tag = process.argv[2];
const packagePath = resolve(
  repositoryRoot,
  "packages/npm/workout-engine/package.json",
);
const lockPath = resolve(
  repositoryRoot,
  "packages/npm/workout-engine/package-lock.json",
);
const changelogPath = resolve(repositoryRoot, "CHANGELOG.md");

if (!tag || !/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tag)) {
  fail("release tag must be v followed by a valid release version");
}

const version = tag.slice(1);
const packageMetadata = JSON.parse(await readFile(packagePath, "utf8"));
const lockMetadata = JSON.parse(await readFile(lockPath, "utf8"));

assertEqual(packageMetadata.version, version, "package.json version");
assertEqual(lockMetadata.version, version, "package-lock.json root version");
assertEqual(
  lockMetadata.packages?.[""]?.version,
  version,
  "package-lock.json package version",
);

const changelog = await readFile(changelogPath, "utf8");
const escapedVersion = version.replaceAll(".", "\\.");
const heading = new RegExp(
  `^## \\[${escapedVersion}\\] - (\\d{4}-\\d{2}-\\d{2})$`,
  "m",
);
const match = heading.exec(changelog);
if (!match) {
  fail(`CHANGELOG.md must contain "## [${version}] - YYYY-MM-DD"`);
}

const notesStart = match.index + match[0].length;
const nextHeading = changelog.indexOf("\n## ", notesStart);
const notes = changelog
  .slice(notesStart, nextHeading === -1 ? undefined : nextHeading)
  .trim();
if (!notes || !/^### /m.test(notes) || !/^- /m.test(notes)) {
  fail(`CHANGELOG.md release ${version} must contain a section and list item`);
}

const outputPath = process.env.GITHUB_OUTPUT;
if (outputPath) {
  await appendFile(outputPath, `version=${version}\n`);
}
if (process.env.CAUDEX_RELEASE_NOTES_PATH) {
  await writeFile(process.env.CAUDEX_RELEASE_NOTES_PATH, `${notes}\n`);
}

console.log(`validated npm release ${tag}`);

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    fail(`${label} must be ${expected}, found ${String(actual)}`);
  }
}

function fail(message) {
  console.error(`npm release validation failed: ${message}`);
  process.exit(1);
}
