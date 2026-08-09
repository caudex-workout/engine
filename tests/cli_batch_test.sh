#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI batch contract"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-batch.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
batch="$temporary_directory/commands.jsonl"
printf '%s\n' \
  '{"args":["--database","'"$database"'","workout","start","--command-id","batch-start","--workout","batch-workout","--started-at","2026-07-26T12:00:00Z","--occurred-at","2026-07-26T12:00:00Z"]}' \
  '{"args":["--database","'"$database"'","workout","start","--command-id","batch-start","--workout","batch-workout","--started-at","2026-07-26T12:00:00Z","--occurred-at","2026-07-26T12:00:00Z"]}' >"$batch"

result=$("$cli" batch "$batch")
test "$(grep -c '"kind":"caudex.workout.start"' <<<"$result")" -eq 2
grep -q '"disposition":"applied"' <<<"$result"
grep -q '"disposition":"replayed"' <<<"$result"
