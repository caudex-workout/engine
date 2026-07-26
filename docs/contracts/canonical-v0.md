# Canonical v0 request and result contract

Status: reviewed design contract for CWE-002. It defines the public shape that
later implementation issues must preserve; it does not implement recommendation
or evaluation behavior.

The authoritative representations are:

- Zig types in `src/canonical.zig`
- JSON Schemas in `schemas/v0/`, with shared definitions in
  `canonical.schema.json`
- Cross-language examples in this document
- Request fixtures in `fixtures/requests/`

## Boundary rules

- `schemaVersion` is `1` for every v0 canonical message.
- JSON field names use lower camel case. Zig names match them to prevent a
  hand-maintained rename layer from drifting.
- Authoritative non-integer measurements, weights, percentages, RPE, and RIR
  use JSON decimal strings. JSON numbers are reserved for inherently integral
  counts, indexes, limits, and schema versions.
- Timestamps are explicit RFC 3339 strings. The engine never supplies an
  implicit current time.
- Methodology configuration and state data are versioned, methodology-owned
  JSON objects. Shared code treats their contents as opaque.
- Unknown fields are rejected by the v0 schemas. Version negotiation is based
  on `schemaVersion`, not permissive guessing.
- IDs and taxonomy codes are host supplied. They carry no database identity or
  storage semantics.
- Results are proposals. `nextMethodologyState` is never implicitly accepted or
  persisted.

## Reviewed TypeScript representation

These types are examples for contract review. A later package issue may
generate equivalent declarations from the canonical source rather than copying
this text.

```ts
type Decimal = string;
type JsonObject = Record<string, unknown>;
type Severity = "info" | "warning" | "error";

interface Measurement {
  amount: Decimal;
  unit: string;
}

interface Metric {
  code: string;
  value: Measurement;
}

interface MethodologyRef {
  id: string;
  versionRequirement?: string;
  configVersion: number;
  config: JsonObject;
}

interface MethodologyState {
  schemaVersion: number;
  data: JsonObject;
}

interface Exercise {
  id: string;
  name?: string;
  equipmentIds?: string[];
  movementTags?: string[];
  muscleContributions?: Array<{
    muscleId: string;
    role: "primary" | "secondary" | "stabilizer" | "custom";
    weight?: Decimal;
  }>;
  unilateral?: boolean;
  aliases?: string[];
  attributes?: JsonObject;
}

interface CompletedSet {
  id?: string;
  kind: string;
  actualMetrics: Metric[];
  targetMetrics?: Metric[];
  completedAt?: string;
  status: "completed" | "partial" | "skipped" | "failed";
}

interface CompletedWorkout {
  id: string;
  startedAt: string;
  completedAt: string;
  exercises: Array<{
    exerciseId: string;
    sets: CompletedSet[];
    tags?: string[];
    notes?: string;
  }>;
}

interface RequestBase {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athlete?: JsonObject;
  history?: {
    workouts?: CompletedWorkout[];
    summaries?: JsonObject;
  };
}

interface RecommendationRequest extends RequestBase {
  session?: JsonObject;
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

interface EvaluationRequest extends RequestBase {
  completedWorkout: CompletedWorkout;
}

interface ValidationIssue {
  code: string;
  path: string;
  message: string;
  severity: Severity;
  parameters?: JsonObject;
  suggestion?: string;
}

interface Explanation {
  id: string;
  code: string;
  category: string;
  summary: string;
  subject?: { exerciseId?: string; setIndex?: number };
  evidence?: Array<{ path: string }>;
  parameters?: JsonObject;
  ruleId?: string;
  severity: Severity;
}

interface ResultMetadata {
  engineVersion: string;
  schemaVersion: 1;
  methodology: {
    id: string;
    version: string;
    configVersion: number;
  };
  inputFingerprint: string;
  resultFingerprint: string;
}

interface ResultBase {
  ok: boolean;
  nextMethodologyState?: MethodologyState;
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  issues?: ValidationIssue[];
  metadata: ResultMetadata;
}

interface RecommendationResult extends ResultBase {
  recommendation?: SessionRecommendation;
  alternatives?: SessionRecommendation[];
}

interface SessionRecommendation {
  title?: string;
  estimatedDuration?: Measurement;
  exercises: Array<{
    exerciseId: string;
    sets: Array<{
      kind: string;
      targetMetrics: Metric[];
      restDuration?: Measurement;
      explanationRefs?: string[];
    }>;
    substitutionGroup?: string;
    explanationRefs?: string[];
  }>;
}

interface EvaluationResult extends ResultBase {
  evaluation?: {
    outcome: string;
    exercises: Array<{
      exerciseId: string;
      outcome: string;
      explanationRefs?: string[];
    }>;
  };
}
```

## Required and optional fields

Requests require the schema version, explicit `asOf`, methodology identity and
configuration, and a non-empty catalog because those values determine the
meaning and reproducibility of a calculation. Evaluation additionally requires
the completed workout being evaluated.

Methodology state is optional because methodologies must define initial-state
behavior. Athlete inputs, history, and session constraints are optional because
a methodology may safely operate without them or return a structured issue when
it requires missing data. Optional collection fields have empty-array semantics.
`versionRequirement` is optional so a host can request the installed default;
the exact resolved version is always recorded in result metadata.

Results require `ok` and metadata for both accepted and rejected calculations.
The recommendation or evaluation payload is optional because expected
validation rejection is a result value. Issues, warnings, explanations, and
alternatives are optional at the JSON boundary and mean empty collections when
absent. Proposed next state is optional because a calculation need not advance
methodology state.

Human-readable messages and summaries are present for immediate usability, but
codes and parameters are the compatibility surface. Their namespaces,
compatibility, path, severity, and localization rules are defined in
[`issues-and-explanations.md`](issues-and-explanations.md).

## Deliberate exclusions

The contract contains no user account, authorization, database key, repository,
revision, transaction, synchronization, UI, device, or acceptance-status field.
Hosts may correlate canonical IDs with their own data, but storage and
application lifecycle remain outside the core.

First-party methodology configuration and state remain methodology-owned rather
than shared canonical definitions. Double progression v1 is defined in
[`double-progression-v1.md`](../methodologies/double-progression-v1.md), and RPE
top-set/backoff v1 is defined in
[`rpe-top-set-backoff-v1.md`](../methodologies/rpe-top-set-backoff-v1.md).
Each has dedicated configuration and state schemas. Other methodology contracts
are added by their corresponding implementation issues. This contract does not
define parsing limits or wire encoding behavior, which belong to CWE-050.
