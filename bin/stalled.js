#!/usr/bin/env node
// Copyright 2026 RHerAle
// SPDX-License-Identifier: Apache-2.0
// founder-mode stalled: sessions whose conversation ended on an API error, such as a usage limit or a dropped
// connection. After a limit resets, not every session resumes on its own, so the coordinator wakes the ones still
// stopped. It reads local files only and costs no tokens. --hook: live sessions only, on one line, for a hook.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const FM = process.env.FM_HOME || path.join(os.homedir(), '.founder-mode');
const CL = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const hook = process.argv.includes('--hook');
const TAIL = 1 << 20; // the last entry sits near the end; one MiB finds it without reading a long transcript whole

const list = dir => { try { return fs.readdirSync(dir); } catch { return []; } };

// Alive, and the same process: after a reboot a pid can come back as another program. Linux can tell by start time.
function sameProcess(s) {
  process.kill(s.pid, 0);
  if (!s.procStart || !fs.existsSync(`/proc/${s.pid}/stat`)) return true;
  return fs.readFileSync(`/proc/${s.pid}/stat`, 'utf8').replace(/^.*\) /s, '').split(' ')[19] === String(s.procStart);
}

function liveIds() {
  const ids = new Set();
  for (const f of list(path.join(CL, 'sessions')).filter(f => f.endsWith('.json'))) {
    try {
      const s = JSON.parse(fs.readFileSync(path.join(CL, 'sessions', f), 'utf8'));
      if (sameProcess(s)) ids.add(s.sessionId);
    } catch { /* unreadable entry or dead process */ }
  }
  return ids;
}

function transcript(id) {
  for (const p of list(path.join(CL, 'projects'))) {
    const f = path.join(CL, 'projects', p, `${id}.jsonl`);
    if (fs.existsSync(f)) return f;
  }
  return null;
}

// Last user or assistant entry: the tail first, the whole file only when the tail holds none.
function lastEntry(file) {
  const size = fs.statSync(file).size;
  for (const from of [Math.max(0, size - TAIL), 0]) {
    const buf = Buffer.alloc(size - from);
    const fd = fs.openSync(file, 'r');
    try { fs.readSync(fd, buf, 0, buf.length, from); } finally { fs.closeSync(fd); }
    const lines = buf.toString('utf8').split('\n');
    if (from > 0) lines.shift(); // the tail starts mid-line
    for (let i = lines.length - 1; i >= 0; i--) {
      let e;
      try { e = JSON.parse(lines[i]); } catch { continue; }
      if (e.type === 'user' || e.type === 'assistant') return e;
    }
    if (from === 0) break;
  }
  return null;
}

// Session name and kind per role, from roles.tsv.
function roles() {
  const r = {};
  let rows = [];
  try { rows = fs.readFileSync(path.join(FM, 'roles.tsv'), 'utf8').split('\n'); } catch { /* show role keys */ }
  for (const row of rows) {
    const c = row.split('\t');
    if (c.length > 1 && !row.startsWith('#')) r[c[0]] = { name: c[1], kind: c[5] };
  }
  return r;
}

const live = liveIds();
const info = roles();
const stalled = [];
for (const f of list(path.join(FM, 'state')).filter(f => f.endsWith('.session'))) {
  const role = f.slice(0, -'.session'.length);
  if (role === process.env.FM_ROLE) continue; // the caller is awake
  let id;
  try { id = fs.readFileSync(path.join(FM, 'state', f), 'utf8').trim(); } catch { continue; }
  const t = transcript(id);
  const e = t && lastEntry(t);
  if (!e || !e.isApiErrorMessage) continue;
  const isLive = live.has(id);
  if (hook && !isLive) continue;
  const c = e.message && e.message.content;
  const text = Array.isArray(c) ? c.map(x => x.text || '').join(' ') : String(c || '');
  const when = new Date(e.timestamp).toLocaleString([], { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
  const r = info[role] || {};
  // An isolated role runs --restricted, which opens no inbox: a founder resumes it in its own window.
  stalled.push({ name: r.name || role, when, text: text.replace(/\s+/g, ' ').slice(0, 90), isLive, closed: r.kind === 'isolated' });
}

const names = a => a.map(s => `${s.name} (since ${s.when}: ${s.text})`).join('; ');
if (hook) {
  const wake = stalled.filter(s => !s.closed), ask = stalled.filter(s => s.closed);
  const out = [];
  if (wake.length) {
    out.push(`Sessions stopped on an API error: ${names(wake)}. This turn is running, so the limit has reset: `
      + 'wake each one with SendMessage ("Limit reset: pick up what you left half done; no need to reply").');
  }
  if (ask.length) out.push(`Stopped on an API error and closed to messages: ${names(ask)}. Ask a founder to resume it in its window.`);
  if (out.length) console.log(out.join(' '));
} else if (!stalled.length) {
  console.log('No session stopped on an API error.');
} else {
  const state = s => (!s.isLive ? 'closed, needs a relaunch' : s.closed ? 'live, takes no messages: resume it in its window' : 'live');
  for (const s of stalled) console.log(`${s.name.padEnd(16)} stopped since ${s.when} · ${state(s)} · ${s.text}`);
}
