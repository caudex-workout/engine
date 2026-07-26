# Caudex CLI

`caudex` is the reference command-line client for Caudex Workout Engine. The
walking skeleton provides command discovery, version reporting, and public
SQLite adapter metadata inspection:

```text
caudex --help
caudex version
caudex --database :memory: database info
caudex --format json database info
```

Build and run it from the repository root:

```sh
zig build caudex-cli
zig build run-caudex-cli -- --help
zig build test-caudex-cli
```

The client receives only the public `caudex`, `caudex_persistence`, and
`caudex_sqlite` packages from the root build graph. It must not import private
engine, adapter, or migration source paths, and it contains no SQL.

Database selection uses `--database PATH`, then `CAUDEX_DATABASE`, then the
platform default:

- Linux and other Unix-like systems use
  `$XDG_DATA_HOME/caudex/caudex.sqlite`, falling back to
  `$HOME/.local/share/caudex/caudex.sqlite`.
- macOS uses `$HOME/Library/Application Support/Caudex/caudex.sqlite`.
- Windows uses `%LOCALAPPDATA%\Caudex\caudex.sqlite`.

Missing parent directories are created when the database is opened.
