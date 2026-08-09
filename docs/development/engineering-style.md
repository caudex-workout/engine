# Caudex engineering style

This document is the authoritative engineering-style policy for Caudex. It is
derived from TigerBeetle's Tiger Style, but it is a Caudex policy: an
embeddable, deterministic workout SDK has different failure, allocation, ABI,
and ecosystem constraints from a database server.

The priorities, in order, are:

1. correctness and safety;
2. determinism and compatibility;
3. developer experience;
4. predictable performance;
5. terseness.

When rules conflict, the earlier priority wins. Existing public Zig, C, WASM,
npm, schema, CLI, persistence, and deterministic-result contracts are not
changed merely to improve style.

## Applicability matrix

| Tiger Style principle | Caudex status | Caudex policy |
| --- | --- | --- |
| Safety before performance | Adopted | Correctness and defined public failures come first. |
| Bounded execution and resources | Adopted | Give externally controlled work a named product limit at the boundary that owns the contract. |
| Simple, explicit control flow | Adopted | Prefer shallow branches, exhaustive `switch`, early rejection, and obvious mutation. |
| No production recursion | Adapted | Production Zig is iterative by default. A reviewed exception must document an intrinsic depth bound and safe stack use. |
| Assertions for invariants | Adapted | Assert programmer-only invariants after validation; malformed caller input produces a public issue or error. |
| Paired assertions | Adapted | Use before/after assertions when they materially protect a transformation, state transition, or representation boundary. They are not a quota. |
| Explicit checked arithmetic | Adopted | Check overflow, underflow, scaling, size calculations, and narrowing when the type or validated bound does not prove safety. |
| Fixed-width integers | Adapted | Stable domain, wire, storage, ABI, and WASM quantities use explicit widths. `usize` remains correct for slices, indices, memory sizes, and Zig allocator APIs. |
| Small functions | Adapted | About 70 executable lines is a design warning, not an automatic failure. Split responsibilities, not coherent algorithms or declarative tables. |
| 100-column lines | Adapted | New and materially edited code targets about 100 columns. Prefer restructuring to awkward wrapping; generated, table, schema, SQL, and external syntax may exceed it. |
| Small variable scope | Adopted | Declare values near use and keep mutable state local. |
| Explicit ownership | Adopted | Allocator ownership, borrowed data, returned lifetimes, and buffer capacity must be apparent from types, names, or API documentation. |
| Static allocation after startup | Intentionally rejected | Caudex uses explicit allocators and bounded dynamic allocation at host and adapter boundaries. Pure decisions continue to use caller-owned storage. |
| Zero dependencies | Intentionally rejected | Dependencies are restrained, pinned, reviewed, and justified; useful ecosystem or platform dependencies are not removed for a metric. |
| All large values by pointer | Not applicable | Use pointers when they clarify ownership or avoid meaningful copying. Small value semantics remain idiomatic Zig. |
| Zig naming in every language | Intentionally rejected | Zig uses `snake_case`; TypeScript and JavaScript preserve idiomatic ecosystem and public API conventions. |
| Assertion-count targets | Intentionally rejected | Assertions express facts. Counts are never a quality objective. |
| Terseness as a primary goal | Intentionally rejected | Clarity, compatibility, and explicit behavior outrank brevity. |

## Bounded execution

Every loop is finite in the language sense, but that alone is insufficient.
Work driven by a caller, file, database, or decoded payload must have a
practical limit when scale can affect latency, memory, stack, output, or denial
of service resistance.

Limits must:

- describe a real contract with a precise `max_*` name and unit;
- live at the layer that owns the contract;
- be checked before allocation or expensive traversal where practical;
- reject through the layer's defined public error model;
- have tests below, exactly at, and above the boundary when the limit is new or
  behaviorally important;
- be documented when consumers can observe it.

Related dimensions should support simple upper-bound reasoning. For example,
tracking work is bounded by workouts times exercises per workout times sets per
exercise times metrics per set. Do not add a cap merely to conceal an
unbounded design, and do not invent a product limit without checking realistic
host data.

Current boundary owners include canonical JSON request bytes, nesting,
collections, and strings; tracking batches and snapshots; workout templates;
portable imports and exports; diagnostic buffers; C and WASM request/output
buffers; CLI arguments, paths, and batch files; and adapter query limits.

## Zig production code

### Control flow and state

- Prefer positive domain states and early rejection when they reduce nesting.
- Use exhaustive `switch` for tagged unions, enums, operations, and state
  transitions. Centralize the branch that chooses behavior; keep leaf helpers
  straightforward.
- Give each mutable value one obvious owner. Do not mirror state in aliases or
  update related fields in dispersed branches.
- Production recursion requires a narrow, documented exception. Iteration is
  the default.
- A function near or over 70 executable lines deserves review. Large
  orchestration functions, exhaustive conversion tables, and coherent parsing
  state machines can be clearer intact. Never extract one-line forwarding
  helpers solely to meet a number.

### Integers, arithmetic, and units

- Use explicit widths for repetitions, sets, revisions, schema/methodology
  versions, timestamps, durations, persisted sequences, and other stable
  domain quantities.
- Use `usize` for slice indices and lengths, buffer capacities, byte sizes,
  allocator counts, and Zig-native collection APIs.
- Names distinguish `index`, `count`, `bytes`, `capacity`, `revision`, and
  units such as `_milliseconds` or `_seconds`.
- Use `std.math.add`, `sub`, and `mul`, overflow builtins, or a wider proven
  intermediate where overflow is possible. Check component calculations as
  well as their final sum or product.
- Narrowing conversions must be preceded by a proof, validation, or checked
  conversion. Do not rely on build-mode overflow behavior.
- Decimal scaling, unit conversion, division, and rounding state their policy
  in code and tests. Authoritative measurements remain exact decimals.

### Assertions and errors

External malformed input must never require an assertion to stay safe:

```text
external invalid input -> validation issue or defined public error
validated internal state violates an invariant -> assertion
```

Good assertions protect cursor/capacity agreement, post-validation facts,
canonical ordering, representation round-trips, and state-transition
postconditions. Do not assert facts that are still controlled by an unvalidated
host payload. Do not translate persistence conflicts or resource failures into
domain validation issues.

Expected invalid/domain conditions, recommendation issues, engine failures,
adapter conflicts/failures, ABI statuses, npm initialization/runtime failures,
and CLI exits remain distinct. Cleanup errors may be deliberately ignored only
when another error is already being returned and the primary failure cannot be
replaced; transaction cleanup is the representative case.

### Allocation and ownership

Caudex does not require static allocation after startup. Instead:

- pure domain decisions do not hide allocation;
- allocator-taking APIs make ownership and deallocation responsibility clear;
- caller-provided buffers, fixed buffers, and arenas are preferred where they
  simplify lifetime reasoning or make maximum use explicit;
- validate caller-controlled counts before allocating them when practical;
- avoid repeated temporary allocation in hot loops;
- do not introduce pointer-heavy APIs for small values without evidence;
- borrowed slices must not outlive their owner, and stored pointers must have a
  documented lifetime.

Measure meaningful allocation or copy changes with the existing benchmarks.
Predictability is the goal, not allocation ideology.

### Naming, comments, and layout

Zig follows normal `snake_case`. Prefer complete domain words over obscure
abbreviations, precise verbs over generic `do`/`handle`, and qualified names
such as `requested`, `canonical`, `proposed`, `accepted`, `persisted`,
`encoded`, and `decoded` when the distinction matters. Public renames require
a compatibility reason beyond aesthetics.

Comments explain rationale, invariants, surprising methodology rules,
compatibility obligations, safety reasoning, measured performance decisions,
or evidence. Remove comments that merely restate syntax. New and substantially
edited code targets about 100 columns, with narrow exceptions for content whose
native representation would become less readable.

### API shape

Use an options struct when behaviorally significant defaults or same-typed
positional values are easy to swap. Do not wrap trivial APIs for consistency
alone. Stable C and WASM surfaces use fixed-width values for protocol concepts
and `size_t`/`usize` for native pointer lengths and capacities. Public
boundaries define null handling, ownership, lifetimes, and insufficient-buffer
behavior.

## TypeScript and JavaScript

TypeScript and JavaScript stay idiomatic: public objects and methods use the
existing `camelCase` contracts. Apply the structural rules—bounded parsing and
batch work, explicit state transitions, checked safe-integer conversions,
clear ownership of handles and buffers, exhaustive discriminated unions, and
separate initialization/runtime errors—without imitating Zig syntax.

Avoid semantic duplication in the npm facade. Recommendation, methodology,
tracking, and canonical behavior belongs in Zig; JavaScript validates the
crossing, manages the WASM lifetime, and presents an ergonomic host API.
Generated declarations and bundled artifacts are governed by their generators.

## JavaScript, shell, build, and release tooling

- Keep each tool in the language best suited to its ecosystem. Do not rewrite
  functioning Node.js tooling into Zig for ideological reasons.
- Bound file reads, argument counts, archive entries, subprocess time or work,
  and generated output when they consume untrusted or release-provided data.
- Shell uses strict failure handling where appropriate, quotes expansions, and
  avoids parsing structured data as ad hoc text when a repository tool already
  owns the format.
- Release tooling validates versions, paths, checksums, archive contents, and
  compatibility metadata explicitly. It must not silently continue after a
  corrupt artifact or failed subprocess.
- `build.zig` may contain long declarative dependency sections when splitting
  would obscure the build graph. Build steps remain named, bounded, and
  composable.

## Production, tests, generated code, and migrations

The strictest rules apply to core/domain, methodologies, tracking transitions,
protocol conversion, persistence decoding, and public ABI boundaries. Tests
may use larger coherent scenario functions, direct fixture construction, and
intentional invalid states. They must still be deterministic and bounded.

Generated code is changed through its source and generator. Historical
compatibility fixtures are immutable evidence. Released migrations are
immutable and forward-only; style improvements apply to new migrations and
adapter code, never by rewriting history.

## Dependencies

Prefer, in order: Zig/std or current repository functionality; small
repository-owned tooling; existing pinned dependencies; then a new dependency
whose capability clearly justifies its security, lifecycle, licensing, and
maintenance cost. A new production dependency requires an explicit rationale
and license review. Zero dependencies is not a goal.

## Exceptions and enforcement

Automate only rules with a low false-positive rate. Formatting, tests,
compatibility snapshots, bounded fuzzing, curated mutation tests, and targeted
repository validators belong in the canonical checks. Function length, line
width, recursion, ownership, semantic arithmetic, and assertion placement
remain review rules unless a syntax-aware check can identify them accurately.

A checked-in exception must identify the rule, file, symbol or narrow location,
and reason. Avoid directory-wide exemptions. Exceptions are reviewed when the
affected code changes and removed when their reason no longer applies.

## Representative examples

Use a fixed-width revision and checked transition:

```zig
const next_revision = std.math.add(u64, revision, 1) catch
    return error.RevisionOverflow;
```

Use a native index for a slice:

```zig
var exercise_index: usize = 0;
while (exercise_index < exercises.len) : (exercise_index += 1) { ... }
```

Validate before relying on an invariant:

```zig
if (commands.len > max_commands_per_batch) return error.BatchLimitExceeded;
std.debug.assert(commands.len <= max_commands_per_batch);
```

Keep malformed public input defined:

```zig
const id = Id.parse(input.id) catch return error.InvalidRequest;
```

Do not replace that boundary with `std.debug.assert(Id.parse(input.id) !=
null)`, and do not replace an allocator-taking adapter with a global static
buffer merely to resemble another project.
