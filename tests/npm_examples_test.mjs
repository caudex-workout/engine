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
    `class Element {
  constructor(tagName = "div") {
    this.tagName = tagName;
    this.textContent = "";
    this.value = "";
    this.className = "";
    this.children = [];
    this.listeners = {};
    this.dataset = {};
  }
  addEventListener(type, listener) { this.listeners[type] = listener; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  click() { this.listeners.click?.(); this.clicked = true; }
}
const ids = [
  "request-editor", "methodology", "run-request", "copy-fixture",
  "download-fixture", "action-status", "result-status", "result-summary",
  "explanations", "explanation-count", "output",
];
const elements = Object.fromEntries(ids.map((id) => [id, new Element()]));
elements.methodology.value = "double-progression";
let clipboardText = "";
let downloaded = "";
globalThis.document = {
  body: { dataset: { status: "loading" } },
  querySelector(selector) {
    const element = elements[selector.slice(1)];
    if (!element) throw new Error("unexpected selector: " + selector);
    return element;
  },
  createElement(tagName) {
    const element = new Element(tagName);
    if (tagName === "a") {
      element.click = () => { downloaded = element.download; };
    }
    return element;
  },
};
Object.defineProperty(globalThis, "navigator", {
  value: {
    clipboard: { async writeText(value) { clipboardText = value; } },
  },
  configurable: true,
});
URL.createObjectURL = () => "blob:fixture";
URL.revokeObjectURL = () => {};
await import("./browser/dist/app.js");
if (document.body.dataset.status !== "passed") {
  throw new Error(elements.output.textContent);
}
const initial = JSON.parse(elements.output.textContent);
if (
  initial.recommendation?.exercises?.[0]?.exerciseId !==
    "incline-dumbbell-press" ||
  elements.explanations.children.length === 0
) {
  throw new Error("playground did not render its recommendation and explanations");
}
elements.methodology.value = "rpe-top-set-backoff";
elements.methodology.listeners.change();
elements["run-request"].click();
const switched = JSON.parse(elements.output.textContent);
const editedRequest = JSON.parse(elements["request-editor"].value);
if (
  document.body.dataset.status !== "passed" ||
  editedRequest.methodology.id !== "caudex.rpe-top-set-backoff" ||
  switched.metadata?.methodology?.id !== "caudex.rpe-top-set-backoff" ||
  switched.recommendation?.exercises?.[0]?.sets?.[0]?.kind !== "top"
) {
  throw new Error("methodology selector did not execute the RPE request: " +
    JSON.stringify({
      status: document.body.dataset.status,
      request: editedRequest.methodology,
      result: switched,
    }));
}
await elements["copy-fixture"].listeners.click();
elements["download-fixture"].click();
if (
  clipboardText !== elements["request-editor"].value ||
  downloaded !== "caudex-rpe-top-set-backoff-request.json"
) {
  throw new Error("fixture copy/download controls failed");
}
console.log(JSON.stringify({
  recommendation: {
    exerciseId: initial.recommendation.exercises[0].exerciseId,
    explanationCode: initial.explanations[0].code,
  },
  playground: {
    selectedMethodology: editedRequest.methodology.id,
    selectedResultCode: switched.explanations[1].code,
    explanationCount: elements.explanations.children.length,
    copied: true,
    downloaded,
  },
}));
`,
  );
  const browserResult = run(
    process.execPath,
    ["browser-node-smoke.mjs"],
    project,
    true,
  );
  assertPlaygroundResult(JSON.parse(browserResult.stdout));

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

function assertPlaygroundResult(result) {
  if (
    result.recommendation?.exerciseId !== "incline-dumbbell-press" ||
    result.recommendation?.explanationCode !==
      "exercise.selected.available_equipment" ||
    result.playground?.selectedMethodology !==
      "caudex.rpe-top-set-backoff" ||
    result.playground?.selectedResultCode !==
      "load.selected.initial_estimated_one_rep_max" ||
    result.playground?.copied !== true ||
    result.playground?.downloaded !==
      "caudex-rpe-top-set-backoff-request.json"
  ) {
    throw new Error(
      "browser playground returned unexpected output: " +
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
