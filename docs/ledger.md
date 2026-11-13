# Tutti: builder's ledger

The builder's decisions and progress, one line each.

Task 1 done: Core (Init, DB, Color, Theme), `Tutti.toc`, the offline test harness and the repo files (`luajit tests/run.lua` → 45 passed, 0 failed; `luajit tests/syntax.lua` → syntax ok).
Ruling: added `tests/test_init.lua` for the Init helpers (the brief named load, db, color and theme only) — cost if wrong: none.
Ruling: the fake client keeps a one-method `DEFAULT_CHAT_FRAME` (lines go to `W.chatLog`) so `ns.Print` can be tested; the rest of the chat machinery is gone — cost if wrong: none.
Ruling: Theme drops the palette entries only Sotto's chat, rail and lockdown UI used (`bn`, `link`, `quest`, `offline`, `success`, `warning`, `warningText`, `danger`, `warnBg`, `warnLine`); Sotto's widgets and their tests use none of them — cost if wrong: a later task adds one line back.
Ruling: the pick colours are palette entries (`need`, `greed`, `pass`, `transmog`) as well as `Theme.Pick` states, so `Theme.Hex("need")` and name-based fills work; `wait` and `out` read the `faint` grey — cost if wrong: none.
Ruling: an unknown, missing or secret item quality reads as Common (white) in `Theme.Quality` and `Theme.QualityEdge`, and the brightened qualities are cached per quality (cleared on every `Refresh`, since the background can change) — cost if wrong: none.
R6 (the controller's ruling, issued after Task 1 started): item quality text is the quality colour brightened in OKLab lightness, hue and chroma kept (`ns.Color.Shift`, steps of 0.0025, bounded), until it reads at 5.5:1, instead of Sotto's 4.5:1 mix toward white; rare comes out #2f8dfc (the approved mockup's #2b8cff), epic #c35cff, and every quality that already reads (poor, common, uncommon, legendary, artifact, heirloom) stays exactly the game's colour; the icon edge stays the raw `ITEM_QUALITY_COLORS` — the approved look decides — cost if wrong: one colour rule.
R6a (the controller's ruling): the contrast ground for R6 is `P.bg`, the window background (EllesmereUI's panel colour, #141414 by default), not `P.panel` (#191919); the quoted hexes reproduce only on `P.bg` (on `P.panel` rare would be #3390ff) — cost if wrong: about 4/255 brighter blue.
Task 1 fix round 1 done: `Theme.Quality` follows R6 and R6a; `tests/test_theme.lua` asserts rare #2f8dfc, epic #c35cff, the colours that stay as the game has them, 5.5:1 on `P.bg`, and that the lift is redone when the background changes (`luajit tests/run.lua` → 46 passed, 0 failed; `luajit tests/syntax.lua` → syntax ok).
