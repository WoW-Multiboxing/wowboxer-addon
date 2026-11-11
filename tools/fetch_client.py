#!/usr/bin/env python3
"""Game data (TBC Anniversary, Classic Era, WoW Forever) from Blizzard's own client tables (DB2), as published per build
on wago.tools (docs/multi-flavor-plan.md, "Where the data comes from"). Writes datasrc/<game>/blizzard-<build>.json:
  trees[cls]   = [{n, f}] in the client's tab order (TalentTab.OrderIndex), f = icon file ID
  talents[cls] = [{k, n, t, r, c, m, f, ranks, req}] (t = tree index 0-2, r/c = 1-based row/column like the Forever
                 data, m = max rank, ranks = spell ID per rank, req = key of the prerequisite talent or null)
  spells[cls]  = {name: [[spellId, level], ...]} class abilities from the class skill lines (no pets), ranks by level
  icons[cls]   = {name: icon file ID of the first rank}
  racials      = {spellId: {n, f}} for the ids listed in datasrc/<game>/races.json
Classic Era: Season of Discovery runs on the same client; its rune spells (AcquireMethod 3) are left out.
WoW Forever: the client's Talent table is a stale Classic Era copy; the live talents are C_Traits trees (one TraitTree
  per class, found through SkillLineXTraitTree; its currency has SourcedMax 51 = the 51 points). A class tree holds the
  three talent trees side by side: a node's tree is its PosX band (named from TalentTab in OrderIndex order, left to
  right), its row and column come from PosX/PosY on a 600-unit grid. Nodes parked off the grid (e.g. PosY 39300) are
  not shown in game and are left out (listed under "parked"; Wowhead's calculator leaves out the same ones).
  Prerequisites: TraitEdge Type 2/3 between two nodes of the class tree. One spell per node: ranks = [spell ID] and
  m = TraitNodeEntry.MaxRanks; node = the TraitNode ID (C_Traits nodeID, used by diag.talentTree and Wowhead).
Only facts of the game (names, positions, ranks, levels, icon IDs); names (c) Blizzard Entertainment.
Usage: python tools/fetch_client.py tbc|era|forever [--cache DIR]   (downloads the CSVs, or reads DIR/<Table>.csv)
"""
import csv
import io
import json
import os
import re
import sys
import urllib.request

# the builds on the owner's PC (<client>\.build.info; Era/TBC 2 Nov 2026, Forever = product "wowf", 11 Nov 2026)
GAMES = {'tbc': '2.5.6.70577', 'era': '1.15.9.70576', 'forever': '1.60.1.70888'}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = None
TABLES = ['Talent', 'TalentTab', 'SpellName', 'SpellMisc', 'SkillLine', 'SkillLineAbility', 'SkillRaceClassInfo', 'SpellLevels']
TRAIT_TABLES = ['TraitNode', 'TraitNodeEntry', 'TraitDefinition', 'TraitEdge', 'TraitNodeXTraitNodeEntry',
                'SkillLineXTraitTree', 'TraitTreeXTraitCurrency', 'TraitCurrency']
CLASS_BIT = {'warrior': 1, 'paladin': 2, 'hunter': 4, 'rogue': 8, 'priest': 16, 'shaman': 64, 'mage': 128, 'warlock': 256, 'druid': 1024}
ORDER = ['warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid']
GRID_X = [1020, 5020, 9080]   # Forever: PosX of column 1 of the three trees in a class tree
GRID_Y = 2130                 # PosY of row 1
STEP = 600                    # one row / column
SNAP = 20                     # a few units off the grid still count (Demonology 2120/3320)


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
    if text.startswith('{"errors"'):
        raise SystemExit('wago.tools has no table %s for build %s' % (name, BUILD))
    return list(csv.DictReader(io.StringIO(text)))


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower().replace("'", '')).strip('-')


def class_tabs(T):
    tabs = {}
    for r in T['TalentTab']:
        cls = [c for c, b in CLASS_BIT.items() if int(r['ClassMask']) == b]
        if cls:
            tabs[int(r['ID'])] = (cls[0], int(r['OrderIndex']), r['Name_lang'], int(r['SpellIconID'] or 0))
    return tabs


def classic_talents(T, name, icon, out):
    tabs = class_tabs(T)
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


def trait_talents(T, name, icon, out):
    """WoW Forever: the class C_Traits trees (see the module doc)."""
    tabs = class_tabs(T)
    lineCls = {}
    for r in T['SkillRaceClassInfo']:
        cls = [c for c, b in CLASS_BIT.items() if int(r['ClassMask'] or 0) == b]
        if cls:
            lineCls[int(r['SkillID'])] = cls[0]
    currency = {int(r['TraitTreeID']): int(r['TraitCurrencyID']) for r in T['TraitTreeXTraitCurrency']}
    sourced = {int(r['ID']): int(r['SourcedMax'] or 0) for r in T['TraitCurrency']}
    treeOf = {}
    for r in T['SkillLineXTraitTree']:
        cls = lineCls.get(int(r['SkillLineID']))
        assert cls, ('no class for skill line', r)
        assert cls not in treeOf, ('two trait trees', cls)
        tid = int(r['TraitTreeID'])
        assert sourced.get(currency.get(tid)) == 51, ('class tree without 51 points', cls, tid)
        treeOf[cls] = tid
    assert sorted(treeOf) == sorted(ORDER), treeOf
    entry = {int(r['ID']): r for r in T['TraitNodeEntry']}
    defn = {int(r['ID']): r for r in T['TraitDefinition']}
    entries = {}
    for r in sorted(T['TraitNodeXTraitNodeEntry'], key=lambda r: int(r['_Index'] or 0)):
        entries.setdefault(int(r['TraitNodeID']), []).append(int(r['TraitNodeEntryID']))
    edges = [(int(r['LeftTraitNodeID']), int(r['RightTraitNodeID'])) for r in T['TraitEdge'] if r['Type'] in ('2', '3')]
    out['traitTrees'], out['parked'] = {}, {}
    for cls in ORDER:
        tid = treeOf[cls]
        out['traitTrees'][cls] = tid
        mine = sorted([(o, n, f) for _, (c, o, n, f) in tabs.items() if c == cls])
        assert len(mine) == 3, (cls, mine)
        out['trees'][cls] = [{'n': n, 'f': f} for _, n, f in mine]
        byNode, parked = {}, []
        for r in T['TraitNode']:
            if int(r['TraitTreeID']) != tid:
                continue
            nid, x, y = int(r['ID']), int(r['PosX']), int(r['PosY'])
            es = entries.get(nid, [])
            assert len(es) == 1, ('node with %d entries' % len(es), cls, nid)
            e = entry[es[0]]
            d = defn[int(e['TraitDefinitionID'])]
            sid = int(d['SpellID'])
            n = d['OverrideName_lang'] or name.get(sid, '?')
            t = max([i for i, gx in enumerate(GRID_X) if x >= gx - STEP // 2] or [0])
            c = int(round((x - GRID_X[t]) / float(STEP))) + 1
            row = int(round((y - GRID_Y) / float(STEP))) + 1
            on = abs(x - (GRID_X[t] + (c - 1) * STEP)) <= SNAP and abs(y - (GRID_Y + (row - 1) * STEP)) <= SNAP
            if not (on and 1 <= c <= 4 and 1 <= row <= 7):
                parked.append({'node': nid, 'n': n, 'x': x, 'y': y})
                continue
            f = int(d['OverrideIcon'] or 0) or icon.get(sid)
            byNode[nid] = {'k': slug(n), 'n': n, 't': t, 'r': row, 'c': c, 'm': int(e['MaxRanks']), 'f': f, 'ranks': [sid], 'node': nid}
        nodes = sorted(byNode.values(), key=lambda x: (x['t'], x['r'], x['c']))
        keys = [x['k'] for x in nodes]
        assert len(set(keys)) == len(keys), (cls, [k for k in keys if keys.count(k) > 1])
        cells = [(x['t'], x['r'], x['c']) for x in nodes]
        assert len(set(cells)) == len(cells), (cls, 'two talents in one cell')
        pre = {}
        for a, b in edges:
            if a in byNode and b in byNode and a != b:
                # an edge both ways (Druid 104927/104928) is one prerequisite: the upper talent opens the lower one
                if (byNode[a]['r'], byNode[a]['c']) > (byNode[b]['r'], byNode[b]['c']):
                    a, b = b, a
                assert pre.get(b, a) == a, (cls, byNode[b]['n'], 'has two prerequisites')
                assert byNode[a]['t'] == byNode[b]['t'], (cls, byNode[b]['n'], 'prerequisite in another tree')
                pre[b] = a
        for x in nodes:
            p = pre.get(x['node'])
            x['req'] = byNode[p]['k'] if p else None
        out['talents'][cls] = nodes
        if parked:
            out['parked'][cls] = parked


def spells_and_racials(game, T, name, icon, level, out):
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
    # ---- racials named in races.json (Forever keeps the seed's racials: it has no races.json)
    rp = os.path.join(ROOT, 'datasrc', game, 'races.json')
    races = json.load(open(rp, encoding='utf-8')) if os.path.exists(rp) else {'racials': {}}
    for r in races['racials'].values():
        for x in r['racials']:
            sid = x['spellId']
            assert name.get(sid) == x['name'], (sid, name.get(sid), x['name'])
            out['racials'][str(sid)] = {'n': name[sid], 'f': icon.get(sid)}


def main(argv):
    global BUILD
    game = argv[0] if argv and argv[0] in GAMES else sys.exit('usage: fetch_client.py tbc|era|forever [--cache DIR]')
    BUILD = GAMES[game]
    OUT = os.path.join(ROOT, 'datasrc', game, 'blizzard-%s.json' % BUILD)
    cache = argv[argv.index('--cache') + 1] if '--cache' in argv else None
    T = {n: table(n, cache) for n in TABLES + (TRAIT_TABLES if game == 'forever' else [])}
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
    if game == 'forever':
        out['source'] += ' (talents: C_Traits tables)'
        trait_talents(T, name, icon, out)
    else:
        classic_talents(T, name, icon, out)
    spells_and_racials(game, T, name, icon, level, out)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write('\n')
    print('wrote %s: %s' % (OUT, ', '.join('%s %d talents/%d spells' % (c, len(out['talents'][c]), len(out['spells'][c])) for c in ORDER)))


if __name__ == '__main__':
    main(sys.argv[1:])
