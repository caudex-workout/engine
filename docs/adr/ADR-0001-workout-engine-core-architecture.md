# ADR-0001: Functional Core, Explicit Zig Shell, and Adapter Architecture

- **Status:** Accepted, partially superseded by ADR-0002 and ADR-0003
- **Date:** 2026-07-19
- **Decision owners:** Workout Engine maintainers
- **Applies to:** Engine v0.1 and later unless superseded by another ADR

> **Supersession notice:** ADR-0002 supersedes this ADR's tracking-first
> product scope, SQLite-first MVP, event-journal requirements, and
> implementation sequence. ADR-0003 supersedes any remaining implication that
> the core owns repositories, database schemas, migrations, transactions, or
> durable state. This ADR remains authoritative for the functional-core
> discipline, explicit idiomatic Zig shell, deterministic calculations, C ABI
> principles, exact-measurement rules, and rejection of generalized
> functional-programming frameworks. Do not use the superseded storage or
> sequencing sections as current implementation requirements.

## Context

Workout Engine is intended to become an embeddable, tracking-first strength-training engine used by native applications, servers, command-line clients, and potentially WebAssembly hosts. Its first release must accurately record workouts and expose history without embedding a training methodology. Later releases may calculate recommendations, model recovery, and support programming.

The engine must also remain:

- Deterministic enough to test exhaustively
- Safe to embed across language boundaries
- Suitable for local-first and eventually synchronized clients
- Idiomatic in Zig 0.16.0
- Understandable without adopting a large abstraction framework
- Capable of using SQLite without making the database schema the public API

The original plan correctly separated domain logic from persistence, but it left several risks:

1. “Pure core” could be interpreted as adopting generalized functional-programming machinery that is unnatural in Zig.
2. A large set of abstract ports and repositories could reproduce object-oriented dependency-injection patterns through function pointers.
3. Horizontally implementing every domain layer before proving one end-to-end path would delay architectural feedback.
4. Public numeric positions and globally canonical micro-units would create avoidable ordering and measurement problems.
5. Treating current-state tables and domain events as two vaguely independent sources of truth would leave recovery and synchronization semantics unclear.
6. Scaffolding a large final directory tree before the code earns those boundaries would create empty abstractions and unnecessary navigation.

## Decision

Workout Engine will use a **functional core and explicit imperative shell**, adapted to Zig rather than copied from a generalized functional-programming ecosystem.

> Workout Engine uses functional programming as an architectural discipline rather than adopting a generalized functional-programming abstraction framework. Domain decisions and recommendation calculations are deterministic and effect-free. Application orchestration, allocation, persistence, and ABI handling use explicit idiomatic Zig.

The architecture consists of:

```text
Host application
    │
    ├── Direct Zig API
    ├── C ABI adapter
    ├── Future WASM adapter
    └── Future HTTP / CLI clients
            │
            ▼
Application orchestration
    ├── Parse and validate boundary input
    ├── Allocate owned data and scratch storage
    ├── Load state
    ├── Invoke deterministic domain decisions
    ├── Project accepted events
    ├── Persist state, events, and command receipt atomically
    └── Encode the response
            │
      ┌─────┴─────────────┐
      ▼                   ▼
Domain model         Storage adapter
and decisions        SQLite in v0.1
```

The dependency direction is inward:

- Domain code depends only on domain primitives and Zig’s standard language facilities.
- Application code depends on the domain.
- SQLite, protocol, ABI, and future platform adapters depend on the application/domain contracts.
- Domain code never imports SQLite, ABI, JSON protocol, filesystem, networking, clocks, or randomness.

## Functional-programming discipline

### What “functional” means in this project

The project adopts these practices:

- Domain decision functions receive all required inputs explicitly.
- The same valid inputs produce the same decision result.
- Domain decisions do not perform I/O.
- Domain decisions do not read clocks, random generators, process state, environment variables, global mutable state, or databases.
- Recommendation calculations use immutable snapshots and explicit strategy configuration.
- Validation and calculation are expressed as ordinary functions over values.
- Commands describe intent; domain events describe accepted state transitions.
- Exhaustive `switch` statements over tagged unions make state transitions visible.
- Errors are values with stable machine-readable codes.
- Mutation and allocation are visible at the call site rather than hidden behind abstractions.
- Derived calculations use checked arithmetic.

“Effect-free” means no externally observable effects or hidden nondeterministic inputs. A deterministic projector may mutate caller-owned in-memory state, and a calculation may write into caller-provided output storage, but those operations must be explicit in the function signature and must not perform external I/O.

### What the project will not adopt

Workout Engine will not adopt a generalized functional-programming abstraction framework merely to make Zig resemble Haskell, Scala, or functional TypeScript.

The core will not introduce:

- Monad, functor, applicative, lens, or typeclass emulation
- A generalized `.map` / `.filter` / `.reduce` wrapper hierarchy
- Persistent immutable collection frameworks by default
- Free-monad or effect-system interpreters
- Runtime dependency-injection containers
- Framework-wide currying or point-free style
- Generic “pipeline” abstractions that obscure allocation or control flow
- A `zig-cats` dependency unless a later, concrete use case demonstrates a clear benefit that ordinary Zig cannot provide cleanly

Idiomatic Zig constructs are preferred:

- Structs and tagged unions
- Error unions
- Optional values
- Slices and caller-owned buffers
- Explicit loops
- Explicit allocators
- `defer` and `errdefer`
- `switch`
- Compile-time generics where they materially simplify code
- Narrow function-pointer tables only where runtime substitution is truly required

Domain-specific higher-order helpers are allowed when they make a repeated domain operation clearer. The restriction is against adopting a generalized abstraction framework, not against functions as values.

## Domain decision and projection model

The conceptual write flow is:

```text
decision = decide(current_state_view, command)
events = decision.events
projected_state = project(current_state, events)
```

The implementation does not need to force every aggregate into one generic signature. Each aggregate may expose explicit functions such as:

```zig
pub fn decideWorkout(
    state: *const Workout,
    command: WorkoutCommand,
    out: *DecisionBuffer,
) DomainIssue!void;

pub fn applyWorkoutEvent(
    state: *Workout,
    event: WorkoutEvent,
) DomainIssue!void;
```

Important constraints:

- Decision functions do not allocate.
- The application layer owns any arena, buffer, or long-lived allocation.
- Decision outputs either fit in bounded value storage or are written to caller-provided storage.
- Event projection is deterministic.
- Event projection may mutate caller-owned aggregate memory.
- Projection must not access persistence or other aggregates implicitly.
- Cross-aggregate facts required for a decision are loaded explicitly and passed as value snapshots.

Recommendation calculations follow the same rule:

```zig
pub fn recommend(
    history: HistorySnapshot,
    config: StrategyConfig,
    out: *RecommendationBuffer,
) RecommendationIssue!void;
```

A recommendation function must not persist, accept, or apply its own recommendation.

## Application orchestration

The application layer is an explicit imperative shell. It is responsible for:

1. Decoding or receiving a typed command
2. Enforcing request-size and protocol limits
3. Beginning a transaction
4. Checking the command receipt for idempotency
5. Loading the required aggregate and supporting snapshots
6. Checking the expected revision
7. Allocating scratch and owned output memory
8. Calling the domain decision function
9. Applying accepted events to the loaded state
10. Writing the state projection
11. Appending the event records
12. Recording the command result
13. Committing
14. Returning a typed result
15. Translating errors at the public boundary

This code should look like straightforward Zig. It may use mutable locals, loops, `defer`, `errdefer`, and explicit error handling. It should not be forced through a generalized functional pipeline.

Infrastructure failures and domain rejections remain distinct:

```text
DomainIssue
- validation.invalid_metric
- workout.invalid_transition
- exercise.archived
- revision.conflict

EngineError
- out_of_memory
- storage.busy
- storage.corrupt
- protocol.invalid_utf8
- protocol.unsupported_version
- abi.invalid_argument
```

A domain issue is an expected rejected decision. An engine error means the engine could not safely complete the operation.

## Storage abstraction

SQLite is the required v0.1 store.

The project will not begin with a broad runtime-polymorphic `Repository` interface. Instead:

- Define narrow store operations around actual application use cases.
- Use concrete Zig types.
- Parameterize contract tests and application helpers with compile-time generics when both `MemoryStore` and `SqliteStore` need to satisfy the same shape.
- Introduce a runtime function-pointer table only when a real host must select storage implementations at runtime.
- Keep SQL, row mapping, migrations, and SQLite error handling inside `src/storage/sqlite`.

A likely pattern is:

```zig
pub fn CommandService(comptime Store: type) type {
    return struct {
        store: *Store,
        // ...
    };
}
```

This is a direction, not a requirement to genericize every function. If a concrete `SqliteCommandService` is clearer, use it and share only the deterministic domain tests.

## State projections and event journal

Workout Engine uses both:

- Normalized state tables for ordinary reads
- An append-only domain-event journal for audit, idempotent synchronization, and deterministic projection tests

They are not independent competing truths.

For every accepted command, one SQLite transaction must atomically:

1. Update the materialized state projection
2. Append all domain events
3. Advance the aggregate revision
4. Store the command receipt and replayable result

Domain events must contain enough information to apply the accepted transition without rereading the original command. Aggregate streams must be replayable in tests from creation to current state.

Normal startup and queries do not replay the entire event history. Materialized tables are the serving representation. A mismatch between event replay and materialized state is corruption, not a conflict to resolve by arbitrarily choosing one representation.

The project is not committing to a global event-sourcing platform, event broker, or event-only query model.

## Idempotency, revisions, and concurrency

Every command envelope includes:

- `command_id`
- `athlete_id`
- Optional `aggregate_id`
- Optional `expected_revision`
- `occurred_at`
- Optional `device_id`
- Versioned payload

Rules:

- Retrying a processed `command_id` returns the original stored result.
- A mismatched `expected_revision` produces a domain conflict and no state change.
- SQLite updates, event appends, and command receipts commit together.
- One engine handle supports one active caller at a time in v0.1.
- Multiple handles may exist, subject to SQLite locking behavior.
- Busy handling is explicit and bounded.
- No automatic field-level merge or CRDT behavior is implemented in v0.1.

## Ordering collections

Public commands do not set raw numeric positions.

Commands express semantic placement:

- Insert first
- Insert after an entity ID
- Move first
- Move after an entity ID

The state projection may use dense positions or gapped internal sort keys, but that representation is private and may change. Events retain anchor identity so future synchronization can detect missing or conflicting anchors rather than merging unexplained integer positions.

## Measurements and arithmetic

The engine preserves the exact value and unit entered by a client:

```text
Decimal
- mantissa: i64
- scale: u8

MetricValue
- code
- decimal
- unit_code
```

Examples:

```text
70 lb    => mantissa 70, scale 0, unit lb
2.5 kg   => mantissa 25, scale 1, unit kg
7.5 RPE  => mantissa 75, scale 1, unit rpe
```

This replaces a requirement to store every value in extremely small canonical units.

Rules:

- Floating-point values do not cross the stable protocol as authoritative measurements.
- Values are range checked.
- Unit conversion occurs only when needed.
- Derived calculations use checked `i128` intermediates where appropriate.
- The engine returns a structured overflow or incompatible-unit issue rather than wrapping.
- User-entered values remain available for faithful display.
- A future query projection may cache normalized values, but the domain value remains exact and unit-aware.

## Public APIs and adapters

### Direct Zig API

The direct typed Zig API is the primary implementation API and the first end-to-end integration target.

It exposes:

- Engine opening and closing
- Typed command execution
- Typed queries
- Explicit allocators and ownership
- Stable domain and engine error categories

Internal module types are not automatically public API. Public declarations are intentionally exported through `src/root.zig`.

### C ABI

The C ABI is a thin adapter over the application API.

It uses:

- Opaque handles
- Stable numeric status codes
- Length-delimited input
- Versioned request and response messages
- Engine-owned output buffers with one documented free function

Zig domain structs, allocators, error unions, and slices are not exposed directly as ABI-stable layouts.

JSON is the initial message encoding because it is debuggable and easy to bind. The encoding is not part of the domain model, and another encoding may be added under a new protocol identifier without replacing the C entry points.

### WASM, HTTP, and CLI

These are downstream adapters or clients.

- WASM is deferred until the native core and protocol are stable.
- HTTP remains a host application concern.
- The CLI is the first planned real client after engine v0.1.
- No adapter may mutate SQLite tables directly.

## Compatibility boundaries

These versions evolve independently:

- Engine semantic version
- Direct Zig public API
- C ABI version
- Command/query protocol version
- Domain-event payload version
- SQLite schema version
- Extension/annotation schema versions

A migration in one boundary does not automatically require a major version change in every other boundary.

Compatibility tests must verify:

- Old supported databases migrate to the current schema.
- Old supported protocol fixtures still decode or fail with the documented version error.
- C headers compile as C11 and C++.
- Domain-event fixtures replay after internal refactors.
- Public Zig declarations do not accidentally expose private implementation types.

## Initial module boundaries

Do not scaffold the final imagined repository tree all at once. Start with a small structure and split files only when responsibilities become substantial:

```text
src/
├── root.zig
├── domain/
│   ├── primitives.zig
│   ├── catalog.zig
│   ├── workout.zig
│   ├── command.zig
│   ├── event.zig
│   ├── decision.zig
│   └── recommendation.zig
├── app/
│   ├── engine.zig
│   ├── command_service.zig
│   └── query_service.zig
├── storage/
│   ├── memory.zig
│   └── sqlite/
├── protocol/
└── abi/
```

Files may later be split by aggregate or capability. The architecture is defined by dependency and effect boundaries, not by maximizing the number of directories.

## Development sequencing

Implementation proceeds through a walking skeleton before broad feature work:

1. Establish primitives, errors, and architecture tests.
2. Implement one minimal command and deterministic event.
3. Execute it through the application layer against `MemoryStore`.
4. Persist it through SQLite.
5. Expose it through the direct Zig API.
6. Reopen the database and query the result.
7. Expand the catalog and workout model.
8. Add the C ABI only after the typed API is coherent.

This replaces a purely horizontal “finish all domain code, then all persistence, then all integration” sequence.

## Enforcement

Every code review and Codex task must check:

- No SQLite, protocol, ABI, clock, randomness, filesystem, or networking imports from `src/domain`.
- No hidden allocation in domain decision or recommendation functions.
- No generalized FP framework or abstraction added without a concrete, measured benefit.
- No runtime polymorphism where compile-time specialization or a concrete type is simpler.
- No public numeric collection positions.
- No floating-point authoritative measurements.
- No infrastructure error represented as a domain validation issue.
- No command accepted without atomic state, event, revision, and receipt persistence.
- No public API that permits direct mutation of internal tables.
- No recommendation that applies itself.

The build should include a domain-only test target that does not link SQLite or libc. Contract tests should exercise both memory and SQLite stores where sharing the contract provides value.

## Consequences

### Benefits

- Domain behavior is easy to test and reason about.
- Recommendation strategies can be evaluated against fixed snapshots.
- Zig code remains explicit and familiar to Zig developers.
- Allocation and ownership remain visible.
- Cross-language clients receive a narrow stable boundary.
- SQLite can evolve without becoming the public data contract.
- Event-based audit and synchronization remain possible.
- The project avoids premature commitment to a generalized abstraction framework.
- An early vertical slice validates the architecture before the full model is built.

### Costs

- Application orchestration contains more explicit code than a framework-driven design.
- State projection and event replay must be kept equivalent.
- The C ABI requires serialization and buffer ownership code.
- Compile-time store specialization may increase compilation work if overused.
- Pure decision boundaries require deliberate snapshot construction.
- Future synchronization still requires a conflict policy and transport.

### Risks

- “Functional core” may erode into effectful convenience methods.
- Events may become incomplete audit messages rather than replayable transitions.
- Annotation extensibility may be abused to avoid proper domain modeling.
- The direct Zig API may accidentally expose unstable internals.
- Generic store code may become an abstraction project of its own.

The enforcement rules and compatibility tests above are intended to control these risks.

## Rejected alternatives

### Adopt `zig-cats` or another generalized FP framework

Rejected for the core architecture. The project needs deterministic domain functions, not a generalized typeclass ecosystem. A dependency may be reconsidered only for a specific problem with a demonstrated reduction in complexity.

### Use object-oriented runtime interfaces for every port

Rejected. Zig supports explicit composition and compile-time generic contracts. Runtime function tables are reserved for actual runtime substitution.

### Put all behavior in mutable service objects

Rejected because it would make decision logic harder to test independently and would encourage hidden clocks, persistence, and allocation.

### Use event history as the only query store

Rejected for v0.1. Workout history queries should use normalized indexed state projections rather than replaying every event.

### Store only current state and add events later

Rejected because idempotent offline synchronization and historical corrections influence identifiers, revisions, tombstones, and transaction boundaries from the beginning.

### Expose SQLite as the integration API

Rejected because clients would bypass invariants, compatibility rules, audit events, and revision checks.

### Use a large C struct API for every domain type

Rejected because it would freeze too much layout and create expensive ABI evolution.

### Build the C ABI before the typed Zig API

Rejected. The direct API should prove the application contract first; the C ABI then adapts a coherent surface.

## References

- Zig 0.16.0 language documentation: <https://ziglang.org/documentation/0.16.0/>
- Zig 0.16.0 release notes: <https://ziglang.org/download/0.16.0/release-notes.html>
- SQLite transaction and WAL documentation: <https://sqlite.org/wal.html>
- SQLite STRICT tables: <https://sqlite.org/stricttables.html>
