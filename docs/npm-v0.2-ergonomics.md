# npm application API, determinism, and v0.1 migration

The normal v0.2 entry point binds stable host context once. It is a facade over
the same deterministic runtime, not an engine-owned profile or mutable workout
program:

```ts
import { createCaudex, lb, methodologies } from "@caudex-workout/engine";

const caudex = await createCaudex({
  clock: { now: () => "2026-08-10T14:00:00Z" },
  ids: { next: (kind) => `${kind}-test-1` },
});
const program = caudex.createProgram({
  hostScopeKey: "profile-1",
  catalog,
  methodology: methodologies.presets.hypertrophy({
    initialLoad: lb(45),
    loadIncrement: lb(5),
  }),
  history: { workouts: [] },
});

const recommendation = program.recommend({
  session: { availableEquipmentIds: ["barbell"] },
});
if (!recommendation.ok) throw new Error(recommendation.issues[0].message);

const workout = await program.startWorkout(recommendation);
const set = workout.workout.exercises?.[0]?.sets?.[0];
if (!set) throw new Error("No set was instantiated");
await workout.completeSet(set.id, { reps: 10, load: lb(65), rpe: "8.5" });

const completed = await workout.complete();
program.appendCompletedWorkout(completed); // explicit authoritative history update
const evaluation = program.evaluate(completed);
if (evaluation.ok && evaluation.nextMethodologyState) {
  await program.acceptState(evaluation); // explicit host acceptance
}
const next = program.recommend();
```

`createProgram` retains the supplied catalog, methodology, scope, accepted
state reference, and a host-controlled history snapshot. Use
`replaceHistory()` or `appendCompletedWorkout()` to update that snapshot
explicitly. Every call still constructs a complete request containing
`schemaVersion`, `asOf`, catalog, methodology, history, and state before calling
WebAssembly. The clock and ID provider are injected at `createCaudex`, so tests
can reproduce requests and tracking commands exactly. Persistence is optional.
Without it, `program.acceptState()` updates only that program facade's retained
accepted-state reference. When supplied, active-workout saves and state
compare-and-set remain explicit host capabilities.

## Measurement helpers

`lb`, `kg`, `reps`, `rpe`, `rir`, `seconds`, and `minutes` create canonical
exact-decimal values or metrics. Strings preserve spelling such as `"185.00"`.
Numbers are accepted only when their normal JavaScript spelling is a bounded,
non-exponential decimal. Invalid values throw `CaudexMeasurementError` with the
machine-readable code `measurement.invalid`.

The double-progression `hypertrophy` preset explicitly chooses 8–12 repetitions,
three sets, advancement after all three sets reach 12, hold-on-partial,
regress-on-failure, and nearest-quantum rounding. Its return value is an ordinary
inspectable canonical methodology reference. Use
`methodologies.doubleProgression({...})` for fully explicit configuration.

## Runtime and canonical layers

Advanced integrators may call `caudex.runtime.recommend(completeRequest)` and
`caudex.runtime.evaluate(completeRequest)`. The `runtime` and `canonical`
subpath exports expose advanced types without making internal files public.
The v0.1 aliases `recommendSession`, `evaluatePerformance`, `workflows`, and all
tracking/discovery/portable methods remain supported.

## v0.1 to v0.2

The old recommendation path constructed one canonical request and called
`caudex.recommendSession(request)`. It remains valid. The v0.2 equivalent moves
stable `catalog`, `methodology`, `history`, and scope into `createProgram`, then
passes only session-varying data to `program.recommend()`.

Old set logging passed `{ membershipId, setId, actual: Metric[] }`. It remains
valid. New code passes `setId` plus `{ reps, load, rpe, rir }`; the active workout
resolves the membership from its current snapshot immediately before applying
the canonical command. Reloaded workouts receive fresh facades, and stale or
non-open sets produce structured `CaudexTrackingRejectedError` issues.

There are no removed or deprecated v0.1 APIs and no canonical, WASM, or C ABI
changes. Result typings are compatibly strengthened into discriminated unions,
so `if (result.ok)` now narrows payload fields without optional chaining.
