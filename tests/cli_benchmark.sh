#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init cli-benchmark

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-benchmark.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --scope benchmark --format json)

measure() {
  local name=$1
  shift
  local start end
  start=$(date +%s%N)
  "$@" >/dev/null
  end=$(date +%s%N)
  printf '%s %s ns\n' "$name" "$((end - start))"
}

measure startup "$cli" version
measure database_open "$cli" --database "$database" database info
"$cli" "${common[@]}" exercise create bench --name Bench --command-id benchmark-catalog --occurred-at 2026-07-27T09:00:00Z >/dev/null
"$cli" "${common[@]}" workout start --command-id benchmark-start --workout benchmark-workout --started-at 2026-07-27T09:00:00Z --occurred-at 2026-07-27T09:00:00Z >/dev/null
"$cli" "${common[@]}" workout add-exercise bench --workout benchmark-workout --membership-id benchmark-membership --command-id benchmark-add --occurred-at 2026-07-27T09:01:00Z >/dev/null
"$cli" "${common[@]}" set log 100kg 5r --workout benchmark-workout --exercise benchmark-membership --set benchmark-set --command-id benchmark-log --occurred-at 2026-07-27T09:02:00Z >/dev/null
"$cli" "${common[@]}" workout finish --workout benchmark-workout --command-id benchmark-finish --occurred-at 2026-07-27T09:03:00Z >/dev/null
last=$("$cli" "${common[@]}" history last bench)
grep -Fq 'benchmark-workout' <<<"$last"
grep -Fq '2026-07-27T09:03:00Z' <<<"$last"
measure catalog_search "$cli" --database "$database" exercise search bench
measure history_list "$cli" --database "$database" history list
measure last_performance "$cli" "${common[@]}" history last bench
