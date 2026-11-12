#!/usr/bin/env node
// Copyright 2026 RHerAle
// SPDX-License-Identifier: Apache-2.0
// Part of Founder Mode: https://github.com/RHerAle/FounderMode
// check-text.js [--terms FILE] [--sources] [--retired FILE]... [--retired-only FILE]... FILE...
// Checks a text before it leaves the company: dashes and arrows, AI attribution lines, secrets, the names in the
// terms file and the words that mark a guess. Reads .md, .txt, .html and .tex. Code blocks and inline code in
// Markdown, and comments in LaTeX, don't count for dashes, arrows and guesses; every other rule reads them too. The
// terms file holds one term per line, after its kind and a tab:
//   old-name<TAB>term       a name the company no longer uses; a finding prints it
//   confidential<TAB>term   a name under NDA; a finding prints neither the term nor its context
//   guess<TAB>term          a word that marks an unchecked claim, such as "probably"; a finding prints it
//   source-tag<TAB>tag      a tag that names a source, besides "source:"
// With --sources, every prose paragraph, and every \bibitem in LaTeX, must carry a source tag, in a comment or in
// the text. A prose paragraph is a block between blank lines, outside code, with at least MIN_WORDS words. Headings
// and LaTeX spacing commands at its top don't count; after them it opens with none of a table, a quote, an HTML tag
// other than <p>, \item, or a LaTeX command that leaves no text, such as \begin or \caption.
// With --retired, the old phrases of a retired.tsv (facts/README.md, its first column) are findings too, in code as
// well. --retired-only checks those phrases and nothing else: for memories, role files and the org chart, which don't
// leave the company.
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
const MIN_WORDS = 12; // below this, a block counts as a label or a caption
// A LaTeX command with its arguments; an argument with nested braces stays in the text.
const TEX_CMD = /\\[a-zA-Z@]+\*?(\s*\[[^\]]*\])*(\s*\{[^{}]*\})*/g;
// LaTeX lines without text that a paragraph may follow with no blank line between: headings, labels and spacing.
const TEX_LEAD = /^\s*\\((sub)*section|chapter|part|(sub)?paragraph|label|noindent|indent|par|(small|med|big)skip|vspace)\b/;
const esc = t => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// A literal term, with word boundaries at its alphanumeric ends.
const word = t => (/^\w/.test(t) ? '\\b' : '') + esc(t) + (/\w$/.test(t) ? '\\b' : '');
// [category, pattern, reads code too, hidden]
const RULES = [
  ['dash or arrow', new RegExp('[' + Object.keys(MARKS).join('') + ']', 'g'), false, false],
  ['attribution', /\bCo-Authored-By\b|\bClaude-Session\b|\bGenerated with\b|claude\.ai\/code|noreply@anthropic\.com|\u{1F916}/giu, true, false],
  ['secret', /sk-ant-|ghp_|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[bp]-/g, true, true],
];
// A kind in the terms file: [category, reads code too, hidden]
const KINDS = {
  'old-name': ['old name', true, false],
  confidential: ['confidential name', true, true],
  guess: ['guess', false, false],
};

// The rules and the source tags that the terms file adds.
function terms(file) {
  const rules = [], tags = ['source:'];
  if (!file || !fs.existsSync(file)) return { rules, tags };
  for (const l of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!l.trim() || l.startsWith('#')) continue;
    const [kind, term] = l.split('\t').map(x => (x || '').trim());
    if (term && kind === 'source-tag') { tags.push(term.toLowerCase()); continue; }
    if (!term || !KINDS[kind]) throw new Error(`bad line in ${file}: kind<TAB>term`);
    const [cat, code, hidden] = KINDS[kind];
    rules.push([cat, new RegExp(word(term), 'gi'), code, hidden]);
  }
  return { rules, tags };
}

// The old phrases of retired.tsv files, as rules.
const retired = files => files.flatMap(f => fs.readFileSync(f, 'utf8').split('\n'))
  .filter(l => l.trim() && !l.startsWith('#')).map(l => l.split('\t')[0].trim()).filter(t => t)
  .map(t => ['retired phrase', new RegExp(word(t), 'gi'), true, false]);

const unescape = t => t.replace(/&mdash;/g, '—').replace(/&ndash;/g, '–').replace(/&rarr;/g, '→')
  .replace(/&larr;/g, '←').replace(/&rArr;/g, '⇒')
  .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)));

// [line number, text, text with Markdown code or LaTeX comments blanked]
function lines(file) {
  if (!/\.(md|txt|html|tex)$/.test(file)) throw new Error('only .md, .txt, .html and .tex');
  const md = file.endsWith('.md'), tex = file.endsWith('.tex'), html = /\.(md|html)$/.test(file);
  let fence = false;
  return fs.readFileSync(file, 'utf8').split('\n').map((l, i) => {
    if (html) l = unescape(l);
    let mask = l;
    if (md) {
      if (l.trimStart().startsWith('```')) { fence = !fence; mask = ''; }
      else if (fence) mask = '';
      else mask = l.replace(/`[^`]*`/g, m => ' '.repeat(m.length));
    } else if (tex) {
      mask = l.replace(/(^|[^\\])%.*$/, (m, p) => p + ' '.repeat(m.length - p.length));
    }
    return [i + 1, l, mask];
  });
}

// The prose paragraphs, and the \bibitem entries in LaTeX, that carry no source tag.
function unsourced(file, rows, tags) {
  const out = [], md = file.endsWith('.md'), tex = file.endsWith('.tex');
  const tagged = t => { t = t.toLowerCase(); return tags.some(g => t.includes(g)); };
  const want = `without ${tags.join(' or ')}`;
  // In Markdown an HTML comment holds the tag and isn't prose.
  const prose = r => (md ? r[2].replace(/<!--.*?-->/g, '') : r[2]);
  // How a line opens a paragraph: 'lead' (a heading or spacing, passed over), 'markup' (not prose) or 'prose'.
  const opens = r => {
    const t = prose(r);
    if (tex) {
      if (/^\s*\\([^a-zA-Z@]|(bib)?item\b)/.test(t)) return 'markup';
      if (/\p{L}/u.test(t.replace(TEX_CMD, ' '))) return 'prose';
      return TEX_LEAD.test(t) ? 'lead' : 'markup';
    }
    if (/^\s*(#|<h[1-6][\s>])/i.test(t)) return 'lead';
    return /^\s*([|<>\\]|```)/.test(t.replace(/^\s*<p(\s[^>]*)?>/i, '')) ? 'markup' : 'prose';
  };
  const words = t => ((tex ? t.replace(/\\[a-zA-Z@]+/g, ' ') : t).match(/\p{L}+/gu) || []).length;
  let block = [];
  const flush = () => {
    const body = block.filter(r => prose(r).trim());
    let i = 0;
    while (i < body.length && opens(body[i]) === 'lead') i++;
    const para = body.slice(i);
    if (para.length && opens(para[0]) === 'prose' && words(para.map(prose).join(' ')) >= MIN_WORDS
        && !tagged(block.map(r => r[1]).join('\n')))
      out.push(`${file}: line ${para[0][0]}: [no source] a paragraph ${want}`);
    block = [];
  };
  for (const r of rows) {
    if (r[1].trim()) block.push(r);
    else flush();
  }
  flush();
  if (!file.endsWith('.tex')) return out;
  let item = null;
  const close = () => {
    if (item && !tagged(item.text)) out.push(`${file}: line ${item.n}: [no source] \\bibitem${item.key} ${want}`);
    item = null;
  };
  for (const [n, text, mask] of rows) {
    const m = mask.match(/\\bibitem(?:\[[^\]]*\])?(\{[^}]*\})?/);
    if (m) { close(); item = { n, key: m[1] || '', text: text.slice(m.index) }; }
    else if (item && /\\end\{thebibliography\}/.test(mask)) close();
    else if (item) item.text += '\n' + text;
  }
  close();
  return out;
}

function check(file, rules, tags, sources) {
  const out = [], rows = lines(file);
  for (const [n, text, mask] of rows) {
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
  return sources ? out.concat(unsourced(file, rows, tags)) : out;
}

function main(argv) {
  let termFile = null, sources = false, only = false;
  const old = [];
  for (;;) {
    if (argv[0] === '--terms') { termFile = argv[1]; argv = argv.slice(2); }
    else if (argv[0] === '--retired' || argv[0] === '--retired-only') {
      only = only || argv[0] === '--retired-only'; old.push(argv[1]); argv = argv.slice(2);
    }
    else if (argv[0] === '--sources') { sources = true; argv = argv.slice(1); }
    else break;
  }
  let t, r;
  try { t = terms(termFile); r = retired(old); } catch (e) { console.log(e.message); return 2; }
  const rules = only ? r : RULES.concat(t.rules, r);
  let found = 0, unread = 0;
  for (const f of argv) {
    let r;
    try { r = check(f, rules, t.tags, sources); } catch (e) { console.log(`${f}: can't read it (${e.code || e.message})`); unread++; continue; }
    r.forEach(x => console.log(x));
    found += r.length;
  }
  return unread ? 2 : found ? 1 : 0;
}

process.exitCode = main(process.argv.slice(2));
