#!/usr/bin/env bash
# Copyright 2026 RHerAle
# SPDX-License-Identifier: Apache-2.0
# SessionStart hook. /clear and /branch start a new conversation inside a running session, and the launcher writes
# the role's conversation pointer (state/<role>.session) only at launch. Without this hook the next launch would
# resume the conversation from before the /clear, and founder-mode stalled would watch it instead of the live one.
# On a start, a clear, a compaction or a fork, it points the role at the conversation now running. It skips a resume:
# the launcher already wrote the id it resumes, and /resume inside a session can open another role's conversation,
# which this hook would then record as the role's own.
# Arguments: FM_HOME and the role, which the launcher writes into this hook's entry in --settings. Without them the
# hook does nothing. It prints nothing, since Claude reads a SessionStart hook's stdout as context, and it never
# blocks.
set -uo pipefail
[ $# = 2 ] || exit 0
[[ $2 =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
IFS=$'\t' read -r sid src < <(jq -r '[.session_id // "", .source // ""] | @tsv' 2>/dev/null)
[ "${src:-}" = resume ] && exit 0
[[ ${sid:-} =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 0
f=$1/state/$2.session
# A rename replaces the file in one step, so the launcher never reads a half-written id.
{ printf '%s\n' "$sid" > "$f.$$" && mv -f "$f.$$" "$f"; } 2>/dev/null
exit 0
