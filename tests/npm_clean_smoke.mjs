import { spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { canonicalNpmArtifact } from "../tools/release/npm-artifact.mjs";

const packageRoot = resolve("packages/npm/workout-engine");
const contract = "npm clean-consumer packaging";
const fixturePath = resolve("fixtures/requests/recommendation.json");
const packageMetadata = JSON.parse(
  await readFile(join(packageRoot, "package.json"), "utf8"),
);
const expectedArtifactFilename = `caudex-workout-engine-${packageMetadata.version}.tgz`;
const keep = process.argv.includes("--keep");
const suppliedTarballIndex = process.argv.indexOf("--tarball");
const suppliedIntegrityIndex = process.argv.indexOf("--integrity");
const suppliedTarball = suppliedTarballIndex === -1
  ? undefined
  : resolve(process.argv[suppliedTarballIndex + 1]);
const suppliedIntegrity = suppliedIntegrityIndex === -1
  ? undefined
  : process.argv[suppliedIntegrityIndex + 1];
const temporary = await mkdtemp(join(tmpdir(), "caudex npm smoke-"));
const packDirectory = join(temporary, "pack");
const project = join(temporary, "project");
await mkdir(packDirectory);
await mkdir(project);

try {
  let artifactPath = suppliedTarball;
  let artifactIntegrity = suppliedIntegrity;
  if (!artifactPath) {
    const packResult = run("npm", [
      "pack",
      "--json",
      "--ignore-scripts",
      "--pack-destination",
      packDirectory,
      packageRoot,
    ], undefined, "pack engine package");
    const [packManifest] = JSON.parse(packResult.stdout);
    if (packManifest?.filename !== expectedArtifactFilename) {
      throw new Error(
        `${contract}: npm pack produced unexpected artifact filename: ` +
          `${packManifest?.filename ?? "<missing>"}; expected ${expectedArtifactFilename}`,
      );
    }
    if (typeof packManifest.integrity !== "string") {
      throw new Error(`${contract}: npm pack did not report artifact integrity`);
    }
    artifactPath = join(packDirectory, packManifest.filename);
    artifactIntegrity = packManifest.integrity;
  }
  const artifact = await canonicalNpmArtifact(
    artifactPath,
    expectedArtifactFilename,
    artifactIntegrity,
  );
  const consumerPackage = {
    private: true,
    type: "module",
    dependencies: { [packageMetadata.name]: artifact.npmDependencySpec },
  };
  if (
    consumerPackage.dependencies[packageMetadata.name] !== artifact.npmDependencySpec ||
    !isAbsolute(artifact.npmDependencySpec)
  ) {
    throw new Error(`${contract}: generated dependency did not retain the local npm spec`);
  }
  await writeFile(join(project, "package.json"), JSON.stringify(consumerPackage));
  run(
    "npm",
    [
      "install",
      "--ignore-scripts",
      "--no-audit",
      "--no-fund",
      artifact.npmDependencySpec,
    ],
    project,
    "install exact packed artifact",
    artifact,
  );
  const consumerManifest = JSON.parse(
    await readFile(join(project, "package.json"), "utf8"),
  );
  const dependencySpec = consumerManifest.dependencies?.[packageMetadata.name];
  if (
    typeof dependencySpec !== "string" ||
    !dependencySpec.startsWith("file:")
  ) {
    throw new Error(
      `${contract}: npm rewrote the exact artifact dependency ambiguously: ` +
        `${dependencySpec ?? "<missing>"}`,
    );
  }
  const consumerLockfile = JSON.parse(
    await readFile(join(project, "package-lock.json"), "utf8"),
  );
  const lockedPackage = consumerLockfile.packages?.[`node_modules/${packageMetadata.name}`];
  if (typeof lockedPackage?.resolved !== "string" || !lockedPackage.resolved.startsWith("file:")) {
    throw new Error(
      `${contract}: package lock does not retain a local exact-artifact resolution`,
    );
  }
  if (lockedPackage.version !== packageMetadata.version) {
    throw new Error(
      `${contract}: installed artifact version mismatch: ` +
        `${lockedPackage.version ?? "<missing>"}; expected ${packageMetadata.version}`,
    );
  }
  await cp(fixturePath, join(project, "request.json"));

  await writeFile(
    join(project, "node-smoke.mjs"),
    `import { readFile } from "node:fs/promises";
import { createCaudex, lb, methodologies } from "@caudex-workout/engine";
import {} from "@caudex-workout/engine/runtime";
import {} from "@caudex-workout/engine/canonical";
import canonicalSchema from "@caudex-workout/engine/schema/canonical" with { type: "json" };
import discoverySchema from "@caudex-workout/engine/schema/discovery" with { type: "json" };

const request = JSON.parse(await readFile(new URL("./request.json", import.meta.url)));
request.methodology = methodologies.doubleProgression(request.methodology.config);
const caudex = await createCaudex();
const program = caudex.createProgram({
  hostScopeKey: "clean-consumer",
  catalog: request.catalog,
  methodology: methodologies.presets.hypertrophy({ initialLoad: lb(45) }),
});
const ergonomic = program.recommend({ asOf: request.asOf, trainingContext: request.trainingContext });
const result = caudex.recommendSession(request);
const invalid = caudex.recommendSession({ ...request, schemaVersion: 2 });
const discovered = caudex.listMethodologies();
caudex.dispose();
if (!result.ok || result.metadata.resultFingerprint !==
  "acc27989785258bff14df982a222e277e9b51bfed565c363d1f3300277fabe47") {
  throw new Error("npm clean-consumer packaging: canonical tarball fixture failed");
}
if (!ergonomic.ok || ergonomic.recommendation.exercises.length !== 1) {
  throw new Error("npm clean-consumer packaging: application facade failed");
}
if (invalid.ok || invalid.issues?.[0]?.code !== "protocol.unsupported_version") {
  throw new Error("npm clean-consumer packaging: error fixture did not return a structured issue");
}
if (canonicalSchema.$id !== "https://caudex.dev/schemas/v0/canonical.schema.json") {
  throw new Error("npm clean-consumer packaging: schema subpath export failed");
}
if (discoverySchema.$id !== "https://caudex.dev/schemas/discovery/v1/discovery.schema.json" || discovered.methodologies.length !== 2) {
  throw new Error("npm clean-consumer packaging: discovery schema or runtime metadata export failed");
}
`,
  );
  run(process.execPath, ["node-smoke.mjs"], project, "run npm consumer runtime smoke");

  await writeFile(
    join(project, "smoke.ts"),
    `import {
  createCaudex,
  lb,
  methodologies,
  type RecommendationRequest,
  type RecommendationResult,
} from "@caudex-workout/engine";
import type { RuntimeFacade } from "@caudex-workout/engine/runtime";
import type { Measurement } from "@caudex-workout/engine/canonical";

const methodology = methodologies.doubleProgression({
  repRange: { min: 8, max: 12 },
  workingSets: 3,
  advancementCriteria: { minimumSuccessfulSets: 3, minimumRepetitions: 12 },
  initialLoad: { amount: "45", unit: "lb" },
  loadIncrement: { amount: "5", unit: "lb" },
  failurePolicy: {
    onPartial: "hold",
    onFailure: "regress",
    regressionAmount: { amount: "5", unit: "lb" },
  },
  rounding: { mode: "nearest", quantum: { amount: "2.5", unit: "lb" } },
});
async function discover(): Promise<string> {
  const engine = await createCaudex();
  try { return engine.describeMethodology("caudex.double-progression").displayName; }
  finally { engine.dispose(); }
}
void discover;
const request: RecommendationRequest = {
  schemaVersion: 1,
  asOf: "2026-07-25T14:00:00Z",
  methodology,
  catalog: [{ id: "press" }],
};
const check = async (): Promise<RecommendationResult> => {
  const caudex = await createCaudex();
  const result = caudex.recommendSession(request);
  caudex.dispose();
  return result;
};
void check;
const exact: Measurement = lb("45.00");
declare const runtime: RuntimeFacade;
void exact;
void runtime;
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
    resolve(packageRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ], undefined, "typecheck npm consumer project");

  const browser = join(project, "browser");
  await mkdir(join(browser, "dist"), { recursive: true });
  await mkdir(join(browser, "wasm"), { recursive: true });
  await cp(join(project, "request.json"), join(browser, "request.json"));
  await cp(
    join(
      project,
      "node_modules/@caudex-workout/engine/wasm/caudex.wasm",
    ),
    join(browser, "wasm/caudex.wasm"),
  );
  await writeFile(
    join(browser, "app.js"),
    `import { createCaudex } from "../node_modules/@caudex-workout/engine/dist/index.js";
const output = document.querySelector("#output");
try {
  const request = await fetch("/request.json").then((response) => response.json());
  const caudex = await createCaudex();
  const result = caudex.recommendSession(request);
  const invalid = caudex.recommendSession({ ...request, schemaVersion: 2 });
  caudex.dispose();
  if (!result.ok || invalid.ok ||
      invalid.issues?.[0]?.code !== "protocol.unsupported_version") {
    throw new Error("npm clean-consumer packaging: browser canonical/error fixture failed");
  }
  document.body.dataset.status = "passed";
  output.textContent = result.metadata.resultFingerprint;
} catch (error) {
  document.body.dataset.status = "failed";
  output.textContent = String(error?.stack ?? error);
}
`,
  );
  await writeFile(
    join(browser, "index.html"),
    `<!doctype html>
<html><head><meta charset="utf-8"><title>Caudex npm smoke</title></head>
<body data-status="running"><pre id="output">running</pre>
<script type="module" src="/dist/app.js"></script></body></html>
`,
  );
  run(process.execPath, [
    resolve(packageRoot, "node_modules/rollup/dist/bin/rollup"),
    join(browser, "app.js"),
    "--format",
    "esm",
    "--file",
    join(browser, "dist/app.js"),
  ], undefined, "bundle npm browser consumer");

  console.log(
    `${contract}: Node ESM, TypeScript 5.9, ` +
      `Rollup 4.62; artifact ${artifact.artifactPath}; ` +
      `browser fixture ${browser}`,
  );
  if (keep) {
    console.log(`CAUDEX_BROWSER_FIXTURE=${browser}`);
  }
} finally {
  if (!keep) await rm(temporary, { recursive: true, force: true });
}

function run(
  command,
  args,
  cwd = undefined,
  phase = "consumer command",
  artifact = undefined,
) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    timeout: 30_000,
  });
  if (result.status === 0) return result;

  const commandText = [command, ...args].map(shellQuote).join(" ");
  const details = [
    `${contract}: ${phase} failed`,
    `project: ${cwd ?? process.cwd()}`,
    `command: ${commandText}`,
    `exit status: ${result.status ?? "not available"}`,
  ];
  if (result.signal) details.push(`signal: ${result.signal}`);
  if (result.error) details.push(`launcher error: ${result.error.message}`);
  if (artifact !== undefined) {
    details.push("artifact exists:\n  true");
    details.push(`artifact filesystem path:\n  ${artifact.artifactPath}`);
    details.push(`npm spec:\n  ${artifact.npmDependencySpec}`);
    details.push(`artifact file URL (diagnostic only):\n  ${artifact.artifactFileUrl}`);
    details.push(
      "fixture:\n  clean consumer install (Node ESM, TypeScript, Rollup/browser)",
    );
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
    if (output.includes("git ls-remote") || output.includes("github.com")) {
      details.push(
        "invariant violation: npm attempted Git/GitHub resolution for the local release artifact",
      );
    }
  }
  details.push(outputBlock("stdout", result.stdout));
  details.push(outputBlock("stderr", result.stderr));
  throw new Error(details.join("\n"));
}

function shellQuote(value) {
  if (/^[A-Za-z0-9_./:@%+=,-]+$/.test(value)) return value;
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function outputBlock(label, value) {
  const text = value?.trimEnd() ?? "";
  const maximum = 12_000;
  if (text.length === 0) return `${label}: <empty>`;
  if (text.length <= maximum) return `${label}:\n${text}`;
  return `${label}:\n${text.slice(0, maximum)}\n[... ${label} truncated at ${maximum} bytes]`;
}
