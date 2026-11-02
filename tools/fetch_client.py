#!/usr/bin/env python3
"""Game data (TBC Anniversary, Classic Era) from Blizzard's own client tables (DB2), as published per build on wago.tools
(docs/multi-flavor-plan.md, "Where the data comes from"). Writes datasrc/<game>/blizzard-<build>.json:
  trees[cls]   = [{n, f}] in the client's tab order (TalentTab.OrderIndex), f = icon file ID
  talents[cls] = [{k, n, t, r, c, m, f, ranks, req}] (t = tree index 0-2, r/c = 1-based row/column like the Forever
                 data, m = max rank, ranks = spell ID per rank, req = key of the prerequisite talent or null)
  spells[cls]  = {name: [[spellId, level], ...]} class abilities from the class skill lines (no pets), ranks by level
  icons[cls]   = {name: icon file ID of the first rank}
  racials      = {spellId: {n, f}} for the ids listed in datasrc/<game>/races.json
Classic Era: Season of Discovery runs on the same client; its rune spells (AcquireMethod 3) are left out.
Only facts of the game (names, positions, ranks, levels, icon IDs); names (c) Blizzard Entertainment.
Usage: python tools/fetch_client.py tbc|era [--cache DIR]   (downloads the CSVs, or reads DIR/<Table>.csv when present)
"""
import csv
import io
import json
import os
import re
import sys
import urllib.request

GAMES = {'tbc': '2.5.6.70577', 'era': '1.15.9.70576'}  # the builds on the owner's PC (2 Nov 2026)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = None
TABLES = ['Talent', 'TalentTab', 'SpellName', 'SpellMisc', 'SkillLine', 'SkillLineAbility', 'SkillRaceClassInfo', 'SpellLevels']
CLASS_BIT = {'warrior': 1, 'paladin': 2, 'hunter': 4, 'rogue': 8, 'priest': 16, 'shaman': 64, 'mage': 128, 'warlock': 256, 'druid': 1024}
ORDER = ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid']


def table(name, cache):
    path = cache and os.path.join(cache, name + '.csv')
    if path and os.path.exists(path):
        text = open(path, encoding='utf-8').read()
    else:
        url = 'https://wago.tools/db2/%s/csv?build=%s' % (name, BUILD)
        req = urllib.request.Request(url, headers={'User-Agent': 'WoWBoxer data tool (github.com/WoW-Multiboxing/wowboxer-addon)'})
        text = urllib.request.urlopen(req, timeout=300).read().decode('utf-8')
        if path:
            os.makedirs(cache, exist_ok=True)
            open(path, 'w', encoding='utf-8').write(text)
    return list(csv.DictReader(io.StringIO(text)))


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower().replace("'", '')).strip('-')


def main(argv):
    global BUILD
    game = argv[0] if argv and argv[0] in GAMES else sys.exit('usage: fetch_client.py tbc|era [--cache DIR]')
    BUILD = GAMES[game]
    OUT = os.path.join(ROOT, 'datasrc', game, 'blizzard-%s.json' % BUILD)
    cache = argv[argv.index('--cache') + 1] if '--cache' in argv else None
    T = {n: table(n, cache) for n in TABLES}
    name = {int(r['ID']): r['Name_lang'] for r in T['SpellName']}
    icon = {}
    for r in T['SpellMisc']:
        if r['DifficultyID'] == '0' and int(r['SpellIconFileDataID'] or 0) > 0:
            icon.setdefault(int(r['SpellID']), int(r['SpellIconFileDataID']))
    level = {}
    for r in T['SpellLevels']:
        if r['DifficultyID'] == '0':
            level[int(r['SpellID'])] = int(r['SpellLevel'] or 0) or int(r['BaseLevel'] or 0)

    out = {'build': BUILD, 'source': 'Blizzard client tables (DB2) of build %s via wago.tools' % BUILD,
           'trees': {}, 'talents': {}, 'spells': {}, 'racials': {}}
    # ---- talents
    tabs = {}
    for r in T['TalentTab']:
        cls = [c for c, b in CLASS_BIT.items() if int(r['ClassMask']) == b]
        if cls:
            tabs[int(r['ID'])] = (cls[0], int(r['OrderIndex']), r['Name_lang'], int(r['SpellIconID'] or 0))
    for cls in ORDER:
        mine = sorted([(o, tid, n, f) for tid, (c, o, n, f) in tabs.items() if c == cls])
        assert len(mine) == 3, (cls, mine)
        out['trees'][cls] = [{'n': n, 'f': f} for _, _, n, f in mine]
        tindex = {tid: i for i, (_, tid, _, _) in enumerate(mine)}
        rows = [r for r in T['Talent'] if int(r['TabID']) in tindex]
        byId = {}
        for r in rows:
            ranks = [int(r['SpellRank_%d' % i]) for i in range(9) if int(r['SpellRank_%d' % i] or 0) > 0]
            n = name.get(ranks[0], '?')
            byId[int(r['ID'])] = {'k': slug(n), 'n': n, 't': tindex[int(r['TabID'])], 'r': int(r['TierID']) + 1,
                                  'c': int(r['ColumnIndex']) + 1, 'm': len(ranks), 'f': icon.get(ranks[0]), 'ranks': ranks,
                                  'pre': int(r['PrereqTalent_0'] or 0)}
        nodes = sorted(byId.values(), key=lambda x: (x['t'], x['r'], x['c']))
        keys = [x['k'] for x in nodes]
        assert len(set(keys)) == len(keys), (cls, [k for k in keys if keys.count(k) > 1])
        for x in nodes:
            x['req'] = byId[x['pre']]['k'] if x['pre'] in byId else None
            del x['pre']
        out['talents'][cls] = nodes
    # ---- class abilities: class skill lines (category 7, not pets) of the class
    lineClass = {}
    for r in T['SkillRaceClassInfo']:
        cm = int(r['ClassMask'] or 0)
        for cls, b in CLASS_BIT.items():
            if cm & b and cm != 1535 and cm != -1:
                lineClass.setdefault(int(r['SkillID']), set()).add(cls)
    classLines = {int(r['ID']) for r in T['SkillLine'] if r['CategoryID'] == '7' and not r['DisplayName_lang'].startswith('Pet')}
    for cls in ORDER:
        sp = {}
        for r in T['SkillLineAbility']:
            line = int(r['SkillLine'])
            if line in classLines and cls in lineClass.get(line, ()):
                cm = int(r['ClassMask'] or 0)
                if r['AcquireMethod'] == '3':
                    continue  # Season of Discovery runes (Classic Era client)
                if cm and not (cm & CLASS_BIT[cls]):
                    continue
                sid = int(r['Spell'])
                n = name.get(sid)
                if n and not n.startswith('Engrave '):
                    sp.setdefault(n, set()).add((sid, level.get(sid, 0)))
        out['spells'][cls] = {n: sorted(v, key=lambda x: (x[1], x[0])) for n, v in sorted(sp.items())}
        out.setdefault('icons', {})[cls] = {n: icon.get(sorted(v, key=lambda x: (x[1], x[0]))[0][0]) for n, v in sorted(sp.items())}
    # ---- racials named in races.json
    races = json.load(open(os.path.join(ROOT, 'datasrc', game, 'races.json'), encoding='utf-8'))
    for r in races['racials'].values():
        for x in r['racials']:
            sid = x['spellId']
            assert name.get(sid) == x['name'], (sid, name.get(sid), x['name'])
            out['racials'][str(sid)] = {'n': name[sid], 'f': icon.get(sid)}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write('\n')
    print('wrote %s: %s' % (OUT, ', '.join('%s %d talents/%d spells' % (c, len(out['talents'][c]), len(out['spells'][c])) for c in ORDER)))


if __name__ == '__main__':
    main(sys.argv[1:])
