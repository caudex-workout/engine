#!/usr/bin/env bash

# Shared, intentionally small diagnostics for standalone integration tests.
# Call test_diagnostics_init immediately after `set -euo pipefail`.
test_diagnostics_init() {
  test_diagnostic_id=$1
  printf '[%s] running\n' "$test_diagnostic_id"
  trap test_diagnostics_err ERR
}

test_diagnostics_err() {
  local status=$?
  [[ $- == *e* ]] || return 0
  printf '[%s] FAILED: command at line %s: %s (exit %s)\n' \
    "$test_diagnostic_id" "$LINENO" "$BASH_COMMAND" "$status" >&2
  return "$status"
}
