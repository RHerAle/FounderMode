#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# founder-mode delegations [<id> <status> [note]]
# Without an id, lists the subagent calls in state/delegations.tsv that carry no mark yet: the caller's own when
# FM_ROLE is set, every role's otherwise. With an id and a status, appends a mark to state/delegation-marks.tsv. Both
# files only grow, and the last mark of an id counts. The launcher passes FM_HOME as the first argument.
set -euo pipefail
st=$1/state; shift
log=$st/delegations.tsv marks=$st/delegation-marks.tsv
statuses='ok|invented|redone|escalated|refused|incomplete'
mkdir -p "$st"; touch "$log" "$marks"
if [ $# = 0 ]; then
  awk -F'\t' -v r="${FM_ROLE:-}" 'FILENAME == ARGV[1] { m[$3]; next } !($4 in m) && (r == "" || $2 == r)' "$marks" "$log"
  exit 0
fi
[ $# -ge 2 ] || { echo "usage: founder-mode delegations [<id> <${statuses//|/,}> ['path:line or note']]" >&2; exit 2; }
[[ $2 =~ ^($statuses)$ ]] || { echo "founder-mode: unknown status $2; use one of ${statuses//|/, }" >&2; exit 2; }
awk -F'\t' -v id="$1" '$4 == id { f = 1 } END { exit !f }' "$log" || { echo "founder-mode: no delegation $1 in $log" >&2; exit 1; }
printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %H:%M')" "${FM_ROLE:--}" "$1" "$2" "$(printf '%s' "${3:-}" | tr '\t\n' '  ')" >> "$marks"
echo "marked $1 as $2"
