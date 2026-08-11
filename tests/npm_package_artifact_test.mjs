import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const packageRoot = resolve(
  process.argv[2] ?? "packages/npm/workout-engine",
);
const temporary = await mkdtemp(join(tmpdir(), "caudex-npm-pack-"));

try {
  const packed = spawnSync(
    "npm",
    [
      "pack",
      "--json",
      "--ignore-scripts",
      "--pack-destination",
      temporary,
      packageRoot,
    ],
    { encoding: "utf8" },
  );
  if (packed.status !== 0) {
    throw new Error(`npm pack failed:\n${packed.stderr}`);
  }
  const [manifest] = JSON.parse(packed.stdout);
  const paths = manifest.files.map((file) => file.path).sort();
  const required = [
    "LICENSE",
    "NOTICE",
    "README.md",
    "dist/index.d.ts",
    "dist/index.js",
    "dist/canonical.d.ts",
    "dist/application.js",
    "dist/active-workout.js",
    "dist/canonical.js",
    "dist/measurements.d.ts",
    "dist/measurements.js",
    "dist/methodologies.js",
    "dist/methodologies.d.ts",
    "dist/methodologies/index.d.ts",
    "dist/methodologies/index.js",
    "dist/programs.d.ts",
    "dist/programs.js",
    "dist/testing.d.ts",
    "dist/testing.js",
    "dist/runtime.d.ts",
    "dist/runtime.js",
    "dist/wasm-runtime.js",
    "fixtures/requests/recommendation.json",
    "fixtures/results/recommendation-no-history.json",
    "package.json",
    "schemas/v0/canonical.schema.json",
    "wasm/caudex.wasm",
  ];
  for (const path of required) {
    if (!paths.includes(path)) throw new Error(`packed artifact is missing ${path}`);
  }
  for (const path of paths) {
    if (
      path.startsWith("src/") ||
      path.startsWith("scripts/") ||
      path.includes("node_modules") ||
      path.endsWith(".tgz")
    ) {
      throw new Error(`unintended packed file: ${path}`);
    }
  }
  const metadata = JSON.parse(
    await readFile(resolve(packageRoot, "package.json"), "utf8"),
  );
  for (const forbidden of ["preinstall", "install", "postinstall"]) {
    if (metadata.scripts?.[forbidden]) {
      throw new Error(`package must not define ${forbidden}`);
    }
  }
  if (metadata.dependencies && Object.keys(metadata.dependencies).length !== 0) {
    throw new Error("runtime package must have no production dependencies");
  }
  console.log(
    `caudex npm artifact: ${manifest.filename}, ` +
      `${manifest.size} packed bytes, ${manifest.unpackedSize} unpacked bytes, ` +
      `${paths.length} files`,
  );
} finally {
  await rm(temporary, { recursive: true, force: true });
}
