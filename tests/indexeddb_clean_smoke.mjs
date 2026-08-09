import { spawnSync } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const roots = {
  engine: resolve("packages/npm/workout-engine"),
  persistence: resolve("packages/persistence"),
  indexeddb: resolve("packages/persistence-indexeddb"),
};
const contract = "IndexedDB clean-consumer packaging";
const indexeddbManifest = JSON.parse(
  await readFile(join(roots.indexeddb, "package.json"), "utf8"),
);
const typescriptVersion = indexeddbManifest.devDependencies?.typescript;
if (typeof typescriptVersion !== "string" || typescriptVersion.length === 0) {
  throw new Error(`${contract}: package must pin its TypeScript test tool`);
}
const temporary = await mkdtemp(join(tmpdir(), "caudex-indexeddb-smoke-"));
const packDirectory = join(temporary, "pack");
const project = join(temporary, "project");
await mkdir(packDirectory);
await mkdir(project);

try {
  for (const root of Object.values(roots)) {
    run("npm", [
      "pack",
      "--json",
      "--ignore-scripts",
      "--pack-destination",
      packDirectory,
      root,
    ]);
  }
  const tarballs = (await readdir(packDirectory))
    .map((name) => join(packDirectory, name));
  await writeFile(
    join(project, "package.json"),
    JSON.stringify({
      private: true,
      type: "module",
      devDependencies: { typescript: typescriptVersion },
    }),
  );
  run("npm", [
    "install",
    "--ignore-scripts",
    "--no-audit",
    "--no-fund",
    ...tarballs,
  ], project);
  await writeFile(
    join(project, "runtime-smoke.mjs"),
    `import {
  IndexedDbPersistenceAdapter,
  INDEXEDDB_SCHEMA_VERSION,
} from "@caudex-workout/persistence-indexeddb";
if (INDEXEDDB_SCHEMA_VERSION !== 4 ||
    typeof IndexedDbPersistenceAdapter !== "function") {
  throw new Error("IndexedDB clean-consumer packaging: runtime exports failed");
}
`,
  );
  run(process.execPath, ["runtime-smoke.mjs"], project);
  await writeFile(
    join(project, "smoke.ts"),
    `import {
  IndexedDbPersistenceAdapter,
  INDEXEDDB_SCHEMA_VERSION,
} from "@caudex-workout/persistence-indexeddb";
import type { ActiveWorkoutStore, CatalogSource, MethodologyStateStore, PortableDataStore, WorkoutTemplateStore, WorkflowRecoveryStore } from "@caudex-workout/persistence";

const adapter = new IndexedDbPersistenceAdapter({ databaseName: "smoke" });
const catalog: CatalogSource = adapter;
const states: MethodologyStateStore = adapter;
const active: ActiveWorkoutStore = adapter;
const templates: WorkoutTemplateStore = adapter;
const recovery: WorkflowRecoveryStore = adapter;
const portable: PortableDataStore = adapter;
if (INDEXEDDB_SCHEMA_VERSION !== 4) throw new Error("IndexedDB clean-consumer packaging: schema version mismatch");
void catalog;
void states;
void active;
void templates;
void recovery;
void portable;
`,
  );
  await writeFile(
    join(project, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        noEmit: true,
        target: "ES2022",
        module: "NodeNext",
        moduleResolution: "NodeNext",
        lib: ["ES2022", "DOM"],
      },
      files: ["smoke.ts"],
    }),
  );
  run(process.execPath, [
    join(project, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  console.log(
    `${contract}: packed peers and DOM types passed`,
  );
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function run(command, args, cwd = undefined) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: "inherit",
    timeout: 30_000,
  });
  if (result.error) {
    throw new Error(
      `${contract}: ${command} ${args.join(" ")} could not start: ${result.error.message}`,
    );
  }
  if (result.signal) {
    throw new Error(
      `${contract}: ${command} ${args.join(" ")} terminated with ${result.signal}`,
    );
  }
  if (result.status !== 0) {
    throw new Error(
      `${contract}: ${command} ${args.join(" ")} failed with status ${result.status}`,
    );
  }
}
