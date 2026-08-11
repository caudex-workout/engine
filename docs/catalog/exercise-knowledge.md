# Exercise knowledge and catalog projections

This guide explains how to supply programming-relevant exercise knowledge to
Caudex. It complements [ADR-0008](../adr/ADR-0008-exercise-knowledge-architecture.md).

## Keep the two records separate

A rich catalog record belongs to its source or host. It can contain the title
shown in a UI, aliases, instructions, media, localized text, provider IDs,
editorial notes, licensing data, and source provenance. Caudex does not need
or persist that record to calculate a recommendation.

The engine receives a compact canonical `Exercise` projection. Its stable `id`
is the only exercise identity at the boundary. The optional `knowledge`
projection carries only facts a deterministic feature needs, such as:

- movement or variant facts;
- explicit equipment requirements;
- laterality, repetition semantics, and tracking dimensions;
- loading and progression capabilities;
- restriction tags; and
- typed, directed exercise relationships and evidence.

Do not use the compact projection as a database row. Conversely, do not send a
rich record merely because a host stores it. Project the facts needed for the
particular engine snapshot.

## Choose an authority deliberately

For each fact, retain its authority in `knowledge.evidence`:

| Authority | Appropriate use | Must not imply |
| --- | --- | --- |
| `source_provided` | Exact upstream values and provenance | A fact the upstream did not state |
| `caudex_curated` | Reviewed first-party normalization or relationship | Universal truth or full catalog coverage |
| `mechanically_derived` | Deterministic transformation with known inputs | A semantic or medical inference |
| `host_provided` | A host's curated/overridden programming facts | First-party endorsement |
| `unknown` | An assertion whose authority or confidence is not established | Compatible, incompatible, or safe behavior |

The host-provided request is authoritative for one engine call. If a host
merges multiple sources, it resolves conflicts before constructing the
snapshot and records the resulting evidence. Caudex does not fetch a catalog
or resolve an ID through a remote source during calculation.

## Start minimal; enrich when a feature needs it

The existing compact fields support a valid minimal catalog:

```ts
const catalog = [{
  id: "host:split-squat",
  name: "Split squat",
  equipmentIds: ["dumbbell"],
}];
```

Add structured knowledge only when it affects an intentional feature. A rich
host projection could declare that a movement is unilateral, repetitions are
per side, a dumbbell and bench are both required, and repetition-based loading
is compatible. Keep any UI-only prose, images, provider keys, and coaching
content in the host's rich record.

Absent knowledge stays unknown. Do not derive a capability, substitute,
movement pattern, or restriction solely from a display name, muscle list,
equipment label, or broad source category. When a host policy needs a known
answer, it must decide whether unknown means defer, exclude, use documented
legacy behavior, or ask the user.

`muscleContributions[].weight`, when supplied, is a unitless programming-credit
heuristic: it lets a host or future volume policy express relative credit among
the contributions of one exercise. It is not muscle activation, force,
hypertrophy, or a physiological percentage, and Caudex does not currently sum
it into weekly volume. Prefer roles alone when no defensible relative credit is
available; absence means unknown rather than zero.

Laterality and each tracking dimension's `scope` define logging meaning. For
example, `repetitions/per_side` distinguishes ten repetitions per side from ten
alternating repetitions total, while `load/per_hand` distinguishes a dumbbell
entry from total barbell load. Accepted custom exercises are serialized with
their canonical knowledge, and external first-party records retain the catalog
version/fingerprint used to project them. Historical consumers must use that
snapshot or pinned reference instead of consulting the latest catalog.

## Relationships are not state aliases

Use relationships to describe catalog navigation or candidate selection. A
variant, similar exercise, substitute, progression, or regression relationship
does not make two exercises identical and does not automatically share their
training history.

`exerciseId` identifies a catalog movement. `slotId` identifies a program
role. `stateId` identifies a progression lane. They intentionally differ. The
same exercise can appear in two slots with independent state, and a substitute
can be selected without inheriting the replaced exercise's state. Any state
routing or migration requires an explicit program/progression policy and
recorded provenance; catalog relationships alone never perform it.

## Replay-safe catalog changes

Retain the exact request/accepted-result snapshot used for a decision. A later
catalog edit, new enrichment release, renamed display value, or altered source
record must not reinterpret a prior recommendation or completed workout.

Version the knowledge schema and retain catalog release identifiers and
fingerprints with rich distribution metadata. An enrichment release must also
pin the source catalog version and fingerprint it was reviewed against. This
makes upgrades intentional: produce a new host snapshot for a new calculation
instead of resolving an old ID through a current catalog.

## Maintaining curated enrichment

Curated enrichment should be independently reviewable and deterministic.

- Keep its source/license, schema version, catalog version, and base
  fingerprint in the enrichment artifact.
- Validate every target ID, reject duplicate entries and relationships, and
  prohibit self relationships.
- Produce a coverage report that counts enriched records and the records and
  edges present for each knowledge category.
- Treat a missing enrichment entry as unknown, not as a negative assertion.
- Re-review enrichment when its pinned base catalog changes; do not silently
  carry it forward after IDs or source data drift.

Coverage is an operational maintenance signal. It does not prove correctness,
fitness suitability, or progression-state equivalence.

## Out of scope

Exercise knowledge does not make Caudex a hosted catalog, account system,
medical advisor, coaching-content platform, media distributor, synchronization
service, or universal taxonomy authority. It also does not require a catalog
package or require every custom exercise to be richly classified.
