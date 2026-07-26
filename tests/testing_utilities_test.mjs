import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const packageRoot = resolve("packages/npm/workout-engine");
const temporary = await mkdtemp(join(tmpdir(), "caudex-testing-utilities-"));
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
    join(project, "testing-smoke.mjs"),
    `import { createCaudex } from "@caudex/workout-engine";
import {
  CaudexTestAssertionError,
  assertDeterministic,
  assertExplanationCode,
  buildCompletedWorkout,
  buildExercise,
  buildRecommendationRequest,
  loadCanonicalFixture,
} from "@caudex/workout-engine/testing";

const caudex = await createCaudex();
try {
  const fixture = await loadCanonicalFixture("recommendation-request");
  const deterministic = assertDeterministic(
    () => caudex.recommendSession(fixture),
    3,
  );
  const explanation = assertExplanationCode(
    deterministic,
    "exercise.selected.available_equipment",
  );
  const request = buildRecommendationRequest({
    catalog: [buildExercise({ id: "custom-exercise" })],
  });
  const workout = buildCompletedWorkout({ id: "custom-workout" });
  let assertionFailed = false;
  try {
    assertExplanationCode(deterministic, "missing.code");
  } catch (error) {
    assertionFailed = error instanceof CaudexTestAssertionError;
  }
  if (
    explanation.code !== "exercise.selected.available_equipment" ||
    request.catalog[0]?.id !== "custom-exercise" ||
    workout.id !== "custom-workout" ||
    !assertionFailed
  ) {
    throw new Error("testing utilities returned unexpected values");
  }
  console.log(deterministic.metadata.resultFingerprint);
} finally {
  caudex.dispose();
}
`,
  );
  await writeFile(
    join(project, "testing-smoke.ts"),
    `import type { RecommendationResult } from "@caudex/workout-engine";
import {
  assertDeterministic,
  assertExplanationCode,
  buildCompletedWorkout,
  buildExercise,
  buildRecommendationRequest,
  loadCanonicalFixture,
} from "@caudex/workout-engine/testing";

const request = buildRecommendationRequest({
  catalog: [buildExercise({ id: "typed-exercise" })],
});
const workout = buildCompletedWorkout();
declare const calculate: () => RecommendationResult;
const result = assertDeterministic(calculate);
assertExplanationCode(result, "exercise.selected.available_equipment");
const fixture = loadCanonicalFixture("recommendation-request");
void [request, workout, fixture];
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
      files: ["testing-smoke.ts"],
    }),
  );
  run(process.execPath, [
    resolve(packageRoot, "node_modules/typescript/bin/tsc"),
    "--project",
    join(project, "tsconfig.json"),
  ]);
  run(process.execPath, ["testing-smoke.mjs"], project);
  console.log("caudex public testing utilities passed");
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
