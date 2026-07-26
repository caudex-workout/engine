import { spawnSync } from "node:child_process";
import { cp, mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const packageRoot = resolve("packages/npm/workout-engine");
const keep = process.argv.includes("--keep");
const temporary = await mkdtemp(join(tmpdir(), "caudex-npm-examples-"));
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
  await writeFile(
    join(project, "package.json"),
    JSON.stringify({ private: true, type: "module" }),
  );

  await cp(
    resolve("examples/typescript-node/recommend-and-evaluate.ts"),
    join(project, "node-example.ts"),
  );
  await writeFile(
    join(project, "tsconfig.json"),
    JSON.stringify({
      compilerOptions: {
        strict: true,
        target: "ES2022",
        module: "NodeNext",
        moduleResolution: "NodeNext",
        outDir: "dist-node",
        lib: ["ES2022", "DOM"],
      },
      files: ["node-example.ts"],
    }),
  );
  run(process.execPath, [
    resolve(packageRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  const nodeResult = run(
    process.execPath,
    ["dist-node/node-example.js"],
    project,
    true,
  );
  assertExampleResult(JSON.parse(nodeResult.stdout), "Node");

  const browser = join(project, "browser");
  await cp(resolve("examples/browser"), browser, { recursive: true });
  await mkdir(join(browser, "dist"), { recursive: true });
  await mkdir(join(browser, "wasm"), { recursive: true });
  await cp(
    join(
      project,
      "node_modules/@caudex/workout-engine/wasm/caudex.wasm",
    ),
    join(browser, "wasm/caudex.wasm"),
  );
  const require = createRequire(join(packageRoot, "package.json"));
  const { rollup } = await import(pathToFileURL(require.resolve("rollup")));
  const { nodeResolve } = await import(
    pathToFileURL(require.resolve("@rollup/plugin-node-resolve"))
  );
  const bundle = await rollup({
    input: join(browser, "app.js"),
    plugins: [nodeResolve()],
  });
  await bundle.write({
    file: join(browser, "dist/app.js"),
    format: "esm",
  });
  await bundle.close();

  await writeFile(
    join(project, "browser-node-smoke.mjs"),
    `const output = { textContent: "" };
globalThis.document = {
  body: { dataset: { status: "running" } },
  querySelector(selector) {
    if (selector !== "#output") throw new Error("unexpected selector");
    return output;
  },
};
await import("./browser/dist/app.js");
if (document.body.dataset.status !== "passed") {
  throw new Error(output.textContent);
}
console.log(output.textContent);
`,
  );
  const browserResult = run(
    process.execPath,
    ["browser-node-smoke.mjs"],
    project,
    true,
  );
  assertExampleResult(JSON.parse(browserResult.stdout), "browser");

  console.log("caudex packed Node and browser examples passed");
  if (keep) console.log(`CAUDEX_BROWSER_EXAMPLE=${browser}`);
} finally {
  if (!keep) await rm(temporary, { recursive: true, force: true });
}

function assertExampleResult(result, environment) {
  if (
    result.recommendation?.exerciseId !== "incline-dumbbell-press" ||
    result.recommendation?.explanationCode !==
      "exercise.selected.available_equipment" ||
    result.evaluation?.outcome !== "advanced" ||
    result.evaluation?.explanationCode !==
      "load.increased.rep_range_completed"
  ) {
    throw new Error(
      `${environment} example returned unexpected output: ` +
        JSON.stringify(result),
    );
  }
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
