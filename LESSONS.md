# Lessons

Founder Mode comes from a small company that ran about ten Claude Code sessions on one account for several weeks. Most entries record something that went wrong there, or that a reviewer caught in this repository. A few come from a GitHub limit or a founder's request. "No mechanism" means a written rule carries the fix and nothing enforces it.

## Conversations

### One memory and one role file per role

- **What happened:** Seven sessions started in the same folder shared one automatic memory, and each role lived only in its own chat.
- **Cause:** Claude Code keys the automatic memory to the folder, and no file recorded the roles.
- **Fix:** The launcher points each role at its own memory folder, and each role has a file that the launcher adds to its prompt.
- **Where:** `bin/founder-mode` (`autoMemoryDirectory`), `templates/roles/`.

### A role resumes its own conversation by id

- **What happened:** A founder resumed a role with `-r` and no id. Claude Code opened its picker, which lists every conversation in the working folder, and several roles shared that folder. The founder resumed another role's conversation while that role was still running, and two processes wrote the same transcript.
- **Cause:** `claude -r` without an id searches the whole folder, and `claude -r <name>` runs the same search. Nothing stopped a second process from opening a conversation already open.
- **Fix:** The launcher keeps each role's conversation id and resumes by id. It takes only a UUID after `-r`, refuses a transcript that another role opened, and refuses a conversation or a session name that a live process holds. A lock covers the seconds before Claude Code registers a new session. The launcher refuses `--from-pr` and `--teleport`, which pick a conversation too, and reads `-r<id>` as `-r <id>`, as `claude` does. Starting `claude` by hand skips all of this, and so do `/resume`, `/teleport` and `/desktop` inside a session.
- **Where:** `bin/founder-mode`, with `state/<role>.session` and `state/<role>.lock` under `$FM_HOME`.

### Find the transcript by id in every project folder

- **What happened:** The launcher rebuilt a transcript's folder name by swapping each `/` in the working folder for `-`. The advisors' folder had a dot in its path, so the launcher never found their transcripts, and resuming a case and the ownership check both failed for them.
- **Cause:** Claude Code turns every character other than a letter or a digit into `-`, dots included.
- **Fix:** The launcher looks for `<id>.jsonl` in every project folder, as `claude --resume <id>` does.
- **Where:** `bin/founder-mode`.

### `/clear` starts a new conversation

- **What happened:** A reviewer cleared a role's conversation with `/clear`, as the org chart suggests between unrelated tasks. The next launch resumed the conversation from before the `/clear`. Later the new conversation hit a usage limit, and `founder-mode stalled` and the coordinator's hook skipped the role.
- **Cause:** `/clear` starts a conversation with a new id inside the running process, and the hooks documentation lists `/branch` as another such start. The launcher wrote the role's conversation pointer only at launch.
- **Fix:** A SessionStart hook on every role writes the running conversation's id into the role's pointer, on start and after `/clear` or `/branch`. It skips a resume: the launcher writes the id it resumes, and `/resume` inside a session can open another role's conversation, which the next launch would then refuse.
- **Where:** `hooks/session-pointer.sh`, `bin/founder-mode`, `tests/smoke.sh`.

### A relaunch resumes the previous conversation

- **What happened:** The coordinator relaunched a role fresh to save quota. The role lost its working context, and the founder wanted it back.
- **Cause:** The coordinator traded the role's context for a small saving: a resumed session costs nothing until it gets a message.
- **Fix:** A plain launch resumes the role's last conversation. Use `--new` only on a founder's order or when the conversation won't open. Restart a session only while it is idle, or it loses any wake-up it scheduled.
- **Where:** `bin/founder-mode`, `templates/roles/coordinator.md`.

### Two sessions under one name

- **What happened:** After a relaunch, the session list still showed a stale remote entry under the same name, and a message sent by name failed.
- **Cause:** Messages travel by session name, and two entries answered to it.
- **Fix:** Send by the short identifier the listing shows. The launcher refuses a second local session under a name in use; a remote entry is out of its reach.
- **Where:** `bin/founder-mode` for local sessions. No mechanism for remote entries.

### Keep plain `claude` out of the role folders

- **What happened:** After the resume mix-up above, the board approved a shell function that stops plain `claude` in the role folders, since a plain `claude` there skips every check.
- **Cause:** The checks live in the launcher, and nothing stops a founder from typing `claude` in a role's folder.
- **Fix:** A shell function in `~/.bashrc` refuses plain `claude` in the role folders and points to the launcher; `command claude` still works.
- **Where:** README (Limits). No mechanism in the launcher.

### Each new folder asks for trust once

- **What happened:** The first launch in each new role folder stopped at Claude Code's trust prompt until a founder answered it, the advisors' folder included.
- **Cause:** Claude Code asks once per folder.
- **Fix:** A founder answers the prompt on the first launch of each role.
- **Where:** README (Quick start). No mechanism.

### The quick start puts `~/.local/bin` on the `PATH`

- **What happened:** On a machine without `~/.local/bin` on its `PATH`, the quick start's first `founder-mode` command failed with "command not found".
- **Cause:** The quick start linked the launcher into `~/.local/bin` and assumed the shell looked there.
- **Fix:** The quick start puts `~/.local/bin` on the `PATH` and says to add it to the shell profile. The smoke test runs the quick start in a clean home folder, with a `PATH` where `founder-mode` isn't found.
- **Where:** README (Quick start), `tests/smoke.sh`.

### The launcher drops a parent session's variables

- **What happened:** The coordinator opened a role in a new terminal from its own shell, clearing a few variables by hand. The role started as the coordinator's child, with the coordinator's session id and message socket. It was missing from the local session list and answered only over Remote Control. An older `claude` refused to start at all in the same spot.
- **Cause:** A child process inherits the session's variables (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, the messaging socket and its token), and a list kept by hand missed some of them.
- **Fix:** The launcher unsets those variables before it starts `claude`, and keeps the founder's own, such as `CLAUDE_CONFIG_DIR`. The dry run shows what it unsets.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

## Prompts and context

### A session hears when the org chart changes

- **What happened:** The coordinator rewrote the org chart and the roles, and the sessions already running kept working from the old text.
- **Cause:** Claude Code fixes a session's prompt when the process starts, and a resumed conversation reuses the prompt it recorded until it compacts.
- **Fix:** A hook tells a session once, on its next prompt, that the org chart or its role file changed after its conversation started.
- **Where:** `hooks/orgchart-notice.sh`.

### Date that notice per conversation

- **What happened:** The first version kept one mark per role and reset it at every launch. A role that resumed an older conversation after an edit never got the notice.
- **Cause:** One role resumes several conversations, and each carries the prompt of its own start.
- **Fix:** One mark per conversation id. The hook dates a new conversation by its launch. The launcher gives a resumed conversation with no mark an old date, so that one hears the notice once.
- **Where:** `hooks/orgchart-notice.sh`, `bin/founder-mode`, `$FM_HOME/state/loaded/`.

### Append the role to Claude Code's prompt

- **What happened:** A test showed that `--agent` replaces Claude Code's own system prompt.
- **Cause:** `--agent` swaps the whole prompt; `--append-system-prompt` adds to it.
- **Fix:** The launcher appends the org chart and the role file.
- **Where:** `bin/founder-mode`.

### Set the compaction window at launch

- **What happened:** Changing the window with `/autocompact` inside a running session didn't hold.
- **Cause:** The launcher's settings outrank it, and the command writes to the global settings that every session reads.
- **Fix:** The window comes from `roles.tsv` through `--autocompact`, and `FM_COMPACT` overrides it for every role. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` outranks the flag, so the launcher clears it (see "A variable in your shell outranks every role's row").
- **Where:** `bin/founder-mode`, `templates/roles.tsv`.

### Keep windows small, above a floor

- **What happened:** The board measured what the compaction window costs. Bigger windows made every request carry more context, and the extra compactions of a smaller window cost little. A session whose window left little room above its fixed prompt compacted in a loop and logged "Autocompact is thrashing".
- **Cause:** Every request re-sends the conversation, and a session idle past the cache's lifetime rewrites its whole context into the cache on its next request. The main conversation's cache lasts an hour on a Claude subscription within its included usage, and five minutes on an API key or usage credits (Claude Code's prompt caching page, checked with 2.1.303).
- **Fix:** 300k tokens for the working roles and 1M for the coordinator and the advisors. Switch a role to a smaller window right after it compacts, or the relaunch compacts it on its first turn. `auto` means the model's full window.
- **Where:** `templates/roles.tsv`, `bin/founder-mode`.

### One session per role

- **What happened:** After a run of usage-limit stops, the board weighed fewer sessions, or one agent with subagents, against the full team.
- **Cause:** The limit counts tokens whatever the number of processes, and every subagent pays the fixed prompt again. One agent doing everything keeps it all in one context: the coordinator, which had pulled too much work into its own conversation, compacted about thirty times.
- **Fix:** Keep one session per role and cut the fixed cost of each request. The coordinator hands topics to their owners.
- **Where:** `templates/roles.tsv`, `templates/roles/coordinator.md`.

### A stop order outlasts a compaction

- **What happened:** During a shutdown, a session told to save and stop compacted twice, went back to its previous task, kept spending and held up the shutdown.
- **Cause:** After a compaction, the session resumes "the last task" from a summary that can leave out a recent order.
- **Fix:** A stop order says it still holds after a compaction. The coordinator reads the transcript of any session still working a few minutes later and closes each one once it has saved.
- **Where:** `templates/ORGCHART.md` (Context), `templates/roles/coordinator.md`.

### What has to survive goes in a file

- **What happened:** A reboot emptied every temporary folder, the sessions' scratch files with it. An order given only in the chat can vanish the same way at a compaction.
- **Cause:** `/tmp` empties on reboot, and a compaction keeps a summary.
- **Fix:** Plans and work in progress go in the deliverable, in the role's memory or in `$FM_HOME/work/<role>/`, which the launcher creates.
- **Where:** `templates/ORGCHART.md` (Context), `bin/founder-mode`.

### A session's scheduled jobs die with it

- **What happened:** After a shutdown, a role had to recreate the jobs it had scheduled inside its session, and the role missed one daily run.
- **Cause:** A job created inside a session lives in that process.
- **Fix:** Anything that has to run every day goes in the system's scheduler, or in the role's memory as a job to recreate after a relaunch.
- **Where:** `templates/ORGCHART.md` (Context). No mechanism.

### Take times from `date`

- **What happened:** The coordinator wrote invented times in its log of a night's work and had to correct them from the transcript.
- **Cause:** A model writes a plausible time when nothing in its context gives the real one.
- **Fix:** Take dates and times from `date`, and attribute a time that another session reports to that session.
- **Where:** `templates/ORGCHART.md` (Context). No mechanism.

## Authority

### Only founders merge, deploy, spend, sign or send

- **What happened:** An agent told to work on its own read that as permission to merge several PRs. Later, a founder's passing "fine" arrived while a PR waited for approval, and the coordinator had to rule that it approved nothing.
- **Cause:** A standing instruction to keep working reads like a blanket permission.
- **Fix:** An approval covers what it names. The org chart lists what only the founders authorize, and the guard blocks the commands that merge.
- **Where:** `templates/ORGCHART.md` (People), `hooks/irreversible-guard.sh`.

### Ask the owner

- **What happened:** A session asked both founders to approve something that belonged to one of them.
- **Cause:** Asking everyone felt safer than finding the owner.
- **Fix:** Each founder decides within their own area, and both decide what binds the company. When you can't tell whose a decision is, ask whose it is.
- **Where:** `templates/ORGCHART.md` (People). No mechanism.

### When the founders are away

- **What happened:** A founder went to bed and asked the sessions to keep working, and to take to the board whatever didn't need a human.
- **Cause:** Without a list, a session can't tell a decision the absence blocks from one it only delays.
- **Fix:** The coordinator keeps moving what the absence doesn't block. Merging to main, deploying, spending, signing, sending anything outside, commenting or reviewing on GitHub and touching the founders' configuration still wait, whatever the board says. A reversible technical decision that blocks work goes to the board.
- **Where:** `templates/roles/coordinator.md`. No mechanism beyond the guard.

### The guard looks for `gh` anywhere in a line

- **What happened:** A session put a wrapper in front of `gh api` and got a write past a guard anchored at the start of the line.
- **Cause:** An anchored pattern sees only the first word of the line.
- **Fix:** The guard matches `gh` and `git` after any character that can't be part of a word.
- **Where:** `hooks/irreversible-guard.sh`.

### The guard covers Monitor

- **What happened:** During a review, a session ran `gh pr merge` through the Monitor tool, which the guard's matcher didn't cover; Bash had blocked the same command.
- **Cause:** Monitor runs shell commands too, and a hook fires only for the tools its matcher names.
- **Fix:** The matcher is `Bash|Monitor`.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

### Grouped short options and shortened long ones

- **What happened:** The guard caught `git push -f` and missed `git push -fu`. Later a reviewer got `git push --del`, `--mirr` and `--force-w` past it.
- **Cause:** git reads `-fu` as `-f -u`, and it accepts any unambiguous abbreviation of a long option.
- **Fix:** The guard treats a short-option group that holds `f` or `d` as a force push or a deletion, and treats any abbreviation of a dangerous long option that git accepts as the option itself.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### Commands split over two lines

- **What happened:** A command split with a backslash at the end of a line went through the guard.
- **Cause:** grep compares one line at a time.
- **Fix:** The guard joins continued lines before it looks.
- **Where:** `hooks/irreversible-guard.sh`.

### Options before the subcommand, and a read list for `gh`

- **What happened:** `gh -R owner/repo pr merge` and `gh pr --repo owner/repo merge` went through, and so did `gh` writes that nobody had listed: a public repository, a secret, a workflow run.
- **Cause:** The guard listed forbidden subcommands and expected each one right after `gh`.
- **Fix:** The guard skips options and quotes, lets through reads, `gh pr create` and local clones, and blocks every other subcommand of a known `gh` command group.
- **Where:** `hooks/irreversible-guard.sh`.

### One command per line

- **What happened:** A reviewer found that `(cd ../wt && git push --force)`, `git push origin main;git status` and `docker compose down -v;docker compose up -d` went through the guard, and so did `git push origin "main"`.
- **Cause:** The patterns ended a word only at a space or at the end of the line, and only the `gh` check dropped quotes.
- **Fix:** The guard splits the command at `;`, `&`, `|`, parentheses, `<`, `>` and backticks, and reads it twice: with quotes dropped, and with each quoted word kept whole, so `git -C "/tmp/my repo" push --force` counts too. Between `git` or `docker` and the subcommand it accepts only options, so a commit message that says "push to main" passes; one that quotes a whole command, such as `git push origin main`, waits (see "The guard reads quoted text and heredocs"). It judges each `gh api` call on its own line, so a GraphQL read doesn't clear a write next to it.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### A command substitution splits a command

- **What happened:** A reviewer found that `git push origin "$(git branch --show-current)" --force-with-lease`, `git -C "$(git rev-parse --show-toplevel)" push origin main` and `docker compose -p "$(basename "$PWD")" down -v` went through the guard, by Bash and by Monitor. With a plain word in place of the substitution, the guard blocked the same commands. Later reviewers put a substitution, and then a variable, where the `gh` subcommand goes (`gh pr $(echo merge) 1`, `gh pr $ACTION 1`), and both passed.
- **Cause:** The guard cut each command at parentheses and backticks to reach the commands nested inside, so it also separated the words after a substitution from their command.
- **Fix:** For a command with `$(...)` or backticks, the guard adds two readings with each substitution turned into one word, innermost first. The other two readings still see the command inside the substitution. The guard holds a `gh` command whose group or subcommand is a variable or a substitution, since it can't tell which command that runs.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### Shell encodings hide a word

- **What happened:** A reviewer got `git push origin $'main'`, `gh pr {merge,} 1` and `gh${IFS}pr${IFS}merge${IFS}1` past the guard.
- **Cause:** The shell turns `$'main'` into `main`, `{merge,}` into `merge` and `${IFS}` into a space, and the guard read the words as written.
- **Fix:** The first reading drops the `$` of `$'...'` and turns `${IFS}` into a space. A brace expansion in place of a `gh` command group or subcommand counts as a substitution. One in a `git` or `docker` command still passes, and README (Limits) says so.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### gh has aliases

- **What happened:** The guard blocked `gh codespace delete` and let `gh cs delete` through, along with `gh agent create`, `gh extensions install` and `gh api ... -fbody=hi`.
- **Cause:** The guard listed command groups by their full names, and pflag takes a value glued to a short flag.
- **Fix:** The guard knows gh's aliases (`cs`, `ext`, `at`, `rs`, `agent`), accepts a plural for any group and blocks `gh copilot`, which runs an agent with the founder's GitHub session. It counts a glued `-f` or `-F` as a field, and it blocks `gh auth status --show-token`, which prints the token. A GraphQL query written inline with no mutation passes as a read.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### A field sent with GET is a read

- **What happened:** The guard blocked `gh api -X GET search/issues -f q=...`, the example that gh's own help gives for a GET with parameters, and a GraphQL read written over several lines. Each time, the session had to ask a founder about a read.
- **Cause:** The guard counted every field as a write, and it read a query that starts on the line after `query=` as a field with no query.
- **Fix:** With `-X GET` and no `--input`, gh sends the fields as query parameters, so the guard lets them through. The guard joins a query that starts on the next line to the line with `query=`.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### A pushed tag publishes a version

- **What happened:** A reviewer pushed tags past the guard: `git push origin --tags`, `--follow-tags`, `refs/tags/v1.2.0` and `tag v1.2.0`. The guard already blocked `gh release create`.
- **Cause:** The guard watched branches and history rewrites, and many release and deploy workflows run on a tag push.
- **Fix:** The guard blocks `--tags`, `--follow-tags`, a `refs/tags/` refspec and `tag <name>`. The guard can't tell a tag pushed by its bare name from a branch, so the server needs a protection rule for tags.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`, README (Limits).

### A gate that can't run lets the call through

- **What happened:** A reviewer timed the guard on long commands. A 100 KB heredoc held each call for 25 seconds, and a command of half a megabyte would outlast the default hook timeout of 600 seconds, after which the call goes ahead unchecked. A send hook that failed to start would have let the send through in the same way.
- **Cause:** Claude Code treats a hook that can't start or times out as a non-blocking error, unless the hook sets `onFailure: "block"`, which needs 2.1.295 or later.
- **Fix:** The launcher sets `onFailure: "block"` on the guard and the one-send hook, and gives the guard a 30-second timeout.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

### Read a long command in one pass

- **What happened:** A reviewer timed the guard: a 100 KB heredoc took 25 seconds, a 213 KB one over two minutes and a 360 KB one almost seven. With that fixed, a 400 KB script with a substitution on every line still took close to two minutes. A later reviewer found that 3,300 `gh api` lines in 134 KB took 34 seconds, past the guard's 30-second timeout. The smoke test had missed it: it timed only a command the guard blocks, and the guard stops at the first reading that blocks one.
- **Cause:** One reading appended each character to a jq array with `reduce`, which copies the array every time. Another replaced the substitutions one at a time, each a pass over the whole command. The `gh` check started a `sed` and a here-string for every line, and the `gh api` check a grep for every test on every line.
- **Fix:** jq's `foreach` emits one character per step, one awk `gsub` pass per nesting level replaces the substitutions, one awk pass reads every `gh` call and every `gh api` call, and another joins the lines split with a backslash, which bash's own substitution did in quadratic time (1.76 MB, 30 seconds). On Linux with bash 5.3, 1 MB took 4 to 7 seconds for plain text, quotes, substitutions, split lines, `gh` calls and `gh api` calls alike. The smoke test times a long command the guard blocks and two it lets through, one of them 3,000 `gh api` reads.
- **Where:** `hooks/irreversible-guard.sh`, `tests/smoke.sh`.

### The guard sees shell commands only

- **What happened:** A reviewer found that member roles kept connectors that share files or create events, and a built-in tool that starts remote agents, all of which act without the guard.
- **Cause:** The guard hooks Bash and Monitor.
- **Fix:** `settings/all.json` denies the mail connectors and `RemoteTrigger` to member roles. Anything else that writes outside goes in that deny list, or member roles stay out of bypass mode.
- **Where:** `templates/settings/all.json`, README (Limits).

### Hooks take their values from their command line

- **What happened:** A reviewer started Claude Code's background service from one shell and moved a session from another shell to the background. That session's hooks ran with the first shell's role, kind and unlock variable, so one key press could leave a role without its guard, or hand it another role's.
- **Cause:** Claude Code restarts a session you move to the background (`/background`, the left-arrow key or `claude --bg`) in a process of the background service, with that service's environment. It keeps only some launch flags: `--settings` is on the documented list, while `--append-system-prompt`, `--tools` and `--restricted` aren't. The hooks read their role, its kind and the unlock from the environment.
- **Fix:** The launcher sets `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` for every role, which turns off `/background`, the left-arrow key and `claude --bg`. It refuses `--environment` and `--tmux`, which run the session elsewhere. Each hook gets its values as arguments in its `--settings` entry. Claude Code runs it without a shell, and it takes none of its values from the environment. `FM_UNLOCK=1` leaves the guard out of the settings. The session id that a hook receives doesn't name the role: `/clear` starts a new one inside the same process.
- **Where:** `bin/founder-mode`, `hooks/`, `tests/smoke.sh`.

### A setting or a variable can switch every hook off

- **What happened:** A reviewer set `disableAllHooks` in the user settings, then `CLAUDE_CODE_SAFE_MODE` or `CLAUDE_CODE_SIMPLE` in the shell. Each one left every role without hooks: a member ran a merge-shaped command the guard should have stopped, and the isolated role with a send grant wrote through a send gate that never ran.
- **Cause:** Claude Code reads the two variables as `--safe-mode` and `--bare`, which the launcher refused, and `disableAllHooks` turns off every hook that settings files define. The launcher passed the shell's environment through and left the user settings in charge of that key.
- **Fix:** The launcher sets `disableAllHooks` to false in `--settings`, which outranks the user, project and local settings but not a managed policy, and starts the session with both variables empty. Tested on 2.1.295 and 2.1.303 with the key in the user settings and both variables set in the shell: the guard and the notice hook ran in a member, and the send gate ran in the isolated role. The launcher warns on stderr when the shell sets either variable or the user settings set the key.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

### A rule marked as enforced binds without its hook

- **What happened:** A session pushed from a clone where the repository's hooks weren't installed. The check it skipped was failing.
- **Cause:** The repository enforced its rules through git hooks installed per clone.
- **Fix:** A rule that a repository marks as enforced binds whether or not its hook runs. One worktree per branch, and never `--no-verify`.
- **Where:** `templates/ORGCHART.md` (Shared rules). No mechanism.

### The guard reads quoted text and heredocs

- **What happened:** A session wrote a file of test cases with `cat <<EOF`, and the guard blocked the whole command because the cases named blocked commands. A reviewer found the same with quoted text: `git commit -m "Block gh pr merge in the guard"`, a `git log --grep` pattern and `gh pr merge --help` all waited for a founder.
- **Cause:** A heredoc's text and quoted text are part of the command the guard reads, and the guard can't tell an argument from a command.
- **Fix:** Write a file that names blocked commands with the Write or Edit tool. A commit message or a search that names a blocked command waits for a founder, and README (Limits) says so.
- **Where:** `hooks/irreversible-guard.sh` (header), README (Limits).

### Read-only means a prompt while the shell stays

- **What happened:** The templates called the advisors and the checker read-only, and both keep Bash, which can commit and push.
- **Cause:** Taking away the edit tools leaves the shell.
- **Fix:** The templates say "read-only by instruction". The guard fires in their sessions and inside subagents, and blocks the commands that publish.
- **Where:** `templates/BOARD.md`, `templates/ORGCHART.md`, `agents/checker.md`, `hooks/irreversible-guard.sh`.

### A sandbox would make advisors read-only, and it needs root

- **What happened:** The board approved read-only advisors through Claude Code's Bash sandbox: shell writes confined to a scratch folder, `allowUnsandboxedCommands: false` and `failIfUnavailable: true`. Nobody applied it, because the machine needed root first.
- **Cause:** On Linux the sandbox needs bubblewrap and socat, and on Ubuntu 24.04 and later an AppArmor profile that lets bubblewrap create user namespaces.
- **Fix:** A founder who installs those can add a `sandbox` section to `settings/advisor.json`, which the launcher merges into the advisors' settings.
- **Where:** `settings/advisor.json` under `$FM_HOME`. No mechanism in the templates.

## Messages between sessions

### Measure before you claim

- **What happened:** The coordinator told a founder that a setting was capped below its configured value, from a hint in the CLI binary, and it was false. In a board case, the advisors corrected two facts in the coordinator's own case file by measuring them.
- **Cause:** A hint or an earlier note felt like a checked fact.
- **Fix:** Every claim carries its source or says "not verified", and a session checks what another session tells it like any other claim.
- **Where:** `templates/ORGCHART.md` (Talking between sessions), `templates/roles/engineering.md`, `agents/checker.md`. No mechanism.

### Ten lines per message

- **What happened:** Sessions wrote long replies and long messages to each other, and the founder watched them spend tokens on nothing.
- **Cause:** A message costs output to write, then sits in the receiver's context, which every request re-sends.
- **Fix:** Ten lines per message. Longer material goes in a file, and the message gives the path.
- **Where:** `templates/ORGCHART.md` (Talking between sessions). No mechanism.

### Check a due delivery in its file

- **What happened:** A session sent two messages that reported success, and the receiver never saw them. The receiver found the work by reading the file and the sender's transcript.
- **Cause:** A send that reports success can still miss the conversation.
- **Fix:** When a delivery is due by a set time, check the file and the sender's session once that time has passed.
- **Where:** `templates/ORGCHART.md` (Talking between sessions). No mechanism.

### Leave idle sessions alone

- **What happened:** The board measured that a session idle for more than an hour rewrote its whole context into the cache on its next request.
- **Cause:** The cache outlives a pause only up to its lifetime (see "Keep windows small, above a floor"), and a message to an idle session starts a turn.
- **Fix:** Message an idle session only when it has work to do. After a usage limit, wake only the sessions stopped on the error.
- **Where:** `templates/roles/coordinator.md`, `bin/stalled.js`.

### The isolated role neither sends nor takes messages

- **What happened:** A reviewer of this repository found that the session reading outside mail could message every live session, and that its template still accepted messages it could no longer receive.
- **Cause:** The isolated role kept `SendMessage` and `ListAgents`, and since Claude Code 2.1.290 a `--restricted` session opens no inbox.
- **Fix:** The isolated role has neither tool and works through files in its folder. When a limit stops it, the coordinator asks a founder to resume it.
- **Where:** `bin/founder-mode`, `templates/roles/outreach.md`, `bin/stalled.js`.

### The isolated role writes no instruction files

- **What happened:** A reviewer showed that the isolated role could write a `CLAUDE.md` in its folder, which sat inside the coordinator's. The coordinator read a log there and followed that file as project instructions. Once the launcher denied `CLAUDE.md`, a later reviewer did the same with `AGENTS.md`, through a session started in a folder above.
- **Cause:** A session that reads a file in a folder of its own tree loads that folder's instructions, and Claude Code reads `AGENTS.md` where a folder has no `CLAUDE.md`. A probe of a folder outside the tree loaded nothing.
- **Fix:** The launcher denies the isolated role every file that Claude Code loads by itself as instructions (`CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, anything under `.claude/`), in any letter case. The launcher holds the rules, so no template edit removes them. The template puts its folder outside the others, and the launcher refuses a layout where an isolated folder holds another role's folder or sits inside one.
- **Where:** `bin/founder-mode`, `templates/roles.tsv`, `tests/smoke.sh`.

### The isolated folder holds none of the launcher's files

- **What happened:** A reviewer put `$FM_HOME` inside the isolated role's folder, and the launcher started both roles. From there the isolated role could rewrite the org chart, the role files and `settings/all.json`, which make up the other sessions' prompts and settings.
- **Cause:** The layout check compared the isolated folder with the other roles' folders only.
- **Fix:** The launcher also refuses an isolated folder that holds `$FM_HOME` or the launcher's own checkout.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

### The isolated role's whole folder is outside text

- **What happened:** A reviewer pointed out that the isolated role could rewrite any file in its folder, `kit/` included, where other roles leave account sheets and legal text and read them back later as their own.
- **Cause:** The rules treated only the role's log as outside text.
- **Fix:** Everything in the isolated role's folder is data, `kit/` included, and whoever puts a file in `kit/` keeps the original outside that folder.
- **Where:** `templates/ORGCHART.md` (Talking between sessions), `templates/roles/finance.md`. No mechanism.

## Usage and cost

### The limit belongs to the account

- **What happened:** The whole team hit the five-hour usage limit three times in about a day and sat stopped for hours in total. One window ran out in under an hour while a session ran several subagents in parallel.
- **Cause:** Every session draws on one account limit.
- **Fix:** Four subagents at once per session at most, heavy sweeps only when the window has room, and the coordinator staggers heavy jobs.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### Pace follows `/usage`

- **What happened:** The coordinator set two homemade caps in one night. Both were wrong: heavy work waited while the real meter sat under a quarter.
- **Cause:** An estimate built from transcripts doesn't weigh tokens the way the plan does, and a founder may use the same account elsewhere.
- **Fix:** Read `/usage` before you hold work back. Past 60% of the five-hour window, heavy jobs wait.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### Keep part of the weekly limit for the founders

- **What happened:** A founder asked the sessions to leave part of the account's weekly limit to the founders, who use the same account themselves.
- **Cause:** The limit belongs to the account, and no rule stopped the sessions before it ran out.
- **Fix:** A founder sets a weekly cap below the account's limit, in a file only a founder edits, and the sessions stop at it until the weekly reset. A hook that blocks at the cap would need a live reading of the meter, and this repo reads the meter only through `/usage`.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### Two teams on one account

- **What happened:** A second team of sessions started on the same account and drew on the same limit.
- **Cause:** The usage limit belongs to the account, whatever the team.
- **Fix:** Both teams follow the same cap, and a coordinator warns the other in one line before a job that could take more than a third of the window. At the end of the week each spends what is left under the founders' weekly cap.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### Close to a reset, start pending work

- **What happened:** The coordinator held work back for the reset, and the end of the window went unused.
- **Cause:** The reset discards whatever is left of a window.
- **Fix:** Close to a reset, start pending work at once, as long as the week stays under the founders' weekly cap. If the limit hits first, the sessions stop for a few minutes and the coordinator wakes them.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### Wake the sessions a limit stopped

- **What happened:** After a limit reset, one session resumed by itself and two others sat stopped for hours.
- **Cause:** Never pinned down. All three processes predated the auto-continue setting, the one that resumed included.
- **Fix:** `founder-mode stalled` lists the sessions stopped on an API error without spending tokens, and the coordinator's hook names the live ones on every prompt.
- **Where:** `bin/stalled.js`, `hooks/orgchart-notice.sh`, `templates/roles/coordinator.md`.

### Most of the cost is context

- **What happened:** A count over every transcript showed that most of the cost went to context, read from and written to the cache. Output was a small share.
- **Cause:** Every request re-sends the conversation, and every prompt carried a large project file and the schemas of every tool.
- **Fix:** Smaller compaction windows, only the plugins and connectors each role uses, and facts sent to the checker.
- **Where:** `templates/roles.tsv`, `bin/founder-mode` (the settings merge), `agents/checker.md`.

### A program does what a program can do

- **What happened:** A role on the strongest model ran the same daily job by hand, and each run cost a turn on that model over its whole context. A founder ruled that anything programmable becomes software, and that sessions are for reasoning and analysis.
- **Cause:** Nothing sent recurring work to a program, so it fell to the session that owned it.
- **Fix:** A recurring job with fixed steps runs from a timer or a script that commits its output and leaves a short status file. The session reads the status and steps in on a failure. Each role lists what it repeats, and the coordinator sets the order to build it.
- **Where:** `templates/ORGCHART.md` (Pace). No mechanism.

### A subagent runs at the session's model and effort

- **What happened:** Sweeps launched from a session on the most expensive model ran on that model. After the sessions sent their sweeps to a cheaper model, the board counted the transcripts and found three in four of those requests still at `max`, the effort of the sessions that launched them.
- **Cause:** A named subagent takes the session's model unless the call or its definition sets `model`, and the session's effort unless one of them sets `effort`; the call's value beats the definition's. A fork always runs at the session's model and effort. `CLAUDE_CODE_EFFORT_LEVEL` beats every one of these. Checked with Claude Code 2.1.303.
- **Fix:** Read-heavy sweeps go to a named subagent called with `model: "sonnet"` and `effort: "high"`, and the checker's definition sets `effort: high`. The launcher clears `CLAUDE_CODE_EFFORT_LEVEL`. Writing stays with the session's own model.
- **Where:** `templates/ORGCHART.md` (Pace), `agents/checker.md`, `bin/founder-mode`.

### A new model or effort costs a resumed conversation

- **What happened:** The board recommended lowering the effort of several roles and checked what the change would cost a conversation already under way.
- **Cause:** The launcher passes each role's model and effort at launch, and a resumed conversation re-sends its whole history. On a new model it re-reads all of it uncached. On a new effort it does the same, except on Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1, which keep the cache on an API key or a Claude subscription (Claude Code's prompt caching page, checked with 2.1.303). On Amazon Bedrock, Google Cloud's Agent Platform or a Claude apps gateway, even those models re-read it uncached.
- **Fix:** Change a role's model, or its effort on a model that loses the cache, with `--new` or right after the role compacts.
- **Where:** `templates/roles.tsv` (header). No mechanism.

### A variable in your shell outranks every role's row

- **What happened:** A reviewer set `CLAUDE_CODE_EFFORT_LEVEL=low` in the shell, and every role, the checker and a subagent called with `effort: "high"` ran at `low`. The same variable in the user settings did the same, and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` overrode each role's window.
- **Cause:** Claude Code ranks `CLAUDE_CODE_EFFORT_LEVEL` above `--effort`, an agent's `effort` and the call's, and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` above `--autocompact`. Its documentation recommends `CLAUDE_CODE_EFFORT_LEVEL` for keeping `max` in every session.
- **Fix:** The launcher's `--settings` sets both to an empty string, which overrides the value from the shell or the user settings (checked with 2.1.295 and 2.1.303). When the shell sets either, the launcher prints a warning on stderr.
- **Where:** `bin/founder-mode`, `tests/smoke.sh`.

### The checker carries its rules in the prompt

- **What happened:** On its first request, a checker without CLAUDE.md wrote about a thirteenth of the cache that a general-purpose agent wrote, and it couldn't see the project's rules.
- **Cause:** `omitClaudeMd` drops the project file and its cost together, and the checker loads a short list of tools.
- **Fix:** Facts go to the checker, and each delegation states the rules the check depends on.
- **Where:** `agents/checker.md`, `templates/ORGCHART.md` (Pace).

### A new agent file waits for a restart

- **What happened:** A session already running answered "Agent type not found" for a checker added after it started.
- **Cause:** That version of Claude Code loaded agent definitions when the session started.
- **Fix:** Restart the sessions that need a new agent.
- **Where:** No mechanism.

### Transcripts undercount output

- **What happened:** The board's cost scripts undercounted the output of the windows that hit the limit.
- **Cause:** A transcript records no usage for the call that writes a compaction summary.
- **Fix:** Count that call from its text when you measure, and read `/usage` for the state of the account.
- **Where:** No mechanism.

### Count each request once

- **What happened:** A first count of subagent requests by effort, built from the transcripts, counted many requests more than once.
- **Cause:** Claude Code writes one API response as several transcript entries, one per content block, and each carries the same message id, request id and usage. Checked on transcripts of Claude Code 2.1.303.
- **Fix:** Deduplicate by message id and request id before you add up requests or tokens.
- **Where:** No mechanism.

### Long unattended runs

- **What happened:** On a night with every session working, the weekly limit rose about five points every twenty minutes, and the machine ran out of memory with many sessions open and a test suite running.
- **Cause:** Every session spends from one weekly limit and holds memory on the machine.
- **Fix:** Before a long run, assign only what the founders asked for and set the cap at the start. Close sessions once they report done, and run test suites with fewer workers.
- **Where:** `templates/roles/coordinator.md`. No mechanism.

### Per-role settings travel with the launch

- **What happened:** A plugin that compresses replies kept its mode in one global file, so one session's startup could switch it off for every session. The board also worried that the same mode would cut documents written for outside readers.
- **Cause:** One shared setting applied to every session, and to chat and deliverables alike.
- **Fix:** The launcher passes per-role settings, plugins included, in one `--settings` value, and nothing goes in a global file. Compressed output stays in chat and messages.
- **Where:** `bin/founder-mode`, `templates/settings/`. No mechanism for the prose rule.

## Git and CI

### One topic, one branch, one open PR

- **What happened:** A session stacked more than a dozen PRs that carried the same change, and every push ran CI.
- **Cause:** The session opened a branch and a PR per subtask and pushed every commit.
- **Fix:** One topic per branch, one open PR per session and repository, one push per batch, and no loose commits to an open PR.
- **Where:** `templates/ORGCHART.md` (Shared rules). No mechanism.

### Batch GitHub calls

- **What happened:** A session made one `gh` call per branch to audit two dozen branches, and every reply landed whole in its context. Another passed long text with `--body`, the shell expanded its backticks, and a broken comment went out.
- **Cause:** Calls in a loop, output nobody trimmed, and shell expansion inside an argument.
- **Fix:** Local git before the API, `--json` with `--jq` to pick fields, never `gh` in a loop, and `--body-file` for long text.
- **Where:** `templates/ORGCHART.md` (Shared rules). No mechanism.

### Run CI once per push

- **What happened:** Each push to a PR branch ran CI twice.
- **Cause:** The workflow triggered on both `push` and `pull_request`.
- **Fix:** Trigger each workflow once per change.
- **Where:** No mechanism; it lives in each repository's workflow files.

### A hook's test can break every worktree

- **What happened:** A test that the repository's pre-push hook ran inherited `GIT_DIR`, wrote `core.bare=true` and a fake user into the shared git config, and broke git in every worktree for a minute.
- **Cause:** git exports `GIT_DIR` to hooks, and every worktree shares one config file.
- **Fix:** The pre-push hook unsets `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` before it runs checks, and a check of `core.bare` and `[user]` catches the damage.
- **Where:** No mechanism; it lives in each repository's hooks.

### Every PR goes in a log

- **What happened:** All sessions pushed under one GitHub account, and GitHub couldn't tell which session had opened which PR.
- **Cause:** One account for every session.
- **Fix:** Whoever opens or closes a PR updates the PR log.
- **Where:** `templates/PR.md`, `templates/ORGCHART.md` (Shared rules).

### Remove a merged worktree right away

- **What happened:** The disk filled up with the worktrees of merged branches.
- **Cause:** Every branch had its own worktree, and nobody removed them after the merge.
- **Fix:** The coordinator removes a worktree once its branch is merged, without `--force`, after `git status --porcelain --ignored`. An ignored `.env` doesn't show in plain status and would go with the worktree.
- **Where:** `templates/ORGCHART.md` (Shared rules), `hooks/irreversible-guard.sh`.

### Search every live branch before you trim worktrees

- **What happened:** The coordinator cut a large folder out of the worktrees to save disk, and the checks broke on branches that still read files from it.
- **Cause:** The coordinator searched for references on the main branch alone.
- **Fix:** Before you exclude files from worktrees, search every live branch for references to them.
- **Where:** `templates/ORGCHART.md` (Shared rules). No mechanism.

## The board

### Keep every vote out of the case folder until the round closes

- **What happened:** In one case the advisors saw the coordinator's vote before they voted, because the case file cited a memory note where the coordinator had written it. In the same case, the coordinator filed each vote in the case folder as it arrived, where the other advisor could read it.
- **Cause:** Votes sat where the other members would look: in the case folder, and in a note the case file cited. Advisors can read the whole disk.
- **Fix:** Until the round closes, no vote goes in the case folder or in any file the case file cites. The coordinator keeps its own vote elsewhere, puts its sha256 in the case file and files the three votes together.
- **Where:** `templates/BOARD.md` (Procedure), `templates/roles/coordinator.md`.

### A vote for a founder's judgment ends the rounds

- **What happened:** In one case two members voted that the question needed a founder's judgment, and another round could not have changed what reached the founder.
- **Cause:** The procedure had no exit for a question the board shouldn't decide.
- **Fix:** When a member votes that the question needs a founder's judgment, the case goes to a founder with the positions, without more rounds.
- **Where:** `templates/BOARD.md` (Procedure).

### Quote what the advisors can't reach

- **What happened:** The advisors couldn't read the founders' decision list, which lived in a web service.
- **Cause:** The advisors had no tool that could open it, and in this launcher they lose every MCP tool.
- **Fix:** The case file quotes whatever the advisors need from a connector.
- **Where:** `templates/BOARD.md` (Procedure).

### Check who proposed

- **What happened:** A case file named the coordinator as the author of a proposal that another session had made.
- **Cause:** The coordinator wrote the attribution from memory.
- **Fix:** Check the record of who proposed each option before the case file names anyone.
- **Where:** `templates/BOARD.md` (Procedure).

### A case can use a seventh of a window in half an hour

- **What happened:** Two advisors on the strongest model used about a seventh of a five-hour window in half an hour, and one of them read dozens of transcripts.
- **Cause:** Advisors check facts at the source, at full effort.
- **Fix:** Only decisions worth that cost go to the board. A small decision that its owner can undo stays with the owner.
- **Where:** `templates/BOARD.md` (What comes to the board).

## Sending

### A one-time send grant

- **What happened:** A founder wanted one email sent from the isolated session without giving it a send tool for good.
- **Cause:** The isolated role only drafts, by design.
- **Fix:** `FM_ONE_SEND` and `FM_SEND_TOOL` at launch approve one tool, and a hook lets one call through, to one address. Each launch gets its own grant id, and the first call the hook allows uses that grant up.
- **Where:** `bin/founder-mode`, `hooks/one-send.sh`.

### Count every address

- **What happened:** The one-send hook read "a@x, B <b@y>" in one recipient field as one address and let a call with two recipients through.
- **Cause:** The hook cut each field down to one address with a greedy pattern, and it looked only at fields with known names.
- **Fix:** The hook collects every address in the call outside the subject and the body, whatever the field is called, and refuses the call unless the granted address is the only one.
- **Where:** `hooks/one-send.sh`, `tests/smoke.sh`.

### A draft id sends whatever the draft holds

- **What happened:** A reviewer read the schema of the mail connector's send tool: given a draft id, it ignores the recipients in the call and sends the draft as it is. The hook let `{"to": [<granted>], "draftId": ...}` through, and the role may create drafts.
- **Cause:** The hook counted addresses and ignored every other field.
- **Fix:** The call may set only `to`, `cc`, `bcc`, `subject` and the body, so the hook refuses a draft id, a reply-all switch and a line break in a header field.
- **Where:** `hooks/one-send.sh`, `tests/smoke.sh`.

### A grant fixes the text as well as the address

- **What happened:** A reviewer pointed out that the one-send grant fixed the recipient and left the subject and the body to the session, which reads hostile mail in the same conversation.
- **Cause:** The hook compared addresses only, after a founder had reviewed a draft.
- **Fix:** The grant names a file with the approved subject and body. The launcher copies it outside the role's folder, and the hook refuses a call whose subject or body differs, or that carries an HTML body.
- **Where:** `bin/founder-mode`, `hooks/one-send.sh`, `tests/smoke.sh`.

### Line endings don't count in the approved text

- **What happened:** A reviewer saved the approved text with Windows line endings. No call could match it, and the hook's refusal named the subject or the body.
- **Cause:** The hook compared the call's subject with the file's first line, carriage return included, and it refuses a carriage return in a call's subject as a line break.
- **Fix:** The hook drops the carriage return at the end of each line, in the approved text and in the call's body, before it compares them.
- **Where:** `hooks/one-send.sh`, `tests/smoke.sh`.
