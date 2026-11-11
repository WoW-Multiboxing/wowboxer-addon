#!/usr/bin/env python3
"""Write datasrc/forever/guides.json (the Forever guides rebuilt from a current source) from source extracts.

An extract is a JSON file {<old guide id>: {found, url, title, author, updated, scope, order | ranks, unmatched,
illegalAt, notes, site?}} made by reading the source page (Wowhead/Icy Veins/Warcraft Tavern/WowVendor/Mobalytics,
docs/forever-talent-diff.md §Guides). Only entries that were found and whose every name is a live talent are used;
an order with one illegal click (final ranks legal) is marked repair=true (tools/forever_data.js re-sequences it and
says so in the guide's note); an order whose final ranks are not legal is not used. tools/build_data.js checks
every point again. The files are data only (hard rule 2).
A build dated before WoW Forever's launch (4 Nov 2026) is not current and is not used.
Usage: python tools/forever_guides.py <site>=<extract.json> [...] [--skip <id>=<reason>] [--note <id>=<text>]
       e.g. WowVendor=wowvendor.json
"""
import json
import os
import re
import sys

LAUNCH = '2026-11-04'

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'datasrc', 'forever', 'guides.json')


def main(argv):
    if not argv:
        sys.exit(__doc__)
    doc = json.load(open(OUT, encoding='utf-8'))
    rebuilt = {}
    skipped = []
    skip, notes, files = {}, {}, []
    it = iter(argv)
    for arg in it:
        if arg in ('--skip', '--note'):
            gid, text = next(it).split('=', 1)
            (skip if arg == '--skip' else notes)[gid] = text
        else:
            files.append(arg)
    for arg in files:
        site, path = arg.split('=', 1)
        for gid, x in json.load(open(path, encoding='utf-8')).items():
            if not x.get('found') or x.get('unmatched') or not (x.get('order') or x.get('ranks')):
                skipped.append((gid, site, 'not found / unmatched names / no build'))
                continue
            if x.get('finalRanksLegal') is False:
                skipped.append((gid, site, 'final ranks not legal'))
                continue
            if (x.get('updated') or '') < LAUNCH:
                skipped.append((gid, site, 'dated %s, before launch' % x.get('updated')))
                continue
            if gid in skip:
                skipped.append((gid, site, skip[gid]))
                continue
            e = {'source': {'site': x.get('site') or site, 'author': x.get('author') or None, 'title': x.get('title'),
                            'url': x['url'], 'updated': x['updated'],
                            'scope': (re.match(r'\d+(-\d+)?', x.get('scope') or '') or re.match('.*', '10-60')).group(0)}}
            e['source'] = {k: v for k, v in e['source'].items() if v}
            if x.get('order'):
                e['order'] = x['order']
                if x.get('illegalAt'):
                    e['repair'] = True
            else:
                e['ranks'] = x['ranks']
            if gid in notes:
                e['note'] = notes[gid]
            assert gid not in rebuilt, ('two sources for', gid)
            rebuilt[gid] = e
    doc['rebuilt'] = dict(sorted(rebuilt.items()))
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write('\n')
    print('wrote %s: %d guides' % (os.path.relpath(OUT, ROOT), len(rebuilt)))
    for s in skipped:
        print('  skipped %s (%s): %s' % s)


if __name__ == '__main__':
    main(sys.argv[1:])
