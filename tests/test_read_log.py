#!/usr/bin/env python3
"""tools/read_log.py: diag.talentTree (the live C_Traits tree the addon dumps) compared with WoWBoxer's Forever data
(docs/talents-rerun-2026-11-11.md §2.1.5). A dump made from the data itself has 0 differences; a moved, renamed,
re-ranked, missing or extra talent is reported; parked nodes are ignored unless the game shows them."""
import copy
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import read_log  # noqa: E402
from fetch_client import GRID_X, GRID_Y, STEP  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond:
        fails += 1


data = read_log.forever_data()
ok(data is not None and data.get('build'), 'Forever client data found')


def dump(cls, spent=None):
    """A diag.talentTree as the addon writes it, made from the data (positions back on the client grid)."""
    nodes = []
    for x in data['talents'][cls]:
        nodes.append({'id': x['node'], 'x': GRID_X[x['t']] + (x['c'] - 1) * STEP, 'y': GRID_Y + (x['r'] - 1) * STEP,
                      'max': x['m'], 'spent': (spent or {}).get(x['n'], 0), 'name': x['n'], 'spell': x['ranks'][0], 'visible': True})
    for p in (data.get('parked') or {}).get(cls, []):
        nodes.append({'id': p['node'], 'x': p['x'], 'y': p['y'], 'max': 1, 'spent': 0, 'name': p['n'], 'visible': False})
    return {'cls': cls, 'configID': 1, 'trees': [data['traitTrees'][cls]], 'nodes': nodes}


for cls in ('paladin', 'priest', 'warlock', 'hunter'):
    c, diff, spent = read_log.compare_talent_tree(dump(cls), data)
    ok(c == cls and diff == [], '%s: a dump of the data itself has 0 differences' % cls)

t = dump('paladin', {'Divine Strength': 5, 'Redoubt': 2})
_, diff, spent = read_log.compare_talent_tree(t, data)
ok(diff == [] and sum(spent) == 7, 'spent points are summed per tree: %s' % spent)

t = dump('paladin')
t2 = copy.deepcopy(t)
t2['nodes'][0]['y'] += STEP          # moved down one row
t2['nodes'][1]['max'] += 1           # rank change
t2['nodes'][2]['name'] = 'Renamed Talent'
gone = t2['nodes'].pop(3)            # missing in game
t2['nodes'].append({'id': 999999, 'x': GRID_X[0], 'y': GRID_Y + 6 * STEP, 'max': 1, 'spent': 0, 'name': 'Brand New', 'visible': True})
_, diff, _ = read_log.compare_talent_tree(t2, data)
text = '\n'.join(diff)
ok(len(diff) == 5, 'five differences reported (%d): %s' % (len(diff), diff))
ok('row 2' in text and 'max rank' in text and 'Renamed Talent' in text and gone['name'] in text and 'Brand New' in text,
   'each difference names the talent and what changed')

t3 = dump('hunter')
for n in t3['nodes']:
    if n['id'] in {p['node'] for p in data['parked'].get('hunter', [])}:
        n['visible'] = True
_, diff, _ = read_log.compare_talent_tree(t3, data)
ok(len(diff) == len(data['parked']['hunter']) and all('parked' in d for d in diff), 'a parked node the game shows is reported')

t4 = dump('warlock')
t4.pop('cls')
c, diff, _ = read_log.compare_talent_tree(t4, data)
ok(c == 'warlock' and diff == [], 'without cls the class is found by node IDs')

ok(read_log.cell(102800, 5740) is None and read_log.cell(9080, 2130) == (2, 1, 1) and read_log.cell(2220, 3320) == (0, 3, 3),
   'grid: parked positions are off the grid, a few units off still snap')

print('%d failed' % fails if fails else 'all passed')
sys.exit(1 if fails else 0)
