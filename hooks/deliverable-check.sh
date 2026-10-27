#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PostToolUse hook on Write and Edit. When the file just written matches a pattern in $FM_HOME/deliverables.txt, it
# runs bin/check-text.js on it with the terms in $FM_HOME/forbidden-terms.tsv and hands what it finds to the session
# as context. It never blocks: the text is already on disk, and the session that delivers it decides. A program does
# the check that a session used to do by hand before every delivery: dashes, attribution, secrets and names that must
# not go out.
# Arguments: FM_HOME, which the launcher writes into this hook's entry in --settings. Without it the hook does nothing.
set -uo pipefail
[ $# = 1 ] || exit 0
list=$1/deliverables.txt
[ -f "$list" ] || exit 0
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$f" ] && [ -f "$f" ] || exit 0
while IFS= read -r p; do
  case $p in ''|'#'*) continue ;; esac
  p=${p//'$FM_HOME'/$1}
  # shellcheck disable=SC2053
  [[ $f == $p ]] || continue
  out=$(node "$(dirname "$0")/../bin/check-text.js" --terms "$1/forbidden-terms.tsv" "$f" 2>&1) && exit 0
  msg=$(printf 'check-text.js found problems in a deliverable (%s). Fix them before it goes out:\n%s' "$f" "$(head -n 15 <<<"$out")")
  jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
  exit 0
done < "$list"
exit 0
