#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init "CLI ergonomics" "test-cli-ergonomics"

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-ergonomics.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
home="$temporary_directory/home"
case "$(uname -s)" in
  Darwin)
    expected="$home/Library/Application Support/Caudex/config"
    ;;
  Linux)
    expected="$home/.local/share/caudex/config"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    local_app_data="$temporary_directory/local-app-data"
    expected="$local_app_data/Caudex/config"
    ;;
  *)
    printf '[%s] unsupported host platform: %s\n' "$test_diagnostic_id" "$(uname -s)" >&2
    exit 2
    ;;
esac

if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  test_diagnostics_run_capture "config path" env -u XDG_DATA_HOME HOME="$home" "$cli" config path
else
  test_diagnostics_run_capture "config path" env -u XDG_DATA_HOME HOME="$home" LOCALAPPDATA="${local_app_data:-}" "$cli" config path
fi
test_diagnostics_assert_status "config path" 0 "$test_diagnostics_last_status"
path=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "config path" "$expected" "$path"
test_diagnostics_assert_not_exists "config path database side effect" "${home}/.local/share/caudex/caudex.sqlite"
test_diagnostics_assert_not_exists "config path database side effect" "$home/Library/Application Support/Caudex/caudex.sqlite"

xdg_home="$temporary_directory/xdg-data"
if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  test_diagnostics_run_capture "XDG config path" env HOME="$home" XDG_DATA_HOME="$xdg_home" "$cli" config path
  test_diagnostics_assert_status "XDG config path" 0 "$test_diagnostics_last_status"
  xdg_path=$test_diagnostics_last_stdout
  test_diagnostics_assert_equal "XDG config path" "$xdg_home/caudex/config" "$xdg_path"
  test_diagnostics_assert_not_exists "XDG config path database side effect" "$xdg_home/caudex/caudex.sqlite"
fi

if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  test_diagnostics_run_capture "set config color" env -u XDG_DATA_HOME HOME="$home" "$cli" config set color never
else
  test_diagnostics_run_capture "set config color" env -u XDG_DATA_HOME HOME="$home" LOCALAPPDATA="${local_app_data:-}" "$cli" config set color never
fi
test_diagnostics_assert_status "set config color" 0 "$test_diagnostics_last_status"

if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  test_diagnostics_run_capture "show config" env -u XDG_DATA_HOME HOME="$home" "$cli" config show
else
  test_diagnostics_run_capture "show config" env -u XDG_DATA_HOME HOME="$home" LOCALAPPDATA="${local_app_data:-}" "$cli" config show
fi
test_diagnostics_assert_status "show config" 0 "$test_diagnostics_last_status"
shown=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "config color" 'color=never' "$shown"
test_diagnostics_assert_contains "config table" 'table=compact' "$shown"

test_diagnostics_run_capture "history help" env HOME="$home" "$cli" history --help
test_diagnostics_assert_status "history help" 0 "$test_diagnostics_last_status"
help=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "history help command" 'history correct-set' "$help"
help_database="$temporary_directory/missing-parent/database.sqlite"
test_diagnostics_run_capture "history help with missing database" env HOME="$home" "$cli" --database "$help_database" history --help
test_diagnostics_assert_status "history help with missing database" 0 "$test_diagnostics_last_status"
help_with_missing_database=$test_diagnostics_last_stdout
test_diagnostics_assert_contains "history help with missing database" 'history correct-set' "$help_with_missing_database"
test_diagnostics_assert_not_exists "history help database side effect" "$help_database"

test_diagnostics_run_capture "exercise alias" "$cli" --database :memory: e list --limit 1
test_diagnostics_assert_status "exercise alias" 0 "$test_diagnostics_last_status"
alias_output=$test_diagnostics_last_stdout
test_diagnostics_assert_equal "exercise alias output" 'No exercises.' "$alias_output"
