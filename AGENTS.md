# Workout Engine Codex Instructions

## Project purpose

Workout Engine is an open-source, embeddable strength and hypertrophy workout-tracking engine written in Zig 0.16.0.

The initial product is a developer-facing engine/library. Frontends, mobile applications, a CLI, hosted services, workout generation, and periodization are outside engine v0.1.

Read these documents before making architectural or domain changes:

- `docs/adr/ADR-0001-workout-engine-core-architecture.md`
- `docs/plans/implementation-plan.md`
- `README.md`

The ADR is authoritative when another document or a task prompt conflicts with it. Report material conflicts before implementing around them.

## Architectural discipline

Workout Engine uses functional programming as an architectural discipline rather than adopting a generalized functional-programming abstraction framework.

Domain decisions and recommendation calculations are deterministic and effect-free.

Application orchestration, allocation, persistence, protocol handling, and ABI handling use explicit idiomatic Zig.

### Domain rules

Code under `src/domain/` must not:

- Access SQLite or other persistence
- Read files or environment variables
- Access the network
- Read a clock
- Generate random values or IDs
- Access global mutable state
- Parse public JSON protocols
- Depend on the C ABI
- Log as part of domain behavior
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
- Compile-time generics only when they make concrete code clearer

Do not introduce:

- `zig-cats`
- Monad, functor, applicative, lens, or typeclass emulation
- A generalized map/filter/reduce abstraction hierarchy
- Persistent immutable collection frameworks by default
- Runtime dependency-injection containers
- Framework-wide currying
- Generic pipeline abstractions that obscure control flow or allocation

A domain-specific higher-order helper is acceptable when it clearly simplifies a real repeated operation.

## Commands and events

Commands express user or host intent.

Events express accepted domain facts.

Domain decision functions validate commands and produce events without performing I/O or persistence.

Event projection deterministically applies accepted events to caller-owned in-memory state.

A rejected command must produce no events and no state mutation.

State projection, emitted events, aggregate revision advancement, and command receipts must eventually be persisted atomically.

## Storage and API rules

- SQLite is the required v0.1 persistence adapter.
- SQLite tables are not the public mutation API.
- Use prepared statements and bound parameters.
- Released migrations are immutable and forward-only.
- Prefer concrete store implementations and narrow contracts.
- Do not create broad runtime-polymorphic repository frameworks prematurely.
- Implement and stabilize the typed Zig API before the C ABI.
- Do not expose SQLite or private domain representations through the public API.
- Public collection commands use semantic anchors such as “first” and “after ID,” not raw numeric positions.
- Authoritative measurements use exact decimal values and explicit unit codes, not floating-point values.

## Scope constraints

Do not add any of the following unless the current issue explicitly requires it:

- CLI
- Mobile, desktop, or web frontend
- HTTP service
- Workout generation
- Programs or templates
- Periodization
- Recommendation strategies
- Muscle recovery or fatigue modeling
- Cardio tracking
- Cloud synchronization transport
- Automatic conflict merging
- HealthKit or Health Connect integration
- Comprehensive exercise database
- Dynamic plugin system

Do not build speculative abstractions solely for these future capabilities.

## Implementation workflow

For every task:

1. Read the relevant documents and neighboring code.
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
   - Architectural decisions
   - Known limitations

Do not modify unrelated files.

Do not add a production dependency without explaining its purpose, license, and why the standard library or direct implementation is insufficient.

Do not commit, push, create branches, rewrite Git history, or open pull requests unless the user explicitly requests it.

## Required checks

Once the build system supports them, run:

```bash
zig build
zig build test
zig fmt --check .
git diff --check
```

Use the commands that actually exist in the current repository. Do not claim a check passed unless it was run successfully.

## Task sizing

Work on one independently testable issue at a time.

Do not implement an entire epic or the complete implementation plan in one task.

Prefer the smallest coherent change that satisfies the current acceptance criteria.