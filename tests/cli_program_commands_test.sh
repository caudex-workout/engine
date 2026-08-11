#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI program planning" "test-cli-programs"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-programs.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
database="$temporary_directory/should-not-exist/caudex.sqlite"

test_diagnostics_run_capture "list presets" env CAUDEX_DATABASE="$database" "$cli" program list
test_diagnostics_assert_status "list presets" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "rotation preset" 'rotation' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "structured block preset" 'block' "$test_diagnostics_last_stdout"
test_diagnostics_assert_not_exists "program list database side effect" "$database"

test_diagnostics_run_capture "inspect structured block" "$cli" --format json program inspect block
test_diagnostics_assert_status "inspect structured block" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "inspect kind" '"kind":"caudex.program.inspect"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "inspect deload" '"phase":"deload"' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "start rotation" "$cli" --format json --athlete athlete-7 program start rotation --instance run-42
test_diagnostics_assert_status "start rotation" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "active lifecycle" '"lifecycle":"active"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "initial state" '"revision":0' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "next rotation" "$cli" --format json program next rotation --instance run-42
test_diagnostics_assert_status "next rotation" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "upper first" '"roleId":"upper-a"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "rotation provenance" '"schedulingProvenance":"rotation_next"' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "advance rotation" "$cli" --format json program advance rotation --instance run-42
test_diagnostics_assert_status "advance rotation" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "proposal kind" '"kind":"caudex.program.advancement_proposed"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "proposal revision" '"revision":1' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "proposal cursor" '"sessionCursor":1' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "fixed weekday requires host date" "$cli" program next weekdays
test_diagnostics_assert_status "fixed weekday requires host date" 2 "$test_diagnostics_last_status"
test_diagnostics_run_capture "fixed weekday next" "$cli" --format json program next weekdays --date 2026-08-10 --weekday monday
test_diagnostics_assert_status "fixed weekday next" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "weekday provenance" '"schedulingProvenance":"weekday_match"' "$test_diagnostics_last_stdout"
test_diagnostics_assert_contains "scheduled date" '"scheduledDate":"2026-08-10"' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "structured deload status" "$cli" --format json program status block --instance run-block --revision 10 --block 1 --microcycle 0 --cursor 0 --completed 10
test_diagnostics_assert_status "structured deload status" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "structured block index" '"blockIndex":1' "$test_diagnostics_last_stdout"

test_diagnostics_run_capture "pause instance" "$cli" --format json program pause rotation --instance run-42 --revision 1 --cursor 1
test_diagnostics_assert_status "pause instance" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "paused lifecycle" '"lifecycle":"paused"' "$test_diagnostics_last_stdout"
test_diagnostics_run_capture "end instance" "$cli" --format json program end rotation --instance run-42 --revision 1 --cursor 1
test_diagnostics_assert_status "end instance" 0 "$test_diagnostics_last_status"
test_diagnostics_assert_contains "ended lifecycle" '"lifecycle":"ended"' "$test_diagnostics_last_stdout"
