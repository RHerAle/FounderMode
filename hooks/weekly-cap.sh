#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PreToolUse hook on every tool, and UserPromptSubmit. Once the account's week reaches the cap in $FM_HOME/weekly-cap,
# it refuses every tool call, a subagent's included, and every new prompt, until the weekly reset. The coordinator's
# prompts still go through with a note, so a founder can still talk to it, and it answers without tools. With the cap
# reached no session can run a tool, so none can raise the cap: a founder does that from a terminal.
# The reading comes from $FM_HOME/state/usage.json, in epoch seconds:
#   {"seven_day": {"utilization": 81, "resets_at": 1767225600}, "read_at": 1767196800}
# Founder Mode ships no program that writes it (README, Hooks). Without a number in the cap file, a reading under two
# hours old and a reset still ahead, the hook does nothing. With a cap but no such reading the cap is not enforced, so
# the coordinator's prompt gets a note that says so, at most once every 30 minutes (the modification time of
# $FM_HOME/state/weekly-cap.warned). Nothing changes for a tool call or for any other role.
# Arguments: FM_HOME and the role's kind, which the launcher writes into this hook's entry in --settings. Without them
# the hook does nothing.
set -uo pipefail
[ $# = 2 ] || exit 0
home=$1 kind=$2
cap=$(cat "$home/weekly-cap" 2>/dev/null)
[[ $cap =~ ^[0-9]+$ ]] || exit 0
ev=$(jq -r '.hook_event_name // empty' 2>/dev/null)
now=$(date +%s)
hit=$(jq -r --argjson now "$now" --argjson cap "$cap" '.read_at as $at | .seven_day // {} | select(
    ([.utilization, .resets_at, $at] | map(type == "number") | all)
    and $now - $at < 7200 and .resets_at > $now and .utilization >= $cap)
  | "\(.utilization)|\(.resets_at | strftime("%Y-%m-%d %H:%M UTC"))"' "$home/state/usage.json" 2>/dev/null)
if [ -z "$hit" ]; then
  [ "$ev" = UserPromptSubmit ] && [ "$kind" = coordinator ] || exit 0
  seen=$(jq -r --argjson now "$now" '.read_at as $at | (.seven_day // {}) as $w
    | if ([$w.utilization, $w.resets_at, $at] | map(type == "number") | all) and $now - $at < 7200 and $w.resets_at > $now then "fresh"
      else ($at | numbers | strftime("%Y-%m-%d %H:%M UTC")) // "none" end' "$home/state/usage.json" 2>/dev/null)
  [ "$seen" != fresh ] || exit 0
  warned=$home/state/weekly-cap.warned
  [ -z "$(find "$warned" -mmin -30 2>/dev/null)" ] || exit 0
  mkdir -p "$home/state" && touch "$warned"
  case $seen in ''|none) seen="no reading" ;; *) seen="last reading: $seen" ;; esac
  r="The weekly cap is set to $cap%, but it is not being applied: $home/state/usage.json has no reading under 2 hours old with a reset still ahead ($seen). No session will stop at the cap until one is written there."
  jq -cn --arg r "$r" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $r}}'
  exit 0
fi
IFS='|' read -r pct reset <<<"$hit"
r="The account's week is at $pct%, and the weekly cap is $cap%. Stop here and use no more tools. Work resumes at the weekly reset ($reset). Only a founder can raise the cap, from a terminal: echo <new cap> > $home/weekly-cap"
if [ "$ev" = UserPromptSubmit ] && [ "$kind" = coordinator ]; then
  jq -cn --arg r "You may answer the founder, without tools. $r" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $r}}'
elif [ "$ev" = UserPromptSubmit ]; then
  jq -cn --arg r "$r" '{decision: "block", reason: $r}'
else
  jq -cn --arg r "$r" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
fi
exit 0
