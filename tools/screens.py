#!/usr/bin/env python3
"""Crop the screenshots of /wbx shots into docs/screens/<client>-<page>.png (needs Pillow and lupa).

After the owner types /wbx shots in a client and /reloads, WoWBoxerDB.shots lists every page with the window's box in
screen pixels and the time it was taken. The game saved the pictures in <client>\\Screenshots (WoWScrnShot_*.jpg or
.tga); each record gets the first file written at or after its time. Read-only for the game folders.
  python tools/screens.py [--client _classic_era_|_forever_] [--pad 8]
"""
import argparse, glob, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_log import WOW, load_sv  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "screens")
LABEL = {"_classic_era_": "era", "_forever_": "forever"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", action="append")
    ap.add_argument("--pad", type=int, default=8)
    a = ap.parse_args()
    from PIL import Image
    os.makedirs(OUT, exist_ok=True)
    done = 0
    for client in a.client or list(LABEL):
        best = None
        for sv in glob.glob(os.path.join(WOW, client, "WTF", "Account", "*", "SavedVariables", "WoWBoxer.lua")):
            shots = (load_sv(sv).get("WoWBoxerDB") or {}).get("shots")
            if shots and shots.get("list") and (not best or shots.get("at", 0) > best.get("at", 0)):
                best = shots
        if not best:
            print("%s: no /wbx shots saved yet" % client)
            continue
        files = sorted(glob.glob(os.path.join(WOW, client, "Screenshots", "WoWScrnShot_*")), key=os.path.getmtime)
        used = set()
        for rec in best["list"]:
            at = rec.get("at", 0)
            cand = [f for f in files if f not in used and os.path.getmtime(f) >= at - 1]
            if not cand:
                print("%s %s: no screenshot file found" % (client, rec.get("name")))
                continue
            f = cand[0]
            used.add(f)
            im = Image.open(f).convert("RGB")
            sx = im.width / (rec.get("w") or im.width)
            sy = im.height / (rec.get("h") or im.height)
            p = a.pad
            box = (max(0, int(rec["l"] * sx) - p), max(0, int(rec["top"] * sy) - p),
                   min(im.width, int(rec["r"] * sx) + p), min(im.height, int(rec["bottom"] * sy) + p))
            out = os.path.join(OUT, "%s-%s.png" % (LABEL.get(client, client.strip("_")), rec["name"]))
            im.crop(box).save(out)
            done += 1
            print("wrote", os.path.relpath(out, ROOT), box)
    print("%d screenshot(s) cropped" % done)


if __name__ == "__main__":
    main()
