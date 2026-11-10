#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PreToolUse and PostToolUse hook on the send tool, for the mail channel to the other founder. The launcher attaches it
# only when the mail role starts with FM_FOUNDER_MAIL=<address>. Any session may then write to the other founder
# without asking, through founder-mode mail, which leaves the text in $FM_HOME/state/founder-mail/pending, out of the
# mail role's reach. The gate lets a call through only when its subject and body are those of a waiting text, so an
# email the mail role reads can't put its own words in front of a founder.
# One topic, one email. A waiting text carries its topic in <name>.topic. A topic already in sent.tsv goes out again
# only after a founder adds a line with it to state/founder-mail.unlock from their own terminal, and the post hook
# uses that line up. A text waits WAIT_MIN after founder-mode mail last wrote it, so a correction joins the same
# email, unless a founder orders it out now with a line holding its file name in state/founder-mail.now, which the
# post hook also uses up. At most MAX_PER_DAY go out a day.
# Arguments: pre or post, FM_HOME, the address and the mail role's kit/to-founder folder, all written by the launcher
# into this hook's entries in --settings. Like the one-send hook it refuses every call when they are missing, and the
# launcher sets onFailure: "block" on the pre entry.
# Exit 2 blocks the call and shows stderr to Claude as the reason; exit 0 lets it through.
set -uo pipefail
WAIT_MIN=60     # a founder's rule: at least an hour between writing an email and sending it, to reread it and fold in a correction
MAX_PER_DAY=5   # a loop or a hostile email can't fill the other founder's inbox
fields='to|cc|bcc|subject|body'
deny() { echo "Founder-mail gate: $1" >&2; exit 2; }
[ $# = 4 ] || deny "this session was not started by founder-mode with FM_FOUNDER_MAIL."
mode=$1 home=$2 kit=$4
to=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
[[ $mode =~ ^(pre|post)$ && -n $to ]] || deny "this session was started with bad gate arguments."
box=$home/state/founder-mail unlock=$home/state/founder-mail.unlock now=$home/state/founder-mail.now
spend() { [ -f "$2" ] && awk -v t="$1" '!h && $0 == t { h = 1; next } 1' "$2" > "$2.tmp" && mv "$2.tmp" "$2"; }
input=$(cat)
norm() { sed $'s/\r$//' | tr -s ' \t\n' ' ' | sed 's/^ //; s/ $//'; }
# The waiting text whose subject (line 1) and body (from line 3) are the call's, whitespace aside.
waiting() {
  local s b f
  s=$(jq -r '.tool_input.subject // ""' <<<"$input")
  b=$(jq -r '.tool_input.body // ""' <<<"$input" | norm)
  for f in "$box"/pending/*.md; do
    [ -f "$f" ] && [ "$(head -n 1 "$f")" = "$s" ] && [ "$(tail -n +3 "$f" | norm)" = "$b" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

if [ "$mode" = post ]; then
  f=$(waiting) || exit 0
  n=$(basename "$f") topic=$(cat "${f%.md}.topic" 2>/dev/null || true)
  a=$box/sent/$(date +%F_%H%M%S)_$n
  mkdir -p "$box/sent"
  mv "$f" "$a"
  [ ! -f "${f%.md}.topic" ] || mv "${f%.md}.topic" "${a%.md}.topic"
  rm -f "$kit/$n"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$n" "$(head -n 1 "$a")" "$topic" >> "$box/sent.tsv"
  # Each unlock line and each order to send now covers one send.
  [ -z "$topic" ] || spend "$topic" "$unlock"
  spend "$n" "$now"
  exit 0
fi

other=$(jq -r --arg f "^($fields)$" '.tool_input | keys[] | select(test($f) | not)' <<<"$input" 2>/dev/null) \
  || deny "the call can't be read, so it is refused."
[ -z "$other" ] || deny "this channel covers the fields ${fields//|/, } alone. This call also sets: $(tr '\n' ' ' <<<"$other")"
jq -e '[.tool_input | to_entries[] | select(.key != "body") | .value | .. | strings
  | select(test("[\r\n]"))] | length == 0' <<<"$input" >/dev/null 2>&1 \
  || deny "a line break in to, cc, bcc or the subject is refused."
got=$(jq -r '[.tool_input | (.to, .cc, .bcc) | .. | strings | ascii_downcase
  | scan("[^\\s<>,;:\"()\\[\\]]+@[^\\s<>,;:\"()\\[\\]]+")] | unique | .[]' <<<"$input" 2>/dev/null)
[ "$got" = "$to" ] || deny "this channel writes to $to alone, with no copies. This call names: $(tr '\n' ' ' <<<"$got")"
today=$(grep -c "^$(date +%F) " "$box/sent.tsv" 2>/dev/null || true)
[ "${today:-0}" -lt "$MAX_PER_DAY" ] || deny "$today emails went to the other founder today (cap $MAX_PER_DAY). More need a founder's OK."
f=$(waiting) || deny "the subject or the body matches no text that founder-mode mail left. Send the file in kit/to-founder unchanged."
tf=${f%.md}.topic
[ -f "$tf" ] || deny "the waiting $(basename "$f") has no topic. Whoever wrote it runs founder-mode mail <file> <topic> again."
topic=$(cat "$tf")
[[ $topic =~ ^[a-z0-9][a-z0-9-]{2,39}$ ]] || deny "the topic in $(basename "$tf") is not valid."
if [ -f "$box/sent.tsv" ] && awk -F'\t' -v t="$topic" '$4 == t { e = 1 } END { exit !e }' "$box/sent.tsv" \
  && ! { [ -f "$unlock" ] && grep -qxF -- "$topic" "$unlock"; }; then
  deny "the topic $topic already went to the other founder. One topic, one email, corrections included. Only a founder unlocks it, from their own terminal."
fi
{ [ -f "$now" ] && grep -qxF -- "$(basename "$f")" "$now"; } && exit 0
age=$(( $(date +%s) - $(stat -c %Y "$tf") ))
[ "$age" -ge $((WAIT_MIN * 60)) ] \
  || deny "this text waits $WAIT_MIN minutes after it was written, in case a correction follows; $(( (WAIT_MIN * 60 - age + 59) / 60 )) to go. Send it after that, or a founder orders it out now from their own terminal."
exit 0
