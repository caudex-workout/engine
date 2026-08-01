# Catalog-management scope review

Status: accepted for CWE-130

Scope: public catalog-management capabilities required by the first-party
reference client

## Decision

Caudex will expose narrow, engine-owned exercise catalog commands and queries.
They belong with the public tracking/application contracts rather than the
stateless recommendation API or the database-independent persistence source
capabilities.

The dependency direction remains:

```text
host or optional adapter
    └── caudex_tracking catalog contracts
            └── canonical Exercise snapshot
```

Catalog management is optional host orchestration. The recommendation engine
continues to accept complete snapshots and does not read, write, or require a
managed catalog. A host may keep using its own catalog and `CatalogSource`.

## Capability classification

| Need | Classification | Decision |
| --- | --- | --- |
| Athlete | Deferred, host-owned | `Scope.athlete_id` remains a selector. Accounts, profiles, names, authorization, preferences, restrictions, and lifecycle are not catalog records. Recommendation requests continue to accept an explicit athlete snapshot. |
| Equipment | Deferred as records; IDs approved | Exercise and session snapshots may reference stable equipment IDs. Equipment names, inventory, locations, availability, brands, plates, and CRUD remain host-owned until a methodology requires reusable equipment invariants beyond identity. |
| Exercise | Approved | Add public create, edit, read, list, and bounded search capabilities for engine-relevant exercise fields. Stable exercise IDs are immutable after creation. |
| Alias | Approved as exercise data | Aliases are embedded values on an exercise, replaced through an exercise edit. They are not independently revisioned entities. Exact collisions across exercises are allowed and resolve as ambiguity; the engine and client never guess. |
| Archive | Approved | Archiving makes an exercise unavailable for new selection and new workout membership while preserving stable references and historical meaning. It is not deletion. |
| Restore | Approved | Restoration reverses archive state through a revision-checked command. It does not create a new exercise ID. |
| Annotation | Deferred, host-owned | Free-form notes, coaching cues, UI descriptions, media, provenance, and private annotations do not affect shared engine semantics. Methodology-relevant structured data may use documented canonical fields or `attributes` in supplied snapshots, but CWE-131 adds no general annotation store. |
| External ID | Deferred, host-owned | Provider/source mappings, import keys, URLs, and synchronization identities remain host mapping data. The public exercise ID is the sole Caudex identity; hosts may deterministically namespace it when combining providers. |

This classification does not approve athlete, equipment, annotation, or
external-ID commands in CWE-131.

## Approved managed exercise model

The public management record should contain:

- host scope key;
- immutable exercise ID;
- canonical exercise value;
- availability (`active` or `archived`);
- monotonic revision;
- explicit update timestamp supplied by the host.

Commands additionally carry a stable command ID. Create requires absence. Edit,
archive, and restore require an expected revision. A repeated command ID and
identical payload replays its accepted result; payload reuse conflicts. Storage
and transaction failures remain adapter errors rather than catalog issues.

Only fields already meaningful at an engine boundary are approved for managed
exercise values:

- display name;
- equipment IDs;
- movement tags;
- muscle contributions and exact decimal weights;
- unilateral flag;
- aliases;
- structured attributes supplied for methodology interpretation.

The management contract must validate reusable boundary invariants without
inventing UI policy:

- IDs and aliases are valid, non-empty UTF-8 values within documented bounds;
- the exercise ID cannot change during edit;
- repeated IDs within equipment, movement, muscle, or alias collections reject;
- muscle contribution weights retain canonical exact-decimal rules;
- results have deterministic ordering and bounded result counts;
- empty search text rejects rather than selecting the whole catalog;
- exact ID precedes exact name/alias and documented search;
- multiple friendly matches remain explicit ambiguity.

Display-name requirements, title casing, preferred units, exercise taxonomies,
alias ownership, and cross-scope uniqueness are host policy. Alias or name
collisions are not rejected globally because multiple legitimate exercises may
share them; callers receive candidate stable IDs.

## Archive and historical behavior

Archive is a reversible availability state, not a tombstone or erasure.

- Active catalog snapshots omit archived exercises by default.
- A direct management read may return an archived record.
- Archived exercises cannot be added to an active workout or newly selected by
  recommendation.
- Existing workout memberships and completed history retain their exercise ID.
- Archive does not rewrite history, methodology state, recommendations, or
  accepted workout data.
- Restore makes the same stable ID eligible again.
- Hard delete, purge, cascading deletion, and tombstone synchronization are not
  approved.

The optional SQLite adapter may retain archived rows indefinitely. Other hosts
may project equivalent behavior from their own stores.

## Canonical snapshot compatibility

The existing canonical `Exercise` shape remains unchanged. It is the portable
calculation snapshot, not a storage entity:

```text
ManagedExerciseRecord
├── canonical exercise ──► RecommendationRequest.catalog[]
├── availability ────────► include active / omit archived
├── revision ────────────► management concurrency only
└── updated_at ──────────► management audit only
```

No revision, archive flag, command ID, storage key, or external-ID map is added
to canonical request schemas. Existing direct-snapshot consumers, persistence
capabilities, fixtures, C/WASM contracts, and host mappings therefore remain
compatible. `CatalogSource.load` continues to return active canonical exercises
and does not become a management repository.

The current SQLite `replaceCatalog` capability remains a snapshot-loading
operation. CWE-131 may add management operations alongside it, but must not
change replacement semantics or make recommendation behavior database-dependent.

## Deferred scope

The following remain explicitly outside CWE-131:

- athlete/account/profile CRUD and authentication;
- equipment catalogs, inventory, availability schedules, and plate management;
- arbitrary annotations, notes, media, links, and coaching content;
- external provider identity registries, import reconciliation, and sync;
- hard delete, purge, tombstone replication, and undelete windows;
- bulk import/export, merge, duplicate detection, and taxonomy administration;
- arbitrary custom exercise schemas or database-owned recommendation fields;
- client configuration, favorites, recents, and hidden default exercises.

Future issues must justify any of these with concrete engine semantics and a
focused public contract. They are not implied by the approved exercise CRUD.

## Requirements for CWE-131

CWE-131 may implement only the approved exercise surface. It must:

- define typed catalog commands, queries, results, and stable issues before CLI
  syntax;
- keep deterministic validation free of allocation and persistence;
- use prepared SQL, transactions, stable command receipts, and revision checks;
- provide bounded, indexed search with deterministic ordering;
- test create/edit/archive/restore, replay, payload conflicts, stale revisions,
  archived selection, rollback, and canonical snapshot projection;
- avoid athlete, equipment-record, annotation, external-ID, deletion, import,
  and synchronization APIs.
