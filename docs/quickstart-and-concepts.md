# npm quickstart and concepts

Caudex turns a complete workout snapshot into a deterministic recommendation.
The v0.2 application facade binds stable context once; it still constructs a
complete deterministic snapshot for every runtime call:

```bash
npm install @caudex-workout/engine
```

```ts
import { createCaudex, lb, methodologies } from "@caudex-workout/engine";

const caudex = await createCaudex();
try {
  const program = caudex.createProgram({
    hostScopeKey: "profile-1",
    methodology: methodologies.presets.hypertrophy({
      initialLoad: lb(45),
      loadIncrement: lb(5),
    }),
    catalog: [{
      id: "incline-dumbbell-press",
      equipmentIds: ["dumbbell", "adjustable-bench"],
      movementTags: ["horizontal-push"],
    }],
    history: { workouts: [] },
  });
  const result = program.recommend({
    asOf: "2026-07-25T14:00:00Z",
    session: {
      availableMinutes: 35,
      availableEquipmentIds: ["dumbbell", "adjustable-bench"],
    },
  });
  if (!result.ok) {
    throw new Error(`Request rejected: ${JSON.stringify(result.issues)}`);
  }

  const exercise = result.recommendation.exercises[0];
  const explanation = result.explanations?.[0];
  console.log(exercise?.exerciseId);
  console.log(explanation?.code, explanation?.summary);
} finally {
  caudex.dispose();
}
```

The repository's complete
[TypeScript quickstart](../examples/typescript-node/quickstart.ts) uses the same
flow with a separate sample catalog. `zig build test-docs-quickstart` packs the
real npm artifact, installs it into a clean temporary project, strictly
compiles that example, runs it, and checks its recommendation and explanation.

## Requests are snapshots

A request contains all information material to the calculation:

- the explicit `asOf` instant;
- the methodology configuration and optional current methodology state;
- the exercise catalog relevant to this host and user;
- optional training history, preferences, restrictions, and readiness;
- the current session's time, equipment, and selection constraints.

Caudex does not look up omitted data. It does not read a clock, database,
account, environment variable, or network service to complete a request. Send
the same supported snapshot to the same engine version and methodology version
to reproduce the same result.

Measurements use decimal strings and explicit units, such as
`{ amount: "45", unit: "lb" }`. This avoids treating binary floating-point
values as authoritative training measurements.

## Results are proposals

A successful result contains a recommendation, structured explanations,
metadata fingerprints, and optionally proposed next methodology state. Calling
`recommendSession()` does not accept a workout, mutate the request, or save
anything.

The host application owns:

- user and account records;
- exercise IDs and catalog content;
- workout history;
- methodology configuration and previously accepted state;
- whether a recommendation is displayed, edited, accepted, or rejected;
- persistence and synchronization.

If the host accepts `nextMethodologyState`, it may store that value using its
existing database or state system. A prototype can simply discard it. Caudex
requires no persistence setup in either case.

## Inspect explanations

Explanations are stable, structured records rather than generated coaching
text. A recommended exercise or set may contain `explanationRefs`; these IDs
point into `result.explanations`.

```ts
const explanationsById = new Map(
  result.explanations?.map((explanation) => [explanation.id, explanation]),
);

for (const exercise of result.recommendation?.exercises ?? []) {
  for (const id of exercise.explanationRefs ?? []) {
    const explanation = explanationsById.get(id);
    console.log(explanation?.code, explanation?.evidence);
  }
}
```

Use `code` for application behavior and localization. Treat `summary` as
human-readable diagnostic text, not as a stable machine contract.

## Handle rejection and runtime failure separately

Expected input or methodology problems return `ok: false` with structured
`issues`. Initialization failures, such as an incompatible WASM artifact, throw
`CaudexInitializationError`. Failures that prevent safe execution after
initialization throw `CaudexRuntimeError`.

Dispose the engine when its WASM instance is no longer needed. Disposal releases
engine-owned runtime resources; it does not affect host-owned request or result
objects.
