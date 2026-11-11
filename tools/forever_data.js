/* WoW Forever data from the live client (docs/talents-rerun-2026-11-11.md), used by tools/build_data.js.
   - Talent trees: Blizzard client tables (C_Traits) of datasrc/forever/blizzard-<build>.json (tools/fetch_client.py),
     cross-checked with Wowhead's calculator (tools/wowhead_forever.js, docs/forever-talent-diff.md).
   - Spells: the frozen seed's macro rules (vendor/companion, read-only) with ranks, levels, gates and talent keys from
     the client tables; datasrc/forever/spells-extra.json on top. Rank levels: one rank per level (the seed's spell ID
     at that level, else the lowest ID: the skill lines also hold effect spells at the same level); a talent's spell
     never comes before the first level its row can be reached (10 + 5 per row, Talented rank 0).
   - Guides: every seed guide is checked on the live trees (E.validateOrder) and kept, repaired (E.repairOrder),
     rebuilt from a current source (datasrc/forever/guides.json) or, without one, moved to the live trees by the
     starter-build rules (removed talents dropped, ranks clamped, rows first) with a note.
   Everything it changes is listed in report (printed by node tools/build_data.js --report). */
'use strict';
const fs = require('fs');
const path = require('path');

const BUILD = '1.60.1.70888';
const SRC = path.join(__dirname, '..', 'datasrc', 'forever');
const RERUN = '2026-11-11';

const rowLevel = r => 10 + 5 * (r - 1);
const slugId = (cls, name) => cls + '-' + name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

function load({ D, E }) {
  const BZ = JSON.parse(fs.readFileSync(path.join(SRC, 'blizzard-' + BUILD + '.json'), 'utf8'));
  const EXTRA = JSON.parse(fs.readFileSync(path.join(SRC, 'spells-extra.json'), 'utf8'));
  const REBUILT = JSON.parse(fs.readFileSync(path.join(SRC, 'guides.json'), 'utf8'));
  const report = { build: BZ.build, spells: [], guides: [], core: [], defaults: [], problems: [] };
  const out = { BZ, report, talents: {}, spells: {}, extra: {}, guides: {}, core: {} };

  for (const cls of D.classOrder) {
    // ---- talents
    const seedT = D.talents[cls];
    const seedNode = {}; for (const n of seedT.nodes) seedNode[n.k] = n;
    const seedTree = {}; for (const t of seedT.trees) seedTree[t.n] = t;
    const nodes = BZ.talents[cls];
    const talents = {
      trees: BZ.trees[cls].map(t => ({ n: t.n, f: t.f, i: seedTree[t.n] ? seedTree[t.n].i : undefined })),
      nodes: nodes.map(n => ({ k: n.k, n: n.n, t: n.t, r: n.r, c: n.c, m: n.m, i: seedNode[n.k] && seedNode[n.k].n === n.n ? seedNode[n.k].i : undefined, f: n.f })),
      arrows: nodes.filter(n => n.req).map(n => [n.req, n.k]),
    };
    out.talents[cls] = talents;
    const byName = {}, bySpell = {}, byKey = {};
    for (const n of nodes) { byName[n.n] = n; bySpell[n.ranks[0]] = n; byKey[n.k] = n; }
    const book = BZ.spells[cls];

    // ---- spells
    const merged = [];
    const note = (name, what) => report.spells.push({ cls, name, what });
    const ranksFrom = (name, seedRanks, talent) => {
      const tb = book[name];
      if (!tb) return seedRanks.map(r => ({ id: r.id, l: talent ? Math.max(r.l, rowLevel(talent.r)) : r.l }));
      const seedAt = {}; for (const r of seedRanks) if (r.id) (seedAt[r.l] = seedAt[r.l] || []).push(r.id);
      const seedIds = new Set(seedRanks.map(r => r.id).filter(Boolean));
      const byLevel = new Map();
      for (const [id, l0] of tb) {
        const l = talent ? Math.max(l0, rowLevel(talent.r)) : l0;
        if (!l) continue; // level 0 = not trained (quest/other versions); talents get their row's level above
        (byLevel.get(l) || byLevel.set(l, []).get(l)).push(id);
      }
      const ranks = [];
      for (const l of [...byLevel.keys()].sort((a, b) => a - b)) {
        const ids = byLevel.get(l);
        // ranks the talent itself grants share a level (e.g. Holy Shield 30 -> 40): keep each one the seed knows
        const known = ids.filter(id => seedIds.has(id));
        const pick = known.length ? known.sort((a, b) => a - b) : [Math.min(...ids)];
        for (const id of pick) ranks.push({ id, l });
      }
      if (!ranks.length) return seedRanks.map(r => ({ id: r.id, l: r.l }));
      return ranks;
    };
    for (const s of D.spells.filter(x => x.cls === cls)) {
      let name = s.name;
      let talent = byName[name];
      if (s.gate === 'talent' && !talent && !byKey[s.talent]) {
        const first = s.ranks && s.ranks[0] && s.ranks[0].id;
        if (first && bySpell[first]) { talent = bySpell[first]; name = talent.n; note(s.name, 'renamed to ' + name + ' (same spell ' + first + ', the live talent)'); }
        else if (!book[name]) { note(s.name, 'removed: its talent ' + s.talent + ' is not in the live tree and no class skill line teaches it (Wowhead\'s Forever class abilities agree)'); continue; }
      }
      const r0 = (s.ranks || []).map(r => ({ id: r.id, l: r.l }));
      const ranks = ranksFrom(name, r0, talent);
      const before = r0.map(r => r.id + '@' + r.l).join(' '), after = ranks.map(r => r.id + '@' + r.l).join(' ');
      if (before !== after) note(name, 'ranks ' + (before || '-') + ' -> ' + after);
      const gate = talent ? 'talent' : (s.gate === 'talent' ? 'trainer' : s.gate);
      if (gate !== s.gate) note(name, 'gate ' + s.gate + ' -> ' + gate);
      if (talent && s.talent && s.talent !== talent.k) note(name, 'talent ' + s.talent + ' -> ' + talent.k);
      merged.push({ seed: s, name, gate, talent: talent ? talent.k : undefined, ranks: ranks.map((r, i) => ({ r: i + 1, l: r.l, id: r.id })) });
    }
    out.spells[cls] = merged;
    // spells-extra (client tables already): talent key and row level from the live tree
    out.extra[cls] = (EXTRA[cls] || []).map(x => {
      if (merged.some(m => m.name === x.name)) report.problems.push('spells-extra: ' + cls + ' ' + x.name + ' is already a spell');
      const t = byName[x.name];
      const ranks = x.ranks.map(([id, l]) => [id, t ? Math.max(l, rowLevel(t.r)) : l]);
      if (t && x.gate !== 'talent') note(x.name, 'extra: gate ' + x.gate + ' -> talent');
      if (t && ranks.some((r, i) => r[1] !== x.ranks[i][1])) note(x.name, 'extra: level ' + x.ranks[0][1] + ' -> ' + ranks[0][1] + ' (talent row ' + t.r + ')');
      return Object.assign({}, x, { gate: t ? 'talent' : x.gate, talent: t ? t.k : undefined, ranks, level: ranks[0][1] });
    });

    // ---- recommended macros (core): names that are no Forever spell any more are left out
    const have = new Set(merged.map(m => m.name).concat(out.extra[cls].map(x => x.name)));
    const rename = {}; for (const m of merged) if (m.name !== m.seed.name) rename[m.seed.name] = m.name;
    out.core[cls] = {};
    for (const [role, items] of Object.entries(D.core[cls] || {})) {
      out.core[cls][role] = [];
      for (const it of items) {
        const alts = (Array.isArray(it) ? it : [it]).map(n => rename[n] || n);
        const keep = alts.filter(n => have.has(n));
        for (const n of alts) if (!have.has(n)) report.core.push({ cls, role, name: n, what: 'left out (not a Forever spell any more)' });
        if (keep.length) out.core[cls][role].push(Array.isArray(it) ? keep : keep[0]);
      }
    }

    // ---- guides
    const T = E.makeTree(JSON.parse(JSON.stringify(talents)));
    const fixed = REBUILT.rebuilt || {};
    out.guides[cls] = [];
    for (const g0 of D.guides.filter(x => x.cls === cls)) {
      const g = JSON.parse(JSON.stringify(g0));
      const removed = [...new Set(g.order.filter(k => !T.byKey[k]))];
      const counts = E.countsOf(g.order);
      const over = Object.keys(counts).filter(k => T.byKey[k] && counts[k] > T.byKey[k].m);
      const row = { id: g.id, cls, spec: g.spec, points: g.order.length, status: 'OK', what: '' };
      if (!removed.length && !over.length && !E.validateOrder(T, g.order)) {
        row.what = g.order.length ? 'every point still legal' : 'no point order (tips only)';
      } else if (!removed.length && !over.length && E.repairOrder(T, g.order)) {
        g.order = E.repairOrder(T, g.order);
        row.status = 'repaired';
        row.what = 'same points, order repaired (first illegal point: ' + E.validateOrder(T, g0.order).reason + ')';
        g.note = (g.note ? g.note + ' ' : '') + 'Order repaired for WoW Forever\'s live talents (' + RERUN + '): same points, a few moved later.';
      } else if (fixed[g.id]) {
        const r = fixed[g.id];
        const key = n => (byName[n] || { k: '?' + n }).k;
        let order = r.order ? r.order.map(key) : ranksOrder(E, T, Object.fromEntries(Object.entries(r.ranks).map(([n, v]) => [key(n), v])));
        const bad = order.filter(k => !T.byKey[k]);
        let v = bad.length ? { reason: 'unknown ' + bad.join(', ') } : E.validateOrder(T, order);
        let fix = '';
        if (v && !bad.length && r.order && r.repair) { // the page's click order is a point early somewhere; its final ranks are legal
          const rep = E.repairOrder(T, order);
          if (rep) { fix = ' The page\'s click order takes ' + T.byKey[v.key].n + ' one point early; WoWBoxer moved it to the first legal level.'; order = rep; v = null; }
        }
        if (v) { report.problems.push('guides.json ' + g.id + ': ' + v.reason); continue; }
        const why = describe(T, g0.order, removed, over);
        g.order = order;
        g.kind = r.order ? 'exact-order' : 'final-derived';
        g.source = Object.assign({}, g.source, r.source);
        const pts = E.treePoints(T, E.countsOf(order));
        const split = pts.join('/');
        g.spec = T.trees[pts.indexOf(Math.max(...pts))].n;
        g.label = g.spec + ' · ' + r.source.site + (r.source.author ? ' · ' + r.source.author : '') + ' lv ' + r.source.scope + ' ' + split + ' — ' + (r.label || r.source.title || '').slice(0, 44);
        g.note = 'Rebuilt for WoW Forever\'s live talents from ' + r.source.site + (r.source.author ? ' (' + r.source.author + ')' : '') +
          ', updated ' + r.source.updated + ', checked ' + RERUN + ': ' + split + ', ' + order.length + ' points' +
          (r.order ? ' in the page\'s level order.' : ', the page gives final ranks only: order by WoWBoxer (main tree first, rows first).') +
          fix + ' The old version (pre-launch trees) ' + why + '.' + (r.note ? ' ' + r.note : '');
        delete g.priorities;
        row.status = 'rebuilt';
        row.points = order.length;
        row.what = 'old: ' + why + '; now ' + r.source.site + ' ' + r.source.updated + ' (' + split + ')';
      } else {
        // no current source: the starter-build rules (keep what exists, clamp ranks, rows first, nothing invented)
        const keep = [], seen = {};
        for (const k of g.order) { const n = T.byKey[k]; if (!n) continue; seen[k] = (seen[k] || 0) + 1; if (seen[k] <= n.m) keep.push(k); }
        // keep the original order where the rules allow; points that can never be placed (a row or prerequisite
        // they no longer reach) are left out, as Wowhead does when it opens an old link
        const { order, dropped } = placeAll(E, T, keep);
        const why = describe(T, g0.order, removed, over);
        const free = g0.order.length - order.length;
        g.order = order;
        g.note = 'Moved to WoW Forever\'s live talents by WoWBoxer (' + RERUN + '): no updated version of the source was found (it is from ' +
          (g.source.updated || 'before launch') + '). The old version ' + why + '.' + (dropped.length ? ' Left out because they no longer fit: ' + names(T, dropped) + '.' : '') +
          (free > 0 ? ' ' + free + ' point' + (free > 1 ? 's are' : ' is') + ' left for you to place.' : '') + ' Compare it with a current guide.' + (g0.note ? ' Original note: ' + g0.note : '');
        row.status = 'moved';
        row.points = order.length;
        row.what = 'old: ' + why + '; no current source, ' + order.length + '/' + g0.order.length + ' points kept';
        if (!order.length && g0.order.length) row.status = 'broken';
      }
      if (g.order.length && E.validateOrder(T, g.order)) report.problems.push(g.id + ' still illegal');
      row.default = !!g.default;
      report.guides.push(row);
      out.guides[cls].push(g);
    }
    // the class default must be a whole guide: a default that only kept part of its points (no current source) hands
    // over to the fullest current guide of the same spec (exact order first)
    const rows = report.guides.filter(r => r.cls === cls);
    const def = out.guides[cls].find(g => g.default);
    const defRow = def && rows.find(r => r.id === def.id);
    if (def && defRow && (defRow.status === 'moved' || defRow.status === 'broken')) {
      const ok = out.guides[cls].filter(g => g.spec === def.spec && g.order.length && ['OK', 'repaired', 'rebuilt'].includes(rows.find(r => r.id === g.id).status));
      ok.sort((a, b) => (a.kind !== 'exact-order') - (b.kind !== 'exact-order') || b.order.length - a.order.length);
      if (ok[0]) {
        def.default = false; ok[0].default = true;
        defRow.default = false; rows.find(r => r.id === ok[0].id).default = true;
        report.defaults.push({ cls, from: def.id, to: ok[0].id, why: def.id + ' kept ' + def.order.length + ' points only (no current source)' });
      }
    }
  }
  return out;
}

// final ranks -> a point order by the starter-build rules: the main tree first, rows first, every point legal
function ranksOrder(E, T, ranks) {
  const want = [], per = [0, 0, 0];
  for (const [k, n] of Object.entries(ranks)) { const node = T.byKey[k]; if (!node) return [k]; want.push({ node, n }); per[node.t] += n; }
  const main = per.indexOf(Math.max(...per));
  want.sort((a, b) => ((a.node.t !== main) - (b.node.t !== main)) || a.node.r - b.node.r || a.node.t - b.node.t || a.node.c - b.node.c);
  const keys = [];
  for (const w of want) for (let i = 0; i < w.n; i++) keys.push(w.node.k);
  const { order, dropped } = placeAll(E, T, keys);
  return dropped.length ? keys : order; // not placeable: validateOrder reports it
}
function placeAll(E, T, keys) {
  const rest = keys.slice(), order = [], c = Object.create(null);
  for (;;) {
    const i = rest.findIndex(k => !E.addBlocker(T, c, k));
    if (i < 0) break;
    const k = rest.splice(i, 1)[0];
    order.push(k); c[k] = (c[k] || 0) + 1;
  }
  return { order, dropped: rest };
}
function names(T, keys) { return [...new Set(keys)].map(k => (T.byKey[k] || { n: k }).n).join(', '); }
function describe(T, order, removed, over) {
  const parts = [];
  if (removed.length) parts.push('used ' + removed.join(', ') + ' (not in the live tree)');
  if (over.length) { const c = {}; for (const k of order) c[k] = (c[k] || 0) + 1; parts.push('had ' + over.map(k => T.byKey[k].n + ' ' + c[k] + '/' + T.byKey[k].m).join(', ')); }
  if (!parts.length) parts.push('no longer fit the rows/prerequisites');
  return parts.join(' and ');
}

module.exports = { load, BUILD, rowLevel, slugId };
