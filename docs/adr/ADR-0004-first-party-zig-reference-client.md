# ADR-0004: First-Party Zig Reference Client in the Workout Engine Monorepo

- **Status:** Accepted
- **Date:** 2026-07-26
- **Decision owners:** Caudex Workout Engine maintainers
- **Extends:** ADR-0002 and ADR-0003
- **Preserves:** ADR-0001's functional-core discipline, explicit idiomatic Zig
  shell, deterministic calculations, and rejection of generalized
  functional-programming frameworks
- **Implementation plan:** [First-party Zig reference-client implementation
  plan](../implementation-plan.md)

## Context

Caudex Workout Engine v0.1 is a stateless, library-first recommendation and
performance-evaluation engine. It exposes a typed Zig package, canonical
protocols, C and WebAssembly boundaries, two methodologies, and optional
persistence capabilities. Hosts own user interfaces, application lifecycle,
tracking state, and persistence.

The repository also contains a Zig SQLite adapter implementation. It currently
exists as a build-local test module rather than a distributable public Zig
package. It can open and migrate a database, load catalog and completed-history
snapshots, append completed workouts, compare-and-set methodology state, and
close. It does not expose the command/query surface needed by a complete
workout tracker.

A first-party client is the next reference integration. It must demonstrate how
a native Zig host composes public engine and persistence packages without
turning terminal or storage concerns into core behavior. It should also be
useful enough for maintainers and users to log real local workouts.

The current public surface does not yet support the full requested tracker.
There are no public operations for athletes, equipment records, active
workouts, workout exercises and sets, corrections, cancellation, archival, or
tracker-oriented queries. Those capabilities must be introduced deliberately
through public package contracts before the client uses them. Monorepo-relative
reachability is not publication.

## Decision

Caudex will provide a first-party reference workout client written entirely in
Zig.

- The terminal command is `caudex`.
- The application package is `caudex-cli`.
- The source lives under `apps/caudex-cli/`.
- The application is physically in the monorepo but architecturally external
  to the engine and persistence adapter.
- It consumes only named, intentionally public Zig packages.
- It starts as a one-shot, line-oriented CLI, matures as a scriptable
  integration, and only then gains a full TUI.
- The line CLI remains supported after the TUI ships.

The dependency direction is:

```text
caudex-cli
├── client-owned argument, output, configuration, and TUI code
├── public SQLite adapter package
├── public tracking/application package, when introduced
└── public caudex engine package
        └── deterministic recommendation and evaluation core
```

No dependency points from an engine or adapter package into the application.

## Architectural boundaries

The engine remains the deterministic calculation core. It accepts explicit
snapshots and returns proposals, evaluations, issues, explanations, and
proposed methodology state. It does not read process arguments, terminals,
files, environment variables, clocks, or databases.

Reusable tracker decisions and their public command/query contracts belong in
a separate engine-owned public application package only when required by a
focused issue. That package may orchestrate deterministic decisions but must
not absorb terminal behavior. Its exact name is resolved in Phase 0; the
working name in the implementation plan is `caudex_tracking`.

The public SQLite adapter owns its schema, migrations, transactions, prepared
statements, row mapping, compatibility checks, and durable command handling. It
must remain useful to third-party Zig hosts and must not contain CLI defaults,
paths, prompts, output, aliases, or terminal behavior.

The client owns:

- Process arguments and environment inspection
- Standard input, output, and error
- Output-format and color selection
- Platform database and configuration locations
- Explicit command IDs, timestamps, and retry inputs
- Translation from public results to exit status
- Human formatting and stable machine encoding
- Reference resolution and client-level use-case orchestration
- Terminal lifecycle, events, display, signals, and restoration
- TUI presentation state

## Meaning of “external reference client”

“External” describes dependency and authority, not repository location.

The client is built as if it were a third-party Zig consumer:

- It imports only named packages supplied in its build module import table.
- It cannot import repository-relative engine, adapter, migration, fixture, or
  ABI files.
- It receives no special mutation API unavailable to other Zig hosts.
- It demonstrates supported integration rather than privileged access.
- Public gaps are fixed at the owning boundary before client work proceeds.

Build and architecture tests enforce this posture.

## Monorepo placement and build graph

Implementation begins with only files needed by the first vertical slice:

```text
apps/
└── caudex-cli/
    ├── README.md
    └── src/
        └── main.zig
```

Later issues may add `app.zig`, `command_line/`, `output/`, `tui/`, and `tests/`
when concrete responsibilities earn those boundaries.

The root `build.zig` remains the single authoritative build graph and the root
`build.zig.zon` remains the single dependency manifest initially. It registers
public modules and exposes focused steps such as `zig build caudex-cli` and
`zig build test-caudex-cli`. The root install step installs the `caudex`
executable once it is an intentional release artifact.

An app-local `build.zig` or `build.zig.zon` is not created initially. A second
manifest is justified only if the app later requires independent source
distribution, dependency resolution, or release cadence that cannot be
represented cleanly by the root graph. Focused tests do not by themselves
justify duplicate manifests.

## Public dependency rules

The allowed imports are recorded explicitly in the build:

- `caudex`: public Workout Engine package
- `caudex_persistence`: public database-independent persistence/tracking
  contracts, after Phase 0 naming review
- `caudex_sqlite`: public SQLite adapter root, after Phase 0 publication
- Zig standard library
- A future application-owned terminal facade

The client must not import:

- Private files under `src/`
- Internal SQLite modules or migration resources
- Private command services or query implementations
- Adapter-private tables, SQL, or row representations
- Test fixtures or persistence contract-test internals
- `c_api.zig`, `wasm_api.zig`, or private ABI implementation
- Any path merely because it is reachable within the checkout

The app does not use the C ABI when the typed Zig API exists.

## SQLite adapter decision

The repository has a Zig SQLite implementation but not a public distributable
Zig SQLite package. Before the CLI depends on it, Phase 0 will:

1. Define and register a named public SQLite package root.
2. Include the required adapter sources and migrations in the appropriate Zig
   package allowlist or define a separately consumable package.
3. Preserve current open/create, automatic forward migration, file and
   in-memory operation, prepared SQL, busy handling, and close semantics.
4. Add public metadata and compatibility inspection.
5. Distinguish open, migration, busy, corruption, unsupported/newer-schema,
   and general storage failures.
6. Expose tracker application construction or attachment only after the public
   tracking contracts exist.
7. Keep raw database handles, writable tables, migrations, and SQL private.

The default lifecycle is:

```text
resolve path
    ↓
open or create with explicit options
    ↓
check compatibility and run supported forward migrations
    ↓
obtain public metadata and application capabilities
    ↓
execute commands and queries
    ↓
close and release resources
```

Integrity checking, backup, and restore belong at this reusable adapter
boundary only when they can be made safe and useful for any Zig host. They are
not prerequisites for the first vertical slice.

The adapter is not customized around `caudex-cli`. CLI paths, prompts, aliases,
configuration, formatting, and terminal behavior remain in the app.

## Line-oriented CLI principles

Phase 1 is a conventional one-shot process, not a TUI or interactive REPL.

- One invocation performs one coherent operation.
- Successful requested data goes to stdout.
- Diagnostics and errors go to stderr.
- Commands do not prompt unexpectedly.
- Potentially interactive commands advertise that behavior and provide
  non-interactive alternatives such as `--yes`.
- Piped output contains no unsolicited ANSI sequences.
- `--format human|json` selects distinct output contracts where appropriate.
- `--quiet` suppresses nonessential success text but not errors.
- Structured batch input may use stdin only for commands that document it.
- Broken pipes are normal process outcomes and do not produce noisy diagnostics.
- Signals and interruptions leave committed database state consistent.
- Retries use explicit or safely generated command IDs where the public
  command API provides idempotency.

Human convenience syntax must translate into explicit public commands. It must
not invent domain values that cannot be represented reliably.

## Command grammar

The grammar uses stable nouns followed by verbs:

```text
caudex <global-options> <noun> <verb> [arguments] [options]
```

Global commands may omit a noun:

```text
caudex help
caudex version
caudex doctor
caudex completion <shell>
caudex tui
```

Every meaningful command level supports `--help`. Long names form the
documented compatibility surface; concise aliases are additive conveniences.
Scripts can always pass explicit IDs. Friendly references resolve exact ID,
exact alias/name, then documented search; multiple matches return a structured
ambiguity error and never guess.

The exact initial tree is capability-gated in the implementation plan. A
command is not documented as available until a public package supports it.

## Active-workout resolution policy

Separate processes do not share hidden in-memory workout state.

Commands that operate on a workout resolve it as follows:

1. `--workout <id>` selects that public engine-owned workout explicitly.
2. Without it, query active workouts for the selected athlete/scope.
3. Exactly one active workout is selected.
4. None produces a documented not-found result.
5. More than one produces a structured ambiguity result listing stable IDs and
   instructing the user to pass `--workout`.

The client does not persist an undocumented “current workout” pointer.
A future explicit default-selection preference is allowed only if documented,
inspectable, reversible, and never a second source of workout-domain truth.

## Standard streams and exit-code policy

The initial stable exit classes are:

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 2 | CLI syntax, option, or structured-input error |
| 3 | Public validation or rejected domain decision |
| 4 | Requested entity not found |
| 5 | Ambiguous reference or required selection |
| 6 | Revision, idempotency, or other conflict |
| 7 | Database busy or temporarily unavailable |
| 8 | Database incompatible, corrupt, or migration failed |
| 70 | Internal/runtime failure |
| 130 | Interrupted by the user where the platform provides SIGINT semantics |

Platform process conventions may constrain signal-derived values, but published
non-signal mappings remain stable within a major client version. JSON errors
include a stable code, category, message, and optional details. Human error
wording may improve during 0.x without changing its code or exit class.

## Human and machine output policy

Human output favors concise tables and actionable errors. It may adapt to
terminal width and evolve during 0.x.

JSON output:

- Uses UTF-8 JSON on stdout.
- Contains stable identifiers even when friendly names are present.
- Has an explicit document kind and schema version.
- Uses exact decimal strings and unit codes.
- Does not mix progress or diagnostics into stdout.
- Receives stronger compatibility guarantees than human decoration.

User-controlled names and notes are escaped or sanitized before terminal
rendering so control sequences cannot alter the terminal. `NO_COLOR`, a
non-terminal stdout, or explicit `--color never` disables ANSI styling.

## Shared client application layer

The line CLI and TUI share an application-owned orchestration layer when real
duplication appears. It may implement client use cases such as:

- Resolve an exercise reference
- Resolve the only active workout
- Start a workout with explicit IDs and time
- Log a set
- Load history and last performance
- Correct a historical set

This layer composes public queries and commands. It does not:

- Reimplement engine validation or state transitions
- Interpret private domain events
- Mutate SQLite
- Store workout-domain state
- Know about CLI tokens or TUI widgets

Line parsing and TUI event handling adapt into the same typed client use cases.

## TUI architecture

The TUI is implemented only after the line CLI's command, error, JSON, and
persistence integration are stable.

Its conceptual flow is:

```text
terminal event
    ↓
explicit update function
    ↓
client application action
    ↓
public command or query
    ↓
new presentation state
    ↓
render model
    ↓
terminal output
```

The TUI uses an explicit Zig event loop. Deterministic update and render-model
functions are preferred where practical, but the project does not adopt a
generalized Elm, Redux, free-effect, or UI framework.

The terminal boundary owns:

- Raw-mode entry and exit
- Optional alternate screen
- Signal and panic restoration
- Input decoding and resize events
- Color/capability detection and `NO_COLOR`
- Unicode display-width policy
- Bounded render writes and broken-pipe handling

The first TUI is keyboard-only operable, has discoverable help, does not rely
on color alone, and remains testable with synthetic events and an in-memory
render target. Long-running operations are explicit actions; asynchronous
complexity is introduced only when a measured operation would otherwise block
interaction.

## Terminal dependency criteria

Ordinary argument parsing and formatting use Zig and its standard library.

Before adopting a terminal/TUI dependency, a focused issue records:

- Concrete functionality that would otherwise be implemented
- License and notice obligations
- Pinned revision or release and content hash
- Maintenance activity and release history
- Supported operating systems and terminals
- Unicode, resize, signal, and input behavior
- Ability to test without a live terminal
- Binary-size and startup effects
- An application-owned facade preventing leakage into engine public APIs

If no candidate meets these criteria, the first TUI foundation implements the
small terminal subset directly behind that facade.

## Zig-only dependency policy

All client and TUI production implementation is Zig. The client does not add
JavaScript, TypeScript, Node.js, npm, or npm packages.

Third-party Zig dependencies are exceptional, pinned, license-reviewed,
platform-reviewed, testable, and isolated behind application-owned boundaries.
They never leak into engine, persistence, or tracker public declarations.

## Configuration and local data policy

Database selection precedence is:

1. Explicit `--database <path>`
2. A documented `CAUDEX_DATABASE` environment override
3. Client configuration preference
4. Platform data-directory default

The platform default follows appropriate XDG, macOS application-support, and
Windows local-application-data conventions. `caudex config path` and
`caudex database info` make resolution inspectable.

Client configuration may store presentation units, color, theme, table
preferences, and other non-domain preferences. It must not duplicate active
workouts, sets, history, engine aliases, or other engine-owned workout data.
Writes are atomic and use restrictive permissions where the platform permits.

Database switching is explicit. Backup/export never silently follows or
overwrites a symlink or existing destination without documented opt-in.
Diagnostics avoid secrets and unnecessary paths.

## Testing strategy

The client uses layered tests:

- Unit tests for arguments, shorthand metrics, path resolution, active-workout
  selection, output, exit mappings, deterministic TUI update, and render models.
- Integration tests run the compiled binary against temporary file databases,
  across multiple processes, and assert stdout, stderr, status, and public API
  state.
- Architecture tests permit only named public imports and keep private files
  outside app visibility.
- Selective golden tests cover help, JSON documents, stable errors,
  completion scripts, and important TUI render states.
- End-to-end scenarios cover catalog setup, workout execution, short
  completion, history, correction, retries, ambiguity, interruption, and the
  same live-workout flow through the TUI.

Tests inspect state through public packages, never raw SQL.

## Versioning and compatibility

These dimensions evolve independently:

- `caudex-cli` semantic version
- Public engine Zig API
- Public tracking/application contract
- Public SQLite adapter API
- SQLite adapter schema and migration compatibility
- CLI command grammar
- JSON output schema
- Exit-code classes
- Human output
- TUI keybindings and layout

During 0.x, human formatting and TUI layout may evolve. Machine-readable JSON,
stable error codes, and exit classes receive stronger compatibility treatment.
Breaking command or JSON changes require release notes and compatibility tests.

`caudex version --format json` eventually reports client, engine, persistence
contract, SQLite adapter, database schema, and supported command/query protocol
versions. It must not imply compatibility based on coincidentally matching
numbers.

## Consequences

### Benefits

- Developers get a native, realistic public-package integration example.
- The engine remains independently embeddable and storage agnostic.
- Public package gaps are discovered through a demanding first-party host.
- Line commands support people, scripts, pipes, aliases, and automation.
- The TUI reuses the same public operations and client orchestration.
- Third-party Zig hosts benefit from adapter improvements made at reusable
  boundaries.

### Costs

- Full tracking requires new public capabilities before many client features.
- Package-boundary enforcement adds build and architecture tests.
- A durable CLI grammar and JSON contract require compatibility discipline.
- Terminal lifecycle and cross-platform packaging are significant maintenance
  work.
- The repository will support an application in addition to library artifacts.

### Risks

- Client pressure could expand the recommendation engine into a tracker core.
- Build-local files could be mistaken for public packages.
- Convenience parsing could duplicate domain rules.
- CLI and TUI behavior could diverge.
- A terminal dependency could become unmaintained or leak across boundaries.
- Human-friendly resolution could guess incorrectly.
- Hidden client state could compete with engine-owned workout state.

The phased capability gates, named imports, contract tests, explicit ambiguity
policy, and shared client application layer mitigate these risks.

## Enforcement rules

- `apps/caudex-cli` imports only named public modules.
- App build modules receive no repository root path or private module import.
- The client never executes SQL or receives a raw SQLite handle.
- The client never interprets migrations or private domain events.
- Engine and adapter additions are separate focused issues.
- Terminal, parsing, rendering, navigation, paths, and client configuration
  never enter the core.
- CLI-specific behavior never enters the public SQLite adapter.
- New dependencies require a recorded license and suitability review.
- No production JavaScript, TypeScript, Node.js, or npm is added for the client.
- Unsupported commands remain absent rather than bypassing public boundaries.
- Architecture tests and package smoke tests are release gates.

## Rejected alternatives

### Put the CLI in the engine package

Rejected. Process and terminal effects would blur the stateless library
boundary and burden library consumers with application concerns.

### Access SQLite directly from the client

Rejected. Raw writes would bypass invariants, idempotency, migrations,
compatibility checks, and third-party-host contracts.

### Add CLI-specific repositories inside the core

Rejected. Repositories and client use cases are effects in the imperative shell,
not deterministic recommendation logic.

### Implement the client with Node.js or npm

Rejected. The reference client is specifically a typed Zig integration and
must not require the JavaScript toolchain.

### Implement the TUI before a stable line CLI

Rejected. It would delay the smallest public-package proof and couple domain
coverage to terminal complexity.

### Make the TUI spawn the line CLI

Rejected for normal operations. It adds parsing, process, performance, and
error-translation boundaries instead of using the same public Zig packages.

### Build line CLI and TUI as unrelated clients

Rejected. Duplicated resolution and orchestration would drift even if both used
public packages.

### Expose private modules because the client shares the monorepo

Rejected. Physical colocation does not make an implementation contract public.

### Create a generalized UI framework first

Rejected. Concrete screens and input behavior must establish the smallest
useful abstractions.

### Add a browser client in this phase

Rejected. Browser integration remains a later, separate reference-client phase
and does not justify JavaScript or npm work here.

### Require the C ABI from the Zig client

Rejected. The typed Zig API is clearer, safer, and avoids serialization and
ownership overhead.

### Persist a hidden current-workout pointer outside the engine

Rejected without a documented future need. Active-workout queries and explicit
IDs prevent a second source of domain state.

### Duplicate a package manifest immediately

Rejected. A single root graph provides focused builds without split dependency
resolution. Independent distribution may justify reassessment later.

