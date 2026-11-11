#!/usr/bin/env node
/* WoW Forever talents: cross-check the client tables against Wowhead's talent calculator and refresh
   vendor/wowhead/forever-trees.json (docs/talents-rerun-2026-11-11.md §2.1.4).
   Input: Wowhead's calculator data, saved from https://nether.wowhead.com/forever/data/talents-classic (a JS file
   whose first line is WH.setPageData("wow.talentCalcClassic.classicplus.data", {...})). It is only parsed as JSON
   (hard rule 2: never run). Talents are matched by node ID: Wowhead's talent id is the client's C_Traits node ID.
   Usage: node tools/wowhead_forever.js <talents-classic.js> [--write]
     prints every difference (client wins) as markdown; --write also refreshes vendor/wowhead/forever-trees.json:
       hashVersion = Wowhead's current hash version, trees = current layout (row, then column per tree),
       layouts.v2 = the old v2 layout (links made before the change still read, matched by name). */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const BZ = JSON.parse(fs.readFileSync(path.join(ROOT, 'datasrc', 'forever', 'blizzard-1.60.1.70888.json'), 'utf8'));
const VENDOR = path.join(ROOT, 'vendor', 'wowhead', 'forever-trees.json');
const ORDER = ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid'];

function readWowhead(file) {
  const line = fs.readFileSync(file, 'utf8').split('\n')[0];
  const m = line.match(/^WH\.setPageData\("wow\.talentCalcClassic\.classicplus\.data",(\{.*\})\);?\s*$/);
  if (!m) throw new Error('not Wowhead calculator data: ' + file);
  return JSON.parse(m[1]);
}

function compare(W) {
  const byNode = {};
  for (const [tab, ts] of Object.entries(W.talents)) for (const t of Object.values(ts)) byNode[t.id] = Object.assign({ tab: +tab }, t);
  const rows = [], trees = {}, tabOf = {};
  for (const cls of ORDER) {
    const nodes = BZ.talents[cls];
    const key = {}; for (const n of nodes) key[n.node] = n;
    trees[cls] = [[], [], []];
    for (const n of nodes) {
      const w = byNode[n.node];
      if (!w) { rows.push([cls, BZ.trees[cls][n.t].n, n.n, 'only in the client (not on Wowhead)']); continue; }
      tabOf[w.tab] = tabOf[w.tab] || { cls, t: n.t };
      if (tabOf[w.tab].cls !== cls || tabOf[w.tab].t !== n.t) rows.push([cls, BZ.trees[cls][n.t].n, n.n, 'Wowhead has it in another tree']);
      const d = [];
      if (w.name !== n.n) d.push('name "' + w.name + '" on Wowhead');
      if (w.row + 1 !== n.r || w.col + 1 !== n.c) d.push('row/col ' + (w.row + 1) + '/' + (w.col + 1) + ' on Wowhead, ' + n.r + '/' + n.c + ' in the client');
      if (w.ranks.length !== n.m) d.push(w.ranks.length + ' ranks on Wowhead, ' + n.m + ' in the client');
      if (w.requiredPoints !== (n.r - 1) * 5) d.push('Wowhead needs ' + w.requiredPoints + ' points in the tree');
      const wr = (w.requires || []).map(x => key[x.id] ? key[x.id].k + '@' + x.qty : '?' + x.id).join(',');
      const cr = n.req ? n.req + '@' + nodes.find(x => x.k === n.req).m : '';
      if (wr !== cr) d.push('prerequisite "' + wr + '" on Wowhead, "' + cr + '" in the client');
      if (d.length) rows.push([cls, BZ.trees[cls][n.t].n, n.n, d.join('; ') + ' – the client wins']);
      trees[cls][n.t].push(n);
    }
    const mine = new Set(nodes.map(n => n.node));
    for (const w of Object.values(byNode)) if (!mine.has(w.id) && tabOf[w.tab] && tabOf[w.tab].cls === cls) rows.push([cls, BZ.trees[cls][tabOf[w.tab].t].n, w.name, 'only on Wowhead (not in the client) – left out']);
  }
  return { rows, trees };
}

function main() {
  const file = process.argv[2];
  if (!file) { console.error('usage: node tools/wowhead_forever.js <talents-classic.js> [--write]'); process.exit(2); }
  const W = readWowhead(file);
  const { rows, trees } = compare(W);
  const total = ORDER.reduce((s, c) => s + BZ.talents[c].length, 0);
  console.log('Wowhead hash version: ' + W.hashVersion + '; old layouts it still reads: ' + Object.keys(W.hashLayouts || {}).join(', '));
  console.log(total + ' client talents checked against Wowhead by node ID: ' + (rows.length ? rows.length + ' differences' : 'they agree on every talent (name, row, column, ranks, prerequisite, points needed)'));
  if (rows.length) {
    console.log('\n| Class | Tree | Talent | Difference |\n|---|---|---|---|');
    for (const r of rows) console.log('| ' + r.join(' | ') + ' |');
  }
  if (process.argv.includes('--write')) {
    const old = JSON.parse(fs.readFileSync(VENDOR, 'utf8'));
    // Wowhead's older layouts per hash version: {tabId: [[row, col, maxRank, spell, name, pointsNeeded, [[index, qty]]], ...]}
    // in digit order; per class here as three trees of {n, m, r (0-based row), p (points needed), q (prerequisites)}
    const tabs = {};
    for (const [tab, ts] of Object.entries(W.talents)) {
      const id = +Object.keys(ts)[0];
      for (const c of ORDER) { const n = BZ.talents[c].find(x => x.node === id); if (n) tabs[tab] = [c, n.t]; }
    }
    const layouts = {};
    for (const [v, list] of Object.entries(W.hashLayouts || {})) layouts[v] = list.map(L => {
      const o = {};
      for (const [tab, arr] of Object.entries(L)) {
        if (!tabs[tab]) continue;
        const [c, t] = tabs[tab];
        o[c] = o[c] || [[], [], []];
        o[c][t] = arr.map(x => ({ n: x[4], m: x[2], r: x[0], p: x[5], q: x[6] && x[6].length ? x[6] : undefined }));
      }
      return o;
    });
    const out = {
      _source: 'Wowhead WoW Forever talent calculator data (nether.wowhead.com/forever/data/talents-classic), hashVersion ' + W.hashVersion +
        ', fetched ' + new Date().toISOString().slice(0, 10) + '; trees = the current layout (row, then column), checked against the client tables of build ' +
        BZ.build + ' by node ID (tools/wowhead_forever.js); layouts = Wowhead\'s own older layouts per hash version (links made before ' +
        'the change, e.g. v2: tried in order, the first that reads legally wins, then matched by name). Names (c) Blizzard. Only the token order is used.',
      tokens: old.tokens, hashVersion: W.hashVersion,
    };
    for (const c of ORDER) out[c] = trees[c].map(t => t.slice().sort((a, b) => a.r - b.r || a.c - b.c).map(n => ({ n: n.n, m: n.m })));
    out.layouts = layouts;
    fs.writeFileSync(VENDOR, JSON.stringify(out, null, 1) + '\n');
    console.log('wrote ' + path.relative(ROOT, VENDOR));
  }
}
main();
