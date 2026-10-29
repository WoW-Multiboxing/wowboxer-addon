'use strict';
/* Reference decoder for Wowhead WoW Forever talent-calculator links (docs/talent-import.md). Port to Lua as-is.
   Link: https://www.wowhead.com/forever/talent-calc/<class>/<points>[/<order>]
     <points> = optional hash version ("v2") + one digit per talent in Wowhead's token order (row, then column),
                trees separated by "-", trailing zeros left out; then "_"-options: t<0-5> Talented rank,
                l<level> player level, r<race id>.
     <order>  = the click order: "0"/"1"/"2" switches tree, a lowercase token = +1 rank of that talent,
                an uppercase token = the rest of its ranks at once.
   Talents are matched to WoWBoxer's tree by name (Wowhead and the companion data disagree on a few positions).
   Pure data: no eval, nothing from the link is ever run. */
function importWowhead(link, D, WH, E) {
  const s = String(link || '').trim().replace(/[?#].*$/, '').replace(/\/+$/, '');
  const m = /talent-calc\/([a-z-]+)\/([^/]*)(?:\/([^/]*))?$/.exec(s);
  if (!m) return { error: 'Not a Wowhead talent calculator link' };
  const cls = m[1];
  if (!D.talents[cls] || !WH[cls]) return { error: 'Unknown class "' + cls + '"' };
  if (!/\/forever\//.test(s)) return { error: 'This is not a WoW Forever link (look for /forever/ in it)' };
  const warn = [];
  const T = E.makeTree(D.talents[cls]);
  const byName = {}; for (const n of D.talents[cls].nodes) byName[n.n.toLowerCase() + '|' + n.t] = n;
  const node = (tree, i) => { const w = WH[cls][tree] && WH[cls][tree][i]; return w ? { w, n: byName[w.n.toLowerCase() + '|' + tree] } : null; };
  // points + options
  let hash = m[2] || '';
  if (WH.hashVersion && hash.startsWith(WH.hashVersion)) hash = hash.slice(WH.hashVersion.length); // "v2" + digits: strip the exact version only
  else if (/^v/.test(hash)) return { error: 'This link uses a newer Wowhead format (' + hash.slice(0, 3) + '…) – WoWBoxer needs an update' };
  const [pts, ...opts] = hash.split('_');
  let talented = 0, level = null;
  for (const o of opts) { let x; if ((x = /^t([0-5])$/.exec(o))) talented = +x[1]; else if ((x = /^l(\d{1,2})$/.exec(o))) level = +x[1]; }
  const counts = {}, add = (k, n) => { counts[k] = (counts[k] || 0) + n; };
  const want = []; // [{key, n}] from the points part, tree by tree
  (pts || '').split('-').forEach((digits, tree) => {
    for (let i = 0; i < digits.length; i++) {
      const r = +digits[i]; if (!r) continue;
      const x = node(tree, i);
      if (!x) return warn.push('Point ' + digits[i] + ' at position ' + (i + 1) + ' in tree ' + (tree + 1) + ' is not a known talent');
      if (!x.n) { warn.push(x.w.n + ' is not in WoWBoxer\'s ' + D.talents[cls].trees[tree].n + ' tree – left out'); continue; }
      const r2 = Math.min(r, x.n.m); if (r2 < r) warn.push(x.w.n + ': ' + r + ' points on Wowhead, max ' + x.n.m + ' here');
      add(x.n.k, r2); want.push({ key: x.n.k, n: r2, t: tree, r: x.n.r });
    }
  });
  // click order, when the link has one
  let order = [], hasOrder = false;
  if (m[3]) {
    const one = WH.tokens.one, max = WH.tokens.max, seen = {};
    let tree = 0;
    for (const ch of m[3]) {
      if ('012'.includes(ch)) { tree = +ch; continue; }
      let i = one.indexOf(ch), all = false;
      if (i < 0) { i = max.indexOf(ch); all = true; }
      const x = i >= 0 ? node(tree, i) : null;
      if (!x || !x.n) { warn.push('Order: unknown talent "' + ch + '" – order ignored'); order = []; break; }
      const have = seen[x.n.k] || 0, to = all ? x.n.m : have + 1;
      for (let r = have + 1; r <= Math.min(to, x.n.m); r++) order.push(x.n.k);
      seen[x.n.k] = Math.min(to, x.n.m);
    }
    hasOrder = order.length > 0;
    if (hasOrder) { // the order must give the same points as the points part
      const c = E.countsOf(order), same = Object.keys(c).length === Object.keys(counts).length && Object.keys(c).every(k => c[k] === counts[k]);
      if (!same) { warn.push('The click order and the points in the link do not match – used the points, order by WoWBoxer'); hasOrder = false; }
    }
  }
  if (!hasOrder) { // no order in the link: rows first, then tree, as the companion does for "final-derived" guides
    want.sort((a, b) => a.r - b.r || a.t - b.t);
    order = []; for (const w of want) for (let i = 0; i < w.n; i++) order.push(w.key);
  }
  if (order.length > 51) { warn.push('More than 51 points – cut to 51'); order = order.slice(0, 51); }
  let bad = E.validateOrder(T, order);
  if (bad) {
    const fixed = E.repairOrder(T, order);
    if (!fixed) return { error: 'The build breaks the talent rules at point ' + (bad.index + 1) + ': ' + bad.reason };
    warn.push((hasOrder ? 'The click order' : 'The order') + ' broke a talent rule at point ' + (bad.index + 1) + ' (' + bad.reason + ') – reordered');
    order = fixed;
  }
  const tp = E.treePoints(T, E.countsOf(order));
  return { cls, order, talented, level, hasOrder, kind: hasOrder ? 'exact-order' : 'final-derived', split: tp.join('/'), points: order.length, warnings: warn };
}
module.exports = { importWowhead };

if (require.main === module) { // node docs/patches/wowhead_import.js [link]
  const path = require('path'), root = path.join(__dirname, '..', '..');
  const D = require(path.join(root, 'vendor/companion/app_data.json')), E = require(path.join(root, 'vendor/companion/engine.js'));
  const WH = require('./wowhead-forever-trees.json');
  const link = process.argv[2] || 'https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa';
  const r = importWowhead(link, D, WH, E);
  if (r.error) { console.log('ERROR', r.error); process.exit(1); }
  const T = E.makeTree(D.talents[r.cls]);
  console.log(r.cls, r.split, r.points + ' points', r.kind, 'talented ' + r.talented, r.warnings);
  r.order.forEach((k, i) => console.log('  level ' + E.levelForPoint(i, r.talented), T.byKey[k].n));
}
