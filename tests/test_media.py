"""Checks the generated media: every texture the code or the TOC names exists, every texture
is an uncompressed 32-bit TGA with power-of-two sides (white on transparent, the shadow black,
so code can tint it), every glyph and shape the plan promises is there at its size, and the
chime is a real Ogg Vorbis file.
Run from the addon folder: python3 -I tests/test_media.py
"""
import math
import os
import re
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = "."
MEDIA = os.path.join(ROOT, "Media")
problems = []

# What the plan promises: path under Media/ (no extension) -> (width, height) in px.
GLYPHS = ("need", "greed", "pass", "transmog", "crown", "star", "clock", "gear",
          "close", "back", "chevron", "check", "down", "dot")
REQUIRED = {"Icons/" + name: (32, 32) for name in GLYPHS}
REQUIRED.update({
    "mark": (64, 64), "circle": (64, 64), "pill": (64, 32), "shadow": (64, 64),
    "wash": (128, 16), "shine": (64, 64), "ring": (64, 64),
})
CHIME = "Sounds/chime.ogg"


def media_path(rel):
    """Media/<rel>, with .tga added to a name that has no extension."""
    return os.path.join(MEDIA, rel if os.path.splitext(rel)[1] else rel + ".tga")


# ---------------------------------------------------------------- what the code names
used = set()  # paths under Media/, "/" separated; a trailing "/" is a folder the code adds a name to


def add(path):
    used.add(path.replace("\\\\", "/").replace("\\", "/"))


def shipped_lua():
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ("docs", "tests", "tools") and not d.startswith(".")]
        for name in files:
            if name.endswith(".lua"):
                yield os.path.join(folder, name)


for path in shipped_lua():
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    # MEDIA .. "mark", W.MEDIA .. "Icons\\need": a path built on the Media folder
    for m in re.finditer(r'MEDIA\s*\.\.\s*"([^"]+)"', text):
        add(m.group(1))
    # "Interface\\AddOns\\Tutti\\Media\\Sounds\\chime.ogg": a full path (Lua writes \ as \\)
    for m in re.finditer(r'Media\\\\([\w.]+(?:\\\\[\w.]*)*)', text):
        add(m.group(1))
    # W.Icon(parent, "need", ...), W.IconButton(parent, "close", ...): a glyph name
    for m in re.finditer(r'\b(?:Icon|IconButton)\(\s*[^,()]+,\s*"(\w+)"', text):
        used.add("Icons/" + m.group(1))

for name in os.listdir(ROOT):  # ## IconTexture: Interface\AddOns\Tutti\Media\mark
    if name.endswith(".toc"):
        text = Path(ROOT, name).read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'Media\\([\w.]+(?:\\[\w.]+)*)', text):
            add(m.group(1))

named = {media_path(rel) for rel in used if not rel.endswith("/")}
promised = {media_path(rel) for rel in REQUIRED} | {media_path(CHIME)}
for path in sorted(named | promised):
    if not os.path.exists(path):
        why = "named in the code" if path in named else "promised by the plan"
        problems.append(f"missing {path} ({why})")


# ---------------------------------------------------------------- the textures
def row(alpha, y):
    return [alpha.getpixel((x, y)) for x in range(alpha.width)]


def centre(alpha, y):
    r = row(alpha, y)
    return sum(x * v for x, v in enumerate(r)) / (sum(r) or 1)


def solid_xs(alpha, y):
    """The columns of row y that are at 50 % opacity or more."""
    return [x for x in range(alpha.width) if alpha.getpixel((x, y)) >= 128]


def check_tga(path):
    rel = os.path.relpath(path, MEDIA)[:-4].replace(os.sep, "/")
    data = Path(path).read_bytes()
    if len(data) < 18:
        problems.append(f"{path}: too short for a TGA header")
        return
    id_len, cmap, kind = data[0], data[1], data[2]
    w, h = struct.unpack("<HH", data[12:16])
    depth, flags = data[16], data[17]
    if cmap != 0 or kind != 2:
        problems.append(f"{path}: image type {kind} (colour map {cmap}), "
                        "want uncompressed true-colour (type 2)")
    if depth != 32 or flags & 15 != 8:
        problems.append(f"{path}: {depth} bits with {flags & 15} alpha bits, want 32 and 8")
    if w == 0 or h == 0 or w & (w - 1) or h & (h - 1):
        problems.append(f"{path}: {w}x{h} is not a power of two")
    if len(data) < 18 + id_len + w * h * 4:
        problems.append(f"{path}: the pixel data is short")
    if rel in REQUIRED and (w, h) != REQUIRED[rel]:
        problems.append(f"{path}: {w}x{h}, want {REQUIRED[rel][0]}x{REQUIRED[rel][1]}")
    try:
        im = Image.open(path)
        im.load()
    except Exception as e:
        problems.append(f"{path}: cannot be read ({e})")
        return
    colour = 0 if rel == "shadow" else 255
    if im.mode != "RGBA" or any(ch.getextrema() != (colour, colour) for ch in im.split()[:3]):
        problems.append(f"{path}: not {'black' if rel == 'shadow' else 'white'} on transparent")
        return
    alpha = im.getchannel("A")
    edges = ((0, 0, w, 1), (0, h - 1, w, h), (0, 0, 1, h), (w - 1, 0, w, h))
    solid = alpha.point(lambda v: 255 if v >= 128 else 0).getbbox()
    if solid is None:
        problems.append(f"{path}: blank (nothing at 50 % opacity or more)")
        return
    if rel.startswith("Icons/") and (min(solid[:2]) < 1 or solid[2] > w - 1 or solid[3] > h - 1):
        problems.append(f"{path}: the glyph is cut off by the edge of its texture")
    # the shapes the animations lean on, and the glyphs whose look was ruled on
    if rel == "wash":
        top = row(alpha, 0)
        if top[0] != 255 or top[-1] != 0 or any(p < q for p, q in zip(top, top[1:])):
            problems.append(f"{path}: the wash must fall from 100 % to 0 % from left to right")
        if any(row(alpha, y) != top for y in range(h)):
            problems.append(f"{path}: the wash must be the same on every row")
    elif rel == "ring":
        if alpha.getpixel((w // 2, h // 2)) != 0 or any(alpha.crop(e).getbbox() for e in edges) \
                or alpha.getextrema()[1] < 200:
            problems.append(f"{path}: the ring must be hollow, bright, and faded out before the edge")
    elif rel == "shine":
        lean = math.degrees(math.atan((centre(alpha, 0) - centre(alpha, h - 1)) / (h - 1)))
        if any(alpha.crop(e).getbbox() for e in edges[2:]) or alpha.getextrema()[1] < 250 \
                or len(solid_xs(alpha, h // 2)) < 28 or not 7 <= lean <= 13:
            problems.append(f"{path}: the shine must be a broad soft band: clear at both edges, "
                            "wide, leaning about 10 degrees like a slash")
    elif rel == "Icons/dot":
        cx, cy = (solid[0] + solid[2]) / 2, (solid[1] + solid[3]) / 2
        if not (5 <= solid[2] - solid[0] <= 7 and 5 <= solid[3] - solid[1] <= 7) \
                or abs(cx - w / 2) > 0.5 or abs(cy - h / 2) > 0.5:
            problems.append(f"{path}: the dot must be a 6 px disc in the middle")
    elif rel == "Icons/chevron":  # wide at the top, a point at the bottom, as big as the mockup's
        rows = [y for y in range(h) if solid_xs(alpha, y)]
        upper, lower = solid_xs(alpha, rows[0]), solid_xs(alpha, rows[-1])
        if upper[-1] - upper[0] < lower[-1] - lower[0] + 6 or solid[2] - solid[0] < 20:
            problems.append(f"{path}: the chevron must point down and fill its box like the mockup's")
    elif rel == "Icons/gear":
        gap = [alpha.getpixel((int(w / 2 + 6.6 * math.cos(a * math.pi / 4)),
                               int(h / 2 + 6.6 * math.sin(a * math.pi / 4)))) for a in range(8)]
        if max(gap) > 64:
            problems.append(f"{path}: the gear must be the outline one, clear between its two circles")


checked = 0
for folder, _, files in os.walk(MEDIA):
    for name in sorted(files):
        if name.endswith(".tga"):
            check_tga(os.path.join(folder, name))
            checked += 1

chime = media_path(CHIME)
if os.path.exists(chime):
    head = Path(chime).read_bytes()[:200]
    if not head.startswith(b"OggS") or b"vorbis" not in head:
        problems.append(chime + " is not Ogg Vorbis")

for p in problems:
    print("MEDIA " + p)
print(f"media ok ({checked} textures, {len(used)} names in the code)" if not problems
      else f"{len(problems)} media problem(s)")
sys.exit(1 if problems else 0)
