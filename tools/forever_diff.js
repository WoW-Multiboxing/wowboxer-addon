#!/usr/bin/env node
/* Prints the generated tables of docs/forever-talent-diff.md: the talent trees of the pre-launch seed
   (vendor/companion) against the live client (datasrc/forever/blizzard-<build>.json) per class and tree, the guide
   table and the spell changes of the rerun (tools/forever_data.js). Usage: node tools/forever_diff.js > out.md */
'use strict';
const { load } = require('./companion');
const FOREVER = require('./forever_data');

const { D, E, K } = load();
const FV = FOREVER.load({ D, E, K });
const BZ = FV.BZ;
const out = [];
const p = s => out.push(s);
const cap = s => s.charAt(0).toUpperCase() + s.slice(1);

p('### Trees: pre-launch seed → live client (build ' + BZ.build + ')\n');
p('Matched by talent name inside the class. "moved" = other row/column (or tree); a name that left one cell while a new');
p('name took the same cell is shown as "replaced by".\n');
let same = 0, changed = 0;
for (const cls of D.classOrder) {
  const seed = D.talents[cls].nodes, live = BZ.talents[cls];
  const sBy = {}, lBy = {};
  for (const n of seed) sBy[n.n] = n;
  for (const n of live) lBy[n.n] = n;
  for (let t = 0; t < 3; t++) {
    const rows = [];
    const sT = seed.filter(n => n.t === t), lT = live.filter(n => n.t === t);
    const gone = sT.filter(n => !lBy[n.n]), added = lT.filter(n => !sBy[n.n]);
    for (const n of gone) {
      const r = added.find(a => a.r === n.r && a.c === n.c);
      rows.push(r ? 'replaced by **' + r.n + '** (' + r.m + ') at row ' + n.r + ' col ' + n.c + ': ' + n.n + ' (' + n.m + ')' : 'removed: ' + n.n + ' (' + n.m + ', row ' + n.r + ')');
    }
    for (const n of added) if (!gone.find(g => g.r === n.r && g.c === n.c)) rows.push('added: **' + n.n + '** (' + n.m + ', row ' + n.r + ' col ' + n.c + ')');
    for (const n of lT) {
      const s = sBy[n.n];
      if (!s) continue;
      const d = [];
      if (s.t !== n.t || s.r !== n.r || s.c !== n.c) d.push('moved ' + (s.t !== n.t ? 'from tree ' + D.talents[cls].trees[s.t].n + ' ' : '') + 'row ' + s.r + ' col ' + s.c + ' → row ' + n.r + ' col ' + n.c);
      if (s.m !== n.m) d.push('ranks ' + s.m + ' → ' + n.m);
      const sa = (D.talents[cls].arrows.find(a => a[1] === s.k) || [])[0] || null;
      if ((sa || null) !== (n.req || null)) d.push('prerequisite ' + (sa || 'none') + ' → ' + (n.req || 'none'));
      if (d.length) rows.push(n.n + ': ' + d.join(', '));
    }
    const name = BZ.trees[cls][t].n;
    if (!rows.length) { same++; continue; }
    changed++;
    p('- **' + cap(cls) + ' ' + name + '** (' + lT.length + ' talents): ' + rows.join('; ') + '.');
  }
}
p('\n' + changed + ' of 27 trees changed, ' + same + ' unchanged (same names, cells, ranks and prerequisites).\n');

p('### Guides\n');
p('| Guide | Class | Status | Points | What changed |');
p('|---|---|---|---|---|');
const count = {};
for (const g of FV.report.guides) {
  count[g.status] = (count[g.status] || 0) + 1;
  p('| `' + g.id + '`' + (g.default ? ' (default)' : '') + ' | ' + g.cls + ' | ' + g.status + ' | ' + g.points + ' | ' + g.what.replace(/\|/g, '/') + ' |');
}
p('\n' + Object.entries(count).map(([k, v]) => v + ' ' + k).join(', ') + ' (' + FV.report.guides.length + ' guides).');
for (const d of FV.report.defaults) p('Default moved: ' + d.cls + ' ' + d.from + ' → ' + d.to + ' (' + d.why + ').');

p('\n### Spells\n');
const bucket = {};
for (const s of FV.report.spells) (bucket[s.cls] = bucket[s.cls] || []).push(s);
for (const cls of D.classOrder) {
  const list = bucket[cls] || [];
  if (!list.length) continue;
  p('- **' + cap(cls) + '**: ' + list.map(s => s.name + ' – ' + s.what).join('; ') + '.');
}
for (const c of FV.report.core) p('- Recommended macros: ' + c.cls + '/' + c.role + ' ' + c.name + ' ' + c.what + '.');
console.log(out.join('\n'));
