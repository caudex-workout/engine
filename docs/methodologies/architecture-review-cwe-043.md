# Methodology architecture review after two implementations

Status: accepted for v0.1

Scope: `caudex.double-progression` and `caudex.rpe-top-set-backoff`

## Decision

The v0.1 custom Zig methodology interface is sufficient as a narrow,
build-time-registered dispatch boundary. It exposes stable implementation
metadata, config and state validation, recommendation, evaluation, explicit
scratch memory, and caller-owned output writers. Typed methodology modules
remain the primary direct Zig authoring API.

The interface is not a universal programming model. Implementations adapt their
own typed request, state, and result shapes at the registry boundary. The
engine must not require either methodology to use the other's decision stages
or force both through a candidate-scoring pipeline.

This review adds state schema version metadata and an explicit state-validation
callback. Those are shared lifecycle requirements demonstrated by both
implementations, not methodology semantics.

## Genuinely shared code

The shared core remains intentionally small:

- Exact `Decimal`, measurement, and unit primitives
- Canonical validation issues and caller-owned issue writing
- Exercise catalog and completed-history models
- Optional history summaries
- Registry identity, versions, validation, recommendation, and evaluation
  lifecycle
- Non-negative same-unit load rounding

Load rounding was duplicated with identical behavior in both methodologies.
It now lives in `src/load_math.zig`; each methodology publicly aliases the same
rounding config types so its JSON contract remains unchanged.

The existing history helpers remain optional. Double progression uses recent
set performance differently from RPE top-set/backoff, which derives exertion-
adjusted estimated 1RM evidence. Sharing the snapshot traversal does not imply
sharing the decision model.

## Deliberately methodology-owned behavior

The following similarities do not justify shared abstractions:

- Per-exercise state lookup: state entry types and update meanings differ.
- Missing-history warnings: the assumptions and user guidance differ.
- Explanation selection: stable codes describe methodology-specific rules.
- Performance analysis: double progression counts successful working sets,
  while RPE top-set/backoff interprets one top set's load, repetitions, and
  exertion.
- State proposal construction: double progression proposes load and target
  repetitions; RPE top-set/backoff proposes estimated 1RM.
- Percentage and Epley calculations: only the RPE methodology currently needs
  them.

No generic progression state, performance outcome, candidate pipeline, or
methodology base class is introduced.

## Extension pain points

- Custom implementations need small adapter functions to convert opaque
  registry views and writers to their typed API. This is acceptable for v0.1,
  but first-party adapters should establish a documented example before
  promising source compatibility.
- Scratch-memory requirements are implementation-owned and not yet
  discoverable from metadata. A future real host use case may justify a size
  query; speculative allocation negotiation is deferred.
- Config and state versions are scalar metadata. Migration discovery and
  compatibility ranges are not part of v0.1.
- Error translation at the registry boundary still needs the canonical
  protocol implementation. Methodology-specific expected outcomes must remain
  structured results rather than being collapsed into `MethodologyError`.
- Session-wide result construction will need adapters because the two
  methodologies have different native prescription shapes.

These are explicit integration costs, not justification for a DSL.

## Portable bundles

Portable methodology bundles remain deferred. Two native implementations do
not establish a safe or sufficiently expressive portable format. Open
questions include:

- How deterministic code and formula versions would be identified and audited
- How resource limits and termination would be enforced
- How bundle config/state schemas and migrations would be distributed
- How explanation catalogs would be namespaced and localized
- Whether portable execution can preserve exact arithmetic across runtimes
- What trust, signing, and compatibility model hosts would require

v0.1 therefore supports methodologies compiled into a Zig build and official
first-party methodologies compiled into distributed artifacts. It does not
define bytecode, a rule DSL, or arbitrary runtime plugins.
