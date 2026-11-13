#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# PreToolUse and PostToolUse hook for mail to people outside the company: the mail role's draft tool, and the one send
# a founder grants (hooks/one-send.sh calls it before it takes the grant). Writing twice about one thing to the other
# founder is bad; to a customer or a partner it can't be undone.
#   pre:  refuses when an address in the call already has a row in state/outbound.tsv within ADDRESS_DAYS, or its
#         company does (its registrable domain; addresses at a public mail provider count one by one); when the subject or the
#         start of the body corrects an earlier email; or when the subject is close to one sent to that company within
#         SIMILAR_DAYS. A founder's send grant doesn't lift any of this. Only a line with the address, or @ and the
#         exact or registrable domain, in state/outbound.unlock does, written by a founder from their own terminal, and
#         it covers one call.
#   post: logs one row per address and uses up the unlock lines the call relied on.
# Arguments: pre or post, FM_HOME and the kind of call (draft or send), written by the launcher. Without them it refuses
# every call, and the launcher sets onFailure: "block" on the pre entry.
# Exit 2 blocks the call and shows stderr to Claude as the reason; exit 0 lets it through.
set -uo pipefail
export LC_ALL=C.UTF-8
ADDRESS_DAYS=7    # one email a week to a person or a company, whatever the topic; more is pestering
SIMILAR_DAYS=30   # a subject close to one a company got within a month is the same email again
# Public mail providers: each address there is a different person, so they count by address and not by domain.
PUBLIC=' gmail.com googlemail.com outlook.com hotmail.com live.com msn.com yahoo.com ymail.com icloud.com me.com mac.com aol.com proton.me protonmail.com pm.me gmx.com gmx.net gmx.de web.de mail.com yandex.com zoho.com tutanota.com '
deny() { echo "Outbound gate: $1 Stop here and don't try another way: note it in your log and tell a founder." >&2; exit 2; }
# Without the shared rules the corrections and similar-subject checks can't run, so the gate refuses rather than pass.
# shellcheck source=bin/mail-rules.sh
. "$(dirname "$(readlink -f "$0")")/../bin/mail-rules.sh" 2>/dev/null && declare -F corrects similar >/dev/null \
  || deny "it can't load bin/mail-rules.sh, so the call is refused."
[ $# = 3 ] || deny "this session was not started by founder-mode with the outbound gate."
mode=$1 home=$2 kind=$3
[[ $mode =~ ^(pre|post)$ && $kind =~ ^(draft|send)$ ]] || deny "this session was started with bad gate arguments."
log=$home/state/outbound.tsv unlock=$home/state/outbound.unlock
how="Only a founder lifts it, from their own terminal, with a line holding the address or @domain in $unlock (good for one call)."
input=$(cat)
addrs=$(jq -r '[.tool_input | (.to, .cc, .bcc) | .. | strings | ascii_downcase
  | scan("[^\\s<>,;:\"()\\[\\]]+@[^\\s<>,;:\"()\\[\\]]+")] | unique | .[]' <<<"$input" 2>/dev/null)
subject=$(jq -r '.tool_input.subject // "" | gsub("[\t\r\n]"; " ")' <<<"$input" 2>/dev/null)
body=$(jq -r '.tool_input.body // ""' <<<"$input" 2>/dev/null)
# A company is its registrable domain: the last two labels, or the last three when the second to last is co, com, org,
# net, gov, gob, edu or ac and the last has two letters (acme.co.uk, acme.com.es). So sales.acme.example is acme.example.
# This is not the Public Suffix List: acme.uk.com counts as uk.com, and two domains of one company stay two.
REG_AWK='function reg(d,  n, l) {
  n = split(tolower(d), l, ".")
  if (n >= 3 && l[n-1] ~ /^(co|com|org|net|gov|gob|edu|ac)$/ && length(l[n]) == 2) return l[n-2] "." l[n-1] "." l[n]
  return n >= 2 ? l[n-1] "." l[n] : d
}'
company() { awk -v d="$1" "$REG_AWK"' BEGIN { print reg(d) }'; }
public() { [[ $PUBLIC == *" ${1#*@} "* ]]; }
key() { if public "$1"; then printf '%s' "$1"; else printf '@%s' "$(company "${1#*@}")"; fi; }
# The unlock line that covers an address: its own, or its company's (@ and the exact or the registrable domain) unless
# it sits at a public provider.
line() {
  [ -f "$unlock" ] || return 1
  if grep -qxF -- "$1" "$unlock"; then printf '%s' "$1"
  elif public "$1"; then return 1
  elif grep -qxF -- "@${1#*@}" "$unlock"; then printf '@%s' "${1#*@}"
  elif grep -qxF -- "@$(company "${1#*@}")" "$unlock"; then printf '@%s' "$(company "${1#*@}")"
  else return 1; fi
}
# rows KEY DAYS: date, address and subject of the logged rows for that address or company within DAYS. The log keeps
# the exact domain, so rows are matched on its registrable domain.
rows() {
  [ -f "$log" ] || return 0
  awk -F'\t' -v k="$1" -v d="$(date -d "$2 days ago" '+%F %T')" \
    "$REG_AWK"' $1 > d && (substr(k, 1, 1) == "@" ? "@" reg($3) == k : $2 == k) { print $1 "\t" $2 "\t" $4 }' "$log"
}

if [ "$mode" = post ]; then
  mkdir -p "$home/state"
  for a in $addrs; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$a" "${a#*@}" "$subject" "$kind" >> "$log"
    if l=$(line "$a"); then awk -v t="$l" '!h && $0 == t { h = 1; next } 1' "$unlock" > "$unlock.tmp" && mv "$unlock.tmp" "$unlock"; fi
  done
  exit 0
fi

[ -n "$addrs" ] || deny "no recipient address found, so the call is refused."
for a in $addrs; do
  line "$a" >/dev/null && continue
  k=$(key "$a")
  prev=$(rows "$k" "$ADDRESS_DAYS" | head -n 1)
  [ -z "$prev" ] || deny "${k#@} got mail on $(cut -f1 <<<"$prev") ($(cut -f2 <<<"$prev")). One email per address and per company every $ADDRESS_DAYS days, whatever the topic. $how"
  ! printf '%s\n' "$body" | corrects "$subject" \
    || deny "the subject or the start of the body corrects an earlier email. A correction is a second email. $how"
  while IFS=$'\t' read -r date _ s; do
    ! similar "$subject" "$s" || deny "the subject is too close to \"$s\", sent to ${k#@} on $date. $how"
  done < <(rows "$k" "$SIMILAR_DAYS")
done
exit 0
