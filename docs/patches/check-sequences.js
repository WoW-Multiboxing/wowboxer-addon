// Checks the proposed v8.5 sequences: every macro <= 255 chars for leader + party1-4 + focus at levels 1-60, and the trio
// classes unchanged. Usage: node docs/patches/check-sequences.js [warrior,rogue,...]  (prints level 20/40/60 macros)
const D = require('../../vendor/companion/app_data.json');
const E = require('./engine-v8.5-proposed.js'), O = require('../../vendor/companion/engine.js');
const has = (cls, L) => n => D.spells.find(s => s.cls === cls && s.name === n && s.level <= L) || null;
const ctxs = [{ leader: true, unit: 'party1' }, ...['party1','party2','party3','party4','focus'].map(u => ({ leader: false, unit: u }))];
let bad = 0, regress = 0;
for (const cls of Object.keys(D.classes)) for (const role of D.classes[cls].roles) for (const tier of ['simple', 'medium', 'advanced']) for (const ctx of ctxs) for (let L = 1; L <= 60; L++) {
  const r = E.buildSequences(cls, role, tier, ctx, has(cls, L), {});
  for (const x of r) if (x.macro.length > 255 || x.tooLong) { bad++; if (bad < 10) console.log('TOO LONG', cls, role, tier, ctx.unit, ctx.leader, L, x.macro.length); }
  if (O.seqSupported(cls)) { const o = O.buildSequences(cls, role, tier, ctx, has(cls, L), {}); if (JSON.stringify(o) !== JSON.stringify(r)) regress++; }
}
console.log('too long:', bad, 'regressions vs current trio:', regress);
const show = process.argv[2];
if (show) for (const cls of show.split(',')) for (const role of D.classes[cls].roles) for (const tier of ['simple', 'medium', 'advanced']) for (const ctx of [ctxs[1], ctxs[0]]) {
  for (const L of [20, 40, 60]) { const r = E.buildSequences(cls, role, tier, ctx, has(cls, L), {}); for (const x of r) console.log(`--- ${cls}/${role}/${tier}/${ctx.leader ? 'leader' : ctx.unit} L${L} ${x.label} [${x.kind}] ${x.macro.length}c ${x.why || ''}\n${x.macro}`); }
}
