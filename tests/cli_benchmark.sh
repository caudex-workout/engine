#!/usr/bin/env bash
set -euo pipefail

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-benchmark.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"

measure() {
  local name=$1
  shift
  local start end
  start=$(date +%s)
  "$@" >/dev/null
  end=$(date +%s%N)
  printf '%s %s s\n' "$name" "$((end - start))"
}

measure startup "$cli" version
measure database_open "$cli" --database "$database" database info
"$cli" --database "$database" exercise create bench --name Bench >/dev/null
measure catalog_search "$cli" --database "$database" exercise search bench
measure history_list "$cli" --database "$database" history list
measure last_performance "$cli" --database "$database" history last bench
