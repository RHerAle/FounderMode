#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# UserPromptSubmit hook. A conversation keeps the prompt it started with, so an edit to ORGCHART.md or to the role
# file after that point never reaches it: tell the session once, on its next prompt. For the coordinator, also name
# the sessions stopped on an API error, so it wakes them once a usage limit resets.
# The mark is per conversation (state/loaded/<session id>), because one role resumes several conversations that
# started at different times. The launcher dates a resumed conversation it has no mark for; one that starts inside a
# running process, after /clear, carries the prompt read at launch and takes the launch time.
# Arguments: FM_HOME, the role, its kind and its role file, which the launcher writes into this hook's entry in
# --settings. Without them the hook does nothing. It takes none of them from the environment, which can belong to
# another process. Claude reads this hook's stdout as context.
set -uo pipefail
[ $# -ge 3 ] || exit 0
home=$1 role=$2 kind=$3 rolefile=${4:-}
sid=$(jq -r '.session_id // empty' 2>/dev/null)
files=("$home/ORGCHART.md")
[ -n "$rolefile" ] && files+=("$rolefile")
msg=
if [[ $sid =~ ^[0-9a-f-]+$ ]]; then
  mark=$home/state/loaded/$sid
  [ -e "$mark" ] || touch -r "$home/state/$role.launched" "$mark" 2>/dev/null || touch "$mark" 2>/dev/null
  if [ -e "$mark" ] && [ -n "$(find "${files[@]}" -newer "$mark" 2>/dev/null)" ]; then
    touch "$mark"
    msg="The org chart or your role changed after this conversation started. Read them again before you go on: ${files[*]}."
  fi
fi
if [ "$kind" = coordinator ]; then
  p=$(FM_HOME=$home FM_ROLE=$role node "$(dirname "$0")/../bin/stalled.js" --hook 2>/dev/null)
  msg="${msg:+$msg }$p"
fi
[ -z "${msg// /}" ] || echo "$msg"
exit 0
