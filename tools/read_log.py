#!/usr/bin/env python3
"""Print what WoWBoxer saved in the game: the login diagnose, the debug log and the WBX macros the game stored.

Reads WTF\\Account\\*\\SavedVariables\\WoWBoxer.lua (decoded with real Lua via lupa) and every
WTF\\Account\\*\\<Realm>\\<Char>\\macros-cache.txt. Read-only. Usage:
  python tools/read_log.py [--client _classic_era_|_forever_] [--log N] [--json]
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_client import GRID_X, GRID_Y, STEP, SNAP  # noqa: E402  (the same grid as the data)

WOW = r"C:\Program Files (x86)\World of Warcraft"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def forever_data():
    """WoWBoxer's Forever talent data source (datasrc/forever/blizzard-<build>.json, the newest build)."""
    files = sorted(glob.glob(os.path.join(ROOT, "datasrc", "forever", "blizzard-*.json")))
    return json.load(open(files[-1], encoding="utf-8")) if files else None


def cell(x, y):
    """(tree 0-2, row, column) of a C_Traits node position, or None when it is off the grid (parked)."""
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        return None
    t = max([i for i, gx in enumerate(GRID_X) if x >= gx - STEP // 2] or [0])
    c = int(round((x - GRID_X[t]) / float(STEP))) + 1
    r = int(round((y - GRID_Y) / float(STEP))) + 1
    on = abs(x - (GRID_X[t] + (c - 1) * STEP)) <= SNAP and abs(y - (GRID_Y + (r - 1) * STEP)) <= SNAP
    return (t, r, c) if on and 1 <= c <= 4 and 1 <= r <= 7 else None


def compare_talent_tree(tree, data):
    """Differences between diag.talentTree (the live tree, C_Traits) and WoWBoxer's data. Returns (cls, lines, spent)."""
    nodes = [n for n in (tree.get("nodes") or []) if isinstance(n, dict)]
    live = {n.get("id"): n for n in nodes}
    cls = tree.get("cls")
    if cls not in (data.get("talents") or {}):  # older diag: the class whose node IDs match best
        cls = max(data["talents"], key=lambda c: sum(1 for x in data["talents"][c] if x["node"] in live))
    ours = {x["node"]: x for x in data["talents"][cls]}
    parked = {x["node"] for x in (data.get("parked") or {}).get(cls, [])}
    out, spent = [], [0, 0, 0]
    for nid, n in sorted(live.items(), key=lambda kv: (kv[1].get("y") or 0, kv[1].get("x") or 0)):
        where = cell(n.get("x"), n.get("y"))
        name = n.get("name") or "?"
        x = ours.get(nid)
        if not x:
            if nid in parked:
                if n.get("visible") is True or (n.get("spent") or 0) > 0:
                    out.append("%s (node %s): shown in game but parked off the grid in the data" % (name, nid))
                continue
            if where is None and n.get("visible") is not True:
                continue  # parked in game too
            out.append("%s (node %s): in the game at %s, not in WoWBoxer's data" % (name, nid, where and "tree %d row %d col %d" % (where[0] + 1, where[1], where[2])))
            continue
        if where:
            spent[where[0]] += n.get("spent") or 0
        if name != x["n"]:
            out.append("%s (node %s): the game calls it %r" % (x["n"], nid, name))
        if n.get("max") is not None and n.get("max") != x["m"]:
            out.append("%s: max rank %s in the game, %s in the data" % (x["n"], n.get("max"), x["m"]))
        if where and where != (x["t"], x["r"], x["c"]):
            out.append("%s: tree %d row %d col %d in the game, tree %d row %d col %d in the data" % (x["n"], where[0] + 1, where[1], where[2], x["t"] + 1, x["r"], x["c"]))
        if (n.get("spent") or 0) > x["m"]:
            out.append("%s: %s points spent, max %s" % (x["n"], n.get("spent"), x["m"]))
    for nid, x in ours.items():
        if nid not in live:
            out.append("%s (node %s): in the data, not in the game's tree" % (x["n"], nid))
    return cls, out, spent


def lua_to_py(v):
    if hasattr(v, "items"):
        d = {k: lua_to_py(x) for k, x in v.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d
    return v


def load_sv(path):
    from lupa import lua51
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    env = L.eval("function(src) local f = assert(loadstring(src)); local e = {}; setfenv(f, e); f(); return e end")
    with open(path, encoding="utf-8", errors="replace") as fh:
        return lua_to_py(env(fh.read()))


def macros_cache(path):
    out, cur = [], None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if line.startswith("VER ") or line.startswith("MACRO "):
                parts = line.split('"')
                cur = {"name": parts[1] if len(parts) > 1 else "?", "body": [], "icon": parts[3] if len(parts) > 3 else None}
            elif line == "END" and cur:
                out.append(cur)
                cur = None
            elif cur is not None:
                cur["body"].append(line)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default="_classic_era_")
    ap.add_argument("--log", type=int, default=30)
    ap.add_argument("--json", action="store_true", help="dump the full diagnose as JSON")
    a = ap.parse_args()
    wtf = os.path.join(WOW, a.client, "WTF", "Account")
    found = False
    for sv in sorted(glob.glob(os.path.join(wtf, "*", "SavedVariables", "WoWBoxer.lua"))):
        found = True
        acc = sv.split(os.sep)[-3]
        print(f"=== {acc}  ({sv}, {os.path.getmtime(sv):.0f})")
        data = load_sv(sv).get("WoWBoxerDB") or {}
        for char, d in (data.get("diag") or {}).items():
            if a.json:
                print(json.dumps(d, indent=1, sort_keys=True, default=str))
                continue
            p, m = d.get("probe", {}), d.get("member") or {}
            missing_api = sorted(k for k, v in (p.get("api") or {}).items() if v == "missing")
            print(f"-- {char}: {p.get('game')} toc {p.get('interface')} build {p.get('build')} spellbook={p.get('spellbook')}"
                  f" macros max {p.get('maxAccount')}/{p.get('maxCharacter')}")
            print(f"   WoWBoxer {d.get('build') or '-'}")
            print(f"   missing API: {', '.join(missing_api) or '-'}")
            print(f"   player {d.get('player')}")
            if d.get("error"):
                print(f"   compute: {d['error']}")
            else:
                print(f"   member {m}")
                mc = d.get("macros") or {}
                print(f"   macros {mc.get('counts')} free={mc.get('free')} unused={mc.get('unused')}")
                for it in mc.get("items") or []:
                    print(f"     {it}")
                print(f"   bars {(d.get('bars') or {}).get('counts')}")
                for it in (d.get("bars") or {}).get("items") or []:
                    print(f"     {it}")
                print(f"   not in spellbook: {d.get('missing')}")
            print(f"   cvars { {k: (v.get('cur'), v.get('want'), v.get('status')) for k, v in (d.get('cvars') or {}).items()} }")
            print(f"   addons {d.get('addons')}  party {d.get('party')} focus {d.get('focus')}")
            if d.get("strip"):
                print(f"   strip {d.get('strip')}")
            if d.get("team"):
                print(f"   team {d.get('team')}")
            if d.get("ui"):
                print(f"   ui {d.get('ui')}")
            if d.get("fly"):
                print(f"   fly {d.get('fly')}")
            if d.get("talents"):
                print(f"   talents {d.get('talents')}")
            tt = d.get("talentTree")
            if isinstance(tt, dict) and tt.get("nodes"):
                fd = forever_data()
                if fd:
                    cls, diff, spent = compare_talent_tree(tt, fd)
                    print(f"   talent tree (C_Traits, {len(tt['nodes'])} nodes) vs data build {fd.get('build')}: {cls}, "
                          f"spent {spent[0]}/{spent[1]}/{spent[2]}, {len(diff)} difference(s)")
                    for line in diff:
                        print(f"     {line}")
            elif isinstance(tt, dict) and tt.get("error"):
                print(f"   talent tree: error {tt.get('error')}")
            if "extraSpells" in d:
                ex = d.get("extraSpells") or []
                print(f"   spellbook spells not in the data: {len(ex) if isinstance(ex, list) else ex}")
                for it in (ex if isinstance(ex, list) else []):
                    print(f"     {it.get('name')} id {it.get('id')} {it.get('rank') or ''} {('level ' + str(it.get('level'))) if it.get('level') else ''}"
                          f"{' (future)' if it.get('future') else ''}")
            au = d.get("auto") if isinstance(d.get("auto"), dict) else {}
            if "abandonHooks" in au:
                hk = au.get("abandonHooks") or {}
                found = [k for k, v in (hk.items() if isinstance(hk, dict) else []) if v]
                print(f"   abandon together: {au.get('abandonMode')}, hooks {', '.join(sorted(found)) or 'none'}")
            for k in ("binds", "seqCheck", "cvarProbe"):
                if d.get(k):
                    print(f"   {k} {d.get(k)}")
            lay = d.get("layout")
            if lay:
                print(f"   layout audit: {lay.get('count')} finding(s), scale {lay.get('scale')}, {lay.get('game')}")
                for it in lay.get("items") or []:
                    print(f"     [{it.get('tab')}] {it.get('kind')}: {it.get('text')!r} needs {it.get('need')} has {it.get('have')}")
        log = data.get("log") or []
        print(f"-- log (last {a.log} of {len(log)})")
        for e in log[-a.log:]:
            print(f"   {e.get('t')} {e.get('c')} {e.get('l')}: {e.get('m')}")
    if not found:
        print(f"No WoWBoxer.lua under {wtf} yet (log in with the addon enabled, then /reload).")
    # taint: lines that name WoWBoxer in Logs\taint.log (after /console taintLog 1)
    taint = os.path.join(WOW, a.client, "Logs", "taint.log")
    if os.path.exists(taint):
        with open(taint, encoding="utf-8", errors="replace") as fh:
            hits = [l.rstrip() for l in fh if "WoWBoxer" in l]
        print(f"=== taint.log: {len(hits)} line(s) naming WoWBoxer")
        for l in hits[-15:]:
            print(f"   {l}")
    for mc in sorted(glob.glob(os.path.join(wtf, "*", "*", "*", "macros-cache.txt"))):
        wbx = [x for x in macros_cache(mc) if x["name"].startswith("WBX")]
        if wbx:
            print(f"=== WBX macros in {os.path.relpath(mc, wtf)}")
            for x in wbx:
                icon = f" [{x['icon']}]" if x.get("icon") else ""
                print(f"   {x['name']}{icon}: " + " | ".join(x["body"]))
    # keys that press a WBX macro directly (the game's own binding file per character)
    for bc in sorted(glob.glob(os.path.join(wtf, "*", "*", "*", "bindings-cache.wtf"))):
        with open(bc, encoding="utf-8", errors="replace") as fh:
            hits = [l.strip() for l in fh if "MACRO WBX" in l]
        if hits:
            print(f"=== direct WBX keybinds in {os.path.relpath(bc, wtf)}: " + "; ".join(hits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
