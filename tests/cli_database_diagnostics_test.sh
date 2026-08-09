#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI database diagnostics"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-diagnostics.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/caudex.sqlite"

check=$("$cli" --database "$database" --format json database check)
test "$check" = "{\"schemaVersion\":1,\"kind\":\"caudex.database.check\",\"data\":{\"databasePath\":\"$database\",\"integrity\":\"ok\"}}"

doctor=$("$cli" --database "$database" doctor)
grep -Fx "Database: $database" <<<"$doctor"
grep -Fx 'Integrity: ok' <<<"$doctor"
