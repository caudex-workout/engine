# Caudex Workout Engine

Caudex Workout Engine is an open-source, embeddable strength and hypertrophy
programming engine for developers. Applications supply explicit training
snapshots and methodology configuration; Caudex returns deterministic,
explainable workout recommendations, performance evaluations, and proposed
methodology state.

Caudex is a stateless library, not a workout-tracker application or hosted
fitness platform. The host owns users, UI, workout-history persistence,
synchronization, and whether a recommendation is accepted or stored. The core
does not require SQLite or any other database.

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

It does not include a tracker UI, required persistence, user accounts, sync, a
CLI product, a hosted API, full periodization, cardio programming, arbitrary
runtime plugins, or medical/AI coaching.

## Architecture

Caudex uses a functional core with an explicit idiomatic Zig shell. Domain and
methodology calculations receive all material inputs explicitly and perform no
I/O, persistence, clock reads, or hidden randomness. Optional adapters and host
applications depend on the core; the core never depends on them.

The architecture and implementation sequence are defined by:

- [ADR-0001: Functional Core, Explicit Zig Shell, and Adapter Architecture](docs/adr/ADR-0001-workout-engine-core-architecture.md)
- [ADR-0002: Library-First Product, Stateless Core, and Multi-Ecosystem Distribution](docs/adr/ADR-0002-library-first-product-and-distribution.md)
- [ADR-0003: Persistence Is an Optional Adapter Outside the Core](docs/adr/ADR-0003-persistence-as-optional-adapter.md)
- [Implementation plan](docs/implementation-plan.md)

ADR-0002 supersedes ADR-0001's tracking-first and SQLite-first product
decisions. ADR-0003 makes persistence permanently optional and outside the core.
ADR-0001 remains authoritative for the functional-programming discipline and
explicit Zig boundary design.

The project is currently in its contract and core-scaffolding phase. Public API
examples should be treated as design material until their corresponding
milestone acceptance criteria are complete.
