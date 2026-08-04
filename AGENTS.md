# Caudex Workout Engine Codex Instructions

## Project purpose

Caudex Workout Engine is an open-source, embeddable exercise-programming and
active-workout tracking SDK written in Zig 0.16.0. It accepts explicit
host-supplied snapshots and returns deterministic recommendations, performance
evaluations, tracking transitions, workflow results, and proposed methodology
state.

The initial product is a developer-facing, stateless engine/library. The host
owns users, UI, persistence, workout history, synchronization, and the decision
to accept or store a result.

The SDK includes programming and pure tracking domains plus first-party
reference applications. It does not include required persistence, hosted
services, mobile or web frontends, full periodization, or long-term calendar
generation.

Read these documents before making architectural or domain changes:

- `docs/adr/ADR-0001-workout-engine-core-architecture.md`
- `docs/adr/ADR-0002-library-first-product-and-distribution.md`
- `docs/adr/ADR-0003-persistence-as-optional-adapter.md`
- `docs/adr/ADR-0006-programming-and-active-tracking-sdk.md`
- `docs/implementation-plan.md`
- `README.md`

Accepted ADRs are authoritative. Apply them in decision order: ADR-0002
supersedes ADR-0001's tracking-first scope, SQLite-first MVP, event-journal
requirements, and implementation sequence; ADR-0003 supersedes any remaining
implication that the core owns persistence or durable state; ADR-0006 supersedes
ADR-0002's programming-only scope. ADR-0001 remains
authoritative for the functional-core discipline, explicit idiomatic Zig shell,
deterministic calculations, C ABI principles, and rejection of generalized
functional-programming frameworks.

Report a material conflict before implementing around it.

## Architectural discipline

Caudex uses functional programming as an architectural discipline rather than
adopting a generalized functional-programming abstraction framework.

Domain and methodology calculations are deterministic and effect-free.
Application orchestration, allocation, serialization, package loading,
protocol handling, and ABI handling use explicit idiomatic Zig.

The dependency direction is inward:

```text
host or optional adapter -> facade/canonical schemas -> stateless core
```

The core never depends on a persistence adapter, repository interface, database,
host lifecycle, or platform service.

### Core domain rules

These rules apply to the inner deterministic core, whether the current code is
located under `core/src/model`, `core/src/validation`, `core/src/history`,
`core/src/recommendation`, `core/src/methodology`, or a future directory named
`src/domain`.

Core domain and methodology calculations must not:

- Access SQLite or other persistence
- Depend on repository interfaces, migrations, or transaction managers
- Read files or environment variables
- Access the network
- Read a clock; time must be an explicit input
- Use hidden randomness; any seed must be an explicit input
- Generate nondeterministic values or IDs
- Access global mutable state
- Parse public JSON protocols
- Depend on the C ABI or platform APIs
- Log as part of domain behavior
- Persist, accept, or automatically apply recommendations
- Hide allocation inside decision or recommendation functions

Prefer:

- Structs
- Tagged unions
- Error unions
- Optional values
- Explicit loops
- Explicit `switch` statements
- Slices and caller-provided buffers
- Explicit allocators outside domain decisions
- `defer` and `errdefer`
- Checked arithmetic
- Compile-time generics only when they make concrete code clearer

Do not introduce:

- `zig-cats`
- Monad, functor, applicative, lens, or typeclass emulation
- A generalized map/filter/reduce abstraction hierarchy
- Free-monad or effect-system interpreters
- Persistent immutable collection frameworks by default
- Runtime dependency-injection containers
- Framework-wide currying
- Generic pipeline abstractions that obscure control flow or allocation

A domain-specific higher-order helper is acceptable when it clearly simplifies
a real repeated operation. A runtime function table is acceptable for the
methodology registry because runtime methodology selection is a concrete
product requirement.

## Inputs, results, and effects

The host supplies complete request snapshots, including history, catalog data,
methodology configuration and state, session constraints, and explicit time or
tie-break inputs when needed.

The core validates those values and returns recommendations, evaluations,
structured explanations, warnings, and proposed next state. A rejected request
produces no accepted result or hidden mutation. A calculated recommendation is
a proposal; the host explicitly decides whether to accept or persist it.

Persistence adapters are optional downstream packages. Adapter operations may
load snapshots and persist an explicitly accepted result, but they must not
change recommendation semantics. SQLite, PostgreSQL, IndexedDB, custom
repositories, remote APIs, and no persistence are all valid host choices.

## Issue and error rules

Keep expected calculation outcomes distinct from failures to execute:

- Validation and methodology issues are structured result values with stable
  machine-readable codes. They describe input or domain conditions the core
  safely rejected.
- Engine/runtime errors mean calculation could not complete safely, such as
  allocation failure, corrupt artifacts, serialization failure, or an internal
  invariant violation.
- Persistence conflicts and adapter failures belong to the adapter/application
  layer. They must not masquerade as core validation or methodology issues.

`DomainIssue` and `EngineError` in ADR-0001 are conceptual categories, not
mandatory public Zig type names. CWE-002 and CWE-004 define the canonical public
models and naming before those contracts are implemented.

## Storage and API rules

- The core and core npm/WASM package must not link a database.
- Persistence adapters are post-v0.1 optional packages unless a specific issue
  explicitly changes their schedule.
- An optional SQLite adapter must use prepared statements and bound parameters.
- Released adapter migrations are immutable and forward-only.
- Prefer narrow adapter capabilities and concrete implementations.
- Do not create a broad runtime-polymorphic repository framework.
- Implement and stabilize the typed Zig API before adapting it to the C ABI.
- Do not expose private core representations through a public API.
- Authoritative measurements use exact decimal values and explicit unit codes,
  not floating-point values.
- Material recommendation decisions include structured explanation codes.

## Scope constraints

Do not add the following unless the current issue explicitly requires it:

- Tracker application
- CLI as a product
- Mobile, desktop, or web frontend
- Hosted HTTP service
- User accounts, authentication, or cloud synchronization
- Required persistence or persistence inside the core
- Event sourcing
- Full periodization or long-term calendar generation
- Cardio or mobility programming
- Muscle recovery or fatigue modeling beyond explicit v0.1 inputs
- HealthKit or Health Connect integration
- Comprehensive exercise database
- Arbitrary runtime plugins or a methodology bytecode/DSL
- AI/LLM-generated recommendations
- Medical or rehabilitation logic

Do not build speculative abstractions solely for future capabilities.

## Implementation prerequisites

Follow the issue order and acceptance criteria in `docs/implementation-plan.md`.
In particular:

- CWE-001 establishes current product positioning.
- CWE-002 defines and reviews the canonical v0 request/result model before code
  implements that model.
- CWE-003 defines the npm-first quickstart as an executable documentation target.
- CWE-004 defines stable issue and explanation conventions.
- CWE-010 is the first code implementation issue.

Do not invent the unresolved public API, schemas, or issue catalog as part of an
unrelated scaffolding task. If a prerequisite is incomplete and materially
blocks the requested issue, report it and complete only when it is in scope.

## Implementation workflow

For every task:

1. Read the relevant ADRs, plan sections, and neighboring code.
2. Inspect the current Git status.
3. State a concise implementation plan before editing.
4. Identify conflicts or ambiguity that materially affect correctness.
5. Implement only the requested issue.
6. Add tests for new behavior.
7. Run formatting and all relevant tests.
8. Inspect the final diff for unrelated changes.
9. Report:
   - Summary
   - Files changed
   - Tests and exact commands run
   - Public API or schema changes
   - Architectural decisions
   - Known limitations

Do not modify unrelated files.

Do not add a production dependency without explaining its purpose, license, and
why the standard library or a direct implementation is insufficient.

Do not commit, push, create branches, rewrite Git history, or open pull requests
unless the user explicitly requests it.

## Required checks

Once the build system supports them, run:

```bash
zig build
zig build test
zig fmt --check .
git diff --check
```

Use commands that actually exist in the repository. Do not claim a check passed
unless it ran successfully.

For documentation-only tasks before the Zig build exists, run applicable
read-only link/path checks and `git diff --check`.

## Task sizing

Work on one independently testable issue at a time.

Do not implement an entire epic or the complete implementation plan in one task.

Prefer the smallest coherent change that satisfies the current acceptance
criteria. Do not create empty directories merely to match the proposed final
repository tree.
