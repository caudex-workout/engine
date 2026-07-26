import { spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const packageRoot = resolve("packages/npm/workout-engine");
const temporary = await mkdtemp(join(tmpdir(), "caudex-data-mapping-"));
const packDirectory = join(temporary, "pack");
const project = join(temporary, "project");

try {
  await mkdir(packDirectory);
  await mkdir(project);
  run("npm", [
    "pack",
    "--json",
    "--ignore-scripts",
    "--pack-destination",
    packDirectory,
    packageRoot,
  ]);
  const [tarballName] = await readdir(packDirectory);
  run(
    "npm",
    [
      "install",
      "--ignore-scripts",
      "--no-audit",
      "--no-fund",
      join(packDirectory, tarballName),
    ],
    project,
  );
  await cp(
    resolve("examples/typescript-node/data-mapping.ts"),
    join(project, "data-mapping.ts"),
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
        target: "ES2022",
        module: "NodeNext",
        moduleResolution: "NodeNext",
        outDir: "dist",
        lib: ["ES2022", "DOM"],
      },
      files: ["data-mapping.ts"],
    }),
  );
  run(process.execPath, [
    resolve(packageRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  const result = run(
    process.execPath,
    ["dist/data-mapping.js"],
    project,
    true,
  );
  const output = JSON.parse(result.stdout);
  if (
    output.catalogExerciseId !== "host-exercise:42" ||
    output.historyExerciseId !== output.catalogExerciseId ||
    output.load?.amount !== "65" ||
    output.load?.unit !== "lb" ||
    output.decisions?.rejected !== "unchanged" ||
    output.decisions?.accepted !== "saved" ||
    output.savedMethodologyId !== "caudex.double-progression"
  ) {
    throw new Error(`unexpected data mapping output: ${result.stdout}`);
  }

  const guide = await readFile(resolve("docs/data-mapping.md"), "utf8");
  for (const required of [
    "## Keep host IDs stable",
    "## Map an exercise catalog",
    "## Map workout history",
    "## Handle optional and missing fields",
    "## Load and persist methodology state",
    "## Accept or reject a recommendation",
  ]) {
    if (!guide.includes(required)) {
      throw new Error(`data mapping guide is missing ${required}`);
    }
  }

  console.log("caudex data mapping guide and example passed");
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
