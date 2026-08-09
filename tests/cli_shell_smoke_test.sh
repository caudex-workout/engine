#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI shell compatibility"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-shell-smoke.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"

# A scheduler-safe invocation supplies every generated value explicitly.
scheduled=$("$cli" --database "$database" --format json workout start \
  --command-id scheduled-start \
  --workout scheduled-workout \
  --started-at 2026-07-27T09:00:00Z \
  --occurred-at 2026-07-27T09:00:00Z)
grep -Fq '"kind":"caudex.workout.start"' <<<"$scheduled"
grep -Fq '"workoutId":"scheduled-workout"' <<<"$scheduled"

# Command substitution and the additive short aliases work in shell scripts.
workout=$("$cli" --database "$database" --format json w show --workout scheduled-workout)
grep -Fq '"workoutId":"scheduled-workout"' <<<"$workout"
alias_output=$("$cli" --database "$database" e list --limit 1)
test "$alias_output" = 'No exercises.'

# JSON remains on stdout while failures retain their documented exit code and stderr.
set +e
invalid_stdout=$("$cli" --database "$database" --format json database unknown 2>"$temporary_directory/invalid.stderr")
invalid_exit=$?
set -e
test "$invalid_exit" -eq 2
test -z "$invalid_stdout"
grep -Fq '"code":"client.invalid_arguments"' "$temporary_directory/invalid.stderr"

# Quiet successful commands write no stdout, making scheduled jobs log-free.
quiet_stdout=$("$cli" --database "$database" --quiet e list --limit 1)
test -z "$quiet_stdout"

# Closing a pipe early is treated as a successful SIGPIPE-style consumer exit.
"$cli" --database "$database" database info | true
"$cli" completion fish | head -n 1 | grep -Fx "complete -c caudex -f -a 'database'"
