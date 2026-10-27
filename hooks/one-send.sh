#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PreToolUse hook on the one tool named by FM_SEND_TOOL. The launcher attaches it only when an isolated role starts
# with FM_ONE_SEND=<address> and FM_SEND_TEXT=<file>: a founder grants one send per launch, of one approved text to one
# address, and nothing the session reads can grant another. The launcher gives that launch its own grant id and copies
# the approved text into $FM_HOME/state, outside the role's folder, so the session can't edit it.
# Arguments: FM_HOME, the role, the granted address and the grant id, which the launcher writes into this hook's entry
# in --settings. It takes no value from the environment, which can belong to another process.
# It lets one call through and refuses everything else, including a call whose recipients it can't find. The call may
# set only the fields listed below: a draft id or a reply-all switch would send to people the call doesn't name, and
# an HTML body would send text nobody approved. Every address in to, cc and bcc counts, a line break in a header field
# could add a header such as Bcc, and the subject and the body must match the approved text exactly. The first call it
# lets through uses up the grant even if the send then fails.
# Unlike the other hooks it refuses when its arguments are missing: a gate on sending fails closed. For the same
# reason the launcher sets onFailure: "block", so the send waits when this hook can't start, fails or times out.
# Exit 2 blocks the call and shows stderr to Claude as the reason; exit 0 lets it through.
set -uo pipefail
deny() { echo "One-send guard: $1" >&2; exit 2; }
# The fields of the claude.ai Gmail send tool that this hook understands; for another connector, list its own.
fields='to|cc|bcc|subject|body'
[ $# = 4 ] || deny "this session was not started by founder-mode with a send grant."
home=$1 role=$2 grant=$4
to=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
[[ -n $to && $grant =~ ^[0-9a-f-]+$ ]] || deny "this session was started without a send grant."
state=$home/state
mark=$state/$role.one-send.$grant
approved=$mark.txt
[ -f "$approved" ] || deny "this launch carries no approved text."
input=$(cat)
other=$(jq -r --arg f "^($fields)$" '.tool_input | keys[] | select(test($f) | not)' <<<"$input" 2>/dev/null) \
  || deny "the call can't be read, so it is refused."
[ -z "$other" ] || deny "the grant covers the fields ${fields//|/, } alone. This call also sets: $(tr '\n' ' ' <<<"$other")"
jq -e '[.tool_input | to_entries[] | select(.key != "body") | .value | .. | strings
  | select(test("[\r\n]"))] | length == 0' <<<"$input" >/dev/null 2>&1 \
  || deny "a line break in to, cc, bcc or the subject is refused."
got=$(jq -r '[.tool_input | (.to, .cc, .bcc) | .. | strings | ascii_downcase
  | scan("[^\\s<>,;:\"()\\[\\]]+@[^\\s<>,;:\"()\\[\\]]+")] | unique | .[]' <<<"$input" 2>/dev/null)
[ -n "$got" ] || deny "no recipient address found, so the call is refused."
[ "$got" = "$to" ] || deny "the grant covers $to alone, with no copies. This call names: $(tr '\n' ' ' <<<"$got")"
# The approved file holds the subject on its first line and the body after it; blank lines between them don't count,
# and neither do line endings: an editor on Windows saves the file with CRLF.
[ "$(jq -r '.tool_input.subject // ""' <<<"$input")" = "$(head -n 1 "$approved" | sed $'s/\r$//')" ] \
  && [ "$(jq -r '.tool_input.body // ""' <<<"$input" | sed $'s/\r$//')" = "$(tail -n +2 "$approved" | sed -e $'s/\r$//' -e '/./,$!d')" ] \
  || deny "the subject or the body differs from the text a founder approved at launch."
# noclobber turns the redirection into create-only, so two calls can't both take the grant.
( set -o noclobber; date > "$mark" ) 2>/dev/null \
  || deny "this launch's grant was used ($(cat "$mark" 2>/dev/null)). Another send needs a founder to relaunch with a new grant."
exit 0
