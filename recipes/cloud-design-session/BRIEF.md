# Brief: full redesign of <APP> (interface, brand and logo)

<OWNER>, <DATE>. Do all of it without stopping to ask: nobody will supervise the run. Where there are options, decide with the method under "How you decide" and write down why.

## What the owner wants
<One paragraph: the experience you want and what you dislike today.> The current interface and its design notes are the starting point, not the norm. You may drop any earlier decision, with reasons.

## What doesn't change
- No feature is lost. Before you start, list every screen and action; when you finish, check that everything that existed is still reachable. <The features that must survive, by name.>
- <The screen or element that stays at the centre of the app.>
- Logic changes only where the interface needs it, and the existing tests keep passing.
- The version, signing, minification and release configuration stay as they are, and so do the build tools' versions.
- The logo is vector, and you build it yourself in SVG, without image generators.
- The rules in `~/.claude/CLAUDE.md` are binding.

## For whom and where
<Who uses the app and in what conditions: place, light, posture, attention, battery, coverage. What they read at a glance.>

## Order of work
0. **Facts.** Read the interface code, build, run the tests and take baseline screenshots of every screen. In `design/FACTS.md`, the inventory and, for each screen, what it does, what it shows and its measured problems (contrast, sizes, hierarchy, copy). `design/PROGRESS.md` holds the state: update it when you close each step.
1. **Brand.** A brand brief with the structure of brand-discovery, drawn from the repository and from use. The logo, with logo-semantic-fusion and logo-design: 8 to 12 one-line ideas, the best three drawn in SVG, tests at 16 px, in one colour, inverted, blurred and on a shelf with other apps' icons, and a scored critique. Finish the winner: the app icon for each platform, the splash screen and the wordmark. Concepts, versions and decisions about the app's own mark go to `design/brand/`, dated. Shelf sheets carry other brands' icons, so they stay out of the repository, in `~/shelf/`.
2. **Design system.** Colour (light and dark, plus a high-contrast mode if the screenshots call for one), type with tabular figures, spacing, shapes, elevation, and motion that respects the system setting to reduce animation. Write it as platform resources and document it in a new `DESIGN.md`.
3. **Screens.** For the three main screens, at least two real, rendered directions. Keep the best and carry it to every screen, dialog and state: empty, loading, error and offline <and the app's own states>. Accessibility: touch targets of 48 dp (44 pt) or more, contrast of 4.5:1 (7:1 for the figures read at a glance), screen-reader labels, and text at 130 % without clipping.
4. **Verification.** Screenshots of every screen in light and dark, at two phone widths and with text at 130 %. Look at all of them, fix what you find and repeat until you find nothing. Before-and-after contact sheets go in `design/screenshots/`, few and optimised.
5. **Second platform** (optional). The same system for <OTHER PLATFORM>, with HTML mock-ups captured in Chromium when the VM can't build it. Don't say it builds unless you saw it build.
6. **Close.** Push the branch and send a final message with the summary, the key screenshots sent with SendUserFile, what you couldn't check, and the PR title and description.

## How you decide
For each important choice, at least two real, rendered options. Score each from 1 to 10 on <the conditions of real use>, reading at a glance, fit with the brand and execution, with huashu-design's `critique-guide.md`. The highest score wins unless it breaks a constraint. The table goes to `design/decisions.md`, dated, and each discarded option stays documented with its screenshot. Keep the logo's finalists too: if the owner registers it one day, they choose among them.

## When you stop
When steps 0 to 6 are done. Also when two verification rounds in a row improve nothing, or when something blocks you twice (network, tools): write it down and close with what you have. No endless loops: the cloud credit is shared with other work.

## Pace
Small commits in step order, and a push when you close each step, so no work is lost. In the final report, say which commits belong to each step. After a compaction, read this brief and `design/PROGRESS.md` again.
