import { readFile } from "node:fs/promises";
import {
  MethodologyConfigError,
  createCaudex,
  methodologies,
  type DoubleProgressionConfig,
  type RecommendationRequest,
  type RpeTopSetBackoffConfig,
} from "../packages/npm/workout-engine/src/index.ts";

const [wasmPath, requestPath, doubleConfigPath, rpeConfigPath] =
  process.argv.slice(2);
if (!wasmPath || !requestPath || !doubleConfigPath || !rpeConfigPath) {
  throw new Error("missing methodology factory test paths");
}

const doubleConfig = JSON.parse(
  await readFile(doubleConfigPath, "utf8"),
) as DoubleProgressionConfig;
const rpeConfig = JSON.parse(
  await readFile(rpeConfigPath, "utf8"),
) as RpeTopSetBackoffConfig;

const doubleMethodology = methodologies.doubleProgression(doubleConfig);
if (
  doubleMethodology.id !== "caudex.double-progression" ||
  doubleMethodology.versionRequirement !== "^0.1.0" ||
  doubleMethodology.configVersion !== 1 ||
  JSON.stringify(doubleMethodology.config) !== JSON.stringify(doubleConfig)
) {
  throw new Error("double-progression factory returned the wrong reference");
}
const rpeMethodology = methodologies.rpeTopSetBackoff(rpeConfig);
if (
  rpeMethodology.id !== "caudex.rpe-top-set-backoff" ||
  rpeMethodology.versionRequirement !== "^0.1.0" ||
  rpeMethodology.configVersion !== 1 ||
  JSON.stringify(rpeMethodology.config) !== JSON.stringify(rpeConfig)
) {
  throw new Error("RPE factory returned the wrong reference");
}

const invalidDouble = {
  ...doubleConfig,
  workingSets: 0,
  loadIncrement: { amount: "0", unit: "kg" },
  exerciseOverrides: [
    { exerciseId: "squat" },
    { exerciseId: "squat" },
  ],
} as DoubleProgressionConfig;
expectConfigIssues(
  () => methodologies.doubleProgression(invalidDouble),
  3,
);

const invalidRpe = {
  ...rpeConfig,
  targetRpe: "10.5",
  backoff: { ...rpeConfig.backoff, percentage: "0", setCount: 0 },
  rounding: {
    ...rpeConfig.rounding,
    quantum: { amount: "2.5", unit: "kg" },
  },
} as RpeTopSetBackoffConfig;
expectConfigIssues(() => methodologies.rpeTopSetBackoff(invalidRpe), 4);

const request = JSON.parse(
  await readFile(requestPath, "utf8"),
) as RecommendationRequest;
request.methodology = methodologies.doubleProgression(
  request.methodology.config as unknown as DoubleProgressionConfig,
);
const caudex = await createCaudex({ wasm: await readFile(wasmPath) });
const result = caudex.recommendSession(request);
caudex.dispose();
if (!result.ok) {
  throw new Error("factory output was not accepted by the canonical runtime");
}

console.log("caudex methodology factories validated both v1 configurations");

function expectConfigIssues(factory: () => unknown, minimum: number): void {
  try {
    factory();
    throw new Error("invalid methodology config was accepted");
  } catch (error) {
    if (!(error instanceof MethodologyConfigError)) throw error;
    if (error.issues.length < minimum) {
      throw new Error(
        `expected at least ${minimum} issues, received ${error.issues.length}`,
      );
    }
    if (
      error.issues.some(
        (issue) =>
          issue.code !== "methodology.config_invalid" ||
          issue.severity !== "error",
      )
    ) {
      throw new Error("factory issues do not match runtime conventions");
    }
  }
}
