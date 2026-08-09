# Caudex Workout Engine

[![Required CI](https://github.com/caudex-workout/engine/actions/workflows/ci.yml/badge.svg)](https://github.com/caudex-workout/engine/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Current contract line: **0.1.0** · supported Zig: **0.16.x**

> Public release status: no npm package, Zig tag, or native C release bundle is
> currently published. The v0.1.0 artifacts are staged and validated locally;
> the consumer commands below become network-installable only after a release
> is deliberately published.

Caudex is an open-source, embeddable strength and hypertrophy programming
engine for developers. It accepts complete host-owned snapshots and returns
deterministic recommendations, evaluations, structured explanations, and
proposed methodology state. The core is stateless, persistence-independent,
and designed for Zig, C, and npm/WebAssembly consumers.

It is not a hosted fitness service, account system, synchronization layer,
medical coach, or required database. Hosts own users, UI, history, persistence,
and whether a proposal is accepted or stored.

## Choose your path

- [npm/TypeScript and browser usage](#npm-quickstart)
- [Zig package integration](#zig-package)
- [C integration and release artifacts](docs/release/c.md)
- [CLI and TUI reference client](apps/caudex-cli/README.md)
- [Browser playground](examples/browser/README.md)
- [Architecture and contracts](#architecture)
- [Contributor setup and checks](CONTRIBUTING.md)

## npm quickstart

For a future public release, install the package into a Node.js 22 or newer
project:

```bash
npm install @caudex-workout/engine
```

TypeScript projects should opt into ESM and NodeNext resolution:

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

Optional npm packages use the same namespace:
`@caudex-workout/persistence`, `@caudex-workout/persistence-indexeddb`, and
`@caudex-workout/exercise-catalog`. Earlier unpublished `@caudex/persistence*`
names are not retained as aliases.

Then create an engine, supply a complete request snapshot, and inspect the
result:

```ts
import {
  createCaudex,
  methodologies,
  type RecommendationRequest,
} from "@caudex-workout/engine";

const sampleCatalog = [{
  id: "incline-dumbbell-press",
  name: "Incline Dumbbell Press",
  equipmentIds: ["dumbbell", "adjustable-bench"],
  movementTags: ["horizontal-push"],
  muscleContributions: [
    { muscleId: "pectoralis-major", role: "primary" as const },
    { muscleId: "triceps", role: "secondary" as const },
  ],
}];

const caudex = await createCaudex();
const methodology = methodologies.doubleProgression({
  repRange: { min: 8, max: 12 },
  workingSets: 3,
  advancementCriteria: { minimumSuccessfulSets: 3, minimumRepetitions: 12 },
  initialLoad: { amount: "45", unit: "lb" },
  loadIncrement: { amount: "5", unit: "lb" },
  failurePolicy: { onPartial: "hold", onFailure: "regress", regressionAmount: { amount: "5", unit: "lb" } },
  rounding: { mode: "nearest", quantum: { amount: "2.5", unit: "lb" } },
});

const request: RecommendationRequest = {
  schemaVersion: 1,
  asOf: "2026-07-25T14:00:00Z",
  methodology,
  catalog: sampleCatalog,
  history: { workouts: [] },
  session: {
    availableMinutes: 35,
    availableEquipmentIds: ["dumbbell", "adjustable-bench"],
  },
};

const result = caudex.recommendSession(request);
if (!result.ok) {
  throw new Error(`Request rejected: ${JSON.stringify(result.issues)}`);
} else {
  const exercise = result.recommendation?.exercises[0];
  const explanation = result.explanations?.[0];
  console.log(exercise?.exerciseId);
  console.log(explanation?.code, explanation?.summary);
}

caudex.dispose();
```

This produces an `incline-dumbbell-press` recommendation and a structured
`exercise.selected.available_equipment` explanation. The complete example is
[`examples/typescript-node/quickstart.ts`](examples/typescript-node/quickstart.ts).
It is compiled and executed against the packed npm artifact by
`zig build test-docs-quickstart`.

The package is not yet published to the public npm registry. To validate the
same flow locally from this checkout, run `zig build package-npm`, then pack
`packages/npm/workout-engine` with `npm pack` and install the resulting tarball
into a separate consumer project. Do not interpret that local tarball as a
published package.

## Zig package

After a public tag exists, direct Zig consumers can add its source archive with `zig fetch --save`
and import `@import("caudex")` plus the optional database-independent
`@import("caudex_persistence")` and host-owned `@import("caudex_tracking")`
contracts, plus the optional `@import("caudex_sqlite")` adapter. The
optional `@import("caudex_exercise_catalog")` module supplies the pinned
first-party textual catalog without making it a core dependency. npm hosts can
install the equivalent `@caudex-workout/exercise-catalog` package. The
[Zig package guide](docs/zig-package.md) documents dependency wiring, public
modules, persistence ownership/error/compatibility semantics, the Zig 0.16.x
support policy, and the checked-in consumer. `zig build test-zig-package`
verifies both named imports from a clean copy containing only the source
package's declared paths.

The first-party [`caudex` CLI guide](apps/caudex-cli/README.md) covers the
GitHub Release installation path, first workout, JSON and shell
automation, database backup/restore, exit codes, TUI keybindings, and
troubleshooting. Third-party Zig applications should start with the
[Zig integrator guide](docs/zig-integrator-guide.md), which uses public
packages without copying CLI or TUI presentation logic.

Native C consumers can use the prebuilt static or shared libraries documented
in the [C release matrix](docs/release/c.md). Every target bundle includes the
public header, license notices, build metadata, SHA-256 checksums, and measured
artifact sizes.

Release compatibility, migration rules, and completed security/license reviews
are indexed in the [v0.1.0 release record](docs/release/v0.1.0.md).

Maintainers should use the single [release guide](docs/releasing.md) for
rehearsals and future tagged releases; the first public release has not been
performed.

See the [quickstart and concepts guide](docs/quickstart-and-concepts.md) for the
request/result model, explanation references, data ownership, deterministic
inputs, and error handling. No database, account, or runtime network request is
required.

The [methodology guides](docs/methodologies/README.md) compare the two
first-party approaches and document their configuration, state, explanation
codes, and limitations.

The [data-mapping guide](docs/data-mapping.md) shows how existing applications
map catalogs and workout records, preserve host IDs, handle missing fields, and
explicitly accept or reject proposed methodology state.

Framework-neutral builders, determinism checks, explanation assertions, and
canonical fixture loading are available from
`@caudex-workout/engine/testing`.

The checked-in [Node](examples/typescript-node/recommend-and-evaluate.ts)
example demonstrates recommendation and completed-performance evaluation. The
static [browser playground](examples/browser/README.md) consumes the packed
public API and lets developers edit requests, switch methodologies, inspect
explanations, and export fixtures without a backend.

Caudex Workout Engine is an open-source, embeddable exercise-programming and
active-workout tracking SDK for developers. Applications supply explicit
snapshots and commands; Caudex returns deterministic recommendations,
performance evaluations, tracking transitions, explanations, and proposed
methodology state.

Caudex's pure core is stateless even when calculating active-workout
transitions. It is not a hosted fitness platform. The host owns users, UI,
persistence, synchronization, and whether a proposal is accepted or stored.
The core does not require SQLite or any other database.

The first-party `caudex-cli` reference client lives under `apps/caudex-cli`. It
remains architecturally external to the engine: it consumes intentionally
public engine and SQLite-adapter packages and does not import private modules
or mutate adapter tables directly. The [reference-client implementation
plan](docs/implementation-plan.md) records its command, persistence, TUI, and
release boundaries.

## v0.1 scope

The initial release targets Zig 0.16.0 and includes:

- A stateless Zig core with exact decimal measurements and checked arithmetic
- Explicit methodology selection and deterministic recommendation behavior
- Double-progression and RPE top-set/backoff methodologies
- Session recommendation and completed-performance evaluation
- Structured validation issues, explanations, and proposed next state
- Typed Zig and C APIs
- An npm/WebAssembly package with Node and browser examples
- Canonical schemas and cross-language conformance fixtures
- A pure Zig active-workout lifecycle with explicit revisions and replay

The engine itself does not include required persistence, user accounts, sync, a
hosted API, full periodization, cardio programming, arbitrary runtime plugins,
or medical/AI coaching. The reference CLI/TUI is an optional application and
does not change the pure engine's stateless scope.

## Architecture

Caudex uses a functional core with an explicit idiomatic Zig shell. Domain and
methodology calculations receive all material inputs explicitly and perform no
I/O, persistence, clock reads, or hidden randomness. Optional adapters and host
applications depend on the core; the core never depends on them.

The architecture and implementation sequence are defined by:

- [ADR-0001: Functional Core, Explicit Zig Shell, and Adapter Architecture](docs/adr/ADR-0001-workout-engine-core-architecture.md)
- [ADR-0002: Library-First Product, Stateless Core, and Multi-Ecosystem Distribution](docs/adr/ADR-0002-library-first-product-and-distribution.md)
- [ADR-0003: Persistence Is an Optional Adapter Outside the Core](docs/adr/ADR-0003-persistence-as-optional-adapter.md)
- [ADR-0004: First-Party Zig Reference Client in the Workout Engine Monorepo](docs/adr/ADR-0004-first-party-zig-reference-client.md)
- [ADR-0006: Programming and Active-Workout Tracking SDK](docs/adr/ADR-0006-programming-and-active-tracking-sdk.md)
- [Active reference-client implementation plan](docs/implementation-plan.md)
- [Programming and active-tracking SDK implementation plan](docs/implementation-plans/programming-tracking-sdk.md)
- [Canonical tracking protocol v1](docs/contracts/tracking-v1.md)
- [Canonical workflow protocol v1](docs/contracts/workflows-v1.md)
- [Programming, tracking, and template workflows](docs/tracking/workflows-and-templates.md)
- [C ABI v2](docs/contracts/c-abi-v2.md)
- [WebAssembly runtime v2](docs/contracts/wasm-v2.md)
- [Completed v0.1 implementation plan](docs/implementation-plans/completed/v0.1-library-first-implementation-plan.md)

ADR-0002 supersedes ADR-0001's tracking-first and SQLite-first product
decisions. ADR-0003 makes persistence permanently optional and outside the core.
ADR-0001 remains authoritative for the functional-programming discipline and
explicit Zig boundary design.

Engine v0.1 and the reference-client tracking lifecycle are implemented. The
active SDK plan records the remaining cross-language tracking and workflow work.
