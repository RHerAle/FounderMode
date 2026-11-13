#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# founder-mode mail <file> <topic>: leave a message for the other founder, which the mail role sends once
# hooks/founder-mail-gate.sh lets it through. The file holds the subject on its first line, a blank second line, the
# body, and as its last line with text the name of the session that wrote it, so the founder who reads it knows a
# founder didn't. The text goes to $FM_HOME/state/founder-mail/pending, out of the mail role's reach, with its topic in
# <name>.topic, and a copy goes to the mail role's kit/to-founder. One topic, one email: a topic that already went out
# needs a founder's unlock, a correction of a sent email counts as a second email on its topic, and a subject much like
# another one under a different topic is refused. Run again with the same topic while the text waits, and the new text
# replaces it and restarts the wait. The launcher passes FM_HOME and the kit folder as the first two arguments.
set -euo pipefail
export LC_ALL=C.UTF-8
no() { echo "founder-mode mail: $*" >&2; exit 1; }
# shellcheck source=bin/mail-rules.sh
. "$(dirname "$(readlink -f "$0")")/mail-rules.sh" 2>/dev/null && declare -F corrects similar >/dev/null \
  || no "can't load bin/mail-rules.sh, so nothing was written"
WAIT_MIN=60      # the gate's wait, in hooks/founder-mail-gate.sh; repeated here for the time it prints
SIMILAR_DAYS=7   # how far back a sent subject still counts as the same topic
usage="usage: founder-mode mail <file> <topic>   (topic: 3 to 40 lowercase letters, digits and dashes, such as pricing-draft)"
home=$1 kit=$2; shift 2
f=${1:?$usage} topic=${2:?$usage}
box=$home/state/founder-mail unlock=$home/state/founder-mail.unlock
how="Only a founder unlocks it, from their own terminal: echo $topic >> $unlock (good for one send)."
n=$(basename "$f")
[[ $topic =~ ^[a-z0-9][a-z0-9-]{2,39}$ ]] || no "bad topic '$topic'. $usage"
[[ $n =~ ^[A-Za-z0-9._-]+\.md$ ]] || no "bad file name $n (letters, digits, . _ -, ending in .md)"
[ -f "$f" ] || no "no file $f"
[ -n "$(head -n 1 "$f")" ] && [ -z "$(sed -n 2p "$f")" ] || no "line 1 is the subject and line 2 stays blank"
! grep -q $'\r' "$f" || no "the file has carriage returns"
last=$(grep -v '^[[:space:]]*$' "$f" | tail -n 1)
signed=0
while IFS= read -r s; do if [ -n "$s" ] && grep -qwF -- "$s" <<<"$last"; then signed=1; fi; done \
  < <(awk -F'\t' '!/^#/ && NF >= 2 { print $2 }' "$home/roles.tsv")
[ "$signed" = 1 ] || no "the last line names the session that wrote it, as roles.tsv spells it"
subject=$(head -n 1 "$f")
unlocked() { [ -f "$unlock" ] && grep -qxF -- "$topic" "$unlock"; }

# A topic goes out once. Rows from before topics existed have three columns.
before=$(awk -F'\t' -v t="$topic" '$4 == t { print $1 " (" $2 ")"; exit }' "$box/sent.tsv" 2>/dev/null || true)
if [ -n "$before" ] && ! unlocked; then no "the topic $topic went out on $before. One topic, one email, corrections included. $how"; fi
if ! unlocked && tail -n +3 "$f" | corrects "$subject"; then
  no "the subject or the start of the body corrects an earlier email. A correction of a sent email is a second email on its topic and needs a founder's unlock for that topic. $how"
fi
# A subject much like a recent one, or a waiting one, under another topic is the same topic.
since=$(date -d "$SIMILAR_DAYS days ago" '+%F %T')
if [ -f "$box/sent.tsv" ]; then
  while IFS=$'\t' read -r date _ s t; do
    if [[ $date > $since ]] && [ "${t:-}" != "$topic" ] && similar "$subject" "$s"; then
      no "the subject is too close to \"$s\", sent on $date${t:+ under the topic $t}. If it is the same topic, it went out already: $how"
    fi
  done < "$box/sent.tsv"
fi
for p in "$box"/pending/*.topic; do
  [ -f "$p" ] || continue
  t=$(cat "$p"); [ "$t" = "$topic" ] && continue
  if similar "$subject" "$(head -n 1 "${p%.topic}.md" 2>/dev/null)"; then
    no "the subject is too close to the waiting $(basename "${p%.topic}").md, under the topic $t. If it is the same topic, run this with $t and it replaces that text."
  fi
done

# While a text waits, the same topic replaces it and the wait starts again.
mkdir -p "$box/pending" "$kit"
for p in "$box"/pending/*.topic; do
  [ -f "$p" ] && [ "$(cat "$p")" = "$topic" ] || continue
  v=$(basename "${p%.topic}").md
  rm -f "$box/pending/$v" "$p" "$kit/$v"
  echo "Replaces the waiting $v, on the same topic."
done
[ ! -e "$box/pending/$n" ] || no "a waiting text has that name under another topic"
cp "$f" "$box/pending/$n"
printf '%s\n' "$topic" > "$box/pending/${n%.md}.topic"
cp "$f" "$kit/$n"
echo "Ready. The mail role can send kit/to-founder/$n from $(date -d "+$WAIT_MIN min" +%H:%M)."
