import type {
  CompletedWorkout,
  Exercise,
  Explanation,
  JsonValue,
  RecommendationRequest,
  RecommendationResult,
} from "./index.ts";

export interface CanonicalFixtureMap {
  "recommendation-request": RecommendationRequest;
  "evaluation-request": JsonValue;
  "recommendation-result": RecommendationResult;
  diagnostics: JsonValue;
}

export type CanonicalFixtureName = keyof CanonicalFixtureMap;

export interface LoadCanonicalFixtureOptions {
  fetch?: typeof globalThis.fetch;
}

export class CaudexTestAssertionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CaudexTestAssertionError";
  }
}

export function buildExercise(overrides: Partial<Exercise> = {}): Exercise {
  return {
    id: "exercise-1",
    name: "Test Exercise",
    equipmentIds: ["test-equipment"],
    ...overrides,
  };
}

export function buildCompletedWorkout(
  overrides: Partial<CompletedWorkout> = {},
): CompletedWorkout {
  return {
    id: "workout-1",
    startedAt: "2026-01-01T12:00:00Z",
    completedAt: "2026-01-01T12:30:00Z",
    exercises: [],
    ...overrides,
  };
}

export function buildRecommendationRequest(
  overrides: Partial<RecommendationRequest> = {},
): RecommendationRequest {
  return {
    schemaVersion: 1,
    asOf: "2026-01-01T12:00:00Z",
    methodology: {
      id: "caudex.double-progression",
      versionRequirement: "^0.1.0",
      configVersion: 1,
      config: {
        repRange: { min: 8, max: 12 },
        workingSets: 3,
        advancementCriteria: {
          minimumSuccessfulSets: 3,
          minimumRepetitions: 12,
        },
        initialLoad: { amount: "45", unit: "lb" },
        loadIncrement: { amount: "5", unit: "lb" },
        failurePolicy: {
          onPartial: "hold",
          onFailure: "regress",
          regressionAmount: { amount: "5", unit: "lb" },
        },
        rounding: {
          mode: "nearest",
          quantum: { amount: "2.5", unit: "lb" },
        },
      },
    },
    catalog: [buildExercise()],
    history: { workouts: [] },
    session: { availableEquipmentIds: ["test-equipment"] },
    ...overrides,
  };
}

export function assertDeterministic(
  calculate: () => RecommendationResult,
  repetitions = 2,
): RecommendationResult {
  if (!Number.isSafeInteger(repetitions) || repetitions < 2) {
    throw new RangeError("repetitions must be a safe integer of at least 2");
  }

  const baseline = calculate();
  const serialized = JSON.stringify(baseline);
  for (let index = 1; index < repetitions; index += 1) {
    const candidate = calculate();
    if (
      candidate.metadata.resultFingerprint !==
        baseline.metadata.resultFingerprint ||
      JSON.stringify(candidate) !== serialized
    ) {
      throw new CaudexTestAssertionError(
        `Caudex result changed between deterministic run 1 and run ${index + 1}.`,
      );
    }
  }
  return baseline;
}

export function assertExplanationCode(
  result: RecommendationResult,
  expectedCode: string,
): Explanation {
  const explanation = result.explanations?.find(
    (candidate) => candidate.code === expectedCode,
  );
  if (!explanation) {
    const actual = result.explanations?.map(({ code }) => code) ?? [];
    throw new CaudexTestAssertionError(
      `Expected explanation code "${expectedCode}"; received ${JSON.stringify(actual)}.`,
    );
  }
  return explanation;
}

export async function loadCanonicalFixture<
  Name extends CanonicalFixtureName,
>(
  name: Name,
  options: LoadCanonicalFixtureOptions = {},
): Promise<CanonicalFixtureMap[Name]> {
  const relativePath = FIXTURE_PATHS[name];
  if (!relativePath) {
    throw new TypeError(`Unknown canonical fixture "${String(name)}".`);
  }
  const url = new URL(relativePath, import.meta.url);
  let source: string;
  if (url.protocol === "file:" && isNode()) {
    const dynamicImport = new Function(
      "specifier",
      "return import(specifier)",
    ) as (specifier: string) => Promise<{
      readFile(url: URL, encoding: "utf8"): Promise<string>;
    }>;
    const { readFile } = await dynamicImport("node:fs/promises");
    source = await readFile(url, "utf8");
  } else {
    const fetchImplementation = options.fetch ?? globalThis.fetch;
    if (!fetchImplementation) {
      throw new Error(`No fetch implementation can load fixture ${name}.`);
    }
    const response = await fetchImplementation(url);
    if (!response.ok) {
      throw new Error(
        `Canonical fixture ${name} returned HTTP ${response.status}.`,
      );
    }
    source = await response.text();
  }
  return JSON.parse(source) as CanonicalFixtureMap[Name];
}

const FIXTURE_PATHS: Record<CanonicalFixtureName, string> = {
  "recommendation-request": "../fixtures/requests/recommendation.json",
  "evaluation-request": "../fixtures/requests/evaluation.json",
  "recommendation-result":
    "../fixtures/results/recommendation-no-history.json",
  diagnostics: "../fixtures/results/diagnostics.json",
};

function isNode(): boolean {
  return Boolean(
    (globalThis as { process?: { versions?: { node?: string } } }).process
      ?.versions?.node,
  );
}

