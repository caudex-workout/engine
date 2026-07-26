import { spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  mkdtemp,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const engineRoot = resolve("packages/npm/workout-engine");
const persistenceRoot = resolve("packages/persistence");
const temporary = await mkdtemp(join(tmpdir(), "caudex-custom-repository-"));
const packDirectory = join(temporary, "pack");
const project = join(temporary, "project");

try {
  await mkdir(packDirectory);
  await mkdir(project);
  for (const packageRoot of [engineRoot, persistenceRoot]) {
    run("npm", [
      "pack",
      "--json",
      "--ignore-scripts",
      "--pack-destination",
      packDirectory,
      packageRoot,
    ]);
  }
  const tarballs = (await readdir(packDirectory))
    .map((name) => join(packDirectory, name));
  run(
    "npm",
    [
      "install",
      "--ignore-scripts",
      "--no-audit",
      "--no-fund",
      ...tarballs,
    ],
    project,
  );
  await cp(
    resolve("examples/custom-repository/index.ts"),
    join(project, "custom-repository.ts"),
  );
  await writeFile(
    join(project, "package.json"),
    JSON.stringify({ private: true, type: "module" }),
  );
  await writeFile(
    join(project, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        exactOptionalPropertyTypes: true,
        target: "ES2022",
        module: "NodeNext",
        moduleResolution: "NodeNext",
        outDir: "dist",
      },
      files: ["custom-repository.ts"],
    }),
  );
  run(process.execPath, [
    resolve(engineRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  const result = run(
    process.execPath,
    ["dist/custom-repository.js"],
    project,
    true,
  );
  const output = JSON.parse(result.stdout);
  if (
    output.request?.catalogId !== "legacy-exercise:42" ||
    output.request?.historyIds?.join(",") !==
      "legacy-workout:901,legacy-workout:902" ||
    output.request?.historyLoads?.join(",") !== "45,50" ||
    output.request?.loadedStateRevision !== "3" ||
    output.writes?.exercises !== 0 ||
    output.writes?.workouts !== 0 ||
    output.writes?.methodologyStates !== 1 ||
    output.hostRecordsRetained?.exercises !== 1 ||
    output.hostRecordsRetained?.workouts !== 2 ||
    output.savedStateRevision !== "4"
  ) {
    throw new Error(`unexpected custom repository output: ${result.stdout}`);
  }
  console.log("caudex custom repository example passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function run(command, args, cwd = undefined, capture = false) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
    timeout: 30_000,
  });
  if (result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed with status ${result.status}\n` +
        (result.stderr ?? ""),
    );
  }
  return result;
}
