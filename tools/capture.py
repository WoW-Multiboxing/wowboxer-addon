#!/usr/bin/env python3
"""In-game screenshots of WoWBoxer for the website and CurseForge – captured read-only (tools/wowgrab.py:
PrintWindow on the WoW window; never input to the game, never focus).

  python tools/capture.py watch --client _classic_era_ [--minutes 30]
      While the owner follows the checklist (docs/screenshots.md) in the game: every second, grab the window; when the
      WoWBoxer window is on screen, has changed and then stays still for two grabs, save the frame as a candidate
      (dist/capture/<client>/NNN.png + NNN.json with the detected boxes). Candidates may show names – never commit them.
  python tools/capture.py detect <image.png>      print the boxes found (for checks)
  python tools/capture.py export --client _classic_era_
      Build media/screenshots/<flavour>/ from media/screenshots/shots.json: each shot names its candidate, crop mode
      and the regions to blur; writes <id>-1440.webp, <id>-720.webp and manifest.json.

Detection uses the theme's flat colours (UI/Theme.lua): the header (panel-2) is a wide band of one colour, the rail
(night-2) runs down its left edge, dialogs are wide runs of the panel colour next to it.
"""
import argparse, datetime, hashlib, json, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
OUT = os.path.join(ROOT, "media", "screenshots")
CAND = os.path.join(ROOT, "dist", "capture")
FLAVOUR = {"_classic_era_": "era", "_forever_": "forever"}
GAME = {"_classic_era_": "WoW Classic Era", "_forever_": "WoW: Forever"}
DESIGN_W, DESIGN_H = 889, 517            # UI.WIDTH, UI.HEIGHT
PANEL2, NIGHT2, PANEL = (28, 35, 51), (15, 19, 28), (21, 26, 36)
TOL = 5


def _np(img):
    import numpy as np
    return np.asarray(img.convert("RGB"), dtype=np.int16)


def _mask(a, rgb):
    import numpy as np
    return (np.abs(a - np.array(rgb, dtype=np.int16)).max(axis=2) <= TOL)


def _runs(row):
    """(start, end) of the longest run of True in a 1-D bool array."""
    best, start = (0, -1), None
    for i, v in enumerate(list(row) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start > best[1] - best[0] + 1:
                best = (start, i - 1)
            start = None
    return best


def detect(img):
    """{"frame": [l, t, r, b], "scale": px per design unit, "dialogs": [[l, t, r, b], ...]} or None."""
    import numpy as np
    a = _np(img)
    h, w, _ = a.shape
    hdr = _mask(a, PANEL2)
    counts = hdr.sum(axis=1)
    rows = np.where(counts >= max(200, w * 0.2))[0]
    if len(rows) == 0:
        return None
    # the first band of such rows that is at least 25 rows tall is the header
    bands, s = [], rows[0]
    for i in range(1, len(rows) + 1):
        if i == len(rows) or rows[i] != rows[i - 1] + 1:
            bands.append((s, rows[i - 1]))
            if i < len(rows):
                s = rows[i]
    bands = [b for b in bands if b[1] - b[0] >= 25]
    if not bands:
        return None
    top, bot = bands[0]
    # a row near the header's top edge: no widgets there (they are centred), only the rounded corners
    probe = top + max(3, (bot - top) // 8)
    l, r = _runs(hdr[probe])
    if r - l < 300:
        return None
    scale = (r - l + 3) / DESIGN_W
    # the rail (night-2) runs down from the header at the left edge; the window ends where it stops
    x = min(l + int(8 * scale), w - 1)
    y, miss, last = bot + 2, 0, bot
    night = _mask(a, NIGHT2)
    while y < h and miss < 6:
        if night[y, x]:
            last, miss = y, 0
        else:
            miss += 1
        y += 1
    frame = [max(0, l - 2), max(0, top - 3), min(w, r + 3), min(h, last + 3)]
    if (frame[3] - frame[1]) < 200 * scale:
        frame[3] = min(h, frame[1] + int(DESIGN_H * scale) + 2)
    # dialogs: wide runs of the panel colour outside the frame but near it (copy box, report window)
    pan = _mask(a, PANEL)
    pan[frame[1]:frame[3], frame[0]:frame[2]] = False
    dl = []
    prow = np.where(pan.sum(axis=1) >= 150 * scale)[0]
    if len(prow):
        y0, y1 = prow.min(), prow.max()
        cols = np.where(pan[y0:y1 + 1].sum(axis=0) >= 40 * scale)[0]
        if len(cols):
            box = [int(cols.min()) - 2, int(y0) - 2, int(cols.max()) + 3, int(y1) + 3]
            near = box[0] < frame[2] + 200 * scale and box[2] > frame[0] - 200 * scale and box[1] < frame[3] + 200 * scale
            if near:
                dl.append(box)
    return {"frame": [int(v) for v in frame], "scale": round(float(scale), 4), "dialogs": dl, "size": [w, h]}


def _sig(img, box):
    from PIL import Image
    c = img.crop(box).convert("L").resize((48, 32), Image.BILINEAR)
    return c.tobytes()


def _diff(a, b):
    if a is None or b is None or len(a) != len(b):
        return 255
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def watch(client, minutes):
    from wowgrab import find_window, grab
    out = os.path.join(CAND, FLAVOUR.get(client, client.strip("_")))
    os.makedirs(out, exist_ok=True)
    n = len([f for f in os.listdir(out) if f.endswith(".png")])
    end = time.time() + minutes * 60
    prev, saved, still = None, None, 0
    print("watching", client, "until", time.strftime("%H:%M", time.localtime(end)), "->", out, flush=True)
    while time.time() < end:
        hwnd = find_window(client)
        img = grab(hwnd) if hwnd else None
        d = detect(img) if img else None
        if d:
            boxes = [d["frame"]] + d["dialogs"]
            u = [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]
            sig = _sig(img, u)
            still = still + 1 if _diff(sig, prev) < 2.0 else 0
            prev = sig
            if still >= 1 and _diff(sig, saved) > 3.0:
                n += 1
                base = os.path.join(out, "%03d" % n)
                img.save(base + ".png")
                d["at"] = datetime.datetime.now().isoformat(timespec="seconds")
                with open(base + ".json", "w", encoding="utf-8") as f:
                    json.dump(d, f)
                saved = sig
                print("candidate", n, d["frame"], "dialogs", len(d["dialogs"]), flush=True)
        else:
            prev, still = None, 0
        time.sleep(1.0)
    print("watch ended,", n, "candidates", flush=True)


def _blur(img, box, radius=8):
    from PIL import ImageFilter
    box = [int(v) for v in box]
    if box[2] <= box[0] or box[3] <= box[1]:
        return img
    region = img.crop(box).filter(ImageFilter.GaussianBlur(radius))
    img.paste(region, box)
    return img


def export(client):
    from PIL import Image
    flav = FLAVOUR.get(client, client.strip("_"))
    with open(os.path.join(OUT, "shots.json"), encoding="utf-8") as f:
        spec = json.load(f)
    dest = os.path.join(OUT, flav)
    os.makedirs(dest, exist_ok=True)
    manifest = {"version": 1, "app": "wowboxer-addon", "appVersion": spec.get("appVersion"), "flavour": flav,
                "game": GAME.get(client, flav), "generated": datetime.date.today().isoformat(), "shots": []}
    for shot in spec["shots"]:
        src = (shot.get("source") or {}).get(flav)
        if not src:
            print("skip", shot["id"], "(no candidate chosen for", flav + ")")
            continue
        img = Image.open(os.path.join(CAND, flav, src + ".png")).convert("RGB")
        with open(os.path.join(CAND, flav, src + ".json"), encoding="utf-8") as f:
            d = json.load(f)
        fl, ft, fr, fb = d["frame"]
        k = d["scale"]
        # blur: regions in design units, relative to the WoWBoxer window's top-left
        for reg in shot.get("blur", []) + spec.get("blurAlways", []):
            _blur(img, [fl + reg[0] * k, ft + reg[1] * k, fl + reg[2] * k, ft + reg[3] * k], radius=max(6, int(6 * k)))
        # blur: regions as fractions of the whole game window (chat, player frame)
        for reg in shot.get("blurScreen", []):
            W, H = img.size
            _blur(img, [reg[0] * W, reg[1] * H, reg[2] * W, reg[3] * H], radius=12)
        pad = int(12 * k)
        box = [fl, ft, fr, fb]
        if shot.get("crop") == "dialog":
            for b in d["dialogs"]:
                box = [min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3])]
        elif shot.get("crop") == "bars":
            W, H = img.size
            box = [min(fl, int(W * 0.12)), ft, max(fr, int(W * 0.88)), H]
        box = [max(0, box[0] - pad), max(0, box[1] - pad), min(img.width, box[2] + pad), min(img.height, box[3] + pad)]
        crop = img.crop(box)
        files = {}
        for width in (1440, 720):
            h = round(crop.height * width / crop.width)
            name = "%s-%d.webp" % (shot["id"], width)
            crop.resize((width, h), Image.LANCZOS).save(os.path.join(dest, name), "WEBP", quality=88, method=6)
            files[str(width)] = name
        manifest["shots"].append({"id": shot["id"], "title": shot["title"], "alt": shot["alt"], "files": files,
                                  "width": 1440, "height": round(crop.height * 1440 / crop.width),
                                  "capturedAt": d.get("at"), "source": "in-game, " + GAME.get(client, flav)})
        print("wrote", shot["id"], files)
    with open(os.path.join(dest, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("manifest:", os.path.relpath(os.path.join(dest, "manifest.json"), ROOT), len(manifest["shots"]), "shots")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("watch"); w.add_argument("--client", default="_classic_era_"); w.add_argument("--minutes", type=float, default=30)
    t = sub.add_parser("detect"); t.add_argument("image")
    e = sub.add_parser("export"); e.add_argument("--client", default="_classic_era_")
    a = ap.parse_args()
    if a.cmd == "watch":
        watch(a.client, a.minutes)
    elif a.cmd == "detect":
        from PIL import Image
        print(json.dumps(detect(Image.open(a.image))))
    else:
        export(a.client)


if __name__ == "__main__":
    main()
