'use strict';
// Round trip: every companion guide is written as a Wowhead link (points + click order, with and without max-rank
// tokens), read back with importWowhead, and must give the same order. Plus a few bad links. node docs/patches/wowhead_import.test.js
const path = require('path'), root = path.join(__dirname, '..', '..');
const D = require(path.join(root, 'vendor/companion/app_data.json')), E = require(path.join(root, 'vendor/companion/engine.js'));
const WH = require('../../vendor/wowhead/forever-trees.json'), { importWowhead } = require('./wowhead_import.js');
let pass = 0, fail = 0, skip = 0;
function encode(cls, order, compress) {
  const T = E.makeTree(D.talents[cls]), idx = {};
  WH[cls].forEach((tree, t) => tree.forEach((w, i) => { const n = D.talents[cls].nodes.find(x => x.t === t && x.n.toLowerCase() === w.n.toLowerCase()); if (n) idx[n.k] = { t, i, m: n.m }; }));
  if (order.some(k => !idx[k])) return null; // talent only in WoWBoxer's data (e.g. Mage Arcane Focus)
  const c = E.countsOf(order), trees = [[], [], []];
  for (const k in c) trees[idx[k].t][idx[k].i] = c[k];
  let pts = trees.map(a => Array.from({ length: a.length }, (_, i) => a[i] || 0).join('').replace(/0+$/, '')).join('-').replace(/-+$/, '');
  let ord = '', tree = -1, seen = {};
  for (let j = 0; j < order.length; j++) {
    const k = order[j], x = idx[k];
    if (x.t !== tree) { ord += x.t; tree = x.t; }
    if (seen[k]) { continue; }
    let run = 1; while (order[j + run] === k) run++;
    if (compress && run === x.m && !seen[k]) { ord += WH.tokens.max[x.i]; seen[k] = true; j += run - 1; continue; }
    ord += WH.tokens.one[x.i];
  }
  // non-compressed: one lowercase token per point
  if (!compress) { ord = ''; tree = -1; for (const k of order) { const x = idx[k]; if (x.t !== tree) { ord += x.t; tree = x.t; } ord += WH.tokens.one[x.i]; } }
  return 'https://www.wowhead.com/forever/talent-calc/' + cls + '/' + WH.hashVersion + pts + '_t0/' + ord;
}
const guides = Array.isArray(D.guides) ? D.guides : Object.values(D.guides).flat();
for (const g of guides) {
  if (!g.order || !g.order.length) continue;
  for (const compress of [false, true]) {
    const link = encode(g.cls, g.order, compress);
    if (!link) { skip++; continue; }
    const r = importWowhead(link, D, WH, E);
    const ok = !r.error && r.hasOrder && r.order.join() === g.order.join() && !r.warnings.length;
    if (ok) pass++; else { fail++; console.log('FAIL', g.id, compress, r.error || r.warnings, link); }
  }
}
const bad = [['https://www.wowhead.com/classic/talent-calc/druid/0abaa', 'not a WoW Forever link'],
  ['https://example.com/x', 'Not a Wowhead'], ['https://www.wowhead.com/forever/talent-calc/deathknight/v2', 'Unknown class'],
  ['https://www.wowhead.com/forever/talent-calc/druid/v3123', 'newer Wowhead format']];
for (const [l, want] of bad) { const r = importWowhead(l, D, WH, E); if (r.error && r.error.includes(want)) pass++; else { fail++; console.log('FAIL bad link', l, r); } }
const ex = importWowhead('https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa', D, WH, E);
if (ex.split === '11/4/0' && ex.points === 15 && ex.hasOrder) pass++; else { fail++; console.log('FAIL example', ex); }
console.log('pass', pass, 'fail', fail, 'skipped (talent only in WoWBoxer data)', skip);
process.exit(fail ? 1 : 0);
