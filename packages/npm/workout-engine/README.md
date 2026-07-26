# TypeScript loader and facade

The v0.1 facade is initialized once and accepts ordinary canonical request
objects:

```ts
import {
  createCaudex,
  type RecommendationRequest,
} from "@caudex/workout-engine";

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

The public `Caudex` value exposes only `recommendSession()` and `dispose()`.
Linear-memory addresses, allocation functions, result descriptors, and runtime
handles remain private to the loader.

## Methodology factories

The package exports typed factories for both first-party configurations:

```ts
import { methodologies } from "@caudex/workout-engine";

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

CommonJS is not exported or supported. Rollup is the documented browser
bundler for v0.1; other bundlers are not part of the current compatibility
claim.

The package has no runtime dependencies. Its development-only dependencies are
TypeScript (Apache-2.0), used to compile the installed declarations, and Rollup
(MIT), used to bundle the installed browser entry point.

On 2026-07-26, a read-only lookup of `@caudex/workout-engine` against the public
npm registry returned `E404`, meaning no published package currently claims
that full name. Publication still requires the maintainer to create or control
the `@caudex` organization; this repository does not infer registry ownership
from name availability.
