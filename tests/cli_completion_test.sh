#!/usr/bin/env bash
set -euo pipefail

cli=$1
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/caudex-cli-completion.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT

CAUDEX_DATABASE="$temporary_directory/missing/caudex.sqlite" "$cli" completion bash >"$temporary_directory/bash"
CAUDEX_DATABASE="$temporary_directory/missing/caudex.sqlite" "$cli" completion zsh >"$temporary_directory/zsh"
CAUDEX_DATABASE="$temporary_directory/missing/caudex.sqlite" "$cli" completion fish >"$temporary_directory/fish"

printf '%s\n' \
  '# bash completion for caudex' \
  '_caudex() {' \
  '    local commands="database workout set exercise history config batch completion command-reference"' \
  '    COMPREPLY=( $(compgen -W "$commands" -- "${COMP_WORDS[COMP_CWORD]}") )' \
  '}' \
  'complete -F _caudex caudex' >"$temporary_directory/expected-bash"
printf '%s\n' \
  '#compdef caudex' \
  "_arguments '1:command:(database workout set exercise history config batch completion command-reference)'" >"$temporary_directory/expected-zsh"
printf '%s\n' \
  "complete -c caudex -f -a 'database'" \
  "complete -c caudex -f -a 'workout'" \
  "complete -c caudex -f -a 'set'" \
  "complete -c caudex -f -a 'exercise'" \
  "complete -c caudex -f -a 'history'" \
  "complete -c caudex -f -a 'config'" \
  "complete -c caudex -f -a 'batch'" \
  "complete -c caudex -f -a 'completion'" \
  "complete -c caudex -f -a 'command-reference'" >"$temporary_directory/expected-fish"

diff -u "$temporary_directory/expected-bash" "$temporary_directory/bash"
diff -u "$temporary_directory/expected-zsh" "$temporary_directory/zsh"
diff -u "$temporary_directory/expected-fish" "$temporary_directory/fish"

reference=$("$cli" command-reference)
grep -Fq '# Caudex CLI command reference' <<<"$reference"
grep -Fq '## `completion`' <<<"$reference"
test ! -e "$temporary_directory/missing/caudex.sqlite"
