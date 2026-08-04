export interface TaxonomyRef { sourceValue: string; id: string }
export interface CatalogSourceProvenance { dataset: string; upstreamRepository: string; upstreamCommit: string; upstreamId: string; license: string }
export interface ExerciseCatalogRecord {
  id: string; upstreamId: string; name: string; aliases: readonly string[];
  force: string | null; difficulty: string | null; mechanic: string | null;
  equipment: TaxonomyRef | null; primaryMuscles: readonly TaxonomyRef[];
  secondaryMuscles: readonly TaxonomyRef[]; instructions: readonly string[];
  category: string | null; movementPatterns: readonly string[]; source: CatalogSourceProvenance;
}
export interface ExerciseProjection { id: string; name: string; aliases: string[]; equipmentIds: string[]; movementTags: string[]; muscleContributions: Array<{ muscleId: string; role: "primary" | "secondary" }> }
export interface CatalogDocument { schemaVersion: 1; catalogId: string; version: string; fingerprint: string; recordCount: number; mediaIncluded: false; records: readonly ExerciseCatalogRecord[] }
export interface SearchQuery { text?: string; equipmentId?: string; muscleId?: string; difficulty?: string; category?: string; limit?: number }
export declare const catalog: CatalogDocument;
export declare const records: readonly ExerciseCatalogRecord[];
export declare const version: string;
export declare const fingerprint: string;
export declare function search(query?: SearchQuery): ExerciseCatalogRecord[];
export declare function project(record: ExerciseCatalogRecord): ExerciseProjection;
export declare function mergeCatalog(overrides: readonly ExerciseCatalogRecord[]): ExerciseCatalogRecord[];
