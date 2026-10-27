/* Loads the vendored companion (data + engine.js) and extracts the kit helpers from app.js verbatim, so the addon is
   generated from and tested against the companion's own code. No DOM is needed: the extracted functions are pure. */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const VENDOR = path.join(__dirname, '..', 'vendor', 'companion');

function load() {
  const D = JSON.parse(fs.readFileSync(path.join(VENDOR, 'app_data.json'), 'utf8'));
  const E = require(path.join(VENDOR, 'engine.js'));
  const appSrc = fs.readFileSync(path.join(VENDOR, 'app.js'), 'utf8');

  // --- extract top-level declarations from app.js by name (function NAME(...) {...} or const NAME = ...;)
  function grab(name) {
    let i = appSrc.search(new RegExp('\\nfunction ' + name + '\\s*\\('));
    if (i >= 0) {
      i += 1;
      let j = appSrc.indexOf('{', i), depth = 0;
      for (; j < appSrc.length; j++) {
        const ch = appSrc[j];
        if (ch === '{') depth++;
        else if (ch === '}') { depth--; if (depth === 0) return appSrc.slice(i, j + 1); }
        else if (ch === "'" || ch === '"' || ch === '`') { // skip strings
          const q = ch; j++;
          while (j < appSrc.length && appSrc[j] !== q) { if (appSrc[j] === '\\') j++; j++; }
        }
      }
      throw new Error('unterminated function ' + name);
    }
    i = appSrc.search(new RegExp('\\nconst ' + name + '\\s*='));
    if (i < 0) throw new Error('not found in app.js: ' + name);
    i += 1;
    // a const runs to the first ';' at depth 0 followed by a newline
    let depth = 0;
    for (let j = i; j < appSrc.length; j++) {
      const ch = appSrc[j];
      if ('([{'.includes(ch)) depth++;
      else if (')]}'.includes(ch)) depth--;
      else if (ch === "'" || ch === '"' || ch === '`') { const q = ch; j++; while (j < appSrc.length && appSrc[j] !== q) { if (appSrc[j] === '\\') j++; j++; } }
      else if (ch === ';' && depth === 0 && appSrc[j + 1] === '\n') return appSrc.slice(i, j + 1);
    }
    throw new Error('unterminated const ' + name);
  }

  const NAMES = ['ENGAGE', 'racialsOf', 'raceOk', 'spellsOf', 'rankAt', 'buildHas', 'learned', 'coreList', 'CAT_ORDER', 'catOrder',
    'kitLists', 'MELEE_CLS', 'isMelee', 'seqHas', 'ctxOf', 'seqOf', 'seqOn', 'seqPlan', 'defaultGuide', 'ROLE_SPEC', 'defaultGuideFor'];
  const src = NAMES.map(grab).join('\n') +
    '\n;({ ENGAGE, racialsOf, raceOk, spellsOf, rankAt, buildHas, learned, coreList, CAT_ORDER, catOrder, kitLists, MELEE_CLS, isMelee, seqHas, ctxOf, seqOf, seqOn, seqPlan, defaultGuide, ROLE_SPEC, defaultGuideFor })';
  const RACES = D.races;
  const RACE = Object.fromEntries(RACES.map(r => [r.k, r]));
  const TREES = Object.create(null); D.classOrder.forEach(c => { TREES[c] = E.makeTree(D.talents[c]); });
  const ctx = vm.createContext({ D, E, RACE, RACES, TREES, SPELLS: D.spells, GUIDES: D.guides, CM: D.classes, Object, Array, Math, String, Number, JSON, Set, isFinite });
  const K = vm.runInContext(src, ctx, { filename: 'app.js (extracted)' });
  return { D, E, K, TREES, RACE, appSrc };
}

module.exports = { load, VENDOR };
