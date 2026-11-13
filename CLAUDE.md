# Tutti

Every group loot roll in one window (who picked Need, Greed or Pass, the rolls, the winner),
in the EllesmereUI + Polestar look, built on WoW Forever (12.1 engine, Interface 16001). A
sibling of Sotto, with the same foundations. Author for anything public: creazy231.

- Design: `docs/design.md`; approved look: `docs/mockup/tutti-mockup.html` (serve `docs/mockup`
  over http, for example `python3 -m http.server`, the font needs it; keep the built window
  pixel-close to it). Plan: `docs/plan.md`; the builder's decisions and progress:
  `docs/ledger.md`.
- Offline checks, from this folder, after every change:
  `luajit tests/run.lua && luajit tests/syntax.lua && python3 -I tests/test_media.py` (LuaJIT
  from Homebrew; `tests/fake_wow.lua` is the fake client, `tests/harness.lua` the loader). One
  file: `luajit tests/run.lua tests/test_x.lua`.
- Blizzard's own code: github.com/Gethe/wow-ui-source, branch `forever` (the loot-history and
  roll-popup files Tutti works with are named in `docs/design.md`, "How it works"). Check every
  new hook or API against it.
- Rules that keep Tutti taint-free:
  - plain frames only, no secure templates; hooks only through `hooksecurefunc`; never assign
    to a Blizzard global or to a field of a Blizzard frame;
  - every event payload and API result goes through `ns.IsSecret` and a type check before it
    is compared, indexed or stored: `ns.Clear(value, kind)` does both (the value when it is in the
    clear and of that type, else nil), so do not write a copy of that guard;
  - every event and message handler runs through the protected dispatch (`ns.On`, `ns.Listen`);
  - EllesmereUI only through `EllesmereUI.RegisterSkin` getters (`GetPanelColor`,
    `GetAccentColor`, `GetFont`, `OnLooksChanged`): no EllesmereUI internals, no `EllesmereUIDB`.
- Never ship `docs/`, `tests/` or `tools/` (`.pkgmeta` ignores them, with this file and the
  README). `docs/mockup/` holds a private game screenshot and EllesmereUI's licensed font: it
  is git-ignored and never committed.
- Git: repo-local identity creazy231 / 13473174+creazy231@users.noreply.github.com. The GitHub
  repo and the CurseForge project are created only when the user asks.
- After a user-visible change: add a `CHANGELOG.md` entry under the next version.
  `## Version: @project-version@` in `Tutti.toc` is filled in by the packager from the tag.
