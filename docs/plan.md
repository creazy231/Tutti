# Tutti Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Tutti, a WoW Forever addon that shows every group loot roll in one window: the whole group's picks, the roll numbers and an animated winner. The player rolls from the same window and Blizzard's roll popups stay hidden.

**Architecture:**
- **Copied foundation:** a standalone addon built on Sotto's foundation (`Interface/AddOns/Sotto`). These pieces are copied and renamed, not shared:
  - the event and message buses;
  - the settings store;
  - the colour maths;
  - the EllesmereUI theme;
  - the widgets;
  - the offline fake client.
- **Model:** a pure model (`Core/Rolls.lua`) merges the player's rolls (`START_LOOT_ROLL`, roll API) with the group's picks (`C_LootHistory`) into "cards" and fires messages.
- **UI:** the UI (`UI/*.lua`) only draws cards and reacts to those messages.

**Tech Stack:**
- the WoW Lua 5.1 API (Forever 1.60.1, Interface 16001, 12.1 engine);
- LuaJIT for offline tests;
- Python 3 with Pillow and ffmpeg for the media.

**Spec:** `docs/design.md`. Approved look: `docs/mockup/tutti-mockup.html`; its CSS is the source for every size and colour.
- **Blizzard's code:** github.com/Gethe/wow-ui-source, branch `forever`.
- **Sotto:** the sibling to copy from.

## Global Constraints

- **Addon folder and TOC:** `Interface/AddOns/Tutti`.
  - `## Interface: 16001`
  - `## Author: creazy231`
  - `## SavedVariables: TuttiDB`
  - `## Version: @project-version@`
- **Git:** run all commands from the addon folder. Use the repo-local identity creazy231 / 13473174+creazy231@users.noreply.github.com, never the global one.
- **Frames and hooks:**
  - plain frames only, no secure templates;
  - hooks only through `hooksecurefunc`;
  - never assign to a Blizzard global or a field of a Blizzard frame.
- **EllesmereUI:** only through `EllesmereUI.RegisterSkin` getters (`GetPanelColor`, `GetAccentColor`, `GetFont`, `OnLooksChanged`).
- **Secrets and errors:**
  - every event payload and API result passes `ns.IsSecret` and a type check before it is compared, indexed or stored;
  - every event and message handler runs through Sotto's protected dispatch.
- **Fixed sizes (px):**
  - window width 300;
  - header 32;
  - card padding 9 / 10 / 7;
  - item icon 34;
  - countdown block 16 (8 + 2 + 6);
  - buttons 23 high, block 31 (1 + 23 + 7);
  - reason line block 16 (−3 + 12 + 7);
  - row 21;
  - folded line 26;
  - recent line 36.
- **Colours:**
  - **picks:**
    - Need #6bd999, Greed #fabf4d, Pass #8d9096, Transmog #c58cff;
    - "choosing" and "not in this roll" #6f7277;
  - **text:** #f8f8f8, dim #cacccf, muted #a2a5a9, faint #6f7277;
  - **BiS gold:** #ffd100;
  - **item quality:** text lifted to 4.5:1 on the panel, with the icon edge in `ITEM_QUALITY_COLORS`;
  - **accent:** the class colour lifted to 4.5:1, or EllesmereUI's.
- **Font sizes (px, EllesmereUI font):**
  - title 13.5 bold;
  - item name 13.5 bold;
  - subtitle 11;
  - row name 12.5 bold;
  - pick word 11.5;
  - roll number 13 bold;
  - button 12;
  - folded line 12;
  - section label 9.5;
  - small 10.5;
  - "YOU" tag 9.5.
- **Timings:**
  - number spin 0.75 s;
  - winner wash 0.7 s;
  - crown pop 0.5 s after 0.3 s;
  - new pick fade-in 0.35 s;
  - window rise 8 px in 0.35 s, fade-out 0.55 s;
  - a decided card folds after 4 s;
  - closing 10 s after the last decision (setting choices 5 / 10 / 20 / 30 / 0 = never);
  - a roll without a history decision ends 5 s after its time runs out.
- **Strings:** English UI text, as in the design. Game words come from Blizzard globals (`NEED`, `GREED`, `PASS`, `TRANSMOGRIFICATION`, `LOOT_ROLL_INELIGIBLE_REASON<n>`), with English fallbacks.
- **Shipping:** never ship `docs/`, `tests/` or `tools/`. The mockup assets in `docs/mockup/` are git-ignored.

## Review Focus

1. The loot history for an item arrives before its `START_LOOT_ROLL`. Expected: one card, not two. Test in Task 5: "history first, roll second: one card".
2. Two copies of one item drop together. Expected: each roll keeps its own card, and the player's pick stays on the card it was made on. Test in Task 5: "two copies of one item match two cards".
3. The item isn't cached when the roll starts (`C_Item.GetItemInfo` returns nil). Expected: the card shows the roll's own name and icon, and the type label fills in later. Test in Task 4: "an uncached item fills in its label later".
4. A new roll starts while the window shows Recent rolls or Settings, or while it counts down to close. Expected: it switches to the rolls and the countdown stops. Tests in Task 11: "a new roll cancels the countdown" and "a new roll leaves Recent or Settings".
5. Secret or missing payloads arrive in or after combat (a secret encounter id, `GetSortedInfoForDrop` returning nil). Expected: ignored, no Lua error, no broken card. Test in Task 5: "secret or missing history is ignored".

---

## File map

| File | Responsibility |
|---|---|
| `Tutti.toc` | metadata, load order |
| `Core/Init.lua` | namespace, `ns.IsSecret`, `ns.On/Off`, `ns.Listen/Fire`, `ns.Safe`, `ns.After`, `ns.Print` (from Sotto, without `InLockdown`) |
| `Core/DB.lua` | `TuttiDB`, defaults, `ns.Get/Set` |
| `Core/Color.lua` | OKLab, contrast and lift (copied from Sotto) |
| `Core/Theme.lua` | palette, accent, fonts, pick and quality colours (from Sotto) |
| `Core/Items.lua` | item type label and item level |
| `Core/Group.lua` | group members in display order |
| `Core/Rolls.lua` | the card model: rolls, loot history, matching, decisions |
| `Core/Popups.lua` | switching Blizzard's roll popups off |
| `Core/History.lua` | the session's results |
| `Core/Integrations.lua` | NaowhForever BiS badge |
| `UI/Widgets.lua` | drawing primitives and controls (from Sotto) plus the roll button and item icon |
| `UI/Fx.lua` | tweens and the animations |
| `UI/Card.lua` | one card: head, countdown, buttons, rows, winner, folded line |
| `UI/Recent.lua` | the Recent rolls view |
| `UI/Settings.lua` | the Settings view |
| `UI/Window.lua` | the window: header, views, stacking, folding, closing, position, scale, sound |
| `UI/Launcher.lua` | addon compartment, `/tutti` |
| `UI/Demo.lua` | `/tutti demo`: the mockup's boss drop with made-up data, no real rolls |
| `Media/*.tga`, `Media/Sounds/chime.ogg` | glyphs, shapes, sound (generated) |
| `tests/` | fake client, harness, `test_*.lua`, `test_media.py` |
| `tools/` | `make_media.py`, `make_sound.py`, `tga2png.py`, `render_ui.lua` |
| `docs/ledger.md` | the builder's decisions and progress, one line each |

TOC load order: the Core files in the order above, then `UI/Widgets.lua`, `UI/Fx.lua`, `UI/Card.lua`, `UI/Recent.lua`, `UI/Settings.lua`, `UI/Window.lua`, `UI/Launcher.lua`, `UI/Demo.lua`.

Commands, run from `Interface/AddOns/Tutti`:
- all tests: `luajit tests/run.lua`
- one file: `luajit tests/run.lua tests/test_x.lua`
- syntax check: `luajit tests/syntax.lua`
- media check: `python3 -I tests/test_media.py`

---

### Task 1: Foundation, repo and test harness

**Files:**
- Create: `Tutti.toc`, `Core/Init.lua`, `Core/DB.lua`, `Core/Color.lua`, `Core/Theme.lua`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `.pkgmeta`, `docs/ledger.md`
- Create: `tests/fake_wow.lua`, `tests/harness.lua`, `tests/run.lua`, `tests/syntax.lua`
- Test: `tests/test_load.lua`, `tests/test_db.lua`, `tests/test_color.lua`, `tests/test_theme.lua`

**Interfaces:**
- Produces:
  - `ns.IsSecret(...) -> bool`, `ns.Safe(fn, ...) -> bool`
  - `ns.On(event, fn) -> bool`, `ns.Off(event, fn)`
  - `ns.Listen(msg, fn)`, `ns.Fire(msg, ...)`
  - `ns.After(sec, fn)`, `ns.Print(text)`
  - `ns.DEFAULTS`, `ns.DB` (= `TuttiDB`), `ns.Get(key)`, `ns.Set(key, value)`; `Set` fires `"SETTING_CHANGED", key, value` and nothing when the value is unchanged; `"DB_READY"` fires on `ADDON_LOADED`.
  - `ns.Color.*` (as in Sotto)
  - `ns.Theme.Refresh()`, `.Color(name) -> r,g,b,a`, `.Accent() -> r,g,b`, `.Hex(name)`, `.ClassColor(classFile) -> r,g,b`
  - `ns.Theme.Font(role) -> path,size,flags`, `.ApplyFont(fs, role)`
  - `ns.Theme.Pick(state) -> r,g,b` for `"need"|"greed"|"pass"|"transmog"|"wait"|"out"`
  - `ns.Theme.Quality(q) -> r,g,b` (text, lifted), `ns.Theme.QualityEdge(q) -> r,g,b` (raw)
  - Font roles: `title`, `item`, `sub`, `row`, `pick`, `roll`, `button`, `fold`, `section`, `small`, `you` (sizes from Global Constraints).
  - `"LOOKS_CHANGED"` message.
- Fake client: `T.load(opts) -> G, W, ns`, with the same options as Sotto's (`eui`, `db`, `setup`, `login`). It also provides `W.fire`, `W.advance(seconds)`, `W.clock`, `W.units`, `W.player`, `W.installEUI`, `W.euiLogin`, and `F.secret` as `T.secret`.

**Defaults** (`ns.DEFAULTS`):
- `settings`:
  - `rollInTutti = true`
  - `closeAfter = 10` (0 = never)
  - `sound = "chime"` (`"chime"|"none"`)
  - `accent = "class"` (`"class"|"eui"`)
  - `scale = 1` (0.8–1.3)
- `window = { point = "TOPLEFT", x = 372, y = -226 }`
- `recent = {}`, `schema = 1`

- [ ] **Step 1: Copy Sotto's harness and fake client, renamed.**
  - Copy `tests/fake_wow.lua`, `tests/harness.lua`, `tests/run.lua` and `tests/syntax.lua` from Sotto, renaming "Sotto" to "Tutti" (the TOC name, `SottoDB` → `TuttiDB`).
  - Delete from `fake_wow.lua` what only Sotto uses:
    - chat frames and edit box;
    - `C_ChatInfo`;
    - Battle.net;
    - menus and UnitPopup;
    - bindings;
    - whisper builders.
  - Keep: widgets with anchors, font metrics, events, timers, secrets, units, `GameTooltip`, `PlaySound*`, `UnitClass`, `IsInRaid`, `GetNumGroupMembers` and the EllesmereUI stand-in.

- [ ] **Step 2: Write the failing tests.**
  - `test_load.lua`:
    - "every TOC file loads": `local G, W, ns = T.load(); T.ok(ns.Theme and ns.DB)`.
    - "the TOC says Interface 16001, Author creazy231, SavedVariables TuttiDB": read `Tutti.toc` lines.
  - `test_db.lua`:
    - "fresh DB gets the defaults": every value above, e.g. `T.eq(ns.Get("closeAfter"), 10)`, `T.eq(ns.DB.window.x, 372)`.
    - "Set fires SETTING_CHANGED once and skips equal values".
  - `test_color.lua`: copy Sotto's.
  - `test_theme.lua`:
    - "pick colours": `T.color({ns.Theme.Pick("need")}, "6bd999")` and the same for greed #fabf4d, pass #8d9096, transmog #c58cff, wait and out #6f7277.
    - "quality text reads at 4.5:1 and the edge stays raw": `ns.Color.Contrast({ns.Theme.Quality(3)}, panel) >= 4.5`, and `QualityEdge(3)` equals `ITEM_QUALITY_COLORS[3]`.
    - Copy Sotto's accent and font tests (class colour, EllesmereUI accent with `accent = "eui"`, EllesmereUI's font, and the bold Expressway beside it).

- [ ] **Step 3: Run `luajit tests/run.lua`.** Expected: FAIL (the Core files don't exist).

- [ ] **Step 4: Copy and adapt the Core files.**
  - `Core/Init.lua`: Sotto's, without `InLockdown`. The print prefix is "Tutti".
  - `Core/DB.lua`: Sotto's `fill` / `Get` / `Set` with the defaults above.
  - `Core/Color.lua`: copied as is.
  - `Core/Theme.lua`:
    - Sotto's, without `ns.Format` and `fontSize`.
    - Roles use the fixed sizes.
    - Add `Pick`, `Quality` (lift `ITEM_QUALITY_COLORS[q]` with `ns.Color.Lift(P.panel, P.text, c, 4.5)`, cached per quality) and `QualityEdge`.
    - Register the skin as `"Tutti"`.
  - Write `Tutti.toc` per Global Constraints:
    - `## Title: Tutti`;
    - `## Notes: Every group loot roll in one window: who picked Need, Greed or Pass, the rolls and the winner.`;
    - `## Category: Loot`;
    - `## OptionalDeps: EllesmereUI, NaowhForever_BiS`;
    - `## IconTexture: Interface\AddOns\Tutti\Media\mark`;
    - the three `AddonCompartmentFunc*` lines (functions `Tutti_OnAddonCompartmentClick`, `…Enter`, `…Leave`, defined in Task 12; until then `test_load` tolerates their absence).
    - List only the files that exist so far.

- [ ] **Step 5: Run `luajit tests/run.lua && luajit tests/syntax.lua`.** Expected: all pass.

- [ ] **Step 6: Repo files.**
  - `.gitignore`: Sotto's, minus `PUBLISHING.md`.
  - `.pkgmeta`: Sotto's with `package-as: Tutti`.
  - `LICENSE`: MIT, "Copyright (c) 2026 creazy231".
  - `README.md`: what Tutti does, in 5 lines.
  - `CHANGELOG.md`: "## 1.0.0 (unreleased)".
  - `CLAUDE.md`: Sotto's structure, adapted. It covers: the test commands, the design and mockup paths, the taint rules from Global Constraints, the Blizzard source branch, "author creazy231", and "never ship docs/tests/tools".
  - `docs/ledger.md`: a title and "Task 1 done".

- [ ] **Step 7: Commit.**

```bash
git init -b main && git config user.name creazy231 && git config user.email 13473174+creazy231@users.noreply.github.com
git add -A && git commit -m "Tutti: foundation, theme and offline test harness"
```

### Task 2: Media

**Files:**
- Create: `tools/make_media.py`, `tools/make_sound.py`, `tools/tga2png.py`, `Media/*.tga`, `Media/Sounds/chime.ogg`
- Test: `tests/test_media.py`

**Interfaces:**
- Produces textures under `Interface\AddOns\Tutti\Media\`, white on transparent and tinted in code:
  - `mark` (64 px);
  - 32 px glyphs: `need`, `greed`, `pass`, `transmog`, `crown`, `star`, `clock`, `gear`, `close`, `back`, `chevron`, `dot`;
  - shapes: `circle`, `pill`, `shadow`, `wash` (horizontal alpha ramp, white 100 % to 0 %, 128×16), `shine` (soft diagonal band, 64×64), `ring` (a 34 px icon's glow ring, 64 px).
  - `Media\Sounds\chime.ogg`.

- [ ] **Step 1: Write `tests/test_media.py`** (adapted from Sotto's). It checks that:
  - every `Media\\<name>` referenced in any `*.lua` exists as `Media/<name>.tga` or `.ogg`;
  - each TGA is uncompressed 32-bit with power-of-two sides;
  - the glyph list above is complete.

- [ ] **Step 2: Run `python3 -I tests/test_media.py`.** Expected: FAIL (no Media folder).

- [ ] **Step 3: Write `tools/make_media.py`.**
  - Base it on Sotto's (8× supersampling, Lanczos).
  - Draw the glyphs to the mockup's SVG geometry (`docs/mockup/tutti-mockup.html`, `ICON`):
    - `need`: a rounded square with 3 diagonal pips;
    - `mark`: a die with 5 pips;
    - `greed`: two concentric circles;
    - `pass`: a circle with a diagonal;
    - `crown`: a polygon;
    - `star`: 5 points;
    - `clock`: a circle with hands;
    - `transmog`: a coat hanger, same stroke;
    - `dot`: a 6 px disc.
  - Gear, close, back and chevron are Sotto's.
- Copy `tools/make_sound.py` and `tools/tga2png.py` from Sotto, and generate the chime.

- [ ] **Step 4: Run `python3 -I tools/make_media.py . && python3 -I tools/make_sound.py . && python3 -I tests/test_media.py`.** Expected: PASS.

- [ ] **Step 5: Commit** (`git add tools Media tests/test_media.py && git commit -m "Tutti: glyphs, shapes and the win chime"`).

### Task 3: Group members

**Files:**
- Create: `Core/Group.lua`
- Modify: `tests/fake_wow.lua` (group units), `Tutti.toc`
- Test: `tests/test_group.lua`

**Interfaces:**
- Consumes: `ns.On`, `ns.Fire`, `ns.IsSecret`.
- Produces:
  - `ns.Group.Members() -> { member, ... }` in display order.
    - `member = { unit, guid, name, first, class, isPlayer }`
    - `name` is the full name ("Orlen Brightmoor");
    - `first` is the first name ("Orlen");
    - `class` is the class file ("PALADIN").
  - `ns.Group.ByGUID(guid) -> member|nil`
  - `ns.Group.IsRaid() -> bool`
  - `ns.Group.FirstName(fullName) -> string`
  - Message `"GROUP_CHANGED"`.
- Fake client: `W.setGroup(list, opts)`.
  - Each `list` entry is `{ unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" }`.
  - With `opts.raid = true`, the units are `raid1..`, and the player is one of them via `unit = "raid3"` and `isPlayer = true`.
  - `UnitName` returns first name and surname (Forever).
  - `IsInRaid` and `GetNumGroupMembers` follow the list.

- [ ] **Step 1: Write the failing tests** (`test_group.lua`):
  - "party order is party1..party4, then the player": the names `{"Orlen","Brisé","Corvel","Kestrel","Ayla"}`, with the player last and `isPlayer` true.
  - "raid order follows raid1..raidN and marks the player".
  - "the first name is UnitName's first return on Forever".
  - "FirstName splits 'Orlen Brightmoor' and 'Orlen-Brightmoor' to 'Orlen'".
  - "members with a secret or missing GUID are skipped": `T.secret("Player-1-9")`.
  - "GROUP_ROSTER_UPDATE fires GROUP_CHANGED".
  - "solo: only the player".
- [ ] **Step 2: Run `luajit tests/run.lua tests/test_group.lua`.** Expected: FAIL.
- [ ] **Step 3: Implement `Core/Group.lua`.**
  - Rebuild the list on `GROUP_ROSTER_UPDATE` and `PLAYER_ENTERING_WORLD` (and at load), using `UnitGUID`, `UnitName` and `UnitClass`.
  - Cache by GUID.
- [ ] **Step 4: Run the file, then `luajit tests/run.lua`.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: group members in party-frame order"`).

### Task 4: The player's rolls

**Files:**
- Create: `Core/Items.lua`, `Core/Rolls.lua`
- Modify: `tests/fake_wow.lua` (loot roll API), `Tutti.toc`
- Test: `tests/test_items.lua`, `tests/test_rolls.lua`

**Interfaces:**
- Consumes: `ns.Group.Members()`, `ns.Group.ByGUID`.
- Produces:
  - `ns.Items.Describe(link) -> label|nil, ilvl|nil`. The label is nil while the item is uncached.
  - `ns.Rolls.Cards() -> { card, ... }` in arrival order.
  - `ns.Rolls.Get(id) -> card|nil`
  - `ns.Rolls.Pick(card, choice) -> bool`, with `choice` one of `"need"|"greed"|"transmog"|"pass"`.
  - `ns.Rolls.TimeLeft(card) -> seconds` (≥ 0, a float).
  - `ns.Rolls.AwaitsMe(card) -> bool`: `rollID` is set, `over` is false, `mine` is nil, and `status == "live"`.
  - `ns.Rolls.Rows(card) -> { row, ... }`, defined in Task 5. Until then it is the group with `state = "wait"`, and the player's row shows `mine`.
  - `ns.Rolls.Forget(card)`, `ns.Rolls.ForgetDecided()`
  - Messages:
    - `"CARD_ADDED", card`
    - `"CARD_CHANGED", card, changes`, where `changes` is a set with keys among `item`, `mine`, `over`, `picks`, `decided`;
    - `"CARD_DECIDED", card` (fired once per card);
    - `"CARD_REMOVED", card`.
  - Card fields:
    - `id` (Tutti's own counter), `rollID|nil`, `link`, `itemID`
    - `name`, `icon`, `quality`, `count`, `bop`
    - `label|nil`, `ilvl|nil`
    - `canNeed`, `canGreed`, `canTransmog`, `reasonNeed|nil` (text)
    - `startedAt` (`GetTime()`), `duration` (seconds)
    - `mine|nil`, `over`, `history` (bool)
    - `picks = { [guid] = { state, roll|nil, name, class } }`
    - `status` (`"live"|"decided"|"ended"`), `winner|nil` (guid), `allPassed`, `decidedAt|nil`, `demo|nil`.
- Fake client:
  - `W.addRoll(rollID, spec)` stores a roll and fires `START_LOOT_ROLL(rollID, spec.time or 60000)`.
    - `spec = { link, name, texture, quality = 3, count = 1, bop = true, canNeed = true, canGreed = true, canTransmog = false, reasonNeed = 0 }`
  - `W.items[itemID] = { name, link, quality, ilvl, classID, subclassID, equipLoc, texture }` (missing means uncached), plus `W.cacheItem(itemID)`, which fires `GET_ITEM_INFO_RECEIVED(itemID, true)`.
  - `W.rolled` records `{ rollID, type }` for every `RollOnLoot` call.
  - `W.activeRolls` backs `GetActiveLootRollIDs()`.
  - Also provide `GetLootRollItemInfo`, `GetLootRollItemLink`, `GetLootRollTimeLeft` (ms, from `W.clock`), `C_Loot.GetLootRollDuration`, `C_Item.GetItemInfo`, and `LOOT_ROLL_INELIGIBLE_REASON1..7` strings.

- [ ] **Step 1: Write the failing tests.**
  - `test_items.lua` (uses the fake `W.items`):
    - "type labels as the mockup shows them":
      - (2, 1, `INVTYPE_2HWEAPON`) → "Two-Hand Axe";
      - (4, 2, `INVTYPE_HAND`) → "Leather Hands";
      - (4, 0, `INVTYPE_HOLDABLE`) → "Held In Off-hand";
      - (4, 3, `INVTYPE_FEET`) → "Mail Feet";
      - (4, 1, `INVTYPE_CHEST`) → "Cloth Chest";
      - (4, 1, `INVTYPE_ROBE`) → "Cloth Chest".
    - "uncached → nil, nil".
    - "item level comes from GetItemInfo".
  - `test_rolls.lua`:
    - "START_LOOT_ROLL adds one live card": checks name, quality, `duration == 60`, `rollID`, `status == "live"`, and that `CARD_ADDED` fired once.
    - "a roll without a name (GetLootRollItemInfo nil) adds no card".
    - "Need not allowed carries the game's reason": `canNeed = false, reasonNeed = 1` → `card.reasonNeed == LOOT_ROLL_INELIGIBLE_REASON1`.
    - "Pick need rolls 1 and marks mine": `W.rolled[1]` is `{7, 1}`, `card.mine == "need"`, and `changes.mine`.
    - "Pick greed 2, pass 0, transmog 4". Transmog only when `canTransmog` (and Greed is refused then).
    - "Pick need is refused when Need isn't allowed": returns false and `#W.rolled == 0`.
    - "Pick on a demo card never calls RollOnLoot".
    - "CANCEL_LOOT_ROLL ends the player's part, the card stays live".
    - "CANCEL_ALL_LOOT_ROLLS ends every part".
    - "TimeLeft counts down": after `W.advance(10)` → `T.near(TimeLeft, 50, 0.01)`.
    - "a reload during a roll rebuilds the cards": `W.activeRolls = {7}`, then `PLAYER_ENTERING_WORLD(false, true)` → one card.
    - **Review focus 3:** "an uncached item fills in its label later": `label == nil`; then `W.cacheItem(id)` → `label == "Two-Hand Axe"` and `CARD_CHANGED` with `changes.item`.
- [ ] **Step 2: Run the two files.** Expected: FAIL.
- [ ] **Step 3: Implement `Core/Items.lua` and `Core/Rolls.lua`.**
  - `Describe` builds the label from `equipLoc`'s global name (`_G[equipLoc]`: `INVTYPE_HAND` → "Hands"; `INVTYPE_ROBE` and `INVTYPE_CHEST` → "Chest"; `INVTYPE_HOLDABLE` → "Held In Off-hand") and the subclass:
    - Armor (classID 4): "<subType> <slot>". Subclass 0 (Miscellaneous) and holdables drop the subtype.
    - Weapons (classID 2): "<slot> <singular>" from a subclassID → word table: 0 Axe, 1 Axe, 2 Bow, 3 Gun, 4 Mace, 5 Mace, 6 Polearm, 7 Sword, 8 Sword, 10 Staff, 13 Fist Weapon, 15 Dagger, 16 Thrown, 18 Crossbow, 19 Wand. Otherwise use the slot alone.
  - `reasonNeed` = `_G["LOOT_ROLL_INELIGIBLE_REASON"..n]` when n > 0.
  - Item info is fetched again on `GET_ITEM_INFO_RECEIVED` for cards whose `itemID` matches.
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: the player's rolls as cards"`).

### Task 5: The group's picks from the loot history

**Files:**
- Modify: `Core/Rolls.lua`, `tests/fake_wow.lua` (`C_LootHistory`)
- Test: `tests/test_history_drops.lua`

**Interfaces:**
- Consumes: Task 4's card model and `ns.Group`.
- Produces:
  - Cards gain `encounterID`, `lootListKey`, `dropKey` (`"<enc>:<key>"`), `history = true` and `tied`.
  - `ns.Rolls.Rows(card) -> { row, ... }`.
    - `row = { guid, name, class, isPlayer, state, roll|nil, isWinner }`
    - `name` is the first name.
    - `state` is one of `"need"|"greed"|"transmog"|"pass"|"wait"|"out"`.
  - Row order:
    1. group members in `ns.Group.Members()` order;
    2. then history members no longer in the group, in history order.
  - A group member missing from the history is `"out"` once `card.history`; before that, `"wait"`.
  - The player's row: the history's `isSelf` entry when present, otherwise `card.mine`, otherwise `"wait"`.
- State map from `Enum.EncounterLootDropRollState`: NeedMainSpec 0 and NeedOffSpec 1 → need, Transmog 2 → transmog, Greed 3 → greed, NoRoll 4 → wait, Pass 5 → pass.
- Fake client: `W.setDrop(encounterID, lootListKey, info)` stores an `EncounterLootDropInfo`-shaped table and fires `LOOT_HISTORY_UPDATE_DROP`. Also:
  - `W.historyTime` backs `C_LootHistory.GetLootHistoryTime()`;
  - `Enum.EncounterLootDropRollState` with the values above.

**Matching algorithm** (the design leaves the details here; write it as specified):

```
on LOOT_HISTORY_UPDATE_DROP(enc, key):
  drop the event if enc or key is secret or not a number
  info = C_LootHistory.GetSortedInfoForDrop(enc, key); drop if nil, secret, or info.itemHyperlink is not a string
  card = byDropKey[enc..":"..key]
  if not card:
    candidates = cards with rollID, no dropKey, status "live", same link (exact string; else same itemID)
    if #candidates > 1: prefer those whose mine matches info.playerRollState (mapped), then the oldest
    card = candidates[1]
    if not card:
      if info.winner or info.allPassed then return end          -- decided before we saw it
      if duration > 0 and (historyTime - info.startTime) >= info.duration then return end  -- stale
      card = new card without rollID from the link (over = true)
    attach enc/key to card
  update picks from info.rollInfos (key by playerGUID; skip secret entries)
  if not decided and (info.winner or info.allPassed): status = "decided", winner = info.winner.playerGUID, decidedAt = GetTime(), fire CARD_DECIDED once
  fire CARD_CHANGED(card, changes)   -- changes.picks = { [guid] = "state"|"roll" } for what changed
```

When `START_LOOT_ROLL` arrives for a link that already has an unmatched history-only card (history came first), the roll joins that card instead of making a new one. A live card with no decision becomes `status = "ended"` 5 s after `TimeLeft` reaches 0, and fires `CARD_DECIDED`.

- [ ] **Step 1: Write the failing tests** (`test_history_drops.lua`):
  - "the history attaches to its roll and fills every pick" (rows in party order with states).
  - "every history state maps" (NeedOffSpec → need, NoRoll → wait).
  - "a member missing from the history is out".
  - "numbers arrive: changes.picks marks them 'roll'".
  - "a winner decides the card once" (`CARD_DECIDED` count stays 1 after another update).
  - "everyone passed decides without a winner".
  - "the player's row: history first, then the optimistic pick".
  - **Review focus 2:** "two copies of one item match two cards": two `addRoll` calls with the same link; pick greed on the second; the first drop has `playerRollState` Greed and lands on the second card.
  - **Review focus 1:** "history first, roll second: one card".
  - "a fresh drop without a roll for the player gets a card without buttons" (`AwaitsMe == false`).
  - "drops decided before Tutti saw them are ignored", and "stale drops are ignored".
  - **Review focus 5:** "secret or missing history is ignored": fire with `T.secret(5)`; `GetSortedInfoForDrop` returns nil; a `rollInfos` entry with a secret GUID is skipped; no error, card unchanged.
  - "a roll with no decision ends 5 s after its time": `W.advance(66)` → `status == "ended"`.
  - "a member who leaves keeps their row from the history".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement it in `Core/Rolls.lua`.**
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: the group's picks from the loot history"`).

### Task 6: Blizzard's roll popups

**Files:**
- Create: `Core/Popups.lua`
- Modify: `tests/fake_wow.lua` (`GameEvent`), `Tutti.toc`
- Test: `tests/test_popups.lua`

**Interfaces:**
- Produces:
  - `ns.Popups.Apply()` runs on `DB_READY` and on `SETTING_CHANGED("rollInTutti")`.
  - `ns.Popups.Suppressed() -> bool`
  - `ns.Popups.ReloadNeeded() -> bool`: true when the setting is off but the popups were already switched off this session.
  - Message `"POPUPS_CHANGED"`.
- Fake client: `G.GameEvent = { UnregisterInternalEvent = fn }`, recording into `W.unregistered`. `opts.noGameEvent` leaves `GameEvent` out.

- [ ] **Step 1: Write the failing tests** (`test_popups.lua`):
  - "on at load: START_LOOT_ROLL is unregistered once": `W.unregistered` is `{"START_LOOT_ROLL"}` after login and after a second `Apply`.
  - "off at load: nothing unregistered".
  - "on later: unregistered at once".
  - "off later: ReloadNeeded".
  - "no GameEvent: no error, Suppressed false".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement it.** Call `GameEvent.UnregisterInternalEvent("START_LOOT_ROLL")` through `pcall`, only when it is a function. Never call `GameEvent.RegisterInternalEvent`.
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: switch Blizzard's roll popups off"`).

### Task 7: Session history

**Files:**
- Create: `Core/History.lua`
- Modify: `Tutti.toc`, `tests/fake_wow.lua` (`GetInstanceInfo`, `GetRealZoneText`, `time`)
- Test: `tests/test_history.lua`

**Interfaces:**
- Consumes: `"CARD_DECIDED"`, `ns.Rolls.Rows`.
- Produces:
  - `ns.History.Entries() -> { entry, ... }`, newest first, at most 100.
  - `entry = { link, name, icon, quality, place, at, winner|nil, allPassed, ended, rows }`
    - `at` is `time()`.
    - `winner = { name, class, state, roll }`.
    - `rows` are copies of `Rows()`.
  - `ns.History.Age(entry, now) -> "now"|"<n>m"|"<n>h"` (under 60 s is "now").
  - Message `"HISTORY_CHANGED"`.
  - Stored in `TuttiDB.recent`.
  - Cleared on `PLAYER_ENTERING_WORLD(isInitialLogin = true)`, kept on reload.
  - `place`: the instance name from `GetInstanceInfo()` when in an instance, else `GetRealZoneText()`.
  - Demo cards (`card.demo`) are recorded too, marked `demo = true`, and dropped on the next login.

- [ ] **Step 1: Write the failing tests:**
  - "a decided card becomes an entry with every row".
  - "newest first, capped at 100".
  - "kept on /reload, cleared at login".
  - "ages".
  - "everyone passed and ended entries".
  - "place is the instance name, else the zone".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: the session's results"`).

### Task 8: NaowhForever BiS badge

**Files:**
- Create: `Core/Integrations.lua`
- Modify: `Tutti.toc`
- Test: `tests/test_integrations.lua` (stubs `G.NaowhForever` in `opts.setup`)

**Interfaces:**
- Produces `ns.BiS.Badge(link) -> nil | { text, star, r, g, b }`.
- Rule (from `NaowhForever_BiS/BiS/View/RollBadge.lua`):
  - `NF.BiS.Alerts.On()` and `NF.BiS.Settings.Get("bisAlertBadge")` must both be true.
  - `rank = NF.BiS.Alerts.Rank(link)`, and `NF.BiS.Alerts.Wanted(rank)` must be true.
  - Text: rank 1 "BiS", rank 2 "2nd pick", rank n "#n pick".
  - `star = rank <= 3`.
  - Colour: `NF.Shared.Parts.RankColor(rank)` (fields r, g, b) when reachable, else #ffd100.
  - Every call is wrapped in `pcall` with type checks.

- [ ] **Step 1: Write the failing tests:**
  - "no NaowhForever: nil".
  - "alerts off or badge setting off: nil".
  - "rank 1 BiS with star, 2 '2nd pick' with star, 5 '#5 pick' without".
  - "Wanted false: nil".
  - "an erroring NaowhForever is ignored".
  - "rank colour, else gold".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: NaowhForever BiS badge"`).

### Task 9: Widgets and effects

**Files:**
- Create: `UI/Widgets.lua` (from Sotto), `UI/Fx.lua`
- Modify: `Tutti.toc`
- Test: `tests/test_widgets.lua`, `tests/test_fx.lua`

**Interfaces:**
- Produces Sotto's `ns.W` API with `W.MEDIA = "Interface\\AddOns\\Tutti\\Media\\"`:
  - drawing and controls: `Paint`, `Pixel`, `Fill`, `Hair`, `Outline`, `Border`, `Text`, `SetTextColor`, `Icon`, `SetIconColor`, `Shadow`;
  - `Tip`, `HideTip`, `IconButton`, `Pill`, `Switch`, `Segmented`, `Dropdown`, `Slider`, `Menu`.
- Plus:
  - `W.ClassIcon(tex, classFile)`: the atlas `classicon-<class>` when `C_Texture.GetAtlasInfo` knows it, else `CLASS_ICON_TCOORDS`.
  - `W.ItemIcon(parent, size) -> frame`, with `frame.icon` and `frame:SetItem(texture, quality)`. The 1 px inner edge uses `Theme.QualityEdge`.
  - `W.RollButton(parent, kind, onClick) -> button`, with `kind` one of `"need"|"greed"|"transmog"|"pass"`.
    - 23 px high, glyph 14 px in the pick colour, label 12 px, white 6 % fill with a 10 % hairline.
    - Hover: 10 % fill and a 70 % hairline in the pick colour.
    - Press: scale 0.95 and a 20 % fill.
    - `button:SetAllowed(bool)`: when not allowed, alpha 0.38, a faint glyph, and clicks ignored.
- `ns.Fx`:
  - `Tween(seconds, onStep(t), onDone) -> handle` (ease-out cubic), `handle:Cancel()`
  - `Spin(fs, final, seconds)`: random 1–100 every frame, then `final`, then a 1.5 → 1 scale bump in 0.35 s.
  - `Wash(tex, seconds)`: width 0 → full.
  - `Pop(frame, delay, seconds)`: scale 0 → 1.45 → 1.
  - `Glow(ring, times)`
  - `Shine(band, width)`
  - `FadeIn(region, seconds)`
  - `Rise(frame)`: +8 px and alpha 0 → 1 in 0.35 s.
  - `Sink(frame, onDone)`: alpha → 0 and −6 px in 0.55 s.
  - All of them are driven by one OnUpdate frame through `Tween`.

- [ ] **Step 1: Write the failing tests:**
  - Copy Sotto's `test_widgets.lua`.
  - "roll button: not allowed is 0.38 alpha and ignores clicks".
  - "item icon edge is the quality edge colour".
  - "ClassIcon uses the atlas when it exists".
  - `test_fx.lua`:
    - "Tween reaches 1 after its time and calls done once".
    - "Spin lands on the final number after 0.75 s".
    - "Sink fades out and calls done after 0.55 s".
    - "Cancel stops a tween".
- [ ] **Step 2: Run the files.** Expected: FAIL.
- [ ] **Step 3: Implement them.**
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: widgets and effects"`).

### Task 10: The card

**Files:**
- Create: `UI/Card.lua`
- Modify: `Tutti.toc`
- Test: `tests/test_card.lua`

**Interfaces:**
- Consumes:
  - `ns.Rolls` (`Rows`, `TimeLeft`, `AwaitsMe`, `Pick`), `ns.BiS.Badge`, `ns.W`, `ns.Fx`, `ns.Theme`;
  - the card fields from Tasks 4 and 5.
- Produces:
  - `ns.Card.Acquire(parent) -> view`, `ns.Card.Release(view)`
  - `view:Bind(card)`, `view:Update(changes)`, `view:Height() -> px`
  - `view:SetFolded(bool)`: folded is the 26 px line, "icon name → winner Need 19".
  - `view:Tick()`: refreshes the countdown text and bar; the window calls it each second.
  - `ns.Card.NewRow(parent) -> rowView` with `rowView:Set(row, opts)`, where `opts = { decided = bool, height = 21|19 }`. This is the row painter Recent rolls reuses.
- A card that `AwaitsMe` gets a 2 px accent edge down its left side (the mockup's `.card.yours::before`).
- Heights (px):
  - whole card = 9 + 34 + 16 + (31 if `AwaitsMe`) + (16 if `AwaitsMe` and not `canNeed`) + 21 × rows + (22 for a raid summary line) + 7.
  - folded line = 26.
- Subtitle texts:
  - live: "<label> · ilvl <n>", or "<label>" when the level is unknown, with the right side "<s>s"; when `AwaitsMe`, the right side is "Your pick · <s>s" with "Your pick" in the accent.
  - decided with a winner: "<First> won · <Need|Greed|Transmog> <roll>", with the name in its class colour; "You won · …" with "You won" in the accent when the winner is the player.
  - everyone passed: "Everyone passed".
  - ended: "Roll ended".
- Reason line: "Need: <reason>", in muted text.
- Rows:
  - `out`: "not in this roll", alpha 0.45, spanning the pick and roll columns;
  - `pass`: alpha 0.55;
  - the losers of a decided card: alpha 0.42;
  - the player's row: a 3.5 % white wash and a "YOU" tag.
- Raid (`ns.Group.IsRaid()`): rows only for need, greed and transmog, plus the player. Then a summary line "<n> passed · <m> choosing", leaving out a zero part. Clicking it lists the rest.
- Effects:
  - a newly arrived pick fades in;
  - a newly arrived number spins;
  - on `changes.decided` the winner's wash sweeps and the crown pops;
  - when the player won, the icon ring glows twice and the shine crosses once.
- Icon and name:
  - hover: `GameTooltip:SetLootRollItem(rollID)` while the roll is active, else `SetHyperlink(link)`;
  - a click with a modifier: `HandleModifiedItemClick(link)`.
- The badge comes from `ns.BiS.Badge(link)` and sits after "ilvl n".

- [ ] **Step 1: Write the failing tests** (`test_card.lua`, driving real cards through `W.addRoll` / `W.setDrop`):
  - "awaiting the player: three buttons, five rows in party order, height 218 with the reason line". This is the mockup's Dualblade: `canNeed = false`. The height is 9 + 34 + 16 + 31 + 16 + 105 + 7.
  - "picks show glyph and word in the pick colour; wait shows dots and 'choosing'".
  - "the player's row has the YOU tag".
  - "clicking Need picks need; a disallowed Need ignores the click and shows 'Need: <reason>'".
  - "transmog replaces greed".
  - "BiS badge text in the subtitle".
  - "winner: wash shown, crown shown, number in the accent, losers at 0.42, subtitle 'Orlen won · Need 19'".
  - "the player wins: 'You won · Need 87', glow and shine started".
  - "everyone passed: no crown".
  - "raid: only need/greed rows plus the player, then '13 passed · 2 choosing'; clicking lists them".
  - "folded line text and 26 px".
  - "tooltip on hover, HandleModifiedItemClick on shift-click".
  - "a new number calls Fx.Spin with the final value".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement `UI/Card.lua`.** Match the mockup's CSS (`.card`, `.ihead`, `.is`, `.timer`, `.btns`, `.why`, `.pr`, `.ch`, `.rn`, `.sum`, `.result`). Pool row frames.
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: the item card"`).

### Task 11: The window

**Files:**
- Create: `UI/Window.lua`
- Modify: `Tutti.toc`
- Test: `tests/test_window.lua`

**Interfaces:**
- Consumes: `ns.Card`, `ns.Rolls` messages, `ns.Get` / `ns.Set`, `ns.Fx`, `ns.Popups`.
- Produces:
  - Global frame `TuttiFrame`, parented to `UIParent`, strata `"HIGH"`, clamped, movable by the header.
  - `ns.UI.Open(view)` / `ns.UI.Toggle(view)`, with `view` one of `"rolls"|"recent"|"settings"`.
  - `ns.UI.Close()`, `ns.UI.View() -> string`, `ns.UI.Relayout()`.
  - `ns.UI.RegisterView(name, builder)` for Task 12. A builder returns a frame with `:Refresh()` and `:Height()`.
- Header (32 px):
  - lead: the mark, or the back arrow in Recent and Settings;
  - title: "Loot rolls", "Recent rolls" or "Settings";
  - a count pill with the number of live cards;
  - then "closes in <n>s" or "kept open";
  - clock, gear and close buttons;
  - a 1 px accent line at the bottom that runs down with the countdown.
- Behaviour:
  - `CARD_ADDED` opens the "rolls" view, plays `Rise` when the window was hidden, and appends the card.
  - Cards stack in arrival order, with folded lines under a "DONE" section label. The rolls view and the Done list sit in a scroll frame once the window height would pass 70 % of `UIParent:GetHeight()`.
  - **Fold:** 4 s after `decidedAt`, a decided card folds while at least one other card is unfolded.
  - **Close:**
    - When every card is decided or ended and `closeAfter > 0`, count down `closeAfter` s. The mouse over the window pauses it; leaving resumes it.
    - At 0: `Sink`, hide, `ns.Rolls.ForgetDecided()`.
    - A new card cancels the countdown.
  - The close button is hidden while any card `AwaitsMe`.
  - **Sound:** the chime plays (`PlaySoundFile(W.MEDIA.."Sounds\\chime.ogg", "Master")`) on `CARD_DECIDED` when the winner is the player and `sound == "chime"`.
  - **Position:** saved on drag stop as `TOPLEFT` x/y in `ns.DB.window`. `SetScale(ns.Get("scale"))`.
- Polestar, optional: while `TuttiFrame` and `PolestarLootNeeds` both show, re-anchor `PolestarLootNeeds` to `TuttiFrame`'s BOTTOMLEFT, 0, −4, using a `hooksecurefunc` on its `Show`. Record the decision in `docs/ledger.md` either way.

- [ ] **Step 1: Write the failing tests:**
  - "a new roll opens the window at TOPLEFT 372/−226".
  - "cards stack in arrival order and the pill counts live cards".
  - "a decided card folds after 4 s while another is open; the last stays".
  - "closing: 'closes in 10s', hidden after 10 s, cards forgotten".
  - "hover pauses, leave resumes".
  - "closeAfter 0 never closes".
  - **Review focus 4:** "a new roll cancels the countdown".
  - **Review focus 4:** "a new roll leaves Recent or Settings".
  - "the close button hides while a card awaits the player".
  - "dragging saves the position".
  - "scale applies".
  - "many cards: height capped at 70 % and scrolling".
  - "the chime plays once when the player wins; never with sound none".
- [ ] **Step 2: Run the file.** Expected: FAIL.
- [ ] **Step 3: Implement it** (`.win`, `.hd`, `.sec` and `.result` in the mockup's CSS).
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: the window"`).

### Task 12: Recent rolls, settings, ways in and the demo

**Files:**
- Create: `UI/Recent.lua`, `UI/Settings.lua`, `UI/Launcher.lua`, `UI/Demo.lua`
- Modify: `Tutti.toc`
- Test: `tests/test_recent.lua`, `tests/test_settings.lua`, `tests/test_launcher.lua`, `tests/test_demo.lua`

**Interfaces:**
- Consumes: `ns.UI.RegisterView`, `ns.History`, `ns.Popups.ReloadNeeded`, `ns.W` controls, and `ns.Card.NewRow` (Task 10) for the rows of an opened line.
- Produces:
  - `ns.Demo.Start()`
  - the global functions `Tutti_OnAddonCompartmentClick`, `Tutti_OnAddonCompartmentEnter`, `Tutti_OnAddonCompartmentLeave`
  - `SLASH_TUTTI1 = "/tutti"`
- **Recent:**
  - Rows group under a section label "<place> · today".
  - Each line (36 px): icon 26, name, then "<First> · Need 87", "You · Need 87" (in the accent), or "Everyone passed" / "Roll ended", and the age on the right.
  - Clicking a line opens its rows below it (19 px rows, indented 44 px); a second click closes them.
  - Footer: "Kept for this session · /tutti opens this list".
- **Settings** (the approved rows):
  - "Roll in Tutti", with the line "Need, Greed and Pass on each card; Blizzard's roll popups stay hidden". When `ReloadNeeded()`, the line becomes "Blizzard's popups return after a reload" with a "Reload" button (`C_UI.Reload` or `ReloadUI`).
  - "Close after the last roll": dropdown "5 seconds", "10 seconds", "20 seconds", "30 seconds", "Never".
  - "Sound" (under "WHEN YOU WIN"): "Soft chime" or "None".
  - "Accent": Class colour / EllesmereUI.
  - "Size": 80–130 % in steps of 5.
- **Ways in:**
  - A compartment click toggles Recent rolls; the tooltip reads "Tutti" and "Click: recent rolls".
  - `/tutti` toggles Recent, `/tutti settings` opens Settings, `/tutti demo` runs the demo.
- **Demo:** the mockup's "Play a boss drop" with the player's real group when grouped, else made-up names. It injects `demo = true` cards, which never call `RollOnLoot`, and follows the mockup's `PLAY` timeline.

- [ ] **Step 1: Write the failing tests:**
  - Recent: "lines newest first under their place", "'You · Need 87' in the accent", "click opens the picks, second click closes", "footer text".
  - Settings: "the five rows", "Roll in Tutti off shows the reload hint and button", "close-after choices", "the size slider sets scale".
  - Launcher: "the compartment toggles Recent", "/tutti, /tutti settings, /tutti demo".
  - Demo: "the boss drop plays: Orlen wins the axe, the player the gloves, RollOnLoot never called, the window closes 10 s after".
- [ ] **Step 2: Run the files.** Expected: FAIL.
- [ ] **Step 3: Implement them** (`.hl`, `.hx`, `.hint`, `.settings`, `.row` in the mockup's CSS).
- [ ] **Step 4: Run all tests.** Expected: PASS.
- [ ] **Step 5: Commit** (`"Tutti: recent rolls, settings, ways in, demo"`).

### Task 13: Visual check, docs, release setup

**Files:**
- Create: `tools/render_ui.lua`, `.github/workflows/tests.yml`, `.github/workflows/release.yml`, `docs/RELEASING.md`
- Modify: `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `docs/ledger.md`

- [ ] **Step 1: Adapt Sotto's `tools/render_ui.lua`** so it renders Tutti's frames from the fake client as HTML. Scenes: `pick`, `rolling`, `winner`, `youwon`, `closing`, `recent`, `settings`, `big` (the mockup's states). Use the mockup's backdrop and fonts from `docs/mockup/assets`, with media as PNG through `tools/tga2png.py`.
- [ ] **Step 2: Render every scene.** Put each next to the mockup in the same state (headless Chrome screenshots, 2× close-up) and fix every visible mismatch in size, spacing, colour or text. Log each fix in `docs/ledger.md`.
- [ ] **Step 3: Copy Sotto's workflows** (tests on push, the BigWigs packager on tag) and `docs/RELEASING.md`, adapted to Tutti. The CurseForge project is created only when the user asks.
- [ ] **Step 4: Finish the docs.**
  - `README.md`: features, settings, `/tutti`, compatibility "WoW Forever".
  - `CHANGELOG.md`: the 1.0.0 entries.
  - `CLAUDE.md`: final.
  - `docs/ledger.md`: every call made, plus an in-game checklist (the design's "Risks to check in game").
- [ ] **Step 5: Run `luajit tests/run.lua && luajit tests/syntax.lua && python3 -I tests/test_media.py`.** Expected: all pass.
- [ ] **Step 6: Commit** (`"Tutti: visual check, docs and release setup"`).
