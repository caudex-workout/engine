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
  for (const [packageName, root] of Object.entries(roots)) {
    run("npm", [
      "pack",
      "--json",
      "--ignore-scripts",
      "--pack-destination",
      packDirectory,
      root,
    ], undefined, `pack ${packageName}`);
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
  ], project, "install packed consumer dependencies");
  await writeFile(
    join(project, "runtime-smoke.mjs"),
    `import {
  IndexedDbPersistenceAdapter,
  INDEXEDDB_SCHEMA_VERSION,
} from "@caudex-workout/persistence-indexeddb";
if (INDEXEDDB_SCHEMA_VERSION !== 6 ||
    typeof IndexedDbPersistenceAdapter !== "function") {
  throw new Error("IndexedDB clean-consumer packaging: runtime exports failed");
}
`,
  );
  run(process.execPath, ["runtime-smoke.mjs"], project, "run consumer runtime smoke");
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
if (INDEXEDDB_SCHEMA_VERSION !== 6) throw new Error("IndexedDB clean-consumer packaging: schema version mismatch");
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
  ], undefined, "typecheck consumer project");
  console.log(
    `${contract}: packed peers and DOM types passed`,
  );
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function run(command, args, cwd = undefined, phase = "subprocess") {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: "pipe",
    timeout: 30_000,
  });
  const commandLine = [command, ...args].map(shellQuote).join(" ");
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(
      `${contract}: ${phase} failed\n` +
        `package: @caudex-workout/persistence-indexeddb\n` +
        `project: ${project}\n` +
        `command:\n  ${commandLine}\n` +
        `exit status: ${result.status ?? "unknown"}${result.signal ? ` (${result.signal})` : ""}\n` +
        (result.error ? `launcher error: ${result.error.message}\n` : "") +
        outputBlock("stdout", result.stdout) +
        outputBlock("stderr", result.stderr),
    );
  }
}

function shellQuote(value) {
  if (/^[A-Za-z0-9_./:=+-]+$/.test(value)) return value;
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function outputBlock(label, value) {
  const text = value ?? "";
  if (text.length === 0) return `${label}:\n  <empty>\n`;
  const maximum = 12000;
  const bounded = text.length > maximum ? `${text.slice(0, maximum)}\n  [... output truncated at ${maximum} bytes]` : text;
  return `${label}:\n${bounded}\n`;
}
