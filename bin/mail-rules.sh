# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# shellcheck shell=bash
# Shared rules for mail that leaves a session: bin/founder-mail.sh and hooks/outbound-gate.sh source this file. It only
# defines constants and functions. None of them stops reading its input early (no grep -q or head mid-pipe): under
# pipefail, the writer's SIGPIPE would turn a match into a miss.
# Subjects at or above this Jaccard index on their words of four letters or more count as one topic: the same topic
# under a new label shares half its words, and two different topics rarely do.
SIMILAR_PCT=50
# Words that mark the correction of an earlier email, matched lowercased and without accents. Edit them for your
# language.
CORRECTION='correction|corrected|correcting|replaces|replacing|supersed|errat|the previous|the earlier|my last (e-?mail|message|note)|forgot|i was wrong|my mistake'
plain() { sed 's/.*/\L&/; y/áàäâéèëêíìïîóòöôúùüûñç/aaaaeeeeiiiioooouuuunc/'; }
words() { plain | grep -oE '[a-z]{4,}' | sort -u; }
# similar SUBJECT SUBJECT: true when the two subjects reach SIMILAR_PCT.
similar() {
  local a b i u
  a=$(printf '%s\n' "$1" | words); b=$(printf '%s\n' "$2" | words)
  [ -n "$a" ] && [ -n "$b" ] || return 1
  i=$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | wc -l)
  u=$(printf '%s\n%s\n' "$a" "$b" | sort -u | wc -l)
  [ $((i * 100)) -ge $((SIMILAR_PCT * u)) ]
}
# corrects SUBJECT < BODY: true when the subject or the body's first three lines with text speak of correcting an
# earlier email.
corrects() {
  local n
  n=$({ printf '%s\n' "$1"; awk 'NF { if (k++ < 3) print }'; } | plain | grep -cE "$CORRECTION" || true)
  [ "$n" -gt 0 ]
}
