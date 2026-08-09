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
  local failed_command=$BASH_COMMAND
  local failed_line=${BASH_LINENO[0]:-unknown}
  local failed_source=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  [[ $- == *e* ]] || return 0
  printf '[%s] FAILED: %s:%s: %s (exit %s)\n' \
    "$test_diagnostic_id" "$failed_source" "$failed_line" "$failed_command" "$status" >&2
  return "$status"
}

test_diagnostics_assert_equal() {
  local label=$1
  local expected=$2
  local actual=$3
  if [[ "$expected" != "$actual" ]]; then
    printf '[%s] %s mismatch\nexpected: %s\nactual:   %s\n' \
      "$test_diagnostic_id" "$label" "$expected" "$actual" >&2
    return 1
  fi
}
