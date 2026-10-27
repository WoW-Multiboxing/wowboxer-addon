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

WOW = r"C:\Program Files (x86)\World of Warcraft"


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
                cur = {"name": parts[1] if len(parts) > 1 else "?", "body": []}
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
            if d.get("ui"):
                print(f"   ui {d.get('ui')}")
            if d.get("fly"):
                print(f"   fly {d.get('fly')}")
            if d.get("talents"):
                print(f"   talents {d.get('talents')}")
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
    for mc in sorted(glob.glob(os.path.join(wtf, "*", "*", "*", "macros-cache.txt"))):
        wbx = [x for x in macros_cache(mc) if x["name"].startswith("WBX")]
        if wbx:
            print(f"=== WBX macros in {os.path.relpath(mc, wtf)}")
            for x in wbx:
                print(f"   {x['name']}: " + " | ".join(x["body"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
