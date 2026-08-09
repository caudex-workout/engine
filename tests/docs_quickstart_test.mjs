import { spawnSync } from "node:child_process";
import { cp, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const packageRoot = resolve("packages/npm/workout-engine");
const temporary = await mkdtemp(join(tmpdir(), "caudex-docs-quickstart-"));
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
    resolve("examples/typescript-node/quickstart.ts"),
    join(project, "quickstart.ts"),
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
      files: ["quickstart.ts"],
    }),
  );
  run(process.execPath, [
    resolve(packageRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  const result = run(process.execPath, ["dist/quickstart.js"], project, true);
  const output = JSON.parse(result.stdout);
  if (
    output.exerciseId !== "incline-dumbbell-press" ||
    output.sets !== 3 ||
    output.explanation?.code !== "exercise.selected.available_equipment" ||
    typeof output.explanation?.summary !== "string" ||
    typeof output.fingerprint !== "string"
  ) {
    throw new Error(`unexpected quickstart output: ${result.stdout}`);
  }
  console.log(
    `caudex documentation quickstart passed: ${output.exerciseId}, ` +
      `${output.explanation.code}`,
  );
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
