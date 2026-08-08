# Tiger Style audit, 2026

This audit records the repository baseline and the decisions behind the first
Caudex-specific Tiger Style migration. It is descriptive evidence; the
authoritative ongoing policy is
[`engineering-style.md`](engineering-style.md).

## Baseline

The audit covered root and contributor documentation, accepted ADRs and active
implementation plans, the root and package build manifests, core/domain and
both methodologies, tracking and portable protocols, workflow conversion,
SQLite and browser persistence adapters, the C and WASM boundaries, npm
facades, CLI/TUI, schemas and fixtures, compatibility snapshots, fuzz drivers,
mutation tooling, model/property tests, benchmarks, release tools, and CI
workflows. `AGENTS.md` was read as historical context and was not changed.

Before refactoring:

- `git status --short`: clean;
- `zig build check-release --summary all`: 134/134 steps and 128/128 tests
  passed, including fuzz smoke and mutation smoke (6 killed, 0 actionable
  survivors);
- deterministic C, WASM, and TypeScript fingerprint:
  `83481330a812bb41384d958c104038d230bf93ceee163fd47b7c62a41361fd6f`;
- npm artifact: 213,342 packed bytes, 687,770 unpacked bytes, 37 files;
- CLI benchmark in nanoseconds: startup 19,173,000; database open 16,193,000;
  catalog search 10,400,000; history list 10,018,000; last performance
  10,048,000.

## Classified findings

### Must fix

- The public WASM allocator accepted arbitrary caller-controlled lengths even
  though execution requests, portable payloads, and results already had a
  practical envelope. This made direct WASM use capable of caller-driven
  unbounded linear-memory growth.
- SQLite portable snapshot sizing added a set's target and actual metric counts
  before entering checked arithmetic. The final addition was checked, but the
  intermediate expression was not.
- SQLite methodology-state compare-and-set parsed a stable `u64` revision and
  incremented it with unchecked `+ 1`.

### Worthwhile

- Make the existing bounds model easier to discover. Caudex already has named
  limits for canonical JSON bytes/nesting/collections/strings, diagnostics,
  tracking batches and snapshots, templates, portable records, C buffers, and
  CLI arguments/batches, but no single engineering policy explained ownership
  and validation expectations.
- Add postcondition assertions to bounded diagnostic writers so later changes
  cannot silently separate the cursor from caller capacity or the product cap.
- Require style exceptions to reference a real file and symbol with a reason.
- Continue splitting large orchestration functions when a semantic boundary is
  clear. SQLite portable import and the declarative root build graph are
  recorded exceptions rather than mechanically fragmented.
- Gradually bring materially edited production code toward 100 columns. The
  initial scan found 1,564 lines over 100 columns across production, tests,
  generated declarations, SQL, tools, and fixtures. A bulk wrap would be noisy
  and unsafe; raw line count is not a migration objective.

### Optional

- Add syntax-aware reporting for production function size and recursion if the
  Zig tooling can do so without treating tests, declarations, function
  pointers, generated code, or nested helpers as violations.
- Add allocation/peak-memory benchmark instrumentation once a stable
  cross-platform harness exists.
- Introduce options structs only where future API work finds genuinely
  swappable same-typed parameters or behaviorally significant defaults.

### Not applicable

- Static allocation after process startup does not fit allocator-taking Zig
  APIs, host-owned snapshots, WASM/npm handles, optional persistence adapters,
  or a CLI/TUI. Pure domain decisions already use caller-owned storage.
- Passing every nontrivial value by pointer would make small canonical and
  domain values harder to use without a demonstrated copy problem.
- Zig naming rules do not apply to stable, idiomatic TypeScript/JavaScript
  public APIs.

### Intentional Caudex deviations

- Malformed public input remains a validation issue or defined boundary error;
  assertions are reserved for internal facts after validation.
- `usize` remains the type for memory, slices, indices, and allocator counts.
  Stable domain, storage, wire, C, and WASM quantities use explicit widths.
- Dependencies are restrained and pinned, not prohibited. System SQLite and
  existing ecosystem build/test tools provide justified capabilities.
- Roughly 70 function lines and 100 columns are review guardrails, not quotas.
  Coherent algorithms, transaction orchestration, build graphs, tests,
  declarative tables, SQL, and generated code may justify narrow exceptions.

## Audit observations by area

- Recursion: no intentional production recursion was found in the reviewed Zig
  domain, methodology, tracking, protocol, adapter, or client paths. The policy
  now makes iterative production code the default while permitting reviewed,
  intrinsically bounded exceptions.
- Bounds: the repository was already unusually strong. New work added one
  externally visible allocation bound and retained all established protocol
  limits rather than replacing them with a global cap.
- Arithmetic and types: exact decimal operations use fixed-width values and
  checked intermediates; tracking revisions are `u64`; schema versions are
  `u32`; repetitions and set-like counts at stable domain surfaces are
  generally `u16`. Two unchecked SQLite calculations were the material gaps.
- Assertions: assertions were already used at internal buffer and ABI
  invariants. Public parsing generally returns structured errors. Four
  postcondition assertions were added to diagnostic buffer mutation.
- Allocation: pure domain paths remain caller-buffered. Adapter and boundary
  allocation is explicit. The WASM allocator cap prevents direct unbounded
  caller allocation; no ideological static-allocation conversion was made.
- Control flow: important operations use tagged unions and exhaustive switches.
  Complex adapter and C-boundary orchestration remains a future clarity target,
  but wholesale rewrites would carry greater transaction and compatibility
  risk than incremental extraction.
- Errors: domain issues, engine failures, persistence conflicts, ABI statuses,
  npm runtime failures, and CLI exits remain separate. The corrected SQLite
  overflow cases become adapter `InvalidData`, consistent with corrupt or
  exhausted persisted revision/count representations.
- Compatibility: schemas, fixtures, migrations, public Zig types, the C ABI,
  npm API, CLI output/exit codes, and recommendation semantics were not changed.

## Deferred findings

- Refactor the longest C dispatch/discovery and SQLite portable-import
  orchestration only with focused transaction/failure-injection tests. They are
  understandable today and compatibility-sensitive.
- Audit every SQLite decoded collection against protocol maxima before its
  first allocation. Existing portable/tracking conversion validation catches
  oversized final snapshots, but earlier rejection can further reduce peak
  memory.
- Add representative core recommendation benchmarks. The current repeatable
  harness measures CLI paths and artifact budgets; it does not isolate every
  methodology hot loop.
- Consider a syntax-aware Zig audit tool after compiler APIs stabilize. Review
  remains more reliable than a regex gate for recursion, executable function
  length, semantic integer widths, and assertion placement.
- Reduce long lines only while touching their surrounding logic. Most current
  excess is concentrated in SQLite, C dispatch, workflow conversion, generated
  TypeScript declarations, and coherent test fixtures; a repository-wide wrap
  would obscure meaningful review.
