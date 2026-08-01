#!/usr/bin/env bash
set -euo pipefail

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-ergonomics.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
home="$temporary_directory/home"
expected="$home/Library/Application Support/Caudex/config"

path=$(HOME="$home" "$cli" config path)
test "$path" = "$expected"
HOME="$home" "$cli" config set color never >/dev/null
shown=$(HOME="$home" "$cli" config show)
grep -q '^color=never$' <<<"$shown"
grep -q '^table=compact$' <<<"$shown"

help=$("$cli" history --help)
grep -q 'history correct-set' <<<"$help"
alias_output=$("$cli" --database :memory: e list --limit 1)
test "$alias_output" = 'No exercises.'
