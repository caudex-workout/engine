# ADR-0008: Layer Exercise Knowledge Over a Compact Engine Projection

- **Status:** Accepted
- **Date:** 2026-08-10
- **Clarifies:** ADR-0001, ADR-0003, ADR-0006, and ADR-0007
- **Preserves:** Host-owned snapshots, stable exercise IDs, deterministic
  replay, and separately owned progression state

## Context

An exercise catalog needs to support two very different jobs. Applications
need rich records for search, display, instructions, media, provenance, and
editorial maintenance. The engine needs a small, portable set of facts that a
methodology can use deterministically: stable identity, selection constraints,
equipment requirements, tracking semantics, and explicitly supported
capabilities.

Making the engine own a complete exercise encyclopedia would make its public
request shape large, difficult to version, and unsuitable for host-defined or
minimal catalogs. Treating every rich-catalog field as a programming fact would
also turn incomplete upstream data into unsupported inference.

## Decision

Caudex uses layered exercise knowledge. A host retains the rich catalog record
and supplies a compact engine projection with every calculation snapshot.

```text
rich source / editorial record / host record
                 |
                 | explicit projection and version selection
                 v
canonical Exercise + optional ExerciseKnowledge
                 |
                 v
deterministic recommendation, tracking, and evaluation snapshot
```

`Exercise.id` remains the durable catalog identity. `ExerciseKnowledge` is a
versioned, programming-relevant projection, not a second identity system and
not a storage entity. A projection may include, when known and relevant,
movement and variant facts, equipment requirements, laterality and repetition
semantics, supported tracking dimensions and progression capabilities,
restriction tags, and directed relationships. Instructions, images, URLs,
localized copy, provider payloads, editorial notes, and other rich-record
content stay outside the engine boundary.

The existing compact exercise fields remain useful compatibility projections.
When structured knowledge supplies the same fact, structured knowledge is
authoritative for that fact. This is deliberately additive: a minimal catalog
with only the established `Exercise` fields remains valid.

### Authority layers

Every knowledge-bearing catalog must preserve where a fact came from. The
following layers are distinct; a downstream consumer must not silently promote
one into another.

1. **Source-provided facts** are faithfully copied from an upstream catalog.
   They retain source provenance and say only what that source says.
2. **Caudex-curated enrichment** is an explicitly reviewed overlay for facts
   the source does not establish, such as a normalized movement pattern or a
   carefully curated relationship. It has its own version, fingerprint, and
   coverage report.
3. **Mechanically derived facts** are deterministic transformations with their
   derivation and input version recorded. They are not clinical, coaching, or
   semantic guesses.
4. **Host-provided facts** are the authority for the host's own rich record and
   for the exact request snapshot it supplies to Caudex. Hosts may use a
   different vocabulary or a private curated overlay, provided the projected
   values meet the public contract.

`KnowledgeEvidence` records the authority, source identifier/version, and
confidence associated with an assertion. It is provenance for a supplied
snapshot; it does not make a lower-confidence assertion true.

### Unknown is a valid result

Unknown, absent, and null values mean “not established,” not “false,” “safe,”
or “equivalent.” A source dataset's equipment label, name, muscle list, or
category must not be used to infer a movement pattern, progression capability,
injury suitability, or substitute.

For capability checks, the engine distinguishes compatible, incompatible, and
unknown. A policy that needs a known fact must state how it handles unknown
(for example, defer selection, retain the legacy behavior, or ask the host).
It must not silently convert unknown to compatible or incompatible. This keeps
partial catalogs useful without granting unsupported guarantees.

### Minimal and rich custom catalogs

A host can start with a minimal custom catalog:

```json
{
  "id": "host:split-squat",
  "name": "Split squat",
  "equipmentIds": ["dumbbell"]
}
```

That record is sufficient for the established engine behavior. A host that
needs richer programming behavior can supply an optional knowledge projection
alongside the same stable ID, for example explicit required equipment,
per-side repetition semantics, and declared progression capabilities. The
host chooses which rich fields remain private and which facts become part of
the replayable engine snapshot.

Custom records must not impersonate an upstream or curated authority. A host
override identifies itself as host-provided, keeps the host's stable exercise
ID, and has host-defined versioning. Replacing an exercise's display name or
editorial record does not create a new exercise identity.

### Relationships and progression state

Relationships are directed, typed catalog facts: a variant, substitute,
similar exercise, progression/regression suggestion, or a host-declared
shared-state reference. They support explanation, selection, and host policy;
they do not declare physiological equivalence.

In particular, neither a relationship nor a shared-progression-state reference
automatically permits progression-state reuse, migration, or merging. Per
ADR-0007, `stateId` identifies a progression lane and is deliberately distinct
from `exerciseId`. Only an explicit program/progression policy with recorded
provenance may route or migrate state between lanes. A substitute can therefore
be appropriate for a session while still starting with independent progression
state.

### Replay and versioning

The host supplies the exact compact projection used for each deterministic
request. Recommendation, tracking, evaluation, and replay consume that
snapshot rather than rereading a mutable catalog. Changing a rich record,
source snapshot, or enrichment release affects later host snapshots only; it
does not rewrite accepted recommendations, workouts, historical results, or
progression state.

Knowledge has a schema version. Catalog distributions additionally identify
their catalog version and content fingerprint; enrichment identifies both its
own version/fingerprint and the base catalog version/fingerprint it was built
against. A host replaying a prior operation must retain the prior request or
accepted-result snapshot, not resolve its IDs through whatever catalog happens
to be current.

### Enrichment maintenance and coverage

Curated enrichment is a maintained dataset, not a claim that every exercise is
fully classified. Each enrichment release must:

- pin and verify its base catalog version and fingerprint;
- reject missing, duplicate, self-referential, or invalid relationship targets;
- record its source/license and a deterministic enrichment fingerprint;
- publish coverage counts for enriched records and for each supported knowledge
  category; and
- leave unreviewed records and fields unknown.

Coverage measures only which records have explicitly curated facts. It is not a
quality score, completeness guarantee, medical classification, or promise that
two exercises can share progression state.

## Consequences

- The core stays independent of any particular catalog package, source, or
  editorial workflow.
- Hosts can use no catalog package, a small private catalog, the optional
  first-party catalog, or another source while retaining a common engine
  contract.
- Rich catalog packages can evolve presentation and source data without
  widening every engine request or changing exercise IDs.
- Features that require structured facts can be explicit about unknown data
  and authority instead of relying on name-based heuristics.

## Alternatives considered

- **Make the engine's canonical `Exercise` a full catalog record:** rejected
  because it couples calculation requests to media, prose, localization, and
  provider lifecycle.
- **Infer all knowledge from names or broad source fields:** rejected because
  the inference is neither reliable nor replayable as an authoritative fact.
- **Require rich knowledge for every exercise:** rejected because it prevents
  small and host-specific catalogs from using the existing engine surface.
- **Treat substitutes or variants as one progression state:** rejected because
  movement relationship, program role, and progression lane are different
  identities.

## Non-goals

This decision does not create a hosted catalog service, require the
first-party catalog, certify exercise safety or medical suitability, prescribe
coaching advice, infer missing exercise facts, provide a universal equipment
or anatomy taxonomy, manage media licenses, synchronize provider records, or
automatically migrate progression state. Those capabilities require separate
evidence, ownership, and public-contract decisions.
