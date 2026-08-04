# ADR-0006: Programming and Active-Workout Tracking SDK

- **Status:** Accepted
- **Date:** 2026-08-04
- **Decision owners:** Caudex Workout Engine maintainers
- **Supersedes:** ADR-0002's programming-only product scope and statements that
  active tracking is outside the intended library product
- **Preserves:** ADR-0001's functional-core and C ABI principles, ADR-0002's
  library-first distribution, and ADR-0003's optional-persistence boundary

## Context

Caudex now contains a public deterministic Zig tracking lifecycle, persistence
capabilities, SQLite tracking migrations, and first-party CLI/TUI workflows.
The architecture documents still describe Caudex only as a programming engine.
That description no longer matches the product or implementation.

Developers need both exercise-programming decisions and the active-workout
lifecycle that collects the performance those decisions are evaluated against.
These capabilities remain portable only when domain rules are deterministic and
independent of storage and UI.

## Decision

Caudex is a developer-first exercise-programming and active-workout tracking
SDK. Its distributions are a Zig source library, native C ABI, WebAssembly npm
package, optional adapters and data packages, and reference applications.

The product has these layers:

```text
applications (CLI/TUI, browser, mobile, native frontends)
optional orchestration (clocks, IDs, capabilities, recovery)
optional adapters (SQLite, IndexedDB, custom host adapters)
canonical protocols (programming, tracking, workflows, discovery, import/export)
pure workflow bridge (recommendation/template -> tracking -> evaluation)
pure programming domain             pure tracking domain
  recommendation                      active workout lifecycle
  evaluation                          exercise membership and set lifecycle
  methodology configuration/state     revisions, replay, and idempotency
  filtering/ranking/explanations
```

This is a composition diagram, not permission for dependencies to point
outward. Pure programming, tracking, and workflow code depends on no adapter,
orchestration service, application, clock, random source, filesystem, network,
environment, process, or platform API. Canonical protocols are boundary
translations over typed APIs; JSON is not the internal domain model.

### State and acceptance

Tracking does not make the core stateful. A transition receives its current
snapshot and command explicitly and returns a proposal or structured rejection.
Revisions, replay receipts, timestamps, IDs, randomness, and capacity are
explicit inputs. The host decides whether to persist the next snapshot.

Recommendations and methodology-state changes remain proposals. The host must
explicitly accept them. Convenience APIs may supply clocks and IDs only through
injectable providers and must retain deterministic low-level operations.

### Workflow bridge and provenance

Pure bridges will connect recommendations and templates to tracked workouts and
completed tracked workouts to evaluation. Original prescriptions remain
separate from user edits. Provenance includes relevant input/result
fingerprints, methodology identity and versions, state revision or fingerprint,
acceptance ID, prescribed ordering and targets, modifications, timestamps, and
manual/template/recommendation origin.

### Templates

A template is reusable planned structure. It is not methodology state, a
generated recommendation, an active workout, or a completed workout. The first
model stays small and adds no scheduling or periodization.

### Persistence and orchestration

Persistence remains optional and outside the pure core. Optional orchestration
may coordinate narrow capabilities and recover idempotent multi-step workflows,
but cannot promise a transaction across unrelated host implementations.
Adapters may offer stronger composite transactions when storage supports them.

### Cross-language boundaries

Canonical operations are versioned, bounded, explicitly discriminated, and
preserve exact decimals, stable issue codes, deterministic ordering, and
structured provenance. Independent enums use exhaustive mappings, not ordinal
casts.

C and WASM use versioned message-oriented execution. The pre-release C buffer
with caller-mutable allocator metadata is not preserved: ABI v2 must use caller
output storage with required-size reporting or opaque handles. npm will expose
deterministic low-level APIs and a distinct convenience layer with injectable
clock, ID, and persistence providers.

## Product boundaries

Caudex is not a hosted service, identity system, mandatory database, UI
framework, generalized functional-programming framework, medical product, or AI
coach. Hosts own users, authorization, synchronization, UX, and business
decisions.

## Distribution and CI consequences

- Publishable Zig core includes programming, tracking, and pure workflows, but
  excludes CLI/TUI, Vaxis, SQLite, and application assets.
- SQLite and catalog Zig packages have separate boundaries.
- npm naming changes are coordinated before a stable release.
- Pull requests compile/link a host-native C artifact. The complete prebuilt C
  matrix runs only for version tags or explicit manual dispatch.
- No scheduled or nightly workflow is introduced.

## Consequences

The product becomes broader without weakening the deterministic core.
Canonical tracking, workflows, templates, discovery, import/export, adapters,
catalog data, and language facades require phased conformance-tested additions.
ABI v2, schema additions, migrations, and coordinated npm naming are permitted
pre-stable breaks and require migration notes when implemented.

