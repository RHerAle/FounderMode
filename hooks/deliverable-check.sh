#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PostToolUse hook on Write and Edit. When the file just written matches a pattern in $FM_HOME/deliverables.txt or
# $FM_HOME/sourced.txt, it runs bin/check-text.js on it with the terms in $FM_HOME/forbidden-terms.tsv, adding
# --sources for a file in sourced.txt, and hands what it finds to the session as context. It never blocks: the text is
# already on disk, and the session that delivers it decides. A program does the check that a session used to do by
# hand before every delivery: dashes, attribution, secrets, names that must not go out, guesses and claims that name
# no source.
# Arguments: FM_HOME, which the launcher writes into this hook's entry in --settings. Without it the hook does nothing.
set -uo pipefail
[ $# = 1 ] || exit 0
home=$1
[ -f "$home/deliverables.txt" ] || [ -f "$home/sourced.txt" ] || exit 0
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$f" ] && [ -f "$f" ] || exit 0
# listed LIST: the file just written matches a pattern in $FM_HOME/LIST.
listed() {
  local p
  [ -f "$home/$1" ] || return 1
  while IFS= read -r p; do
    case $p in ''|'#'*) continue ;; esac
    p=${p//'$FM_HOME'/$home}
    # shellcheck disable=SC2053
    [[ $f == $p ]] && return 0
  done < "$home/$1"
  return 1
}
src=
listed sourced.txt && src=--sources
[ -n "$src" ] || listed deliverables.txt || exit 0
out=$(node "$(dirname "$0")/../bin/check-text.js" --terms "$home/forbidden-terms.tsv" ${src:+"$src"} "$f" 2>&1) && exit 0
msg=$(printf 'check-text.js found problems in a deliverable (%s). Fix them before it goes out:\n%s' "$f" "$(head -n 15 <<<"$out")")
if grep -qE '\[(guess|no source)\]' <<<"$out"; then
  msg+=$'\nFor a guess or a claim without a source: check it against the source and tag it, or delete it. A softer word is still a guess.'
fi
jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
