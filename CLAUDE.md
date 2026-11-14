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
  recent, settings and big (the mockup's states) and glow (the listing's "you won"), `eui` as a
  third argument for EllesmereUI's accent; a film (drop, click, won) writes a page per frame. The
  page expects next to it: `media/` (`python3 -I tools/tga2png.py <dir>`), `fonts/expressway.ttf`
  and `fonts/expressway-bold.ttf` (the tool also measures text with them),
  `class/class-<class>.png` and `icons/<key>.png` (axe gloves treads orb robes rope grips), all
  from `docs/mockup/assets`, some renamed: `icon-dualblade.png` is `icons/axe.png`,
  `icon-shapers.png` is `icons/gloves.png`, the other `icon-<key>.png` are `icons/<key>.png`. A
  page draws no backdrop unless it asks for one: `?bg=backdrop.jpg` (`bd-dalaran.jpg`, renamed;
  private: only to compare with the mockup in the same state, its `#<state>` hash, with headless
  Chrome at 2x; never in a public image). Serve the dir over http; keep the renders out of the repo.
- Listing (`docs/listing/`): the render dir above plus `icon.png`. The generated backdrops
  `bg-vault.jpg`, `bg-hall.jpg` and `bg-camp.jpg` (blurred) and their prompts (`prompts.md`) are
  in `docs/listing/backdrops/` (R48), and both tools copy the ones they name into the render dir;
  the sharp originals and `prep_bg.py` stay out of git (`.superpowers/listing/`).
  `python3 -I tools/make_listing.py <dir>` renders `screenshots/` (six shots and the hero);
  `python3 -I tools/make_gifs.py <dir>` makes the three `animations/` (800 x 500, 15 fps, each
  under 5 MB; Chrome, Pillow and ffmpeg; the frames stay in `<dir>/gif-<name>/`). Copy and layout
  are their `SHOTS` and `GIFS` lists (one idea per headline, one `*accent*` word, `|` breaks a
  line), the films' timing `FILMS` in `tools/render_ui.lua`, the listing's text
  `docs/listing/curseforge.md`. Look at every image, and at frames of every GIF
  (`ffmpeg -i x.gif -vsync 0 f%03d.png`), before committing them.
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
