/* WoW Forever Multibox Companion v8.4 — pure logic (no DOM). Shared by the app and the Node tests.
   Talent rules (Forever, build 1.60.1.70450/70532):
     - one talent point per level 10–60 (51 total); Legacy perk "Talented" rank r moves the first point to level 10-r
       (total stays 51, so it only lowers the level a build needs);
     - row N of a tree opens after (N-1)*5 points in that tree;
     - a talent at the end of an arrow needs the talent at the arrow's start at full rank;
     - a rank can only be removed while every other learned talent still has what it needs. */
(function (root) {
  'use strict';
  const MAX_POINTS = 51;

  function firstPointLevel(talented) { return 10 - Math.max(0, Math.min(5, talented | 0)); }
  function pointsAt(level, talented) {
    const n = level - firstPointLevel(talented) + 1;
    return Math.max(0, Math.min(MAX_POINTS, n));
  }
  function levelForPoint(index, talented) { return firstPointLevel(talented) + index; } // index 0-based
  function levelForPoints(n, talented) { return n <= 0 ? 1 : firstPointLevel(talented) + n - 1; }

  function makeTree(classData) {
    const nodes = classData.nodes;
    const byKey = Object.create(null);
    nodes.forEach((n, i) => { byKey[n.k] = n; n.idx = i; });
    const prereq = Object.create(null), dependents = Object.create(null);
    classData.arrows.forEach(([a, b]) => { prereq[b] = a; (dependents[a] = dependents[a] || []).push(b); });
    return { nodes, byKey, prereq, dependents, trees: classData.trees, arrows: classData.arrows };
  }

  function countsOf(order, limit) {
    const c = Object.create(null);
    const n = limit == null ? order.length : Math.min(limit, order.length);
    for (let i = 0; i < n; i++) c[order[i]] = (c[order[i]] || 0) + 1;
    return c;
  }
  function treePoints(T, counts) {
    const t = [0, 0, 0];
    for (const k in counts) { const n = T.byKey[k]; if (n) t[n.t] += counts[k]; }
    return t;
  }
  function total(counts) { let s = 0; for (const k in counts) s += counts[k]; return s; }

  /** Why a point can't be added (null = allowed). */
  function addBlocker(T, counts, key, cap) {
    const n = T.byKey[key];
    if (!n) return { code: 'unknown', text: 'Unknown talent' };
    const have = counts[key] || 0;
    if (have >= n.m) return { code: 'max', text: n.n + ' is already at max rank' };
    const lim = cap == null ? MAX_POINTS : cap;
    if (total(counts) >= lim) return { code: 'points', text: 'No talent points left' };
    const need = (n.r - 1) * 5, spent = treePoints(T, counts)[n.t];
    if (spent < need) return { code: 'row', text: 'Requires ' + need + ' points in ' + T.trees[n.t].n + ' (you have ' + spent + ')', need, spent };
    const p = T.prereq[key];
    if (p && (counts[p] || 0) < T.byKey[p].m) return { code: 'prereq', text: 'Requires ' + T.byKey[p].m + ' point' + (T.byKey[p].m > 1 ? 's' : '') + ' in ' + T.byKey[p].n, prereq: p };
    return null;
  }

  /** Is a final allocation legal (independent of order)? Returns null or a reason. */
  function stateBlocker(T, counts) {
    if (total(counts) > MAX_POINTS) return 'More than ' + MAX_POINTS + ' points';
    for (const k in counts) {
      if (!counts[k]) continue;
      const n = T.byKey[k];
      if (!n) return 'Unknown talent ' + k;
      if (counts[k] > n.m) return n.n + ' above max rank';
      let below = 0;
      for (const kk in counts) { const m = T.byKey[kk]; if (m && m.t === n.t && m.r < n.r) below += counts[kk]; }
      if (below < (n.r - 1) * 5) return n.n + ' (row ' + n.r + ') needs ' + (n.r - 1) * 5 + ' points in the rows above';
      const p = T.prereq[k];
      if (p && (counts[p] || 0) < T.byKey[p].m) return n.n + ' needs ' + T.byKey[p].n + ' at full rank';
    }
    return null;
  }

  function validateOrder(T, order) {
    const c = Object.create(null);
    for (let i = 0; i < order.length; i++) {
      const b = addBlocker(T, c, order[i]);
      if (b) return { index: i, key: order[i], reason: b.text };
      c[order[i]] = (c[order[i]] || 0) + 1;
    }
    return null;
  }

  /** Re-sequence an order so every point is legal when taken, keeping the original order where the rules allow. */
  function repairOrder(T, order) {
    const rest = order.slice(), out = [], c = Object.create(null);
    while (rest.length) {
      let i = 0;
      for (; i < rest.length; i++) if (!addBlocker(T, c, rest[i])) break;
      if (i === rest.length) return null;
      const k = rest.splice(i, 1)[0];
      out.push(k); c[k] = (c[k] || 0) + 1;
    }
    return out;
  }

  /** Add a point. Returns {order} or {error}. */
  function addPoint(T, order, key, cap) {
    const b = addBlocker(T, countsOf(order), key, cap);
    if (b) return { error: b.text, code: b.code };
    return { order: order.concat([key]) };
  }

  /** Remove the last point of a talent. Returns {order} or {error}. */
  function removePoint(T, order, key) {
    const idx = order.lastIndexOf(key);
    if (idx < 0) return { error: 'No points in ' + (T.byKey[key] ? T.byKey[key].n : key) };
    const next = order.slice(0, idx).concat(order.slice(idx + 1));
    const c = countsOf(next);
    // dependents that rely on this talent being maxed
    for (const d of (T.dependents[key] || [])) {
      if ((c[d] || 0) > 0 && (c[key] || 0) < T.byKey[key].m) return { error: T.byKey[d].n + ' requires ' + T.byKey[key].n + ' at full rank' };
    }
    const sb = stateBlocker(T, c);
    if (sb) return { error: "Can't remove: " + sb };
    const fixed = repairOrder(T, next);
    if (!fixed) return { error: "Can't remove: the remaining build would be invalid" };
    return { order: fixed };
  }

  /** Guide helpers */
  function guideNext(T, guideOrder, order) {
    // first guide point not yet covered by the user's build (by talent counts)
    const mine = countsOf(order), need = Object.create(null);
    for (let i = 0; i < guideOrder.length; i++) {
      const k = guideOrder[i];
      need[k] = (need[k] || 0) + 1;
      if (need[k] > (mine[k] || 0)) return { index: i, key: k, rank: need[k] };
    }
    return null;
  }
  function offGuide(guideOrder, order) {
    const g = countsOf(guideOrder), mine = countsOf(order), out = Object.create(null);
    for (const k in mine) if (mine[k] > (g[k] || 0)) out[k] = mine[k] - (g[k] || 0);
    return out;
  }
  function compareCounts(T, a, b) {
    const keys = new Set(Object.keys(a).concat(Object.keys(b)));
    const rows = [];
    keys.forEach(k => { if ((a[k] || 0) !== (b[k] || 0) && T.byKey[k]) rows.push({ key: k, a: a[k] || 0, b: b[k] || 0 }); });
    rows.sort((x, y) => T.byKey[x.key].t - T.byKey[y.key].t || T.byKey[x.key].r - T.byKey[y.key].r || T.byKey[x.key].c - T.byKey[y.key].c);
    let shared = 0; keys.forEach(k => { shared += Math.min(a[k] || 0, b[k] || 0); });
    return { rows, shared };
  }

  /** Compact build code: WF7.<cls>.<chars>, one char per point (node index). */
  const ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  function encodeBuild(T, cls, order) { return 'WF8.' + cls + '.' + order.map(k => ALPHA[T.byKey[k].idx]).join(''); }
  function decodeBuild(classes, code) {
    const m = /^WF[78]\.([a-z]+)\.([A-Za-z0-9_-]{0,51})$/.exec(String(code || '').trim());
    if (m && !Object.prototype.hasOwnProperty.call(classes, m[1])) return { error: 'Unknown class in code' };
    if (!m) return { error: 'Not a valid WF7 build code' };
    const T = classes[m[1]];
    const order = [];
    for (const ch of m[2]) { const i = ALPHA.indexOf(ch); if (i < 0 || !T.nodes[i]) return { error: 'Unknown talent in code' }; order.push(T.nodes[i].k); }
    const v = validateOrder(T, order);
    if (v) return { error: 'Build code breaks talent rules at point ' + (v.index + 1) + ': ' + v.reason };
    return { cls: m[1], order };
  }

  /* ---------------- Macros ----------------
     Squad-aware rules (manual multiboxing, one key press per client):
       - The squad LEADER plays normally: hostile mouseover > own target; heals: friendly mouseover > friendly target > self.
       - FOLLOWERS assist the leader through a unit (party1-4 or focus): hostile mouseover > leader's target > own target;
         heals/buffs: friendly mouseover > leader > self.
       - Melee abilities always start repeat-safe auto attack (/startattack never toggles it off); Auto Shot uses "!" so a
         second press never cancels it.
       - Pet classes send the pet to the same unit as the spell (/petattack); crowd control never starts attacks or pets.
     Every macro must be <= 255 characters and uses the spell name without rank. Single-spell keys never use /castsequence;
     sequences are a separate, opt-in feature (buildSequences below). */
  const MACRO_LIMIT = 255;
  const UNITS = ['party1', 'party2', 'party3', 'party4', 'focus'];
  function units(mode) { // backwards compatible: units('focus') / units('party1')
    const u = UNITS.includes(mode) ? mode : 'party1';
    return { main: u, mainTarget: u + 'target' };
  }
  function ctxOf(ctx) {
    if (typeof ctx === 'string' || ctx == null) return { leader: false, unit: ctx || 'party1' };
    return { leader: !!ctx.leader, unit: UNITS.includes(ctx.unit) ? ctx.unit : 'party1' };
  }
  function makeMacro(s, ctxIn) {
    const out = buildMacro(s, ctxIn);
    // WoW macros max out at 255 characters: drop the (optional) spell name after #showtooltip if needed
    return out.length > MACRO_LIMIT ? out.replace('#showtooltip ' + s.name + '\n', '#showtooltip\n') : out;
  }
  function buildMacro(s, ctxIn) {
    const ctx = ctxOf(ctxIn), u = units(ctx.unit), name = s.name, title = '#showtooltip ' + name;
    const harm = ctx.leader ? '[@mouseover,harm,nodead][harm,nodead]' : '[@mouseover,harm,nodead][@' + u.mainTarget + ',harm,nodead][harm,nodead]';
    const help = ctx.leader ? '[@mouseover,help,nodead][help,nodead][@player]' : '[@mouseover,help,nodead][@' + u.main + ',help,nodead][@player]';
    const meleeStart = ctx.leader ? '/startattack [harm,nodead]' : '/startattack ' + harm;
    const meleeCast = ctx.leader ? '[harm,nodead]' : harm;
    switch (s.action) {
      case 'engage': return '#showtooltip Attack\n' + meleeStart;
      case 'melee': return title + '\n' + meleeStart + '\n/cast ' + meleeCast + ' ' + name;
      case 'melee-pet': return title + '\n' + meleeStart + '\n/petattack ' + harm + '\n/cast ' + meleeCast + ' ' + name;
      case 'melee-cc': return title + '\n' + meleeStart + '\n/cast ' + harm + ' ' + name;
      case 'opener': return title + '\n/cast ' + meleeCast + ' ' + name + '\n' + meleeStart;
      case 'aoe-melee': return title + '\n' + meleeStart + '\n/cast ' + name;
      case 'dual': return title + '\n' + meleeStart + '\n/cast [@mouseover,harm,nodead][@mouseover,help,nodead]' + (ctx.leader ? '' : '[@' + u.mainTarget + ',harm,nodead]') + '[harm,nodead][help,nodead][@player] ' + name;
      case 'ranged': return title + '\n/cast ' + harm + ' ' + name;
      case 'autoshot': return title + '\n/petattack ' + harm + '\n/cast ' + harm + ' !' + name;
      case 'petattack': return title + '\n/petattack ' + harm + '\n/cast ' + harm + ' ' + name;
      case 'friendlymain': return title + '\n/cast ' + help + ' ' + name;
      case 'friendlyself': return title + '\n/cast [@mouseover,help,nodead][help,nodead][@player] ' + name;
      case 'friendlytarget': return title + '\n/cast [@mouseover,help,nodead][help,nodead] ' + name;
      case 'petheal': return title + '\n/cast [@pet,exists,nodead] ' + name;
      case 'resurrection': return title + '\n/cast [@mouseover,help,dead][help,dead] ' + name;
      case 'hostile': return title + '\n/cast [@mouseover,harm,nodead][harm,nodead] ' + name;
      case 'passive': return '';
      default: return title + '\n/cast ' + name;
    }
  }
  const OFFENSIVE_MELEE = ['melee', 'melee-pet', 'melee-cc', 'aoe-melee', 'dual', 'engage', 'opener'];
  const OFFENSIVE_PAL = OFFENSIVE_MELEE;


  /* ---------------- Sequences (opt-in, v8.3) ----------------
     One key press = one cast, written with WoW's own macro commands (no addons, no broadcasting).
       - kind 'sequence': /castsequence [targeting] reset=combat <openers/DoTs>, <filler> x n. The loop length is sized so the
         shortest DoT is roughly refreshed when the list starts over, and so a spell with a cooldown is ready again by then.
         /castsequence does not move on when a cast fails (cooldown, range, line of sight): that is why long cooldowns stay
         out of sequences and why the filler count is chosen from cast times.
       - kind 'priority': several /cast lines, highest priority first. Used where every ability has a cooldown (Paladin);
         a /castsequence would stall on them. Lines that cannot be cast are skipped by the game and the next line is tried.
       - Steps whose spell is not learned yet are left out, so the macro grows with the character's level.
     Tiers: simple (opener + filler), medium (+ DoT / cooldown), advanced (all DoTs / talents). All nine classes (v8.5). */
  const SEQ_TIERS = ['off', 'simple', 'medium', 'advanced'];
  const SEQ_MAX_FILL = 4;
  // step: string = spell name, array = first learned of the alternatives; k: 'dot' | 'cd' | 'nuke' (default nuke)
  const SEQ = {
    warlock: {
      _all: [
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm', pet: true,
          tiers: {
            simple: { steps: [{ s: 'Immolate', k: 'dot' }], filler: ['Shadow Bolt'] },
            medium: { steps: [{ s: 'Corruption', k: 'dot' }, { s: 'Immolate', k: 'dot' }], filler: ['Shadow Bolt'] },
            advanced: { steps: [{ s: 'Bane of Agony', k: 'dot' }, { s: 'Corruption', k: 'dot' }, { s: 'Siphon Life', k: 'dot' }, { s: 'Immolate', k: 'dot' }], filler: ['Shadow Bolt'] } } }] },
    priest: {
      _all: [
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Mind Blast', k: 'cd' }], filler: ['Smite'] },
            medium: { steps: [{ s: 'Shadow Word: Pain', k: 'dot' }, { s: 'Mind Blast', k: 'cd' }], filler: ['Smite'] },
            advanced: { steps: [{ s: 'Shadow Word: Pain', k: 'dot' }, { s: 'Mind Blast', k: 'cd' }, { s: 'Holy Fire' }], filler: ['Smite'] } } },
        { id: 'heal', label: 'Heal', kind: 'sequence', aim: 'help', reset: 'combat/12', fixedFill: 2,
          tiers: {
            simple: { steps: [{ s: 'Renew', k: 'hot' }], filler: ['Greater Heal', 'Heal', 'Lesser Heal'] },
            medium: { steps: [{ s: 'Renew', k: 'hot' }], filler: ['Greater Heal', 'Heal', 'Lesser Heal'] },
            advanced: { steps: [{ s: 'Renew', k: 'hot' }], filler: ['Greater Heal', 'Heal', 'Lesser Heal'] } } }] },
    paladin: {
      tank: [
        { id: 'dps', label: 'Threat', kind: 'priority', aim: 'melee', tip: 'Holy Strike',
          tiers: {
            simple: { steps: ['Holy Strike', 'Judgement'] },
            medium: { steps: [{ s: 'Holy Shield', self: true }, 'Hammer of the Righteous', 'Holy Strike', 'Judgement'] },
            advanced: { steps: [{ s: 'Holy Shield', self: true }, 'Hammer of the Righteous', 'Holy Strike', 'Judgement', { s: 'Consecration', self: true }] } } }],
      _all: [
        { id: 'dps', label: 'Damage', kind: 'priority', aim: 'melee', tip: 'Holy Strike',
          tiers: {
            simple: { steps: ['Holy Strike', 'Judgement'] },
            medium: { steps: ['Hammer of Wrath', 'Holy Strike', 'Judgement'] },
            advanced: { steps: ['Hammer of Wrath', 'Exorcism', 'Holy Strike', 'Judgement', { s: 'Consecration', self: true }] } } }] },
    warrior: {
      tank: [
        { id: 'dps', label: 'Threat', kind: 'priority', aim: 'melee', tip: 'Sunder Armor',
          tiers: {
            simple: { steps: ['Revenge', 'Sunder Armor'] },
            medium: { steps: ['Shield Slam', 'Revenge', 'Sunder Armor'] },
            advanced: { steps: ['Shield Slam', 'Revenge', { s: 'Thunder Clap', self: true }, 'Sunder Armor'] } } }],
      _all: [
        { id: 'dps', label: 'Damage', kind: 'priority', aim: 'melee', tip: 'Mortal Strike',
          tiers: {
            simple: { steps: ['Execute', 'Overpower', ['Mortal Strike', 'Bloodthirst']] },
            medium: { steps: ['Execute', 'Overpower', ['Mortal Strike', 'Bloodthirst'], 'Victory Rush'] },
            advanced: { steps: ['Execute', 'Overpower', ['Mortal Strike', 'Bloodthirst'], { s: 'Whirlwind', self: true }, 'Victory Rush', 'Slam'] } } }] },
    rogue: {
      _all: [
        { id: 'dps', label: 'Combo', kind: 'sequence', aim: 'harm', startattack: true, allowDup: true,
          tiers: {
            simple: { steps: [{ s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: 'Eviscerate' }] },
            medium: { steps: [{ s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: 'Slice and Dice' }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: 'Eviscerate' }] },
            advanced: { steps: [{ s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: 'Slice and Dice' }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: ['Hemorrhage', 'Sinister Strike'] }, { s: 'Eviscerate' }] } } }] },
    hunter: {
      _all: [
        { id: 'dps', label: 'Shots', kind: 'priority', aim: 'ranged', pet: true, autoshot: true, tip: 'Arcane Shot',
          tiers: {
            simple: { steps: ['Arcane Shot'] },
            medium: { steps: ['Arcane Shot', 'Aimed Shot'] },
            advanced: { steps: ['Aimed Shot', 'Arcane Shot', 'Multi-Shot'] } } }] },
    mage: {
      _all: [
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Fire Blast', k: 'cd' }], filler: ['Frostfire Bolt', 'Frostbolt', 'Fireball'] },
            medium: { steps: [{ s: 'Fire Blast', k: 'cd' }, { s: 'Arcane Wrath', k: 'cd' }], filler: ['Frostfire Bolt', 'Frostbolt', 'Fireball'] },
            advanced: { steps: [{ s: 'Pyroblast' }, { s: 'Fire Blast', k: 'cd' }, { s: 'Arcane Wrath', k: 'cd' }], filler: ['Frostfire Bolt', 'Frostbolt', 'Fireball'] } } }] },
    shaman: {
      melee: [
        { id: 'dps', label: 'Damage', kind: 'priority', aim: 'melee', tip: 'Stormstrike',
          tiers: {
            simple: { steps: ['Stormstrike', 'Earth Shock'] },
            medium: { steps: ['Stormstrike', ['Flame Shock', 'Earth Shock']] },
            advanced: { steps: ['Stormstrike', ['Flame Shock', 'Earth Shock'], { s: 'Fire Nova', self: true }] } } }],
      healer: [
        { id: 'heal', label: 'Heal', kind: 'sequence', aim: 'help', reset: 'combat/12', fixedFill: 2,
          tiers: {
            simple: { steps: [{ s: 'Riptide', k: 'hot' }], filler: ['Healing Wave'] },
            medium: { steps: [{ s: 'Riptide', k: 'hot' }], filler: ['Healing Wave'] },
            advanced: { steps: [{ s: 'Riptide', k: 'hot' }, { s: 'Chain Heal' }], filler: ['Healing Wave'] } } },
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Flame Shock', k: 'dot' }], filler: ['Lightning Bolt'] },
            medium: { steps: [{ s: 'Flame Shock', k: 'dot' }], filler: ['Lightning Bolt'] },
            advanced: { steps: [{ s: 'Flame Shock', k: 'dot' }], filler: ['Lightning Bolt'] } } }],
      _all: [
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Flame Shock', k: 'dot' }], filler: ['Lightning Bolt'] },
            medium: { steps: [{ s: 'Flame Shock', k: 'dot' }, { s: 'Lava Burst', k: 'cd' }], filler: ['Lightning Bolt'] },
            advanced: { steps: [{ s: 'Flame Shock', k: 'dot' }, { s: 'Lava Burst', k: 'cd' }, { s: 'Chain Lightning', k: 'cd' }], filler: ['Lightning Bolt'] } } }] },
    druid: {
      tank: [
        { id: 'dps', label: 'Threat', kind: 'priority', aim: 'melee', tip: 'Swipe',
          tiers: {
            simple: { steps: ['Primal Bite', 'Swipe'] },
            medium: { steps: ['Primal Bite', ['Lacerate', 'Swipe']] },
            advanced: { steps: ['Primal Bite', ['Lacerate', 'Swipe']] } } }],
      melee: [
        { id: 'dps', label: 'Combo', kind: 'sequence', aim: 'harm', startattack: true, allowDup: true,
          tiers: {
            simple: { steps: [{ s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: ['Ferocious Bite', 'Rip'] }] },
            medium: { steps: [{ s: 'Rake', k: 'dot' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: ['Ferocious Bite', 'Rip'] }] },
            advanced: { steps: [{ s: 'Rake', k: 'dot' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Rip' }, { s: 'Rake', k: 'dot' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: 'Claw' }, { s: ['Ferocious Bite', 'Rip'] }] } } }],
      healer: [
        { id: 'heal', label: 'Heal', kind: 'sequence', aim: 'help', reset: 'combat/12', fixedFill: 2,
          tiers: {
            simple: { steps: [{ s: 'Rejuvenation', k: 'hot' }], filler: ['Healing Touch'] },
            medium: { steps: [{ s: 'Rejuvenation', k: 'hot' }, { s: 'Regrowth', k: 'hot' }], filler: ['Healing Touch'] },
            advanced: { steps: [{ s: 'Rejuvenation', k: 'hot' }, { s: 'Wild Growth', k: 'cd' }, { s: 'Regrowth', k: 'hot' }], filler: ['Healing Touch'] } } },
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Moonfire', k: 'dot' }], filler: ['Wrath'] },
            medium: { steps: [{ s: 'Moonfire', k: 'dot' }], filler: ['Wrath'] },
            advanced: { steps: [{ s: 'Moonfire', k: 'dot' }], filler: ['Wrath'] } } }],
      _all: [
        { id: 'dps', label: 'Damage', kind: 'sequence', aim: 'harm',
          tiers: {
            simple: { steps: [{ s: 'Moonfire', k: 'dot' }], filler: ['Wrath'] },
            medium: { steps: [{ s: 'Moonfire', k: 'dot' }, { s: 'Insect Swarm', k: 'dot' }], filler: ['Wrath'] },
            advanced: { steps: [{ s: 'Insect Swarm', k: 'dot' }, { s: 'Moonfire', k: 'dot' }], filler: ['Starfire', 'Wrath'] } } }] },
  };
  // Kept out on purpose: Conflagrate (fails without Immolate on the target, which would hold the sequence), Power Word: Shield
  // (Weakened Soul), channels, and cooldowns over 12 s. They stay on their own keys.
  const CHANNEL_SEC = { 'Mind Flay': 3 };   // channels are never used as fillers: a second key press would clip them
  function seqSupported(cls) { return Object.prototype.hasOwnProperty.call(SEQ, cls); }
  function castSec(s, which) {
    if (CHANNEL_SEC[s.name]) return CHANNEL_SEC[s.name];
    const rk = (s.ranks || []), r = which === 'first' ? rk[0] : rk[rk.length - 1];
    const m = /([\d.]+)\s*sec/.exec((r && r.cast) || '');
    return Math.max(1.5, m && !/channel/i.test(r.cast) ? parseFloat(m[1]) : 1.5);
  }
  function cdSec(s) {
    const r = (s.ranks || [])[0], m = /([\d.]+)\s*(sec|min)/.exec((r && r.cd) || '');
    return m ? parseFloat(m[1]) * (m[2] === 'min' ? 60 : 1) : 0;
  }
  function durSec(s) {
    const rk = s.ranks || [], tx = (rk[rk.length - 1] || {}).tx || '';
    const m = /(?:over|Lasts)\s+([\d.]+)\s*sec/.exec(tx);
    return m ? parseFloat(m[1]) : 0;
  }
  function pickSpell(alts, has) { const list = Array.isArray(alts) ? alts : [alts]; for (const n of list) { const s = has(n); if (s) return s; } return null; }
  function seqDefs(cls, role) { const c = SEQ[cls]; return c ? (c[role] || c._all || []) : []; }

  /** Targeting for a sequence line. lvl 0 = full, 1 = without the own-target fallback, 2 = leader's target only (followers). */
  function aimFor(def, ctx, lvl) {
    const u = units(ctx.unit);
    if (def.aim === 'help') {
      if (ctx.leader) return lvl === 0 ? '[@mouseover,help,nodead][help,nodead][@player]' : '[help,nodead][@player]';
      return lvl < 2 ? '[@mouseover,help,nodead][@' + u.main + ',help,nodead][@player]' : '[@' + u.main + ',help,nodead][@player]';
    }
    if (ctx.leader) return lvl < 2 ? '[@mouseover,harm,nodead][harm,nodead]' : '[harm,nodead]';
    return ['[@mouseover,harm,nodead][@' + u.mainTarget + ',harm,nodead][harm,nodead]', '[@mouseover,harm,nodead][@' + u.mainTarget + ',harm,nodead]', '[@' + u.mainTarget + ',harm,nodead]'][lvl];
  }

  /** Build the sequence keys for one character. has(name) -> learned spell object or null. opts: {targetReset} */
  function buildSequences(cls, role, tier, ctxIn, has, opts) {
    if (!SEQ_TIERS.includes(tier) || tier === 'off' || !seqSupported(cls)) return [];
    const ctx = ctxOf(ctxIn), o = opts || {};
    return seqDefs(cls, role).map(def => (def.kind === 'priority' ? buildPriority : buildCastSequence)(def, def.tiers[tier], ctx, has, o)).filter(Boolean);
  }

  function buildCastSequence(def, t, ctx, has, o) {
    const steps = [];
    t.steps.forEach(st => { const s = pickSpell(st.s, has); if (s && (def.allowDup || !steps.some(x => x.s === s))) steps.push({ s, k: st.k || 'nuke', consumes: st.consumes }); });
    const filler = pickSpell(t.filler, has);
    if (!filler && !steps.length) return null;
    const names = steps.map(x => x.s.name);
    // loop sizing: refresh the shortest DoT/HoT, and never come back to a cooldown before it is ready
    const pre = steps.reduce((a, x) => a + castSec(x.s, 'last'), 0), preFast = steps.reduce((a, x) => a + castSec(x.s, 'first'), 0);
    let n = 0, why = '', need = 1;
    if (filler) {
      const consumed = steps.filter(x => x.consumes).map(x => x.consumes);
      const dots = steps.filter(x => (x.k === 'dot' || x.k === 'hot') && !consumed.includes(x.s.name)).map(x => durSec(x.s)).filter(Boolean);
      const cds = steps.filter(x => x.k === 'cd').map(x => cdSec(x.s)).filter(Boolean);
      const fc = castSec(filler, 'last'), fcFast = castSec(filler, 'first');
      if (!steps.length) n = 1;
      else if (def.fixedFill) n = def.fixedFill;
      else {
        if (dots.length) { const d = Math.min.apply(null, dots); n = Math.max(1, Math.round((d - pre) / fc)); why = 'about every ' + d + ' s'; }
        if (cds.length) { const c = Math.max.apply(null, cds); need = Math.max(1, Math.ceil((c - preFast) / fcFast)); if (need > n) { n = need; why = need <= SEQ_MAX_FILL ? 'cooldown-safe' : ''; } }
      }
      n = Math.max(1, Math.min(def.fixedFill ? 6 : SEQ_MAX_FILL, n)); need = Math.min(need, n);
    }
    // reset=target only helps a character whose own target changes: the leader. Followers cast on the leader's target.
    const reset = def.reset || (o.targetReset && ctx.leader ? 'target/combat' : 'combat');
    const make = (lvl, nFill) => {
      const aim = aimFor(def, ctx, lvl), list = names.concat(filler ? Array(nFill).fill(filler.name) : []);
      let txt = '#showtooltip\n';
      if (def.startattack) txt += '/startattack ' + aim + '\n';
      if (def.pet) txt += '/petattack ' + aim + '\n';
      if (list.length === 1) return txt + '/cast ' + aim + ' ' + list[0];
      return txt + '/castsequence ' + aim + ' reset=' + reset + ' ' + list.join(', ');
    };
    // fit 255 characters: (1) drop the own-target fallback, (2) the leader's target only, then (3) fewer fillers,
    // but never fewer than a cooldown in the loop needs
    let level = 0, fill = n, macro = make(0, fill);
    for (const lv of [1, 2]) if (macro.length > MACRO_LIMIT && aimFor(def, ctx, lv) !== aimFor(def, ctx, level)) { level = lv; macro = make(lv, fill); }
    while (macro.length > MACRO_LIMIT && fill > need) { fill--; macro = make(level, fill); }
    const single = names.length + (filler ? fill : 0) === 1;
    const loopSec = Math.round((pre + (filler ? fill * castSec(filler, 'last') : 0)) * 10) / 10;
    if (fill < n && why.startsWith('about')) why = '';
    return { id: def.id, label: def.label, base: 'sequence', fixedReset: !!def.reset, kind: single ? 'single' : 'sequence', spells: names.concat(filler ? [filler.name] : []), filler: filler ? filler.name : null, fills: filler ? fill : 0,
      reset, loopSec, why, macro, compact: level > 0 || fill < n, tooLong: macro.length > MACRO_LIMIT };
  }

  function buildPriority(def, t, ctx, has) {
    const spells = [], self = new Set();
    t.steps.forEach(n => { const o = typeof n === 'object' && !Array.isArray(n) ? n : { s: n }, s = pickSpell(o.s, has); if (s && !spells.includes(s)) { spells.push(s); if (o.self) self.add(s); } });
    const u = units(ctx.unit);
    const tipName = spells.some(s => s.name === def.tip) ? def.tip : (spells[0] ? spells[0].name : 'Attack');
    const make = (lvl, list) => {
      const aim = ctx.leader ? (def.aim === 'melee' ? '' : '[@mouseover,harm,nodead][harm,nodead] ') : (lvl === 0 ? '[@' + u.mainTarget + ',harm,nodead][harm,nodead] ' : '[@' + u.mainTarget + ',harm,nodead] ');
      const cond = aim.trim() || '[harm,nodead]';
      let head = '#showtooltip ' + tipName;
      if (def.aim === 'melee') head += '\n/startattack ' + cond;
      if (def.pet) head += '\n/petattack ' + cond;
      return head + list.map(s => '\n/cast ' + (self.has(s) ? '[combat] ' : aim) + s.name).join('') + (def.autoshot ? '\n/cast ' + aim + '!Auto Shot' : '');
    };
    if (!spells.length) {
      const c0 = ctx.leader ? '[harm,nodead]' : '[@' + u.mainTarget + ',harm,nodead][harm,nodead]';
      if (def.autoshot) return { id: def.id, label: def.label, base: 'priority', kind: 'engage', spells: [], macro: '#showtooltip Auto Shot\n/petattack ' + c0 + '\n/cast ' + c0 + ' !Auto Shot', compact: false, tooLong: false };
      if (def.aim !== 'melee') return null;
      return { id: def.id, label: def.label, base: 'priority', kind: 'engage', spells: [], macro: '#showtooltip Attack\n/startattack ' + c0, compact: false, tooLong: false };
    }
    let list = spells.slice(), level = 0, macro = make(0, list);
    if (macro.length > MACRO_LIMIT && !ctx.leader) { level = 1; macro = make(1, list); }
    while (macro.length > MACRO_LIMIT && list.length > 1) { list = list.slice(0, -1); macro = make(level, list); }
    return { id: def.id, label: def.label, base: 'priority', kind: list.length === 1 ? 'single' : 'priority', spells: list.map(s => s.name), macro, compact: level > 0 || list.length < spells.length, tooLong: macro.length > MACRO_LIMIT };
  }


  /* ---------------- Custom sequences (v8.4) ----------------
     The player builds their own key from learned spells. Same targeting, pet and 255-character rules as the built-in keys,
     plus warnings for things that make a /castsequence wait (cooldowns, channels, Conflagrate, Power Word: Shield). */
  const CUSTOM_KINDS = ['sequence', 'priority'], CUSTOM_AIMS = ['harm', 'help'], CUSTOM_RESETS = ['combat', 'target/combat', 'combat/12'];
  const PET_CLASSES = ['warlock', 'hunter'], MELEE_CLASSES = ['warrior', 'rogue', 'paladin'];
  const CHANNELS = ['Mind Flay', 'Drain Life', 'Drain Soul', 'Drain Mana', 'Health Funnel', 'Arcane Missiles', 'Evocation', 'Hurricane', 'Tranquility', 'Blizzard', 'Rain of Fire', 'Volley', 'Hellfire', 'Wrack'];
  const STALLERS = { 'Conflagrate': 'needs your Immolate on the target; without it the sequence waits here', 'Power Word: Shield': 'Weakened Soul blocks it for 15 s on the same target, so the sequence waits here' };
  const NO_TARGET = ['self', 'aoe-melee', 'ground', 'petself'];
  /** opts.melee: the character fights in melee (adds /startattack to enemy keys). */
  function buildCustom(cls, c, ctxIn, has, opts) {
    const ctx = ctxOf(ctxIn), id = 'c' + c.id, aim = CUSTOM_AIMS.includes(c.aim) ? c.aim : 'harm';
    const pet = PET_CLASSES.includes(cls) && aim === 'harm';
    if (c.kind === 'priority') {
      const spells = []; (c.steps || []).forEach(n => { const s = has(n); if (s && !spells.includes(s)) spells.push(s); });
      if (!spells.length) return { id, label: c.name, custom: true, base: 'priority', kind: 'empty', spells: [], macro: '', compact: false, tooLong: false };
      const melee = ((opts && opts.melee) || MELEE_CLASSES.includes(cls)) && aim === 'harm', def = { aim };
      const make = (lvl, list) => {
        const a = aimFor(def, ctx, lvl);
        let txt = '#showtooltip\n';
        if (melee) txt += '/startattack ' + a + '\n';
        if (pet) txt += '/petattack ' + a + '\n';
        return txt + list.map(s => '/cast ' + (NO_TARGET.includes(s.action) ? '[combat] ' : a + ' ') + s.name).join('\n');
      };
      let level = 0, list = spells.slice(), macro = make(0, list);
      for (const lv of [1, 2]) if (macro.length > MACRO_LIMIT && aimFor(def, ctx, lv) !== aimFor(def, ctx, level)) { level = lv; macro = make(lv, list); }
      while (macro.length > MACRO_LIMIT && list.length > 1) { list = list.slice(0, -1); macro = make(level, list); }
      return { id, label: c.name, custom: true, base: 'priority', kind: list.length === 1 ? 'single' : 'priority', spells: list.map(s => s.name), macro, compact: level > 0 || list.length < spells.length, tooLong: macro.length > MACRO_LIMIT };
    }
    const fills = Math.max(1, Math.min(6, c.fills | 0 || 1));
    const def = { id, label: c.name, kind: 'sequence', aim, pet, startattack: ((opts && opts.melee) || MELEE_CLASSES.includes(cls)) && aim === 'harm', reset: CUSTOM_RESETS.includes(c.reset) ? c.reset : 'combat', fixedFill: fills, allowDup: true };
    let steps = (c.steps || []).filter(n => has(n)), r = buildCastSequence(def, { steps: steps.map(n => ({ s: n })), filler: c.filler ? [c.filler] : [] }, ctx, has, {});
    while (r && r.tooLong && steps.length > 1) { steps = steps.slice(0, -1); r = buildCastSequence(def, { steps: steps.map(n => ({ s: n })), filler: c.filler ? [c.filler] : [] }, ctx, has, {}); if (r) r.compact = true; }
    if (!r) return { id, label: c.name, custom: true, base: 'sequence', kind: 'empty', spells: [], macro: '', compact: false, tooLong: false };
    return Object.assign(r, { custom: true, why: '' });
  }
  /** Plain-language warnings for a custom key. spells: learned spell objects in key order (filler last for sequences). */
  const FRIENDLY_ACTIONS = ['friendlymain', 'friendlyself', 'friendlytarget', 'resurrection', 'petheal'];
  const HOSTILE_ACTIONS = ['hostile', 'ranged', 'melee', 'melee-pet', 'melee-cc', 'opener', 'petattack', 'autoshot', 'aoe-melee'];
  function customWarnings(kind, spells, filler, aim, cls) {
    const out = [], all = spells.concat(filler ? [filler] : []);
    spells.forEach(s => {
      if (STALLERS[s.name]) out.push(s.name + ' ' + STALLERS[s.name] + '.');
      else if (kind === 'sequence' && cdSec(s) > 12) out.push(s.name + ' has a ' + cdSec(s) + ' s cooldown: the sequence waits until it is ready. Better on its own key.');
      if (CHANNELS.includes(s.name)) out.push(s.name + ' is channelled: pressing the key again cuts it short.');
      if (s.action === 'ground') out.push(s.name + ' needs a click on the ground after the key press.');
    });
    const wrong = all.filter(s => (aim === 'harm' && FRIENDLY_ACTIONS.includes(s.action)) || (aim === 'help' && HOSTILE_ACTIONS.includes(s.action)));
    if (wrong.length) out.push([...new Set(wrong.map(s => s.name))].join(', ') + (aim === 'harm' ? ' is a friendly spell in an Enemy key' : ' is an enemy spell in a Friendly key') + ': it would be cast on the wrong target and fail' + (kind === 'sequence' ? ', and the sequence waits there.' : '.'));
    if (aim === 'harm' && PET_CLASSES.includes(cls) && all.some(s => s.category === 'Control')) out.push('This key also sends your pet, even for crowd control (' + all.filter(s => s.category === 'Control').map(s => s.name).join(', ') + '). Keep crowd control on its own key.');
    if (kind === 'sequence' && filler && cdSec(filler) > 0) out.push('The filler ' + filler.name + ' has a cooldown, so the sequence will wait on it. Pick a spell without a cooldown as filler.');
    if (kind === 'priority') {
      const blockers = spells.slice(0, -1).filter(s => !cdSec(s) && !/Hammer of Wrath|Exorcism|Execute|Overpower|Revenge/.test(s.name));
      if (blockers.length) out.push(blockers.map(s => s.name).join(', ') + ' ha' + (blockers.length > 1 ? 've' : 's') + ' no cooldown, so the lines below ' + (blockers.length > 1 ? 'them' : 'it') + ' never run. Put spells with cooldowns first and the spammable spell last.');
    }
    return out;
  }
  const api = { MAX_POINTS, MACRO_LIMIT, firstPointLevel, pointsAt, levelForPoint, levelForPoints, makeTree, countsOf, treePoints, total,
    addBlocker, stateBlocker, validateOrder, repairOrder, addPoint, removePoint, guideNext, offGuide, compareCounts,
    encodeBuild, decodeBuild, makeMacro, units, UNITS, OFFENSIVE_PAL, OFFENSIVE_MELEE,
    SEQ_TIERS, seqSupported, buildSequences, castSec, durSec, cdSec, buildCustom, customWarnings, CUSTOM_KINDS, CUSTOM_AIMS, CUSTOM_RESETS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.ForeverEngine = api;
})(typeof window !== 'undefined' ? window : globalThis);
