# Cloud design session

A setup script for a Claude Code cloud environment (Claude Code on the web) that redesigns an app's interface, brand and logo while nobody watches. The session gets design skills pinned by commit, fonts and icons with known licences, tools to build a vector logo, a browser for screenshots, and git guards that keep AI attribution out of the history and pushes away from the main branch. An optional block adds a JDK, the Android SDK, Robolectric and a warm Gradle cache.

The cloud VM differs from a laptop in what settings files it reads, a proxy that wants credentials Java can't send, a five-minute budget for the cache and a 64 KB box for the script. [LESSONS.md](../../LESSONS.md#cloud-sessions) has each one.

## What the script sets up

`setup.sh` writes `/usr/local/bin/design-env` and runs `design-env install`. Each step adds a line to `~/design-env/status.txt`, the slow ones also keep a log in `~/design-env/`, and the script exits 0 whatever fails.

| Step | What it leaves |
|---|---|
| `docs` | The session's rules in `~/.claude/CLAUDE.md` and the brief in `~/.claude/briefs/redesign.md` |
| `guards` | Git identity, and the commit-msg and pre-push hooks in `~/.githooks` |
| `repo` | The clone's `.claude/settings.json`, kept out of git, with attribution off and a PreToolUse hook |
| `apt` | rsvg-convert, potrace, ImageMagick, Pillow, fontTools and cairosvg |
| `node` | svgo, svg2vectordrawable (`s2v`) and Playwright, at fixed versions |
| `browser` | Playwright's headless Chromium |
| `skills` | Nine skills for design and copy, each pinned by commit and copied with its licence file, and a provenance list in `~/.claude/skills/PROVENANCE.md` |
| `fonts` | 23 OFL families from the Google Fonts repository at a fixed commit, each with its `OFL.txt` |
| `icons` | Material Symbols (Apache-2.0) and Phosphor (MIT) from npm |
| `android`, `robolectric`, `gradle` | With `ANDROID=1`: the JDK, the SDK platform and build-tools with their sha1 checked, Robolectric's android-all jars with their sha512 checked, and the Gradle cache warmed with the time left. It also accepts the Android SDK licence on your behalf, as `sdkmanager --licenses` would, so read that licence before you set `ANDROID=1` |

The skills:

| Skill | Source | Licence |
|---|---|---|
| frontend-design | anthropics/skills | Apache-2.0 |
| mobile-android-design, mobile-ios-design | wshobson/agents | MIT |
| ui-ux-pro-max | nextlevelbuilder/ui-ux-pro-max-skill | MIT |
| huashu-design (guides only) | alchaincyf/huashu-design | see its LICENSE |
| stop-slop | hardikpandya/stop-slop | see its LICENSE |
| brand-discovery | affaan-m/ecc | see its LICENSE |
| logo-semantic-fusion | ZSeven-W/craft-skills | see its LICENSE and THIRD_PARTY_NOTICES |
| logo-design, with its reference library | kaankiziltug/logo-design-skill | see its LICENSE and TRADEMARKS |

Read each licence before you sell anything built with a skill; the script copies the files and decides nothing for you. The logo-design library holds about 1,400 logos of other companies. The session's rules keep it for study and keep it out of your repository, and a match against it is no trademark search.

We left out a review skill that fetches its rules from an unpinned branch on every use, and the design skills whose scripts download images or call image generators.

`design-env` also has these commands:

- `doctor` lists what is there and what is missing, with the command that fixes each gap;
- `install <step>` reruns one step;
- `relay` starts the local proxy relay and prints the `JAVA_TOOL_OPTIONS` for a JVM;
- `gradle <tasks>` runs `./gradlew` with the JDK, the SDK and the relay;
- `robolectric <version>` fetches one more android-all jar;
- `check` runs the pre-push check by hand;
- `hook` is the PreToolUse guard, called from the clone's settings.

## Setting it up

1. **Edit the block** at the top of `setup.sh`: the repository, the git name, your GitHub noreply address, the branch the session pushes, the base branch, and `ANDROID=1` if you want the Android block. Its values are an example for AGP 8.2 and compileSdk 34. The setup script runs before the environment's variables exist, so these settings can't live there. While `GIT_EMAIL` is empty, the pre-push hook refuses every push.
2. **Replace the brief.** The script writes the text between `<<'BRIEF'` and `BRIEF` to the VM. [BRIEF.md](BRIEF.md) holds the same template: fill in the placeholders in both, or paste your own brief into the script. `tests/smoke.sh` fails when the two differ.
3. **Create the environment.** At claude.ai/code, open the environment selector under the message box and add an environment.
4. **Network access:** Custom. Tick the option that adds the default list of package managers and add, one per line:
   ```
   cdn.playwright.dev
   playwright.download.prss.microsoft.com
   dl.google.com
   ```
   The first two serve Playwright's browser, and the default list has neither. `dl.google.com` serves the Android SDK and is needed only with `ANDROID=1`. Add the sites your session should read for reference, such as a platform's design guidelines. GitHub, npm, PyPI, Maven Central and raw.githubusercontent.com are on the default list.
5. **Environment variables**, for example:
   ```
   ANTHROPIC_MODEL=opus
   CLAUDE_CODE_EFFORT_LEVEL=max
   ```
   The `effortLevel` setting doesn't accept `max`, and the variable does. With the Android block, add `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` and `ANDROID_HOME=/opt/android-sdk`. Anyone who uses the environment can read these values, so no secrets.
6. **Setup script:** "Choose file" and pick your edited `setup.sh`.
7. **Start a session** on your repository, in a permission mode that doesn't wait for approval (we used Auto): a session that asks before every Bash command stalls when nobody is watching. A first message that works:
   ```
   Read ~/.claude/briefs/redesign.md and do all of it on the branch design/redesign. Start with design-env doctor.
   ```

The first session waits for the script, three minutes or so. If the script ends within about five minutes, the cloud keeps a snapshot of the disk and later sessions start from it without running the script again. Changing the script or the allowed domains rebuilds the snapshot.

When the run ends, the session leaves the branch, a PR title and a description in its last message. You open the PR yourself.

## What was tested, and what wasn't

The script in this folder is a generalized copy, and **this version has not been run**. On 25 October 2026 we ran the original it came from, written for one private app, in Docker: Ubuntu 24.04, no direct route to the internet, and all traffic through a proxy that asked for a user and a password, as the cloud's does.

- **Install:** the twelve steps of the original passed in 168 seconds, within the cache budget.
- **A session on a second container started from that state:** `doctor` came back clean. The app's unit tests, its Robolectric test and a debug build passed through the relay, and no credential appeared in Gradle's files. Playwright took a screenshot, and rsvg-convert, `s2v`, logo-design's `svg_audit.py` and `search_library.py` ran. The commit-msg hook stripped the attribution lines, the pre-push check refused a push to main, and the PreToolUse hook denied `--no-verify`, a `gh api -X POST` and an edit to a guard.
- **ui-ux-pro-max's `search.py` failed** in that run, with `No module named 'core'`. Python's `-I` flag keeps the script's own folder off the import path, and the rules now call it without `-I`. Not rerun.

What changed in the generalization and hasn't run since: the settings block and the config file, English messages, finding the clone by the repository's name, the guard's base branch taken from the settings, the Android steps behind `ANDROID=1` and its values read from the settings, and the rules and brief rewritten without the original project. `bash -n` passes on the script and on the `design-env` it writes. That is the whole check so far.

Not checked in a real cloud session, each for a reason:

- **That the cloud loads skills from `~/.claude/skills/`.** The documentation promises a repository's `.claude/skills/` and the skills enabled on your claude.ai account, and says nothing about files a setup script writes. The rules list the skills by path, so the session can read them either way, and `/skills` in the first session settles it.
- **That the clone's `.claude/settings.json` loads.** The documentation says a session with one repository reads it. The rules make the session test the hook with `true --no-verify` before it starts work.
- **How the cloud's proxy behaves.** What we know comes from public issues in anthropics/claude-code (#11791, #13372, #16222), not from the documentation: credentials in `HTTPS_PROXY` that change per session, and Google's domains in `no_proxy`. Our proxy in Docker only imitated that.
- **Whether that proxy inspects TLS with its own certificate authority.** One issue (#13372) reports curl working where Java couldn't verify certificates. If that happens, Gradle fails on certificates, and `doctor` and `~/design-env/gradle.log` show it.
- **iOS.** The cloud has no Mac, so the brief asks for HTML mock-ups of a second platform and forbids claiming a build nobody saw.
