#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# Smoke test. Runs the launcher dry against a throwaway HOME, launches it against a stand-in claude, feeds the hooks
# and the stalled-session report sample input, and runs the README's quick start in a clean home. It never starts the
# real claude. Needs bash, jq and node, and runs shellcheck when it is installed and the pilot's cases when python3 is.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FM=$ROOT/bin/founder-mode
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME=$T/user FM_HOME=$T/user/.founder-mode
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_AGENT_VIEW CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_AUTO_COMPACT_WINDOW \
  CLAUDE_CODE_SAFE_MODE CLAUDE_CODE_SIMPLE \
  FM_COMPACT FM_UNLOCK FM_ONE_SEND FM_SEND_TOOL FM_SEND_TEXT FM_ROLE FM_KIND FM_ROLE_FILE FM_GRANT FM_DRY_RUN \
  FM_FOUNDER_MAIL FM_DRAFT_TOOL
P=$HOME/.claude/projects/some-folder
mkdir -p "$HOME/.claude/sessions" "$P" "$HOME/company/product" "$HOME/company/admin" "$HOME/outreach"

fails=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
# expect NAME CMD...: CMD succeeds.
expect() { local n=$1; shift; if "$@" >/dev/null 2>&1; then pass "$n"; else fail "$n"; fi; }
# refuse NAME TEXT CMD...: CMD fails and says TEXT on stderr.
refuse() {
  local n=$1 text=$2 err; shift 2
  if err=$("$@" 2>&1 >/dev/null); then fail "$n (it ran)"
  elif grep -qF -- "$text" <<<"$err"; then pass "$n"
  else fail "$n: $err"; fi
}
# exit2 CMD...: CMD exits with 2, the code that blocks a tool call.
exit2() { "$@"; [ $? = 2 ]; }
exit1() { "$@" >/dev/null; [ $? = 1 ]; }
exit2x() { "$@" >/dev/null; [ $? = 2 ]; }
lacks() { ! grep -qF -- "$1" <<<"$2"; }
# dump ROLE ARGS...: the launcher's dry-run line, run with claude swapped for a dump of its arguments, NUL-separated.
dump() {
  local line
  line=$(FM_DRY_RUN=1 "$FM" "$@") || return 1
  ( claude() { printf '%s\0' "$@"; }; eval "$line" )
}
# arg FLAG < dump: the value that follows FLAG.
arg() { local a prev=; while IFS= read -r -d '' a; do if [ "$prev" = "$1" ]; then printf '%s' "$a"; return 0; fi; prev=$a; done; return 1; }
has() { local a; while IFS= read -r -d '' a; do [ "$a" = "$1" ] && return 0; done; return 1; }
dry() { env FM_DRY_RUN=1 "$FM" "$@"; }
printf '%s\n' 'Hello' '' 'A short note.' > "$T/approved.txt"
merge='{"tool_input":{"command":"gh pr merge 1"}}'
# Start time of this shell's process, as Claude Code's session registry records it (Linux only).
started() { [ -r "/proc/$1/stat" ] && sed -E 's/^.*\) //' "/proc/$1/stat" | cut -d' ' -f20; }
# as_hook SETTINGS EVENT INPUT: that event's first hook, run the way Claude Code runs exec form (its command and its
# args, no shell), under the environment of another process: another role, another kind (KIND, default coordinator),
# another FM_HOME (ENV_HOME), the guard unlocked and a send granted to someone else. A session moved to the background
# gets such an environment.
as_hook() {
  local c x argv=()
  c=$(jq -r --arg e "$2" '.hooks[$e][0].hooks[0].command' <<<"$1")
  while IFS= read -r x; do argv+=("$x"); done < <(jq -r --arg e "$2" '.hooks[$e][0].hooks[0].args[]' <<<"$1")
  env -i PATH="$PATH" HOME="$HOME" FM_HOME="${ENV_HOME:-$T/elsewhere}" FM_ROLE=other FM_KIND="${KIND:-coordinator}" \
    FM_ROLE_FILE="$T/other.md" FM_UNLOCK=1 FM_ONE_SEND=eve@evil FM_FOUNDER_MAIL=eve@evil FM_GRANT=0000 "$c" ${argv[@]+"${argv[@]}"} <<<"$3"
}

echo "# syntax"
for f in "$FM" "$ROOT"/bin/*.sh "$ROOT"/hooks/*.sh "$ROOT/tests/smoke.sh"; do expect "bash -n ${f#"$ROOT"/}" bash -n "$f"; done
for f in "$ROOT"/bin/*.js; do expect "node --check ${f#"$ROOT"/}" node --check "$f"; done
if command -v shellcheck >/dev/null; then
  expect "shellcheck (warnings and errors)" shellcheck -S warning "$FM" "$ROOT"/bin/*.sh "$ROOT"/hooks/*.sh "$ROOT/tests/smoke.sh"
else
  echo "skip  shellcheck (not installed)"
fi

echo "# init"
expect "init runs" "$FM" init
for f in ORGCHART.md BOARD.md PR.md roles.tsv roles/advisor.md roles/design.md settings/outreach.json \
  board/precedents.md deliverables.txt forbidden-terms.tsv sourced.txt; do
  expect "init wrote $f" test -f "$FM_HOME/$f"
done
echo "# edited" >> "$FM_HOME/ORGCHART.md"
"$FM" init >/dev/null
expect "a second init keeps an edited file" grep -qx '# edited' "$FM_HOME/ORGCHART.md"

echo "# a member role"
expect "the design role carries its role file" grep -qx '# Your role: Design' <<<"$(dump design | arg --append-system-prompt)"
expect "and gets the member hooks" jq -e '.hooks.PreToolUse[0].hooks[0].args == ["member"]' <<<"$(dump design | arg --settings)"
d=$(dump engineering | arg --append-system-prompt)
expect "prompt opens with the org chart" grep -qx '# Org chart' <<<"$d"
expect "prompt carries the role file" grep -qx '# Your role: Engineering' <<<"$d"
expect "prompt has \$FM_HOME filled in" grep -qF "$FM_HOME/BOARD.md" <<<"$d"
expect "prompt keeps no literal \$FM_HOME" lacks '$FM_HOME' "$d"
s=$(dump engineering | arg --settings)
expect "settings are valid JSON" jq -e . <<<"$s"
expect "memory folder is per role" jq -e --arg m "$FM_HOME/memory/engineering" '.autoMemoryDirectory == $m' <<<"$s"
expect "the guard watches Bash and Monitor" jq -e '.hooks.PreToolUse[0].matcher == "Bash|Monitor"' <<<"$s"
expect "the guard gets the role's kind as its argument" jq -e --arg c "$ROOT/hooks/irreversible-guard.sh" \
  '.hooks.PreToolUse[0].hooks[0] | .command == $c and .args == ["member"]' <<<"$s"
expect "a guard that can't start, fails or times out blocks the call" \
  jq -e '.hooks.PreToolUse[0].hooks[0] | .onFailure == "block" and .timeout == 30' <<<"$s"
expect "the pointer hook gets FM_HOME and the role" jq -e --arg c "$ROOT/hooks/session-pointer.sh" --arg h "$FM_HOME" \
  '.hooks.SessionStart[0].hooks[0] | .command == $c and .args == [$h, "engineering"]' <<<"$s"
expect "and neither it nor the notice blocks anything" \
  jq -e '[.hooks.SessionStart[0].hooks[0], .hooks.UserPromptSubmit[0].hooks[0] | has("onFailure")] | any | not' <<<"$s"
expect "the notice hook and the weekly cap watch the prompts" jq -e --arg h "$ROOT/hooks" \
  '[.hooks.UserPromptSubmit[0].hooks[].command] == ["\($h)/orgchart-notice.sh", "\($h)/weekly-cap.sh"]' <<<"$s"
expect "the notice hook gets FM_HOME, the role, its kind and its role file" jq -e --arg c "$ROOT/hooks/orgchart-notice.sh" \
  --arg h "$FM_HOME" '.hooks.UserPromptSubmit[0].hooks[0] | .command == $c and .args == [$h, "engineering", "member", "\($h)/roles/engineering.md"]' <<<"$s"
expect "every hook runs in exec form, without a shell" jq -e '[.hooks[][].hooks[] | has("args")] | all' <<<"$s"
expect "settings/all.json merged in" jq -e '.permissions.deny | index("mcp__claude_ai_Gmail")' <<<"$s"
expect "members lose RemoteTrigger" jq -e '.permissions.deny | index("RemoteTrigger")' <<<"$s"
cleared='{"CLAUDE_CODE_EFFORT_LEVEL": "", "CLAUDE_CODE_AUTO_COMPACT_WINDOW": ""}'
expect "settings clear the variables that would override the effort and the window" \
  jq -e --argjson c "$cleared" '.env == $c' <<<"$s"
printf '%s\n' '{"env": {"CLAUDE_CODE_EFFORT_LEVEL": "low"}}' > "$FM_HOME/settings/engineering.json"
expect "and no file under settings/ puts one back" jq -e --argjson c "$cleared" '.env == $c' <<<"$(dump engineering | arg --settings)"
rm "$FM_HOME/settings/engineering.json"
for v in CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_SAFE_MODE CLAUDE_CODE_SIMPLE; do
  expect "a $v in the shell is announced" grep -qF "your shell sets $v" <<<"$(env "$v=1" FM_DRY_RUN=1 "$FM" engineering 2>&1 >/dev/null)"
done
# A role opened from inside another session must not start as that session's child.
seen=$(env CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_MESSAGING_SOCKET=/x \
  CLAUDE_CODE_USE_BEDROCK=1 bash -c 'line=$(FM_DRY_RUN=1 "$0" engineering) || exit 1
  claude() { echo "${CLAUDECODE-} ${CLAUDE_CODE_SESSION_ID-} ${CLAUDE_CODE_CHILD_SESSION-} ${CLAUDE_CODE_MESSAGING_SOCKET-}|${CLAUDE_CODE_USE_BEDROCK-}"; }
  eval "$line"' "$FM")
expect "a parent session's identity doesn't reach the role" test "$seen" = "   |1"
expect "settings switch the hooks back on, whatever disableAllHooks says elsewhere" jq -e '.disableAllHooks == false' <<<"$s"
printf '%s\n' '{"disableAllHooks": true}' > "$FM_HOME/settings/engineering.json"
expect "and no file under settings/ switches them off" jq -e '.disableAllHooks == false' <<<"$(dump engineering | arg --settings)"
rm "$FM_HOME/settings/engineering.json"
mkdir -p "$HOME/.claude"
printf '%s\n' '{"disableAllHooks": true}' > "$HOME/.claude/settings.json"
expect "disableAllHooks in the user settings is announced" grep -qF 'sets disableAllHooks' <<<"$(dry engineering 2>&1 >/dev/null)"
rm "$HOME/.claude/settings.json"
for v in CLAUDE_CODE_SAFE_MODE CLAUDE_CODE_SIMPLE; do
  expect "the session gets $v empty, since a value would switch every hook off" grep -qF " $v= " <<<"$(dry engineering)"
done
for a in intern junior senior; do
  expect "the $a runs at high effort, whatever the session's" grep -qx 'effort: high' "$ROOT/agents/$a.md"
done
for x in 'intern:model: haiku' 'intern:omitClaudeMd: true' 'junior:model: sonnet' 'junior:omitClaudeMd: true' \
  'junior:disallowedTools: Agent' 'senior:model: opus' 'senior:maxTurns: 150'; do
  expect "agents/${x%%:*}.md sets ${x#*:}" grep -qx "${x#*:}" "$ROOT/agents/${x%%:*}.md"
done
expect "the senior reads CLAUDE.md" lacks omitClaudeMd "$(cat "$ROOT/agents/senior.md")"
pre() { jq -c --arg m "$1" '[.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[] | {c: (.command | sub(".*/"; "")), a: .args}]'; }
post() { jq -c --arg m "$1" '[.hooks.PostToolUse[] | select(.matcher == $m) | .hooks[] | {c: (.command | sub(".*/"; "")), a: .args}]'; }
expect "the tier hook gets the tier names" test "$(pre Agent <<<"$s")" = '[{"c":"subagent-tier.sh","a":["intern","junior","senior"]}]'
expect "the weekly cap watches every tool, with FM_HOME and the kind" \
  test "$(pre '*' <<<"$s")" = "[{\"c\":\"weekly-cap.sh\",\"a\":[\"$FM_HOME\",\"member\"]}]"
expect "the delegation log gets FM_HOME, the role and the tiers" \
  test "$(post Agent <<<"$s")" = "[{\"c\":\"delegation-log.sh\",\"a\":[\"$FM_HOME\",\"engineering\",\"intern\",\"junior\",\"senior\"]}]"
expect "the deliverable check gets FM_HOME" test "$(post 'Write|Edit' <<<"$s")" = "[{\"c\":\"deliverable-check.sh\",\"a\":[\"$FM_HOME\"]}]"
expect "only the guard blocks when it can't run" \
  jq -e '[.hooks[][].hooks[] | select(.onFailure) | .command | sub(".*/"; "")] == ["irreversible-guard.sh"]' <<<"$s"
expect "the coordinator's guard knows its kind" jq -e '.hooks.PreToolUse[0].hooks[0].args == ["coordinator"]' <<<"$(dump coordinator | arg --settings)"
expect "default compaction window" test "$(dump engineering | arg --autocompact)" = 300000
expect "per-role compaction window" test "$(dump coordinator | arg --autocompact)" = 1000000
expect "FM_COMPACT overrides it" test "$(FM_COMPACT=500000 dump coordinator | arg --autocompact)" = 500000
expect "a first launch starts a conversation" has --session-id < <(dump engineering)
for r in engineering coordinator advisor1 outreach; do
  expect "$r runs with agent view off, so it can't move to the background" \
    grep -qF ' CLAUDE_CODE_DISABLE_AGENT_VIEW=1 claude ' <<<"$(dry "$r" 2>/dev/null)"
done
u=$(FM_UNLOCK=1 dry engineering 2>&1 >/dev/null)
expect "FM_UNLOCK=1 is announced" grep -qF 'guard is off for Engineering' <<<"$u"
s=$(FM_UNLOCK=1 dump engineering 2>/dev/null | arg --settings)
expect "FM_UNLOCK=1 leaves the guard out of the settings" jq -e '[.hooks.PreToolUse[].matcher] == ["Agent", "*"]' <<<"$s"
expect "and keeps the notice hook" jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | endswith("/orgchart-notice.sh")' <<<"$s"
expect "and isn't passed on to the session" lacks FM_UNLOCK "$(FM_UNLOCK=1 dry engineering 2>/dev/null)"

echo "# conversations"
mkdir -p "$FM_HOME/state"
idd=dddddddd-dddd-4ddd-8ddd-dddddddddddd
echo '{"type":"user","agentName":"Dev"}' > "$P/$idd.jsonl"
echo "$idd" > "$FM_HOME/state/dev.session"
expect "a role resumes its last conversation" test "$(dump dev | arg -r)" = "$idd"
expect "--new starts a fresh one" has --session-id < <(dump dev --new)
refuse "refuses another role's conversation" "belongs to Dev" dry engineering -r "$idd"
refuse "-r takes an id, not a name" "UUID" dry dev -r Dev
refuse "refuses --from-pr, which picks a conversation" "launcher's job" dry dev --from-pr 12
refuse "refuses --teleport" "launcher's job" dry dev --teleport
refuse "reads -r<id> as -r <id>" "belongs to Dev" dry engineering -r"$idd"
refuse "and -r<name> as a name" "UUID" dry engineering -rDev
refuse "refuses grouped short options" "one at a time" dry engineering -pr "$idd"
for f in "-n Other" "--name Other" --safe-mode --bare "--settings {}" --bg --desktop --cloud "--environment ccpool_x" \
  --environment=ccpool_x --tmux --tmux=classic; do
  # shellcheck disable=SC2086
  refuse "refuses $f" "founder-mode:" dry engineering $f
done
ide=eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee
reg() { printf '{"pid":%s,"sessionId":"%s","name":"%s","procStart":"%s"}' "$1" "$2" "$3" "${4:-}" > "$HOME/.claude/sessions/$1.json"; }
reg $$ "$ide" Someone
refuse "refuses a conversation open in another process" "already open" dry engineering -r "$ide"
reg $$ "$ide" Legal
refuse "refuses a second live session under one name" "already open" dry legal --new
ln -s $$ "$FM_HOME/state/finance.lock"
refuse "refuses while another launcher holds the role" "starting or open" dry finance
rm "$FM_HOME/state/finance.lock"
ln -s 999999999 "$FM_HOME/state/finance.lock"
expect "ignores a lock whose launcher died" dry finance
rm "$FM_HOME/state/finance.lock"
if me=$(started $$) && [ -n "$me" ]; then
  reg $$ "$ide" Legal "$me"
  refuse "a registry entry with the same start time counts" "already open" dry legal --new
  reg $$ "$ide" Legal "$((me + 1))"
  expect "a registry pid that now runs another program doesn't" dry legal --new
  ln -s "$$:$((me + 1))" "$FM_HOME/state/finance.lock"
  expect "nor does a lock whose pid now runs another program" dry finance
  rm "$FM_HOME/state/finance.lock"
else
  echo "skip  start-time checks (no /proc)"
fi
rm -f "$HOME/.claude/sessions/$$.json"

echo "# advisors"
ida=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
echo '{"type":"user","agentName":"Advisor1"}' > "$P/$ida.jsonl"
echo "$ida" > "$FM_HOME/state/advisor1.session"
n=$(dump advisor1 | arg --session-id)
expect "an advisor opens a fresh conversation per case" test -n "$n" -a "$n" != "$ida"
expect "advisor -r reopens the case in progress" test "$(dump advisor1 -r | arg -r)" = "$ida"
dump advisor1 > "$T/adv"
tools=$(arg --tools < "$T/adv")
for w in Edit Write NotebookEdit Agent; do expect "advisor has no $w" lacks ",$w," ",$tools,"; done
expect "advisor loses every MCP tool" test "$(arg --disallowed-tools < "$T/adv")" = 'mcp__*'
expect "the advisor's guard knows its kind" jq -e '.hooks.PreToolUse[0].hooks[0].args == ["advisor"]' <<<"$(arg --settings < "$T/adv")"
expect "the advisor gets the pointer hook" jq -e '.hooks.SessionStart[0].hooks[0].args[1] == "advisor1"' <<<"$(arg --settings < "$T/adv")"
expect "the advisor's hooks can't be switched off" jq -e '.disableAllHooks == false' <<<"$(arg --settings < "$T/adv")"
refuse "advisor takes no extra claude flags" "takes no extra" dry advisor1 --tools Edit

echo "# the isolated role"
dump outreach > "$T/out"
p=$(arg --append-system-prompt < "$T/out")
expect "isolated prompt has no org chart" lacks '# Org chart' "$p"
expect "isolated prompt carries its role" grep -qx '# Your role: Outreach (first contacts)' <<<"$p"
expect "isolated runs --restricted" has --restricted < "$T/out"
expect "isolated refuses what nobody approved" test "$(arg --permission-mode < "$T/out")" = dontAsk
tools=$(arg --tools < "$T/out")
expect "isolated has no shell" lacks Bash "$tools"
expect "isolated can't send messages" lacks SendMessage "$tools"
expect "isolated can't list sessions" lacks ListAgents "$tools"
s=$(arg --settings < "$T/out")
expect "isolated memory lives in its folder" jq -e --arg m "$(cd "$HOME/outreach" && pwd -P)/memory" '.autoMemoryDirectory == $m' <<<"$s"
expect "isolated skips settings/all.json" jq -e '.permissions.deny | index("mcp__claude_ai_Gmail") | not' <<<"$s"
expect "isolated gets settings/outreach.json" jq -e '.permissions.allow | index("WebSearch")' <<<"$s"
expect "isolated asks for no messages" jq -e '.crossSessionInbound == null' <<<"$s"
expect "isolated clears the effort and window variables too" jq -e --argjson c "$cleared" '.env == $c' <<<"$s"
expect "and its send gate can't be switched off" jq -e '.disableAllHooks == false' <<<"$s"
expect "without a send grant, isolated has the pointer hook and the outbound gate on its drafts" \
  jq -e '(.hooks | keys) == ["PostToolUse", "PreToolUse", "SessionStart"] and .hooks.SessionStart[0].hooks[0].args[1] == "outreach"' <<<"$s"
expect "the outbound gate watches the draft tool in Pre, blocking when it can't run, and in Post" \
  jq -e --arg c "$ROOT/hooks/outbound-gate.sh" --arg h "$FM_HOME" '
    (.hooks.PreToolUse[0] | .matcher == "mcp__claude_ai_Gmail__create_draft" and .hooks[0].command == $c
      and .hooks[0].args == ["pre", $h, "draft"] and .hooks[0].onFailure == "block")
    and (.hooks.PostToolUse[0] | .matcher == "mcp__claude_ai_Gmail__create_draft" and .hooks[0].args == ["post", $h, "draft"])' <<<"$s"
for r in engineering coordinator advisor1 outreach; do
  expect "$r edits nothing under \$FM_HOME/state" jq -e --arg d "Edit(/$FM_HOME/state/**)" '.permissions.deny | index($d)' \
    <<<"$(dump "$r" | arg --settings)"
done
expect "isolated writes no instruction file, in any case" jq -e '.permissions.deny as $d
  | ["[Cc][Ll][Aa][Uu][Dd][Ee].[Mm][Dd]", "[Cc][Ll][Aa][Uu][Dd][Ee].[Ll][Oo][Cc][Aa][Ll].[Mm][Dd]",
     "[Aa][Gg][Ee][Nn][Tt][Ss].[Mm][Dd]", ".[Cc][Ll][Aa][Uu][Dd][Ee]/**"]
  | all(. as $f | ($d | index("Edit(**/\($f))")) and ($d | index("Write(**/\($f))")))' <<<"$s"
refuse "isolated takes no extra claude flags" "takes no extra" dry outreach --add-dir /tmp
FM_ONE_SEND=buyer@example FM_SEND_TOOL=mcp__mail__send FM_SEND_TEXT=$T/approved.txt dump outreach > "$T/send" 2>"$T/send.err"
expect "a send grant is announced" grep -qF 'one send to buyer@example' "$T/send.err"
cp "$T/approved.txt" "$HOME/outreach/approved.txt"
refuse "the approved text lives outside the role's folder" "inside outreach" env FM_ONE_SEND=buyer@example \
  FM_SEND_TOOL=mcp__mail__send FM_SEND_TEXT="$HOME/outreach/approved.txt" FM_DRY_RUN=1 "$FM" outreach
rm "$HOME/outreach/approved.txt"
refuse "a send grant needs an approved text" "FM_SEND_TEXT" env FM_ONE_SEND=buyer@example FM_SEND_TOOL=mcp__mail__send FM_DRY_RUN=1 "$FM" outreach
expect "a send grant hooks the send tool" jq -e '.hooks.PreToolUse[0].matcher == "mcp__mail__send"' <<<"$(arg --settings < "$T/send")"
expect "and the send waits when that hook can't start, fails or times out" \
  jq -e '.hooks.PreToolUse[0].hooks[0].onFailure == "block"' <<<"$(arg --settings < "$T/send")"
expect "the send hook gets FM_HOME, the role, the address and the grant" jq -e --arg c "$ROOT/hooks/one-send.sh" --arg h "$FM_HOME" \
  '.hooks.PreToolUse[0].hooks[0] | .command == $c and (.args | length == 4 and .[0] == $h and .[1] == "outreach"
    and .[2] == "buyer@example" and (.[3] | test("^[0-9a-f-]{36}$")))' <<<"$(arg --settings < "$T/send")"
expect "and logs each granted send in the outbound log" jq -e --arg c "$ROOT/hooks/outbound-gate.sh" --arg h "$FM_HOME" \
  '.hooks.PostToolUse | map(select(.matcher == "mcp__mail__send")) | .[0].hooks[0] | .command == $c and .args == ["post", $h, "send"]' \
  <<<"$(arg --settings < "$T/send")"
expect "a send grant pre-approves that tool" grep -qF ',mcp__mail__send' <<<"$(arg --allowed-tools < "$T/send")"
refuse "a send grant needs the isolated role" "only applies" env FM_ONE_SEND=buyer@example FM_SEND_TOOL=x FM_DRY_RUN=1 "$FM" finance
refuse "a send grant needs a plain tool name" "FM_SEND_TOOL" env FM_ONE_SEND=buyer@example FM_SEND_TOOL='mcp__.*' FM_DRY_RUN=1 "$FM" outreach
grant() {
  FM_ONE_SEND=buyer@example FM_SEND_TOOL=mcp__mail__send FM_SEND_TEXT="$T/approved.txt" dump outreach 2>/dev/null \
    | arg --settings | jq -r '.hooks.PreToolUse[0].hooks[0].args[3]'
}
g1=$(grant) g2=$(grant)
expect "each launch gets its own grant" test -n "$g1" -a "$g1" != "$g2"

echo "# folder layout"
# A second home whose isolated role sits inside the coordinator's folder, then the other way round.
L=$T/layout
mkdir -p "$L/fm/roles" "$L/boss/out" "$L/solo/inner"
cp "$FM_HOME/ORGCHART.md" "$L/fm/"; cp "$FM_HOME/roles/coordinator.md" "$FM_HOME/roles/outreach.md" "$L/fm/roles/"
printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' boss Boss opus max "$L/boss" coordinator coordinator \
  out Out opus high "$L/boss/out" isolated outreach > "$L/fm/roles.tsv"
refuse "refuses an isolated folder inside another role's" "inside boss's folder" env FM_HOME="$L/fm" FM_DRY_RUN=1 "$FM" out
refuse "and refuses the other roles while it stays there" "inside boss's folder" env FM_HOME="$L/fm" FM_DRY_RUN=1 "$FM" boss
printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' boss Boss opus max "$L/solo/inner" coordinator coordinator \
  out Out opus high "$L/solo" isolated outreach > "$L/fm/roles.tsv"
refuse "refuses an isolated folder that holds another role's" "which holds boss's folder" env FM_HOME="$L/fm" FM_DRY_RUN=1 "$FM" out
# Then an isolated folder that holds FM_HOME, and one that holds the launcher's own checkout.
mkdir -p "$L/base" "$L/kit/repo"
cp -R "$L/fm" "$L/base/fm"
printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' boss Boss opus max "$L/boss" coordinator coordinator \
  out Out opus high "$L/base" isolated outreach > "$L/base/fm/roles.tsv"
refuse "refuses an isolated folder that holds FM_HOME" "/base/fm; move one of them out" env FM_HOME="$L/base/fm" FM_DRY_RUN=1 "$FM" boss
cp -R "$ROOT/bin" "$ROOT/hooks" "$L/kit/repo/"
printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\n' boss Boss opus max "$L/boss" coordinator coordinator \
  out Out opus high "$L/kit" isolated outreach > "$L/fm/roles.tsv"
refuse "refuses an isolated folder that holds the launcher" "/kit/repo; move one of them out" \
  env FM_HOME="$L/fm" FM_DRY_RUN=1 "$L/kit/repo/bin/founder-mode" boss

echo "# a real launch, against a stand-in claude"
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then echo "${FAKE_VERSION:-2.1.296} (Claude Code)"; exit 0; fi
[ -L "$FM_HOME/state/$FM_ROLE.lock" ] && echo held > "$FM_HOME/state/$FM_ROLE.ran"
echo "${CLAUDE_CODE_DISABLE_AGENT_VIEW:-unset}" > "$FM_HOME/state/$FM_ROLE.agent-view"
echo "${CLAUDE_CODE_SAFE_MODE-unset}|${CLAUDE_CODE_SIMPLE-unset}" > "$FM_HOME/state/$FM_ROLE.modes"
while [ $# -gt 1 ]; do [ "$1" = --settings ] && printf '%s' "$2" > "$FM_HOME/state/$FM_ROLE.settings"; shift; done
exit 0
EOF
chmod +x "$T/bin/claude"
launch() { PATH="$T/bin:$PATH" "$FM" "$@"; }
refuse "refuses a claude older than 2.1.295" "needs Claude Code 2.1.295" env FAKE_VERSION=2.1.294 PATH="$T/bin:$PATH" "$FM" engineering
expect "accepts a newer minor version" env FAKE_VERSION=2.2.0 PATH="$T/bin:$PATH" "$FM" engineering --new
expect "a launch runs claude" launch engineering --new
expect "the lock is held while claude runs" grep -qx held "$FM_HOME/state/engineering.ran"
expect "no lock is left behind" test ! -e "$FM_HOME/state/engineering.lock"
expect "claude runs with agent view off" grep -qx 1 "$FM_HOME/state/engineering.agent-view"
env CLAUDE_CODE_SAFE_MODE=1 CLAUDE_CODE_SIMPLE=1 PATH="$T/bin:$PATH" "$FM" engineering --new 2>/dev/null
expect "and with CLAUDE_CODE_SAFE_MODE and CLAUDE_CODE_SIMPLE emptied, though the shell set them" \
  grep -qx '|' "$FM_HOME/state/engineering.modes"
env FM_ONE_SEND=buyer@example FM_SEND_TOOL=mcp__mail__send FM_SEND_TEXT="$T/approved.txt" PATH="$T/bin:$PATH" "$FM" outreach 2>/dev/null
g=$(jq -r '.hooks.PreToolUse[0].hooks[0].args[3]' "$FM_HOME/state/outreach.settings")
expect "a granted launch copies the approved text out of the role's reach" \
  cmp -s "$T/approved.txt" "$FM_HOME/state/outreach.one-send.$g.txt"

echo "# org chart notice, per conversation"
notice() {
  local k=member; [ "$1" = coordinator ] && k=coordinator
  "$ROOT/hooks/orgchart-notice.sh" "$FM_HOME" "$1" "$k" "$FM_HOME/roles/$1.md" <<<"{\"session_id\":\"${2:-}\"}"
}
said() { grep -q 'changed after this conversation started' <<<"$(notice "$@")"; }
st=$FM_HOME/state
touch -t 200001010000 "$FM_HOME/ORGCHART.md" "$FM_HOME/roles/engineering.md"
launch engineering --new
a=$(cat "$st/engineering.session")
touch -t 200101010000 "$st/engineering.launched"
expect "a new conversation starts quiet" test -z "$(notice engineering "$a")"
touch -t 200201010000 "$FM_HOME/ORGCHART.md"
launch engineering --new
expect "a conversation begun after the edit stays quiet" test -z "$(notice engineering "$(cat "$st/engineering.session")")"
echo '{"type":"user","agentName":"Engineering"}' > "$P/$a.jsonl"
launch engineering -r "$a"
expect "the older conversation, resumed, hears of the edit" said engineering "$a"
expect "once" test -z "$(notice engineering "$a")"
c=cccccccc-cccc-4ccc-8ccc-cccccccccccc
echo '{"type":"user","agentName":"Engineering"}' > "$P/$c.jsonl"
launch engineering -r "$c"
expect "a conversation resumed without a mark hears it once" said engineering "$c"
expect "a session id that isn't one is ignored" test -z "$(notice engineering '../x')"
expect "without its arguments it does nothing" test -z "$(FM_ROLE=coordinator FM_KIND=coordinator "$ROOT/hooks/orgchart-notice.sh" <<<'{}')"

echo "# irreversible-action guard"
guard() { jq -cn --arg c "$1" --arg t "${3:-Bash}" '{tool_name: $t, tool_input: {command: $c}}' \
  | "$ROOT/hooks/irreversible-guard.sh" "${2:-member}" 2>/dev/null; }
blocked() { guard "$@"; [ $? = 2 ]; }
while IFS= read -r c; do
  for tool in Bash Monitor; do expect "blocks ($tool): $c" blocked "$c" member "$tool"; done
done < <(printf '%s\n' 'gh pr merge 12 --squash' 'env GH_DEBUG=1 gh pr comment 3 --body hi' \
  'cd repo && gh pr review 1 --approve' 'gh api repos/o/r/issues/1/comments -f body=hi' 'gh api -X DELETE repos/o/r' \
  'gh issue create --title t' 'git -C repo push --force origin main' 'git push origin +main' 'git push origin :old' \
  'git push --force-with-lease=main origin main' 'git worktree remove --force ../wt' 'git worktree remove ../wt' \
  'docker compose -p app down -v' 'docker volume rm data' 'git push -fu origin feature' 'git push -uf origin feature' \
  'git push -d origin old' 'git push --prune origin' 'gh -R owner/repo pr merge 12' 'gh pr --repo owner/repo merge 12' \
  'gh --repo=o/r pr close 3' 'gh pr "merge" 12' 'gh secret --env prod set K' 'git push origin HEAD:main' \
  'git push origin main' 'git push -u origin feature:refs/heads/main' 'gh repo create acme/tool --public --source .' \
  'gh gist create --public notes' 'gh workflow run ci' 'gh secret set K' 'gh pr update-branch 3' \
  'gh issue transfer 3 o/r' 'gh label delete bug' 'gh run rerun 5' 'gh auth token' 'gh label clone o/r' \
  'echo $(gh pr merge 1)' 'gh pr view 1 && gh pr merge 1' \
  'git push origin main; git status' '(cd ../wt && git push origin main)' 'out=$(git push origin main)' \
  'git push origin main|tail -3' 'git push -f; echo done' '(cd ../wt && git push --force)' \
  '(cd ../wt && git push --force-with-lease)' 'git push origin feature -f;git log -1' \
  'docker compose down -v;docker compose up -d' '(docker compose down -v)' 'git push origin "main"' \
  'bash -c "git push origin main"' 'gh cs delete --all --force' 'gh cs ports visibility 3000:public -c x' \
  'gh cs create -r o/r' 'gh agent create "fix the flaky test"' 'gh agents create "fix the flaky test"' \
  'gh skills publish' 'gh extensions install owner/gh-x' 'gh api repos/o/r/issues/1/comments -fbody=hi' \
  'gh api repos/o/r/issues/1/comments -Fbody=@msg.txt' 'gh auth status --show-token' 'gh auth status -t' \
  'gh api graphql -f query="mutation { addStar(input: {starrableId: \"x\"}) { clientMutationId } }"' \
  'gh api graphql -F query=@q.graphql' 'gh api graphql -f query="$(cat q.graphql)"' 'GH_REPO=o/r gh pr merge 1' \
  'xargs -n1 gh pr merge' 'gh release create v1' \
  'gh api graphql -f query="{ viewer { login } }" && gh api repos/o/r/issues/1/comments -f body=hi' \
  'gh api graphql -f query="{ viewer { login } }"; gh api repos/o/r/issues/1/comments -F body=done' \
  'gh api graphql -f query="query { viewer { login } }" --jq .data.viewer.login && gh api -f body=LGTM repos/o/r/issues/5/comments' \
  'git -C "/tmp/my repo" push --force origin feature' 'git -C "/tmp/my repo" push origin main' \
  'git -C /tmp/my\ repo push --force origin feature' 'git push -f>/dev/null' 'git push origin main>push.log' \
  'git push origin feature --force>push.log' 'docker compose down -v>/dev/null' \
  'gh 2>/dev/null pr merge 1' 'git 2>&1 push --force origin x' 'git -C repo 2>/dev/null push origin main' \
  'docker compose 2>/dev/null down -v' 'bash <<<"git push origin main"' 'cat <(git push --force origin x)' \
  'gh copilot -p "merge PR 12 and delete the branch" --allow-all-tools' 'gh copilot' \
  'git push --all origin' 'git push origin --all' 'git push origin "refs/heads/*:refs/heads/*"' \
  'git push --branches origin' 'docker compose rm -sfv' 'docker rm -v web' 'docker container rm --volumes web' \
  'git push origin "$(git branch --show-current)" --force-with-lease' \
  'git push -u origin "$(git rev-parse --abbrev-ref HEAD)" -f' 'git -C "$(git rev-parse --show-toplevel)" push origin main' \
  'gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/3/merge" -X PUT' \
  'gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/issues/1/comments" -f body=hi' \
  'docker compose -p "$(basename "$PWD")" down -v' 'git push origin $(git branch --show-current) --force-with-lease' \
  'git -C $(git rev-parse --show-toplevel) push origin main' 'docker compose -p $(basename $PWD) down -v' \
  'git push origin `git branch --show-current` --force-with-lease' 'git -C `git rev-parse --show-toplevel` push origin main' \
  'gh api repos/`gh repo view --json nameWithOwner -q .nameWithOwner`/pulls/3/merge -X PUT' \
  'docker compose -p `basename $PWD` down -v' 'git push origin "$(echo "$(git branch --show-current)")" -f' \
  'git -C "/tmp/my repo/$(echo sub)" push --force origin feature' \
  'gh api -X GET repos/o/r/issues -f q=x --input body.json' \
  'gh api -X GET repos/o/r/issues -f q=x && gh api repos/o/r/issues/1/comments -f body=hi' \
  'gh pr $(echo merge) 1' 'gh $(echo pr) merge 1' 'gh pr `echo merge` 1' 'gh "$(echo pr)" merge 1' \
  'git push --tags origin' 'git push origin --tags' 'git push --follow-tags origin feature' \
  'git push origin refs/tags/v1.2.0' 'git push origin tag v1.2.0' 'git tag v1.2.0 && git push origin tag v1.2.0' \
  'git push origin HEAD:refs/tags/v1' 'git push --ta origin' 'git push --fol origin feature' \
  'git push --del origin old' 'git push --de origin old' 'git push --mirr origin' 'git push --m origin' \
  'git push origin feature --force-w' 'git push origin feature --force-i' 'git push --pru origin' \
  'git push --al origin' 'git push --b origin' 'gh pr $ACTION 1' 'gh pr "$ACTION" 1' 'gh pr ${ACTION} 1' \
  'gh $GROUP merge 1' "git push origin \$'main'" 'gh pr {merge,} 1' 'gh {pr,} merge 1' \
  'gh${IFS}pr${IFS}merge${IFS}1' 'git${IFS}push${IFS}--force')
expect 'blocks: gh pr \ + line break + merge 12' blocked $'gh pr \\\nmerge 12'
expect 'blocks: git push origin \ + line break + --force feature' blocked $'git push origin \\\n--force feature'
expect 'blocks: bash -c "git push \ + line break + origin main"' blocked $'bash -c "git push \\\norigin main"'
expect 'blocks: a GraphQL mutation written over several lines' blocked $'gh api graphql -f query=\'\n  mutation {\n    addStar(input: {starrableId: "x"}) { clientMutationId }\n  }\n\''
expect 'blocks: a mutation after a query in one GraphQL text' blocked $'gh api graphql -f query=\'query {\n  viewer { login }\n}\nmutation { addStar(input: {starrableId: "x"}) { clientMutationId } }\''
expect "blocks the coordinator's forced worktree removal: git worktree remove ../wt --force;ls" \
  blocked 'git worktree remove ../wt --force;ls' coordinator
while IFS= read -r c; do
  expect "allows: $c" guard "$c"
done < <(printf '%s\n' 'gh pr create --fill' 'gh pr view 1 --json state' 'gh -R o/r pr list' 'gh pr checks 3 --watch' \
  'gh run view 5 --log' 'gh api repos/o/r/pulls' 'gh auth status' 'gh search prs flaky' 'gh repo clone o/r' \
  'gh pr checkout 3' 'gh project item-list 1' 'gh cs list' 'git push origin feature' \
  'git push -u origin HEAD:refs/heads/feature' 'git push origin main-fix' 'git push -v origin feature' \
  'docker compose down' 'echo done' 'grep -rn "gh pr" .' 'git commit -m "Batch gh calls in the sync script"' \
  "git commit -m \"Don't push to main\"" 'git log --format="%h|%s" -5' 'ls ~/.config/gh' \
  'gh api graphql -f query="{ viewer { login } }"' 'gh pr list --json number --jq ".[] | .number"' \
  'git -C "/tmp/my repo" push origin feature' 'git push --no-follow-tags origin feature' 'docker rm -f web' \
  'git push --no-tags origin feature' 'git push --dry-run origin feature' 'git push --atomic origin feature' \
  'gh pr view "$(git branch --show-current)"' 'gh api "$(cat endpoint.txt)"' \
  'gh run view `gh run list --limit 1 --json databaseId -q ".[0].databaseId"` --log' \
  'gh pr view $PR' 'gh api $ENDPOINT' 'gh -R "$REPO" pr list' 'gh api repos/{owner}/{repo}/pulls' \
  'git push origin feature 2>&1 | tail -3' 'git push origin "$(git branch --show-current)"' \
  'git commit -m "$(cat msg.txt)"' 'git push -u origin `git branch --show-current`' 'echo $((1 + 2)) && git status' \
  "gh api -X GET search/issues -f q='repo:cli/cli is:open remote'" \
  'gh api --method GET repos/{owner}/{repo}/pulls -f state=closed' 'gh api --method=GET repos/o/r/issues -F per_page=100')
expect 'allows: a GraphQL read written over several lines' guard $'gh api graphql -f query=\'\n  query {\n    viewer { login }\n  }\n\''
expect "lets the coordinator remove a worktree" guard 'git worktree remove ../wt' coordinator
expect "inert without its argument, even with FM_ROLE set" env FM_ROLE=dev "$ROOT/hooks/irreversible-guard.sh" <<<"$merge"
expect "FM_UNLOCK=1 in its environment doesn't lift it" exit2 env FM_UNLOCK=1 "$ROOT/hooks/irreversible-guard.sh" member <<<"$merge"
# A 300 KB heredoc with a substitution, quotes and a gh read on every line, then a merge. The guard used to take
# minutes on this; a call that runs into the hook's timeout is blocked, so time is part of what it checks.
{ printf '%s\n' "cat > data.txt <<'EOF'"
  printf 'row %s: $(date +%%s) and "a quoted phrase" next to `hostname` and gh pr view 1, more text\n' {1..3500}
  printf '%s\n' EOF 'gh pr merge 1'; } | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' > "$T/big.json"
SECONDS=0
expect "blocks a merge after a 300 KB heredoc" exit2 "$ROOT/hooks/irreversible-guard.sh" member < "$T/big.json"
expect "and reads it in under 15 seconds (took ${SECONDS}s)" test "$SECONDS" -lt 15
# Without the merge every reading runs to the end, and 3,000 different gh api reads go through the api check.
jq '.tool_input.command |= sub("\ngh pr merge 1\n$"; "\n")' "$T/big.json" > "$T/big-pass.json"
{ printf '%s\n' "cat > data.txt <<'EOF'"
  printf 'gh api -X GET repos/o/r/issues/%s -f state=open --jq .number\n' {1..3000}
  printf '%s\n' EOF; } | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' > "$T/api.json"
SECONDS=0
expect "lets the same heredoc through without the merge" "$ROOT/hooks/irreversible-guard.sh" member < "$T/big-pass.json"
expect "and lets 3,000 gh api reads through" "$ROOT/hooks/irreversible-guard.sh" member < "$T/api.json"
expect "both in under 15 seconds (took ${SECONDS}s)" test "$SECONDS" -lt 15

echo "# hooks under another process's environment"
s=$(dump dev | arg --settings)
expect "the guard still blocks a merge" exit2 as_hook "$s" PreToolUse "$merge"
expect "and still stops a member removing a worktree" exit2 as_hook "$s" PreToolUse '{"tool_input":{"command":"git worktree remove ../wt"}}'
s=$(FM_ONE_SEND=buyer@example FM_SEND_TOOL=mcp__mail__send FM_SEND_TEXT="$T/approved.txt" dump outreach 2>/dev/null | arg --settings)
cp "$T/approved.txt" "$FM_HOME/state/outreach.one-send.$(jq -r '.hooks.PreToolUse[0].hooks[0].args[3]' <<<"$s").txt"
expect "the send gate refuses the address the environment names" exit2 as_hook "$s" PreToolUse \
  '{"tool_input":{"to":"eve@evil","subject":"Hello","body":"A short note."}}'
expect "and lets through the send its own grant names" as_hook "$s" PreToolUse \
  '{"tool_input":{"to":"buyer@example","subject":"Hello","body":"A short note."}}'

echo "# one-send guard"
mark=$FM_HOME/state/outreach.one-send.0a1b
printf '%s\n' 's' '' 'b' > "$mark.txt"
printf '%s\n' 's' '' 'b' > "$FM_HOME/state/outreach.one-send.0a1c.txt"
printf '%s\n' 'help@example' '' 'Write to help@example.' 'Thanks' > "$FM_HOME/state/outreach.one-send.0a1d.txt"
printf '%s\n' 's' '' 'b' > "$FM_HOME/state/outreach.one-send.0a1f.txt"
# sendas GRANT INPUT [ADDRESS]: the one-send hook for Outreach, with the arguments the launcher gives it.
sendas() { "$ROOT/hooks/one-send.sh" "$FM_HOME" outreach "${3:-buyer@example}" "$1" <<<"$2" 2>/dev/null; }
send() { sendas 0a1b "$1" Buyer@Example; }
refused() { rm -f "$mark"; send "$1"; [ $? = 2 ]; }
second() { send "$1"; [ $? = 2 ]; }
expect "lets the granted send through" send '{"tool_input":{"to":["Buyer <buyer@example>"],"subject":"s","body":"b"}}'
expect "refuses a second send" second '{"tool_input":{"to":["buyer@example"]}}'
expect "a new launch brings a new grant" sendas 0a1c '{"tool_input":{"to":"buyer@example","subject":"s","body":"b"}}'
expect "refuses a copy to anyone else" refused '{"tool_input":{"to":["buyer@example"],"cc":["other@example"],"subject":"s","body":"b"}}'
expect "refuses two addresses in one field" refused '{"tool_input":{"to":"eve@evil, Buyer <buyer@example>","subject":"s","body":"b"}}'
expect "refuses them inside a list" refused '{"tool_input":{"to":["eve@evil, Buyer <buyer@example>"],"subject":"s","body":"b"}}'
expect "refuses a copy written as text" refused '{"tool_input":{"to":"buyer@example","cc":"Eve <eve@evil>, Buyer <buyer@example>","subject":"s","body":"b"}}'
expect "refuses a field it doesn't know" refused '{"tool_input":{"to":"buyer@example","copy_to":"eve@evil","subject":"s","body":"b"}}'
expect "refuses a header list" refused '{"tool_input":{"to":"buyer@example","headers":[{"name":"Bcc","value":"eve@evil"}],"subject":"s","body":"b"}}'
expect "refuses a draft id, which sends the draft as it is" refused '{"tool_input":{"to":["buyer@example"],"draftId":"r-1","subject":"s","body":"b"}}'
expect "refuses reply-all" refused '{"tool_input":{"to":"buyer@example","replyAll":true,"subject":"s","body":"b"}}'
expect "refuses a line break in an address field" refused '{"tool_input":{"to":"buyer@example\r\nX-Note: y","subject":"s","body":"b"}}'
expect "refuses a call without recipients" refused '{"tool_input":{"subject":"s","body":"b"}}'
expect "refuses a body other than the approved one" refused '{"tool_input":{"to":"buyer@example","subject":"s","body":"b, and the thread below"}}'
expect "refuses an HTML body" refused '{"tool_input":{"to":"buyer@example","subject":"s","body":"b","html_body":"<p>other</p>"}}'
expect "refuses a grant whose text is missing" exit2 sendas 0a1e '{"tool_input":{"to":"buyer@example","subject":"s","body":"b"}}'
expect "an address or a line break in the approved body doesn't count" sendas 0a1d \
  '{"tool_input":{"to":"buyer@example","subject":"help@example","body":"Write to help@example.\nThanks"}}'
printf 'Hello\r\n\r\nA short note.\r\nThanks\r\n' > "$FM_HOME/state/outreach.one-send.0a20.txt"
expect "an approved text saved with CRLF still matches" sendas 0a20 \
  '{"tool_input":{"to":"buyer@example","subject":"Hello","body":"A short note.\nThanks"}}'
printf 'Hello\n\nA short note.\n' > "$FM_HOME/state/outreach.one-send.0a21.txt"
expect "and so does a body sent with CRLF" sendas 0a21 \
  '{"tool_input":{"to":"buyer@example","subject":"Hello","body":"A short note.\r\n"}}'
expect "refuses without its arguments, whatever its environment holds" exit2 env FM_HOME="$FM_HOME" FM_ROLE=outreach \
  FM_ONE_SEND=buyer@example FM_GRANT=0a1f "$ROOT/hooks/one-send.sh" <<<'{"tool_input":{"to":"buyer@example","subject":"s","body":"b"}}'
expect "refuses a grant without its launch id" exit2 sendas '' '{"tool_input":{"to":"buyer@example","subject":"s","body":"b"}}'

echo "# mail to the other founder"
box=$FM_HOME/state/founder-mail tofounder=$(cd "$HOME/outreach" && pwd -P)/kit/to-founder W=$T/mail
mkdir -p "$W"
fresh() { rm -rf "$box" "$tofounder" "$FM_HOME/state/founder-mail.unlock"; }
# note FILE SUBJECT [BODY]: a message signed by the Finance session.
note() { printf '%s\n' "$2" '' "${3:-The numbers for Monday.}" '' 'Finance' > "$W/$1"; }
fmail() { "$FM" mail "$@"; }
# fgate MODE FILE [CC]: the gate's answer to the call that sends that waiting text.
fgate() {
  local f=$box/pending/$2; [ -f "$f" ] || f=$W/$2
  jq -cn --arg s "$(head -n 1 "$f")" --arg b "$(tail -n +3 "$f")" --arg cc "${3:-}" \
    '{tool_input: ({to: "partner@example", subject: $s, body: $b} + if $cc != "" then {cc: $cc} else {} end)}' \
    | "$ROOT/hooks/founder-mail-gate.sh" "$1" "$FM_HOME" partner@example "$tofounder"
}
fsend() { fgate pre "$@" 2>/dev/null; }
aged() { touch -d '61 minutes ago' "$box/pending/${1%.md}.topic"; }
fresh; note a.md 'Monday numbers for the board'
refuse "mail needs a topic" "usage" fmail "$W/a.md"
for t in Monday ab -monday 'two words' "$(printf 'a%.0s' {1..41})"; do refuse "refuses the topic '$t'" "bad topic" fmail "$W/a.md" "$t"; done
printf '%s\n' 'Subject' '' 'Body' > "$W/unsigned.md"
refuse "a message names the session that wrote it" "names the session" fmail "$W/unsigned.md" unsigned
expect "a valid topic leaves the text waiting" fmail "$W/a.md" monday-numbers
expect "with its topic beside it, not in it" test "$(cat "$box/pending/a.topic")" = monday-numbers -a "$(cmp "$W/a.md" "$box/pending/a.md" && echo same)" = same
expect "and a copy in the mail role's kit" cmp -s "$W/a.md" "$tofounder/a.md"
refuse "the gate holds a fresh text for an hour" "60 to go" fgate pre a.md
note a2.md 'Monday numbers for the board, checked' 'The numbers for Monday, checked.'
expect "the same topic while it waits replaces the text" fmail "$W/a2.md" monday-numbers
expect "and drops the old text, topic and kit copy" test ! -e "$box/pending/a.md" -a ! -e "$box/pending/a.topic" -a ! -e "$tofounder/a.md"
refuse "the replaced text no longer sends" "matches no text" fgate pre a.md
refuse "and the wait starts again" "60 to go" fgate pre a2.md
echo a2.md > "$FM_HOME/state/founder-mail.now"
expect "a founder's order to send now skips the wait" fsend a2.md
refuse "and covers no other text" "matches no text" fgate pre a.md
rm "$FM_HOME/state/founder-mail.now"
aged a2.md
expect "after the wait it sends" fsend a2.md
refuse "with a copy to anyone, it doesn't" "no copies" fgate pre a2.md eve@example
fgate post a2.md
expect "the post hook logs four columns, the topic last" test "$(awk -F'\t' '{ print NF "|" $4 }' "$box/sent.tsv")" = '4|monday-numbers'
expect "and archives the text and drops the kit copy" test -z "$(ls "$box/pending")" -a ! -e "$tofounder/a2.md"
note b.md 'Something else about the budget' 'New body.'
refuse "a topic that went out is refused" "Only a founder unlocks it" fmail "$W/b.md" monday-numbers
cp "$W/b.md" "$box/pending/b.md"; echo monday-numbers > "$box/pending/b.topic"; aged b.md
refuse "and so is a text slipped into pending by hand" "already went" fgate pre b.md
rm "$box/pending/b.md" "$box/pending/b.topic"
printf '%s\n' other-topic monday-numbers > "$FM_HOME/state/founder-mail.unlock"
expect "a founder's unlock line lets it through once" fmail "$W/b.md" monday-numbers
aged b.md
expect "past the gate too" fsend b.md
echo b.md > "$FM_HOME/state/founder-mail.now"
fgate post b.md
expect "and the order to send now, if any" test ! -s "$FM_HOME/state/founder-mail.now"
expect "the send uses that line up and keeps the others" test "$(cat "$FM_HOME/state/founder-mail.unlock")" = other-topic
note c.md 'A third thing with no relation' 'Body three.'
refuse "then it is refused again" "went out" fmail "$W/c.md" monday-numbers
fresh
printf '%s\told.md\tYearly budget for the company\n' "$(date -d '2 days ago' '+%F %T')" > "$box/sent.tsv" 2>/dev/null \
  || { mkdir -p "$box"; printf '%s\told.md\tYearly budget for the company\n' "$(date -d '2 days ago' '+%F %T')" > "$box/sent.tsv"; }
note d.md 'Test calendar for the demo' 'Body.'
expect "an old three-column row doesn't block a new topic" fmail "$W/d.md" test-calendar
aged d.md
expect "and the gate reads it" fsend d.md
note e.md 'Yearly budget for the company, revised'
refuse "a subject close to an old row's is the same topic" "too close" fmail "$W/e.md" budget
for s in 'Correction: Monday numbers' 'This replaces my earlier note' 'Errata in the table' 'One thing I forgot' 'I was wrong about the date'; do
  note f.md "$s"; refuse "refuses a correction: $s" "corrects an earlier email" fmail "$W/f.md" new-topic
done
note f.md 'Monday plan' $'Hello.\nI FORGOT one thing in the last one.'
refuse "and one in the body's second line" "corrects" fmail "$W/f.md" new-topic
note f.md 'Monday plan' $'One.\nTwo.\nThree.\nFour: better than the previous one.'
expect "a word on the body's fourth line doesn't count" fmail "$W/f.md" new-topic
printf '%s\tx.md\tNotes from the partner call\tpartner-notes\n' "$(date -d '2 days ago' '+%F %T')" >> "$box/sent.tsv"
printf '%s\ty.md\tPricing sheet for the pilot\tpricing\n' "$(date -d '8 days ago' '+%F %T')" >> "$box/sent.tsv"
note g.md 'Partner call notes: summary'
refuse "a subject close to one sent 2 days ago, under another topic" "too close" fmail "$W/g.md" call-summary
note g.md 'Pricing sheet for the pilot, part two'
expect "one sent 8 days ago doesn't count" fmail "$W/g.md" pricing-two
note h.md 'Pricing sheet for pilot: part two'
refuse "a subject close to a waiting one under another topic" "run this with pricing-two" fmail "$W/h.md" pricing-three
for x in 1 2 3 4 5; do printf '%s\tv%s.md\tOld subject %s\n' "$(date '+%F %T')" "$x" "$x" >> "$box/sent.tsv"; done
aged g.md
refuse "the gate keeps the cap of 5 a day" "cap 5" fgate pre g.md
refuse "without its arguments the gate refuses" "not started by founder-mode" "$ROOT/hooks/founder-mail-gate.sh" <<<'{"tool_input":{}}'
d=$(FM_FOUNDER_MAIL=partner@example FM_SEND_TOOL=mcp__mail__send dump outreach 2>"$T/fm.err" | arg --settings)
expect "FM_FOUNDER_MAIL is announced" grep -qF 'send to partner@example' "$T/fm.err"
expect "and hooks the send tool in Pre, blocking when it can't run, and in Post" jq -e --arg c "$ROOT/hooks/founder-mail-gate.sh" \
  --arg h "$FM_HOME" --arg k "$tofounder" '
  (.hooks.PreToolUse | map(select(.matcher == "mcp__mail__send")) | .[0].hooks[0]
    | .command == $c and .args == ["pre", $h, "partner@example", $k] and .onFailure == "block")
  and (.hooks.PostToolUse | map(select(.matcher == "mcp__mail__send")) | .[0].hooks[0].args == ["post", $h, "partner@example", $k])' <<<"$d"
refuse "FM_FOUNDER_MAIL needs the mail role" "only applies to the mail role" env FM_FOUNDER_MAIL=p@example FM_SEND_TOOL=x FM_DRY_RUN=1 "$FM" finance
refuse "and a send tool" "FM_SEND_TOOL" env FM_FOUNDER_MAIL=p@example FM_DRY_RUN=1 "$FM" outreach
refuse "and refuses FM_ONE_SEND in the same launch" "with one of them" env FM_FOUNDER_MAIL=p@example FM_ONE_SEND=b@example \
  FM_SEND_TOOL=x FM_SEND_TEXT="$T/approved.txt" FM_DRY_RUN=1 "$FM" outreach
for c in "echo monday >> $FM_HOME/state/founder-mail.unlock" "printf 'x\n'>$FM_HOME/state/founder-mail.unlock" \
  "cat $FM_HOME/state/outbound.unlock" "echo a.md > $FM_HOME/state/founder-mail.now" "cd $FM_HOME/state && tee -a founder-mail.\"unlock\" <<< x" \
  $'echo x \\\n >> '"$FM_HOME/state/outbound.unlock"; do
  expect "the guard blocks: $c" blocked "$c"
done
expect "and lets founder-mode mail run" guard 'founder-mode mail note.md monday-numbers'

echo "# outbound gate"
og() { "$ROOT/hooks/outbound-gate.sh" "$1" "$FM_HOME" "${2:-draft}"; }
# draft TO SUBJECT [BODY] [CC]: the draft call the mail role would make.
draft() { jq -cn --arg t "$1" --arg s "$2" --arg b "${3:-Hello.}" --arg cc "${4:-}" \
  '{tool_input: ({to: [$t], subject: $s, body: $b} + if $cc != "" then {cc: [$cc]} else {} end)}'; }
dpass() { draft "$@" | og pre 2>/dev/null; }
dlog() { draft "$@" | og post; }
row() { printf '%s\t%s\t%s\t%s\tdraft\n' "$(date -d "$1 days ago" '+%F %T')" "$2" "${2#*@}" "$3" >> "$FM_HOME/state/outbound.tsv"; }
outfresh() { rm -f "$FM_HOME/state/outbound.tsv" "$FM_HOME/state/outbound.unlock"; }
outfresh
expect "a first draft to an address passes" dpass ann@acme.example 'Pilot proposal'
dlog ann@acme.example 'Pilot proposal' 'Hello.' lou@acme.example
expect "the post hook logs one row per address, with domain, subject and kind" \
  test "$(cut -f2- "$FM_HOME/state/outbound.tsv" | tr '\t\n' '|;')" = 'ann@acme.example|acme.example|Pilot proposal|draft;lou@acme.example|acme.example|Pilot proposal|draft;'
refuse "the same address within 7 days, on any topic" "One email per address" bash -c 'jq -cn "{tool_input:{to:\"ann@acme.example\",subject:\"Other\",body:\"x\"}}" | "$0" pre "$1" draft' "$ROOT/hooks/outbound-gate.sh" "$FM_HOME"
refuse "and says to stop and log it" "don't try another way" bash -c 'jq -cn "{tool_input:{to:\"eve@acme.example\",subject:\"Other\",body:\"x\"}}" | "$0" pre "$1" draft' "$ROOT/hooks/outbound-gate.sh" "$FM_HOME"
expect "another person at the same company is refused" exit2x dpass eve@acme.example 'Something else'
expect "an address already mailed, in cc, is refused" exit2x dpass eve@beta.example 'Calendar' 'Hello.' ann@acme.example
expect "a public provider counts by address" dpass fm-smoke-pat@gmail.com 'Calendar'
dlog fm-smoke-pat@gmail.com 'Calendar'
expect "so another address there passes" dpass fm-smoke-joe@gmail.com 'Budget'
expect "and the same one doesn't" exit2x dpass fm-smoke-pat@gmail.com 'Budget'
expect "nor with a dot after the domain" exit2x dpass fm-smoke-pat@gmail.com. 'Budget'
expect "and that dot doesn't make a new company" exit2x dpass eve@acme.example. 'Something else'
row 8 x@gamma.example 'Pilot proposal for the client'
expect "after 8 days, a subject close to one the company got within 30 is refused" exit2x dpass x@gamma.example 'Pilot proposal for client, second version'
expect "and a different one passes" dpass y@gamma.example 'Demo test calendar'
row 31 z@delta.example 'Pilot proposal for the client'
expect "a subject the company got 31 days ago passes" dpass z@delta.example 'Pilot proposal for the client'
expect "a correction is refused" exit2x dpass new@eps.example 'Correction to the proposal'
expect "and so is one in the body" exit2x dpass new@eps.example 'Pilot' $'Hello.\nI was wrong about the figure.'
expect "a call without recipients is refused" exit2x og pre <<<'{"tool_input":{"subject":"Hi","body":"x"}}'
echo ann@acme.example > "$FM_HOME/state/outbound.unlock"
expect "a founder's unlock for the address lets one through" dpass ann@acme.example 'Follow-up'
dlog ann@acme.example 'Follow-up'
expect "the post hook uses it up" test ! -s "$FM_HOME/state/outbound.unlock"
expect "then the address is refused again" exit2x dpass ann@acme.example 'Follow-up two'
echo @acme.example > "$FM_HOME/state/outbound.unlock"
expect "@domain unlocks the company, a correction too" dpass eve@acme.example 'Correction to the calendar'
echo @gmail.com > "$FM_HOME/state/outbound.unlock"
expect "@ and a public provider unlocks no one there" exit2x dpass fm-smoke-pat@gmail.com 'More'
expect "without its arguments it refuses" exit2x "$ROOT/hooks/outbound-gate.sh" <<<'{"tool_input":{"to":"a@b.example"}}'
outfresh
row 2 buyer@example 'Hello'
printf '%s\n' 's' '' 'b' > "$FM_HOME/state/outreach.one-send.0b01.txt"
expect "a founder's send grant doesn't lift the outbound rules" exit2 sendas 0b01 '{"tool_input":{"to":"buyer@example","subject":"s","body":"b"}}'
expect "and the refusal leaves the grant unused" test ! -e "$FM_HOME/state/outreach.one-send.0b01"
outfresh

echo "# subagent tiers"
tier() { jq -cn --arg t "$1" '{tool_input: {subagent_type: $t, description: "count the rows"}}' \
  | "$ROOT/hooks/subagent-tier.sh" intern junior senior | jq -rs '.[0].hookSpecificOutput.permissionDecision // "allow"'; }
for t in '' general-purpose Explore Plan fork; do expect "refuses a subagent of type ${t:-none}" test "$(tier "$t")" = deny; done
for t in intern junior senior my-own-agent; do expect "lets the $t through" test "$(tier "$t")" = allow; done
expect "the tier hook names the tiers" grep -qF 'intern junior senior' <<<"$(jq -cn '{tool_input: {}}' | "$ROOT/hooks/subagent-tier.sh" intern junior senior)"
expect "without its arguments it does nothing" test -z "$("$ROOT/hooks/subagent-tier.sh" <<<'{"tool_input":{}}')"

echo "# delegation log"
dlog() { jq -cn --arg t "$1" --arg u "${2:-toolu_01ABCDEFGH12345678}" \
  '{tool_use_id: $u, tool_input: {subagent_type: $t, description: "count\tthe rows"}}' \
  | "$ROOT/hooks/delegation-log.sh" "$FM_HOME" dev intern junior senior; }
L=$FM_HOME/state/delegations.tsv
c=$(dlog junior | jq -r .hookSpecificOutput.additionalContext)
expect "logs a call to a tier and gives its id" grep -qF 'call as 12345678' <<<"$c"
expect "the log line holds role, tier, id and description" grep -qP '\tdev\tjunior\t12345678\tcount the rows$' "$L"
expect "and the note names the command that marks it" grep -qF "$ROOT/bin/founder-mode delegations 12345678" <<<"$c"
dlog general-purpose >/dev/null
expect "ignores a type outside the tiers" test "$(wc -l < "$L")" = 1
dlog intern toolu_01ZZZZZZZZ87654321 >/dev/null
expect "lists the unmarked calls" test "$("$FM" delegations | cut -f4 | tr '\n' ' ')" = '12345678 87654321 '
expect "marks one" "$FM" delegations 12345678 ok 'src/a.js:12'
expect "and lists only the other" test "$("$FM" delegations | cut -f4)" = 87654321
expect "lists only the caller's own" test -z "$(FM_ROLE=legal "$FM" delegations)"
refuse "refuses an unknown status" "unknown status" "$FM" delegations 87654321 fine
refuse "refuses an id that isn't logged" "no delegation" "$FM" delegations 00000000 ok
expect "without its arguments the hook does nothing" test -z "$("$ROOT/hooks/delegation-log.sh" <<<'{"tool_input":{"subagent_type":"junior"}}')"

echo "# deliverable check"
ck() { node "$ROOT/bin/check-text.js" --terms "$FM_HOME/forbidden-terms.tsv" "$@"; }
D=$T/deliv; mkdir -p "$D"
printf 'Plain text, nothing wrong.\n' > "$D/clean.md"
expect "a clean text passes" ck "$D/clean.md"
printf 'One %s two\nCo-Authored-By: x\nkey sk-ant-abc123\n' $'\u2014' > "$D/bad.txt"
o=$(ck "$D/bad.txt"); r=$?
expect "a text with findings exits 1" test "$r" = 1
expect "finds the em dash" grep -qF 'line 1: [dash or arrow] em dash U+2014' <<<"$o"
expect "finds the attribution line" grep -qF 'line 2: [attribution]' <<<"$o"
expect "finds the secret and hides it" grep -qx "$D/bad.txt: line 3: \[secret\]" <<<"$o"
printf 'a &rarr; b\n' > "$D/ent.html"
expect "reads an HTML entity as the character" exit1 ck "$D/ent.html"
printf '%s\n' 'Use `a %s b` in code.' '```' 'x %s y' '```' > "$D/code.md"
sed -i "s/%s/$(printf '\u2192')/g" "$D/code.md"
expect "Markdown code doesn't count for dashes and arrows" ck "$D/code.md"
printf 'old-name\tAcme Old\nconfidential\tHushco\n' >> "$FM_HOME/forbidden-terms.tsv"
printf 'We were Acme Old.\nTalks with hushco went well.\nHushcorp is fine.\n' > "$D/names.md"
o=$(ck "$D/names.md")
expect "prints an old name" grep -qF 'line 1: [old name] Acme Old' <<<"$o"
expect "hides a confidential name and its context" grep -qx "$D/names.md: line 2: \[confidential name\]" <<<"$o"
expect "matches whole words only" lacks 'line 3' "$o"
printf 'guess\tprobably\nguess\tpodría deberse\nsource-tag\tfuente:\n' >> "$FM_HOME/forbidden-terms.tsv"
printf '%s\n' 'It is probably the mesh.' 'Esto podría deberse a la malla.' 'Use `probably` in code.' > "$D/guess.md"
o=$(ck "$D/guess.md")
expect "prints a guess" grep -qF 'line 1: [guess] probably' <<<"$o"
expect "finds a guess with an accent" grep -qF 'line 2: [guess] podría deberse' <<<"$o"
expect "a guess in Markdown code doesn't count" lacks 'line 3' "$o"
printf '%s\n' '\section{Results}' '' \
  'The drag coefficient of the chosen mesh is within one percent of the finest mesh in the study.' \
  '% source: study.csv, rows 3 and 5' '' \
  'The friction share grows with the mesh because the prism layers scale with the base size here.' '' \
  'Este párrafo cita su fuente con la etiqueta en castellano y tiene palabras de sobra para contar.' \
  '% fuente: estudio.pdf, p. 2' '' \
  'Fine. % probably not' '' \
  '\begin{thebibliography}{9}' '\bibitem{a} A. Author. A book. % source: book.pdf, p. 3' \
  '\bibitem{b} B. Author. A book nobody opened.' '\end{thebibliography}' > "$D/report.tex"
o=$(ck --sources "$D/report.tex")
expect "a paragraph with its source passes" lacks 'line 3:' "$o"
expect "flags a paragraph without a source" grep -qF 'line 6: [no source]' <<<"$o"
expect "a source tag from the terms file counts" lacks 'line 8:' "$o"
expect "a guess in a LaTeX comment doesn't count" lacks 'line 11:' "$o"
expect "a heading needs no source" lacks 'line 1:' "$o"
expect "a \\bibitem with its source passes" lacks 'line 14:' "$o"
expect "flags a \\bibitem without a source" grep -qF 'line 15: [no source] \bibitem{b}' <<<"$o"
expect "without --sources it skips sources" lacks 'no source' "$(ck "$D/report.tex")"
printf '%s\n' '<!-- source: https://example.org/a.pdf, p. 4 -->' \
  'This paragraph names its source in an HTML comment on the line above it, as Markdown allows.' > "$D/sourced.md"
expect "an HTML comment carries the tag in Markdown" ck --sources "$D/sourced.md"
printf '%s\n' '\section{Results}\label{sec:results}' \
  'The drag coefficient of the chosen mesh is within one percent of the finest mesh here.' '' \
  '\noindent The friction share grows with the mesh because the prism layers scale with the base size.' '' \
  '\citet{a} measured the same share on a coarser mesh with the same prism layers and base size.' '' \
  '\begin{itemize}' '\item A list item with enough words to count as a paragraph if lists were prose here.' \
  '\end{itemize}' '' '\begin{figure}' \
  '\caption{A caption with enough words to count as a paragraph if captions were prose here.}' \
  '\end{figure}' > "$D/lead.tex"
o=$(ck --sources "$D/lead.tex")
expect "flags a paragraph right under a heading" grep -qF 'line 2: [no source]' <<<"$o"
expect "flags a paragraph that opens with \\noindent" grep -qF 'line 4: [no source]' <<<"$o"
expect "flags a paragraph that opens with a command" grep -qF 'line 6: [no source]' <<<"$o"
expect "skips the list and the caption" test "$(grep -c 'no source' <<<"$o")" = 3
printf '%s\n' '## Results' 'The drag coefficient of the chosen mesh is within one percent of the finest mesh here.' > "$D/lead.md"
expect "flags a Markdown paragraph right under a heading" grep -qF 'line 2: [no source]' <<<"$(ck --sources "$D/lead.md")"
printf '%s\n' '<h2>Results</h2>' \
  '<p>The friction share grows with the mesh because the prism layers scale with the base size.</p>' > "$D/lead.html"
expect "flags an HTML paragraph in <p> under a heading" grep -qF 'line 2: [no source]' <<<"$(ck --sources "$D/lead.html")"
expect "an unreadable file exits 2" exit2x ck "$D/missing.md"
echo "$D/*.md" >> "$FM_HOME/deliverables.txt"
expect "the hook reports on a deliverable" grep -qF 'confidential name' <<<"$(jq -cn --arg f "$D/names.md" '{tool_input: {file_path: $f}}' | "$ROOT/hooks/deliverable-check.sh" "$FM_HOME")"
expect "and stays quiet on a clean one" test -z "$(jq -cn --arg f "$D/clean.md" '{tool_input: {file_path: $f}}' | "$ROOT/hooks/deliverable-check.sh" "$FM_HOME")"
expect "and on a file outside the list" test -z "$(jq -cn --arg f "$D/bad.txt" '{tool_input: {file_path: $f}}' | "$ROOT/hooks/deliverable-check.sh" "$FM_HOME")"
expect "without its argument it does nothing" test -z "$(jq -cn --arg f "$D/names.md" '{tool_input: {file_path: $f}}' | FM_HOME=$FM_HOME "$ROOT/hooks/deliverable-check.sh")"
echo "$D/*.tex" >> "$FM_HOME/sourced.txt"
o=$(jq -cn --arg f "$D/report.tex" '{tool_input: {file_path: $f}}' | "$ROOT/hooks/deliverable-check.sh" "$FM_HOME")
expect "the hook checks sources in a file of sourced.txt" grep -qF 'no source' <<<"$o"
expect "and says to check or delete, not soften" grep -qF 'or delete it' <<<"$o"

echo "# weekly cap"
now=$(date +%s)
# cap EVENT KIND UTILIZATION [RESET_OFFSET] [AGE]: the hook's decision, with a reading written AGE seconds ago.
cap() {
  jq -cn --argjson u "$3" --argjson r "$((now + ${4:-86400}))" --argjson a "$((now - ${5:-60}))" \
    '{seven_day: {utilization: $u, resets_at: $r}, read_at: $a}' > "$FM_HOME/state/usage.json"
  jq -cn --arg e "$1" '{hook_event_name: $e}' | "$ROOT/hooks/weekly-cap.sh" "$FM_HOME" "$2" \
    | jq -rs '.[0] | if . == null then "none" else .hookSpecificOutput.permissionDecision // .decision // "note" end'
}
expect "no cap file, no cap" test "$(cap PreToolUse member 99)" = none
echo 80 > "$FM_HOME/weekly-cap"
expect "denies a tool at the cap" test "$(cap PreToolUse member 80)" = deny
expect "lets a tool through under it" test "$(cap PreToolUse member 79.9)" = none
expect "blocks a member's prompt" test "$(cap UserPromptSubmit member 85)" = block
expect "lets the coordinator answer, with a note" test "$(cap UserPromptSubmit coordinator 85)" = note
expect "and still denies the coordinator's tools" test "$(cap PreToolUse coordinator 85)" = deny
expect "ignores a reading older than two hours" test "$(cap PreToolUse member 85 86400 7300)" = none
expect "ignores a week that has reset" test "$(cap PreToolUse member 85 -60)" = none
echo high > "$FM_HOME/weekly-cap"
expect "a cap that isn't a number does nothing" test "$(cap PreToolUse member 99)" = none
echo 80 > "$FM_HOME/weekly-cap"
echo 'not json' > "$FM_HOME/state/usage.json"
expect "a broken reading does nothing" test -z "$("$ROOT/hooks/weekly-cap.sh" "$FM_HOME" member <<<'{"hook_event_name":"PreToolUse"}')"
cap PreToolUse member 85 >/dev/null
expect "without its arguments it does nothing" test -z "$(FM_HOME=$FM_HOME "$ROOT/hooks/weekly-cap.sh" <<<'{"hook_event_name":"PreToolUse"}')"
rm "$FM_HOME/weekly-cap" "$FM_HOME/state/usage.json"

echo "# the Design role's plugin and SKILLS.md"
mkdir -p "$FM_HOME/plugins/design/.claude-plugin"
awk '/```json$/ { f = 1; next } /```$/ { f = 0 } f' "$ROOT/SKILLS.md" > "$FM_HOME/plugins/design/.claude-plugin/plugin.json"
expect "SKILLS.md's plugin file is valid JSON" jq -e '.name == "design"' "$FM_HOME/plugins/design/.claude-plugin/plugin.json"
expect "the launcher passes the plugin to Design" test "$(dump design | arg --plugin-dir)" = "$FM_HOME/plugins/design"
expect "and to no other role" lacks --plugin-dir "$(dry engineering)"
rm -rf "$FM_HOME/plugins"
expect "without a plugin file, Design gets no --plugin-dir" lacks --plugin-dir "$(dry design)"
expect "every GitHub link in SKILLS.md is pinned to a commit" \
  test -z "$(grep -oE 'https://github.com/[^)]*' "$ROOT/SKILLS.md" | grep -vE '^https://github.com/[^/]+/[^/]+/tree/[0-9a-f]{40}(/|$)')"
expect "and so is every one in the README's skills table" \
  test -z "$(sed -n '/^## Skills we use most/,/^## Limits/p' "$ROOT/README.md" | grep -oE 'https://github.com/[^)]*' | grep -vE '/tree/[0-9a-f]{40}(/|$)')"

echo "# the pending log and its SQL views (pilot)"
if command -v python3 >/dev/null; then
  expect "the pilot's self-test passes" "$ROOT/bin/db" --selftest
  refuse "refuses a write from a role that doesn't write" "FM_ROLE must be" env FM_ROLE=advisor1 "$FM" db open --owner dev --source f:1 'An item'
  refuse "refuses a write without a source" "source: missing" env FM_ROLE=dev "$FM" db open --owner legal 'An item'
  refuse "refuses a secret pattern and doesn't repeat it" "text: holds a secret pattern" env FM_ROLE=dev "$FM" db open --owner legal --source f:1 "token=$(printf 'x9%.0s' 1 2 3 4)"
  expect "opens an item through the launcher" env FM_ROLE=dev "$FM" db open --owner legal --source 'notes.md:3' --due 2001-01-01 'Send the form'
  item=$("$FM" db pending | awk -F'\t' 'NR == 2 { print $1 }')
  expect "lists it as pending and overdue" test "$("$FM" db overdue | cut -f2,6 | tail -n 1)" = "legal	Send the form"
  refuse "a third role can't close it" "only the owner" env FM_ROLE=design "$FM" db close "$item" --source f:2
  expect "its owner closes it" env FM_ROLE=legal "$FM" db close "$item" --source f:2 done
  expect "the log only grew" test "$(grep -c "	$item	" "$FM_HOME/pending/events.tsv")" = 2
  expect "q reads the views" test "$("$FM" db q "SELECT state, creator FROM pending" | tail -n 1)" = "closed	dev"
  refuse "q refuses a write" "q takes only SELECT or WITH" "$FM" db q "DELETE FROM pending"
  refuse "and a write inside a WITH" "query refused" "$FM" db q "WITH x AS (SELECT 1) DELETE FROM pending"
  expect "the views leave no database file" test -z "$(find "$FM_HOME/pending" -type f ! -name events.tsv)"
  rm -rf "$FM_HOME/pending"
else
  echo "skip  python3 is not installed: the pilot's cases didn't run"
fi

echo "# stalled sessions"
ids=55555555-5555-4555-8555-555555555555
echo "$ids" > "$FM_HOME/state/dev.session"
printf '%s\n' '{"type":"user","message":{"content":"go on"}}' \
  '{"type":"assistant","isApiErrorMessage":true,"timestamp":"2001-01-01T09:00:00Z","message":{"content":[{"type":"text","text":"usage limit reached"}]}}' \
  '{"type":"system"}' > "$P/$ids.jsonl"
expect "lists a session stopped on an API error" grep -q '^Dev .*usage limit reached' <<<"$("$FM" stalled)"
expect "leaves out the caller" grep -q '^No session' <<<"$(FM_ROLE=dev "$FM" stalled)"
expect "--hook skips closed sessions" test -z "$("$FM" stalled --hook)"
reg $$ "$ids" Dev
expect "the coordinator's hook names a live one" grep -q 'Dev (since' <<<"$(notice coordinator)"
expect "and still does under an environment that says it is a member" \
  grep -q 'Dev (since' <<<"$(KIND=member as_hook "$(dump coordinator | arg --settings)" UserPromptSubmit '{}')"
expect "a member's hook names none, under an environment that says it is the coordinator" \
  test -z "$(ENV_HOME=$FM_HOME as_hook "$(dump engineering | arg --settings)" UserPromptSubmit '{}')"
idc=77777777-7777-4777-8777-777777777777
echo "$idc" > "$FM_HOME/state/coordinator.session"
cp "$P/$ids.jsonl" "$P/$idc.jsonl"
cs=$(dump coordinator | arg --settings)
reg $$ "$idc" Coordinator
expect "the coordinator's hook leaves the coordinator out, whatever role the environment names" \
  lacks 'Coordinator (since' "$(ENV_HOME=$FM_HOME KIND=member as_hook "$cs" UserPromptSubmit '{}')"
rm "$HOME/.claude/sessions/$$.json"
ido=66666666-6666-4666-8666-666666666666
echo "$ido" > "$FM_HOME/state/outreach.session"
cp "$P/$ids.jsonl" "$P/$ido.jsonl"
reg $$ "$ido" Outreach
h=$(notice coordinator)
expect "the hook lists the isolated role apart" grep -q 'closed to messages: Outreach' <<<"$h"
expect "and asks a founder to resume it" grep -q 'Ask a founder to resume it' <<<"$h"
rm "$HOME/.claude/sessions/$$.json"

echo "# the conversation pointer follows /clear"
# Legal's pointer names a conversation that ended well; after /clear, the new one stops on a usage limit.
old=99999999-9999-4999-8999-999999999999 new=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
printf '%s\n' '{"type":"user","agentName":"Legal"}' '{"type":"assistant","message":{"content":"done"}}' > "$P/$old.jsonl"
printf '%s\n' '{"type":"user","agentName":"Legal"}' \
  '{"type":"assistant","isApiErrorMessage":true,"timestamp":"2001-01-01T09:00:00Z","message":{"content":"usage limit reached"}}' \
  > "$P/$new.jsonl"
echo "$old" > "$FM_HOME/state/legal.session"
expect "before the hook, stalled misses the conversation that /clear started" lacks Legal "$("$FM" stalled)"
pointer() { "$ROOT/hooks/session-pointer.sh" "$@"; }
expect "the hook prints nothing, since its stdout becomes context" \
  test -z "$(pointer "$FM_HOME" legal <<<"{\"session_id\":\"$new\",\"source\":\"clear\"}")"
expect "it points the role at the new conversation" test "$(cat "$FM_HOME/state/legal.session")" = "$new"
expect "stalled now finds it" grep -q '^Legal .*usage limit reached' <<<"$("$FM" stalled)"
expect "and the next launch resumes it" test "$(dump legal | arg -r)" = "$new"
pointer "$FM_HOME" legal <<<'{"session_id":"../../x","source":"clear"}'
expect "it ignores a session id that isn't a UUID" test "$(cat "$FM_HOME/state/legal.session")" = "$new"
pointer "$FM_HOME" legal <<<"{\"session_id\":\"$old\",\"source\":\"resume\"}"
expect "it ignores a resume, which the launcher points itself or /resume may take to another role" \
  test "$(cat "$FM_HOME/state/legal.session")" = "$new"
echo "$old" > "$FM_HOME/state/legal.session"
pointer <<<"{\"session_id\":\"$new\"}"
expect "without its arguments it does nothing" test "$(cat "$FM_HOME/state/legal.session")" = "$old"
ENV_HOME=$T/elsewhere as_hook "$(dump legal | arg --settings)" SessionStart "{\"session_id\":\"$new\",\"source\":\"clear\"}"
expect "it writes where its arguments say, whatever the environment names" \
  test "$(cat "$FM_HOME/state/legal.session")" = "$new" -a ! -e "$T/elsewhere/state/legal.session"

echo "# the README's quick start, on a machine without ~/.local/bin on its PATH"
Q=$T/clean
mkdir -p "$Q"
# The block up to its dry run, with the clone swapped for a link to this checkout and the editor lines left out. The
# PATH drops every folder that holds a founder-mode, and the stand-in claude comes first, so the real one can't start.
qs=$(awk '/^## Quick start/ { q = 1 } q && /^```bash$/ { b = 1; next } b && /^```$/ { exit } b { print } b && /FM_DRY_RUN=1/ { exit }' \
  "$ROOT/README.md" | sed -e "s|^git clone <this repository> ~/founder-mode|ln -s '$ROOT' ~/founder-mode|" -e '/EDITOR/d')
qp=$T/bin
while IFS= read -r x; do [ -n "$x" ] && [ ! -e "$x/founder-mode" ] && qp+=:$x; done < <(tr ':' '\n' <<<"$PATH")
expect "the block has the dry run" grep -qF 'FM_DRY_RUN=1 founder-mode coordinator' <<<"$qs"
expect "it runs from a clean home" env -i HOME="$Q" PATH="$qp" bash -euc "$qs"
expect "and leaves the launcher and the org chart in place" test -x "$Q/.local/bin/founder-mode" -a -f "$Q/.founder-mode/ORGCHART.md"

echo "$fails failed"
[ "$fails" = 0 ]
