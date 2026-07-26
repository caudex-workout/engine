# Caudex CLI

`caudex` is the reference command-line client for Caudex Workout Engine. The
walking skeleton provides command discovery, version reporting, and public
SQLite adapter metadata inspection:

```text
caudex --help
caudex version
caudex --database :memory: database info
caudex --format json database info
caudex workout start
```

Build and run it from the repository root:

```sh
zig build caudex-cli
zig build run-caudex-cli -- --help
zig build test-caudex-cli
```

The client receives only the public `caudex`, `caudex_persistence`,
`caudex_sqlite`, and `caudex_tracking` packages from the root build graph. It
must not import private engine, adapter, or migration source paths, and it
contains no SQL.

Database selection uses `--database PATH`, then `CAUDEX_DATABASE`, then the
platform default:

- Linux and other Unix-like systems use
  `$XDG_DATA_HOME/caudex/caudex.sqlite`, falling back to
  `$HOME/.local/share/caudex/caudex.sqlite`.
- macOS uses `$HOME/Library/Application Support/Caudex/caudex.sqlite`.
- Windows uses `%LOCALAPPDATA%\Caudex\caudex.sqlite`.

Missing parent directories are created when the database is opened.

The local reference client uses host scope `local` unless `--scope ID` is
provided; `--athlete ID` selects an optional athlete within that scope. Workout
start generates secure command and workout IDs plus a current UTC timestamp.
For repeatable automation and idempotent retries, supply all values explicitly:

```sh
caudex --database caudex.sqlite --format json workout start \
  --command-id command-example \
  --workout workout-example \
  --started-at 2026-07-26T12:00:00Z \
  --occurred-at 2026-07-26T12:00:00Z

caudex --database caudex.sqlite --format json \
  workout show --workout workout-example
```

`--format human|json` selects human output or a versioned JSON envelope.
Diagnostics use stderr and the same selected format; requested data remains on
stdout. `--color auto|always|never` controls human styling, while JSON and
non-terminal automatic output never contain ANSI sequences. `NO_COLOR`
disables styling.
