#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test_diagnostics.sh"
test_diagnostics_init cli-ergonomics

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
  path=$(HOME="$home" env -u XDG_DATA_HOME "$cli" config path)
else
  path=$(HOME="$home" LOCALAPPDATA="${local_app_data:-}" env -u XDG_DATA_HOME "$cli" config path)
fi
test_diagnostics_assert_equal "config path" "$expected" "$path"
test ! -e "${home}/.local/share/caudex/caudex.sqlite"
test ! -e "$home/Library/Application Support/Caudex/caudex.sqlite"

xdg_home="$temporary_directory/xdg-data"
if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  xdg_path=$(HOME="$home" XDG_DATA_HOME="$xdg_home" "$cli" config path)
  test_diagnostics_assert_equal "XDG config path" "$xdg_home/caudex/config" "$xdg_path"
  test ! -e "$xdg_home/caudex/caudex.sqlite"
fi

if [[ "$expected" == "$home/.local/share/caudex/config" ]]; then
  HOME="$home" env -u XDG_DATA_HOME "$cli" config set color never >/dev/null
  shown=$(HOME="$home" env -u XDG_DATA_HOME "$cli" config show)
else
  HOME="$home" LOCALAPPDATA="${local_app_data:-}" env -u XDG_DATA_HOME "$cli" config set color never >/dev/null
  shown=$(HOME="$home" LOCALAPPDATA="${local_app_data:-}" env -u XDG_DATA_HOME "$cli" config show)
fi
grep -q '^color=never$' <<<"$shown"
grep -q '^table=compact$' <<<"$shown"

help=$(HOME="$home" "$cli" history --help)
grep -q 'history correct-set' <<<"$help"
help_database="$temporary_directory/missing-parent/database.sqlite"
help_with_missing_database=$(HOME="$home" "$cli" --database "$help_database" history --help)
grep -q 'history correct-set' <<<"$help_with_missing_database"
test ! -e "$help_database"
alias_output=$("$cli" --database :memory: e list --limit 1)
test "$alias_output" = 'No exercises.'
