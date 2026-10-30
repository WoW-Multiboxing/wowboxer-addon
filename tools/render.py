#!/usr/bin/env python3
"""Paint the draw lists of tests/render.lua as PNG (needs Pillow): a look at every page without the game.

  python tools/render.py [outdir] [--era] [--scale 2]

Runs tests/render.lua in the simulator, then paints each JSON with the real theme textures (WoWBoxer/Media/Theme)
and fonts (WoWBoxer/Media/Fonts). The game font is stood in for by Georgia, spell icons by a tinted square with the
icon's initial. It is an approximation of the game (no masks, no shadows), good for layout and colour checks.
"""
import json, os, re, subprocess, sys, zlib
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "WoWBoxer", "Media")
GAME_FONT = "C:/Windows/Fonts/georgia.ttf" if os.path.exists("C:/Windows/Fonts/georgia.ttf") else None
_tex, _font = {}, {}


def tex_image(path):
    """A WoW texture path of ours -> PIL image, or None."""
    m = re.search(r"WoWBoxer\\Media\\(.+)$", path or "")
    if not m:
        return None
    rel = m.group(1).replace("\\", os.sep)
    for ext in ("", ".tga", ".png"):
        p = os.path.join(MEDIA, rel + ext)
        if os.path.isfile(p):
            if p not in _tex:
                _tex[p] = Image.open(p).convert("RGBA")
            return _tex[p]
    return None


def font(file, size):
    key = (file, size)
    if key not in _font:
        m = re.search(r"Fonts\\(.+\.ttf)$", file or "")
        path = os.path.join(MEDIA, "Fonts", m.group(1)) if m and "WoWBoxer" in file else GAME_FONT
        try:
            _font[key] = ImageFont.truetype(path, size) if path else ImageFont.load_default()
        except OSError:
            _font[key] = ImageFont.load_default()
    return _font[key]


def rgba(c, alpha=1.0):
    c = c or [1, 1, 1, 1]
    a = (c[3] if len(c) > 3 else 1) * alpha
    return tuple(int(max(0, min(1, x)) * 255) for x in (c[0], c[1], c[2], a))


def segments(text, base):
    """Split a WoW string into (text, colour) runs: |cffRRGGBB … |r, |T…|t -> a small box, |n -> newline."""
    text = text.replace("|n", "\n")
    out, col, i = [], base, 0
    for m in re.finditer(r"\|c[fF]{2}([0-9a-fA-F]{6})|\|r|\|T[^|]*\|t", text):
        if m.start() > i:
            out.append((text[i:m.start()], col))
        tok = m.group(0)
        if tok.startswith("|c"):
            h = m.group(1)
            col = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), base[3])
        elif tok == "|r":
            col = base
        else:
            out.append(("\u25a0", (150, 140, 120, base[3])))
        i = m.end()
    if i < len(text):
        out.append((text[i:], col))
    return out


def wrap_lines(runs, fnt, width):
    """Word-wrap runs into lines of runs."""
    lines, cur, cur_w = [], [], 0.0
    for txt, col in runs:
        parts = re.split(r"(\n|\s+)", txt)
        for p in parts:
            if p == "":
                continue
            if p == "\n":
                lines.append(cur); cur, cur_w = [], 0.0
                continue
            w = fnt.getlength(p)
            if width and cur_w + w > width + 0.5 and cur and not p.isspace():
                lines.append(cur); cur, cur_w = [], 0.0
            if p.isspace() and not cur:
                continue
            cur.append((p, col)); cur_w += w
    lines.append(cur)
    return lines


def paint(doc, scale, out_path):
    sw, sh = doc["screen"]["w"], doc["screen"]["h"]
    img = Image.new("RGBA", (int(sw * scale), int(sh * scale)), (11, 14, 20, 255))
    for it in doc["items"]:
        l, b, r, t = it["rect"]
        box = (round(l * scale), round((sh - t) * scale), round(r * scale), round((sh - b) * scale))
        w, h = box[2] - box[0], box[3] - box[1]
        if w <= 0 or h <= 0:
            continue
        tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        if it["k"] == "tex":
            if it.get("color"):
                tile.paste(rgba(it["color"], it["alpha"]), (0, 0, w, h))
            elif it.get("file"):
                src = tex_image(it["file"])
                tint = it.get("tint") or [1, 1, 1, 1]
                if src is not None:
                    c = it.get("coords")
                    if c and len(c) == 4:
                        sx, sy = src.size
                        crop = (int(c[0] * sx), int(c[2] * sy), max(int(c[1] * sx), int(c[0] * sx) + 1), max(int(c[3] * sy), int(c[2] * sy) + 1))
                        src = src.crop(crop)
                    part = src.resize((w, h), Image.LANCZOS)
                    col = Image.new("RGBA", (w, h), rgba(tint, it["alpha"])[:3] + (255,))
                    a = part.getchannel("A").point(lambda v, k=rgba(tint, it["alpha"])[3]: v * k // 255)
                    col.putalpha(a)
                    tile = col
                elif "Icons" in it["file"] or it["file"].startswith("id:"):
                    hue = zlib.crc32(it["file"].encode()) % 360
                    base = Image.new("HSV", (w, h), (int(hue * 255 / 360), 120, 110)).convert("RGBA")
                    ImageDraw.Draw(base).text((w / 2, h / 2), it["file"].split("\\")[-1][:1], fill=(240, 240, 240, 220),
                                              anchor="mm", font=font(None, max(8, int(h * 0.5))))
                    tile = base
                else:
                    tile.paste((120, 110, 90, int(90 * it["alpha"])), (0, 0, w, h))
        else:
            size = max(6, round(it["size"] * scale))
            fnt = font(it.get("font"), size)
            base = rgba(it.get("color") or [1, 0.82, 0, 1], it["alpha"])
            lines = wrap_lines(segments(it["text"], base), fnt, w if it.get("wrap") else None)
            lh = size + 2 * scale
            y = (h - lh * len(lines)) / 2
            d = ImageDraw.Draw(tile)
            for ln in lines:
                lw = sum(fnt.getlength(p) for p, _ in ln)
                x = 0 if it["justify"] == "LEFT" else (w - lw if it["justify"] == "RIGHT" else (w - lw) / 2)
                for p, col in ln:
                    d.text((x, y + lh / 2), p, fill=col, font=fnt, anchor="lm")
                    x += fnt.getlength(p)
                y += lh
        if it.get("clip"):
            cl, cb, cr, ct = it["clip"]
            cbox = (round(cl * scale), round((sh - ct) * scale), round(cr * scale), round((sh - cb) * scale))
            mask = Image.new("L", (w, h), 0)
            ImageDraw.Draw(mask).rectangle((cbox[0] - box[0], cbox[1] - box[1], cbox[2] - box[0] - 1, cbox[3] - box[1] - 1), fill=255)
            tile.putalpha(Image.composite(tile.getchannel("A"), Image.new("L", (w, h), 0), mask))
        img.alpha_composite(tile, (box[0], box[1]))
    img.convert("RGB").save(out_path)


def main():
    args = sys.argv[1:]
    era = "--era" in args
    scale = 2.0
    if "--scale" in args:
        scale = float(args[args.index("--scale") + 1])
    rest = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--scale")]
    out = os.path.abspath(rest[0] if rest else os.path.join(ROOT, "dist", "render"))
    os.makedirs(out, exist_ok=True)
    lua = [sys.executable, os.path.join(ROOT, "tools", "lua.py")]
    r = subprocess.run(lua + ["tests/render.lua", out.replace("\\", "/")] + (["era"] if era else []), cwd=ROOT,
                       capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode != 0:
        sys.exit(r.stderr)
    for name in sorted(os.listdir(out)):
        if name.endswith(".json"):
            with open(os.path.join(out, name), encoding="utf-8") as f:
                doc = json.load(f)
            png = os.path.join(out, name[:-5] + (".era" if era else "") + ".png")
            paint(doc, scale, png)
            os.remove(os.path.join(out, name))
            print("painted", png)


if __name__ == "__main__":
    main()
