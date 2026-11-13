# Tutti: builder's ledger

The builder's decisions and progress, one line each.

Task 1 done: Core (Init, DB, Color, Theme), `Tutti.toc`, the offline test harness and the repo files (`luajit tests/run.lua` → 45 passed, 0 failed; `luajit tests/syntax.lua` → syntax ok).
Ruling: added `tests/test_init.lua` for the Init helpers (the brief named load, db, color and theme only) — cost if wrong: none.
Ruling: the fake client keeps a one-method `DEFAULT_CHAT_FRAME` (lines go to `W.chatLog`) so `ns.Print` can be tested; the rest of the chat machinery is gone — cost if wrong: none.
Ruling: Theme drops the palette entries only Sotto's chat, rail and lockdown UI used (`bn`, `link`, `quest`, `offline`, `success`, `warning`, `warningText`, `danger`, `warnBg`, `warnLine`); Sotto's widgets and their tests use none of them — cost if wrong: a later task adds one line back.
Ruling: the pick colours are palette entries (`need`, `greed`, `pass`, `transmog`) as well as `Theme.Pick` states, so `Theme.Hex("need")` and name-based fills work; `wait` and `out` read the `faint` grey — cost if wrong: none.
Ruling: an unknown, missing or secret item quality reads as Common (white) in `Theme.Quality` and `Theme.QualityEdge`, and the lifted qualities are cached per panel colour (cleared on every `Refresh`) — cost if wrong: none.
