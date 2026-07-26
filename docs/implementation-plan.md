# Caudex First-Party Zig Reference Client Implementation Plan

- **Status:** Planned
- **Date:** 2026-07-26
- **Architecture:** [ADR-0004](adr/ADR-0004-first-party-zig-reference-client.md)
- **Predecessor:** [Completed v0.1 library-first implementation
  plan](implementation-plans/completed/v0.1-library-first-implementation-plan.md)

## 1. Product definition

`caudex-cli` is the first-party Zig reference client for Caudex Workout Engine.
It is a useful, local workout tracker and an executable example of composing
Caudex's intentionally public Zig packages.

The installed command is:

```text
caudex
```

The package is:

```text
caudex-cli
```

The client is external in architecture and colocated in the monorepo. It starts
with stable one-shot commands, grows into a strong shell integration, and then
adds a full TUI without retiring the scriptable interface.

## 2. Repository baseline

Planning is based on the completed repository, not the old plan's projected
tree.

### 2.1 Public boundaries today

- `caudex` is the only root `b.addModule` package and the only Zig module in the
  tagged source-package allowlist.
- `caudex` exports typed recommendation/evaluation, canonical models and JSON,
  training snapshots, primitives, methodologies, diagnostics, filtering,
  ordering, history, duration, and load arithmetic.
- `adapters/persistence.zig` defines useful Zig capability contracts, but the
  root build creates it only as the build-local module `persistence`.
- `adapters/sqlite.zig` is tested as the build-local module `sqlite`; neither it
  nor its migrations are included in `build.zig.zon`'s distributable paths.
- JavaScript persistence packages do not satisfy a Zig-only application.

### 2.2 Existing SQLite lifecycle

The adapter currently supports:

- Open/create from a sentinel path
- Busy-timeout option
- Automatic forward migration to schema version 1
- Catalog replacement and loading
- Completed-workout append and history loading
- Methodology-state load and compare-and-set
- File and `:memory:` databases
- Close

It does not yet provide:

- A distributable public Zig package
- Explicit public metadata/compatibility inspection
- Detailed busy, corruption, migration, and newer-schema errors
- Tracker application-service construction
- Active-workout or catalog-management commands and queries
- Integrity, backup, or restore APIs

### 2.3 Public capability gap

The current engine represents completed workout snapshots for recommendation
and evaluation. It does not implement a mutable tracking domain. The client
cannot legitimately implement the illustrative command tree until public
packages add the relevant operations.

Each requested feature is classified as:

1. **Engine/application contract:** reusable workout rules, commands, queries,
   idempotency, revisions, and stable issues.
2. **SQLite adapter:** durable implementation, migrations, transactions,
   indexed queries, integrity, backup, or compatibility.
3. **Client:** parsing, resolution, presentation, configuration, paths,
   prompts, terminal behavior, and shared use-case orchestration.
4. **Out of scope:** capabilities unsupported by the engine and not approved as
   a focused engine expansion.

The client never fills category 1 or 2 gaps with raw SQL or duplicated rules.

## 3. Scope

### 3.1 Included

- Public Zig persistence and SQLite package readiness
- A line-oriented CLI with human, quiet, and JSON output
- Local catalog and workout tracking supported by approved public contracts
- Active-workout ambiguity handling across processes
- History, last-performance, and correction workflows
- Shell completion, command docs, batch input, and diagnostics
- A full Zig TUI focused first on live workout execution
- Release packaging and third-party Zig integration documentation
- Measured, justified public engine/adapter improvements required by the client

### 3.2 Excluded

- Browser reference client
- JavaScript, TypeScript, Node.js, npm wrappers, or npm packages
- Mobile, desktop GUI, hosted service, accounts, billing, or cloud sync
- A generic GUI toolkit or plugin marketplace
- Direct table editing or an alternate workout schema
- Workout generation, periodization, recovery modeling, or unsupported
  recommendation/methodology UI
- Cardio, mobility, medical, or rehabilitation behavior
- A TUI framework before concrete terminal needs exist

## 4. Proposed monorepo structure

Create only the files required by the current issue:

```text
caudex/
├── build.zig
├── build.zig.zon
├── adapters/
│   ├── persistence.zig
│   ├── sqlite.zig
│   └── sqlite/
├── apps/
│   └── caudex-cli/
│       ├── README.md
│       └── src/
│           └── main.zig
└── src/
    └── root.zig
```

Expected growth after concrete features exist:

```text
apps/caudex-cli/
├── README.md
├── src/
│   ├── main.zig
│   ├── app.zig
│   ├── command_line/
│   ├── output/
│   └── tui/
└── tests/
```

The root build graph owns app build, install, run, and focused test steps.
Initially there is no app-local build file or duplicate package manifest.

The Phase 0 package review decides whether adapter source remains under
`adapters/` or moves to a package subtree. The decision is based on package
publication and visibility, not aesthetic directory symmetry.

## 5. Public dependency diagram

```text
                          ┌──────────────────────────┐
                          │ apps/caudex-cli          │
                          │ args, output, config, UI │
                          └────────────┬─────────────┘
                                       │ named public imports only
                  ┌────────────────────┼────────────────────┐
                  ▼                    ▼                    ▼
       ┌──────────────────┐ ┌────────────────────┐ ┌──────────────────┐
       │ caudex_tracking  │ │ caudex_sqlite      │ │ caudex           │
       │ commands/queries │ │ durable adapter    │ │ recommendation   │
       └────────┬─────────┘ └──────────┬─────────┘ │ and evaluation   │
                │                      │           └──────────────────┘
                └──────────┬───────────┘
                           ▼
                 ┌────────────────────┐
                 │ caudex_persistence │
                 │ host contracts     │
                 └─────────┬──────────┘
                           ▼
                 ┌────────────────────┐
                 │ caudex public data │
                 └────────────────────┘
```

`caudex_tracking` is a working package name, not an authorized implementation
detail. CWE-103 resolves its need and name without reviving ADR-0001's
superseded persistence-owned core.

## 6. Build and package policy

- Root `build.zig` registers every public module explicitly.
- The app module import table contains only approved package names.
- Private implementation roots are not supplied to the app.
- Root steps provide `caudex-cli`, `run-caudex-cli`, and `test-caudex-cli`.
- `zig build` remains simple and installs intentional release artifacts.
- Adapter consumer smoke tests copy only declared package paths.
- A future app manifest requires a concrete independent-distribution need.
- System SQLite remains the initial driver dependency; supported platforms and
  development headers are documented.

## 7. Command grammar principles

Syntax:

```text
caudex [global-options] <noun> <verb> [arguments] [options]
```

Principles:

- Long noun/verb forms are canonical; aliases never replace them.
- `--help` works at the root, noun, and command levels.
- Explicit IDs work everywhere relevant.
- Friendly lookup checks exact ID, exact alias/name, then documented search.
- Ambiguous lookup reports candidates and exits 5.
- IDs are always present in JSON entities.
- Global `--database`, `--format`, `--color`, `--quiet`, and scope selection
  precede nouns and have documented precedence.
- Commands do not prompt unless explicitly interactive.
- Destructive commands use confirmation on a TTY and `--yes` for automation.
- Metric shorthand maps to exact public measurements and rejects ambiguity.
- One invocation performs one coherent operation.

## 8. Capability-gated command tree

The tree is a target, not evidence that the current engine supports every
command.

### 8.1 Walking skeleton

```text
caudex --help
caudex version
caudex database info
```

### 8.2 Essential tracking

```text
caudex workout start
caudex workout show [--workout ID]
caudex workout add-exercise EXERCISE [--workout ID]
caudex set log [--workout ID] [--exercise ID] [METRICS...]
caudex set skip [--workout ID] [--set ID]
caudex set reopen [--workout ID] --set ID
caudex workout finish [--workout ID]
caudex workout cancel [--workout ID] [--yes]
```

### 8.3 Catalog and history

```text
caudex athlete create|list|show
caudex equipment add|list|edit|archive|restore
caudex exercise add|list|show|edit|archive|restore
caudex history list|show|exercise|correct-set
```

Athlete and equipment commands ship only if accepted public models require
them. Otherwise the CLI uses a documented host-scope ID and equipment IDs
embedded in public exercises.

### 8.4 Mature integration

```text
caudex completion bash|zsh|fish
caudex config path|show|set
caudex database info|check|backup|restore
caudex batch
caudex doctor
caudex tui
```

Import/export commands are added only for stable public engine formats. Backup
is not described as export.

### 8.5 Shorthand

Frequent commands may gain aliases after usability tests. Examples such as
`caudex set log 70kg 8r @2rir` are accepted only when every token maps
unambiguously to exact public metric code, amount, and unit. Long explicit
options remain available.

## 9. Active-workout selection

Client selection is a pure, unit-tested policy over public query results:

```text
explicit --workout ID ──► use or not-found
no explicit ID
    ├── zero active ─────► not-found
    ├── one active ──────► use it
    └── multiple ────────► ambiguity with candidate IDs
```

The selected athlete or scope is explicit or comes from inspectable
configuration. The client stores no domain current-workout pointer.

## 10. Streams, JSON, and exit contracts

### 10.1 Standard streams

- Requested successful output: stdout
- Diagnostics, warnings, and errors: stderr
- No unsolicited ANSI when stdout/stderr is not an appropriate terminal
- No partial success JSON followed by plain-text errors
- Clean `EPIPE` handling
- Structured stdin accepted only by documented commands

### 10.2 Formats

`--format human` is the default for terminals. `--format json` emits one
versioned JSON document per ordinary invocation. Batch mode may use documented
newline-delimited JSON.

Example envelope:

```json
{
  "schemaVersion": 1,
  "kind": "caudex.workout.show",
  "data": {
    "id": "workout-01...",
    "status": "in_progress"
  }
}
```

Example error:

```json
{
  "schemaVersion": 1,
  "kind": "caudex.error",
  "error": {
    "code": "client.reference.ambiguous",
    "category": "ambiguity",
    "message": "More than one workout is active.",
    "details": {
      "workoutIds": ["workout-a", "workout-b"]
    }
  }
}
```

Exact measurements remain strings plus units. JSON key order may be
deterministic for golden tests but consumers must not rely on it.

### 10.3 Exit codes

| Code | Contract |
| ---: | --- |
| 0 | Success |
| 2 | Invocation/input syntax |
| 3 | Validation/domain rejection |
| 4 | Not found |
| 5 | Ambiguous selection |
| 6 | Revision/idempotency conflict |
| 7 | Busy/temporarily unavailable |
| 8 | Migration/corruption/incompatibility |
| 70 | Internal/runtime failure |
| 130 | SIGINT-style interruption where applicable |

Exit mapping is centralized and golden-tested. Public issue codes are preserved
in JSON rather than inferred from human strings.

## 11. Configuration and database-path policy

Database precedence:

1. `--database`
2. `CAUDEX_DATABASE`
3. client configuration
4. platform data directory

Defaults:

- Unix-like/XDG: `$XDG_DATA_HOME/caudex/caudex.sqlite`, otherwise the
  documented user data fallback
- macOS: user Application Support under `Caudex`
- Windows: user-local application data under `Caudex`

Implementation uses platform APIs and safe path joining, never shell command
construction. Relative explicit paths are allowed but shown clearly by
diagnostic commands.

Configuration contains only client preferences:

- Default host scope/athlete selector
- Display units
- Human table and color preferences
- Future theme/keybinding preferences

It never stores workouts, sets, history, exercise aliases already owned by the
engine, or hidden domain selection state. Writes use a temporary sibling,
flush where appropriate, and atomic replacement. Permissions are restrictive
where controllable.

## 12. Testing strategy

### 12.1 Unit tests

- Tokenization and command parsing
- Help routing and option precedence
- Exact unit/metric shorthand
- Human tables and terminal escaping
- JSON encoding and error envelopes
- Platform database-path resolution
- Active-workout selection
- Exit mapping
- Config parsing and atomic-write planning
- TUI event/update functions
- TUI render models and width behavior

### 12.2 Integration tests

Compile and run `caudex` as a subprocess against temporary SQLite files:

- Assert stdout, stderr, and exit status separately.
- Execute related operations in separate processes.
- Verify persisted results through public APIs.
- Cover validation, ambiguity, conflicts, busy databases, newer schema, and
  failed/interrupted operations.
- Run with piped stdout, closed stdout, empty environment overrides, and
  non-terminal descriptors.
- Never inspect or mutate tables directly.

### 12.3 Architecture tests

- Record allowed app imports by package name.
- Do not provide private modules to the app build.
- Scan app imports for relative traversal and forbidden internal names.
- Build from a package view containing only declared public paths.
- Deliberately review additions to `src/root.zig` and all adapter roots.

### 12.4 Golden tests

Use selective, reviewed fixtures for:

- Root and command help
- JSON output and stable JSON errors
- Exit-code examples
- Completion scripts
- Important TUI render states

Avoid freezing every human sentence, spacing choice, or adaptive table.

### 12.5 Required end-to-end scenarios

1. Create/open a local database.
2. Create required public catalog records.
3. Start a workout.
4. Add exercises.
5. Log several sets.
6. Complete a short workout without treating shortness as failure.
7. Query it from a new process.
8. Display last exercise performance.
9. Correct a historical mistake.
10. Retry an idempotent command without duplication.
11. Create two active workouts and verify the client refuses to guess.
12. Run the same live-workout flow through the TUI.

## 13. Release and packaging

- Root builds produce the `caudex` executable for supported targets.
- A release issue defines the initial target matrix after SQLite and terminal
  support are verified.
- Artifacts include license, notices, checksums, build metadata, and install
  instructions.
- Homebrew, system packages, or other channels are evaluated only after direct
  archives are reproducible.
- Client and library releases may share repository tags during 0.x but publish
  independent version fields.
- Database migrations remain adapter-owned, immutable after release, and tested
  from every supported predecessor.
- Release smoke tests run from unpacked artifacts with a temporary user data
  directory.

## 14. Documentation strategy

Documentation grows with shipped capability:

- `apps/caudex-cli/README.md`: install, first workout, database path, and scope
- Command reference and exit codes
- Shell aliases, pipes, JSON, cron, and batch examples
- Database metadata, backup, restore, and compatibility guidance
- TUI keybindings and terminal recovery
- Architecture guide for third-party Zig hosts
- Explicit public-package dependency example
- Guide to building another client by reusing engine/adapter packages rather
  than copying CLI presentation
- Troubleshooting and bug-report diagnostics

Generated command docs and man pages come from the same command metadata only
after the command tree is stable enough to justify generation.

## 15. Compatibility policy

| Boundary | 0.x policy |
| --- | --- |
| Client semantic version | SemVer with explicit breaking-change notes |
| Engine Zig API | Engine release/version policy |
| Tracking contract | Independently versioned public contract |
| SQLite adapter API | Independently documented source compatibility |
| Database schema | Forward migration; reject unsupported newer versions |
| CLI grammar | Long forms stable within documented support window |
| JSON output | Versioned; breaking changes require schema/version change |
| Exit codes | Stable classes with compatibility tests |
| Human output | May improve without compatibility promise |
| TUI keys/layout | Documented but allowed to evolve during early 0.x |

`version` and `doctor` report dimensions separately.

## 16. Performance and startup

Establish baselines, not speculative optimization:

- Process startup to first output
- Database open plus no-op migration check
- `database info`
- Workout show and set log
- Exercise search
- Last-performance query
- Paginated history list
- TUI initial render and input-to-render latency
- Representative large local history

Initial budgets are measured in CWE-154 before release. Common repeated workout
commands should feel immediate on supported local hardware. Queries should use
adapter-owned indexes and bounds; the client must not load the entire database
or replay all history when a public indexed query exists.

Profiling precedes caching. Client caches cannot become workout-domain truth.

## 17. Security and data integrity

- Treat database, config, import, export, and backup paths as untrusted input.
- Never form shell commands or SQL from user values.
- Use prepared/bound SQL only inside the adapter.
- Apply restrictive file permissions when creating local data where supported.
- Document symlink behavior; never silently overwrite backup/export targets.
- Atomically replace client configuration.
- Escape terminal control sequences in names and notes.
- Bound arguments, stdin, notes, JSON, query limits, and render allocations.
- Treat closed stdout as normal and stop unnecessary work.
- Restore the terminal after error, panic, signal, and ordinary exit.
- Avoid secrets and full unnecessary paths in diagnostic bundles.
- Use adapter transactions for every multi-write command.
- Verify interrupted and rejected commands leave no partial accepted state.
- Do not offer a raw-table editing escape hatch.

## 18. Accessibility and terminal compatibility

- Keyboard-only operation
- Discoverable help overlay
- No meaning conveyed by color alone
- `NO_COLOR` and explicit color policy
- Sensible monochrome rendering
- Resize recovery without data loss
- Documented Unicode-width behavior and safe fallback
- Narrow-terminal behavior that preserves critical IDs and metrics
- Screen-reader-friendly line CLI as a permanent alternative
- Configurable units and, later, keybindings only when understandable
- Terminal restoration tests using a fake terminal boundary

## 19. Phased roadmap and Codex-ready issues

Issue IDs continue the repository's `CWE` sequence after the completed v0.1
plan. Each issue is independently testable and must obey the repository-wide
definition of done.

### Phase 0 — Public-package and adapter readiness

#### CWE-102: Publish the Zig persistence contract as a named package — S

**Class:** Missing public SQLite-adapter prerequisite.

**Work:**

- Decide the public Zig name, provisionally `caudex_persistence`.
- Register only the database-independent root in the build.
- Document ownership, allocator, error, and compatibility semantics.
- Add a clean external Zig consumer smoke test.

**Acceptance criteria:**

- A consumer imports the named package without repository-relative paths.
- The package depends only on public `caudex`.
- Test utilities remain a separate test-only package.
- Existing contract tests pass unchanged or with reviewed naming updates.

#### CWE-103: Define the minimum public tracking command/query contract — L

**Class:** Missing public engine capability.

**Work:**

- Review ADR-0002/0003 and prevent restoration of the superseded
  persistence-owned core.
- Define the minimum types for a host-owned local tracker: scope, active workout,
  exercise membership, set logging, completion, stable IDs, command IDs,
  timestamps, revisions, issues, and queries.
- Decide whether this is a new `caudex_tracking` package or narrow extensions
  to another intentionally public application contract.
- Specify idempotency, short-workout completion, ambiguity, and correction
  prerequisites.
- Do not implement storage or CLI behavior.

**Acceptance criteria:**

- An architecture review approves dependency direction and naming.
- Typed fixtures express start-workout and read-workout across host calls.
- No database, terminal, clock, random, or global dependency enters the core.
- Unsupported Phase 4 features are clearly marked rather than implied.

#### CWE-104: Implement the minimal deterministic workout lifecycle — L

**Class:** Missing public engine capability.

**Work:**

- Implement only create/start and queryable lifecycle state required for the
  first persisted vertical slice.
- Use caller-supplied IDs and timestamps.
- Define structured rejection and conflict results.
- Add deterministic unit and architecture tests.

**Acceptance criteria:**

- Start is deterministic and effect-free.
- Retry semantics are representable by the public contract.
- No persistence or allocation is hidden in decisions.
- Tests cover valid start, duplicate/retry, invalid data, and two active
  workouts where the contract allows them.

#### CWE-105: Publish the Zig SQLite adapter package and metadata lifecycle — L

**Class:** Missing public SQLite-adapter capability.

**Work:**

- Register `caudex_sqlite` as a distributable named package.
- Package required private migrations without exposing them.
- Provide open/create, supported options, migration, metadata, in-memory/file,
  and close lifecycle.
- Improve error categories for busy, corruption, migration, and compatibility.
- Preserve prepared statements and private schema.

**Acceptance criteria:**

- A clean external consumer opens `:memory:`, reads metadata, and closes.
- A file database persists across adapter instances.
- Newer schemas are rejected distinctly.
- Busy and corruption behavior are tested.
- No raw writable handle, SQL, table name, or migration body is public.

#### CWE-106: Persist the minimal workout lifecycle through the public adapter — L

**Class:** Missing SQLite-adapter capability.

**Work:**

- Implement atomic start, idempotent receipt, and workout query using the public
  tracking contract.
- Add forward-only migrations and indexes.
- Expose an application/service handle without leaking SQLite types where
  practical.

**Acceptance criteria:**

- A workout started through one adapter instance is queried through another.
- Retrying a command ID returns the original result without duplication.
- Failure rolls back state and receipt together.
- Tests use public APIs, not direct SQL assertions.

### Phase 1 — Line-CLI walking skeleton

#### CWE-110: Scaffold `caudex-cli` and enforce public imports — M

**Class:** Client.

**Work:**

- Create only `README.md` and `src/main.zig`.
- Wire root build, run, install, and focused test steps.
- Supply only `caudex`, `caudex_persistence`, and `caudex_sqlite`.
- Add architecture checks for forbidden imports.

**Acceptance criteria:**

- `caudex --help` and `caudex version` run.
- Focused app tests do not require npm.
- A deliberately private import fails at the build boundary.
- Root builds remain simple.

#### CWE-111: Resolve database paths and open/query/close metadata — M

**Class:** Client.

**Work:**

- Implement explicit path, environment override, and platform default
  resolution.
- Open the public adapter, query version/schema metadata, render human output,
  and close cleanly.
- Add `caudex database info`.

**Acceptance criteria:**

- This complete path works:

  ```text
  args → path → public adapter → metadata query → stdout → close
  ```

- Tests cover precedence, missing directories, `:memory:`, human/JSON output,
  stderr, and exit status.
- No client SQL or private import exists.

#### CWE-112: Add centralized errors, streams, formats, and exit mapping — M

**Class:** Client.

**Work:**

- Introduce minimal earned modules for output and errors.
- Implement human and versioned JSON envelopes.
- Centralize stable exit classes, color policy, and broken-pipe behavior.

**Acceptance criteria:**

- stdout/stderr never mix contracts.
- Piped output has no ANSI.
- Golden tests cover JSON errors and representative help.
- `EPIPE` exits quietly with no database damage.

#### CWE-113: Prove `workout start` across processes — L

**Class:** Client vertical slice.

**Work:**

- Parse `caudex workout start`.
- Supply or safely generate explicit command/workout IDs and timestamps at the
  client boundary.
- Execute through public tracking and SQLite packages.
- Query the workout from a second process.

**Acceptance criteria:**

- A subprocess starts a workout and emits its ID.
- A fresh subprocess shows the persisted workout.
- JSON includes stable IDs and exact timestamps.
- Retrying the same explicit command ID does not duplicate state.

### Phase 2 — Essential workout-tracking commands

#### CWE-120: Add public workout-exercise ordering operations — L

**Class:** Missing public engine and adapter capability.

**Acceptance criteria:**

- Public commands add, remove, and reorder by semantic anchors, never numeric
  storage positions.
- Deterministic rules and SQLite transactions have separate tests.
- Archived/missing exercises produce structured issues.
- No CLI syntax is added in this issue.

#### CWE-121: Add public set lifecycle and exact metrics — L

**Class:** Missing public engine and adapter capability.

**Acceptance criteria:**

- Add/log, complete, skip, reopen, remove, and reorder behavior is explicit.
- Repetitions, load, RIR, RPE, duration, targets, and actuals use exact public
  measurements.
- Invalid transitions reject without mutation.
- Idempotency, revision conflicts, and rollback are tested.

#### CWE-122: Implement client reference and active-workout resolution — M

**Class:** Client.

**Acceptance criteria:**

- Explicit IDs, exact aliases/names, and documented search resolve in order.
- Multiple candidates return exit 5 and candidate IDs.
- Zero/one/many active-workout selection follows ADR-0004.
- No hidden current-workout preference is stored.

#### CWE-123: Implement add-exercise and workout display commands — M

**Class:** Client.

**Acceptance criteria:**

- Separate subprocess tests add and show exercises.
- Human tables remain readable in narrow output.
- JSON includes workout, exercise, ordering, and revision IDs.
- Client uses shared typed use cases rather than command-specific SQL.

#### CWE-124: Implement concise set logging, skipping, and reopening — L

**Class:** Client.

**Acceptance criteria:**

- Long explicit metric options and unambiguous shorthand are supported.
- Unit/shorthand parser tests cover invalid and conflicting input.
- Helpful validation errors preserve engine issue codes.
- Quiet and JSON modes work in subprocess tests.

#### CWE-125: Implement finish and cancel workflows — M

**Class:** Engine/adapter gap plus client.

**Acceptance criteria:**

- A short or partial workout can finish successfully when domain rules allow it.
- Cancellation is distinct from completion.
- Genuinely destructive behavior confirms only on a TTY and supports `--yes`.
- Interrupted/rejected operations leave the database consistent.

### Phase 3 — Catalog and history commands

#### CWE-130: Review and define public catalog-management scope — M

**Class:** Missing public engine capability review.

**Acceptance criteria:**

- Athlete, equipment, exercise, alias, archive, restore, annotation, and
  external-ID needs are each classified.
- Only engine-relevant reusable invariants enter public contracts.
- Existing exercise snapshot compatibility is addressed.
- Out-of-scope capabilities remain explicitly deferred.

#### CWE-131: Implement approved catalog commands and SQLite queries — L

**Class:** Engine and adapter.

**Acceptance criteria:**

- Approved create/edit/archive/restore operations use stable IDs, revisions,
  idempotency, and prepared SQL.
- Search is indexed and bounded.
- Tombstone behavior is tested only where the approved model supports it.
- No CLI behavior is implemented.

#### CWE-132: Implement catalog CLI commands — L

**Class:** Client.

**Acceptance criteria:**

- Only approved athlete/equipment/exercise nouns are exposed.
- Exact ID operation and friendly ambiguity reporting coexist.
- Example data is created through public commands.
- Human tables, JSON, and subprocess tests cover CRUD lifecycle.

#### CWE-133: Add public history, last-performance, and correction queries — L

**Class:** Missing engine/adapter capability.

**Acceptance criteria:**

- Date-bounded paginated history and exercise history use public types.
- Last performance avoids loading all history.
- Correction is an explicit audited command, not a raw update.
- Revisions, tombstones where supported, and methodology-state implications are
  documented.

#### CWE-134: Implement history and correction CLI commands — L

**Class:** Client.

**Acceptance criteria:**

- History list/show/exercise and correction use public APIs.
- A completed workout is queried from a fresh process.
- Last performance is concise and scriptable.
- Mistake correction is confirmed when destructive and is regression-tested.

### Phase 4 — Shell ergonomics and machine integration

#### CWE-140: Mature help, aliases, tables, and config — M

**Class:** Client.

**Acceptance criteria:**

- Help exists at every meaningful level.
- Frequent aliases are documented and collision-tested.
- Non-domain preferences are inspectable and atomically persisted.
- User-controlled terminal text is safely escaped.

#### CWE-141: Stabilize JSON schemas and batch input — L

**Class:** Client/protocol.

**Acceptance criteria:**

- Every scriptable command has a versioned JSON document.
- Batch input is bounded, documented, and reports per-operation outcomes.
- Golden and compatibility fixtures cover schemas and exact decimals.
- Batch retries preserve public idempotency.

#### CWE-142: Generate shell completion and command documentation — M

**Class:** Client.

**Acceptance criteria:**

- Bash, zsh, and fish completion is generated from reviewed command metadata.
- Completion never queries or mutates a database unexpectedly.
- Golden tests cover scripts.
- Man page or command reference generation has one source of truth.

#### CWE-143: Add shell-script smoke scenarios — M

**Class:** Client integration.

**Acceptance criteria:**

- Pipes, command substitution, aliases, and non-interactive scheduling patterns
  are tested.
- stdout, stderr, quiet mode, JSON, signals, and exit codes are asserted.
- Tests use only the Zig-built binary and ordinary shell facilities.

### Phase 5 — Line-CLI hardening and release

#### CWE-150: Add database diagnostics and integrity checking — M

**Class:** SQLite adapter plus client presentation.

**Acceptance criteria:**

- Reusable public metadata and integrity operations contain no CLI defaults.
- Busy, corrupt, incompatible, and newer-schema results are distinct.
- `database check` and `doctor` render actionable, sanitized output.

#### CWE-151: Add safe backup and restore — L

**Class:** SQLite adapter plus client.

**Acceptance criteria:**

- A reusable adapter API owns consistency mechanics.
- Existing destinations, symlinks, permissions, and interruption are handled
  explicitly.
- Restore validates compatibility before switching.
- Backup/restore tests never depend on direct table editing.

#### CWE-152: Document and lock CLI compatibility contracts — M

**Class:** Client.

**Acceptance criteria:**

- Exit codes, JSON schemas, command grammar, database paths, and human-output
  non-guarantees are documented.
- Compatibility tests cover old supported fixtures.
- Version output reports all independent boundaries.

#### CWE-153: Run the complete line-CLI end-to-end suite — L

**Class:** Integration.

**Acceptance criteria:**

- The first eleven required scenarios pass across subprocesses.
- Busy, interruption, closed stdout, retry, and ambiguity are covered.
- No test reaches into private SQL or engine modules.
- All relevant format, build, and package checks pass.

#### CWE-154: Establish performance and large-history baselines — M

**Class:** Quality.

**Acceptance criteria:**

- Startup, database open, common commands, search, last performance, and history
  listing are measured on documented hardware/data.
- Regressions have repeatable benchmark fixtures.
- Any optimization follows evidence and preserves public behavior.

#### CWE-155: Package the first line-CLI release — L

**Class:** Release.

**Acceptance criteria:**

- Supported target matrix and SQLite requirements are documented.
- Archives install and run from clean locations.
- Checksums, license, notices, version metadata, and smoke tests are complete.
- No TUI dependency is included.

### Phase 6 — TUI foundation

#### CWE-160: Evaluate terminal libraries and record the dependency decision — M

**Class:** Architecture review.

**Acceptance criteria:**

- Candidate maintenance, platforms, licenses, Unicode, resize, signal,
  testability, size, and pinning are compared.
- Standard-library/direct implementation is evaluated.
- Any dependency is pinned and isolated behind an app facade.
- No terminal code enters public engine/adapter APIs.

#### CWE-161: Implement crash-safe terminal lifecycle — L

**Class:** Client.

**Acceptance criteria:**

- Raw mode, alternate screen, resize, signals, ordinary exit, and panic/error
  restoration are covered.
- A fake terminal verifies lifecycle without a live terminal.
- `NO_COLOR` and non-color modes work.

#### CWE-162: Implement explicit TUI event/update/render foundation — L

**Class:** Client.

**Acceptance criteria:**

- Synthetic events drive deterministic update tests.
- Rendering targets an application-owned buffer/facade.
- Resize, narrow layout, Unicode fallback, and help overlay states have selective
  goldens.
- No generalized Elm/Redux/effect framework is introduced.

#### CWE-163: Connect TUI actions to the shared client application layer — M

**Class:** Client.

**Acceptance criteria:**

- TUI actions call the same typed use cases as line commands.
- No subprocess spawning occurs for ordinary operations.
- Errors and conflicts update presentation state without duplicating rules.

### Phase 7 — Live-workout TUI

#### CWE-170: Build the current-workout dashboard and exercise picker — L

**Acceptance criteria:**

- Dashboard handles zero, one, and multiple active workouts safely.
- Exercise search and ambiguity use public queries.
- Last performance is visible.
- Keyboard-only navigation and help are tested.

#### CWE-171: Add exercise ordering and set logging screens — L

**Acceptance criteria:**

- Add/reorder exercises and log/edit/skip/reopen sets through shared use cases.
- Target-versus-actual exact metrics render clearly.
- Conflicts refresh or explain; they never guess or overwrite.

#### CWE-172: Add notes, completion, cancellation, and recovery — L

**Acceptance criteria:**

- Supported notes use public commands.
- Short completion and cancellation are distinct.
- Resize and interruption preserve database consistency and restore terminal.
- Confirmation is accessible and does not trap non-interactive execution.

#### CWE-173: Run the live-workout TUI end-to-end scenario — L

**Acceptance criteria:**

- A fake-terminal or controlled PTY test performs the line-CLI scenario through
  the TUI.
- The resulting workout is queried by a new line-CLI process.
- Render and input latency baselines are recorded.

### Phase 8 — Full reference-client feature coverage

#### CWE-180: Build catalog-management TUI screens — L

**Acceptance criteria:**

- Screens expose only approved public catalog operations.
- Search/filter, aliases, archive/restore, annotations, and external IDs appear
  only where supported.
- No alternate catalog schema or direct database edit exists.

#### CWE-181: Build history browser and correction flows — L

**Acceptance criteria:**

- Date range, exercise history, last performance, detail, and search use bounded
  public queries.
- Historical correction is explicit and conflict-aware.
- Stable export appears only if a public export contract exists.

#### CWE-182: Add local-data and database-switching UI — M

**Acceptance criteria:**

- Metadata, migration visibility, diagnostics, backup/restore, and safe switching
  use public adapter APIs.
- Busy/corrupt/incompatible states are recoverable and clear.
- No raw table browser is added.

#### CWE-183: Audit complete supported tracking coverage — M

**Class:** Architecture/product review.

**Acceptance criteria:**

- Every public tracking operation is demonstrated or intentionally excluded.
- Every desired but absent feature is classified into the four gap categories.
- Recommendation, workout generation, periodization, and recovery features are
  not invented.

### Phase 9 — Hardening, packaging, and documentation

#### CWE-190: Harden terminal compatibility and accessibility — L

**Acceptance criteria:**

- Supported terminals/platforms, Unicode width, color, resize, signal, and
  keyboard behavior are tested and documented.
- Meaning is not conveyed by color alone.
- Line CLI remains the accessible fallback.

#### CWE-191: Harden security, diagnostics, and crash behavior — L

**Acceptance criteria:**

- Bounded input, terminal escaping, path/symlink behavior, permissions,
  closed-output, and diagnostic redaction tests pass.
- Terminal restoration survives injected failures.
- No secrets or unsafe raw content appear in diagnostics.

#### CWE-192: Publish integrator and user documentation — L

**Acceptance criteria:**

- Installation, first workout, shell scripting, JSON, database, backup, exit
  code, command, TUI keybinding, and troubleshooting docs are complete.
- A third-party Zig guide proves use of public packages only.
- It explains how to build another client without copying presentation logic.

#### CWE-193: Package the full reference-client release — L

**Acceptance criteria:**

- Cross-platform artifacts and terminal/SQLite requirements are verified.
- Complete line and TUI smoke suites run from release archives.
- Versions, licenses, notices, checksums, migration support, and release notes
  are complete.

## 20. Recommended implementation order

Strict prerequisites:

```text
CWE-102
  ↓
CWE-103 → CWE-104
  ↓         ↓
CWE-105 → CWE-106
  ↓
CWE-110 → CWE-111 → CWE-112 → CWE-113
  ↓
Phase 2 essential tracking
  ↓
Phase 3 catalog/history
  ↓
Phase 4 shell integration
  ↓
Phase 5 line-CLI release
  ↓
Phase 6 TUI foundation
  ↓
Phase 7 live TUI
  ↓
Phase 8 coverage
  ↓
Phase 9 full release
```

Do not start TUI dependency selection until CWE-155 is complete. Do not expose a
CLI command before its owning public command/query contract and adapter support
are accepted.

## 21. Definition of done for every issue

Every issue:

1. Reads AGENTS.md, ADR-0001 through ADR-0004, relevant plan sections, public
   package docs, neighboring code, and current git status.
2. States the issue's gap classification and concise plan before editing.
3. Resolves material public-contract ambiguity before implementation.
4. Changes only the independently testable scope.
5. Adds tests at the correct deterministic, adapter, client, subprocess, or
   terminal boundary.
6. Uses public packages in app code and prepared/bound SQL in adapter code.
7. Adds no dependency without purpose, license, standard-library comparison,
   pin, platform review, and isolation.
8. Runs applicable focused tests plus:

   ```bash
   zig build
   zig build test
   zig fmt --check .
   git diff --check
   ```

9. Inspects the final diff for unrelated changes.
10. Updates documentation and compatibility fixtures when public behavior
    changes.
11. Reports summary, files, exact commands, public API/schema changes,
    architecture decisions, assumptions, and limitations.
12. Does not commit, push, branch, or open a pull request without explicit
    instruction.

## 22. Focused Codex issue prompt template

```text
Implement only CWE-___ from docs/implementation-plan.md.

Read AGENTS.md, ADR-0001 through ADR-0004, the issue and its prerequisites,
relevant public package documentation, neighboring code/tests, build.zig, and
build.zig.zon. Inspect git status first.

Before editing:
- classify the work as engine contract, SQLite adapter, client, or out of scope;
- report current public capability and any blocking mismatch;
- state a concise plan.

Constraints:
- preserve the stateless recommendation core and explicit Zig shell;
- app code imports named public packages only;
- no raw SQLite access from the client;
- no terminal or CLI behavior in engine/adapter contracts;
- no JavaScript, TypeScript, Node.js, or npm;
- no generalized FP/UI framework;
- no unrelated scaffolding or speculative features.

Implement the smallest independently testable change satisfying every listed
acceptance criterion. Add boundary-appropriate tests. Run all applicable
focused checks and the repository required checks. Report exact results,
public API/schema changes, architectural decisions, assumptions, and known
limitations. Do not commit or push.
```

## 23. Public engine/adapter issue prompt template

```text
Implement only CWE-___, a public [engine|SQLite-adapter] prerequisite for the
first-party reference client.

Do not implement CLI or TUI behavior. Read the authoritative ADRs and inspect
the completed public surface. Define the smallest reusable host-facing contract
that solves the stated capability for third-party Zig hosts as well as
caudex-cli. Keep private representations, SQL, migrations, and service
implementations outside public roots.

Separate deterministic issues from runtime/storage failures. Require explicit
IDs, timestamps, revisions, allocators, and ownership as applicable. Use
prepared statements and atomic transactions in SQLite. Add public contract,
adapter, clean-consumer, and architecture tests. Run the repository checks and
report any compatibility or migration change. Do not commit or push.
```

## 24. Architectural review prompt template

```text
Review CWE-___ without implementing production code.

Read AGENTS.md, ADR-0001 through ADR-0004, the active plan, completed v0.1 plan,
public package docs, build manifests, package roots, relevant tests, and current
git status.

Evaluate:
- whether the capability belongs to the deterministic engine, a public
  tracking/application contract, the reusable SQLite adapter, or the client;
- whether caudex-cli can consume it through named public packages;
- whether any private type, SQL, migration, event, ABI, fixture, terminal, or
  client preference leaks across boundaries;
- idempotency, revisions, errors, allocation/ownership, compatibility,
  migration, testability, security, performance, and dependency implications;
- whether a smaller vertical slice proves the architecture first.

Report findings by severity with file/line evidence, unresolved questions,
required acceptance-criteria changes, and a go/no-go recommendation. Do not
edit files.
```

## 25. Open decisions intentionally deferred

These are safe to decide in their focused issues:

- Final names and independent release cadence of public persistence/tracking
  Zig packages
- Whether tracker state belongs in the existing adapter schema or a separately
  versioned adapter component
- Whether athlete and equipment need first-class v0.2 models
- Approved notes, grouping, tombstone, annotation, and external-ID semantics
- Terminal dependency selection
- Exact cross-platform release matrix and installer channels
- Concrete performance budgets after baseline measurement
- Whether safe reusable backup uses SQLite's backup API or another adapter-owned
  mechanism
- Whether app-local manifests become useful for independent distribution

None authorizes a private import or direct table mutation in the interim.
