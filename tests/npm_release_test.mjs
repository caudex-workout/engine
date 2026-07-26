import { spawnSync } from "node:child_process";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repositoryRoot = resolve(".");
const temporary = await mkdtemp(join(tmpdir(), "caudex-release-test-"));

try {
  await cp(
    resolve(repositoryRoot, "tools/release/validate-npm-release.mjs"),
    join(temporary, "tools/release/validate-npm-release.mjs"),
    { recursive: true },
  );
  await cp(
    resolve(repositoryRoot, "packages/npm/workout-engine/package.json"),
    join(temporary, "packages/npm/workout-engine/package.json"),
    { recursive: true },
  );
  await cp(
    resolve(repositoryRoot, "packages/npm/workout-engine/package-lock.json"),
    join(temporary, "packages/npm/workout-engine/package-lock.json"),
  );

  await setVersion("1.2.3");
  await writeFile(
    join(temporary, "CHANGELOG.md"),
    "# Changelog\n\n## [1.2.3] - 2026-07-26\n\n### Added\n\n- Release.\n",
  );
  run(["v1.2.3"], 0);
  run(["v1.2.4"], 1);

  await writeFile(
    join(temporary, "CHANGELOG.md"),
    "# Changelog\n\n## [Unreleased]\n\n- Pending.\n",
  );
  run(["v1.2.3"], 1);

  const workflow = await readFile(
    resolve(repositoryRoot, ".github/workflows/npm-release.yml"),
    "utf8",
  );
  for (const required of [
    'tags:\n      - "v*"',
    "workflow_dispatch:",
    "zig build test",
    "npm publish \"${{ steps.pack.outputs.tarball }}\" \\\n            --dry-run",
    "npm publish \"${{ steps.pack.outputs.tarball }}\" --provenance",
    "gh release create",
    "--draft",
    "gh release edit",
    "--draft=false",
    "id-token: write",
    "cancel-in-progress: false",
  ]) {
    if (!workflow.includes(required)) {
      throw new Error(`npm release workflow is missing ${JSON.stringify(required)}`);
    }
  }

  console.log("caudex npm release validation passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

async function setVersion(version) {
  const packagePath = join(
    temporary,
    "packages/npm/workout-engine/package.json",
  );
  const lockPath = join(
    temporary,
    "packages/npm/workout-engine/package-lock.json",
  );
  const packageMetadata = JSON.parse(await readFile(packagePath, "utf8"));
  const lockMetadata = JSON.parse(await readFile(lockPath, "utf8"));
  packageMetadata.version = version;
  lockMetadata.version = version;
  lockMetadata.packages[""].version = version;
  await writeFile(packagePath, JSON.stringify(packageMetadata));
  await writeFile(lockPath, JSON.stringify(lockMetadata));
}

function run(args, expectedStatus) {
  const result = spawnSync(
    process.execPath,
    [join(temporary, "tools/release/validate-npm-release.mjs"), ...args],
    { cwd: temporary, encoding: "utf8" },
  );
  if (result.status !== expectedStatus) {
    throw new Error(
      `release validator returned ${result.status}, expected ${expectedStatus}\n` +
        result.stdout +
        result.stderr,
    );
  }
}
