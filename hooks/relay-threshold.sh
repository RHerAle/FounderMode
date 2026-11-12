#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# Part of Founder Mode: https://github.com/RHerAle/FounderMode
# UserPromptSubmit hook of the relay pilot. When the context of the last answer in the transcript passes the role's
# threshold, it tells the session to write its relay (templates/relay.md) once it closes the topic. Mid-task it only
# warns, and it never blocks: compaction stays as the safety net.
# Arguments: FM_HOME, the role and the threshold in tokens, from the role's row in relay.tsv, which the launcher writes
# into this hook's entry in --settings. Without them the hook does nothing.
set -uo pipefail
[ $# = 3 ] && [[ $3 =~ ^[0-9]+$ ]] || exit 0
exec node -e '
const fs = require("node:fs");
const [home, role, limit] = process.argv.slice(1);
let e;
try { e = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }
const p = e.transcript_path || "";
let size;
try { size = fs.statSync(p).size; } catch { process.exit(0); }
// The tail is enough: the last answer with a usage block sits near the end, and a transcript can reach hundreds of MB.
const n = Math.min(size, 1500000), buf = Buffer.alloc(n), fd = fs.openSync(p, "r");
fs.readSync(fd, buf, 0, n, size - n); fs.closeSync(fd);
let ctx = 0;
for (const l of buf.toString("utf8").split("\n").reverse()) {
  if (!l.includes("\"usage\"")) continue;
  let u;
  try { u = JSON.parse(l).message.usage; } catch { continue; }
  if (!u) continue;
  ctx = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
  break;
}
if (ctx <= Number(limit)) process.exit(0);
const m = `Relay pilot: your context is about ${Math.round(ctx / 1000)}k tokens, past ${Math.round(limit / 1000)}k. ` +
  "Finish the task in progress. When you close the topic, write your relay from " + `${home}/relay.md into ${home}/work/${role}/relay/ ` +
  "and send its path to the Coordinator, who relaunches you with --new.";
console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: m } }));
' "$@"
