#!/usr/bin/env bash
set -euo pipefail

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-catalog.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --format json --scope catalog-integration)

created=$("$cli" "${common[@]}" exercise create bench-press --name "Bench Press" --alias press --equipment barbell --movement horizontal-push --command-id create-bench --occurred-at 2026-07-26T12:00:00Z)
grep -q '"kind":"caudex.exercise.created"' <<<"$created"
grep -q '"id":"bench-press"' <<<"$created"
grep -q '"revision":1' <<<"$created"

"$cli" "${common[@]}" exercise create incline-bench --name "Incline Bench" --alias press --command-id create-incline --occurred-at 2026-07-26T12:01:00Z >/dev/null

set +e
ambiguous=$("$cli" "${common[@]}" exercise show press 2>&1)
status=$?
set -e
test "$status" -eq 5
grep -q '"code":"client.exercise_ambiguous"' <<<"$ambiguous"
grep -q 'bench-press' <<<"$ambiguous"
grep -q 'incline-bench' <<<"$ambiguous"

edited=$("$cli" "${common[@]}" exercise edit bench-press --name "Competition Bench Press" --alias competition-bench --command-id edit-bench --occurred-at 2026-07-26T12:02:00Z)
grep -q '"kind":"caudex.exercise.edited"' <<<"$edited"
grep -q '"revision":2' <<<"$edited"

searched=$("$cli" "${common[@]}" exercise search competition --limit 10)
grep -q 'bench-press' <<<"$searched"

archived=$("$cli" "${common[@]}" exercise archive bench-press --command-id archive-bench --occurred-at 2026-07-26T12:03:00Z)
grep -q '"availability":"archived"' <<<"$archived"
active=$("$cli" "${common[@]}" exercise list --limit 10)
! grep -q 'bench-press' <<<"$active"
all=$("$cli" "${common[@]}" exercise list --limit 10 --include-archived)
grep -q 'bench-press' <<<"$all"

restored=$("$cli" "${common[@]}" exercise restore bench-press --command-id restore-bench --occurred-at 2026-07-26T12:04:00Z)
grep -q '"availability":"active"' <<<"$restored"

human=$("$cli" --database "$database" --scope catalog-integration exercise list --limit 10)
grep -q '^ID  NAME  STATUS  REVISION$' <<<"$human"
grep -q 'bench-press  Competition Bench Press  active  4' <<<"$human"
