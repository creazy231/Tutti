# Tutti

Every group loot roll in one window (who picked Need, Greed or Pass, the rolls, the winner),
in the EllesmereUI + Polestar look, built on WoW Forever (12.1 engine, Interface 16001). A
sibling of Sotto, with the same foundations. Author for anything public: creazy231.

- Design: `docs/design.md`; approved look: `docs/mockup/tutti-mockup.html` (serve `docs/mockup`
  over http, for example `python3 -m http.server`, the font needs it; keep the built window
  pixel-close to it). Plan: `docs/plan.md`; the builder's decisions and progress, and the
  in-game checklist: `docs/ledger.md`.
- Offline checks, from this folder, after every change:
  `luajit tests/run.lua && luajit tests/syntax.lua && python3 -I tests/test_media.py` (LuaJIT
  from Homebrew; `tests/fake_wow.lua` is the fake client, `tests/harness.lua` the loader). One
  file: `luajit tests/run.lua tests/test_x.lua`.
- Media: `python3 -I tools/make_media.py .` and `python3 -I tools/make_sound.py .` regenerate
  `Media/` (Pillow, ffmpeg); the generator is byte-stable, so only a changed texture shows in git.
- Visual check without the game: `luajit tools/render_ui.lua <dir>/pick.html pick` draws what the
  addon built in the fake client as an HTML page. Scenes: pick, rolling, winner, youwon, closing,
  recent, settings and big (the mockup's states), `eui` as a third argument for EllesmereUI's
  accent. The page expects next to it: `media/` (`python3 -I tools/tga2png.py <dir>`),
  `fonts/expressway.ttf` and `fonts/expressway-bold.ttf` (the tool also measures text with them),
  `class/class-<class>.png`, `icons/<key>.png` (axe gloves treads orb robes rope grips) and
  `backdrop.jpg` (all from `docs/mockup/assets`). Serve the dir over http; `?shot=1&scale=2&bg=<image>`
  frames the window for listing shots. Compare with the mockup in the same state (its `#<state>`
  hash) with headless Chrome at 2x; keep the renders out of the repo.
- Public images (the listing, GIFs): R30's made-up cast (the player Maelis Ashvale, Orlen
  Brightmoor, Brisé Tidewater, Corvel Duskmantle, Kestrel Ironmark) and generated backdrops;
  never the mockup's screenshot (`backdrop.jpg`) or its character names.
- Blizzard's own code: github.com/Gethe/wow-ui-source, branch `forever` (the loot-history and
  roll-popup files Tutti works with are named in `docs/design.md`, "How it works"). Check every
  new hook or API against it.
- Rules that keep Tutti taint-free:
  - plain frames only, no secure templates; hooks only through `hooksecurefunc`; never assign
    to a Blizzard global or to a field of a Blizzard frame;
  - every event payload and API result goes through `ns.IsSecret` and a type check before it
    is compared, indexed or stored: `ns.Clear(value, kind)` does both (the value when it is in the
    clear and of that type, else nil) and `ns.Text(value)` is the same for a non-empty string, so do
    not write a copy of either guard;
  - every event and message handler runs through the protected dispatch (`ns.On`, `ns.Listen`);
  - EllesmereUI only through `EllesmereUI.RegisterSkin` getters (`GetPanelColor`,
    `GetAccentColor`, `GetFont`, `OnLooksChanged`): no EllesmereUI internals, no `EllesmereUIDB`.
- Never ship `docs/`, `tests/` or `tools/` (`.pkgmeta` ignores them, with this file and the
  README). `docs/mockup/` holds a private game screenshot and EllesmereUI's licensed font: it
  is git-ignored and never committed.
- Git: repo-local identity creazy231 / 13473174+creazy231@users.noreply.github.com. The GitHub
  repo and the CurseForge project are created only when the user asks. Releases: a version tag
  runs `.github/workflows/release.yml` (BigWigs packager); see `docs/RELEASING.md`.
- After a user-visible change: add a `CHANGELOG.md` entry under the next version.
  `## Version: @project-version@` in `Tutti.toc` is filled in by the packager from the tag.
