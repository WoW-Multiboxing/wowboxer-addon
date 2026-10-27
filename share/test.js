#!/usr/bin/env node
/* Tests for the share-string reference implementation and fixtures for the Lua side (tests/test_share.lua). */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const W = require('./wbx-string.js');

let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

const trio = {
  id: 'sTrio1', name: 'Undead trio', faction: 'horde', linkLevels: true, current: 'mPal', saved: 'dropped by fromCompanionSquad',
  members: [
    { id: 'mPal', name: 'Dorin', cls: 'paladin', race: 'undead', role: 'tank', level: 12, leader: true, unit: 'party1', talented: 0, build: ['redoubt', 'redoubt'], guide: 'pal-prot-holyshield', seq: 'medium', seqTarget: true, customSeq: [], pins: [], saved: [{ name: 'x' }], cmp: '' },
    { id: 'mPri', name: 'Wow2', cls: 'priest', race: 'undead', role: 'healer', level: 12, leader: false, unit: 'party1', talented: 2, build: [], guide: 'pri-holy-wowhead', seq: 'simple', seqTarget: false,
      customSeq: [{ id: 'q1', name: 'Shield + Renew', kind: 'priority', aim: 'help', steps: ['Power Word: Shield', 'Renew'], filler: '', fills: 1, reset: 'combat' }], pins: ['priest-renew'] },
    { id: 'mLock', name: 'Xerrö', cls: 'warlock', race: 'undead', role: 'ranged', level: 11, leader: false, unit: 'focus', talented: 0, build: [], guide: '', seq: 'advanced', seqTarget: false, customSeq: [], pins: [] },
  ],
};
const squad = W.fromCompanionSquad(trio);
ok(!('current' in squad) && !('saved' in squad.members[0]) && !('cmp' in squad.members[0]), 'fromCompanionSquad strips extra fields');

const cases = [
  { name: 'trio', payload: { f: 'wowboxer/1', game: 'forever', squad, cvars: { autoLootDefault: '1', maxfpsbk: '30' }, addons: ['Questie', 'Leatrix_Plus'] } },
  { name: 'minimal', payload: { f: 'wowboxer/1', game: 'any', squad: { id: 's1', name: 'Duo', faction: 'alliance', linkLevels: false, members: [{ id: 'm1', name: 'Æthel', cls: 'mage', race: 'gnome', role: 'ranged', level: 1, leader: true, unit: 'party1', talented: 0, build: [], guide: '', seq: 'off', seqTarget: false, customSeq: [], pins: [] }] } } },
  { name: 'escapes', payload: { f: 'wowboxer/1', game: 'era', squad: { id: 's2', name: 'Quote " back \\ slash / tab\t nl\n ctrl\u0001 emoji 😀', faction: 'horde', linkLevels: false, members: [] } } },
];
for (const c of cases) {
  c.str = W.encode(c.payload);
  const d = W.decode(c.str);
  ok(!d.error, c.name + ': decodes');
  ok(W.canonical(d.payload) === W.canonical(c.payload), c.name + ': round trip');
  ok(W.encode(d.payload) === c.str, c.name + ': re-encode identical');
}
const good = cases[0].str;
const bad = [
  { str: '', err: 'Not a WoWBoxer string (it should start with !WBX:1!).' },
  { str: 'hello', err: 'Not a WoWBoxer string (it should start with !WBX:1!).' },
  { str: '!WBX:2!abc!00000000', err: 'This string was made by a newer WoWBoxer. Update the addon.' },
  { str: good.slice(0, good.length - 20), err: 'The string is incomplete (copy all of it).' },
  { str: good.slice(0, 40) + 'A' + good.slice(41), err: 'The string is damaged (checksum mismatch). Copy it again.' },
  { str: good.replace(/![0-9a-f]{8}$/, '!deadbeef'), err: 'The string is damaged (checksum mismatch). Copy it again.' },
  { str: '!WBX:1!' + 'A'.repeat(20000) + '!00000000', err: 'The string is too long (20016 characters, max 16384).' },
];
// valid checksum, wrong content
const enc = s => { const b = new TextEncoder().encode(s); return '!WBX:1!' + Buffer.from(b).toString('base64') + '!' + W.crc32(b); };
bad.push({ str: enc('{"f":"other/1"}'), err: 'Unknown format.' });
bad.push({ str: enc('[1,2'), errPrefix: 'The string is damaged' });
for (const b of bad) {
  const d = W.decode(b.str);
  ok(d.error && (b.err ? d.error === b.err : d.error.startsWith(b.errPrefix)), 'rejects: ' + (b.err || b.errPrefix) + ' got ' + d.error);
}
ok(W.crc32(new TextEncoder().encode('123456789')) === 'cbf43926', 'crc32 check value');

const out = path.join(__dirname, '..', 'tests', 'vectors');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'share.json'), JSON.stringify({ cases, bad: bad.map(b => ({ str: b.str, err: b.err || null, errPrefix: b.errPrefix || null })) }));
console.log('share/test.js: ' + n + ' passed');
