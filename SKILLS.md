# Skills and tools

Founder Mode installs none of these. Each entry links the repository at the commit we read and gives the licence from that commit's licence file. Decide what you want, then ask Claude to install it where the entry says. Read a licence before you ship anything built with the skill.

**Every role needs stop-slop.** The org chart sends every text that leaves the company through it.

## Where things go

- **Every role:** `~/.claude/skills/<name>/`. Every session on your account loads it.
- **Design only:** `$FM_HOME/plugins/design/skills/<name>/`, next to a minimal plugin file at `$FM_HOME/plugins/design/.claude-plugin/plugin.json`:

  ```json
  {"name": "design"}
  ```

  When that file exists, the launcher passes the folder to the Design role with `--plugin-dir`, and to no other role, so the design skills stay out of every other session's context. A skill inside a plugin carries the plugin's name as a prefix, as in `design:logo-design`. A session already running loads a new skill only after a relaunch.

To install a pinned skill, copy the folder the link points to, at that commit, together with the repository's licence file.

## Skills for every role

| Skill | What it's for | Pinned source | Licence |
|---|---|---|---|
| stop-slop | Every text that leaves the company: web copy, documents, emails, commits | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop/tree/8da1f030185bdfe8471220585162991eaeb970e9) | MIT |
| paper-lookup | Finding papers and DOIs with a traceable source | [K-Dense-AI/scientific-agent-skills, skills/paper-lookup](https://github.com/K-Dense-AI/scientific-agent-skills/tree/5f2bc0341354fd5590aef76a533ada1e1e5b4e62/skills/paper-lookup) | MIT (`LICENSE.md`) |
| peer-review | Reviewing a paper before it goes out | [K-Dense-AI/scientific-agent-skills, skills/peer-review](https://github.com/K-Dense-AI/scientific-agent-skills/tree/5f2bc0341354fd5590aef76a533ada1e1e5b4e62/skills/peer-review) | MIT (`LICENSE.md`) |
| loop, claude-api, update-config, artifact-design | Paced rounds, model facts, hooks and settings, pages published as artifacts | Built into Claude Code | Nothing to install |

## Skills for Design

| Skill | What it's for | Pinned source | Licence |
|---|---|---|---|
| frontend-design | Visual direction: character, type and the clichés to avoid | [anthropics/skills, skills/frontend-design](https://github.com/anthropics/skills/tree/dbd4588f9e1033efb41dad4bef2f7947c8993d44/skills/frontend-design) | Apache-2.0 (`LICENSE.txt` in the skill folder) |
| web-design-guidelines | Auditing a page against interface guidelines | [vercel-labs/agent-skills, skills/web-design-guidelines](https://github.com/vercel-labs/agent-skills/tree/1a2c79d4e6c4a2283dc2c614b6538cbe1ed5ca62/skills/web-design-guidelines) | No licence file: ask the author before you copy it |
| mobile-android-design | Material 3 principles, with Compose examples | [wshobson/agents, plugins/ui-design/skills/mobile-android-design](https://github.com/wshobson/agents/tree/0874a27b17a22e2b7c2e2bcd725768e0803cad06/plugins/ui-design/skills/mobile-android-design) | MIT |
| mobile-ios-design | Apple's interface guidelines and SwiftUI | [wshobson/agents, plugins/ui-design/skills/mobile-ios-design](https://github.com/wshobson/agents/tree/0874a27b17a22e2b7c2e2bcd725768e0803cad06/plugins/ui-design/skills/mobile-ios-design) | MIT |
| ui-ux-pro-max | Searchable data on styles, palettes, type and stacks | [nextlevelbuilder/ui-ux-pro-max-skill, .claude/skills/ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/tree/d14efff8ed1faa4187f004f79926f428c8074ec7/.claude/skills/ui-ux-pro-max) | MIT |
| huashu-design | Facts before design, real variants, critique and verification guides | [alchaincyf/huashu-design](https://github.com/alchaincyf/huashu-design/tree/0830494ecb1c117e25b313a8114fe55a6bf2b125) | MIT |
| brand-discovery | A brand brief: purpose, positioning, audience, voice | [affaan-m/ecc, skills/brand-discovery](https://github.com/affaan-m/ecc/tree/ef648e01899ba3e8dc6371642deaaf64b4477775/skills/brand-discovery) | MIT |
| logo-semantic-fusion | A logo concept that fuses two meanings into one shape | [ZSeven-W/craft-skills, skills/logo-semantic-fusion](https://github.com/ZSeven-W/craft-skills/tree/01c8ffe0bc94cfe1dbfc7e1de537399253d04f39/skills/logo-semantic-fusion) | Apache-2.0, with `THIRD_PARTY_NOTICES.md` |
| logo-design | Logo work from a brief to vector files, with test sheets and an SVG audit | [kaankiziltug/logo-design-skill, skills/logo-design](https://github.com/kaankiziltug/logo-design-skill/tree/0ecf52e9a4b3ac92b714f7cc6e3148ab8c774134/skills/logo-design) | MIT; read `TRADEMARKS.md` |
| logo library | 1,432 logos of other companies, for study and for checking that a new mark doesn't look like a known one | [logo-design, assets/library](https://github.com/kaankiziltug/logo-design-skill/tree/0ecf52e9a4b3ac92b714f7cc6e3148ab8c774134/skills/logo-design/assets/library) | Each logo is its owner's trademark (`TRADEMARKS.md`). Study only: never copy one into a repository or a deliverable. A check against it is no trademark search |

Notes for the copy:

- **ui-ux-pro-max:** its `SKILL.md` calls its search script through `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max`. Inside the Design plugin, change that to `${CLAUDE_PLUGIN_ROOT}/skills/ui-ux-pro-max`.
- **huashu-design:** copy `SKILL.md`, `LICENSE` and `references/`. We haven't reviewed its scripts.
- **The logo library** is about 1,400 SVG files: fetch the repository once as a tarball (`https://codeload.github.com/<owner>/<repo>/tar.gz/<commit>`) and copy the folders you need. One request per file takes several minutes.

## Fonts, icons and tools for Design

| What | Version | Licence | Where |
|---|---|---|---|
| OFL fonts from [google/fonts](https://github.com/google/fonts/tree/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl): Inter, Atkinson Hyperlegible Next, Manrope, Space Grotesk, IBM Plex Sans, Archivo, Saira, Oswald, Bricolage Grotesque, Outfit, Sora, DM Sans, Figtree, Geist, Geist Mono, JetBrains Mono, Overpass, Public Sans, Roboto Flex, Big Shoulders Display, Barlow, Barlow Condensed, Barlow Semi Condensed | Commit e7db6ca | OFL-1.1, in each family's `OFL.txt` | `~/.local/share/fonts/`, each family with its `OFL.txt` |
| [Material Symbols](https://www.npmjs.com/package/@material-symbols/svg-400) | `@material-symbols/svg-400@0.48.1` | Apache-2.0 (npm registry) | `npm i --prefix $FM_HOME/plugins/design/icons` |
| [Phosphor](https://www.npmjs.com/package/@phosphor-icons/core) | `@phosphor-icons/core@2.1.1` | MIT (npm registry) | `npm i --prefix $FM_HOME/plugins/design/icons` |
| [svgo](https://www.npmjs.com/package/svgo) | `svgo@4.1.0` | MIT (npm registry) | `npm i --prefix $FM_HOME/plugins/design/tools` |
| [svg2vectordrawable](https://www.npmjs.com/package/svg2vectordrawable) | `svg2vectordrawable@2.9.1` | MIT (npm registry) | `npm i --prefix $FM_HOME/plugins/design/tools` |
| [Playwright](https://www.npmjs.com/package/playwright), with its headless Chromium | `playwright@1.64.1` | Apache-2.0 (npm registry) | `npm i --prefix $FM_HOME/plugins/design/tools`, then `npx playwright install --only-shell chromium` from that folder |

System packages, for vector logo work (Debian and Ubuntu names, installed with root): `librsvg2-bin` (rsvg-convert), `potrace`, `imagemagick`, `python3-pil`, `python3-fonttools` and `python3-cairosvg`. Each package's licence is in `/usr/share/doc/<package>/copyright`; we didn't read them.

## Plugins

Two plugins run in every session without being called, so a count of skill calls misses them.

| Plugin | What it's for | Pinned source | Licence | Install |
|---|---|---|---|---|
| caveman | Keeps chat between sessions short | [juliusbrussee/caveman](https://github.com/juliusbrussee/caveman/tree/9b68f7ed12b05e7efaff18e65c5a3fc2849fd0a4) | Apache-2.0 (`LICENSE`; the repository also ships a `LICENSE-MIT`) | `/plugin marketplace add juliusbrussee/caveman`, then `/plugin install caveman@caveman` |
| ponytail | Pushes for the smallest change that works | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail/tree/09c434ab73ca43761c5d8b0c5d341926c2fba710) | MIT | `/plugin marketplace add DietrichGebert/ponytail`, then `/plugin install ponytail@ponytail` |

The install commands fetch the repository as it is when you run them, not the commit linked here: compare the two before you install.
