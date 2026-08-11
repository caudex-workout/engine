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
  athleteProfile?: AthleteProfile;
  history?: {
    workouts?: CompletedWorkout[];
    summaries?: JsonObject;
  };
}

interface RecommendationRequest extends RequestBase {
  trainingContext?: TrainingContext;
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
behavior. Athlete profiles, history, and training context are optional because
a methodology may safely operate without them or return a structured issue when
it requires missing data. Optional collection fields have empty-array semantics.
`versionRequirement` is optional so a host can request the installed default;
the exact resolved version is always recorded in result metadata.

`AthleteProfile` is persistent explicit intent; `TrainingContext` contains only
facts for this recommendation. When a profile is supplied, the runtime resolves
location equipment and session deltas and snapshots the decision-relevant
`resolvedTrainingContext` in the recommendation. Its profile ID, programming
revision, and fingerprint are provenance, not account/authentication identity.
The normative field and precedence semantics are documented in
[`../athlete-profiles-and-training-context.md`](../athlete-profiles-and-training-context.md).

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

## JSON processing rules and limits

The Zig canonical JSON API decodes recommendation requests, evaluation
requests, recommendation results, and evaluation results into allocator-owned
documents. Callers must release each successfully decoded document. Encoding
writes to caller-owned storage and reports an output-limit error rather than
allocating implicitly.

Protocol schema version `1` is the only accepted root request version and
result metadata schema version. Unknown and duplicate fields in typed canonical
objects are rejected. Methodology config/state and explicitly open extension
values remain methodology- or host-owned JSON and are not treated as canonical
struct fields.

Default decode limits are:

- 1 MiB input
- 32 object/array nesting levels
- 4,096 structural collection entries across the document
- 64 KiB for an individual string or number token

Hosts may select stricter or larger explicit limits. Invalid UTF-8, malformed
JSON, exceeded limits, and unsupported versions are distinct failures.

Measurements and canonical weights use canonical base-10 decimal strings.
Known decimal configuration fields such as target RPE, percentage, tolerance,
and estimate adjustment percentage are validated the same way. JSON numbers,
leading-zero forms, explicit plus signs, and values beyond supported decimal
precision or range are rejected at these decimal boundaries.

Encoding follows canonical struct declaration order, omits null optional
fields, preserves array order, and emits compact JSON. Re-encoding the same
typed value is byte deterministic. Maps inside explicitly open JSON values
retain their supplied order; callers requiring a cross-producer fingerprint
must use the protocol fingerprint rules rather than assuming arbitrary map
insertion order is canonical.

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
