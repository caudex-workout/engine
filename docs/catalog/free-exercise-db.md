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
| `equipment` | nullable source value plus `free-exercise-db.equipment:<normalized-value>` |
| `primaryMuscles` | source values plus stable muscle taxonomy IDs, projected with `primary` roles |
| `secondaryMuscles` | source values plus stable muscle taxonomy IDs, projected with `secondary` roles |
| `instructions` | ordered textual instructions, including upstream empty values |
| `category` | nullable source category |
| `images` | intentionally omitted |

Unknown/null source values remain null. The importer does not infer movement
patterns from exercise names, muscles, force, mechanic, or category because the
dataset does not provide enough evidence for a reliable taxonomy. The
`movementPatterns` array is consequently empty in version 1. Applications can
add separately curated values through host overrides.

## Projection and extension

The richer record is available through the optional Zig module and
`@caudex-workout/exercise-catalog`. Both expose deterministic search/filter,
canonical core projection, version/fingerprint, and merge/override helpers.
Host records replace matching IDs or extend the catalog; duplicate override IDs
are rejected and merged results are sorted by ID.

The canonical JSON asset at `catalog/generated/catalog.json` is suitable for C
and other language consumers. The recommendation engine never imports or
requires it.

## Media policy

No upstream image bytes, paths, or URLs are present in the generated artifact.
Their individual provenance was not sufficiently verified for first-party
redistribution. Exercise identity is independent of media, allowing a future
separately licensed media package without changing exercise IDs.
