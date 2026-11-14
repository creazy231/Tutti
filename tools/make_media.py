"""Generate Tutti's textures (white on transparent, tinted in game).

Usage: python3 -I tools/make_media.py <addon-folder>

Every glyph is drawn at 8x on a large canvas and downsampled with Lanczos, so
the strokes stay crisp at the sizes the UI shows them (glyphs 32 px, shown at
9-16; the mark 64 px, shown at 15). Output is uncompressed 32-bit TGA, which
every WoW client reads.

Where the shapes come from:
- need, greed, pass, crown, star, clock, gear, chevron and the mark follow the
  SVGs of the approved mockup (docs/mockup/tutti-mockup.html, the ICON object),
  number for number: the mockup draws them in a 16 unit box (the star and the
  chevron in a 10 unit box), so a glyph function writes the mockup's numbers
  and scales them with u.
- transmog, a coat hanger, is not in the mockup; it takes the mockup's stroke.
- close, back, check, down and the circle, pill and shadow shapes are Sotto's,
  unchanged.
- wash, shine and ring are the effect textures; their docstrings say how the
  code is meant to show them. The shine is the mockup's CSS gradient.
- dropabove, dropbelow and dropside are the window's drop shadow, the mockup's
  CSS box-shadow worked out (see DROP_W).
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 8  # supersampling factor


def canvas(size):
    return Image.new("L", (size * SS, size * SS), 0)


def finish(mask, size):
    small = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(small)
    return out


def S(v):
    """Design units (px at final size) -> canvas units."""
    return v * SS


# ---------------------------------------------------------------- Sotto's helpers
def line(d, pts, w):
    d.line([(S(x), S(y)) for x, y in pts], fill=255, width=int(S(w)), joint="curve")
    # round caps
    r = S(w) / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([S(x) - r, S(y) - r, S(x) + r, S(y) + r], fill=255)


def circle(d, cx, cy, r, w=None):
    box = [S(cx - r), S(cy - r), S(cx + r), S(cy + r)]
    if w is None:
        d.ellipse(box, fill=255)
    else:
        d.ellipse(box, outline=255, width=int(S(w)))


# ---------------------------------------------------------------- the mockup's SVG shapes
# SVG strokes sit centred on the path, and by default have butt caps and mitre joins.
def P(v):
    """Design units -> the nearest canvas pixel."""
    return int(round(v * SS))


def box(x0, y0, x1, y1):
    """A PIL bounding box covering exactly [x0, x1) x [y0, y1); PIL counts the far edge in."""
    return [P(x0), P(y0), P(x1) - 1, P(y1) - 1]


def disc(d, cx, cy, r):
    d.ellipse(box(cx - r, cy - r, cx + r, cy + r), fill=255)


def ring(d, cx, cy, r, w):
    """An SVG circle of radius r with a stroke of width w. It clears its own hole, so draw
    an outer ring before whatever sits inside it."""
    disc(d, cx, cy, r + w / 2)
    d.ellipse(box(cx - r + w / 2, cy - r + w / 2, cx + r - w / 2, cy + r - w / 2), fill=0)


def frame(d, x0, y0, x1, y1, rx, w):
    """An SVG rect with corner radius rx and a stroke of width w."""
    h = w / 2
    d.rounded_rectangle(box(x0 - h, y0 - h, x1 + h, y1 + h), radius=P(rx + h), fill=255)
    d.rounded_rectangle(box(x0 + h, y0 + h, x1 - h, y1 - h), radius=P(max(rx - h, 0)), fill=0)


def poly(d, pts):
    d.polygon([(P(x), P(y)) for x, y in pts], fill=255)


def stroke(d, pts, w, round_ends=False):
    """An open polyline of width w: butt caps and mitre joins like SVG's default,
    or round caps and joins."""
    h = w / 2
    segs = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = math.hypot(x1 - x0, y1 - y0)
        segs.append(((y0 - y1) / n, (x1 - x0) / n))  # the segment's unit normal
    if round_ends:
        for (x0, y0), (x1, y1), (nx, ny) in zip(pts, pts[1:], segs):
            poly(d, [(x0 + nx * h, y0 + ny * h), (x1 + nx * h, y1 + ny * h),
                     (x1 - nx * h, y1 - ny * h), (x0 - nx * h, y0 - ny * h)])
        for x, y in pts:
            disc(d, x, y, h)
        return
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        if i == 0:
            nx, ny = segs[0]
        elif i == len(pts) - 1:
            nx, ny = segs[-1]
        else:  # the mitre: the two normals' sum, scaled so both offset edges meet
            (ax, ay), (bx, by) = segs[i - 1], segs[i]
            k = 1 / (1 + ax * bx + ay * by)
            nx, ny = (ax + bx) * k, (ay + by) * k
        left.append((x + nx * h, y + ny * h))
        right.append((x - nx * h, y - ny * h))
    poly(d, left + right[::-1])


# ---------------------------------------------------------------- glyphs (32)
def g_mark(size=64):
    """The die with five pips: the addon's mark."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    frame(d, 2 * u, 2 * u, 14 * u, 14 * u, 2.8 * u, 1.3 * u)
    for x, y in ((5.5, 5.5), (10.5, 5.5), (8, 8), (5.5, 10.5), (10.5, 10.5)):
        disc(d, x * u, y * u, 1.1 * u)
    return finish(m, size)


def g_need(size=32):
    """A rounded die with three pips on the diagonal."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    frame(d, 2.2 * u, 2.2 * u, 13.8 * u, 13.8 * u, 2.6 * u, 1.3 * u)
    for c in (5.6, 8, 10.4):
        disc(d, c * u, c * u, 1.15 * u)
    return finish(m, size)


def g_greed(size=32):
    """Two concentric circles: a coin."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    ring(d, 8 * u, 8 * u, 5.9 * u, 1.3 * u)
    ring(d, 8 * u, 8 * u, 3.1 * u, 1.1 * u)
    return finish(m, size)


def g_pass(size=32):
    """A circle with a diagonal slash."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    ring(d, 8 * u, 8 * u, 5.9 * u, 1.3 * u)
    stroke(d, [(3.9 * u, 12.1 * u), (12.1 * u, 3.9 * u)], 1.3 * u)
    return finish(m, size)


def g_crown(size=32):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    poly(d, [(x * u, y * u) for x, y in
             ((2.5, 13), (13.5, 13), (14.6, 5.6), (10.9, 8.3), (8, 3.2), (5.1, 8.3), (1.4, 5.6))])
    return finish(m, size)


def g_star(size=32):
    """The BiS chip's star; the mockup draws it in a 10 unit box."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 10.0
    poly(d, [(x * u, y * u) for x, y in
             ((5, 0.6), (6.3, 3.4), (9.3, 3.7), (7, 5.7), (7.7, 8.7),
              (5, 7.2), (2.3, 8.7), (3, 5.7), (0.7, 3.7), (3.7, 3.4))])
    return finish(m, size)


def g_clock(size=32):
    """A circle with two hands."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    ring(d, 8 * u, 8 * u, 5.8 * u, 1.25 * u)
    stroke(d, [(8 * u, 4.6 * u), (8 * u, 8 * u), (10.3 * u, 9.5 * u)], 1.25 * u)
    return finish(m, size)


def g_gear(size=32):
    """The outline gear: a ring, a smaller circle inside it and eight short spokes."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    ring(d, 8 * u, 8 * u, 4.4 * u, 1.25 * u)
    ring(d, 8 * u, 8 * u, 2.2 * u, 1.25 * u)
    for x0, y0, x1, y1 in ((8, 1.8, 8, 3.6), (8, 12.4, 8, 14.2), (1.8, 8, 3.6, 8), (12.4, 8, 14.2, 8),
                           (3.6, 3.6, 4.9, 4.9), (11.1, 11.1, 12.4, 12.4),
                           (3.6, 12.4, 4.9, 11.1), (11.1, 4.9, 12.4, 3.6)):
        stroke(d, [(x0 * u, y0 * u), (x1 * u, y1 * u)], 1.25 * u)
    return finish(m, size)


def g_chevron(size=32):
    """The dropdown chevron, pointing down; the mockup draws it in a 10 unit box."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 10.0
    stroke(d, [(2 * u, 3.5 * u), (5 * u, 6.5 * u), (8 * u, 3.5 * u)], 1.4 * u)
    return finish(m, size)


def g_transmog(size=32):
    """A coat hanger: a hook on a neck above a triangle, in the mockup's 1.3 unit stroke.
    The triangle's corners are sharp, so the ends and joins are round."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    u = size / 16.0
    r = 2.0  # the hook: more than half a circle, tangent to the neck, open at the bottom
    neck = [(8, 9)] + [(8 + r + r * math.cos(math.radians(a)), 4.7 + r * math.sin(math.radians(a)))
                       for a in range(180, 401, 10)]
    stroke(d, [(x * u, y * u) for x, y in neck], 1.3 * u, round_ends=True)
    body = [(1.8, 13.6), (8, 9), (14.2, 13.6), (1.8, 13.6)]
    stroke(d, [(x * u, y * u) for x, y in body], 1.3 * u, round_ends=True)
    return finish(m, size)


def g_dot(size=32):
    """A 6 px disc in the middle of the box; shown at 16 px it is the 3 px dot of 'choosing'."""
    m = canvas(size)
    d = ImageDraw.Draw(m)
    disc(d, size / 2, size / 2, 3)
    return finish(m, size)


# ---------------------------------------------------------------- glyphs (32), Sotto's
def g_close(size=32):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    line(d, [(8.5, 8.5), (23.5, 23.5)], 2.6)
    line(d, [(23.5, 8.5), (8.5, 23.5)], 2.6)
    return finish(m, size)


def g_back(size=32):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    line(d, [(19.5, 7.0), (10.5, 16.0), (19.5, 25.0)], 2.6)
    return finish(m, size)


def g_check(size=32):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    line(d, [(7.5, 16.5), (13.5, 22.5), (24.5, 10.0)], 2.8)
    return finish(m, size)


def g_down(size=32):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    line(d, [(16, 6.5), (16, 24.0)], 2.6)
    line(d, [(9.0, 17.5), (16.0, 24.5), (23.0, 17.5)], 2.6)
    return finish(m, size)


# ---------------------------------------------------------------- shapes
def circle_tex(size=64):
    m = canvas(size)
    d = ImageDraw.Draw(m)
    circle(d, size / 2, size / 2, size / 2 - 0.5)
    return finish(m, size)


def pill_tex(w=64, h=32):
    """Stadium shape for switch tracks (white, tinted in game)."""
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=h * SS // 2, fill=255)
    small = m.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(small)
    return out


def shadow_tex(size=64, edge=16):
    """Black soft square for a 9-slice drop shadow (corners `edge` px)."""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    d.rectangle([edge, edge, size - edge - 1, size - edge - 1], fill=255)
    img = img.filter(ImageFilter.GaussianBlur(edge / 2.6))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.putalpha(img)
    return out


# The window's drop shadow, the mockup's box-shadow 0 10px 28px rgba(0,0,0,.55): a box the window's size (300 px
# wide), 10 px lower, blurred by a Gaussian of 14 px (CSS takes half the blur as the deviation), drawn only outside
# the window. The code tints the three textures black at 55 % and lays them round the window: the band above
# (40 px past either side, 28 px high), the band below (52 px), and the sides, the left one mirrored for the right.
# x and y are px from the window's top-left corner, y down; `drop_below` and the side's lower part measure y from
# its bottom edge instead.
DROP_W, DROP_SIGMA, DROP_DOWN = 300, 14.0, 10.0
DROP_SIDE, DROP_ABOVE, DROP_BELOW = 40, 28, 52
DROP_TOP, DROP_BOTTOM = 46, 26  # the side's own parts: under the top edge, above the bottom edge


def phi(t):
    return 0.5 * (1 + math.erf(t / math.sqrt(2)))


def drop_across(x):
    return phi(x / DROP_SIGMA) - phi((x - DROP_W) / DROP_SIGMA)


def black_tex(w, h, alpha):
    """Black texture whose opacity at texel (i, j) is alpha(i, j), 0..1."""
    a = Image.new("L", (w, h))
    a.putdata([round(255 * min(1.0, max(0.0, alpha(i, j)))) for j in range(h) for i in range(w)])
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.putalpha(a)
    return out


def dropabove_tex(w=256, h=16):
    """The band above the window: x from -40 to 340 px, y from -28 px to its top edge."""
    span = DROP_W + 2 * DROP_SIDE
    return black_tex(w, h, lambda i, j: drop_across(-DROP_SIDE + (i + 0.5) * span / w)
                     * phi((-DROP_ABOVE + (j + 0.5) * DROP_ABOVE / h - DROP_DOWN) / DROP_SIGMA))


def dropbelow_tex(w=256, h=32):
    """The band below the window: x from -40 to 340 px, from its bottom edge 52 px down."""
    span = DROP_W + 2 * DROP_SIDE
    return black_tex(w, h, lambda i, j: drop_across(-DROP_SIDE + (i + 0.5) * span / w)
                     * phi((DROP_DOWN - (j + 0.5) * DROP_BELOW / h) / DROP_SIGMA))


def dropside_tex(w=32, h=64, top_rows=40):
    """The left side, 40 px out from the window's edge: rows 0-39 the 46 px under the top edge, rows 40-63 the
    26 px above the bottom edge. Between the two parts every row is the same, so the code stretches the rows where
    they meet over the rest of the window's height."""
    def alpha(i, j):
        across = phi((-DROP_SIDE + (i + 0.5) * DROP_SIDE / w) / DROP_SIGMA)
        if j < top_rows:
            return across * phi(((j + 0.5) * DROP_TOP / top_rows - DROP_DOWN) / DROP_SIGMA)
        up = DROP_BOTTOM - (j - top_rows + 0.5) * DROP_BOTTOM / (h - top_rows)  # px above the bottom edge
        return across * phi((DROP_DOWN + up) / DROP_SIGMA)
    return black_tex(w, h, alpha)


def alpha_tex(w, h, alpha):
    """White texture whose opacity at pixel (x, y) is alpha(x, y), 0..1."""
    a = Image.new("L", (w, h))
    a.putdata([round(255 * min(1.0, max(0.0, alpha(x, y)))) for y in range(h) for x in range(w)])
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(a)
    return out


def wash_tex(w=128, h=16):
    """The winner's wash: white at 100 % on the left, falling in a straight line to 0 % on
    the right, the same on every row. The mockup's gradient (accent at 28 %, 5 % at 82 %,
    then 0) is this ramp at 28 %: stretch it over the row and set the alpha to 0.28."""
    return alpha_tex(w, h, lambda x, y: 1 - x / (w - 1))


def shine_tex(size=64, tilt=10, edge=8):
    """The shine that crosses the card when the player wins: the mockup's gradient (100deg,
    transparent, accent, transparent) as a broad soft band over the whole texture. A raised
    cosine across the full width, 0 % at the left and right edges and 100 % in the middle,
    so it is half intensity over half the width (51 px on the mockup's band frame, a third
    of the card wide). Its middle line leans `tilt` degrees from the vertical like a slash
    (further right at the top), as the 100deg gradient does. The last `edge` px at each side
    fade to 0, so the lean never leaves a hard edge in the corners. Draw it at full white:
    tint it, set the alpha to 0.16 and slide the frame across the card."""
    lean = size * math.tan(math.radians(tilt))  # how far the middle line moves over the height

    def alpha(x, y):
        t = abs(x + 0.5 - (size / 2 + lean * (size / 2 - (y + 0.5)) / size)) / (size / 2)
        a = 0.5 + 0.5 * math.cos(math.pi * t) if t < 1 else 0.0
        near = min(x, size - 1 - x)  # columns to the nearest edge
        if near < edge:
            a *= 0.5 - 0.5 * math.cos(math.pi * near / edge)
        return a
    return alpha_tex(size, size, alpha)


def ring_tex(size=64, icon=34, shown=46, glow=5.5):
    """The glow around the 34 px item icon, a square ring. Show it at 46 px, centred on the
    icon: its hollow is the icon's 34 px, and the glow fades out over `glow` px, from 100 %
    at the icon's edge in a raised cosine (50 % at 2.75 px). That carries about as much
    light as the mockup's 3 px ring, which pulses to 55 %: tint it and pulse the alpha."""
    k = shown / size  # display px per texture px
    n = 4  # samples per texel and axis, for a clean inner edge

    def alpha(x, y):
        total = 0.0
        for j in range(n):
            for i in range(n):
                qx = abs((x + (i + 0.5) / n) * k - shown / 2) - icon / 2
                qy = abs((y + (j + 0.5) / n) * k - shown / 2) - icon / 2
                if qx < 0 and qy < 0:
                    continue  # inside the icon
                t = math.hypot(max(qx, 0), max(qy, 0)) / glow
                if t < 1:
                    total += 0.5 + 0.5 * math.cos(math.pi * t)
        return total / (n * n)
    return alpha_tex(size, size, alpha)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    media = os.path.join(root, "Media")
    icons = os.path.join(media, "Icons")
    os.makedirs(icons, exist_ok=True)
    glyphs = {
        "need": g_need, "greed": g_greed, "pass": g_pass, "transmog": g_transmog, "crown": g_crown,
        "star": g_star, "clock": g_clock, "gear": g_gear, "close": g_close, "back": g_back,
        "chevron": g_chevron, "check": g_check, "down": g_down, "dot": g_dot,
    }
    for name, fn in glyphs.items():
        fn().save(os.path.join(icons, name + ".tga"))
    shapes = {
        "mark": g_mark, "circle": circle_tex, "pill": pill_tex, "shadow": shadow_tex,
        "wash": wash_tex, "shine": shine_tex, "ring": ring_tex,
        "dropabove": dropabove_tex, "dropbelow": dropbelow_tex, "dropside": dropside_tex,
    }
    for name, fn in shapes.items():
        fn().save(os.path.join(media, name + ".tga"))
    print("media written to", media)


if __name__ == "__main__":
    main()
