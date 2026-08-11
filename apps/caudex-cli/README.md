# Caudex CLI

`caudex` is the reference command-line client for Caudex Workout Engine. It
provides a line-oriented workflow for local workout tracking, history, catalog
management, database maintenance, and automation:

```text
caudex --help
caudex version
caudex --database :memory: database info
caudex --format json database info
caudex workout start
```

## Installation and runtime baseline

Released binaries are distributed only through the immutable GitHub Release
for the matching `vX.Y.Z` tag. The release matrix verifies x86_64 and aarch64 Linux GNU, Apple Silicon
macOS, and x86_64 Windows GNU. Prebuilt macOS releases target Apple Silicon.
Intel Macs can build Caudex from source. The initial archives are not
platform-code-signed. Every release binary statically includes the pinned
official SQLite 3.49.1 amalgamation.

Building from the tagged source is also supported. Use Zig 0.16.0 and the
safe release profile:

```sh
zig build caudex-cli -Doptimize=ReleaseSafe
```

Run `caudex version` after installation to record the CLI, engine, contract,
and SQLite schema versions. `caudex --help` is the authoritative overview of
the command grammar, while `caudex command-reference` emits a shell- and
documentation-friendly reference.

Build and run it from the repository root:

```sh
zig build caudex-cli
zig build run-caudex-cli -- --help
zig build test
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

The application-created data directory is private to the current user. A
database, config file, batch input, or backup path that is a symlink is
rejected. Backups must be new regular files; restores must name an existing
regular SQLite file.

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

## Program planning snapshots

The `program` noun demonstrates the public deterministic planner without
turning the workout database into hidden engine state. It can list and inspect
the four structural presets, create an initial instance/state snapshot, resolve
the next intent, and calculate an advancement proposal:

```sh
caudex program list
caudex --format json program inspect block
caudex --format json --athlete athlete-7 \
  program start rotation --instance program-42
caudex --format json program next rotation --instance program-42
caudex --format json program advance rotation --instance program-42 \
  --revision 0 --block 0 --microcycle 0 --cursor 0 --completed 0
```

`advance` prints a proposal; it does not persist or silently accept it. To
continue, pass the proposal's `nextState` fields to `status`, `next`, or a later
`advance` call. Fixed-weekday plans require the host's explicit civil-date
interpretation:

```sh
caudex --format json program next weekdays \
  --date 2026-08-10 --weekday monday
caudex --format json program pause rotation --instance program-42 --revision 1
caudex --format json program end rotation --instance program-42 --revision 1
```

The TUI program screen exposes the same inspect/start/status/next/advance/
pause/end intents through its application-action boundary. Rendering never
advances a cursor; acceptance remains an explicit host action.

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

## First workout

This complete shell sequence creates a catalog entry, starts a workout, adds
an exercise, logs a set, finishes the workout, and reads it from a new process.
Supply IDs and timestamps explicitly when a script must be repeatable:

```sh
set -euo pipefail
db="${TMPDIR:-/tmp}/caudex-first-workout.sqlite"

caudex --database "$db" exercise create bench-press \
  --name "Bench Press" --equipment barbell \
  --command-id catalog-create --occurred-at 2026-07-26T12:00:00Z
caudex --database "$db" workout start \
  --command-id workout-start --workout workout-1 \
  --started-at 2026-07-26T12:01:00Z --occurred-at 2026-07-26T12:01:00Z
caudex --database "$db" workout add-exercise bench-press \
  --workout workout-1 --membership-id membership-1 \
  --command-id exercise-add --occurred-at 2026-07-26T12:02:00Z
caudex --database "$db" set log 70kg 8r @2rir \
  --workout workout-1 --exercise membership-1 --set set-1 \
  --command-id set-log --occurred-at 2026-07-26T12:03:00Z
caudex --database "$db" workout finish --workout workout-1 \
  --command-id workout-finish --occurred-at 2026-07-26T12:04:00Z
caudex --database "$db" history show workout-1
```

The line client accepts a short workout with no logged sets, but logging a set
is useful for a completed-history and `history last` smoke check. Repeat a
command with the same command ID to obtain the recorded idempotent result.

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

## Shell scripting, JSON, and exit codes

Use `--format json` for machine consumers. Successful data is written to
stdout; failures are written to stderr, leaving stdout empty. JSON documents
have `schemaVersion: 1` and a stable `kind`. `--quiet` suppresses successful
human and JSON output without changing the operation.

```sh
set -euo pipefail
result=$(caudex --database "$db" --format json \
  workout show --workout workout-1)
printf '%s\n' "$result" | jq -r '.data.workoutId'
```

`caudex batch FILE` accepts bounded JSON Lines input. Each line contains an
`args` array of ordinary CLI arguments, and each result is emitted as a JSON
document. Batch files are limited to 64 KiB and 100 operations.

| Exit | Meaning |
| ---: | --- |
| 0 | Success |
| 2 | Syntax or invalid arguments |
| 3 | Validation issue |
| 4 | Not found |
| 5 | Ambiguous match |
| 6 | Revision or state conflict |
| 7 | Database busy |
| 8 | Database, migration, or transfer failure |
| 70 | Unexpected runtime failure |
| 130 | User interruption or declined confirmation |

## Database, backup, and restore

`database info` reports the adapter and schema compatibility boundary;
`database check` and `doctor` run SQLite integrity checks. A backup is a
consistent SQLite copy and must target a new regular path:

```sh
caudex --database "$db" database info
caudex --database "$db" database check
caudex --database "$db" database backup "$db.backup"
caudex --database "$db" database restore "$db.backup" --yes
```

Restore validates the source before copying it into the selected database.
Keep backups with the same user and access controls as the database. The CLI
does not encrypt, upload, or rotate backups.

## TUI and accessibility

The application-owned TUI facade uses the tested low-level terminal lifecycle;
the line CLI remains the supported accessible fallback. The key conventions
are:

- `↑`/`k` and `↓`/`j` navigate; `Tab` moves forward.
- `Enter` or `Space` selects; `?` or `F1` opens help.
- `Esc` cancels a prompt; `q` quits.
- Resize and interruption restore the terminal before returning.

Color is decorative and `NO_COLOR` disables styling. Narrow terminals retain
IDs and status labels, with ASCII fallbacks for Unicode glyphs. See
[`TUI-COMPATIBILITY.md`](TUI-COMPATIBILITY.md) for the verified platform and
runtime baseline.

## Troubleshooting

- **`caudex: command not found`:** add the extracted release directory to
  `PATH`, or invoke the source build from `zig-out/bin/caudex`.
- **SQLite library error:** release binaries include SQLite and do not require
  a separately installed SQLite runtime. Source builds use the same bundled
  amalgamation.
- **Database is busy:** retry after the other process closes its transaction;
  the CLI uses a bounded busy timeout and returns exit 7 when it expires.
- **Newer schema:** install the matching Caudex release. The CLI refuses to
  mutate a database created by a newer schema.
- **Symlink or permission error:** use a regular file in a user-owned,
  private directory. The CLI intentionally refuses symlink transfer paths.
- **Terminal rendering is unsuitable:** set `NO_COLOR=1`, use a monochrome
  terminal, or use the line CLI with `--format json`.

For a host application that needs recommendation generation rather than local
tracking, use the stateless engine and public adapter contracts documented in
the [Zig integrator guide](../../docs/zig-integrator-guide.md). A host owns its
storage and presentation; it should not copy this CLI's formatting or private
database SQL.
