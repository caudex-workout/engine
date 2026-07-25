# ADR-0002: Library-First Product, Stateless Core, and Multi-Ecosystem Distribution

- **Status:** Accepted
- **Date:** 2026-07-20
- **Decision owners:** Caudex Workout Engine maintainers
- **Supersedes:** The tracking-first product scope, SQLite-first MVP, event-journal requirements, and implementation sequence in ADR-0001
- **Preserves:** ADR-0001's functional-core discipline, explicit idiomatic Zig shell, deterministic calculations, C ABI principles, and rejection of generalized functional-programming frameworks

## Context

The original Workout Engine plan treated accurate workout logging and SQLite persistence as the initial product. That direction would produce another workout-tracking engine in a market with many open-source trackers.

The stronger opportunity is a developer library that solves the difficult programming and recommendation problems that fitness applications repeatedly reimplement:

- Representing strength and hypertrophy programming inputs
- Selecting exercises under equipment, time, preference, and recovery constraints
- Applying progression methodologies
- Evaluating completed performance
- Producing the next session or progression proposal
- Explaining why each recommendation was made
- Reproducing the same result across clients, servers, and tests
- Allowing an application to change methodologies without replacing its data layer

The product statement is:

> **Caudex Workout Engine is an open-source, embeddable strength and hypertrophy programming engine that lets fitness applications load different training methodologies and produce deterministic, explainable workout recommendations.**

The primary users are developers, not end users. Developer experience, API stability, package availability, documentation, and integration confidence are therefore product features rather than secondary concerns.

A recommendation engine is also materially easier to distribute than a tracking engine when it does not own persistence. A stateless core can compile to WebAssembly for JavaScript, expose a C ABI for native hosts, and remain directly importable from Zig without requiring every consumer to accept SQLite, migrations, filesystem access, or a particular synchronization model.

## Decision

Caudex Workout Engine will be a **library-first, storage-agnostic, deterministic programming engine**.

The core accepts complete input snapshots supplied by the host and returns recommendations, evaluations, explanations, warnings, and proposed state changes. It does not own user accounts, workout-history persistence, synchronization, or application lifecycle.

```text
Host application
├── Owns users, storage, history, sync, UI, and authorization
├── Loads or constructs methodology configuration
├── Builds a recommendation request
└── Persists any accepted recommendation or state update
              │
              ▼
Language-specific facade
├── TypeScript / JavaScript
├── Zig
├── C
├── Swift
├── Kotlin / Java
└── Future language wrappers
              │
              ▼
Canonical boundary
├── Versioned request/result schemas
├── Stable issue codes
├── Exact decimal measurements
└── Deterministic serialization fixtures
              │
              ▼
Caudex core in Zig
├── Validation
├── Training-history analysis
├── Methodology registry
├── Exercise filtering and ranking
├── Set/rep/load prescription
├── Progression evaluation
└── Explainability trace
```

## Functional-programming discipline

The following statement remains a binding architectural rule:

> Caudex Workout Engine uses functional programming as an architectural discipline rather than adopting a generalized functional-programming abstraction framework. Domain decisions and recommendation calculations are deterministic and effect-free. Application orchestration, allocation, serialization, package loading, and ABI handling use explicit idiomatic Zig.

Specifically:

- Recommendation functions receive all material inputs explicitly.
- No recommendation depends on the wall clock unless an explicit `as_of` value is supplied.
- No recommendation depends on random state unless an explicit seed is supplied.
- Recommendation functions do not read databases, files, environment variables, global mutable state, network resources, or platform APIs.
- Recommendation functions do not persist or automatically apply their own outputs.
- Allocation is explicit and owned by the calling/application layer.
- Ordinary Zig structs, tagged unions, slices, error unions, loops, `switch`, `defer`, and caller-provided buffers are preferred.
- The project does not adopt `zig-cats`, monad/typeclass emulation, generalized collection wrappers, a free-monad effect system, or a runtime dependency-injection framework for v0.x.
- A runtime function table is allowed for the methodology registry because runtime methodology selection is a concrete product requirement.

## Stateless core

The core has no durable user state.

A host supplies:

- Exercise catalog or catalog subset
- Athlete preferences and constraints
- Training history or a precomputed history snapshot
- Current program/methodology state
- Available equipment
- Session constraints
- Optional readiness and recovery inputs
- Explicit methodology identity and configuration
- Explicit `as_of` instant
- Optional deterministic tie-break seed

The core returns:

- Recommended session or progression
- Alternative recommendations when requested
- Proposed next methodology state
- Explainability trace
- Assumptions and warnings
- Validation issues
- Engine and methodology versions
- Input and output fingerprints

The host chooses whether to display, modify, accept, reject, or persist the result.

SQLite and other persistence adapters may be built later as optional convenience packages. They are not dependencies of the core, the npm package, or the methodology API.

## Primary public operations

The stable conceptual operations are:

```text
validateRequest(request)
recommendSession(request)
evaluatePerformance(request)
listMethodologies()
describeMethodology(methodology_id)
validateMethodologyConfig(methodology_id, config)
```

Later operations may include:

```text
recommendProgramRevision(request)
simulate(request)
compareMethodologies(request)
```

The public API should remain small. Convenience helpers may compose these operations without creating separate semantic engines.

## Methodology model

A methodology is an implementation selected by stable ID and semantic version.

Examples:

```text
caudex.double-progression
caudex.linear-progression
caudex.rpe-top-set-backoff
vendor.product-specific-method
```

A methodology owns its interpretation of:

- Progression state
- Candidate selection
- Exercise scoring
- Set and rep prescription
- Load recommendation
- Failure and missed-session policy
- Deload or recovery behavior
- Explanation codes

The engine owns shared primitives:

- Validation
- Exact units and decimal arithmetic
- Catalog access
- Common history summaries
- Deterministic candidate ordering
- Constraint handling
- Result construction
- Stable issue and explanation structures

### v0.x extension strategy

The project will not design a universal methodology DSL before implementing real methodologies.

For v0.x:

1. The Zig core exposes an explicit methodology interface.
2. First-party methodologies are registered at build time.
3. Zig consumers may compile custom methodologies into their own engine build.
4. The official npm/native distributions contain the supported first-party methodology registry.
5. JavaScript methodology factories produce validated configurations for those registered methodologies.

After at least two meaningfully different methodologies are implemented and compared, the project may define a portable Methodology Bundle or intermediate representation. That future format must be justified by actual shared structure rather than speculative abstraction.

This means “load different methodologies” initially means selecting and configuring one of the methodology implementations compiled into the distribution. It does not initially mean loading arbitrary untrusted native plugins into a running process.

## Explainability

Explainability is part of the core contract, not a generated paragraph added by a UI.

Each result includes structured explanation records:

```text
Explanation
- code
- category
- subject_id?
- summary
- evidence[]
- parameters
- methodology_rule_id?
- severity
```

Examples:

```text
exercise.selected.available_equipment
exercise.excluded.user_disliked
exercise.excluded.recovery_constraint
load.increased.rep_range_completed
sets.reduced.available_time
session.shortened.minimum_viable_policy
```

The result may also include:

- Rejected candidate reasons
- Score components when the methodology uses scoring
- Input evidence references
- Assumptions used because data was absent
- Warnings for insufficient or contradictory history

Explanations must be deterministic and machine readable. Human-readable strings are provided for convenience but stable codes are the compatibility contract.

## Determinism

For the same:

- Engine version
- Methodology ID and version
- Methodology configuration
- Canonical request
- Explicit `as_of`
- Explicit seed, when applicable

the engine must produce the same canonical result.

Rules:

- Input collection order must not accidentally influence a result unless order is a documented semantic input.
- Candidate ties use a documented stable ordering or explicit seed.
- Floating-point values are not authoritative cross-language inputs.
- Exact decimal arithmetic and checked conversions are used.
- Every result includes an input fingerprint and result fingerprint.
- Cross-language wrappers run the same conformance fixtures.
- A methodology update that intentionally changes output requires a methodology version change and fixture review.

## Canonical data boundary

The canonical cross-language boundary uses versioned JSON-compatible schemas in v0.x.

Reasons:

- Simple inspection and debugging
- Easy TypeScript types and JSON Schema generation
- Straightforward C ABI and WebAssembly marshalling
- Golden fixtures across languages
- No requirement that every consumer adopt Zig layouts

The typed Zig API does not need to serialize internally. Wrappers may use the canonical message boundary.

A future binary encoding may be added, but it must represent the same canonical model and pass the same conformance suite.

## Distribution strategy

### Tier 1: v0.1

#### npm

Publish a scoped public package, proposed as:

```text
@caudex/workout-engine
```

The exact scope and names must be reserved and verified before announcement.

The npm package contains:

- JavaScript loader
- TypeScript declarations
- WebAssembly core
- First-party methodology factories/configuration types
- JSON Schemas
- Testing helpers
- Source maps where useful
- License and notices

Requirements:

- No native compiler required by consumers
- No `postinstall` compilation
- Browser and Node support through WebAssembly
- Explicitly documented bundler support
- React Native excluded until a tested native wrapper exists
- Public subpath exports only
- Package contents controlled with an allowlist
- Artifact tested from `npm pack`, not only from the monorepo
- Release provenance and automated publishing

#### Zig package

Publish tagged source releases consumable through Zig's build/package system.

The package exposes:

- Typed core API
- Methodology registration API
- First-party methodologies
- Optional C ABI build step
- Tests and examples

#### C artifacts

Publish headers and prebuilt static/shared libraries for supported targets through GitHub Releases. Also document building from source with Zig.

### Tier 2: after the C ABI stabilizes

#### Swift Package Manager

Distribute an XCFramework through a Swift package binary target, with an idiomatic Swift facade.

#### Maven Central

Distribute an Android AAR containing the native library and Kotlin facade. Keep the native surface narrow and avoid leaking C ownership details into application code.

### Later ecosystems

Evaluate based on demand:

- React Native package backed by a native module
- Flutter plugin using the C ABI
- Python wheels on PyPI
- Rust crate wrapping the C ABI or compiling Zig
- NuGet package
- Ruby gem
- Go module wrapper

The project will not claim support for an ecosystem until its install, quickstart, and conformance tests run in CI.

## npm API design

The npm package presents an idiomatic TypeScript facade rather than exposing raw WASM memory.

Example:

```ts
import {
  createCaudex,
  methodologies,
  type RecommendationRequest,
} from "@caudex/workout-engine";

const caudex = await createCaudex();

const methodology = methodologies.doubleProgression({
  repRange: { min: 8, max: 12 },
  workingSets: 3,
  loadIncrement: { amount: "5", unit: "lb" },
});

const request: RecommendationRequest = {
  schemaVersion: 1,
  asOf: "2026-07-20T22:00:00Z",
  methodology,
  athlete: {
    preferences: {
      dislikedExerciseIds: ["barbell-back-squat"],
    },
  },
  session: {
    availableMinutes: 35,
    availableEquipmentIds: ["dumbbell", "adjustable-bench"],
  },
  catalog: exercises,
  history: recentHistory,
  programState: previousState,
};

const result = caudex.recommendSession(request);

console.log(result.recommendation);
console.log(result.explanations);
console.log(result.nextProgramState);
```

API rules:

- Initialization may be asynchronous because WebAssembly loading is asynchronous.
- Recommendation calls are synchronous and deterministic after initialization.
- The wrapper accepts ordinary JavaScript objects.
- TypeScript types and runtime validation describe the same schema.
- Errors caused by bad user input return structured issues rather than throwing.
- Initialization and catastrophic runtime failures may throw typed JavaScript errors.
- The package avoids classes where plain values and a small engine handle are clearer.
- Public types use descriptive names and avoid transport-specific fields.
- Optional data remains optional; the engine reports assumptions instead of inventing certainty.

## Package surface

Prefer one excellent npm package for v0.1 with controlled subpath exports:

```text
@caudex/workout-engine
@caudex/workout-engine/methodologies
@caudex/workout-engine/schema
@caudex/workout-engine/testing
```

Do not fragment every feature into a separate package before there is independent versioning or ownership value.

Possible future packages:

```text
@caudex/exercise-catalog
@caudex/react-native
@caudex/history-sqlite
```

## Developer-experience requirements

Developer experience is a release gate.

Every supported package must provide:

- A copy-paste quickstart that produces a recommendation
- Complete TypeScript or language-native types
- API reference generated from the public surface
- A methodology configuration guide
- Input and result JSON Schemas
- Stable error and explanation code documentation
- At least one realistic sample application
- Migration notes for breaking and deprecated behavior
- Determinism and versioning documentation
- A troubleshooting guide
- A supported-platform matrix
- A minimal reproduction template for bug reports
- Testing utilities and canonical fixtures

The first useful npm recommendation should require:

- One package installation
- No native toolchain
- No database
- No account
- No network request
- No more than roughly thirty lines in the primary quickstart

## Repository strategy

Use one monorepo while the core and official bindings release together:

```text
caudex/
├── build.zig
├── build.zig.zon
├── LICENSE
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── adr/
│   ├── concepts/
│   ├── methodologies/
│   ├── reference/
│   └── guides/
├── core/
│   └── src/
│       ├── root.zig
│       ├── model/
│       ├── validation/
│       ├── history/
│       ├── recommendation/
│       ├── explanation/
│       ├── methodology/
│       └── protocol/
├── methodologies/
│   ├── double_progression/
│   └── rpe_top_set_backoff/
├── bindings/
│   ├── c/
│   ├── wasm/
│   ├── swift/
│   └── android/
├── packages/
│   └── npm/
│       └── workout-engine/
├── schemas/
├── fixtures/
│   ├── requests/
│   ├── results/
│   └── methodology/
├── examples/
│   ├── typescript-node/
│   ├── browser/
│   ├── zig/
│   └── c/
└── tools/
    └── release/
```

Directories are created only when implementation work needs them.

## Compatibility and release policy

The following evolve independently:

- Core semantic version
- Canonical schema version
- C ABI version
- Methodology implementation version
- Methodology configuration schema version
- Language-wrapper version

For v0.x, official wrappers may use lockstep release versions to reduce user confusion.

Every recommendation records:

- Core version
- Schema version
- Methodology ID
- Methodology version
- Methodology configuration version
- Input fingerprint
- Result fingerprint

Methodology changes that alter recommendations must be visible in release notes and golden-fixture diffs.

## Consequences

### Benefits

- Caudex solves a less-saturated developer problem rather than competing as another tracker.
- Host applications keep their existing databases and account models.
- The pure core compiles naturally to WebAssembly.
- npm consumers install one package without Zig, SQLite, or native compilation.
- Native clients can share the same recommendation semantics.
- Methodologies become explicit, versioned, testable products.
- Explainability makes recommendations debuggable and safer to integrate.
- Cross-language conformance becomes practical.
- The first useful release can focus on domain value rather than storage infrastructure.

### Costs

- Hosts must map their data into the canonical request model.
- Large histories may require host-side summarization or pagination into a snapshot.
- A portable third-party methodology format is deferred.
- Official distributions initially include only first-party compiled methodologies.
- The project must maintain wrappers and package pipelines across ecosystems.
- JSON/WASM marshalling adds overhead, though recommendation workloads are not expected to be call-frequency bottlenecks.

### Risks

- The canonical request may become too large or too opinionated.
- “Methodology neutral” may become an excuse for an abstract rule engine.
- Explanation output may expose internal implementation details that later become hard to change.
- Package proliferation may fragment the API.
- The TypeScript facade may drift from the canonical schema.
- Methodology versioning may be overlooked when algorithm behavior changes.

Mitigations include a small public API, generated schemas/types, golden fixtures, package smoke tests, two genuinely different reference methodologies, and delaying a methodology DSL until shared structure is demonstrated.

## Rejected alternatives

### Continue with a tracking-first SQLite engine

Rejected as the core product. Persistence can be an optional adapter, but it should not define the library or prevent easy npm/WASM distribution.

### Rewrite the engine in TypeScript for npm convenience

Rejected. Zig remains the portable deterministic core; TypeScript is the ergonomic facade.

### Expose only a C API and make every ecosystem build its own wrapper

Rejected because package quality and language-native ergonomics are central product features.

### Publish a native Node addon as the only npm implementation

Rejected for v0.1 because it would require platform-specific binaries or compilation. WebAssembly provides a simpler browser-and-Node baseline.

### Design a universal methodology DSL immediately

Rejected. Implement at least two real methodologies first, then extract a portable representation from demonstrated commonality.

### Allow arbitrary runtime native plugins

Rejected for v0.x due to ABI, safety, packaging, and cross-platform complexity.

### Bundle persistence into the npm package

Rejected. It would complicate browser support and force host applications into one storage model.

## References

- Zig 0.16.0 language documentation and WebAssembly support: https://ziglang.org/documentation/0.16.0/
- npm scoped public packages: https://docs.npmjs.com/creating-and-publishing-scoped-public-packages/
- npm package public entry points and `exports`: https://docs.npmjs.com/files/package.json/
- Apple binary frameworks through Swift packages: https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages
- Android libraries and AAR packaging: https://developer.android.com/studio/projects/android-library
- Android guidance for middleware containing JNI libraries: https://developer.android.com/ndk/guides/middleware-vendors
- Maven Central publishing: https://central.sonatype.org/publish/
