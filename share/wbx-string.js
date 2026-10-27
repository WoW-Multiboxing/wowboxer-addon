/* WoWBoxer share string – reference implementation for the website and the web companion (MIT).
     !WBX:1!<base64(UTF-8 canonical JSON)>!<crc32 of that JSON, 8 lowercase hex>
   Canonical JSON = JSON.stringify with object keys sorted at every level, so the website, the companion and the
   addon (WoWBoxer/Share.lua) produce byte-identical strings for the same setup.
   Payload: { f: "wowboxer/1", game: "forever"|"era"|"tbc"|"any", squad: <companion squad>, cvars?: {name: value}, addons?: [names] }
   The squad uses the companion's forever-companion/8-squad member fields; use fromCompanionSquad() to strip the rest.
   Works in browsers and Node 16+ (TextEncoder/TextDecoder, btoa/atob). */
(function (root) {
  'use strict';
  const PREFIX = '!WBX:1!';
  const FORMAT = 'wowboxer/1';
  const MAX_LEN = 16384;
  const MEMBER_FIELDS = ['id', 'name', 'cls', 'race', 'role', 'level', 'leader', 'unit', 'talented', 'build', 'guide', 'seq', 'seqTarget', 'customSeq', 'pins'];
  const CUSTOM_FIELDS = ['id', 'name', 'kind', 'aim', 'steps', 'filler', 'fills', 'reset'];

  function canonical(v) {
    if (Array.isArray(v)) return '[' + v.map(x => (x === undefined ? 'null' : canonical(x))).join(',') + ']';
    if (v && typeof v === 'object') {
      return '{' + Object.keys(v).filter(k => v[k] !== undefined).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
    }
    return JSON.stringify(v === undefined ? null : v);
  }

  let CRC_TABLE = null;
  function crc32(bytes) {
    if (!CRC_TABLE) {
      CRC_TABLE = new Uint32Array(256);
      for (let i = 0; i < 256; i++) { let c = i; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; CRC_TABLE[i] = c >>> 0; }
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) crc = CRC_TABLE[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return ((crc ^ 0xFFFFFFFF) >>> 0).toString(16).padStart(8, '0');
  }
  function bytesToB64(bytes) { let s = ''; for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]); return btoa(s); }
  function b64ToBytes(b64) {
    const s = atob(b64.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/'));
    const out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i); return out;
  }

  /** Strip a companion squad (localStorage state) down to the fields the share string carries. */
  function fromCompanionSquad(squad) {
    const pick = (o, fields) => { const r = {}; fields.forEach(f => { if (o[f] !== undefined) r[f] = o[f]; }); return r; };
    return { id: squad.id, name: squad.name, faction: squad.faction, linkLevels: !!squad.linkLevels,
      members: (squad.members || []).map(m => Object.assign(pick(m, MEMBER_FIELDS), { customSeq: (m.customSeq || []).map(c => pick(c, CUSTOM_FIELDS)) })) };
  }

  /** payload -> string */
  function encode(payload) {
    const p = Object.assign({ f: FORMAT, game: 'any' }, payload);
    const json = canonical(p);
    const bytes = new TextEncoder().encode(json);
    return PREFIX + bytesToB64(bytes) + '!' + crc32(bytes);
  }

  /** string -> {payload} or {error} (same messages as the addon) */
  function decode(str) {
    if (typeof str !== 'string') return { error: 'Nothing to import.' };
    str = str.trim();
    if (str.length > MAX_LEN) return { error: 'The string is too long (' + str.length + ' characters, max ' + MAX_LEN + ').' };
    if (str.startsWith('!WBX:') && !str.startsWith(PREFIX)) return { error: 'This string was made by a newer WoWBoxer. Update the addon.' };
    if (!str.startsWith(PREFIX)) return { error: 'Not a WoWBoxer string (it should start with ' + PREFIX + ').' };
    const m = /^([^!]+)!([0-9a-fA-F]{8})$/.exec(str.slice(PREFIX.length));
    if (!m) return { error: 'The string is incomplete (copy all of it).' };
    let bytes;
    try { bytes = b64ToBytes(m[1]); } catch (e) { return { error: 'The string is damaged: invalid base64.' }; }
    if (crc32(bytes) !== m[2].toLowerCase()) return { error: 'The string is damaged (checksum mismatch). Copy it again.' };
    let v;
    try { v = JSON.parse(new TextDecoder('utf-8', { fatal: false }).decode(bytes)); } catch (e) { return { error: 'The string is damaged: invalid JSON.' }; }
    if (!v || typeof v !== 'object' || v.f !== FORMAT) return { error: 'Unknown format.' };
    return { payload: v };
  }

  const api = { PREFIX, FORMAT, MAX_LEN, encode, decode, canonical, crc32, fromCompanionSquad };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.WoWBoxerShare = api;
})(typeof window !== 'undefined' ? window : globalThis);
