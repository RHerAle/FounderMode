#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PreToolUse hook on Agent. A subagent without a model of its own (general-purpose, Explore, Plan, a fork, or a call
# without a type, which falls back to general-purpose) runs at the session's model and effort, so on a role at max it
# costs as much as the session. The hook refuses those calls and names the tiers, which set their own model and
# effort. A call to a tier that sets a model other than the tier's, or an effort of xhigh or max, is refused too: the
# call's model and effort win over the tier's. Any other type passes: an agent file that sets its own model is its
# author's choice.
# Arguments: the names of the tiers to suggest, which the launcher writes into this hook's entry in --settings.
# Without them the hook does nothing. A deny decision on stdout refuses the call and shows Claude the reason.
set -uo pipefail
[ $# -ge 1 ] || exit 0
in=$(cat)
t=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
case $t in
  ''|general-purpose|Explore|Plan|fork) r="A subagent of type ${t:-none} runs at this session's model and effort. Use a tier, which sets its own: $*." ;;
  *) [[ " $* " == *" $t "* ]] || exit 0
     # The tier's own model, from its file next to hooks/: a call that repeats it changes nothing and passes.
     own=$(sed -n 's/^model: *//p' "${0%/*}/../agents/$t.md" 2>/dev/null | head -n 1)
     over=$(jq -r --arg own "$own" '.tool_input | ((.model // "") as $m | $m != "" and $m != $own)
       or ((.effort // "") as $e | $e == "xhigh" or $e == "max")' <<<"$in" 2>/dev/null)
     [ "$over" = true ] || exit 0
     r="The tier $t sets its own model and effort. Drop the model or lower the effort, or use the next tier." ;;
esac
jq -cn --arg r "$r" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
