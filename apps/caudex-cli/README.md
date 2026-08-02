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

## Compatibility contract

The command grammar is the generated `caudex command-reference` output. The
stable machine interface is versioned JSON (`schemaVersion: 1`) on stdout;
diagnostics are written to stderr with the selected human or JSON format. Exit
classes are stable: `0` success, `2` syntax, `3` validation, `4` not found,
`5` ambiguity, `6` conflict, `7` busy, `8` database, `70` runtime, and `130`
interrupted. Human table wording, spacing, and color are intentionally not a
compatibility guarantee.

Database paths resolve as documented above. `caudex version` reports the
independent CLI, engine/schema, persistence-contract, tracking-contract, and
SQLite adapter/schema boundaries so automation can record an exact contract
set. Older supported SQLite files migrate forward; a newer schema is rejected
without mutation.

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

Catalog examples are created through the same public client surface; no SQL or
private seed command is required:

```sh
caudex --database caudex.sqlite exercise create bench-press \
  --name "Bench Press" --alias bench --equipment barbell
caudex --database caudex.sqlite exercise search bench
caudex --database caudex.sqlite exercise edit bench-press \
  --name "Competition Bench Press"
caudex --database caudex.sqlite exercise archive bench-press
caudex --database caudex.sqlite exercise restore bench-press
```

Completed workout history is available from a fresh client process:

```sh
caudex --database caudex.sqlite history list --from 2026-07-01T00:00:00Z
caudex --database caudex.sqlite history exercise bench-press
caudex --database caudex.sqlite --format json history last bench-press
caudex --database caudex.sqlite history correct-set --yes \
  --workout workout-example --exercise membership-example --set set-example 8r @8rpe
```

`history correct-set` requires `--yes` outside a TTY. It is revision-checked,
idempotent when retried with the same command ID, and never changes methodology
state automatically.

Every noun and verb accepts a trailing `--help`. The documented long nouns are
`workout`, `set`, `exercise`, and `history`; the additive aliases `w`, `s`,
`e`, and `h` are convenient for interactive use. Client-only presentation
preferences are inspectable and atomically stored outside the workout database:

```sh
caudex config path
caudex config show
caudex config set color never
caudex config set table wide
```

For bounded automation, `caudex batch FILE` accepts at most 100 JSON Lines
records (64 KiB total). Each record has an `args` array containing ordinary CLI
arguments; each result is emitted as its usual versioned JSON document. Batch
operations preserve normal command IDs and retry behavior.

`--format human|json` selects human output or a versioned JSON envelope.
Diagnostics use stderr and the same selected format; requested data remains on
stdout. `--color auto|always|never` controls human styling, while JSON and
non-terminal automatic output never contain ANSI sequences. `NO_COLOR`
disables styling.

Shell completion never opens the workout database. Install the output that
matches your shell, or inspect the generated command reference:

```sh
caudex completion bash >>"${HOME}/.bashrc"
caudex completion zsh >>"${HOME}/.zshrc"
caudex completion fish >~/.config/fish/completions/caudex.fish
caudex command-reference
```
