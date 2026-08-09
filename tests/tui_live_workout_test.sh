#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI/TUI live-workout integration"
cli=$1
harness=$2
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-tui-e2e.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
start=$(date +%s%N)
"$harness" "$database"
render_input_ns=$(($(date +%s%N) - start))
start=$(date +%s%N)
result=$("$cli" --database "$database" --scope tui-e2e --format json history show tui-workout)
fresh_query_ns=$(($(date +%s%N) - start))
grep -Fq '"workoutId":"tui-workout"' <<<"$result"
grep -Fq '"status":"completed"' <<<"$result"
printf 'tui_render_input_baseline_ns=%s fresh_cli_query_baseline_ns=%s\n' "$render_input_ns" "$fresh_query_ns"
