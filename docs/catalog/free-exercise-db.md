# Optional free-exercise-db catalog

Caudex's optional first-party catalog is generated from
[`yuhonas/free-exercise-db`](https://github.com/yuhonas/free-exercise-db) commit
`b0eed061e1c832b3ed815fbaa4b45b3cdc14df49`. The source manifest records the
repository, commit, import date, Unlicense identifier, upstream schema and data
hashes, transformation-tool version, and normalized output fingerprint.

Ordinary builds, tests, package installation, consumer compilation, and runtime
initialization perform no network access. Maintainers explicitly update the
snapshot with:

```bash
zig build update-exercise-catalog \
  -Dcatalog-commit=<exact-40-character-upstream-commit>
```

Offline drift verification is:

```bash
zig build test-exercise-catalog
```

## Stable IDs and mapping

Caudex IDs are `free-exercise-db:<upstream-id>`. They retain the exact stable
source ID and therefore do not change when a display name is corrected. Exact
duplicate source IDs and collisions in the normalized search form are rejected
by the generator rather than silently renamed.

| Upstream field | Caudex catalog field |
| --- | --- |
| `id` | `upstreamId`, stable Caudex `id`, and source provenance |
| `name` | `name` |
| `force` | nullable `force` (`pull`, `push`, or `static`) |
| `level` | nullable `difficulty` |
| `mechanic` | nullable `mechanic` |
| `equipment` | source value/ID plus normalized `caudex.equipment:<value>` ID |
| `primaryMuscles` | source values/IDs plus normalized muscle IDs, projected with `primary` roles |
| `secondaryMuscles` | source values/IDs plus normalized muscle IDs, projected with `secondary` roles |
| `instructions` | ordered textual instructions, including upstream empty values |
| `category` | nullable source category |
| `images` | intentionally omitted |

Unknown/null source values remain null. The importer does not infer movement
patterns from exercise names, muscles, force, mechanic, or category because the
dataset does not provide enough evidence for a reliable taxonomy. The base
projection consequently leaves `movementPatterns` empty. Separately versioned
curated enrichment or host-provided facts may add explicit values.

## Projection, enrichment, and extension

The generated document is a rich catalog record, not the engine request shape.
It preserves source-facing fields such as instructions, source values, and
provenance. Consumers project only the compact canonical `Exercise` fields and
optional programming-relevant knowledge needed for a deterministic engine
call. See [exercise knowledge and catalog projections](exercise-knowledge.md)
for the authority and replay rules.

Schema version 2 adds a separately versioned Caudex-curated enrichment overlay.
The generated document records the base and enrichment versions and
fingerprints, plus the number of enriched records. It deliberately leaves
unreviewed knowledge absent rather than inferring it from the upstream name,
muscle list, equipment label, or category. Curated knowledge carries explicit
`caudex_curated` evidence with source, version, and confidence.

The enrichment artifact is pinned to the exact upstream commit and normalized
base fingerprint. Before an enrichment change is accepted, the generator
validates that every entry and relationship targets an existing source ID and
rejects duplicates and self references. Maintainers can inspect its factual
coverage with:

```bash
node catalog/tools/generate.mjs --coverage
```

The report measures the records and relationship edges explicitly enriched; it
is not a completeness, safety, or progression-state-equivalence claim.

The richer record is available through the optional Zig module and
`@caudex-workout/exercise-catalog`. Both expose deterministic search/filter,
canonical core projection, version/fingerprint, and merge/override helpers.
Host records replace matching IDs or extend the catalog; duplicate override IDs
are rejected and merged results are sorted by ID. Host overrides remain
host-provided facts and must retain their own authority and versioning.

The canonical JSON asset at `catalog/generated/catalog.json` is suitable for C
and other language consumers. The recommendation engine never imports or
requires it.

## Media policy

No upstream image bytes, paths, or URLs are present in the generated artifact.
Their individual provenance was not sufficiently verified for first-party
redistribution. Exercise identity is independent of media, allowing a future
separately licensed media package without changing exercise IDs.
