import { spawnSync } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readdir,
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
    JSON.stringify({ private: true, type: "module" }),
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
  throw new Error("IndexedDB package runtime exports failed");
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
if (INDEXEDDB_SCHEMA_VERSION !== 4) throw new Error("schema version mismatch");
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
    resolve(roots.indexeddb, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  console.log(
    "caudex clean IndexedDB browser package smoke passed: packed peers and DOM types",
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
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}`,
    );
  }
}
