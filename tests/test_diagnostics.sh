#!/usr/bin/env bash

# Shared, intentionally small diagnostics for standalone integration tests.
# Call test_diagnostics_init immediately after `set -euo pipefail`.
test_diagnostics_init() {
  if [[ $# -lt 1 || $# -gt 2 || -z ${1:-} ]]; then
    printf 'test diagnostics: expected a contract name and optional build target\n' >&2
    return 2
  fi
  test_diagnostic_id=$1
  test_diagnostics_reproduce=${2:-}
  test_diagnostics_last_label=
  test_diagnostics_last_command=
  test_diagnostics_last_status=
  test_diagnostics_last_stdout=
  test_diagnostics_last_stderr=
  test_diagnostics_reported=0
  trap 'test_diagnostics_err "$?" "$BASH_COMMAND"' ERR
}

test_diagnostics_err() {
  local status=${1:-$?}
  local failed_command=${2:-$BASH_COMMAND}
  local failed_line=${BASH_LINENO[0]:-unknown}
  local failed_source=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  local failed_function=${FUNCNAME[1]:-main}
  [[ $- == *e* ]] || return 0
  if [[ ${test_diagnostics_reported:-0} == 1 ]]; then
    test_diagnostics_reported=0
    return "$status"
  fi
  printf '\n%s: command failed\nsource: %s:%s\nfunction: %s\ncommand: %s\nexit: %s\n' \
    "$test_diagnostic_id" "$failed_source" "$failed_line" \
    "$failed_function" "$failed_command" "$status" >&2
  test_diagnostics_print_reproduce
  return "$status"
}

test_diagnostics_command_string() {
  local result=
  local argument
  local quoted
  for argument in "$@"; do
    printf -v quoted '%q' "$argument"
    if [[ -n $result ]]; then result+=" "; fi
    result+=$quoted
  done
  printf '%s' "$result"
}

test_diagnostics_print_block() {
  local label=$1
  local value=$2
  local maximum=12000
  printf '%s:\n' "$label" >&2
  if [[ -z $value ]]; then
    printf '  <empty>\n' >&2
  elif ((${#value} > maximum)); then
    printf '%s\n' "${value:0:maximum}" >&2
    printf '  [... output truncated at %d bytes]\n' "$maximum" >&2
  else
    printf '%s\n' "$value" >&2
  fi
}

test_diagnostics_print_reproduce() {
  if [[ -n ${test_diagnostics_reproduce:-} ]]; then
    printf 'Reproduce:\n  zig build %s --summary all\n' \
      "$test_diagnostics_reproduce" >&2
  fi
}

test_diagnostics_run_capture() {
  local label=$1
  shift
  if [[ $# -eq 0 ]]; then
    test_diagnostics_fail "$label" "no command was provided"
    return 1
  fi
  local temporary_directory
  temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-diagnostics.XXXXXX")
  local stdout_file="$temporary_directory/stdout"
  local stderr_file="$temporary_directory/stderr"
  local status
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    status=0
  else
    status=$?
  fi
  test_diagnostics_last_label=$label
  test_diagnostics_last_command=$(test_diagnostics_command_string "$@")
  test_diagnostics_last_status=$status
  test_diagnostics_last_stdout=$(<"$stdout_file")
  test_diagnostics_last_stderr=$(<"$stderr_file")
  rm -rf -- "$temporary_directory"
}

test_diagnostics_assert_status() {
  local label=$1
  local expected=$2
  local actual=$3
  if [[ "$expected" != "$actual" ]]; then
    test_diagnostics_reported=1
    printf '\n%s: %s command failed\nsource: %s:%s\n' \
      "$test_diagnostic_id" "$label" "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" \
      "${BASH_LINENO[0]:-unknown}" >&2
    printf 'command:\n  %s\nexpected exit status:\n  %s\nactual exit status:\n  %s\n' \
      "${test_diagnostics_last_command:-unknown}" "$expected" "$actual" >&2
    test_diagnostics_print_reproduce
    test_diagnostics_print_block "stdout" "${test_diagnostics_last_stdout:-}"
    test_diagnostics_print_block "stderr" "${test_diagnostics_last_stderr:-}"
    return 1
  fi
}

test_diagnostics_assert_contains() {
  local label=$1
  local expected=$2
  local actual=$3
  if [[ "$actual" != *"$expected"* ]]; then
    test_diagnostics_reported=1
    printf '\n%s: %s mismatch\nsource: %s:%s\n' \
      "$test_diagnostic_id" "$label" "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" \
      "${BASH_LINENO[0]:-unknown}" >&2
    printf 'command:\n  %s\nexpected to contain:\n  %s\n' \
      "${test_diagnostics_last_command:-unknown}" "$expected" >&2
    test_diagnostics_print_reproduce
    test_diagnostics_print_block "actual output" "$actual"
    test_diagnostics_print_block "stderr" "${test_diagnostics_last_stderr:-}"
    return 1
  fi
}

test_diagnostics_assert_equal() {
  local label=$1
  local expected=$2
  local actual=$3
  local assertion_line=${BASH_LINENO[0]:-unknown}
  local assertion_source=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  if [[ "$expected" != "$actual" ]]; then
    test_diagnostics_reported=1
    printf '\n%s: %s mismatch\nsource: %s:%s\n' \
      "$test_diagnostic_id" "$label" "$assertion_source" "$assertion_line" >&2
    printf 'command:\n  %s\n' "${test_diagnostics_last_command:-not captured}" >&2
    test_diagnostics_print_reproduce
    test_diagnostics_print_block "expected" "$expected"
    test_diagnostics_print_block "actual" "$actual"
    test_diagnostics_print_block "stderr" "${test_diagnostics_last_stderr:-}"
    return 1
  fi
}

test_diagnostics_assert_not_exists() {
  local label=$1
  local path=$2
  if [[ -e "$path" ]]; then
    test_diagnostics_reported=1
    printf '\n%s: %s unexpected path\nsource: %s:%s\npath:\n  %s\n' \
      "$test_diagnostic_id" "$label" "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" \
      "${BASH_LINENO[0]:-unknown}" "$path" >&2
    test_diagnostics_print_reproduce
    return 1
  fi
}

test_diagnostics_fail() {
  local label=$1
  local message=$2
  test_diagnostics_reported=1
  printf '\n%s: %s\nsource: %s:%s\n%s\n' \
    "$test_diagnostic_id" "$label" "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" \
    "${BASH_LINENO[0]:-unknown}" "$message" >&2
  test_diagnostics_print_reproduce
}
