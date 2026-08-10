# Caudex Workout Engine

`@caudex-workout/engine` v0.1.0 is published to npm. Install the ESM package
on Node.js 22 or newer:

```bash
npm install @caudex-workout/engine
```

For new integrations, bind stable host context once and let the application
facade construct complete canonical requests:

```ts
import { createCaudex, lb, methodologies } from "@caudex-workout/engine";

const caudex = await createCaudex();
const program = caudex.createProgram({
  hostScopeKey: "profile-1",
  catalog,
  methodology: methodologies.presets.hypertrophy({ initialLoad: lb(45) }),
});
const result = program.recommend();
if (!result.ok) throw new Error(result.issues[0].message);
console.log(result.recommendation.exercises);
```

Use `caudex.runtime` or the existing v0.1 top-level methods when you want to
supply complete canonical request snapshots directly. The convenience facade
does not add hidden engine state; clocks and IDs remain injectable.

TypeScript projects should use ESM and NodeNext resolution:

```json
// package.json
{ "type": "module" }
```

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "outDir": "dist"
  }
}
```

The [quickstart and concepts guide](https://github.com/caudex-workout/engine/blob/main/docs/quickstart-and-concepts.md)
shows the complete install-to-result flow, explanation inspection, and host
data ownership model. It requires no database, account, or runtime network
request.

## TypeScript loader and facade

The v0.1 facade is initialized once and accepts ordinary canonical request
objects:

```ts
import {
  createCaudex,
  type RecommendationRequest,
} from "@caudex-workout/engine";

const caudex = await createCaudex();
const result = caudex.recommendSession(request satisfies RecommendationRequest);

if (!result.ok) {
  console.error(result.issues);
}

caudex.dispose();
```

`createCaudex()` hides Node filesystem loading and browser fetch/streaming behind
one asynchronous API. Callers may explicitly supply a `WebAssembly.Module`,
WASM bytes, or a URL when embedding or testing. After initialization,
recommendation calls are synchronous and deterministic.

Canonical validation and unsupported methodology/version failures are returned
as `ok: false` results with structured issues. WASM loading, ABI mismatch,
missing exports, and runtime creation failures throw
`CaudexInitializationError` with a typed `code`. Failures after successful
initialization that prevent safe execution throw `CaudexRuntimeError`.

The deterministic low-level `Caudex` value exposes `recommendSession()`,
`evaluatePerformance()`, `applyTrackingCommand()`, `applyTrackingBatch()`,
`instantiateRecommendation()`, `instantiateTemplate()`,
`completeForEvaluation()`, `exportPortable()`, `validatePortableImport()`, and
`dispose()`. Portable export validates and canonicalizes a public document;
portable import validation returns structured dry-run issues and counts, while
an optional adapter performs durable merge or replace. Tracking and workflow calls require
the complete current snapshot or programming result plus explicit
command IDs, revisions, and timestamps. Accepted and rejected command results
both return the appropriate resulting snapshot, while transport failures throw
`CaudexRuntimeError`. Linear-memory addresses, allocation functions, result
descriptors, and runtime handles remain private to the loader.

The v0.1 npm evaluation boundary supports double progression. Requests for
other methodology implementations return the same structured unsupported
methodology result used by recommendation requests.

## Application tracker and workflows

`createCaudex()` also provides a convenience workflow layer. It uses secure
platform UUIDs and the platform clock by default; deterministic tests and hosts
can inject both. Persistence is optional and structural, so the engine package
does not depend on a database package.

```ts
const caudex = await createCaudex({ persistence, clock, ids });
const recommendation = caudex.workflows.recommend(request);
const workout = await caudex.workflows.startRecommendation(recommendation, {
  catalog: request.catalog,
  scope: { hostScopeKey: "profile-1" },
});

await workout.completeSet({
  membershipId: workout.workout.exercises![0].id,
  setId: workout.workout.exercises![0].sets![0].id,
  actual: [
    { code: "repetitions", value: { amount: "8", unit: "count" } },
    { code: "load", value: { amount: "185", unit: "lb" } },
  ],
});
```

Every mutation saves with the prior workout revision. Adapter conflicts are
allowed to propagate; they are never converted into success or silently
retried. `reloadActiveWorkout()` works within an in-memory instance and uses
the optional persistence capability across reloads. Methodology state is never
accepted automatically: `acceptProposedState()` must be called explicitly and
requires a compare-and-set capability.

Hosts can also call `recommendFromPersistence()` and
`evaluateCompletionFromPersistence()` to assemble canonical requests from
narrow catalog, history, and optional methodology-state loaders. When recovery
and journal/sink capabilities are supplied, recommendation starts and workout
completions write `pending` then `completed` recovery records. The accepted
recommendation ID and workout ID are the respective idempotency keys. This is a
recoverable multi-step protocol, not a claim that unrelated host services share
one transaction; see the repository's workflow-orchestration persistence guide.

## Methodology factories

The package exports typed factories for both first-party configurations:

```ts
import { methodologies } from "@caudex-workout/engine";

const methodology = methodologies.doubleProgression({
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
});
```

`methodologies.rpeTopSetBackoff()` provides autocomplete for the distinct RPE
configuration. Both factories validate exact decimals, ranges, units, policy
values, override resolution, duplicate IDs, and unknown fields. They return a
normalized canonical methodology reference. Invalid configuration throws
`MethodologyConfigError` with structured `methodology.config_invalid` issues.
Factories contain no recommendation or progression calculations.

Runtime discovery is available through `listMethodologies()`,
`describeMethodology()`, `listCapabilities()`,
`validateMethodologyConfiguration()`, and `validateMethodologyState()`.
Descriptors include UI-neutral field types, exact-decimal and unit requirements,
bounds, choices, versions, and schema references. The metadata originates in
the Zig/WASM registry; TypeScript declarations describe its shape without
maintaining a second copy of the values.

The default WASM URL is `../wasm/caudex.wasm` relative to the distributed
JavaScript module. Packaging and final asset placement belong to CWE-063.

## Package artifact

The ESM-only package uses a controlled export map for the main facade,
methodology factories, and named schema files. Its allowlist contains compiled
JavaScript, declarations, the freestanding WASM runtime, schemas, README,
license, and notice. It has no production dependencies, native compilation,
preinstall, install, or postinstall script. CommonJS is not advertised.

Build and inspect the actual tarball with:

```bash
zig build package-npm
```

## Tested compatibility

The package's clean-project smoke test packs the publish artifact, installs that
tarball into a temporary project, and verifies:

- Node.js 22 or newer through the ESM export
- strict TypeScript 5.9 compilation against the published declarations
- browser ESM bundling with Rollup 4.62
- default WASM discovery in both Node.js and a browser
- the canonical request fixture and a structured unsupported-version error
- the controlled package-content allowlist

Run it with:

```bash
zig build test-npm-clean
```

CommonJS `require()` is not exported or supported; use an ESM entry point.
Rollup is the documented browser
bundler for v0.1; other bundlers are not part of the current compatibility
claim.

The package has no runtime dependencies. Its development-only dependencies are
TypeScript (Apache-2.0), used to compile the installed declarations; Rollup
(MIT), used to bundle browser entry points; and Rollup's node-resolution plugin
(MIT), used to resolve the package import in the checked-in browser example.

## Testing utilities

The dependency-free `@caudex-workout/engine/testing` subpath provides
framework-neutral builders, assertions, and bundled canonical fixtures:

```ts
import { createCaudex } from "@caudex-workout/engine";
import {
  assertDeterministic,
  assertExplanationCode,
  buildRecommendationRequest,
  loadCanonicalFixture,
} from "@caudex-workout/engine/testing";

const fixture = await loadCanonicalFixture("recommendation-request");
const caudex = await createCaudex();
try {
  const result = assertDeterministic(
    () => caudex.recommendSession(fixture),
  );
  assertExplanationCode(
    result,
    "exercise.selected.available_equipment",
  );
} finally {
  caudex.dispose();
}

const request = buildRecommendationRequest();
```

Assertions throw `CaudexTestAssertionError` and do not depend on Jest, Vitest,
or another test runner. Builders use fixed explicit timestamps and return
ordinary mutable objects that callers may customize.

The package is published under the `@caudex-workout` namespace. Registry
ownership and publication are maintained outside this repository.
