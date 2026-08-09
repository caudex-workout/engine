#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI workout completion"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-end.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"
common=(--database "$database" --scope end-integration --format json)

"$cli" "${common[@]}" workout start --command-id start-finish --workout workout-finish \
  --started-at 2026-07-26T12:00:00Z --occurred-at 2026-07-26T12:00:00Z >/dev/null
finished=$("$cli" "${common[@]}" workout finish --workout workout-finish \
  --command-id finish-short --occurred-at 2026-07-26T12:01:00Z)
grep -q '"kind":"caudex.workout.finished"' <<<"$finished"
grep -q '"status":"completed"' <<<"$finished"

"$cli" "${common[@]}" workout start --command-id start-cancel --workout workout-cancel \
  --started-at 2026-07-26T12:02:00Z --occurred-at 2026-07-26T12:02:00Z >/dev/null
set +e
rejected=$("$cli" "${common[@]}" workout cancel --workout workout-cancel 2>&1 >/dev/null)
status=$?
set -e
test "$status" -eq 2
grep -q '"code":"client.confirmation_required"' <<<"$rejected"
still_active=$("$cli" "${common[@]}" workout show --workout workout-cancel)
grep -q '"status":"active"' <<<"$still_active"
cancelled=$("$cli" "${common[@]}" workout cancel --workout workout-cancel --yes \
  --command-id cancel-confirmed --occurred-at 2026-07-26T12:03:00Z)
grep -q '"kind":"caudex.workout.cancelled"' <<<"$cancelled"
grep -q '"status":"cancelled"' <<<"$cancelled"
