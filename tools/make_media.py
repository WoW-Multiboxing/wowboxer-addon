#!/usr/bin/env python3
"""Generate the theme textures in WoWBoxer/Media/Theme/ (docs/ui-redesign.md §2). Standard library only.

All are white + alpha (tinted in the game with SetVertexColor), 64 x 64, 32-bit uncompressed TGA, drawn at 4x so a
corner of r UI units uses 4r texels:
  Fill<r>.tga   a rounded square, radius r (9-slice: the corners are the outer 4r texels)
  Ring<r>.tga   its 1-unit outline (4 texels)
  IconMask.tga  a rounded square for 40-unit spell icons (radius 6) – a mask texture
  Check.tga, Chevron.tga, Close.tga   small glyphs (check mark, ▾, ×), drawn with 1.5-unit strokes
  Circle.tga, CircleRing.tga          a disc and its 1-unit ring for 28-unit round buttons (the "?")
  Question.tga                        "?" in Cinzel Bold (needs Pillow; skipped without it)
Run after changing a radius: python tools/make_media.py  (the files are committed).
"""
import math, os, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "WoWBoxer", "Media", "Theme")
N, K = 64, 4          # texture size, texels per UI unit
SS = 4                # supersampling per texel axis
RADII = (3, 4, 6, 8, 10)


def write_tga(path, alpha_at):
    """alpha_at(x, y) -> 0..1 for texel centres (x, y in texels, y down). Bottom-left origin, BGRA."""
    rows = []
    for y in range(N - 1, -1, -1):
        row = bytearray()
        for x in range(N):
            a = max(0, min(255, int(round(alpha_at(x, y) * 255))))
            row += bytes((255, 255, 255, a))
        rows.append(bytes(row))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8)
    with open(path, "wb") as f:
        f.write(header + b"".join(rows))


def coverage(inside):
    def at(x, y):
        hit = 0
        for i in range(SS):
            for j in range(SS):
                if inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                    hit += 1
        return hit / (SS * SS)
    return at


def rounded(r):
    """Inside test for a rounded square filling the texture with corner radius r texels."""
    def inside(px, py):
        cx = min(max(px, r), N - r)
        cy = min(max(py, r), N - r)
        return (px - cx) ** 2 + (py - cy) ** 2 <= r * r
    return inside


def ring(r, w):
    outer, inner_r = rounded(r), max(r - w, 0)
    def inside(px, py):
        if not outer(px, py):
            return False
        qx, qy = px - w, py - w      # inner rounded square inset by w
        if qx < 0 or qy < 0 or qx > N - 2 * w or qy > N - 2 * w:
            return True
        cx = min(max(qx, inner_r), N - 2 * w - inner_r)
        cy = min(max(qy, inner_r), N - 2 * w - inner_r)
        return (qx - cx) ** 2 + (qy - cy) ** 2 > inner_r * inner_r
    return inside


def stroke(points, w):
    """Inside test for a polyline (texel coordinates) with half-width w/2."""
    def dist(px, py, a, b):
        ax, ay = a; bx, by = b
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - ax - t * dx, py - ay - t * dy)
    segs = list(zip(points, points[1:]))
    return lambda px, py: min(dist(px, py, a, b) for a, b in segs) <= w / 2


def main():
    os.makedirs(OUT, exist_ok=True)
    for r in RADII:
        write_tga(os.path.join(OUT, "Fill%d.tga" % r), coverage(rounded(r * K)))
        write_tga(os.path.join(OUT, "Ring%d.tga" % r), coverage(ring(r * K, 1 * K)))
    write_tga(os.path.join(OUT, "IconMask.tga"), coverage(rounded(N * 6 / 40)))
    s = N / 16  # glyphs are drawn on a 16-unit grid
    write_tga(os.path.join(OUT, "Check.tga"), coverage(stroke([(3.5 * s, 8.5 * s), (6.5 * s, 11.5 * s), (12.5 * s, 4.5 * s)], 2.2 * s)))
    write_tga(os.path.join(OUT, "Chevron.tga"), coverage(stroke([(4 * s, 6 * s), (8 * s, 10 * s), (12 * s, 6 * s)], 1.8 * s)))
    cross = stroke([(4 * s, 4 * s), (12 * s, 12 * s)], 1.6 * s)
    cross2 = stroke([(12 * s, 4 * s), (4 * s, 12 * s)], 1.6 * s)
    write_tga(os.path.join(OUT, "Close.tga"), coverage(lambda x, y: cross(x, y) or cross2(x, y)))
    c = N / 2
    write_tga(os.path.join(OUT, "Circle.tga"), coverage(lambda x, y: (x - c) ** 2 + (y - c) ** 2 <= c * c))
    rw = N / 28  # 1 unit of a 28-unit button
    write_tga(os.path.join(OUT, "CircleRing.tga"), coverage(lambda x, y: (c - rw) ** 2 < (x - c) ** 2 + (y - c) ** 2 <= c * c))
    try:
        from PIL import Image, ImageDraw, ImageFont
        im = Image.new("L", (N, N), 0)
        fnt = ImageFont.truetype(os.path.join(ROOT, "WoWBoxer", "Media", "Fonts", "Cinzel-Bold.ttf"), int(N * 0.86))
        ImageDraw.Draw(im).text((N / 2, N / 2), "?", fill=255, font=fnt, anchor="mm")
        write_tga(os.path.join(OUT, "Question.tga"), lambda x, y: im.getpixel((x, y)) / 255)
    except ImportError:
        print("Pillow missing: Question.tga not written")
    print("wrote", len(os.listdir(OUT)), "textures to", OUT)


if __name__ == "__main__":
    main()
