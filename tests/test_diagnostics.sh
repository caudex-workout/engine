#!/usr/bin/env bash

# Shared, intentionally small diagnostics for standalone integration tests.
# Call test_diagnostics_init immediately after `set -euo pipefail`.
test_diagnostics_init() {
  if [[ $# -ne 1 || -z ${1:-} ]]; then
    printf 'test diagnostics: expected one contract name\n' >&2
    return 2
  fi
  test_diagnostic_id=$1
  trap 'test_diagnostics_err "$?" "$BASH_COMMAND"' ERR
}

test_diagnostics_err() {
  local status=${1:-$?}
  local failed_command=${2:-$BASH_COMMAND}
  local failed_line=${BASH_LINENO[0]:-unknown}
  local failed_source=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  local failed_function=${FUNCNAME[1]:-main}
  [[ $- == *e* ]] || return 0
  printf '\n%s: command failed\nsource: %s:%s\nfunction: %s\ncommand: %s\nexit: %s\n' \
    "$test_diagnostic_id" "$failed_source" "$failed_line" \
    "$failed_function" "$failed_command" "$status" >&2
  return "$status"
}

test_diagnostics_assert_equal() {
  local label=$1
  local expected=$2
  local actual=$3
  local assertion_line=${BASH_LINENO[0]:-unknown}
  local assertion_source=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  if [[ "$expected" != "$actual" ]]; then
    printf '\n%s: %s mismatch\nsource: %s:%s\nexpected: %s\nactual:   %s\n' \
      "$test_diagnostic_id" "$label" "$assertion_source" "$assertion_line" \
      "$expected" "$actual" >&2
    return 1
  fi
}
