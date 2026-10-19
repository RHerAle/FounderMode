#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# PreToolUse hook for Bash and Monitor, which both run shell commands. Stops the git, gh and docker commands on its
# list that publish under a founder's name or can't be undone, and tells the session to ask a founder first. It
# catches accidents: a session set on getting past it can hide a command from any pattern, so the hard stop for a
# merge belongs on the server, in branch protection. It reads heredoc text too, so a session writes a file of example
# commands with the Write or Edit tool, not with cat <<EOF.
# Its one argument is the role's kind, which the launcher writes into this hook's entry in --settings; without it the
# hook does nothing. It takes no value from the environment, which can belong to another process. A founder lifts it
# by launching with FM_UNLOCK=1, and then the launcher leaves the hook out of the settings.
# Exit 2 blocks the call and shows stderr to Claude as the reason; exit 0 lets it through. The launcher sets
# onFailure: "block", so a guard that can't start, fails or times out blocks the call too.
set -uo pipefail
kind=${1:-}
[ -n "$kind" ] || exit 0
input=$(cat)
raw=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$raw" ] || exit 0

# Two readings of the command; the guard blocks what either one catches. In the first, quotes and backslashes go, as
# the shell drops them: bash -c "git push origin main" is a push to main. In the second, a space inside quotes or after
# a backslash becomes _, so a quoted path stays one word: git -C "/tmp/my repo" push --force.
one=${raw//$'\\\n'/ }
# The shell reads $'main' as main and ${IFS} as a space.
one=${one//\$\'/\'} one=${one//'${IFS}'/ } one=${one//'$IFS'/ }
one=$(printf '%s' "$one" | tr -d "\"'\\\\")
# A GraphQL query that starts on the line after query= belongs to that line.
one=${one//query=$'\n'/query=}
# foreach emits one character per step: a reduce that appends to an array copies it on every character, and a 100 KB
# heredoc then held each call for 25 seconds.
two=$(jq -r '.tool_input.command // empty | [foreach explode[] as $c ({q: null, e: false, o: null}; .o = null
    | if .e then .e = false | .o = (if $c == 10 then 32 elif $c == 32 or $c == 9 then 95 else $c end)
    elif $c == 92 and .q != 39 then .e = true
    elif .q == null and ($c == 34 or $c == 39) then .q = $c
    elif .q != null and $c == .q then .q = null
    elif .q != null and ($c == 32 or $c == 9 or $c == 10) then .o = 95
    else .o = $c end; .o // empty)] | implode' <<<"$input" 2>/dev/null)
# One command per line, since grep compares one line at a time: ; & | ( ) < > and backticks end a command or a word,
# so (cd wt && git push), git push origin main;ls and git push -f>/dev/null read as plain commands.
split() { printf '%s' "$1" | tr ';&|()`<>' '\n\n\n\n\n\n\n\n'; }
# Each command substitution, $(...) or backticks, becomes the word X, innermost first, so the words after it stay with
# their command: git push origin "$(git branch --show-current)" -f. The readings without it see the command inside.
# One gsub pass per nesting level, over the whole command as one record: replacing one substitution at a time costs
# a pass per substitution, minutes for a long script.
flat() {
  printf '%s' "$1" | awk 'BEGIN { RS = "\001" } { while (gsub(/\$\([^()]*\)/, "X") > 0) {} gsub(/`[^`]*`/, "X"); printf "%s", $0 }'
}

match() { printf '%s' "$1" | grep -Eiq -- "$2"; }
hit() { match "$cmd" "$1"; }
# Anywhere in the line, not only at its start: a wrapper in front of gh once carried a write past an anchored pattern.
b='(^|[^[:alnum:]_.-])'
# Options between a command and its subcommand, each with or without a value: git -C ../wt push, docker compose -p x down.
o='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

# gh: reads, gh pr create and local clones pass, and any other subcommand of a gh command group waits for a founder,
# so a write that gh adds later is blocked too. A group may carry gh's aliases (cs, ext, agent) or a plural
# (extensions, skills, agents). gh copilot runs an agent with the founder's GitHub session, so it always waits. A word
# after gh that names no gh command (prose in a commit message) passes.
# Known gap: a gh extension, an alias you define, or a command group newer than this list passes; add it here.
groups='pr|issue|repo|release|gist|run|workflow|cache|secret|variable|label|project|codespace|cs|org|ruleset|rs|attestation|at|auth|extension|ext|alias|config|ssh-key|gpg-key|agent-task|agent|discussion|skill|license|preview'
reads='view|list|ls|status|diff|checks?|watch|download|verify|get|search|browse|[a-z-]+-list'
gh_write() {
  local grp verb tok
  while IFS='|' read -r grp verb tok; do
    [ "$grp" = copilot ] && { why='gh copilot (it runs an agent with your GitHub session)'; return 0; }
    # A variable, a substitution (X in the flat readings) or a brace expansion in place of the group or the verb
    # hides which command runs: gh pr $ACTION 1, gh pr $(echo merge) 1, gh pr {merge,} 1.
    if [ "$grp" = X ] || { [ "$verb" = X ] && [[ $grp =~ ^($groups)s?$ ]]; }; then
      why='gh with a variable, a substitution or a brace expansion in place of its command'; return 0
    fi
    [[ -n $verb && $grp =~ ^($groups)s?$ ]] || continue
    # gh auth status prints the token with -t, which is why gh auth token waits too.
    if [[ $verb =~ ^($reads)$ ]] && ! [[ "$grp $verb" == 'auth status' && $tok == 1 ]]; then
      continue
    fi
    # Sessions open PRs, and these three write only to the local clone.
    [[ "$grp $verb" =~ ^(pr\ create|pr\ checkout|repo\ clone|gist\ clone)$ ]] && continue
    why="gh $grp $verb (only gh reads, gh pr create and local clones pass)"
    return 0
  # One pass over every gh call: sed drops the repository option with its value, and awk takes the group and the
  # verb, the first two words after gh that aren't options. It cuts each word at the first character a gh command
  # name can't hold, so a value an option leaves behind fails the read check above, and it turns a variable, a
  # substitution or a brace expansion into X. sort -u keeps one copy of each call, so the loop judges each distinct
  # call once; a process per line used to cost seconds on a heredoc.
  done < <(printf '%s' "$cmd" | grep -Eo "${b}gh([[:space:]].*)?" \
    | sed -E 's/^[^g]*//; s/[[:space:]]+(-R|--repo)([[:space:]]+|=)[^[:space:]]+//g' \
    | awk '{ g = v = ""; for (i = 2; i <= NF; i++) { x = $i; if (x ~ /^-/) continue
        if (x ~ /^[${]/) x = "X"; if (x != "X") sub(/[^a-z-].*/, "", x)
        if (g == "") g = x; else { v = x; break } }
      print g "|" v "|" ($0 ~ /[[:space:]](-t|--show-token)([[:space:]=]|$)/) }' | sort -u)
  return 1
}

# gh api writes when it gets a method or a field; pflag also takes a value glued to the flag (-fbody=hi). With -X GET,
# gh sends the fields as query parameters, so they read. A GraphQL query sends its text as a field too, so a query
# written inline (query={...} or query=query...) with no mutation passes as a read. Each gh api call is judged on its
# own line: a read next to a write doesn't clear the write. A query read from a file or a variable can't be checked and
# waits, and so does a GET with --input, which sends a body.
api_write() {
  # One awk pass over the lowercased gh api calls, which prints the first one that writes. A grep per check and line
  # took longer than the guard's timeout on a few thousand gh api lines.
  [ -n "$(printf '%s\n' "$cmd" | grep -Ei -- "${b}gh[[:space:]]+api([[:space:]]|$)" | awk -v b="$b" '
    { l = tolower($0) }
    l ~ /(-x|--method)[[:space:]=]*(post|put|patch|delete)/ { print; exit }
    l !~ /[[:space:]](-f|--field|--raw-field|--input)([[:space:]=]|$)|[[:space:]]-f[^[:space:]]/ { next }
    l ~ /(-x|--method)[[:space:]=]*get([[:space:]]|$)/ && l !~ /--input|mutation/ { next }
    l ~ (b "gh[[:space:]]+api[[:space:]]+graphql([[:space:]]|$)") && l !~ /mutation|=@|--input/ \
      && l ~ /([[:space:]]-f[[:space:]]*|[[:space:]]--(raw-)?field[[:space:]=]+)query=[[:space:]_]*(query|[{])/ { next }
    { print; exit }')" ]
}

check() {
  why=''
  if gh_write; then :
  elif api_write; then
    why='gh api with a write'
  # git groups short options, so -fu forces and -ud deletes, and it accepts any unambiguous abbreviation of a long
  # option: --del is --delete, --mirr is --mirror, --force-w is --force-with-lease.
  elif hit "${b}git${o}[[:space:]]+push([[:space:]].*)?[[:space:]](--force(-[wi][a-z-]*)?|--m[a-z]*|--de[a-z]*|--pru[a-z]*|-[[:alnum:]]*[fd][[:alnum:]]*|\+[^[:space:]]+|:[^[:space:]]+)([[:space:]=]|$)"; then
    why='a git push that rewrites or deletes remote history'
  elif hit "${b}git${o}[[:space:]]+push([[:space:]].*)?[[:space:]](--al[a-z]*|--b[a-z]*|[^[:space:]]*\*[^[:space:]]*)([[:space:]]|$)"; then
    why='a git push of every branch (--all, --branches or a glob)'
  # A pushed tag publishes a version, and many release and deploy workflows run on one.
  # Known gap: a tag pushed by its bare name (git push origin v1.2) looks like a branch to the guard.
  elif hit "${b}git${o}[[:space:]]+push([[:space:]].*)?[[:space:]](--ta[a-z]*|--fol[a-z-]*|[^[:space:]]*refs/tags/[^[:space:]]*|tag[[:space:]]+[^-[:space:]][^[:space:]]*)([[:space:]=]|$)"; then
    why='a git push of tags (--tags, --follow-tags, refs/tags/ or tag <name>), which can start a release'
  # Known gap: a push that doesn't name main (bare, HEAD) isn't caught from a checkout of main; branch protection is.
  elif hit "${b}git${o}[[:space:]]+push([[:space:]].*)?[[:space:]]([^[:space:]]*:)?(refs/heads/)?(main|master)([[:space:]]|$)"; then
    why='a git push to main or master'
  elif hit "${b}git${o}[[:space:]]+worktree[[:space:]]+remove([[:space:]].*)?[[:space:]](--force|-f+)([[:space:]]|$)"; then
    why='git worktree remove --force'
  elif [ "$kind" != coordinator ] && hit "${b}git${o}[[:space:]]+worktree[[:space:]]+remove([[:space:]]|$)"; then
    why='git worktree remove (the coordinator removes worktrees)'
  elif hit "${b}docker(-compose|${o}[[:space:]]+compose)${o}[[:space:]]+(down|rm)([[:space:]].*)?[[:space:]](-[[:alnum:]]*v[[:alnum:]]*|--volumes)([[:space:]=]|$)" \
    || hit "${b}docker${o}[[:space:]]+(container[[:space:]]+)?(rm|remove)([[:space:]].*)?[[:space:]](-[[:alnum:]]*v[[:alnum:]]*|--volumes)([[:space:]=]|$)" \
    || hit "${b}docker${o}[[:space:]]+(volume[[:space:]]+(rm|remove|prune)|system[[:space:]]+prune([[:space:]].*)?[[:space:]]--volumes)([[:space:]]|$)"; then
    why='docker removing volumes'
  fi
  [ -n "$why" ]
}

readings=("$one" "$two")
# Only a substitution makes the flat readings differ from the other two.
[[ $raw == *'$('* || $raw == *'`'* ]] && readings+=("$(flat "$one")" "$(flat "$two")")
for r in "${readings[@]}"; do
  cmd=$(split "$r")
  check && break
done
[ -n "$why" ] || exit 0
echo "Blocked by the founder-mode guard: $why goes out under a founder's name or can't be undone. Ask a founder; with their OK, they relaunch this session with FM_UNLOCK=1." >&2
exit 2
