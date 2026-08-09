# Bundled SQLite

The first-party Caudex CLI builds the SQLite adapter with the official SQLite
3.49.1 amalgamation (`sqlite3.c` and `sqlite3.h`). The source came from:

<https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip>

The SHA-256 checksum of that upstream archive is:

```text
6cebd1d8403fc58c30e93939b246f3e6e58d0765a5cd50546f16c00fd805d2c3
```

The extracted files are kept verbatim. Their SHA-256 checksums are:

```text
ff80c36ef1bb44eb357c7ff1d15be77540d41c28fb671088215a6cd12785c5d3  sqlite3.c
88da6f1963bc192dfa18a3a48b423cf1fbbb04f903202efe9a78e3a597473e18  sqlite3.h
```

The build explicitly sets `SQLITE_THREADSAFE=1`, matching SQLite's serialized
threading default. No optional extension, JSON, FTS, URI, or loadable-extension
flags are enabled or omitted; Caudex uses only the core SQLite API. Database
semantics such as foreign-key enforcement, journaling, and WAL remain under
the adapter and host's existing control.

To upgrade, download the official amalgamation for the selected version, verify
the archive checksum from the SQLite release page, replace these two extracted
files without reformatting them, record all three new checksums here, and update
the pinned version and source URL in the release workflow and local rehearsal
metadata.
