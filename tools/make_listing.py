#!/usr/bin/env python3
"""Tutti dev tool: renders the CurseForge gallery from the addon's real UI.

    python3 -I tools/make_listing.py <render-dir> [--out <dir>] [name ...]

Run from the addon folder. <render-dir> holds what tools/render_ui.lua pages
need (see CLAUDE.md): media/, fonts/expressway.ttf, fonts/expressway-bold.ttf,
class/, icons/ and icon.png; the generated backdrops named in SHOTS (bg-*.jpg,
never the mockup's private backdrop.jpg) are copied into it from
docs/listing/backdrops/. Every scene is rendered fresh with
luajit, served over http (the fonts need it) and shot with headless Chrome
into docs/listing/screenshots/ (or --out). Names pick shots: "hero", "03-winner".

Copy follows the listing rules: one idea per headline, short words, one word
in the accent (*word*), | breaks a line. The story runs: every roll in one
window, who picked what, the winner, you won, the session's results, your UI.
"""
import functools
import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.parse

# Google Chrome: the CHROME environment variable, else where macOS installs it.
CHROME = os.environ.get("CHROME") or "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = os.path.join("docs", "listing", "screenshots")
BACKDROPS = os.path.join("docs", "listing", "backdrops")  # the generated backdrops (R48)
EUI_ACCENT = "#00cfff"  # EllesmereUI's accent, as the "eui" variant of a scene draws it

# name, scene (tools/render_ui.lua, "scene:eui" for EllesmereUI's accent), shot parameters
SHOTS = [
    ("01-every-roll", "pick", dict(
        bg="bg-vault.jpg", layout="left", eyebrow="Group loot",
        title="Every roll,|in *one* window.",
        sub="Each item gets a card,|with your whole group under it.")),
    ("02-picks", "rolling", dict(
        bg="bg-hall.jpg", layout="right", scale="2.45", eyebrow="The whole group",
        title="Who picked *what*,|at a glance.",
        sub="Need, Greed, Pass or still choosing,|right next to every name.")),
    ("03-winner", "winner", dict(
        bg="bg-camp.jpg", layout="left", scale="2.05", eyebrow="The roll",
        title="Every number.|One *winner*.",
        sub="The numbers spin in,|the winner gets a crown.")),
    ("04-you-won", "glow", dict(
        bg="bg-vault.jpg", layout="right", scale="2.45", eyebrow="Your loot",
        title="When you win,|it *glows*.",
        sub="A light sweeps the card,|a soft chime plays.")),
    ("05-recent", "recent", dict(
        bg="bg-camp.jpg", layout="left", eyebrow="Recent rolls",
        title="The whole *run*,|one click away.",
        sub="Every result of the session,|with everyone's picks.")),
    ("06-settings", "settings:eui", dict(
        bg="bg-hall.jpg", layout="right", scale="2.3", accent=EUI_ACCENT, eyebrow="Settings",
        title="Looks like|*your* UI.",
        sub="Follows EllesmereUI's colours and font,|or your class colour.",
        pills="Raid view,Transmog rolls,Item tooltips,Closes by itself,/tutti demo,Works without EllesmereUI")),
    ("hero", "winner", dict(
        bg="bg-vault.jpg", layout="left", hero="1", scale="1.38", w="1920", h="640", cx="1450", cy="320",
        tagline="Every group loot roll in one *calm* window,|drawn in the EllesmereUI look.")),
]


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def run(args):
    """Runs a command; when it fails, what it wrote to stderr is shown and the tool stops."""
    try:
        return subprocess.run(args, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        sys.stderr.write((e.stderr or b"").decode("utf-8", "replace"))
        sys.exit("make_listing: %s failed (exit %d)" % (os.path.basename(args[0]), e.returncode))


def backdrops(root, names):
    """Copies the backdrops the shots name from docs/listing/backdrops/ into the render dir, which serves them."""
    for name in sorted(names):
        source = os.path.join(BACKDROPS, name)
        if not os.path.exists(source):
            sys.exit("make_listing: no backdrop " + source)
        shutil.copyfile(source, os.path.join(root, name))


def page(scene):
    """The page's file name for a scene ("settings:eui" -> settings-eui.html) and the render_ui arguments."""
    name, _, variant = scene.partition(":")
    return name + ("-" + variant if variant else "") + ".html", [name] + ([variant] if variant else [])


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
    shots = [s for s in SHOTS if not only or s[0] in only]
    if not os.path.exists(os.path.join(root, "fonts", "expressway.ttf")):
        sys.exit("make_listing: no fonts/expressway.ttf in " + root + " (see CLAUDE.md)")
    os.makedirs(out_dir, exist_ok=True)
    backdrops(root, {s[2]["bg"] for s in shots if "bg" in s[2]})
    for scene in sorted({s[1] for s in shots}):
        html, render_args = page(scene)
        run(["luajit", "tools/render_ui.lua", os.path.join(root, html)] + render_args)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=root))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    try:
        for name, scene, params in shots:
            query = dict(shot="1", scale="1.9")
            query.update(params)
            url = "http://127.0.0.1:%d/%s?%s" % (port, page(scene)[0], urllib.parse.urlencode(query))
            out = os.path.abspath(os.path.join(out_dir, name + ".png"))
            profile = tempfile.mkdtemp(prefix="tutti-chrome-")  # a profile of its own, as make_gifs.py's
            try:
                run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--user-data-dir=" + profile,
                     "--force-device-scale-factor=1",
                     "--window-size=%s,%s" % (query.get("w", "1920"), query.get("h", "1080")),
                     "--virtual-time-budget=4000", "--screenshot=" + out, url])
            finally:
                shutil.rmtree(profile, ignore_errors=True)
            print("wrote", os.path.relpath(out) if out.startswith(os.getcwd() + os.sep) else out)
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
