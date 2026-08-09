# ADR-0003: Persistence Is an Optional Adapter Outside the Core

- **Status:** Accepted
- **Date:** 2026-07-24
- **Decision owners:** Caudex Workout Engine maintainers
- **Clarifies:** ADR-0002
- **Supersedes:** Any remaining implication that the Caudex core owns repositories, database schemas, migrations, transactions, or durable state
- **Preserves:** The stateless-core, functional-discipline, deterministic-recommendation, and library-first decisions in ADR-0001 and ADR-0002

## Context

Caudex Workout Engine is intended to be embedded in applications that already make different architectural choices:

- A local mobile application may use SQLite.
- A web application may use IndexedDB in the browser.
- A hosted service may use PostgreSQL.
- An existing fitness product may already have repositories, an ORM, event streams, or remote APIs.
- A prototype, test, playground, or serverless calculation may need no persistence.
- A consumer may want to persist only methodology state while keeping workout history in an existing system.

Requiring a repository interface inside the core would still couple recommendation logic to application lifecycle and storage concerns, even if the interface were abstract. Requiring a canonical database schema would make integration harder for established applications and would undermine npm/WebAssembly portability.

The core already receives explicit snapshots and returns proposed values. Persistence should preserve this model rather than becoming a hidden dependency.

## Decision

The Caudex core is permanently independent of persistence.

> The core accepts explicit request snapshots and returns recommendation or evaluation results. It does not open databases, load repositories, perform migrations, begin transactions, save methodology state, or record accepted recommendations.

Persistence belongs in optional adapters and host integration code.

```text
No-persistence application
    └── builds request ────────────────┐
                                       │
Application with custom repositories   │
    └── maps host data to request ─────┼──► Caudex core
                                       │      │
Application using optional adapter     │      └── result + proposed state
    ├── SQLite adapter ────────────────┤
    ├── PostgreSQL adapter ────────────┤
    └── IndexedDB adapter ─────────────┘
            │
            └── host explicitly persists an accepted result
```

The dependency direction is one way:

```text
optional persistence adapter ──► language facade / canonical schemas ──► core
core ──X──► persistence adapter
```

The core must compile and run without:

- SQLite
- PostgreSQL clients
- IndexedDB APIs
- ORM libraries
- Repository interfaces
- Filesystem access
- Database migrations
- Transaction managers

## Two supported integration modes

### Direct snapshot mode

This is the fundamental API and requires no persistence abstraction:

```ts
const result = caudex.recommendSession({
  catalog,
  history,
  programState,
  methodology,
  session,
  asOf,
});
```

The host obtains and stores those values however it chooses—or does not store them at all.

Direct snapshot mode is always supported and remains the reference semantic API.

### Optional repository-orchestration mode

A separate integration package may help applications assemble requests from repositories and persist accepted state.

Conceptually:

```ts
const integration = createCaudexIntegration({
  engine: caudex,
  catalogSource,
  historySource,
  methodologyStateStore,
  recommendationJournal,
});

const result = await integration.recommendSession(query);

// Nothing has been persisted yet.
await integration.persistAcceptedResult({
  query,
  result,
  expectedStateRevision,
});
```

The integration package is convenience orchestration. It must produce the same canonical core request and result as direct snapshot mode.

It must never make recommendation semantics depend on the selected database.

## Persistence capabilities

Do not require every application to implement one large repository.

Optional integration packages should define narrow capabilities:

```text
CatalogSource
- loadCatalog(scope)

HistorySource
- loadHistory(query)

MethodologyStateStore
- loadState(key)
- compareAndSetState(key, expected_revision, next_state)

RecommendationJournal (optional)
- appendAcceptedRecommendation(record)

CompletedWorkoutSink (optional)
- appendCompletedWorkout(workout)
```

Rules:

- Applications may implement only the capabilities they need.
- Catalog and workout history remain host-owned data.
- Methodology state is an opaque, versioned Caudex value at the storage boundary.
- Recommendation journaling is optional.
- Persisting completed workouts through Caudex is optional.
- The core never sees these capability interfaces.
- Capability interfaces may differ idiomatically by language while preserving the same conceptual responsibilities.

## Explicit acceptance boundary

A recommendation result is a proposal.

The core and adapters do not silently persist `nextProgramState` merely because a recommendation was calculated.

The host must explicitly accept a recommendation or evaluation result before invoking persistence.

This supports:

- User edits
- User rejection
- Preview and simulation
- Multiple alternatives
- Dry runs
- Tests
- Server-side validation before commit

A persistence helper may bundle accepted changes into one transaction when the selected adapter supports transactions.

## Concurrency and revisions

Optional methodology-state stores must support optimistic concurrency or provide an equivalent conflict mechanism.

A stored methodology-state envelope should contain:

```text
MethodologyStateRecord
- host_scope_key
- methodology_id
- methodology_version
- state_schema_version
- state
- revision
- updated_at
```

Saving proposed state should include an expected revision.

If the state changed after the recommendation request was built, the adapter returns a persistence conflict. The core recommendation remains a valid historical calculation, but the host must decide whether to rebuild, discard, or reconcile it.

Conflict handling is an adapter/application concern. It is not represented as a core methodology calculation issue.

## Transactions

The core has no transaction concept.

An optional adapter may support an explicit unit of work for operations such as:

1. Store an accepted recommendation record.
2. Compare-and-set the next methodology state.
3. Append a completed workout or acceptance event.
4. Commit atomically.

Transaction guarantees are documented per adapter.

Do not pretend IndexedDB, SQLite, PostgreSQL, and arbitrary remote repositories have identical operational behavior. The shared adapter contract specifies observable outcomes, not one database transaction API.

## Adapter packages

Proposed packages are separate from the core package and may release independently:

```text
@caudex-workout/engine
@caudex-workout/persistence
@caudex-workout/persistence-indexeddb
@caudex-workout/persistence-sqlite
@caudex-workout/persistence-postgres
```

ADR-0006 finalizes the first three implemented names before stable release.

### `@caudex-workout/persistence`

May contain:

- TypeScript capability interfaces
- Request-assembly orchestration
- Accepted-result persistence orchestration
- Repository contract tests
- In-memory test doubles
- Mapping helpers
- No database driver

### Database-specific packages

Each package:

- Depends on `@caudex-workout/persistence` and public Caudex schemas
- Contains its own driver dependencies
- Owns its own schema and migrations, if it provides a reference schema
- Documents runtime support
- Passes the shared repository contract suite
- Does not alter recommendation semantics
- Can be omitted completely

Equivalent packages or modules may be created for Zig, Swift, Kotlin, or other ecosystems only when there is demand.

## Reference schemas versus existing application schemas

A database adapter may support two patterns.

### Reference repository

Caudex provides tables/object stores for applications that want ready-made persistence.

Reference schemas are private to the adapter package. They are not part of the core API and may evolve through adapter-specific migrations.

### Mapping adapter

An established application implements the capability interfaces over its existing schema.

It may:

- Query existing workout tables
- Translate ORM entities into canonical history
- Persist methodology state in an existing JSON/document column
- Use a remote API rather than a local database
- Combine multiple data sources

Caudex must not require copying all host workout data into a Caudex-owned database.

## Database-specific expectations

### SQLite

Suitable for native, desktop, local server, and some mobile integrations.

The adapter may provide:

- Reference schema
- Forward migrations
- Prepared statements
- Explicit busy handling
- Transactional state compare-and-set
- File and in-memory test modes

SQLite is not linked by the core or npm/WASM package.

### PostgreSQL

Suitable for server and hosted applications.

The adapter may provide:

- SQL migrations
- Optimistic revision updates
- Transactional accepted-result persistence
- Connection-pool integration through host-supplied clients
- No ownership of authentication or tenancy rules

The first PostgreSQL adapter should avoid requiring one specific ORM. A low-level driver adapter and ORM examples are preferable to embedding an ORM in the shared contract.

### IndexedDB

Suitable for browser-local and offline-first applications.

The adapter may provide:

- Object-store versioning
- Indexed history retrieval
- Transactional state and journal writes where supported
- Browser lifecycle and quota guidance
- No dependency from the WebAssembly core

### Custom repositories

Applications can implement the narrow capability interfaces over:

- DynamoDB
- MongoDB
- Cloudflare Durable Objects
- REST or GraphQL APIs
- Event streams
- Files
- In-memory maps
- Existing domain repositories

A custom-repository guide and contract test kit are required before these interfaces are declared stable.

### No persistence

Call the core directly.

This must remain a first-class documented workflow rather than a degraded special case.

## Canonical model versus storage model

The canonical request/result model is a computation and interoperability contract.

It is not:

- A normalized SQL schema
- An ORM entity model
- A required document layout
- A synchronization protocol
- A database migration format

Adapters may denormalize, index, cache, or split canonical values as needed.

Every adapter must reconstruct semantically equivalent canonical inputs before invoking the core.

## Versioning

Version these independently:

- Core engine
- Canonical request/result schema
- Methodology implementation
- Methodology state schema
- Persistence capability contract
- Each database adapter
- Each adapter's reference schema and migrations

A core release must not require a database migration.

A persistence-adapter migration must not change recommendation semantics.

An adapter must reject or migrate unsupported methodology state versions explicitly.

## Testing

### Core tests

Core CI must prove that no persistence dependency is linked or imported.

### Adapter contract tests

The persistence integration package provides reusable tests for:

- Catalog loading
- History loading and ordering
- Missing records
- Methodology-state round trips
- Compare-and-set success
- Compare-and-set conflict
- Accepted-result journaling
- Transaction rollback where advertised
- Versioned state
- Canonical mapping equivalence

Database-specific packages run the same applicable contract tests.

### Cross-mode equivalence

For a canonical fixture:

1. Direct snapshot mode produces a result.
2. Each adapter loads data representing the same fixture.
3. The integration layer constructs the canonical request.
4. The result and fingerprints match direct snapshot mode.

This proves storage choice does not affect recommendation behavior.

## Repository structure

Optional adapters live outside the core:

```text
caudex/
├── core/
├── methodologies/
├── bindings/
├── packages/
│   ├── npm/
│   │   └── workout-engine/
│   └── persistence/
│       ├── contract/
│       ├── indexeddb/
│       ├── sqlite/
│       └── postgres/
└── examples/
    ├── no-persistence/
    ├── custom-repository/
    ├── indexeddb/
    ├── sqlite/
    └── postgres/
```

These directories are created only when the corresponding adapter is implemented.

## Enforcement

- `core/` may not import adapter packages, database modules, repository contracts, or migration code.
- `@caudex-workout/engine` may not depend on any persistence package or database driver.
- Methodology interfaces may not accept repositories or database handles.
- Core operations may not implicitly load history or state.
- Persistence only occurs after an explicit host action.
- Adapter failures remain adapter/runtime errors, not methodology validation issues.
- Database-specific types do not appear in canonical schemas.
- Reference schemas are documented as optional and adapter-private.
- Every adapter passes canonical-equivalence tests.
- Documentation always presents direct snapshot mode before repository orchestration.

## Consequences

### Benefits

- Existing applications can adopt Caudex without replacing their database.
- Browser, server, mobile, native, and test environments use the same core.
- The npm/WASM package remains small and broadly portable.
- Applications can adopt only methodology-state persistence.
- Developers can evaluate Caudex with no setup.
- Database integrations can evolve and release independently.
- Storage choice cannot silently alter recommendations.
- Custom repositories remain practical.

### Costs

- Hosts must map their data to canonical snapshots.
- Optional adapter packages create additional maintenance.
- The persistence contract must avoid lowest-common-denominator design.
- Cross-database behavior cannot be perfectly identical.
- Reference schemas and custom mappings both require documentation.

### Risks

- A convenience adapter may gradually become a required application framework.
- The capability interfaces may become too broad.
- Database-specific behavior may leak into common contracts.
- Developers may confuse reference schemas with the core data model.
- Automatic persistence may blur the recommendation-acceptance boundary.

The enforcement and testing rules above are intended to prevent these outcomes.

## Rejected alternatives

### Put a repository port in the core

Rejected. Even an abstract repository would make core execution depend on persistence orchestration and would complicate WebAssembly and pure tests.

### Make SQLite the default core repository

Rejected. SQLite is valuable as an optional adapter but inappropriate as a universal dependency.

### Standardize one physical database schema

Rejected. Established applications need to map existing models, and different databases require different physical designs.

### Automatically save proposed methodology state

Rejected. Calculation, acceptance, and persistence are separate actions.

### Implement adapters inside `@caudex-workout/engine`

Rejected. Database drivers and environment-specific behavior would increase package size, compatibility risk, and install complexity.

### Require persistence adapters

Rejected. Direct snapshot mode is complete and first class.
