#!/usr/bin/env node
/* Exports test vectors from the companion's own JavaScript (vendor/companion/engine.js + kit functions extracted from
   app.js). Used by tests/test_locale.lua and tests/test_share.lua (the companion parity test was replaced by
   tests/test_golden.lua on 2 Nov 2026: the addon is the source of truth).
   Usage: node tools/export_vectors.js [--quick]   (writes tests/vectors/*.json) */
'use strict';
const fs = require('fs');
const path = require('path');
const { load } = require('./companion');

const QUICK = process.argv.includes('--quick');
const OUT = path.join(__dirname, '..', 'tests', 'vectors');
fs.mkdirSync(OUT, { recursive: true });
const { D, E, K, TREES } = load();

// deterministic PRNG (mulberry32)
function rng(seed) { return function () { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const R = rng(20261027);
const pick = a => a[Math.floor(R() * a.length)];
const int = (a, b) => a + Math.floor(R() * (b - a + 1));
const CTX = [{ leader: true, unit: 'party1' }].concat(E.UNITS.map(u => ({ leader: false, unit: u })));
const counts = {};
function write(name, data) { const txt = JSON.stringify(data); fs.writeFileSync(path.join(OUT, name + '.json'), txt); counts[name] = { bytes: txt.length }; }
const racesOf = cls => D.races.filter(r => r.c.includes(cls)).map(r => r.k);
const guidesOf = cls => D.guides.filter(g => g.cls === cls);

// ---------------------------------------------------------------- 1. single-spell macros
{
  const out = [];
  for (const s of D.spells) out.push({ cls: s.cls, id: s.id, out: CTX.map(c => E.makeMacro(s, c)) });
  for (const race of Object.keys(D.racials)) {
    const cls = D.races.find(r => r.k === race).c[0];
    for (const s of K.racialsOf({ race, cls })) out.push({ race, cls, id: s.id, out: CTX.map(c => E.makeMacro(s, c)) });
  }
  out.push({ engage: true, id: K.ENGAGE.id, out: CTX.map(c => E.makeMacro(K.ENGAGE, c)) });
  // string contexts (backwards compatible API)
  const s0 = D.spells.find(s => s.action === 'ranged');
  out.push({ cls: s0.cls, id: s0.id, strCtx: ['focus', 'party3', null, 'bogus'], out: ['focus', 'party3', null, 'bogus'].map(c => E.makeMacro(s0, c)) });
  write('macros', out);
  counts.macros.n = out.reduce((a, x) => a + x.out.length, 0);
}

// ---------------------------------------------------------------- 2. talent rules
{
  const out = [];
  for (const cls of D.classOrder) {
    const T = TREES[cls], keys = T.nodes.map(n => n.k), gs = guidesOf(cls).filter(g => g.order.length);
    const N = QUICK ? 20 : 150;
    for (let i = 0; i < N; i++) {
      const g = pick(gs);
      // a random prefix of a guide, sometimes shuffled or with random keys mixed in
      let order = g.order.slice(0, int(0, g.order.length));
      const mode = int(0, 3);
      if (mode === 1) order = order.slice().sort(() => R() - 0.5);
      if (mode === 2) for (let j = 0; j < 4; j++) order.splice(int(0, order.length), 0, pick(keys));
      const v = { cls, order, validate: E.validateOrder(T, order), repair: E.repairOrder(T, order) };
      const key = R() < 0.05 ? 'no-such-talent' : pick(keys), cap = R() < 0.3 ? int(0, 51) : null;
      v.add = { key, cap, out: E.addPoint(T, order, key, cap) };
      if (!E.validateOrder(T, order)) {
        const rk = R() < 0.1 ? pick(keys) : (order.length ? pick(order) : pick(keys));
        v.remove = { key: rk, out: E.removePoint(T, order, rk) };
        v.state = E.stateBlocker(T, E.countsOf(order));
        v.code = E.encodeBuild(T, cls, order);
        v.decode = E.decodeBuild(TREES, v.code);
      }
      v.guide = g.id;
      v.next = E.guideNext(T, g.order, order);
      v.off = E.offGuide(g.order, order);
      const lim = int(0, 51);
      v.countsLimit = lim; v.counts = Object.assign({}, E.countsOf(order, lim)); v.trees = E.treePoints(T, E.countsOf(order));
      out.push(v);
    }
  }
  const codes = ['', 'WF8.priest.', 'WF7.priest.AAAAA', 'WF8.nope.AB', ' WF8.mage.AB ', 'WF9.mage.A', 'WF8.priest.!!', 'WF8.warrior.' + 'A'.repeat(52), 'garbage', 'WF8.Priest.A'];
  const dec = codes.map(c => ({ code: c, out: E.decodeBuild(TREES, c) }));
  const pts = [];
  for (let t = -1; t <= 6; t++) for (let L = 0; L <= 62; L++) pts.push([L, t, E.pointsAt(L, t), E.firstPointLevel(t), E.levelForPoints(L, t)]);
  write('talents', { ops: out, decode: dec, points: pts });
  counts.talents.n = out.length;
}

// ---------------------------------------------------------------- 3. kit (coreList / kitLists) per level, banded
function band(fn) { const out = []; let prev = null; for (let L = 1; L <= 60; L++) { const v = fn(L), sig = JSON.stringify(v); if (!prev || sig !== prev.sig) { prev = { from: L, to: L, v, sig }; out.push(prev); } else prev.to = L; } return out.map(b => ({ from: b.from, to: b.to, v: b.v })); }
{
  const out = [];
  for (const cls of D.classOrder) for (const role of D.classes[cls].roles) for (const race of racesOf(cls)) {
    const builds = [[]].concat(guidesOf(cls).filter(g => g.order.length).map(g => g.order));
    const bs = QUICK ? builds.slice(0, 2) : builds;
    for (const build of bs) {
      const talented = R() < 0.3 ? int(1, 5) : 0;
      const classSpells = D.spells.filter(s => s.cls === cls && s.action !== 'passive').map(s => s.id);
      const pins = R() < 0.4 ? [pick(classSpells), pick(classSpells)] : [];
      const m = { cls, race, role, talented, build, pins, leader: false, unit: 'party1', seq: 'off', customSeq: [] };
      out.push({ m, core: band(L => K.coreList(m, L).map(s => s.id)),
        lists: band(L => { const x = K.kitLists(Object.assign({}, m, { level: L })); return { p: x.primary.map(s => s.id), o: x.others.map(s => s.id + (s.fromTalent ? '*' : '')) }; }) });
    }
  }
  const guides = [];
  for (const cls of D.classOrder) for (const role of ['tank', 'healer', 'melee', 'ranged']) guides.push({ cls, role, def: K.defaultGuide(cls), out: K.defaultGuideFor(cls, role) });
  write('kit', { members: out, guides });
  counts.kit.n = out.length;
}

// ---------------------------------------------------------------- 4. built-in sequences (seqPlan over levels 1–60)
{
  const out = [];
  for (const cls of ['warlock', 'priest', 'paladin']) for (const role of D.classes[cls].roles) for (const tier of ['simple', 'medium', 'advanced']) {
    const races = racesOf(cls), builds = [[]].concat(guidesOf(cls).filter(g => g.order.length).map(g => g.order));
    for (const c of CTX) for (const tr of (c.leader ? [false, true] : [false])) {
      const bs = QUICK ? builds.slice(0, 2) : builds;
      for (const build of bs) {
        const m = { cls, race: pick(races), role, leader: c.leader, unit: c.unit, talented: R() < 0.2 ? int(1, 5) : 0, build, seq: tier, seqTarget: tr, customSeq: [], pins: [] };
        out.push({ m, plan: K.seqPlan(m).map(b => ({ from: b.from, to: b.to, list: b.list })) });
      }
    }
  }
  // tier off / unsupported classes
  for (const cls of ['mage', 'warrior']) out.push({ m: { cls, race: racesOf(cls)[0], role: D.classes[cls].roles[0], leader: true, unit: 'party1', talented: 0, build: [], seq: 'advanced', seqTarget: false, customSeq: [], pins: [] }, plan: [] });
  for (const o of out) if (!o.plan.length) o.plan = K.seqPlan(o.m).map(b => ({ from: b.from, to: b.to, list: b.list }));
  write('sequences', out);
  counts.sequences.n = out.length;
}

// ---------------------------------------------------------------- 5. custom keys + warnings
{
  const out = [];
  const N = QUICK ? 200 : 3000;
  for (let i = 0; i < N; i++) {
    const cls = pick(D.classOrder), race = pick(racesOf(cls)), role = pick(D.classes[cls].roles), c = pick(CTX);
    const names = D.spells.filter(s => s.cls === cls && s.action !== 'passive' && s.action !== 'autoshot' && (s.ranks || []).length).map(s => s.name);
    const nKeys = int(1, 3), customSeq = [];
    for (let k = 0; k < nKeys; k++) {
      const steps = []; for (let j = int(0, 8); j > 0; j--) steps.push(R() < 0.05 ? 'Not A Spell' : pick(names));
      customSeq.push({ id: 'q' + i + 'x' + k, name: 'Key ' + k, kind: pick(['sequence', 'sequence', 'priority', 'bogus']), aim: pick(['harm', 'harm', 'help', 'nope']),
        steps, filler: R() < 0.8 ? pick(names) : '', fills: pick([1, 2, 3, 4, 5, 6, 0, 7, 2.7, '3', -1]), reset: pick(['combat', 'target/combat', 'combat/12', 'x']) });
    }
    const builds = guidesOf(cls).filter(g => g.order.length);
    const m = { cls, race, role, leader: c.leader, unit: c.unit, talented: 0, build: R() < 0.7 && builds.length ? pick(builds).order : [], seq: R() < 0.3 ? pick(['simple', 'medium', 'advanced']) : 'off', seqTarget: R() < 0.5, customSeq, pins: [] };
    const L = int(1, 60);
    const has = K.seqHas(m, L);
    const warn = customSeq.map(ck => { const sp = (ck.steps || []).map(has).filter(Boolean), f = ck.filler ? has(ck.filler) : null; return E.customWarnings(ck.kind === 'priority' ? 'priority' : 'sequence', sp, f, ck.aim, cls); });
    out.push({ m, L, seq: K.seqOf(m, L), warn });
  }
  write('custom', out);
  counts.custom.n = out.length;
}

console.log(JSON.stringify(counts));
