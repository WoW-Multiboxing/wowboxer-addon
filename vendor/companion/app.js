/* WoW Forever Multibox Companion v8 — UI layer.
   Data: window.FOREVER_DATA (embedded, all nine classes). Logic: window.ForeverEngine.
   Squads: you build one or more squads of your own characters (class, race, role, level). Everything — kit, spellbook,
   talents, guides, saved builds and macros — is per character and stored locally in this browser (localStorage). */
(function () {
'use strict';
const D = window.FOREVER_DATA, E = window.ForeverEngine;
const CLASSES = D.classOrder;
const CM = D.classes;                                    // {cls:{n,color,roles}}
const RACES = D.races;                                   // [{k,n,f,c:[classes]}]
const RACE = Object.fromEntries(RACES.map(r => [r.k, r]));
const TREES = Object.create(null); CLASSES.forEach(c => { TREES[c] = E.makeTree(D.talents[c]); });
const SPELLS = D.spells, GUIDES = D.guides;
const ROLE_N = { tank: 'Tank', healer: 'Healer', melee: 'Melee DPS', ranged: 'Ranged DPS' };
const UNIT_N = { party1: 'party1', party2: 'party2', party3: 'party3', party4: 'party4', focus: 'focus' };
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const STORE = 'foreverSquadsV8';
const MAX_MEMBERS = 10;

/* ------------------------------------------------------------ state */
const defaultGuide = cls => (GUIDES.find(g => g.cls === cls && g.default) || GUIDES.find(g => g.cls === cls)).id;
const ROLE_SPEC = { warrior: { tank: 'Protection', melee: 'Fury' }, paladin: { tank: 'Protection', healer: 'Holy', melee: 'Retribution' },
  priest: { healer: 'Holy', ranged: 'Shadow' }, shaman: { healer: 'Restoration', melee: 'Enhancement', ranged: 'Elemental' },
  druid: { tank: 'Feral Combat', melee: 'Feral Combat', healer: 'Restoration', ranged: 'Balance' } };
/** Best guide for a class + role: the class default if it matches the role's spec, else the longest exact/derived guide of that spec. */
function defaultGuideFor(cls, role) {
  const spec = (ROLE_SPEC[cls] || {})[role], def = defaultGuide(cls);
  if (!spec || GUIDES.find(g => g.id === def).spec === spec) return def;
  const c = GUIDES.filter(g => g.cls === cls && g.spec === spec && g.order.length).sort((a, b) => (a.kind !== 'exact-order') - (b.kind !== 'exact-order') || b.order.length - a.order.length);
  return c.length ? c[0].id : def;
}
const uid = p => p + Math.random().toString(36).slice(2, 9);
const safeId = (v, p) => (typeof v === 'string' && /^[A-Za-z0-9]{1,24}$/.test(v) ? v : uid(p));
const st = {
  v: 8, view: 'squad', active: null, squads: [],
  ui: { collapse: true, planAhead: false, overlay: 'level', lower: 'prog', book: { status: 'available', cat: 'all', src: 'all', q: '' } },
};
const undo = Object.create(null);

function newMember(o) {
  const cls = CLASSES.includes(o.cls) ? o.cls : 'warrior';
  const races = RACES.filter(r => r.c.includes(cls));
  const race = races.some(r => r.k === o.race) ? o.race : races[0].k;
  const role = CM[cls].roles.includes(o.role) ? o.role : CM[cls].roles[0];
  return { id: safeId(o.id, 'm'), name: String(o.name || CM[cls].n).slice(0, 24), cls, race, role,
    level: clampLvl(o.level || 1), leader: !!o.leader, unit: E.UNITS.includes(o.unit) ? o.unit : 'party1', talented: clampT(o.talented),
    build: sanitizeOrder(cls, o.build || []), guide: GUIDES.some(g => g.id === o.guide && g.cls === cls) ? o.guide : defaultGuideFor(cls, role),
    seq: E.SEQ_TIERS.includes(o.seq) ? o.seq : 'off', seqTarget: !!o.seqTarget, customSeq: cleanCustom(o.customSeq),
    cmp: typeof o.cmp === 'string' ? o.cmp : '', pins: Array.isArray(o.pins) ? o.pins.filter(x => typeof x === 'string').slice(0, 24) : [], saved: Array.isArray(o.saved) ? o.saved.filter(x => x && typeof x.name === 'string').slice(0, 40).map(x => ({ name: x.name.slice(0, 60), at: String(x.at || ''), order: sanitizeOrder(cls, x.order) })) : [] };
}
/** Custom sequence keys (v8.4): plain data only, every field whitelisted. */
const CUSTOM_MAX = 8;
function cleanCustom(list) {
  if (!Array.isArray(list)) return [];
  const str = v => String(v == null ? '' : v).slice(0, 40);
  return list.filter(c => c && typeof c === 'object').slice(0, CUSTOM_MAX).map(c => ({
    id: safeId(c.id, 'q'), name: String(c.name || 'My key').slice(0, 24),
    kind: E.CUSTOM_KINDS.includes(c.kind) ? c.kind : 'sequence', aim: E.CUSTOM_AIMS.includes(c.aim) ? c.aim : 'harm',
    steps: Array.isArray(c.steps) ? c.steps.slice(0, 12).map(str).filter(Boolean) : [], filler: str(c.filler),
    fills: Math.max(1, Math.min(6, Math.round(Number(c.fills)) || 1)), reset: E.CUSTOM_RESETS.includes(c.reset) ? c.reset : 'combat' }))
    .map((c, i, arr) => (arr.findIndex(x => x.id === c.id) < i ? Object.assign(c, { id: uid('q') }) : c));
}
function newSquad(o) {
  const s = { id: safeId(o.id, 's'), name: String(o.name || 'New squad').slice(0, 40), faction: o.faction === 'alliance' ? 'alliance' : 'horde', linkLevels: !!o.linkLevels, members: [], current: null };
  (o.members || []).slice(0, MAX_MEMBERS).forEach(m => s.members.push(newMember(m)));
  fixLeader(s);
  s.current = s.members.some(m => m.id === o.current) ? o.current : (s.members[0] ? s.members[0].id : null);
  applyLink(s);
  return s;
}
function fixLeader(s) { if (s.members.length && !s.members.some(m => m.leader)) s.members[0].leader = true; let seen = false; s.members.forEach(m => { if (m.leader) { if (seen) m.leader = false; seen = true; } }); }
const clampLvl = v => Math.max(1, Math.min(60, Math.round(Number(v)) || 1));
const clampT = v => Math.max(0, Math.min(5, Math.round(Number(v)) || 0));
const sq = () => st.squads.find(s => s.id === st.active) || st.squads[0] || null;
const me = () => { const s = sq(); return s ? (s.members.find(m => m.id === s.current) || s.members[0] || null) : null; };
const leaderOf = s => (s && s.members.find(m => m.leader)) || null;
const ctxOf = m => ({ leader: !!m.leader, unit: m.unit });
const T = () => TREES[me().cls];

function sanitizeOrder(cls, order) {
  if (!Array.isArray(order) || !TREES[cls]) return [];
  const Tr = TREES[cls];
  const o = order.filter(k => typeof k === 'string' && Tr.byKey[k]).slice(0, 51);
  if (!E.validateOrder(Tr, o)) return o;
  const rest = o.slice(), out = [], c = Object.create(null);
  let progress = true;
  while (rest.length && progress) {
    progress = false;
    for (let i = 0; i < rest.length; i++) if (!E.addBlocker(Tr, c, rest[i])) { const k = rest.splice(i, 1)[0]; out.push(k); c[k] = (c[k] || 0) + 1; progress = true; break; }
  }
  if (rest.length) sanitizeOrder.dropped = (sanitizeOrder.dropped || 0) + rest.length;
  return out;
}
function save() { try { localStorage.setItem(STORE, JSON.stringify(st)); } catch (e) { /* storage unavailable */ } }
function applyUi(u) {
  if (!u || typeof u !== 'object') return;
  st.ui.tipSeen = !!u.tipSeen; st.ui.guideInfo = !!u.guideInfo;
  if (typeof u.collapse === 'boolean') st.ui.collapse = u.collapse; st.ui.planAhead = !!u.planAhead;
  if (['level', 'full', 'off'].includes(u.overlay)) st.ui.overlay = u.overlay;
  if (['prog', 'cmp', 'saved'].includes(u.lower)) st.ui.lower = u.lower;
  const b = u.book && typeof u.book === 'object' ? u.book : {};
  if (['available', 'upcoming', 'all'].includes(b.status)) st.ui.book.status = b.status;
  if (typeof b.cat === 'string' && b.cat.length < 20) st.ui.book.cat = b.cat;
  if (['all', 'trainer', 'talent', 'quest', 'racial'].includes(b.src)) st.ui.book.src = b.src;
  if (typeof b.q === 'string') st.ui.book.q = b.q.slice(0, 100);
}
function restore() {
  let raw = null;
  try { raw = JSON.parse(localStorage.getItem(STORE) || 'null'); } catch (e) { raw = null; }
  if (raw && raw.v === 8 && Array.isArray(raw.squads)) {
    st.squads = raw.squads.slice(0, 30).map(newSquad);
    st.active = st.squads.some(s => s.id === raw.active) ? raw.active : (st.squads[0] && st.squads[0].id);
    if (['squad', 'kit', 'spellbook', 'talents', 'setup'].includes(raw.view)) st.view = raw.view;
    applyUi(raw.ui);
  } else {
    st.squads = [migrateV7()];
    st.active = st.squads[0].id;
  }
  if (!st.squads.length) { st.squads = [migrateV7()]; st.active = st.squads[0].id; }
}
/** First run: turn the v7 trio (if any) into a squad, so nothing is lost. */
function migrateV7(given, quiet) {
  let v7 = given || null;
  if (!given) { try { v7 = JSON.parse(localStorage.getItem('foreverTrioV7') || 'null'); } catch (e) { v7 = null; } }
  if (v7 && typeof v7 !== 'object') v7 = null;
  const lvl = v7 && v7.level ? v7.level : 10, unit = v7 && v7.target === 'focus' ? 'focus' : 'party1';
  const mk = (cls, role, leader) => ({ name: CM[cls].n, cls, race: 'undead', role, level: lvl, leader, unit, talented: v7 ? v7.talented : 0,
    build: v7 && v7.builds ? v7.builds[cls] : [], guide: v7 && v7.guide ? v7.guide[cls] : null, saved: v7 && v7.saved ? v7.saved[cls] : [] });
  if (v7 && !quiet && ['kit', 'spellbook', 'talents', 'setup'].includes(v7.view)) st.view = v7.view;
  if (v7 && !quiet) applyUi({ collapse: v7.collapse, planAhead: v7.planAhead, overlay: v7.overlay, lower: v7.lower, book: v7.book });
  return newSquad({ name: 'Undead trio', faction: 'horde', members: [mk('paladin', 'tank', true), mk('priest', 'healer', false), mk('warlock', 'ranged', false)] });
}

/* ------------------------------------------------------------ helpers */
const ICON_CDN = s => 'https://wow.zamimg.com/images/wow/icons/large/' + s + '.jpg';
window.__icErr = function (img) {
  const step = Number(img.dataset.step || 0) + 1; img.dataset.step = step;
  const s = img.dataset.s, f = img.dataset.f;
  if (step === 1 && f) { img.src = 'https://zephras.com/talents/icons/' + f + '.jpg'; return; }
  if (step <= 2) { img.dataset.step = 2; img.src = 'https://render.worldofwarcraft.com/us/icons/56/' + s + '.jpg'; return; }
  const box = img.parentNode; if (box) box.setAttribute('data-missing', '1');
  img.remove();
};
function iconSrc(slug) { return (window.ICON_DATA && window.ICON_DATA[slug]) || ICON_CDN(slug); }
function initials(name) { return esc(String(name).split(/\s+/).filter(w => /^[A-Za-z]/.test(w)).slice(0, 2).map(w => w[0]).join('').toUpperCase()); }
function icon(slug, name, opts) {
  opts = opts || {};
  return '<span class="ic ' + (opts.size || '') + (opts.locked ? ' locked' : '') + '"' + (opts.attrs || '') + '><span class="ini">' + initials(name) + '</span>' +
    '<img alt="" loading="lazy" data-s="' + esc(slug) + '"' + (opts.fdid ? ' data-f="' + opts.fdid + '"' : '') + ' src="' + esc(iconSrc(slug)) + '" onerror="__icErr(this)"></span>';
}
const classIcon = (cls, size) => icon('classicon_' + cls, CM[cls].n, { size: size || 'sm' });
let toastT;
let toastAct = null;
function toast(msg, err, action) {
  const t = $('toast'); toastAct = action || null;
  t.innerHTML = esc(msg) + (action ? ' <button class="toast-act" id="toastAct">' + esc(action.label) + '</button>' : '');
  t.classList.toggle('err', !!err); t.classList.toggle('act', !!action); t.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => { t.classList.remove('show'); toastAct = null; }, action ? 6000 : 2400);
}
/** Destructive squad actions run without confirm() but can be undone from the toast for 6 seconds. */
function withUndo(label, fn) {
  const snap = JSON.stringify({ squads: st.squads, active: st.active });
  fn(); render();
  toast(label, false, { label: 'Undo', fn: () => { const o = JSON.parse(snap); st.squads = o.squads.map(newSquad); st.active = o.active; render(); toast('Restored'); } });
}
/** Short in-place confirmation on the button that was clicked. */
function flash(btn, ok) {
  if (!btn || !btn.classList) return;
  const old = btn.dataset.label || btn.textContent; btn.dataset.label = old;
  btn.textContent = ok ? 'Copied ✓' : 'Failed'; btn.classList.add(ok ? 'done' : 'fail');
  setTimeout(() => { btn.textContent = old; btn.classList.remove('done', 'fail'); }, 1300);
}
function copyText(text) {
  const fallback = () => { const ta = document.createElement('textarea'); ta.value = text; ta.style.cssText = 'position:fixed;left:-9999px;top:0'; (document.querySelector('dialog[open]') || document.body).appendChild(ta); ta.select(); let ok = false; try { ok = document.execCommand('copy'); } catch (e) { ok = false; } ta.remove(); return ok; };
  try { if (navigator.clipboard && window.isSecureContext !== false) return navigator.clipboard.writeText(text).then(() => true, fallback); } catch (e) { /* fall through */ }
  return Promise.resolve(fallback());
}
function download(name, text, type) {
  const blob = new Blob([text], { type: (type || 'text/plain') + ';charset=utf-8' }), url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1500);
}
const fileSafe = s => String(s).replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-|-$/g, '').slice(0, 30) || 'squad';
const avail = (m) => E.pointsAt((m || me()).level, (m || me()).talented);
const capNow = () => (st.ui.planAhead ? 51 : avail());
const unspent = m => Math.max(0, avail(m) - Math.min(m.build.length, avail(m)));
const raceOk = (s, m) => !s.lock || (s.lock.faction ? RACE[m.race].f === s.lock.faction : s.lock.races.includes(m.race));

/* ------------------------------------------------------------ spells & macros */
const ENGAGE = { id: 'paladin-engage', cls: 'paladin', name: 'Engage Target', level: 1, category: 'Damage', action: 'engage', icon: 'ability_meleedamage', gate: 'trainer', desc: 'Levels 1–3 only: starts auto attack safely (never toggles it off). From level 4 Judgement does this job.', ranks: [] };
function racialsOf(m) {
  const r = D.racials[m.race]; if (!r) return [];
  return r.racials.filter(x => !x.only || x.only.includes(m.cls)).map(x => ({
    id: x.id, cls: m.cls, name: x.name, level: 1, category: x.passive ? 'Passive' : 'Racial', action: x.passive ? 'passive' : 'self',
    icon: x.icon, gate: 'racial', desc: (x.note ? x.note + ' ' : '') + (x.forever === 'new' ? 'New in Forever.' : ''), forever: x.forever,
    ranks: [{ r: 1, cd: x.cd, cast: x.cast, tx: x.tx, id: x.spellId }],
  }));
}
function spellsOf(m) { return SPELLS.filter(s => s.cls === m.cls && raceOk(s, m)).concat(racialsOf(m)); }
function spellById(id) { if (id === ENGAGE.id) return ENGAGE; const m = me(); return spellsOf(m).find(s => s.id === id) || SPELLS.find(s => s.id === id); }
const macro = s => E.makeMacro(s, ctxOf(me()));
function rankAt(s, level) { let r = null; (s.ranks || []).forEach(x => { if (x.l == null || x.l <= level) r = x; }); return r; }
function nextRank(s, level) { return (s.ranks || []).find(x => x.l != null && x.l > level) || null; }
function buildHas(m, talentKey, level) { if (!talentKey) return false; const c = E.countsOf(m.build, E.pointsAt(level, m.talented)); return (c[talentKey] || 0) > 0; }
function learned(m, s, level) { return s.level <= level && (s.gate !== 'talent' || buildHas(m, s.talent, level)); }
function chips(s, full) {
  const out = [];
  if (full) out.push('<span class="chip">' + esc(s.category) + '</span>');
  if (full && s.gate === 'trainer' && !s.race) out.push('<span class="chip">Trainer</span>');
  if (s.gate === 'talent') { const Tr = TREES[s.cls]; out.push('<span class="chip talent">Talent' + (full && s.talent && Tr.byKey[s.talent] ? ' · ' + esc(Tr.trees[Tr.byKey[s.talent].t].n) : '') + '</span>'); }
  if (s.gate === 'quest') out.push('<span class="chip quest" title="' + esc(s.gateNote || '') + '">Quest</span>');
  if (s.gate === 'racial') out.push('<span class="chip race">Racial</span>');
  if (full && s.race) out.push('<span class="chip race">' + esc(s.race) + '</span>');
  if (full && s.form) out.push('<span class="chip">' + esc(s.form) + '</span>');
  if (/petattack|melee-pet|autoshot/.test(s.action)) out.push('<span class="chip pet" title="Sends the pet to the same target">Pet</span>');
  if (E.OFFENSIVE_MELEE.includes(s.action)) out.push('<span class="chip swing" title="Starts auto attack safely (/startattack)">Auto attack</span>');
  if (s.disputed) out.push('<span class="chip disputed" title="' + esc(s.disputed) + '">Disputed</span>');
  if (full && s.iconUnverified) out.push('<span class="chip disputed" title="No source showed an icon for this spell">Icon unverified</span>');
  return out.join('');
}
function spellIcon(s, size, locked) { return icon(s.icon, s.name, { size, locked, attrs: ' data-tip="spell" data-id="' + esc(s.id) + '" tabindex="0"' }); }
function card(s, core) {
  const mm = me(), m = macro(s), r = rankAt(s, mm.level);
  const isNew = s.level === mm.level, newRank = !isNew && r && r.l === mm.level && r.r > 1, pinned = (mm.pins || []).includes(s.id);
  const sub = s.ranks && s.ranks.length ? (r ? (s.ranks.length > 1 ? 'Rank ' + r.r + '/' + s.ranks.length : 'Learned') : 'Level ' + s.level) : 'Auto attack';
  return '<article class="card' + (core ? ' core' : '') + '" title="' + esc(s.desc || '') + '"><div class="card-in">' + spellIcon(s, core ? '' : 'sm') + '<div class="card-meta"><h3><a href="#" data-details="' + esc(s.id) + '">' + esc(s.name) + '</a></h3><div class="sub">' + (isNew ? '<span class="chip new" title="Learned at this level">NEW</span>' : newRank ? '<span class="chip new" title="New rank at this level — visit the trainer">NEW RANK</span>' : '') + esc(sub) + ' ' + chips(s) + (s.fromTalent ? '<span class="chip talent">Your talents</span>' : '') + '</div></div>' +
    (s.id !== ENGAGE.id && s.action !== 'passive' ? '<button class="pin' + (pinned ? ' on' : '') + '" data-pin="' + esc(s.id) + '" title="' + (pinned ? 'Unpin from' : 'Pin to') + ' primary keys" aria-pressed="' + pinned + '">' + (pinned ? '★' : '☆') + '</button>' : '') +
    (m ? '<button class="copy" data-copy="' + esc(s.id) + '" title="Copy macro (' + m.length + '/255)">Copy</button>' : '<span class="chip">Passive</span>') + '</div>' +
    (m ? '<pre class="macro">' + esc(m) + '</pre>' : '') + '</article>';
}
function coreList(m, L) {
  const have = spellsOf(m).filter(s => learned(m, s, L));
  const items = ((D.core[m.cls] || {})[m.role]) || [];
  const out = [];
  items.forEach(it => {
    const names = Array.isArray(it) ? it : [it];
    let pick = null; names.forEach(n => { const s = have.find(x => x.name === n); if (s) pick = s; });
    if (pick && !out.includes(pick)) out.push(pick);
  });
  if (m.cls === 'paladin' && L < 4 && (m.role === 'tank' || m.role === 'melee')) out.unshift(ENGAGE);
  return out.slice(0, 8);
}
function kitLists(m) {
  const L = m.level, all = spellsOf(m);
  const pinned = (m.pins || []).map(id => all.find(x => x.id === id)).filter(x => x && learned(m, x, L) && x.action !== 'passive');
  const primary = pinned.concat(coreList(m, L).filter(x => !pinned.includes(x)));
  const others = spellsOf(m).filter(s => learned(m, s, L) && !primary.includes(s) && s.action !== 'passive')
    .map(s => (s.gate === 'talent' ? Object.assign({}, s, { fromTalent: true }) : s))
    .sort((a, b) => catOrder(a) - catOrder(b) || a.level - b.level || a.name.localeCompare(b.name));
  return { primary, others };
}
const CAT_ORDER = ['Damage', 'Heal', 'Debuff', 'Control', 'Defense', 'Buff', 'Totem', 'Pet', 'Utility', 'Mount', 'Racial'];
const catOrder = s => { const i = CAT_ORDER.indexOf(s.category); return i < 0 ? 99 : i; };
const MELEE_CLS = ['warrior', 'rogue', 'paladin'];
function ruleText(m) {
  const s = sq(), L = leaderOf(s), parts = [];
  if (m.leader) parts.push('<b>' + esc(m.name) + ' leads the squad:</b> offensive keys hit a hostile mouseover, otherwise your own target; heals go to a friendly mouseover, your friendly target, otherwise yourself.');
  else parts.push('<b>' + esc(m.name) + ' follows ' + esc(L ? L.name : 'the leader') + ' via ' + esc(m.unit) + ':</b> offensive keys hit a hostile mouseover, otherwise <code>' + esc(m.unit) + 'target</code>, otherwise your own target. Heals and buffs go to a friendly mouseover, otherwise ' + esc(L ? L.name : 'the leader') + ', otherwise yourself.');
  if (MELEE_CLS.includes(m.cls) || (m.cls === 'druid' && (m.role === 'tank' || m.role === 'melee')) || (m.cls === 'shaman' && m.role === 'melee') || m.cls === 'hunter') parts.push('Every melee ability starts auto attack with <code>/startattack</code>, so a second press never switches it off.');
  if (m.cls === 'hunter') parts.push('Auto Shot uses <code>!Auto Shot</code> (never toggles off) and every shot sends the pet to the same target.');
  if (m.cls === 'warlock') parts.push('Damage spells, Banes and Curses send the pet to the same target; crowd control and Bane of Havoc never do.');
  parts.push('Crowd control that breaks on damage never starts attacks or pet attacks.');
  return parts.join(' ');
}
const sum = (k, b, s) => '<div class="sum"><div class="k">' + esc(k) + '</div><b title="' + esc(b) + '">' + esc(b) + '</b><small>' + esc(s) + '</small></div>';
function renderKit() {
  const m = me(), { primary, others } = kitLists(m);
  const trainer = spellsOf(m).filter(s => s.gate !== 'talent' && s.gate !== 'racial');
  const nextLvl = Math.min(...trainer.filter(s => s.level > m.level).map(s => s.level));
  const nextNames = isFinite(nextLvl) ? trainer.filter(s => s.level === nextLvl).map(s => s.name) : [];
  const Tr = T(), A = avail(), spent = Math.min(m.build.length, A), g = guideOf(m);
  const nx = g && g.order.length ? E.guideNext(Tr, g.order, m.build.slice(0, A)) : null;
  const atLvl = spellsOf(m).filter(x => x.gate !== 'racial' && (x.level === m.level || (x.ranks || []).some(r => r.l === m.level && r.r > 1)) && (x.gate !== 'talent' || buildHas(m, x.talent, m.level)));
  $('kitSummary').innerHTML = (atLvl.length ? sum('New at level ' + m.level, atLvl.slice(0, 2).map(x => x.name).join(' · ') + (atLvl.length > 2 ? ' +' + (atLvl.length - 2) : ''), 'Visit your trainer') : '') +
    sum('Next trainer visit', nextNames.length ? 'Level ' + nextLvl : 'All learned', nextNames.slice(0, 2).join(' · ') + (nextNames.length > 2 ? ' +' + (nextNames.length - 2) : '')) +
    sum('Talent points', spent + ' / ' + A, nx && nx.index < A ? 'Next: ' + Tr.byKey[nx.key].n : (g.order.length ? 'Up to date with guide' : '')) +
    sum('Targeting', m.leader ? 'Leader' : 'Assists via ' + m.unit, ROLE_N[m.role]);
  $('kitRule').innerHTML = '<p>' + ruleText(m) + '</p>';
  renderSeq();
  $('primaryCards').innerHTML = primary.map(s => card(s, true)).join('') || '<div class="empty">No everyday spells at this level yet.</div>';
  $('secondaryCards').innerHTML = others.map(s => card(s, false)).join('') || '<div class="empty">Nothing else learned yet.</div>';
  $('primaryCount').textContent = primary.length + ' keys';
  $('secondaryWrap').classList.toggle('collapsed', st.ui.collapse);
  $('toggleSecondary').textContent = st.ui.collapse ? 'Show macros' : 'Hide macros';
  $('toggleSecondary').setAttribute('aria-expanded', String(!st.ui.collapse));
}
/* ------------------------------------------------------------ sequences (v8.3, opt-in per character) */
const SEQ_N = { off: 'Off', simple: 'Simple', medium: 'Medium', advanced: 'Advanced' };
const SEQ_D = { off: 'Normal one-spell keys only', simple: 'Opener, then a filler spell', medium: 'Adds a DoT or a cooldown', advanced: 'Every DoT and talent spell that fits' };
function seqHas(m, L) { const all = spellsOf(m); return name => all.find(s => s.name === name && learned(m, s, L)) || null; }
function seqOf(m, L) {
  const has = seqHas(m, L == null ? m.level : L);
  const gen = E.buildSequences(m.cls, m.role, m.seq || 'off', ctxOf(m), has, { targetReset: !!m.seqTarget });
  return gen.concat((m.customSeq || []).map(c => E.buildCustom(m.cls, c, ctxOf(m), has, { melee: isMelee(m) })).filter(x => x.kind !== 'empty'));
}
function isMelee(m) { return MELEE_CLS.includes(m.cls) || (m.cls === 'druid' && (m.role === 'tank' || m.role === 'melee')) || (m.cls === 'shaman' && m.role === 'melee');
}
const seqOn = m => !!m && ((m.seq && m.seq !== 'off' && E.seqSupported(m.cls)) || (m.customSeq || []).length > 0);
/** Level bands in which the sequence macros stay the same: [{from, to, list}] */
function seqPlan(m) {
  const out = []; let prev = null;
  for (let L = 1; L <= 60; L++) {
    const list = seqOf(m, L), sig = list.map(x => x.macro).join('\n§\n');
    if (!prev || sig !== prev.sig) { prev = { from: L, to: L, list, sig }; out.push(prev); } else prev.to = L;
  }
  return out;
}
function seqChangedNow(m) { if (!seqOn(m) || m.level <= 1) return false; const b = seqPlan(m).find(x => x.from <= m.level && x.to >= m.level); return !!b && b.from === m.level; }
function seqStepsText(x) {
  if (x.kind === 'priority') return x.spells.join(' > ');
  if (x.kind === 'engage') return 'Auto attack';
  const pre = x.filler ? x.spells.slice(0, -1) : x.spells;
  return pre.concat(x.filler ? [x.filler + (x.fills > 1 ? ' ×' + x.fills : '')] : []).join(' → ');
}
function seqStepsHtml(x) {
  if (x.kind === 'priority') return x.spells.map((n, i) => '<span class="chip">' + (i + 1) + '. ' + esc(n) + '</span>').join('');
  if (x.kind === 'engage') return '<span class="chip">Auto attack</span>';
  const pre = x.filler ? x.spells.slice(0, -1) : x.spells;
  return pre.map(n => '<span class="chip">' + esc(n) + '</span>').concat(x.filler ? ['<span class="chip filler" title="Filler: repeated until the list starts over">' + esc(x.filler) + (x.fills > 1 ? ' ×' + x.fills : '') + '</span>'] : []).join('<span class="seq-arrow">→</span>');
}
function seqNote(x) {
  if (x.kind === 'engage') return 'Nothing to put in a sequence yet: this key starts auto attack.';
  if (x.kind === 'single') return x.custom ? 'One spell (the others are not learned yet, or the key has only one).' : 'Only one spell so far. It becomes a ' + (x.base === 'priority' ? 'priority list' : 'sequence') + ' when you learn more.';
  if (x.kind === 'priority') return 'Priority list: each press uses the first ability that is ready (top to bottom). Not yet confirmed in Forever: check in game that a spell on cooldown passes on to the next line.';
  const r = x.reset.split('/'), when = r.map(p => (p === 'combat' ? 'a new fight' : p === 'target' ? 'a new target' : p + ' s without pressing')).join(' or ');
  let t = 'Press it again and again. It restarts on ' + when + '.';
  if (x.loopSec && x.why) t += ' One loop takes about ' + x.loopSec + ' s (' + x.why + ').';
  if (x.compact) t += ' Shortened to fit the 255-character limit.';
  if (x.tooLong) t += ' Warning: longer than 255 characters, WoW will cut it off.';
  return t;
}
function seqCard(m, x) {
  const cid = x.custom ? x.id.slice(1) : '';
  const tag = x.custom ? 'Custom' : SEQ_N[m.seq];
  return '<article class="card core seq' + (x.custom ? ' custom' : '') + '"><div class="card-in"><div class="card-meta"><h3>' + esc(x.label) + ' <span class="small">· ' + tag + '</span></h3><div class="seq-steps">' + seqStepsHtml(x) + '</div></div>' +
    (x.custom ? '<button class="btn sm ghost" data-sdedit="' + esc(cid) + '" title="Edit this key">Edit</button><button class="btn sm ghost danger" data-sdremove="' + esc(cid) + '" title="Delete this key">✕</button>' : '') +
    '<button class="copy" data-copyseq="' + esc(x.id) + '" title="Copy macro (' + x.macro.length + '/255)">Copy</button></div>' +
    '<p class="card-desc" title="' + esc(seqNote(x)) + '">' + esc(seqNoteShort(x)) + '</p><pre class="macro">' + esc(x.macro) + '</pre></article>';
}
/** One line under each key; the full explanation sits in the tooltip (less text). */
function seqNoteShort(x) {
  if (x.tooLong) return 'Longer than 255 characters: WoW will cut it off.';
  if (x.kind === 'engage') return 'Starts auto attack for now.';
  if (x.kind === 'single') return 'One spell so far.';
  if (x.kind === 'priority') return 'Top ready ability fires. Test once in game.';
  return 'Press repeatedly · restarts on ' + x.reset.split('/').map(p => (p === 'combat' ? 'new fight' : p === 'target' ? 'new target' : p + ' s idle')).join(' / ') + (x.compact ? ' · shortened' : '');
}
function renderSeq() {
  const m = me(), wrap = $('seqWrap'), sup = E.seqSupported(m.cls);
  wrap.classList.remove('hidden');
  const tier = sup ? (m.seq || 'off') : 'off';
  $('seqTier').innerHTML = (sup ? E.SEQ_TIERS.map(t => '<button data-seqtier="' + t + '" class="' + (t === tier ? 'on' : '') + '" aria-pressed="' + (t === tier) + '" title="' + esc(SEQ_D[t]) + '">' + SEQ_N[t] + '</button>').join('') : '') +
    '<button data-sdnew="1" title="Build your own sequence or priority key">＋ Custom</button>';
  const list = seqOf(m);
  if (!list.length) {
    $('seqBody').innerHTML = '<p class="small seq-off">One key, a short rotation — e.g. <b>Immolate → Shadow Bolt ×4</b>. ' + (sup ? 'Pick a level above or build your own.' : 'Built-in keys come to this class later; build your own with ＋ Custom.') + '</p>';
    return;
  }
  const plan = seqPlan(m), i = plan.findIndex(b => b.from <= m.level && b.to >= m.level), next = plan[i + 1];
  const hasSeq = m.leader && tier !== 'off' && plan.some(b => b.list.some(x => x.kind === 'sequence' && !x.fixedReset));
  $('seqBody').innerHTML = '<div class="seq-bar">' +
    (next ? '<span class="badge">Changes at level ' + next.from + ': ' + esc(next.list.map(seqStepsText).join(' · ')) + '</span>' : '<span class="badge ok">Final version</span>') +
    (hasSeq ? '<label class="small seq-opt" title="Also start over (with the DoTs) when you switch target. Only for the leader: followers cast on the leader\'s target and never change their own. A spell on cooldown can then hold the sequence for a moment."><input type="checkbox" id="seqTarget"' + (m.seqTarget ? ' checked' : '') + '> Restart on a new target</label>' : '') + '</div>' +
    '<div class="cards">' + list.map(x => seqCard(m, x)).join('') + '</div>' +
    '<details class="hint seq-plan"><summary>Level plan (' + plan.length + ' version' + (plan.length > 1 ? 's' : '') + ')</summary><table class="seq-table">' +
    plan.map(b => '<tr' + (b.from <= m.level && b.to >= m.level ? ' class="now"' : '') + '><td>' + (b.from === b.to ? 'Level ' + b.from : 'Level ' + b.from + (b.to === 60 ? '+' : '–' + b.to)) + '</td><td>' + esc(b.list.map(x => x.label + ': ' + seqStepsText(x)).join(' · ')) + '</td><td>' + b.list.map(x => '<button class="btn sm" data-copyseq="' + esc(x.id) + '@' + b.from + '" title="Copy ' + esc(x.label) + ' for level ' + b.from + '">' + esc(x.label) + '</button>').join(' ') + '</td></tr>').join('') +
    '</table></details>';
}

/* ---- custom key editor (dialog) */
let sdDraft = null;
const SD_RESET_N = { combat: 'New fight', 'target/combat': 'New fight or new target (leader)', 'combat/12': 'New fight or 12 s without pressing' };
function sdSpells(m) { return spellsOf(m).filter(s => s.action !== 'passive' && s.action !== 'autoshot' && (s.ranks || []).length && s.gate !== 'racial').sort((a, b) => a.level - b.level || a.name.localeCompare(b.name)); }
function sdLevelOf(m, name) { const s = spellsOf(m).find(x => x.name === name); return s ? s.level : null; }
function openSeqDlg(id) {
  const m = me(), c = id ? (m.customSeq || []).find(x => x.id === id) : null;
  if (!c && (m.customSeq || []).length >= CUSTOM_MAX) { toast('Up to ' + CUSTOM_MAX + ' custom keys per character', true); return; }
  const role = m.role === 'healer' ? 'help' : 'harm';
  sdDraft = c ? JSON.parse(JSON.stringify(c)) : { id: uid('q'), name: 'My key', kind: 'sequence', aim: role, steps: [], filler: '', fills: 3, reset: 'combat', isNew: true };
  $('sdTitle').textContent = c ? 'Edit ' + c.name : 'New custom key for ' + m.name;
  renderSeqDlg(); $('seqDlg').showModal();
}
function renderSeqDlg() {
  const m = me(), d = sdDraft, opts = sdSpells(m), L = m.level;
  const opt = (s, sel) => '<option value="' + esc(s.name) + '"' + (sel ? ' selected' : '') + '>' + esc(s.name) + (s.level > L ? ' (level ' + s.level + ')' : '') + (s.gate === 'talent' ? ' · talent' : '') + '</option>';
  $('sdBody').innerHTML =
    '<label>Name <input class="input" id="sdName" maxlength="24" value="' + esc(d.name) + '"></label>' +
    '<div class="mf2"><label>Type <select class="select" id="sdKind"><option value="sequence"' + (d.kind === 'sequence' ? ' selected' : '') + '>Sequence — next spell each press</option><option value="priority"' + (d.kind === 'priority' ? ' selected' : '') + '>Priority — first ready spell</option></select></label>' +
    '<label>Target <select class="select" id="sdAim"><option value="harm"' + (d.aim === 'harm' ? ' selected' : '') + '>Enemy</option><option value="help"' + (d.aim === 'help' ? ' selected' : '') + '>Friendly</option></select></label></div>' +
    '<label>Add a spell <span class="sd-add"><select class="select" id="sdSpell">' + opts.map(s => opt(s, false)).join('') + '</select><button type="button" class="btn sm gold" data-sdadd="1">Add</button></span></label>' +
    '<ol class="sd-steps">' + (d.steps.length ? d.steps.map((n, i) => { const lv = sdLevelOf(m, n); return '<li><span>' + esc(n) + (lv > L ? ' <em class="small">from level ' + lv + '</em>' : '') + '</span><button type="button" class="btn sm ghost" data-sdup="' + i + '" title="Move up" aria-label="Move ' + esc(n) + ' up">↑</button><button type="button" class="btn sm ghost" data-sddown="' + i + '" title="Move down" aria-label="Move ' + esc(n) + ' down">↓</button><button type="button" class="btn sm ghost danger" data-sddel="' + i + '" title="Remove" aria-label="Remove ' + esc(n) + '">✕</button></li>'; }).join('') : '<li class="small">No spells yet — add them in the order you want.</li>') + '</ol>' +
    (d.kind === 'sequence' ? '<div class="mf2"><label>Filler (repeated at the end) <select class="select" id="sdFiller"><option value="">None</option>' + (d.filler && !opts.some(s => s.name === d.filler) ? '<option value="' + esc(d.filler) + '" selected>' + esc(d.filler) + '</option>' : '') + opts.map(s => opt(s, s.name === d.filler)).join('') + '</select></label>' +
      '<label>Repeat filler <select class="select" id="sdFills">' + [1, 2, 3, 4, 5, 6].map(n => '<option' + (n === d.fills ? ' selected' : '') + '>' + n + '</option>').join('') + '</select></label></div>' +
      '<label>Start over on <select class="select" id="sdReset">' + E.CUSTOM_RESETS.map(r => '<option value="' + r + '"' + (r === d.reset ? ' selected' : '') + '>' + SD_RESET_N[r] + '</option>').join('') + '</select></label>' : '') +
    '<div id="sdPreview"></div>';
  sdPreview();
}
function sdRead() {
  const d = sdDraft, v = id => ($(id) ? $(id).value : null);
  if (v('sdName') != null) d.name = String(v('sdName')).slice(0, 24) || 'My key';
  if (v('sdKind')) d.kind = E.CUSTOM_KINDS.includes(v('sdKind')) ? v('sdKind') : 'sequence';
  if (v('sdAim')) d.aim = E.CUSTOM_AIMS.includes(v('sdAim')) ? v('sdAim') : 'harm';
  if (d.kind === 'sequence') {
    if (v('sdFiller') != null) d.filler = v('sdFiller');
    if (v('sdFills')) d.fills = Math.max(1, Math.min(6, Number(v('sdFills')) || 1));
    if (v('sdReset')) d.reset = E.CUSTOM_RESETS.includes(v('sdReset')) ? v('sdReset') : 'combat';
  }
}
function sdPreview() {
  const m = me(), d = sdDraft, has = seqHas(m, m.level), x = E.buildCustom(m.cls, cleanCustom([d])[0], ctxOf(m), has, { melee: isMelee(m) });
  const all = spellsOf(m), learnedList = d.steps.map(has).filter(Boolean), filler = d.kind === 'sequence' && d.filler ? has(d.filler) : null;
  const warn = E.customWarnings(d.kind, learnedList, filler, d.aim, m.cls);
  const later = d.steps.concat(d.kind === 'sequence' && d.filler ? [d.filler] : []).filter(n => !has(n) && all.some(s => s.name === n));
  if (later.length) warn.unshift('Not learned at level ' + m.level + ' yet: ' + [...new Set(later)].join(', ') + '. Left out until you learn ' + (later.length > 1 ? 'them' : 'it') + '.');
  if (x.tooLong) warn.push('Longer than 255 characters — remove a spell.');
  $('sdPreview').innerHTML = (warn.length ? '<ul class="sd-warn">' + warn.map(w => '<li>' + esc(w) + '</li>').join('') + '</ul>' : '') +
    (x.macro ? '<div class="small sd-count">Preview at level ' + m.level + ' · ' + x.macro.length + '/255' + (x.compact ? ' · shortened to fit' : '') + '</div><pre class="macro">' + esc(x.macro) + '</pre>' : '<p class="small">Add at least one learned spell to see the macro.</p>');
}
function saveSeqDlg() {
  sdRead();
  const m = me(), d = sdDraft, clean = cleanCustom([d])[0];
  if (clean.kind === 'priority' ? !clean.steps.length : (!clean.steps.length && !clean.filler)) { toast('Add at least one spell', true); return; }
  m.customSeq = m.customSeq || [];
  const i = m.customSeq.findIndex(x => x.id === clean.id);
  if (i >= 0) m.customSeq[i] = clean; else m.customSeq.push(clean);
  $('seqDlg').close(); sdDraft = null; save(); renderKit(); toast('Saved “' + clean.name + '”');
}
function kitText(m) {
  const { primary, others } = kitLists(m), mc = s => E.makeMacro(s, ctxOf(m));
  const line = s => s.name + ' (level ' + s.level + '+)\n' + mc(s) + '\n';
  return 'WOW FOREVER MULTIBOX COMPANION v8 — ' + m.name + ' (' + RACE[m.race].n + ' ' + CM[m.cls].n + ', ' + ROLE_N[m.role] + ') level ' + m.level + '\n' +
    (m.leader ? 'Squad leader' : 'Follows the leader via ' + m.unit) + '\n\n' +
    (seqOn(m) ? 'SEQUENCES' + (m.seq && m.seq !== 'off' && E.seqSupported(m.cls) ? ' (' + SEQ_N[m.seq] + ')' : '') + '\n\n' + seqOf(m).map(x => x.label + ': ' + seqStepsText(x) + '\n' + x.macro + '\n').join('\n') + '\n' : '') + 'PRIMARY\n\n' + primary.filter(s => mc(s)).map(line).join('\n') + '\nSECONDARY\n\n' + others.map(line).join('\n');
}

/* ------------------------------------------------------------ spellbook */
function bookRows() {
  const m = me(), q = st.ui.book.q.trim().toLowerCase(), b = st.ui.book;
  return spellsOf(m)
    .filter(s => b.status === 'all' || (b.status === 'available' ? learned(m, s, m.level) : !learned(m, s, m.level)))
    .filter(s => b.cat === 'all' || s.category === b.cat)
    .filter(s => b.src === 'all' || s.gate === b.src)
    .filter(s => !q || (s.name + ' ' + (s.desc || '') + ' ' + (s.ranks || []).map(r => r.tx || '').join(' ')).toLowerCase().includes(q))
    .sort((a, c) => a.level - c.level || a.name.localeCompare(c.name));
}
function renderBook() {
  const m = me(), b = st.ui.book;
  document.querySelectorAll('#bookStatus button').forEach(x => x.classList.toggle('on', x.dataset.s === b.status));
  const cats = ['all'].concat([...new Set(spellsOf(m).map(s => s.category))].sort());
  $('bookCat').innerHTML = cats.map(c => '<option value="' + esc(c) + '">' + (c === 'all' ? 'All categories' : esc(c)) + '</option>').join('');
  if (!cats.includes(b.cat)) b.cat = 'all';
  $('bookCat').value = b.cat; $('bookSrc').value = b.src; if ($('bookSearch').value !== b.q) $('bookSearch').value = b.q;
  const rows = bookRows(), core = coreList(m, 60).map(s => s.name);
  $('bookCount').textContent = rows.length + ' abilities';
  $('book').innerHTML = rows.map(s => {
    const r = rankAt(s, m.level), nr = nextRank(s, m.level), locked = s.level > m.level;
    const inPlan = s.gate === 'talent' ? buildHas(m, s.talent, Math.max(m.level, s.level)) : true;
    let rk;
    if (locked) rk = 'Learn at level ' + s.level + (s.gate === 'talent' ? (inPlan ? ' · in your talent plan' : ' · talent not in your plan') : '');
    else if (!inPlan) rk = 'Needs the ' + (TREES[s.cls].byKey[s.talent] ? TREES[s.cls].byKey[s.talent].n : s.name) + ' talent · not in your plan';
    else rk = (s.ranks.length > 1 ? 'Rank ' + r.r + ' of ' + s.ranks.length : 'Learned') + (nr ? ' · next rank at ' + nr.l : '') + (s.gate === 'talent' ? ' · from your talents' : '');
    const everyday = core.includes(s.name);
    return '<article class="book-item' + (locked ? ' locked' : '') + '" title="' + esc(s.desc || '') + '">' + spellIcon(s, 'sm', locked) + '<div class="info"><h3><span class="lvlpill">' + s.level + '</span>' + esc(s.name) + '</h3><div class="rk">' + esc(rk) + '</div>' +
      '<div class="chips">' + (everyday ? '<span class="chip swing" title="Part of the Everyday Kit for this role">★ Kit</span>' : '') + chips(s) + '</div></div><div class="btns">' +
      (s.action !== 'passive' ? '<button class="pin' + ((m.pins || []).includes(s.id) ? ' on' : '') + '" data-pin="' + esc(s.id) + '" title="Pin to / unpin from the Kit\'s primary keys">' + ((m.pins || []).includes(s.id) ? '★' : '☆') + '</button><button class="copy sm" data-copy="' + esc(s.id) + '">Copy</button>' : '<span class="chip">Passive</span>') + '<button class="btn sm ghost" data-details="' + esc(s.id) + '" title="Ranks and macro">⋯</button></div></article>';
  }).join('') || '<div class="empty">No abilities match. Try another level, filter or search.</div>';
}

/* ------------------------------------------------------------ tooltips */
const tt = () => $('tt');
let tipOn = false;
const clean = t => String(t || '').replace(/\|c[0-9A-Fa-f]{8}/g, '').replace(/\|r/g, '');
function spellTip(s) {
  const m = me(), r = rankAt(s, m.level) || (s.ranks || [])[0] || {}, isLearned = s.level <= m.level, nr = nextRank(s, m.level), total = (s.ranks || []).length;
  let h = '<div class="t-head">' + icon(s.icon, s.name, { size: 'sm' }) + '<div style="flex:1"><div class="t-row"><span class="t-name">' + esc(s.name) + '</span>' + (r.r && total > 1 ? '<span class="t-rank">Rank ' + r.r + '</span>' : '') + '</div>' +
    (s.gate === 'racial' ? '<div class="t-rank">Racial' + (s.category === 'Passive' ? ' · Passive' : '') + '</div>' : '') + '</div></div>';
  const row = (a, b) => (a || b ? '<div class="t-row"><span>' + esc(a || '') + '</span><span>' + esc(b || '') + '</span></div>' : '');
  h += row(r.cost, r.range) + row(r.cast, r.cd ? r.cd + ' cooldown' : '');
  if (!isLearned) h += '<div class="t-req">Requires level ' + s.level + '</div>';
  if (s.form) h += '<div class="t-rank">Requires ' + esc(s.form) + '</div>';
  if (s.gate === 'talent') {
    const tn = s.talent && TREES[s.cls].byKey[s.talent], has = buildHas(m, s.talent, Math.max(m.level, s.level));
    h += '<div class="' + (has ? 't-ok' : 't-req') + '">Requires talent: ' + esc(tn ? tn.n + ' (' + TREES[s.cls].trees[tn.t].n + ')' : s.name) + (has ? ' — in your plan' : '') + '</div>';
  }
  h += '<div class="t-desc">' + esc(clean(r.tx || s.desc)) + '</div>';
  if (nr) h += '<div class="t-next">Next rank: ' + nr.r + ' at level ' + nr.l + '</div>';
  if (s.disputed) h += '<div class="t-warn">⚠ ' + esc(s.disputed) + '</div>';
  if (s.gateNote) h += '<div class="t-warn">' + esc(s.gateNote) + '</div>';
  const src = { trainer: 'Class trainer', talent: 'Talent', quest: 'Quest', racial: 'Racial' }[s.gate] || '';
  h += '<div class="t-meta">' + src + (r.id ? ' · Spell ID ' + r.id : '') + (total > 1 ? ' · ' + total + ' ranks' : '') + ' · Forever beta data (1.60.1.70532)</div>';
  return h;
}
function talentTip(k) {
  const m = me(), Tr = T(), n = Tr.byKey[k], order = m.build, all = E.countsOf(order), lvlC = E.countsOf(order, avail());
  const have = all[k] || 0, treeName = Tr.trees[n.t].n;
  let h = '<div class="t-head">' + icon(n.i, n.n, { size: 'sm', fdid: n.f }) + '<div style="flex:1"><div class="t-name">' + esc(n.n) + '</div><div class="t-rank">Rank ' + have + '/' + n.m + '</div></div></div>';
  const need = (n.r - 1) * 5, spent = E.treePoints(Tr, all)[n.t];
  if (need && spent < need) h += '<div class="t-req">Requires ' + need + ' points in ' + esc(treeName) + ' Talents</div>';
  const p = Tr.prereq[k];
  if (p && (all[p] || 0) < Tr.byKey[p].m) h += '<div class="t-req">Requires ' + Tr.byKey[p].m + ' point' + (Tr.byKey[p].m > 1 ? 's' : '') + ' in ' + esc(Tr.byKey[p].n) + '</div>';
  if (have > 0) h += '<div class="t-desc">' + esc(clean(n.d[have - 1])) + '</div>';
  if (have < n.m) h += (have > 0 ? '<div class="t-next">Next rank:</div>' : '') + '<div class="t-desc"' + (have > 0 ? ' style="margin-top:2px"' : '') + '>' + esc(clean(n.d[have])) + '</div>';
  const teaches = SPELLS.find(s => s.cls === m.cls && s.talent === k);
  if (teaches && teaches.ranks.length > 1) h += '<div class="t-next" style="color:#9fd0ff">Teaches ' + esc(teaches.name) + ' — ' + teaches.ranks.length + ' ranks, later ranks from the trainer.</div>';
  const idx = []; order.forEach((x, i) => { if (x === k) idx.push(i); });
  if (idx.length) h += '<div class="t-meta" style="border:0;margin-top:6px;padding:0;color:#c8d3e2">Your plan: ' + idx.map((i, j) => 'rank ' + (j + 1) + ' at level ' + E.levelForPoint(i, m.talented)).join(', ') + ((all[k] || 0) > (lvlC[k] || 0) ? ' <span style="color:#ffd38a">(' + ((all[k] || 0) - (lvlC[k] || 0)) + ' planned beyond level ' + m.level + ')</span>' : '') + '</div>';
  const g = GUIDES.find(x => x.id === m.guide);
  if (g) {
    const gi = []; g.order.forEach((x, i) => { if (x === k) gi.push(i); });
    if (gi.length) h += '<div class="t-guide">Guide: ' + gi.map((i, j) => 'rank ' + (j + 1) + ' at level ' + E.levelForPoint(i, m.talented)).join(', ') + '</div>';
    else if (g.key.includes(k)) h += '<div class="t-guide">Guide highlights this talent (no point order published).</div>';
    else if (g.order.length) h += '<div class="t-guide" style="color:#7e8ea3">Not part of the selected guide.</div>';
  }
  const addB = E.addBlocker(Tr, all, k, capNow()), rem = have ? E.removePoint(Tr, order, k) : null;
  h += addB ? '<div class="t-un">' + (addB.code === 'max' ? 'Max rank reached' : addB.code === 'points' ? 'No points left at level ' + m.level + (st.ui.planAhead ? '' : ' — enable Plan ahead to plan further') : esc(addB.text)) + '</div>' : '<div class="t-learn">Left-click to learn</div>';
  if (have) h += rem && rem.error ? '<div class="t-un" style="margin-top:2px">Right-click blocked: ' + esc(rem.error) + '</div>' : '<div class="t-learn" style="margin-top:2px;color:#ff8d8d">Right-click to unlearn</div>';
  h += '<div class="t-meta">' + esc(treeName) + ' · row ' + n.r + ', column ' + n.c + (n.sp ? ' · Spell ID ' + n.sp : '') + (n.f ? ' · Icon FileDataID ' + n.f : '') + '</div>';
  return h;
}
function showTip(html, ev, anchor) {
  const t = tt(); t.innerHTML = html; t.classList.add('show'); tipOn = true;
  if (ev && ev.clientX != null && !(ev.detail === 0 && ev.type === 'click')) placeTip(ev); else if (anchor) { const r = anchor.getBoundingClientRect(); placeTip({ clientX: r.right, clientY: r.top }); }
}
function placeTip(ev) {
  if (!tipOn) return; const t = tt(), pad = 12; let x = ev.clientX + 18, y = ev.clientY + 16;
  const w = t.offsetWidth, h = t.offsetHeight;
  if (x + w > innerWidth - pad) x = ev.clientX - w - 18;
  if (y + h > innerHeight - pad) y = Math.max(pad, innerHeight - h - pad);
  t.style.left = Math.max(pad, x) + 'px'; t.style.top = Math.max(pad, y) + 'px';
}
function hideTip() { tipOn = false; tt().classList.remove('show'); }
function tipFor(el) {
  if (el.dataset.tip === 'spell') { const s = spellById(el.dataset.id); return s ? spellTip(s) : ''; }
  if (el.dataset.tip === 'talent') return talentTip(el.dataset.k);
  return '';
}

/* ------------------------------------------------------------ spell dialog */
let dlgSpell = null;
function openDetails(id) {
  const s = spellById(id); if (!s) return; dlgSpell = s;
  $('dlgIcon').innerHTML = icon(s.icon, s.name, { size: 'sm' });
  $('dlgTitle').textContent = s.name;
  const m = macro(s), r = rankAt(s, me().level);
  let b = '<div class="chips" style="display:flex;gap:5px;flex-wrap:wrap">' + chips(s) + '</div>' + (s.desc ? '<p class="small" style="margin-top:8px">' + esc(s.desc) + '</p>' : '');
  b += m ? '<pre class="macro">' + esc(m) + '</pre>' : '<p class="small">Passive — no macro needed.</p>';
  if (s.ranks && s.ranks.length) {
    b += '<table class="ranks"><thead><tr><th>Rank</th><th>Level</th><th>Cost</th><th>Cast</th><th>Range</th><th>Cooldown</th><th>Tooltip</th></tr></thead><tbody>' +
      s.ranks.map(x => '<tr class="' + (r && x === r ? 'cur' : '') + '"><td>' + (x.r || '') + '</td><td>' + (x.l || '—') + '</td><td>' + esc(x.cost || '—') + '</td><td>' + esc(x.cast || '—') + '</td><td>' + esc(x.range || '—') + '</td><td>' + esc(x.cd || '—') + '</td><td class="tx">' + esc(clean(x.tx || '')) + (x.id ? ' <a href="https://zephras.com/forever/enUS/spell/' + x.id + '/" target="_blank" rel="noopener" title="Open on Zephras">↗</a>' : '') + '</td></tr>').join('') + '</tbody></table>';
  }
  if (s.srcNote) b += '<p class="small" style="margin-top:10px"><b>Source note:</b> ' + esc(s.srcNote) + '</p>';
  if (s.disputed) b += '<p class="small" style="color:#ffb98a"><b>Disputed:</b> ' + esc(s.disputed) + '</p>';
  if (s.gate !== 'racial') b += '<p class="small"><a href="https://theforeverera.com/en/spells/' + s.cls + '/" target="_blank" rel="noopener">The Forever Era ' + CM[s.cls].n + ' spellbook ↗</a></p>';
  $('dlgBody').innerHTML = b;
  $('dlgLen').textContent = m ? m.length + ' / ' + E.MACRO_LIMIT + ' characters · ' + (s.level > me().level ? 'learn at level ' + s.level : 'learned') : '';
  $('dlgCopy').classList.toggle('hidden', !m);
  if (!$('dlg').open) $('dlg').showModal();
}

/* ------------------------------------------------------------ talents */
let tpMsgT;
function tpMsg(text, good) { const el = $('tpMsg'); el.textContent = text || ''; el.style.color = good ? '#8be0a6' : ''; clearTimeout(tpMsgT); if (text) tpMsgT = setTimeout(() => { el.textContent = ''; }, 4500); }
const redo = Object.create(null);
function setBuild(m, order, msg) {
  const u = undo[m.id] = undo[m.id] || [];
  if (order.join() !== m.build.join()) { u.push(m.build.slice()); if (u.length > 60) u.shift(); redo[m.id] = []; }
  m.build = order; save(); renderTalents(); if (msg) tpMsg(msg, true);
}
const guideOf = m => GUIDES.find(g => g.id === m.guide) || GUIDES.find(g => g.id === defaultGuide(m.cls));
const TREE_BG = {
  warrior: ['#b98a52', '#c4512f', '#5d84b8'], paladin: ['#e6c35c', '#4f86c6', '#c9443b'], hunter: ['#7bb04f', '#4f8fc6', '#b0763f'],
  rogue: ['#5fae4f', '#c9443b', '#6c5ab3'], priest: ['#d9d9e6', '#f0c96a', '#7a4bb3'], shaman: ['#3d7fd6', '#c9643b', '#3fb0a0'],
  mage: ['#9b59d6', '#e0662e', '#4fb8e6'], warlock: ['#7bb04f', '#a04bd0', '#e0662e'], druid: ['#4fa0d6', '#c9643b', '#5fbf5f'],
};
const KIND = { 'exact-order': ['ok', 'Exact guide order'], 'final-derived': ['info', 'Guide allocation · order derived'], priorities: ['warn', 'Priorities only'], adaptation: ['adapt', 'Companion adaptation'] };
function undoBuild(m) { const prev = (undo[m.id] || []).pop(); if (!prev) return; (redo[m.id] = redo[m.id] || []).push(m.build.slice()); m.build = sanitizeOrder(m.cls, prev); save(); renderTalents(); tpMsg('Undone', true); }
function redoBuild(m) { const nxt = (redo[m.id] || []).pop(); if (!nxt) return; (undo[m.id] = undo[m.id] || []).push(m.build.slice()); m.build = sanitizeOrder(m.cls, nxt); save(); renderTalents(); tpMsg('Redone', true); }
function renderGuidePanel() {
  const m = me(), sel = $('guideSel');
  const specs = [...new Set(GUIDES.filter(g => g.cls === m.cls).map(g => g.spec))];
  sel.innerHTML = specs.map(sp => '<optgroup label="' + esc(sp) + '">' + GUIDES.filter(g => g.cls === m.cls && g.spec === sp).map(g => '<option value="' + g.id + '"' + (g.id === m.guide ? ' selected' : '') + '>' + esc(g.label.replace(sp + ' · ', sp + ': ')) + (g.default ? '  ★' : '') + '</option>').join('') + '</optgroup>').join('');
  $('overlaySel').value = st.ui.overlay;
  const g = guideOf(m), k = KIND[g.kind];
  $('guideKind').innerHTML = '<span class="badge ' + k[0] + '" title="' + esc(k[1]) + '">' + esc({ 'exact-order': 'Exact order', 'final-derived': 'Derived order', priorities: 'Priorities only', adaptation: 'Adaptation' }[g.kind]) + '</span>';
  let h = '<div class="src"><a href="' + esc(g.source.url) + '" target="_blank" rel="noopener">' + esc(g.source.title) + ' ↗</a>' +
    '<span class="badge">' + esc(g.source.site) + (g.source.author ? ' · ' + esc(g.source.author) : '') + '</span>' + (g.source.updated ? '<span class="badge">' + esc(g.source.updated) + '</span>' : '') + '<span class="badge">Lv ' + esc(g.source.scope || '—') + '</span>' + (g.order.length ? '<span class="badge">' + g.order.length + ' pts</span>' : '') + '</div>';
  h += '<p>' + esc(g.note) + '</p>';
  if (g.adaptedFrom) h += '<p class="small">Adapted from: ' + g.adaptedFrom.map(u => '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(u.replace(/^https:\/\/(www\.)?/, '').split('/')[0]) + '</a>').join(' · ') + '</p>';
  if (g.trio) h += '<p class="trio"><b>Trio fit:</b> ' + esc(g.trio) + '</p>';
  if (g.priorities) h += '<p class="small"><b>What the guide says:</b> ' + esc(g.priorities) + '</p>';
  $('guideInfo').innerHTML = h;
  $('guideInfo').classList.toggle('hidden', !st.ui.guideInfo);
  $('guideInfoBtn').setAttribute('aria-expanded', String(!!st.ui.guideInfo));
  $('applyFull').disabled = !g.order.length;
}
function renderTalents() {
  const m = me(), Tr = T(), order = m.build, A = avail(), cap = capNow();
  const all = E.countsOf(order), lvlC = E.countsOf(order, A), tp = E.treePoints(Tr, all), g = guideOf(m);
  renderGuidePanel();
  const ov = st.ui.overlay;
  const gTarget = g.order.length && ov !== 'off' ? E.countsOf(g.order, ov === 'full' ? 51 : A) : {};
  const nx = g.order.length ? E.guideNext(Tr, g.order, order) : null;
  const off = g.order.length ? E.offGuide(g.order, order) : {};
  const keySet = new Set(ov !== 'off' ? g.key : []);
  $('stLine').innerHTML = '<b class="' + (order.length > A ? 'over' : '') + '">' + order.length + '</b> / ' + A + ' points' + (order.length ? ' · needs level ' + E.levelForPoints(order.length, m.talented) : '') + ' · <span class="split">' + tp.join(' / ') + '</span>';
  $('talentedSel').value = String(m.talented); $('planAhead').checked = st.ui.planAhead;
  $('undoBtn').disabled = !(undo[m.id] && undo[m.id].length); $('redoBtn').disabled = !(redo[m.id] && redo[m.id].length);
  const bn = $('tpBanner');
  if (A === 0) { bn.classList.remove('hidden'); bn.innerHTML = 'Talent points start at level <b>' + E.firstPointLevel(m.talented) + '</b>' + (m.talented ? ' (Legacy Talented ' + m.talented + ')' : '') + '. You can still plan ahead with <b>Plan ahead</b>.'; }
  else if (order.length > A) { bn.classList.remove('hidden'); bn.innerHTML = 'This plan uses <b>' + order.length + '</b> points; level ' + m.level + ' gives <b>' + A + '</b>. The last ' + (order.length - A) + ' are kept as <b>planned</b> (dashed tags) — nothing is lost when you lower the level.'; }
  else bn.classList.add('hidden');
  let nc = '';
  const btns = (can) => '<button class="btn sm gold" id="nextGuide"' + (can ? '' : ' disabled') + ' title="Learn exactly the next point of the guide">Spend next point</button><button class="btn sm" id="applyGuide" title="Replace the build with the guide up to your level">Follow to level ' + m.level + '</button>';
  if (g.kind === 'priorities') nc = '<span class="badge warn">◆</span><span class="nx-t">This guide only names key talents (◆ on the trees) — no point order.</span>';
  else if (nx) {
    const n = Tr.byKey[nx.key], lv = E.levelForPoint(nx.index, m.talented), blk = E.addBlocker(Tr, all, nx.key, cap);
    nc = icon(n.i, n.n, { size: 'xs2', fdid: n.f, attrs: ' data-tip="talent" data-k="' + n.k + '"' }) + '<span class="nx-t"><b>Next: ' + esc(n.n) + ' ' + nx.rank + '/' + n.m + '</b> <small>level ' + lv + (blk ? (order.length >= cap ? ' · no free point yet' : ' · ' + esc(blk.text)) : '') + '</small></span>' +
      (Object.keys(off).length ? '<span class="badge warn" title="Points in talents the guide does not take">' + Object.values(off).reduce((a, b) => a + b, 0) + ' off-guide</span>' : '') + btns(!blk);
  } else nc = '<span class="badge ok">✓</span><span class="nx-t">Build contains the whole guide' + (Object.keys(off).length ? ' (+' + Object.values(off).reduce((a, b) => a + b, 0) + ' extra)' : '') + '.</span>' + btns(false);
  $('nextCallout').innerHTML = nc;
  const firstLvl = E.firstPointLevel(m.talented), bgs = TREE_BG[m.cls] || ['#888', '#888', '#888'];
  $('trees').innerHTML = Tr.trees.map((tr, ti) => {
    const nodes = Tr.nodes.filter(n => n.t === ti), col = bgs[ti];
    let cells = '';
    for (let r = 1; r <= 7; r++) cells += '<div class="rowlbl' + (tp[ti] >= (r - 1) * 5 ? ' open' : '') + '" style="grid-row:' + r + '" title="Earliest level for row ' + r + ' with every point in this tree">' + (firstLvl + (r - 1) * 5) + '</div>';
    cells += nodes.map(n => {
      const have = all[n.k] || 0, haveL = lvlC[n.k] || 0, blk = have ? null : E.addBlocker(Tr, all, n.k, 51);
      const locked = !have && blk && (blk.code === 'row' || blk.code === 'prereq');
      const cl = ['tal', have >= n.m ? 'max' : have ? 'part' : locked ? 'lock' : 'avail'];
      if (gTarget[n.k]) cl.push('guide');
      if (nx && nx.key === n.k && ov !== 'off') cl.push('next');
      return '<button class="' + cl.join(' ') + '" style="grid-column:' + (n.c + 1) + ';grid-row:' + n.r + '" data-tip="talent" data-k="' + n.k + '" aria-label="' + esc(n.n + ', rank ' + have + ' of ' + n.m) + '">' +
        icon(n.i, n.n, { fdid: n.f }) + '<span class="rk">' + have + '/' + n.m + '</span>' +
        (have > haveL ? '<span class="plan" title="Planned beyond your level">+' + (have - haveL) + '</span>' : '') +
        (gTarget[n.k] ? '<span class="gpip" title="Guide ranks ' + (ov === 'full' ? '(full build)' : 'at level ' + m.level) + '">' + gTarget[n.k] + '</span>' : keySet.has(n.k) ? '<span class="key" title="Key talent named by the guide">◆</span>' : '') +
        (off[n.k] ? '<span class="off" title="Not in the selected guide"></span>' : '') + '</button>';
    }).join('');
    const nextRow = [5, 10, 15, 20, 25, 30].find(x => x > tp[ti]);
    const hIcon = tr.i || nodes[0].i;
    return '<section class="tree" data-tree="' + ti + '"><div class="tree-bg" style="background:radial-gradient(120% 70% at 50% 0,' + col + '33,transparent 70%),linear-gradient(180deg,' + col + '14,#0000 60%)"></div>' +
      '<div class="tree-h">' + icon(hIcon, tr.n, { fdid: tr.f }) + '<h3>' + esc(tr.n) + '</h3><span class="pts">' + tp[ti] + '</span><button class="reset" data-resettree="' + ti + '" title="Remove all points in this tree">Reset</button></div>' +
      '<div class="grid">' + cells + '<svg class="arrows" aria-hidden="true"></svg></div>' +
      '<div class="tree-foot"><span>' + (nextRow ? 'Next row at ' + nextRow + ' points' : 'All rows open') + '</span><span>' + nodes.reduce((a, n) => a + (all[n.k] || 0), 0) + ' / ' + nodes.reduce((a, n) => a + n.m, 0) + '</span></div></section>';
  }).join('');
  drawArrows(); requestAnimationFrame(drawArrows);
  renderLower(); renderSaved();
}
function drawArrows() {
  const m = me(); if (!m) return; const Tr = T(), all = E.countsOf(m.build);
  document.querySelectorAll('#trees .tree').forEach(sec => {
    const ti = Number(sec.dataset.tree), grid = sec.querySelector('.grid'), svg = sec.querySelector('svg.arrows');
    const gr = { width: grid.clientWidth, height: grid.clientHeight };
    const box = el => ({ x: el.offsetLeft + el.offsetWidth / 2, y: el.offsetTop + el.offsetHeight / 2, w: el.offsetWidth, h: el.offsetHeight });
    let out = '<defs><marker id="ah' + ti + 'y" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#ffd100"/></marker><marker id="ah' + ti + 'g" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#7d7d7d"/></marker></defs>';
    Tr.arrows.forEach(([a, b]) => {
      const na = Tr.byKey[a]; if (na.t !== ti) return;
      const ea = grid.querySelector('[data-k="' + a + '"]'), eb = grid.querySelector('[data-k="' + b + '"]'); if (!ea || !eb) return;
      const pa = box(ea), pb = box(eb), ax = pa.x, ay = pa.y, bx = pb.x, by = pb.y;
      const met = (all[a] || 0) >= na.m, color = met ? '#ffd100' : '#7d7d7d', mk = 'url(#ah' + ti + (met ? 'y' : 'g') + ')';
      let d;
      if (Math.abs(ax - bx) < 2) d = 'M' + ax + ' ' + (ay + pa.h / 2 + 6) + ' L' + bx + ' ' + (by - pb.h / 2 - 7);
      else if (Math.abs(ay - by) < 2) { const dir = bx > ax ? 1 : -1; d = 'M' + (ax + dir * (pa.w / 2 + 6)) + ' ' + ay + ' L' + (bx - dir * (pb.w / 2 + 8)) + ' ' + by; }
      else d = 'M' + ax + ' ' + (ay + pa.h / 2 + 6) + ' L' + ax + ' ' + by + ' L' + (bx - (bx > ax ? 1 : -1) * (pb.w / 2 + 8)) + ' ' + by;
      out += '<path d="' + d + '" stroke="#000" stroke-width="7" fill="none" stroke-linecap="round" opacity=".85"/><path d="' + d + '" stroke="' + color + '" stroke-width="3.5" fill="none" stroke-linecap="round" marker-end="' + mk + '"/>';
    });
    svg.setAttribute('width', gr.width); svg.setAttribute('height', gr.height); svg.setAttribute('viewBox', '0 0 ' + gr.width + ' ' + gr.height);
    svg.innerHTML = out;
  });
}
function pickCell(Tr, k, rank) { const n = Tr.byKey[k]; return '<span class="who">' + icon(n.i, n.n, { size: 'xs', fdid: n.f }) + esc(n.n) + ' <span class="small">' + rank + '/' + n.m + '</span></span>'; }
function renderLower() {
  document.querySelectorAll('#lowerTabs button').forEach(b => b.classList.toggle('on', b.dataset.t === st.ui.lower));
  $('lowerProg').classList.toggle('hidden', st.ui.lower !== 'prog'); $('lowerCmp').classList.toggle('hidden', st.ui.lower !== 'cmp'); $('lowerSaved').classList.toggle('hidden', st.ui.lower !== 'saved');
  $('savedTab').textContent = 'Saved builds' + (me().saved.length ? ' (' + me().saved.length + ')' : '');
  const m = me(), Tr = T(), g = guideOf(m), order = m.build, A = avail();
  const nx = g.order.length ? E.guideNext(Tr, g.order, order) : null;
  if (st.ui.lower === 'prog') {
    const n = Math.max(g.order.length, order.length, Math.min(A, 51));
    const gc = {}, mc = {}; let rows = '';
    for (let i = 0; i < n; i++) {
      const gk = g.order[i], mk = order[i];
      if (gk) gc[gk] = (gc[gk] || 0) + 1; if (mk) mc[mk] = (mc[mk] || 0) + 1;
      const lv = E.levelForPoint(i, m.talented), future = i >= A;
      let s = '<span class="st todo">—</span>';
      if (gk && mk) s = gk === mk ? '<span class="st ok">✓ match</span>' : '<span class="st diff">≠ differs</span>';
      else if (gk && !mk) s = nx && nx.index === i ? '<span class="st next">▶ next</span>' : '<span class="st todo">to do</span>';
      else if (mk && !gk) s = '<span class="st diff">extra</span>';
      rows += '<tr class="' + (lv === m.level ? 'cur ' : '') + (future ? 'future ' : '') + (nx && nx.index === i ? 'nextrow' : '') + '"><td>' + lv + '</td><td>' + (gk ? pickCell(Tr, gk, gc[gk]) : '<span class="small">' + (g.order.length ? '—' : 'no order') + '</span>') + '</td><td>' + (mk ? pickCell(Tr, mk, mc[mk]) : '<span class="small">—</span>') + '</td><td>' + s + '</td></tr>';
    }
    $('lowerProg').innerHTML = (g.order.length ? '' : '<p class="small">The selected guide has no point order. The table shows your own plan.</p>') +
      '<div class="prog"><table><thead><tr><th>Level</th><th>Guide</th><th>Your plan</th><th>Status</th></tr></thead><tbody>' + rows + '</tbody></table></div>' +
'';
    const cur = $('lowerProg').querySelector('tr.nextrow') || $('lowerProg').querySelector('tr.cur');
    if (cur && cur.offsetTop) $('lowerProg').querySelector('.prog').scrollTop = Math.max(0, cur.offsetTop - 120);
  } else {
    const others = GUIDES.filter(x => x.cls === m.cls && x.id !== g.id && x.order.length);
    const bId = m.cmp && others.some(x => x.id === m.cmp) ? m.cmp : '';
    const b = bId ? GUIDES.find(x => x.id === bId) : null;
    const aC = E.countsOf(g.order), bC = b ? E.countsOf(b.order) : E.countsOf(order);
    const cmp = E.compareCounts(Tr, aC, bC), sp = c => E.treePoints(Tr, c).join('/');
    let h = '<div class="guide-row"><span class="small">Compare <b>' + esc(g.label) + '</b> with</span><select class="select" id="cmpSel"><option value="">My build</option>' + others.map(x => '<option value="' + x.id + '"' + (x.id === bId ? ' selected' : '') + '>' + esc(x.label) + '</option>').join('') + '</select></div>';
    if (!g.order.length) h += '<p class="small">The selected guide has no allocation to compare (priorities only).</p>';
    else {
      h += '<p class="small" style="margin-top:8px">Split: <b>' + sp(aC) + '</b> vs <b>' + sp(bC) + '</b> · shared points: <b>' + cmp.shared + '</b> of ' + g.order.length + '</p>';
      h += '<div class="cmp prog"><table><thead><tr><th>Talent</th><th>' + esc(g.spec) + ' guide</th><th>' + (b ? 'Other guide' : 'My build') + '</th></tr></thead><tbody>' +
        (cmp.rows.map(r => { const n = Tr.byKey[r.key]; return '<tr><td>' + pickCell(Tr, r.key, n.m).replace(/<span class="small">[^<]*<\/span>/, '<span class="small">' + esc(Tr.trees[n.t].n) + '</span>') + '</td><td>' + r.a + '/' + n.m + '</td><td class="' + (r.b > r.a ? 'more' : 'less') + '">' + r.b + '/' + n.m + '</td></tr>'; }).join('') || '<tr><td colspan="3">Identical allocations.</td></tr>') + '</tbody></table></div>';
    }
    $('lowerCmp').innerHTML = h;
  }
}
function renderSaved() {
  const m = me(), list = m.saved;
  $('savedList').innerHTML = list.length ? list.map((x, i) => { const sp = E.treePoints(T(), E.countsOf(x.order)).join('/'); return '<div class="row"><b title="' + esc(x.name) + '">' + esc(x.name) + '</b><small>' + sp + ' · ' + x.order.length + ' pts</small><button class="btn sm" data-load="' + i + '">Load</button><button class="btn sm danger" data-del="' + i + '">Delete</button></div>'; }).join('') : '<p class="small">No saved builds yet — use ⋯ → Save build as…</p>';
}
function buildText(m) {
  const Tr = TREES[m.cls], order = m.build, c = E.countsOf(order), g = guideOf(m);
  let t = 'WoW Forever — ' + m.name + ' (' + CM[m.cls].n + ') talents (' + E.treePoints(Tr, c).join('/') + ', ' + order.length + ' points)\nBuild code: ' + E.encodeBuild(Tr, m.cls, order) + '\nGuide followed: ' + g.label + ' — ' + g.source.url + '\n\n';
  Tr.trees.forEach((tr, ti) => { const ns = Tr.nodes.filter(n => n.t === ti && c[n.k]); if (ns.length) t += tr.n + ': ' + ns.map(n => n.n + ' ' + c[n.k] + '/' + n.m).join(', ') + '\n'; });
  t += '\nLevelling order:\n'; const rc = {};
  order.forEach((k, i) => { rc[k] = (rc[k] || 0) + 1; t += 'Level ' + E.levelForPoint(i, m.talented) + ': ' + Tr.byKey[k].n + ' (' + rc[k] + '/' + Tr.byKey[k].m + ')\n'; });
  return t;
}

/* ------------------------------------------------------------ squad view */
/** Move a member to a new index (drag & drop or keyboard). */
function moveMember(s, id, toIndex) {
  const from = s.members.findIndex(x => x.id === id); if (from < 0) return false;
  const to = Math.max(0, Math.min(s.members.length - 1, toIndex | 0)); if (to === from) return false;
  const [x] = s.members.splice(from, 1); s.members.splice(to, 0, x); return true;
}
/** With "Link levels" on, every follower has the leader's level. */
function applyLink(s) { const L = leaderOf(s); if (s && s.linkLevels && L) s.members.forEach(x => { x.level = L.level; }); }
function memberCard(m, s) {
  const Tr = TREES[m.cls], A = avail(m), sp = E.treePoints(Tr, E.countsOf(m.build, A)), g = guideOf(m);
  const nx = g.order.length ? E.guideNext(Tr, g.order, m.build.slice(0, A)) : null;
  const L = leaderOf(s), isCur = s.current === m.id;
  const units = E.UNITS.map(u => '<option value="' + u + '"' + (u === m.unit ? ' selected' : '') + '>' + UNIT_N[u] + '</option>').join('');
  const linked = s.linkLevels && !m.leader, diff = L && !m.leader && L.level !== m.level;
  return '<article class="mcard' + (isCur ? ' cur' : '') + '" style="--mc:' + CM[m.cls].color + '" draggable="true" data-mdrag="' + m.id + '">' +
    '<div class="mhead">' + classIcon(m.cls, '') + '<div class="mname"><b>' + esc(m.name) + (m.leader ? ' <span class="crown" title="Squad leader">♛</span>' : '') + '</b><small>' + esc(RACE[m.race].n) + ' ' + esc(CM[m.cls].n) + ' · ' + ROLE_N[m.role] + '</small></div>' +
    '<div class="mlvl">' + (linked ? '<output title="Linked to the leader\'s level (squad bar)">🔗 ' + m.level + '</output>' :
      '<button class="step" data-mlvl="-1" data-mid="' + m.id + '" title="Level down">−</button><output title="Level">' + m.level + '</output><button class="step" data-mlvl="1" data-mid="' + m.id + '" title="Level up">+</button>' +
      (diff ? '<button class="step match" data-mmatch="' + m.id + '" title="Set to the leader\'s level (' + L.level + ')">=' + L.level + '</button>' : '')) + '</div>' +
    '<details class="menu"><summary class="btn sm ghost" title="More">⋯</summary><div class="menu-pop right">' +
    '<button class="mi" data-medit="' + m.id + '">Edit character…</button>' + (m.leader ? '' : '<button class="mi" data-mlead="' + m.id + '">♛ Make leader</button>') +
    '<button class="mi" data-mup="' + m.id + '">◀ Move left</button><button class="mi danger" data-mdel="' + m.id + '">Remove</button></div></details></div>' +
    '<div class="mbody">' +
    '<div class="mline"><span>Talents</span><b>' + sp.join(' / ') + '</b>' + (unspent(m) ? '<em class="unsp" title="Unspent talent points">' + unspent(m) + ' free</em>' : '') + '<small>' + (nx && nx.index < A ? 'next: ' + esc(Tr.byKey[nx.key].n) : g.order.length ? 'up to date' : '') + '</small></div>' +
    '<div class="mline"><span>Guide</span><b title="' + esc(g.label) + '">' + esc(g.spec) + '</b><small>' + esc(g.source.site) + '</small></div>' +
    '<div class="mline"><span>Sequence</span>' + (E.seqSupported(m.cls) ? '<select class="select sm" data-mseq="' + m.id + '" title="One-key rotations (/castsequence). Off = normal keys only">' + E.SEQ_TIERS.map(t => '<option value="' + t + '"' + (t === (m.seq || 'off') ? ' selected' : '') + '>' + SEQ_N[t] + '</option>').join('') + '</select>' : '<small title="Paladin, Priest and Warlock first">not yet for ' + esc(CM[m.cls].n) + '</small>') + '</div>' +
    '<div class="mline"><span>Target</span>' + (m.leader ? '<b>Leader</b>' : '<b>via</b><select class="select sm" data-munit="' + m.id + '" title="Which unit the leader is on this character (Setup → Check party order)">' + units + '</select>') + '</div>' +
    '</div><div class="mfoot">' +
    '<button class="btn sm gold" data-open="kit" data-mid="' + m.id + '">Kit</button><button class="btn sm" data-open="talents" data-mid="' + m.id + '">Talents</button><button class="btn sm" data-open="spellbook" data-mid="' + m.id + '">Spells</button></div></article>';
}
/** What needs doing after levelling: unspent talent points and new spells/ranks at the current level. */
function todoStrip(s) {
  const items = [];
  s.members.forEach(m => {
    const u = unspent(m);
    if (u) items.push('<button class="todo-i" data-open="talents" data-mid="' + m.id + '"><i style="background:' + CM[m.cls].color + '"></i><b>' + esc(m.name) + '</b> ' + u + ' talent point' + (u > 1 ? 's' : '') + ' to spend</button>');
    const fresh = spellsOf(m).filter(x => x.gate !== 'racial' && (x.level === m.level || (x.ranks || []).some(r => r.l === m.level && r.r > 1)) && (x.gate !== 'talent' || buildHas(m, x.talent, m.level)));
    if (seqChangedNow(m)) items.push('<button class="todo-i" data-open="kit" data-mid="' + m.id + '"><i style="background:' + CM[m.cls].color + '"></i><b>' + esc(m.name) + '</b> sequence changed: copy it again</button>');
    if (fresh.length) items.push('<button class="todo-i" data-open="kit" data-mid="' + m.id + '"><i style="background:' + CM[m.cls].color + '"></i><b>' + esc(m.name) + '</b> trainer: ' + esc(fresh.slice(0, 2).map(x => x.name).join(', ')) + (fresh.length > 2 ? ' +' + (fresh.length - 2) : '') + '</button>');
  });
  return items.length ? '<div class="todo"><span class="todo-h">To do</span>' + items.join('') + '</div>' : '';
}
function renderSquad() {
  const s = sq();
  const chips = st.squads.map(x => '<button class="sqchip' + (s && x.id === s.id ? ' on' : '') + '" data-squad="' + x.id + '"><b>' + esc(x.name) + '</b><span class="dots">' + x.members.map(m => '<i style="background:' + CM[m.cls].color + '" title="' + esc(m.name) + '"></i>').join('') + '</span></button>').join('') +
    '<button class="sqchip add" id="newSquad" title="Create a new squad">＋ New squad</button>';
  if (!s) { $('squadBody').innerHTML = '<div class="sqlist">' + chips + '</div>'; return; }
  const notes = (s.members.length > 5 ? '<span class="badge warn" title="A party holds 5 characters">More than 5 — not one party</span>' : '') +
    (s.members.some(m => RACE[m.race].f !== s.faction) ? '<span class="badge warn" title="Cross-faction characters cannot group">Mixed factions</span>' : '');
  $('squadBody').innerHTML = '<div class="sqlist">' + chips + '</div>' +
    '<div class="sqbar"><input class="input" id="sqName" value="' + esc(s.name) + '" maxlength="40" aria-label="Squad name" title="Rename squad">' +
    '<select class="select" id="sqFaction" title="Faction"><option value="horde"' + (s.faction === 'horde' ? ' selected' : '') + '>Horde</option><option value="alliance"' + (s.faction === 'alliance' ? ' selected' : '') + '>Alliance</option></select>' + notes +
    '<span style="flex:1"></span><label class="small linklv" title="Followers always have the leader\'s level: level the leader (or anyone) and the whole squad follows"><input type="checkbox" id="sqLink"' + (s.linkLevels ? ' checked' : '') + '> 🔗 Link levels</label><button class="btn sm" id="levelAll" title="Every member gains a level">+1 level all</button>' + (s.linkLevels ? '' : '<button class="btn sm" id="syncLevels" title="Set every member to the leader\'s level">Sync levels</button>') +
    '<details class="menu"><summary class="btn sm" title="Squad actions">⋯</summary><div class="menu-pop right">' +
    '<button class="mi" id="squadSheet">Download all kits (.txt)</button><button class="mi" id="dupSquad">Duplicate squad</button><button class="mi" id="exportSquad">Export this squad (.json)</button>' +
    '<button class="mi" id="exportAll">Export all squads (.json)</button><label class="mi filelbl">Import .json…<input type="file" id="importAll" accept=".json,application/json"></label>' +
    '<hr><button class="mi danger" id="delSquad">Delete squad</button></div></details></div>' +
    todoStrip(s) +
    '<div class="mgrid">' + s.members.map(m => memberCard(m, s)).join('') +
    (s.members.length < MAX_MEMBERS ? '<button class="mcard addcard" id="addMember"><span>＋</span><b>Add character</b></button>' : '') + '</div>';
}
function openMemberDlg(id) {
  const s = sq(), m = id ? s.members.find(x => x.id === id) : null;
  const cls = m ? m.cls : 'warrior';
  $('mdTitle').textContent = m ? 'Edit ' + m.name : 'Add character to ' + s.name;
  $('mdName').value = m ? m.name : '';
  $('mdClass').innerHTML = CLASSES.map(c => '<option value="' + c + '"' + (c === cls ? ' selected' : '') + '>' + CM[c].n + '</option>').join('');
  $('mdLevel').value = m ? m.level : (leaderOf(s) ? leaderOf(s).level : 1);
  $('mdTalented').value = String(m ? m.talented : (leaderOf(s) ? leaderOf(s).talented : 0));
  $('memberDlg').dataset.mid = id || '';
  fillMemberSelects(m ? m.race : null, m ? m.role : null);
  $('mdClass').disabled = !!(m && (m.build.length || m.saved.length));
  $('mdClassNote').textContent = m && (m.build.length || m.saved.length) ? 'Class is locked while this character has talent points or saved builds (reset/delete them to change class).' : '';
  $('memberDlg').showModal(); $('mdName').focus();
}
function fillMemberSelects(race, role) {
  const s = sq(), cls = $('mdClass').value;
  const races = RACES.filter(r => r.c.includes(cls)).sort((a, b) => (a.f === s.faction ? 0 : 1) - (b.f === s.faction ? 0 : 1));
  $('mdRace').innerHTML = races.map(r => '<option value="' + r.k + '"' + (r.k === race ? ' selected' : '') + '>' + r.n + (r.f !== s.faction ? ' (' + (r.f === 'alliance' ? 'Alliance' : 'Horde') + ')' : '') + '</option>').join('');
  $('mdRole').innerHTML = CM[cls].roles.map(r => '<option value="' + r + '"' + (r === role ? ' selected' : '') + '>' + ROLE_N[r] + '</option>').join('');
}
function saveMemberDlg() {
  const s = sq(), id = $('memberDlg').dataset.mid, name = $('mdName').value.trim();
  const data = { name: name || CM[$('mdClass').value].n, cls: $('mdClass').value, race: $('mdRace').value, role: $('mdRole').value, level: $('mdLevel').value, talented: $('mdTalented').value };
  if (id) {
    const m = s.members.find(x => x.id === id); if (!m) return;
    const clsChanged = m.cls !== data.cls;
    const roleChanged = m.role !== data.role && !m.build.length;
    if (clsChanged) delete undo[m.id];
    Object.assign(m, newMember(Object.assign({}, m, data, clsChanged ? { build: [], guide: null, saved: [] } : roleChanged ? { guide: null } : {})));
    toast('Saved ' + m.name);
  } else {
    if (s.members.length >= MAX_MEMBERS) { toast('A squad holds up to ' + MAX_MEMBERS + ' characters', true); return; }
    const m = newMember(Object.assign(data, { leader: !s.members.length, unit: 'party1' }));
    s.members.push(m); s.current = m.id; toast(m.name + ' added');
  }
  fixLeader(s); applyLink(s); $('memberDlg').close(); render();
}

/* ------------------------------------------------------------ setup */
function utilities() {
  const m = me(), s = sq(), L = leaderOf(s), u = E.units(m.unit), out = [];
  out.push({ t: 'Check party order', d: 'Prints party1–party4 on this character, so you can pick the right unit for each follower.', c: '/run for i=1,4 do print("party"..i, UnitName("party"..i) or "-") end' });
  if (!m.leader) {
    out.push({ t: 'Follow ' + (L ? L.name : 'the leader'), d: 'One manual key press on this character.', c: '/follow ' + u.main });
    out.push({ t: 'Assist ' + (L ? L.name : 'the leader'), d: 'Take the leader\'s target as your own target.', c: '/assist ' + u.main });
    out.push({ t: 'Set the leader as focus', d: 'Only for focus mode: target the leader, then press once.', c: '/focus [@target,help,nodead]' });
  } else {
    out.push({ t: 'Mark the target', d: 'Puts a skull on your target so followers can see the kill target.', c: '/run SetRaidTarget("target",8)' });
  }
  if (m.cls === 'warlock' || m.cls === 'hunter') {
    const chain = m.leader ? '[@mouseover,harm,nodead][harm,nodead]' : '[@mouseover,harm,nodead][@' + u.mainTarget + ',harm,nodead][harm,nodead]';
    out.push({ t: 'Send pet (assist)', d: 'Pet attacks the same target as your damage macros, without casting.', c: '#showtooltip\n/petattack ' + chain });
    out.push({ t: 'Recall pet', d: 'Passive + follow. Use before crowd control or to reset a bad pull.', c: '/petpassive\n/petfollow' });
    out.push({ t: 'Pet stay', d: 'Park the pet while you handle a tricky pack.', c: '/petstay' });
  }
  if (!m.leader) out.push({ t: 'Target ' + (L ? L.name : 'the leader'), d: 'Select the leader for a manual heal or buff.', c: '/target ' + u.main });
  return out;
}
function renderSetup() {
  const u = utilities(), s = sq();
  $('util').innerHTML = u.map((x, i) => '<article><h3>' + esc(x.t) + '</h3><p>' + esc(x.d) + '</p><pre class="code">' + esc(x.c) + '</pre><button class="btn sm" data-util="' + i + '">Copy macro</button></article>').join('');
  $('rules').innerHTML = s.members.map(m => '<article><h3 style="color:' + CM[m.cls].color + '">' + esc(m.name) + ' <span class="small">' + esc(CM[m.cls].n) + '</span></h3><p>' + ruleText(m) + '</p></article>').join('') +
    '<article><h3>partyN vs focus</h3><p><b>partyN</b> is relative to each character: on every follower, pick the party slot that holds the leader (use “Check party order”). <b>focus</b> is explicit, but you must set the leader as focus on each follower after every login.</p><p>All macros use spell names without ranks, so the highest learned rank is cast, and stay below the 255-character macro limit.</p></article>' +
    '<article><h3>Sequences (opt-in)</h3><p>Turn them on per character on the Squad page or in the Kit. A sequence key uses WoW\'s own <code>/castsequence</code>: one press, one cast, on one character. It does not move on when a cast fails (cooldown, range, line of sight), so long cooldowns stay on their own keys and the number of filler casts is chosen so short cooldowns are ready again. The Paladin gets a priority list instead, because all its attacks have cooldowns. No addons, no key broadcasting.</p></article>';
  renderDiag();
  const ref = (url, t) => '<li><a href="' + url + '" target="_blank" rel="noopener">' + esc(t) + '</a></li>';
  $('sources').innerHTML = '<div><h3>Game data</h3><ul>' +
    ref('https://zephras.com/data/', 'Zephras talent data (client files, CC BY 4.0)') +
    ref('https://theforeverera.com/en/talents/', 'The Forever Era talent pages (build 1.60.1.70532 + hotfixes)') +
    ref('https://wowforevertalents.com/about/', 'wowforevertalents.com (client 70532 + server hotfix cache)') +
    ref('https://theforeverera.com/en/spells/', 'The Forever Era spellbooks') + ref('https://wowforevertalents.com/racials/', 'wowforevertalents racials') +
    '</ul><p>All nine classes: talent grid, ranks, prerequisites, icons and rank texts are embedded. Mage uses The Forever Era\'s 70532 tree (Frost/Fire hotfixes), the other classes Zephras client data cross-checked with The Forever Era. Paladin: Divine Precision requires Holy Shock (newer sources).</p></div>' +
    '<div><h3>Guides (researched 26 Oct 2026)</h3><p>' + GUIDES.length + ' guides from Wowhead, Mobalytics, WowVendor, Warcraft Tavern, Icy Veins, Method and The Forever Era. Each guide shows its link, author and whether it is an exact order, an allocation with derived order, or priorities only.</p>' +
    '<details><summary class="small" style="cursor:pointer">Reviewed but not included (' + D.reviewedNotIncluded.length + ')</summary><ul>' + D.reviewedNotIncluded.map(x => '<li>' + esc(CM[x.cls] ? CM[x.cls].n : x.cls) + ': ' + esc(x.title) + ' — ' + esc(x.reason) + '</li>').join('') + '</ul></details>' +
    '<p>Zephras data is used under CC BY 4.0 (credit: Zephras, zephras.com) and was changed by this app. World of Warcraft names, texts and icons © Blizzard Entertainment.</p></div>';
}
function renderDiag() {
  const nodes = CLASSES.reduce((a, c) => a + TREES[c].nodes.length, 0);
  const withIcon = CLASSES.reduce((a, c) => a + TREES[c].nodes.filter(n => n.i).length, 0);
  const guideOk = GUIDES.filter(g => !E.validateOrder(TREES[g.cls], g.order)).length;
  let longest = 0;
  SPELLS.concat([ENGAGE]).forEach(s => E.UNITS.concat(['leader']).forEach(u => { longest = Math.max(longest, E.makeMacro(s, u === 'leader' ? { leader: true } : { leader: false, unit: u }).length); }));
  const item = (v, t, ok) => '<div><b style="color:' + (ok ? '#8be0a6' : '#ffb98a') + '">' + v + '</b>' + t + '</div>';
  $('diag').innerHTML = item(nodes, ' talents embedded for 9 classes', nodes > 450) +
    item(withIcon + ' / ' + nodes, 'talents with a verified icon name', withIcon === nodes) +
    item(guideOk + ' / ' + GUIDES.length, 'guides pass every row / prerequisite rule', guideOk === GUIDES.length) +
    item(SPELLS.length, 'class spells with rank data (+ racials for 10 races)', SPELLS.every(s => s.ranks.length)) +
    item(longest + ' chars', 'longest generated macro, any unit (limit 255)', longest <= 255) +
    '<div id="iconProbe"><b style="color:#a9ddff">checking…</b>icon images ' + (window.ICON_DATA ? '(offline pack embedded)' : '(Wowhead image CDN)') + '</div>' +
    item(st.squads.length + ' squads · ' + st.squads.reduce((a, s) => a + s.members.length, 0) + ' characters', 'saved locally in this browser', true);
  const set = (v, ok) => { const el = $('iconProbe'); if (el) el.querySelector('b').outerHTML = '<b style="color:' + (ok ? '#8be0a6' : '#ffb98a') + '">' + v + '</b>'; };
  if (window.ICON_DATA) set(Object.keys(window.ICON_DATA).length + ' embedded', true);
  else { const probe = new Image(); probe.onload = () => set('CDN reachable', true); probe.onerror = () => set('CDN unreachable', false); probe.src = ICON_CDN('spell_holy_holybolt') + '?probe=' + Date.now(); }
}

/* ------------------------------------------------------------ main render */
const JUMPS = [1, 10, 20, 30, 40, 50, 60];
function render() {
  const s = sq(), m = me();
  if (!m && st.view !== 'squad') st.view = 'squad';
  document.body.style.setProperty('--cls', m ? CM[m.cls].color : '#e8c172');
  $('memberTabs').innerHTML = s ? s.members.map(x => '<button class="classtab" style="--tc:' + CM[x.cls].color + '" data-pick="' + x.id + '" aria-pressed="' + (m && x.id === m.id && st.view !== 'squad') + '" title="' + esc(x.name + ' — ' + RACE[x.race].n + ' ' + CM[x.cls].n + ', level ' + x.level) + '">' + classIcon(x.cls, 'xs2') + '<span><b>' + esc(x.name) + (x.leader ? ' ♛' : '') + '</b><small>' + x.level + '</small></span>' + (unspent(x) ? '<i class="dot" title="' + unspent(x) + ' unspent talent point' + (unspent(x) > 1 ? 's' : '') + '"></i>' : '') + '</button>').join('') : '';
  $('squadPick').innerHTML = st.squads.map(x => '<option value="' + x.id + '"' + (s && x.id === s.id ? ' selected' : '') + '>' + esc(x.name) + '</option>').join('');
  document.querySelectorAll('.viewtab').forEach(b => b.setAttribute('aria-selected', String(b.dataset.view === st.view)));
  $('controlbar').classList.toggle('hidden', !m || st.view === 'squad');
  if (m) {
    $('lvlOut').textContent = m.level; $('lvlRange').value = m.level;
    $('jumps').innerHTML = JUMPS.map(j => '<button class="jump' + (j === m.level ? ' on' : '') + '" data-jump="' + j + '">' + j + '</button>').join('');
    $('unitBox').innerHTML = m.leader ? '<span class="badge ok">♛ Squad leader</span>' : '<span class="ctl-label">Leader is</span><select class="select" id="unitSel">' + E.UNITS.map(u => '<option value="' + u + '"' + (u === m.unit ? ' selected' : '') + '>' + u + '</option>').join('') + '</select>';
  }
  ['squad', 'kit', 'spellbook', 'talents', 'setup'].forEach(v => $('view-' + v).classList.toggle('hidden', st.view !== v));
  const who = m ? m.name + ' · ' + RACE[m.race].n + ' ' + CM[m.cls].n : '';
  const titles = { squad: 'Your squads', kit: m ? m.name + ' · Everyday Kit' : '', spellbook: m ? m.name + ' · Spellbook' : '', talents: m ? m.name + ' · Talents' : '', setup: m ? m.name + ' · Setup' : 'Setup' };
  const subs = {
    squad: 'Your multibox squads. Each character keeps its own level, talents, guide and macros — saved automatically in this browser.',
    kit: m ? ROLE_N[m.role] + (m.leader ? ' · squad leader' : ' · follows the leader via ' + m.unit) + '. Copy a key and paste it into WoW.' : '',
    spellbook: 'Every Forever trainer, talent, quest and racial ability for this character, with rank-aware tooltips. Hover an icon; click Copy for its macro.',
    talents: 'All three Forever trees with real positions, ranks and prerequisites. Follow a guide point by point.',
    setup: 'Targeting rules, helper macros, a data self-check and every source used.',
  };
  $('ctxEyebrow').textContent = st.view === 'squad' ? 'MULTIBOX COMPANION · SAVED IN THIS BROWSER' : (m ? (RACE[m.race].n + ' ' + CM[m.cls].n).toUpperCase() + ' · LEVEL ' + m.level + ' · ' + ROLE_N[m.role].toUpperCase() + (m.leader ? ' · LEADER' : '') : '');
  $('ctxTitle').textContent = titles[st.view];
  $('ctxActions').innerHTML = st.view === 'kit' ? '<button class="btn sm" id="copyKit" title="Copy every macro of this level">Copy all</button><button class="btn sm" id="exportKit" title="Download as .txt">Export .txt</button>' : '';
  if (!st.ui.tipSeen) $('tipBar').classList.remove('hidden');
  if (st.view === 'squad') renderSquad();
  if (st.view === 'kit') renderKit();
  if (st.view === 'spellbook') renderBook();
  if (st.view === 'talents') renderTalents();
  if (st.view === 'setup') renderSetup();
  save();
}
function setLevel(v) { const m = me(), s = sq(); if (!m) return; const t = s && s.linkLevels && leaderOf(s) ? leaderOf(s) : m; t.level = clampLvl(v); applyLink(s); render(); }

/* ------------------------------------------------------------ import / export */
function exportAllJson() { return JSON.stringify({ format: 'forever-companion/8', exported: new Date().toISOString(), state: st }, null, 1); }
function importJson(j) {
  if (j && j.format === 'forever-companion/8' && j.state && Array.isArray(j.state.squads)) {
    if (!confirm('Replace all squads in this browser with the ' + j.state.squads.length + ' squad(s) in the file? (Tip: export first as a backup.)')) return 'cancelled';
    const seen = new Set();
    st.squads = j.state.squads.slice(0, 30).map(newSquad).map(s => { if (seen.has(s.id)) s.id = uid('s'); seen.add(s.id); return s; });
    st.active = st.squads[0] && st.squads[0].id; applyUi(j.state.ui); Object.keys(undo).forEach(k => delete undo[k]); return 'Imported ' + st.squads.length + ' squad(s)';
  }
  if (j && j.format === 'forever-companion/8-squad' && j.squad) {
    const src = Object.assign({}, j.squad, { id: null, members: (j.squad.members || []).map(x => Object.assign({}, x, { id: null })) });
    const s = newSquad(src); st.squads.push(s); st.active = s.id; return 'Squad “' + s.name + '” added';
  }
  if (j && j.format === 'forever-trio-companion/7' && j.state) {
    const s = migrateV7(j.state, true); s.name = 'Imported trio (v7)';
    st.squads.push(s); st.active = s.id; return 'v7 trio imported as a new squad';
  }
  if (j && CLASSES.includes(j.cls) && Array.isArray(j.order)) {
    const m = me(); if (!m || m.cls !== j.cls) throw new Error('Select a ' + CM[j.cls].n + ' first');
    sanitizeOrder.dropped = 0; const o = sanitizeOrder(j.cls, j.order); setBuild(m, o); return 'Build imported' + (sanitizeOrder.dropped ? ' (' + sanitizeOrder.dropped + ' invalid points dropped)' : '');
  }
  throw new Error('Unknown file format');
}
function readFile(input, cb) {
  const f = input.files && input.files[0]; if (!f) return;
  const rd = new FileReader();
  rd.onload = () => { try { const r = importJson(JSON.parse(rd.result)); if (r !== 'cancelled') { render(); toast(r); } } catch (err) { toast('Import failed: ' + err.message, true); } input.value = ''; };
  rd.onerror = () => { toast('Could not read the file', true); input.value = ''; };
  rd.readAsText(f);
}

/* ------------------------------------------------------------ events */
document.addEventListener('click', async ev => {
  const t = ev.target;
  const tal = t.closest('.tal');
  if (tal) {
    const m = me(), Tr = T(), k = tal.dataset.k;
    if (ev.shiftKey) { const r = E.removePoint(Tr, m.build, k); if (r.error) tpMsg(r.error); else setBuild(m, r.order); }
    else { const r = E.addPoint(Tr, m.build, k, capNow()); if (r.error) tpMsg(r.code === 'points' ? 'No talent points left at level ' + m.level + '. Raise the level or tick “Plan ahead”.' : r.error); else setBuild(m, r.order); }
    const again = document.querySelector('#trees [data-k="' + k + '"]');
    if (ev.detail === 0 && again) { again.focus(); showTip(talentTip(k), null, again); } else if (tipOn) showTip(talentTip(k), ev);
    return;
  }
  const b = t.closest('button, a[data-details]');
  document.querySelectorAll('details.menu[open]').forEach(dm => { if (!dm.contains(t) || (b && b.classList.contains('mi'))) dm.open = false; });
  if (!b) return;
  const d = b.dataset, s = sq(), m = me();
  if (b.matches('a[data-details]')) { ev.preventDefault(); openDetails(d.details); return; }
  if (d.pick) { s.current = d.pick; if (st.view === 'squad') st.view = 'kit'; hideTip(); render(); }
  else if (d.view) { st.view = d.view; hideTip(); render(); window.scrollTo({ top: 0 }); }
  else if (d.squad) { st.active = d.squad; render(); }
  else if (d.open) { s.current = d.mid; st.view = d.open; render(); window.scrollTo({ top: 0 }); }
  else if (d.mlvl) { const x = s.members.find(y => y.id === d.mid); if (x) { x.level = clampLvl(x.level + Number(d.mlvl)); applyLink(s); render(); } }
  else if (d.mmatch) { const x = s.members.find(y => y.id === d.mmatch), L = leaderOf(s); if (x && L) { x.level = L.level; render(); toast(x.name + ' is now level ' + L.level); } }
  else if (d.sdnew) openSeqDlg(null);
  else if (d.sdedit) openSeqDlg(d.sdedit);
  else if (d.sdremove) { const c = (m.customSeq || []).find(x => x.id === d.sdremove); if (c) withUndo('Deleted “' + c.name + '”', () => { m.customSeq = m.customSeq.filter(x => x.id !== c.id); }); }
  else if (d.sdadd) { sdRead(); const n = $('sdSpell').value; if (n && sdDraft.steps.length < 12) sdDraft.steps.push(n); renderSeqDlg(); }
  else if (d.sdup || d.sddown) { sdRead(); const i = Number(d.sdup || d.sddown), j = d.sdup ? i - 1 : i + 1, st = sdDraft.steps; if (j >= 0 && j < st.length) { [st[i], st[j]] = [st[j], st[i]]; } renderSeqDlg(); }
  else if (d.sddel) { sdRead(); sdDraft.steps.splice(Number(d.sddel), 1); renderSeqDlg(); }
  else if (d.medit) openMemberDlg(d.medit);
  else if (d.mlead) { s.members.forEach(x => { x.leader = x.id === d.mlead; }); render(); toast('New squad leader set'); }
  else if (d.mup) { const i = s.members.findIndex(x => x.id === d.mup); if (i > 0) { const [x] = s.members.splice(i, 1); s.members.splice(i - 1, 0, x); render(); } }
  else if (d.mdel) { const x = s.members.find(y => y.id === d.mdel); if (x) withUndo(x.name + ' removed', () => { s.members = s.members.filter(y => y.id !== x.id); fixLeader(s); if (s.current === x.id) s.current = s.members[0] ? s.members[0].id : null; }); }
  else if (d.jump) setLevel(d.jump);
  else if (d.copy) { const sp = spellById(d.copy); if (sp) { const ok = await copyText(macro(sp)); flash(b, ok); if (!ok) toast('Clipboard unavailable — open the spell and copy manually', true); } }
  else if (d.seqtier) { m.seq = E.SEQ_TIERS.includes(d.seqtier) ? d.seqtier : 'off'; save(); renderKit(); }
  else if (d.copyseq) { const [sid, lv] = d.copyseq.split('@'), x = seqOf(m, lv ? clampLvl(lv) : m.level).find(y => y.id === sid); if (x) { const ok = await copyText(x.macro); flash(b, ok); if (!ok) toast('Clipboard unavailable', true); } }
  else if (d.details) openDetails(d.details);
  else if (d.s) { st.ui.book.status = d.s; renderBook(); save(); }
  else if (d.util) { const u = utilities()[Number(d.util)]; if (u) flash(b, await copyText(u.c)); }
  else if (d.resettree) { const ti = Number(d.resettree), Tr = T(); setBuild(m, E.repairOrder(Tr, m.build.filter(k => Tr.byKey[k].t !== ti)) || [], 'Tree reset'); }
  else if (d.load) { const x = m.saved[Number(d.load)]; if (x) setBuild(m, x.order.slice(), 'Loaded “' + x.name + '”'); }
  else if (d.del) { const i = Number(d.del), x = m.saved[i]; if (x) withUndo('Deleted “' + x.name + '”', () => { m.saved.splice(i, 1); }); }
  else if (d.pin) { const list = m.pins = m.pins || []; const i = list.indexOf(d.pin); if (i >= 0) list.splice(i, 1); else list.push(d.pin); save(); if (st.view === 'kit') renderKit(); else renderBook(); toast(i >= 0 ? 'Unpinned' : 'Pinned to primary keys'); }
  else if (d.t) { st.ui.lower = d.t; save(); renderLower(); }
  else if (b.id === 'guideInfoBtn') { st.ui.guideInfo = !st.ui.guideInfo; save(); renderGuidePanel(); }
  else switch (b.id) {
    case 'lvlDown': setLevel(m.level - 1); break;
    case 'lvlUp': setLevel(m.level + 1); break;
    case 'toggleSecondary': st.ui.collapse = !st.ui.collapse; renderKit(); save(); break;
    case 'copyKit': toast((await copyText(kitText(m))) ? 'All macros for this level copied' : 'Clipboard unavailable'); break;
    case 'exportKit': download('Forever_' + fileSafe(m.name) + '_level_' + m.level + '_macros.txt', kitText(m)); break;
    case 'dlgClose': $('dlg').close(); break;
    case 'dlgCopy': if (dlgSpell) flash(b, await copyText(macro(dlgSpell))); break;
    case 'newSquad': { const name = prompt('Name the new squad:', 'Squad ' + (st.squads.length + 1)); if (!name) break; const ns = newSquad({ name, faction: s ? s.faction : 'horde' }); st.squads.push(ns); st.active = ns.id; render(); openMemberDlg(null); break; }
    case 'dupSquad': { const copy = newSquad(JSON.parse(JSON.stringify(Object.assign({}, s, { id: null, name: s.name + ' (copy)' })))); copy.members.forEach(x => { x.id = uid('m'); }); copy.current = copy.members[0] ? copy.members[0].id : null; st.squads.push(copy); st.active = copy.id; render(); toast('Squad duplicated'); break; }
    case 'delSquad': withUndo('Squad “' + s.name + '” deleted', () => { st.squads = st.squads.filter(x => x.id !== s.id); if (!st.squads.length) st.squads.push(newSquad({ name: 'New squad' })); st.active = st.squads[0].id; }); break;
    case 'levelAll': s.members.forEach(x => { x.level = clampLvl(x.level + 1); }); applyLink(s); render(); toast('Every member is now one level higher'); break;
    case 'sdCancel': $('seqDlg').close(); sdDraft = null; break;
    case 'squadSheet': download('Forever_' + fileSafe(s.name) + '_kits.txt', s.members.map(kitText).join('\n\n==============================\n\n')); break;
    case 'toastAct': if (toastAct) { const f = toastAct.fn; toastAct = null; $('toast').classList.remove('show'); f(); } break;
    case 'keysBtn': openKeys(); break;
    case 'tipClose': st.ui.tipSeen = true; $('tipBar').classList.add('hidden'); save(); break;
    case 'exportSquad': download('forever-squad-' + fileSafe(s.name) + '.json', JSON.stringify({ format: 'forever-companion/8-squad', exported: new Date().toISOString(), squad: s }, null, 1), 'application/json'); break;
    case 'exportAll': download('forever-squads-v8.json', exportAllJson(), 'application/json'); break;
    case 'syncLevels': { const L = leaderOf(s); if (L) { s.members.forEach(x => { x.level = L.level; }); render(); toast('All members set to level ' + L.level); } break; }
    case 'addMember': openMemberDlg(null); break;
    case 'mdCancel': $('memberDlg').close(); break;
    case 'applyGuide': { const g = guideOf(m), o = g.order.slice(0, avail()); if (!o.length) { tpMsg('No talent points at level ' + m.level + ' yet.'); break; } setBuild(m, o, 'Guide applied up to level ' + m.level + ' (' + o.length + ' points)'); break; }
    case 'applyFull': { const g = guideOf(m); if (m.build.length && !confirm('Load the full ' + g.order.length + '-point guide as the plan? Points beyond level ' + m.level + ' are shown as planned. You can Undo.')) break; st.ui.planAhead = true; setBuild(m, g.order.slice(), 'Full guide loaded as plan'); break; }
    case 'nextGuide': { const g = guideOf(m), Tr = T(), nx = E.guideNext(Tr, g.order, m.build); if (!nx) { tpMsg('Nothing left to spend from this guide.', true); break; } const r = E.addPoint(Tr, m.build, nx.key, capNow()); if (r.error) tpMsg(r.code === 'points' ? 'No free point at level ' + m.level + '. The next guide point arrives at level ' + E.levelForPoint(m.build.length, m.talented) + '.' : 'Next guide point blocked: ' + r.error); else setBuild(m, r.order, 'Learned ' + Tr.byKey[nx.key].n + ' (rank ' + nx.rank + ')'); break; }
    case 'undoBtn': undoBuild(m); break;
    case 'redoBtn': redoBuild(m); break;
    case 'resetAll': if (m.build.length) setBuild(m, [], 'Build reset — Undo restores it'); break;
    case 'copyText': toast((await copyText(buildText(m))) ? 'Build copied as text' : 'Clipboard unavailable'); break;
    case 'copyCode': toast((await copyText(E.encodeBuild(T(), m.cls, m.build))) ? 'Build code copied' : 'Clipboard unavailable'); break;
    case 'pasteCode': { const code = prompt('Paste a build code (WF8 or WF7):'); if (!code) break; const r = E.decodeBuild(TREES, code); if (r.error) { toast(r.error, true); break; } if (r.cls !== m.cls) { toast('That code is for a ' + CM[r.cls].n + ' — select a ' + CM[r.cls].n + ' first', true); break; } setBuild(m, r.order, 'Build code imported'); break; }
    case 'saveAs': { const name = prompt('Name this build for ' + m.name + ':', guideOf(m).spec + ' ' + new Date().toISOString().slice(0, 10)); if (!name) break; m.saved.unshift({ name: name.slice(0, 60), at: new Date().toISOString(), order: m.build.slice() }); m.saved = m.saved.slice(0, 40); save(); renderSaved(); toast('Saved “' + name + '”'); break; }
    case 'exportJson': download('forever-squads-v8.json', exportAllJson(), 'application/json'); break;
    case 'exportTxt': download('Forever_' + fileSafe(m.name) + '_talents.txt', buildText(m)); break;
  }
});
document.addEventListener('contextmenu', ev => {
  const tal = ev.target.closest('.tal'); if (!tal) return;
  ev.preventDefault();
  const m = me(), r = E.removePoint(T(), m.build, tal.dataset.k);
  if (r.error) tpMsg(r.error); else setBuild(m, r.order);
  if (tipOn) showTip(talentTip(tal.dataset.k), ev);
});
document.addEventListener('keydown', ev => {
  const tal = ev.target.closest && ev.target.closest('.tal');
  if (tal && (ev.key === 'Backspace' || ev.key === 'Delete')) { ev.preventDefault(); const m = me(), k = tal.dataset.k, r = E.removePoint(T(), m.build, k); if (r.error) tpMsg(r.error); else setBuild(m, r.order); const again = document.querySelector('#trees [data-k="' + k + '"]'); if (again) { again.focus(); showTip(talentTip(k), null, again); } }
  if (ev.key === 'Escape') hideTip();
});
document.addEventListener('pointerover', ev => { const el = ev.target.closest('[data-tip]'); if (el && ev.pointerType !== 'touch') showTip(tipFor(el), ev); });
document.addEventListener('pointermove', ev => { if (tipOn && ev.target.closest('[data-tip]')) placeTip(ev); });
document.addEventListener('pointerout', ev => { const el = ev.target.closest('[data-tip]'); if (el && !el.contains(ev.relatedTarget)) hideTip(); });
document.addEventListener('focusin', ev => { const el = ev.target.closest('[data-tip]'); if (el) showTip(tipFor(el), null, el); });
document.addEventListener('focusout', ev => { if (ev.target.closest('[data-tip]')) hideTip(); });
window.addEventListener('resize', () => { if (st.view === 'talents') drawArrows(); });
window.addEventListener('scroll', hideTip, { passive: true });
$('lvlRange').addEventListener('input', e => setLevel(e.target.value));
$('squadPick').addEventListener('change', e => { st.active = e.target.value; render(); });
$('bookCat').addEventListener('change', e => { st.ui.book.cat = e.target.value; renderBook(); save(); });
$('bookSrc').addEventListener('change', e => { st.ui.book.src = e.target.value; renderBook(); save(); });
$('bookSearch').addEventListener('input', e => { st.ui.book.q = e.target.value; renderBook(); save(); });
$('guideSel').addEventListener('change', e => { me().guide = e.target.value; save(); renderTalents(); });
$('overlaySel').addEventListener('change', e => { st.ui.overlay = e.target.value; save(); renderTalents(); });
$('talentedSel').addEventListener('change', e => { me().talented = clampT(e.target.value); save(); renderTalents(); });
$('planAhead').addEventListener('change', e => { st.ui.planAhead = e.target.checked; save(); renderTalents(); });
$('mdClass').addEventListener('change', () => fillMemberSelects(null, null));
$('memberDlg').addEventListener('submit', e => { e.preventDefault(); saveMemberDlg(); });
$('seqDlg').addEventListener('submit', e => { e.preventDefault(); saveSeqDlg(); });
let dragId = null;
const dragEl = e => (e.target && e.target.nodeType === 3 ? e.target.parentElement : e.target);
document.addEventListener('dragstart', e => { const t0 = dragEl(e), c = t0 && t0.closest && t0.closest('[data-mdrag]'); if (!c) return; dragId = c.dataset.mdrag; c.classList.add('dragging'); try { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', dragId); } catch (x) { /* old browsers */ } });
document.addEventListener('dragover', e => { const t0 = dragEl(e), c = dragId && t0 && t0.closest && t0.closest('[data-mdrag]'); if (!c) return; e.preventDefault(); document.querySelectorAll('.mcard.dropto').forEach(x => x.classList.remove('dropto')); if (c.dataset.mdrag !== dragId) c.classList.add('dropto'); });
document.addEventListener('drop', e => { const t0 = dragEl(e), c = dragId && t0 && t0.closest && t0.closest('[data-mdrag]'); if (!c) return; e.preventDefault(); const s = sq(), id = dragId; dragId = null; document.querySelectorAll('.mcard.dragging, .mcard.dropto').forEach(x => x.classList.remove('dragging', 'dropto')); if (moveMember(s, id, s.members.findIndex(x => x.id === c.dataset.mdrag))) { render(); toast('Order changed'); } });
document.addEventListener('dragend', () => { dragId = null; document.querySelectorAll('.mcard.dragging, .mcard.dropto').forEach(x => x.classList.remove('dragging', 'dropto')); });
document.addEventListener('change', e => {
  const id = e.target.id, s = sq();
  if (id === 'cmpSel') { me().cmp = e.target.value; save(); renderLower(); }
  else if (id === 'unitSel') { me().unit = e.target.value; render(); }
  else if (e.target.dataset.mseq) { const x = s.members.find(y => y.id === e.target.dataset.mseq); if (x) { x.seq = E.SEQ_TIERS.includes(e.target.value) ? e.target.value : 'off'; render(); } }
  else if (id === 'seqTarget') { me().seqTarget = e.target.checked; save(); renderKit(); }
  else if (id === 'sqLink') { const on = e.target.checked; if (on) withUndo('Levels linked to ' + (leaderOf(s) ? leaderOf(s).name : 'the leader'), () => { s.linkLevels = true; applyLink(s); }); else { s.linkLevels = false; render(); } }
  else if (id === 'sdKind' || id === 'sdAim') { sdRead(); renderSeqDlg(); }
  else if (id === 'sdFiller' || id === 'sdFills' || id === 'sdReset') { sdRead(); sdPreview(); }
  else if (e.target.dataset.munit) { const x = s.members.find(y => y.id === e.target.dataset.munit); if (x) { x.unit = e.target.value; render(); } }
  else if (id === 'sqFaction') { s.faction = e.target.value; render(); }
  else if (id === 'importAll' || id === 'importJson') readFile(e.target);
});
document.addEventListener('input', e => {
  if (e.target.id === 'sdName' && sdDraft) { sdRead(); sdPreview(); return; }
  if (e.target.id !== 'sqName') return;
  const s = sq(); s.name = e.target.value.slice(0, 40) || 'Squad';
  const opt = $('squadPick').querySelector('option[value="' + s.id + '"]'); if (opt) opt.textContent = s.name;
  const chip = document.querySelector('[data-squad="' + s.id + '"] b'); if (chip) chip.textContent = s.name;
  $('ctxTitle').textContent = s.name; save();
});
$('dlg').addEventListener('click', e => { if (e.target === $('dlg')) $('dlg').close(); });
window.addEventListener('unhandledrejection', ev => { const r = ev.reason || {}; window.dispatchEvent(new ErrorEvent('error', { message: r.message || String(r) })); });
window.addEventListener('error', ev => {
  let bar = document.querySelector('.errbar');
  if (!bar) { bar = document.createElement('div'); bar.className = 'errbar'; document.body.appendChild(bar); }
  bar.textContent = 'Script error: ' + (ev.message || 'unknown') + ' — please report this.';
});

function readHash() { // deep links / test presets: #view=talents&cls=priest&level=30&guide=...&apply=1 ; #demo=all
  const h = new URLSearchParams(String(window.__PRESET_HASH || location.hash || '').replace(/^#/, ''));
  if (h.get('demo') === 'all') {
    const ds = newSquad({ name: 'All classes (demo)', faction: 'horde', members: CLASSES.map((c, i) => ({ name: CM[c].n, cls: c, race: (RACES.find(r => r.c.includes(c) && r.f === 'horde') || RACES.find(r => r.c.includes(c))).k, role: CM[c].roles[0], level: 30, leader: i === 0 })) });
    st.squads.push(ds); st.active = ds.id;
  }
  const s = sq();
  if (s && CLASSES.includes(h.get('cls'))) { const x = s.members.find(y => y.cls === h.get('cls')); if (x) s.current = x.id; }
  if (['squad', 'kit', 'spellbook', 'talents', 'setup'].includes(h.get('view'))) st.view = h.get('view');
  const m = me();
  if (m) {
    const lv = Math.round(Number(h.get('level'))); if (lv >= 1 && lv <= 60) m.level = lv;
    const g = GUIDES.find(x => x.id === h.get('guide') && x.cls === m.cls); if (g) m.guide = g.id;
    if (h.get('apply') === '1') m.build = guideOf(m).order.slice(0, avail());
    if (h.get('plan') === '1') { st.ui.planAhead = true; m.build = guideOf(m).order.slice(); }
  }
  if (['level', 'full', 'off'].includes(h.get('overlay'))) st.ui.overlay = h.get('overlay');
  if (!window.__PRESET_HASH && location.hash) { try { history.replaceState(null, '', location.pathname + location.search); } catch (e) { /* ignore */ } }
}
/* home, footer link, keyboard shortcuts */
$('homeLink').addEventListener('click', e => { e.preventDefault(); st.view = 'squad'; hideTip(); render(); window.scrollTo({ top: 0 }); });
$('footSources').addEventListener('click', e => { e.preventDefault(); if (!me()) return; st.view = 'setup'; render(); const f = document.querySelectorAll('#view-setup details.fold'); if (f[2]) { f[2].open = true; f[2].scrollIntoView({ behavior: 'smooth' }); } });
document.addEventListener('keydown', e => {
  const mod = e.ctrlKey || e.metaKey;
  if (mod && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); openPalette(); return; }
  const inField = ['input', 'select', 'textarea'].includes((e.target.tagName || '').toLowerCase());
  if (mod && !inField && st.view === 'talents' && me()) {
    if ((e.key === 'z' || e.key === 'Z') && !e.shiftKey) { e.preventDefault(); undoBuild(me()); return; }
    if (e.key === 'y' || e.key === 'Y' || ((e.key === 'z' || e.key === 'Z') && e.shiftKey)) { e.preventDefault(); redoBuild(me()); return; }
  }
  if (e.key === '?' && !inField && !document.querySelector('dialog[open]')) { e.preventDefault(); openKeys(); return; }
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  const tag = (e.target.tagName || '').toLowerCase();
  if (['input', 'select', 'textarea'].includes(tag) || document.querySelector('dialog[open]')) return;
  const views = ['squad', 'kit', 'spellbook', 'talents', 'setup'], s = sq(), m = me();
  if (/^[1-5]$/.test(e.key)) { const v = views[Number(e.key) - 1]; if (v === 'squad' || m) { st.view = v; hideTip(); render(); } }
  else if ((e.key === '[' || e.key === ']') && s && s.members.length) { const i = s.members.findIndex(x => m && x.id === m.id); const n = (i + (e.key === ']' ? 1 : -1) + s.members.length) % s.members.length; s.current = s.members[n].id; if (st.view === 'squad') st.view = 'kit'; render(); }
  else if ((e.key === '+' || e.key === '=') && m) setLevel(m.level + 1);
  else if ((e.key === '-' || e.key === '_') && m) setLevel(m.level - 1);
  else if (e.key === '/' && m) { e.preventDefault(); st.view = 'spellbook'; render(); $('bookSearch').focus(); }
  else if (e.key === 'Escape') document.querySelectorAll('details.menu[open]').forEach(d => { d.open = false; });
});
/* ---------------- command palette (Ctrl+K) ---------------- */
let palItems = [], palSel = 0;
function paletteSource() {
  const s = sq(), m = me(), out = [];
  const views = [['squad', 'Squad'], ['kit', 'Everyday Kit'], ['spellbook', 'Spellbook'], ['talents', 'Talents'], ['setup', 'Setup']];
  views.forEach(([v, n], i) => out.push({ t: 'Go to ' + n, k: 'view', hint: String(i + 1), run: () => { st.view = v; render(); } }));
  if (s) s.members.forEach(x => out.push({ t: x.name + ' — ' + RACE[x.race].n + ' ' + CM[x.cls].n + ' ' + x.level, k: 'character', run: () => { s.current = x.id; if (st.view === 'squad') st.view = 'kit'; render(); } }));
  st.squads.forEach(x => out.push({ t: 'Squad: ' + x.name, k: 'squad', run: () => { st.active = x.id; st.view = 'squad'; render(); } }));
  if (s) {
    out.push({ t: '+1 level for every member', k: 'action', run: () => { s.members.forEach(x => { x.level = clampLvl(x.level + 1); }); render(); toast('Every member is now one level higher'); } });
    out.push({ t: 'Sync levels to the leader', k: 'action', run: () => { const L = leaderOf(s); if (L) { s.members.forEach(x => { x.level = L.level; }); render(); } } });
    out.push({ t: 'Add character…', k: 'action', run: () => { st.view = 'squad'; render(); openMemberDlg(null); } });
    out.push({ t: 'Download all kits of this squad (.txt)', k: 'action', run: () => download('Forever_' + fileSafe(s.name) + '_kits.txt', s.members.map(kitText).join('\n\n==============================\n\n')) });
  }
  out.push({ t: 'Export all squads (.json)', k: 'action', run: () => download('forever-squads-v8.json', exportAllJson(), 'application/json') });
  out.push({ t: 'Keyboard shortcuts', k: 'help', hint: '?', run: openKeys });
  if (m) {
    spellsOf(m).filter(x => x.action !== 'passive').forEach(x => out.push({ t: x.name, k: learned(m, x, m.level) ? 'copy macro' : 'spell · level ' + x.level, icon: x.icon, run: async () => { if (learned(m, x, m.level)) { const ok = await copyText(macro(x)); toast(ok ? x.name + ' macro copied' : 'Clipboard unavailable', !ok); } else openDetails(x.id); }, alt: () => openDetails(x.id) }));
    GUIDES.filter(g => g.cls === m.cls).forEach(g => out.push({ t: 'Guide: ' + g.label, k: 'guide', run: () => { m.guide = g.id; st.view = 'talents'; render(); } }));
    TREES[m.cls].nodes.forEach(n => out.push({ t: n.n, k: 'talent · ' + TREES[m.cls].trees[n.t].n, icon: n.i, run: () => { st.view = 'talents'; render(); const el = document.querySelector('#trees [data-k="' + n.k + '"]'); if (el) { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); el.focus(); } } }));
  }
  return out;
}
function palFilter(q) {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean), src = paletteSource();
  if (!words.length) return src.filter(x => ['view', 'character', 'action'].includes(x.k)).slice(0, 14);
  const scored = [];
  src.forEach(x => { const h = (x.t + ' ' + x.k).toLowerCase(); if (words.every(w => h.includes(w))) scored.push([x.t.toLowerCase().startsWith(words[0]) ? 0 : 1, x]); });
  return scored.sort((a, b) => a[0] - b[0]).map(x => x[1]).slice(0, 30);
}
function renderPalette() {
  palItems = palFilter($('palInput').value);
  palSel = Math.min(palSel, Math.max(0, palItems.length - 1));
  $('palList').innerHTML = palItems.map((x, i) => '<li class="' + (i === palSel ? 'on' : '') + '" data-pi="' + i + '">' + (x.icon ? icon(x.icon, x.t, { size: 'xs' }) : '<span class="pk">›</span>') + '<span class="pt">' + esc(x.t) + '</span><span class="pkind">' + esc(x.k) + '</span>' + (x.hint ? '<kbd>' + esc(x.hint) + '</kbd>' : '') + '</li>').join('') || '<li class="none">No matches</li>';
  const on = $('palList').querySelector('li.on'); if (on && on.scrollIntoView) on.scrollIntoView({ block: 'nearest' });
}
function openPalette() { if ($('palDlg').open) return; hideTip(); $('palInput').value = ''; palSel = 0; renderPalette(); $('palDlg').showModal(); $('palInput').focus(); }
function runPal(i, alt) { const x = palItems[i]; if (!x) return; $('palDlg').close(); (alt && x.alt ? x.alt : x.run)(); }
$('palInput').addEventListener('input', () => { palSel = 0; renderPalette(); });
$('palInput').addEventListener('keydown', e => {
  if (e.key === 'ArrowDown') { e.preventDefault(); palSel = Math.min(palItems.length - 1, palSel + 1); renderPalette(); }
  else if (e.key === 'ArrowUp') { e.preventDefault(); palSel = Math.max(0, palSel - 1); renderPalette(); }
  else if (e.key === 'Enter') { e.preventDefault(); runPal(palSel, e.shiftKey); }
});
$('palList').addEventListener('click', e => { const li = e.target.closest('li[data-pi]'); if (li) runPal(Number(li.dataset.pi), e.shiftKey); });
$('palDlg').addEventListener('click', e => { if (e.target === $('palDlg')) $('palDlg').close(); });
function openKeys() { if (!$('keysDlg').open) $('keysDlg').showModal(); }
$('keysDlg').addEventListener('click', e => { if (e.target === $('keysDlg') || e.target.id === 'keysClose') $('keysDlg').close(); });
$('palBtn').addEventListener('click', openPalette);

restore();
readHash();
render();
window.__forever = { st, TREES, E, render, sq, me, newMember, newSquad, palFilter, kitLists, seqOf, seqPlan, kitText, todoStrip, moveMember, applyLink, openSeqDlg, saveSeqDlg, cleanCustom, get sdDraft() { return sdDraft; } };
})();
