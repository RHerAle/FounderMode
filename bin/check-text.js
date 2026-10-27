#!/usr/bin/env node
// Copyright 2026 RHerAle
// SPDX-License-Identifier: Apache-2.0
// check-text.js [--terms FILE] FILE...
// Checks a text before it leaves the company: dashes and arrows, AI attribution lines, secrets, and the names in the
// terms file. Reads .md, .txt and .html. In Markdown, code blocks and inline code don't count for dashes and arrows;
// every other rule reads them too. The terms file holds one term per line, after its kind and a tab:
//   old-name<TAB>term       a name the company no longer uses; a finding prints it
//   confidential<TAB>term   a name under NDA; a finding prints neither the term nor its context
// One finding per line of output. Exit 0 when clean, 1 with findings, 2 when a file can't be read.
'use strict';
const fs = require('node:fs');

const MARKS = {
  '—': 'em dash U+2014', '–': 'en dash U+2013', '―': 'horizontal bar U+2015',
  '−': 'minus sign U+2212', '‒': 'figure dash U+2012', '⸺': 'two-em dash U+2E3A',
  '⸻': 'three-em dash U+2E3B', '←': 'arrow U+2190', '↑': 'arrow U+2191', '→': 'arrow U+2192',
  '↓': 'arrow U+2193', '↔': 'arrow U+2194', '⇐': 'arrow U+21D0', '⇒': 'arrow U+21D2',
  '⇔': 'arrow U+21D4', '➡': 'arrow U+27A1', '⮕': 'arrow U+2B95',
};
const CONTEXT = 50; // characters printed on each side of a finding
const esc = t => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// A literal term, with word boundaries at its alphanumeric ends.
const word = t => (/^\w/.test(t) ? '\\b' : '') + esc(t) + (/\w$/.test(t) ? '\\b' : '');
// [category, pattern, reads code too, hidden]
const RULES = [
  ['dash or arrow', new RegExp('[' + Object.keys(MARKS).join('') + ']', 'g'), false, false],
  ['attribution', /\bCo-Authored-By\b|\bClaude-Session\b|\bGenerated with\b|claude\.ai\/code|noreply@anthropic\.com|\u{1F916}/giu, true, false],
  ['secret', /sk-ant-|ghp_|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[bp]-/g, true, true],
];

function terms(file) {
  if (!file || !fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith('#')).map(l => {
    const [kind, term] = l.split('\t').map(x => (x || '').trim());
    if (!term || !['old-name', 'confidential'].includes(kind)) throw new Error(`bad line in ${file}: kind<TAB>term`);
    return [kind === 'old-name' ? 'old name' : 'confidential name', new RegExp(word(term), 'gi'), true, kind === 'confidential'];
  });
}

const unescape = t => t.replace(/&mdash;/g, '—').replace(/&ndash;/g, '–').replace(/&rarr;/g, '→')
  .replace(/&larr;/g, '←').replace(/&rArr;/g, '⇒')
  .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)));

// [line number, text, text with Markdown code blanked]
function lines(file) {
  if (!/\.(md|txt|html)$/.test(file)) throw new Error('only .md, .txt and .html');
  const md = file.endsWith('.md'), html = !file.endsWith('.txt');
  let fence = false;
  return fs.readFileSync(file, 'utf8').split('\n').map((l, i) => {
    if (html) l = unescape(l);
    let mask = l;
    if (md) {
      if (l.trimStart().startsWith('```')) { fence = !fence; mask = ''; }
      else if (fence) mask = '';
      else mask = l.replace(/`[^`]*`/g, m => ' '.repeat(m.length));
    }
    return [i + 1, l, mask];
  });
}

function check(file, rules) {
  const out = [];
  for (const [n, text, mask] of lines(file)) {
    for (const [cat, rx, code, hidden] of rules) {
      const seen = new Set();
      for (const m of (code ? text : mask).matchAll(rx)) {
        const k = m[0].toLowerCase();
        if (seen.has(k)) continue;
        seen.add(k);
        const ctx = text.slice(Math.max(0, m.index - CONTEXT), m.index + m[0].length + CONTEXT);
        out.push(`${file}: line ${n}: [${cat}]` + (hidden ? '' : ` ${MARKS[m[0]] || m[0]} | ${ctx}`));
      }
    }
  }
  return out;
}

function main(argv) {
  let termFile = null;
  if (argv[0] === '--terms') { termFile = argv[1]; argv = argv.slice(2); }
  let rules;
  try { rules = RULES.concat(terms(termFile)); } catch (e) { console.log(e.message); return 2; }
  let found = 0, unread = 0;
  for (const f of argv) {
    let r;
    try { r = check(f, rules); } catch (e) { console.log(`${f}: can't read it (${e.code || e.message})`); unread++; continue; }
    r.forEach(x => console.log(x));
    found += r.length;
  }
  return unread ? 2 : found ? 1 : 0;
}

process.exitCode = main(process.argv.slice(2));
