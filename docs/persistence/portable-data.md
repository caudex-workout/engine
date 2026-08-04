# Portable data protocol v1

Caudex portable data is a versioned public document, independent of SQLite
tables and IndexedDB object stores. It can carry scoped catalog references or
embedded custom exercises, templates, active tracking snapshots, completed
canonical workouts, accepted recommendations, methodology states, and workflow
recovery records. It deliberately excludes accounts, credentials, encryption
keys, and other host secrets.

Every document supplies `schemaVersion` and `exportedAt`. Records are sorted by
their stable scoped key, exact decimals remain strings, and each record kind is
limited to 10,000 entries. Canonical decoding additionally limits a document to
4 MiB, 32 nesting levels, 100,000 structural items, and 64 KiB strings.

Imports support `merge` and `replace`. Merge conflict policies are `reject`,
`keepExisting`, and `overwrite`; conflicts are structured `portable.conflict`
issues. `dryRun` defaults to true and performs validation and conflict discovery
without writes. Replace affects only scopes named by the document. Validation
checks versions, bounds, timestamps, exact decimals, units, stable ordering,
duplicate keys, active-workout consistency, and catalog references before an
adapter mutates durable state.

SQLite applies an import in one `BEGIN IMMEDIATE` transaction. IndexedDB uses
one readwrite transaction containing all reads, conflict checks, deletes, and
writes; it performs no unrelated awaits inside that transaction. Arbitrary
custom adapters cannot be assumed to share a transaction with either adapter.

The low-level npm API exposes `exportPortable(document)` for deterministic
canonical validation/encoding and `validatePortableImport(request)` for a
structured dry-run plan. Adapter APIs expose `exportPortable(query)` and
`importPortable(request)`. Zig uses `caudex_portable` and the optional
`PortableDataStore` persistence capability. C and WASM use the same
`exportPortable` and `validatePortableImport` message operations.

The deterministic fixture at `fixtures/portable/export-v1.json` is exercised by
direct Zig, C/WASM/npm, SQLite, and IndexedDB tests. The external catalog
reference is retained across adapter transfers rather than being converted into
an unverified embedded exercise.
