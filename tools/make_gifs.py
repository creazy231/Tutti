#!/usr/bin/env python3
"""Tutti dev tool: makes the listing's animated GIFs from the addon's real UI.

    python3 -I tools/make_gifs.py <render-dir> [--out <dir>] [name ...]

Run from the addon folder, with the render dir tools/make_listing.py uses (see
CLAUDE.md). For each GIF in GIFS, tools/render_ui.lua plays its film in the fake
client, 15 frames a second, and writes one page per frame into the render dir
(film-<film>-0001.html, ...). Each page is served over http and shot with
headless Chrome at twice the GIF's size (several at once), scaled down with
Pillow, and ffmpeg makes the GIF from the frames with one palette for all of them
(palettegen, then paletteuse), looping forever, into docs/listing/animations/ (or
--out). The frames stay in <render-dir>/gif-<name>/. Names pick GIFs:
"03-you-won". Needs luajit, Google Chrome, Pillow and ffmpeg.

The camera keeps still: the window's resting top-left corner sits at (wx, wy) in
every frame, so the window rises, grows, folds and sinks as it does in game.
"""
import concurrent.futures
import functools
import glob
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.parse

from PIL import Image

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
OUT = os.path.join("docs", "listing", "animations")
SIZE = (800, 500)       # the GIF's size; the frames are shot at twice it
WORKERS = 6             # Chrome processes at once
LIMIT = 5 * 1024 * 1024  # CurseForge and GitHub show GIFs; keep each under 5 MB

# name, film (tools/render_ui.lua), shot parameters on the 1600 x 1000 page: scale is the window's (px a unit), wx
# and wy where its resting top-left corner sits.
GIFS = [
    ("01-a-boss-drop", "drop", dict(
        bg="bg-vault.jpg", layout="left", m="100", scale="1.9", wx="930", wy="62",
        eyebrow="A boss drop", title="Loot drops.|Tutti *opens*.")),
    ("02-roll-from-the-window", "click", dict(
        bg="bg-hall.jpg", layout="left", m="100", scale="2.6", wx="720", wy="195",
        eyebrow="Your pick", title="Roll right|from the *card*.")),
    ("03-you-won", "won", dict(
        bg="bg-camp.jpg", layout="left", m="100", scale="2.6", wx="720", wy="230",
        eyebrow="Your loot", title="You *won*.|You'll know.")),
]


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def shoot(url, png, size):
    """One page as a PNG at `size`, with a profile of its own (several Chromes run at once)."""
    profile = tempfile.mkdtemp(prefix="tutti-chrome-")
    try:
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--user-data-dir=" + profile,
                        "--force-device-scale-factor=1", "--window-size=%d,%d" % size,
                        "--virtual-time-budget=3000", "--screenshot=" + png, url],
                       check=True, capture_output=True, timeout=120)
    finally:
        shutil.rmtree(profile, ignore_errors=True)


def make(root, out_dir, port, name, film, params):
    prefix = os.path.join(root, "film-" + film)
    for old in glob.glob(prefix + "-*.html"):
        os.remove(old)
    subprocess.run(["luajit", "tools/render_ui.lua", prefix, film], check=True, capture_output=True)
    with open(prefix + ".json") as fh:
        info = json.load(fh)
    frames_dir = os.path.join(root, "gif-" + name)
    shutil.rmtree(frames_dir, ignore_errors=True)
    os.makedirs(frames_dir)
    big = (SIZE[0] * 2, SIZE[1] * 2)
    query = dict(shot="1", w=str(big[0]), h=str(big[1]), wh="%g" % info["tallest"])
    query.update(params)
    query = urllib.parse.urlencode(query)

    def one(n):
        png = os.path.join(frames_dir, "%04d.png" % n)
        shoot("http://127.0.0.1:%d/film-%s-%04d.html?%s" % (port, film, n, query), png, big)
        Image.open(png).convert("RGB").resize(SIZE, Image.LANCZOS).save(png)

    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(one, range(1, info["frames"] + 1)))

    pattern, palette = os.path.join(frames_dir, "%04d.png"), os.path.join(frames_dir, "palette.png")
    gif = os.path.join(out_dir, name + ".gif")
    rate = str(info["fps"])
    subprocess.run([FFMPEG, "-v", "error", "-y", "-framerate", rate, "-i", pattern,
                    "-vf", "palettegen=max_colors=256:stats_mode=full", palette], check=True)
    subprocess.run([FFMPEG, "-v", "error", "-y", "-framerate", rate, "-i", pattern, "-i", palette,
                    "-lavfi", "[0:v][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle", "-loop", "0", gif],
                   check=True)
    size = os.path.getsize(gif)
    print("wrote %s: %d frames, %.1f s, %.2f MB%s" % (gif, info["frames"], info["frames"] / info["fps"],
                                                     size / 1048576, "" if size < LIMIT else "  OVER 5 MB"))
    return size < LIMIT


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    root = os.path.abspath(args.pop(0))
    out_dir = OUT
    if args[:1] == ["--out"]:
        out_dir = args[1]
        args = args[2:]
    only = set(args)
    if not os.path.exists(os.path.join(root, "fonts", "expressway.ttf")):
        sys.exit("make_gifs: no fonts/expressway.ttf in " + root + " (see CLAUDE.md)")
    os.makedirs(out_dir, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=root))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        ok = all([make(root, out_dir, server.server_address[1], name, film, params)
                  for name, film, params in GIFS if not only or name in only])
    finally:
        server.shutdown()
    if not ok:
        sys.exit("make_gifs: a GIF is over 5 MB")


if __name__ == "__main__":
    main()
