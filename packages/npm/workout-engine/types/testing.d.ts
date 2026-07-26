import type {
  CompletedWorkout,
  Exercise,
  Explanation,
  JsonValue,
  RecommendationRequest,
  RecommendationResult,
} from "./index.js";

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
export declare class CaudexTestAssertionError extends Error {
  constructor(message: string);
}
export declare function buildExercise(
  overrides?: Partial<Exercise>,
): Exercise;
export declare function buildCompletedWorkout(
  overrides?: Partial<CompletedWorkout>,
): CompletedWorkout;
export declare function buildRecommendationRequest(
  overrides?: Partial<RecommendationRequest>,
): RecommendationRequest;
export declare function assertDeterministic(
  calculate: () => RecommendationResult,
  repetitions?: number,
): RecommendationResult;
export declare function assertExplanationCode(
  result: RecommendationResult,
  expectedCode: string,
): Explanation;
export declare function loadCanonicalFixture<
  Name extends CanonicalFixtureName,
>(
  name: Name,
  options?: LoadCanonicalFixtureOptions,
): Promise<CanonicalFixtureMap[Name]>;

