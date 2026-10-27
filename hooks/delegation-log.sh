#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PostToolUse hook on Agent. It logs each call to a tier in $FM_HOME/state/delegations.tsv (time, role, tier, a short
# id, the call's description) and tells the session the id. Once the session has checked what came back, it marks the
# entry with founder-mode delegations <id> <status>. An entry without a mark stays pending, so a count of invented or
# redone results doesn't depend on a session remembering to log them.
# Arguments: FM_HOME, the role and the tier names to log, which the launcher writes into this hook's entry in
# --settings. Without them the hook does nothing. It never blocks. Claude reads its additionalContext as context.
set -uo pipefail
[ $# -ge 3 ] || exit 0
home=$1 role=$2; shift 2
[[ $role =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
in=$(cat)
tier=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
logged=0
for x in "$@"; do [ "$x" = "$tier" ] && logged=1; done
[ "$logged" = 1 ] || exit 0
id=$(jq -r '.tool_use_id // ""' <<<"$in" | tr -cd 'A-Za-z0-9_-')
id=${id: -8}
[ -n "$id" ] || id=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
desc=$(jq -j '.tool_input.description // ""' <<<"$in" | tr '\t\n' '  ' | cut -c1-120)
printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$role" "$tier" "$id" "$desc" >> "$home/state/delegations.tsv" 2>/dev/null || exit 0
fm=$(cd "$(dirname "$0")/.." && pwd)/bin/founder-mode
c="Logged this $tier call as $id. Once you have checked what it returned, mark it: $fm delegations $id <ok|invented|redone|escalated|refused|incomplete> 'path:line or note'. Unmarked, it stays pending."
jq -cn --arg c "$c" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
