# Tutti: design

Status: draft for approval, 2026-11-13. Public author: creazy231.

- **Approved look:** `docs/mockup/tutti-mockup.html`. Serve `docs/mockup` over http, for example `python3 -m http.server`; the font needs that. The built window stays pixel-close to it.
- **Approved by the user:** "looks awesome!".
- **Layouts compared:** `docs/mockup/layouts-compared.html`. The user picked layout A, "Item cards".
- **Private files:** the mockup uses a private game screenshot and EllesmereUI's licensed font. `docs/` is never shipped.

## Why

The user plays WoW Forever as a feral druid, in dungeons with a group. When an item drops, chat makes it hard to see who picked Need, Greed or Pass, and who won. The lines "(Loot): Brisé Tidewater has selected Greed for: [Guardian's Dualblade]" scroll past among everything else in chat.

Blizzard has a "Loot Rolls" window with this data, but Forever never opens it by itself: `Blizzard_FrameXML/Camelot/LootHistory.lua` makes `ShouldAutoOpen` return false. Tutti puts the same facts in front of the player for every roll, readable at a glance. The player also rolls from the same window.

The name: in music, "tutti" is the passage where the whole orchestra plays together. Here it is the whole group's rolls in one window. It is a sibling to the user's addon Sotto, and the name is free on CurseForge, Wago, WoWInterface and GitHub (checked 2026-11-13).

## Goals

- Opens by itself whenever a roll starts in the group.
- For each item it lists every group member with:
  - their pick: Need, Greed, Pass, or still choosing;
  - their roll number once it arrives;
  - a highlight and an animation for the winner.
- The player rolls Need, Greed or Pass in Tutti, and Blizzard's roll popups stay hidden.
- Sotto's look: EllesmereUI as Polestar draws it. EllesmereUI is optional.
- WoW Forever first.

## Non-goals (for now)

- **Other clients:**
  - Retail uses the same loot-history API and could follow later with little work.
  - The Classic clients use the older `C_LootHistory.GetItem` / `GetPlayerInfo` API, so they would be separate work.
- **Loot systems:** master loot, loot councils, soft reserves, DKP, auto-rolling.
- **Chat:** reading or parsing chat lines.
- **Themes:** only the one look, as with Sotto.
- **Publishing:** the repo is prepared like Sotto's. A CurseForge release happens only when the user asks.

## Anti-goals

- The player missing or mis-clicking a roll because of Tutti.
- Taint: anything that breaks Blizzard's UI, in or out of combat.
- A busy window. If the player has to decode anything, Tutti has failed its purpose.

## Constraints

- **Client:** WoW Forever 1.60.1 (game type `camelot`, TOC 16001) on the 12.1 engine. Blizzard's code is at github.com/Gethe/wow-ui-source, branch `forever`.
- **Frames and hooks:**
  - plain frames only, no secure templates;
  - hooks only through `hooksecurefunc`;
  - never write to Blizzard globals or Blizzard frames' fields.
- **EllesmereUI:** only through its skin API (`EllesmereUI.RegisterSkin` getters), the way Sotto's `Core/Theme.lua` does it. Never touch EllesmereUI internals or `EllesmereUIDB`.
- **Author:** creazy231 in the TOC, README and LICENSE, never a real name.

## Approaches considered

1. **A standalone addon built like Sotto. Chosen by the user.**
   - It draws its own window.
   - The loot history supplies the group's picks; the roll functions take the player's own pick.
   - It switches Blizzard's popups off the way ElvUI does.
   - It reuses Sotto's tested pieces: theme and EllesmereUI hookup, widgets, the offline test harness, the release setup.
   - It works with or without EllesmereUI.
2. **An EllesmereUI plugin** (`EllesmereUI.RegisterPlugin`). Its settings would sit in EllesmereUI's own panel. Rejected: Tutti would then work only for people who run EllesmereUI.
3. **A party list attached to Blizzard's roll popups.** Least work, and NaowhForever's BiS badge would stay where it is. Rejected: it can't produce the approved window (one window, folding, closing on its own, history).

For data, the loot history beats the chat lines:
- chat lines depend on the client language;
- on the 12.x engine they become secret during chat lockdown (`SecretInChatMessagingLockdown`);
- the `C_LootHistory` functions only take `SecretArguments = "AllowedWhenUntainted"`, and none of their results are marked secret in Forever's API docs.

## What the player sees

Everything below was shown in the approved mockup unless it is marked *(not in the mockup)*. Points the user decided are marked *(user)*. Everything else is my call, approved together with the mockup.

### The window

- **Layout and opening:**
  - Layout "Item cards" *(user)*: one card per item, with the group listed under it.
  - It opens on its own as soon as a roll starts.
  - Cards stay in drop order; new cards go at the bottom.
- **Card:**
  - item icon with a 1 px quality-coloured edge;
  - name in the quality colour;
  - under it "Two-Hand Axe · ilvl 33";
  - on the right, the seconds left;
  - under that, a 2 px countdown bar.
- **Rows:**
  - Rows keep the group's order (the same order as the party frames) and never move.
  - Each row has: class icon, first name in its class colour (with a small "YOU" tag on your own row), the pick as icon plus word, and the roll number.
- **Picks:**
  - Need: green die.
  - Greed: amber coin.
  - Pass: grey slashed circle, row dimmed.
  - Still choosing: three pulsing dots.
- **Numbers:** they spin in for about 0.75 s when they arrive. Forever usually sends them all at once at the end, but Tutti handles them arriving one at a time just as well.

### Your pick

- **Cards waiting on you:**
  - They get an orange accent edge, and "Your pick · 53s" in the subtitle.
  - They show three buttons: Need, Greed, Pass.
  - When the game offers Transmog instead of Greed, the Greed button becomes Transmog, in purple, just as Blizzard's popup does *(not in the mockup)*.
- **Need not allowed:** the button is greyed out, with the game's reason under the buttons, e.g. "Need: your class can't use this".
- **After you click:** the buttons go away and your row shows the pick at once.
- **Close button:** hidden while a card waits on your pick. Blizzard's popups can't be dismissed without a choice either, and this prevents missed rolls *(not in the mockup)*.
- **Soulbound items:** they still get Blizzard's own "this item will bind to you" confirmation. Tutti never confirms by itself.
- **Item icon and name:** hover shows the item tooltip. Shift-click puts the link in chat, and Ctrl-click opens the dressing room, as usual *(not in the mockup)*.
- **BiS badge:** if NaowhForever_BiS ranks the item for you, its star badge sits in the card's subtitle. See Integrations.

### The winner

- **Winner row:**
  - The winner's row fills with an accent wash from the left, with a 2 px accent edge.
  - A crown pops in.
  - The number turns accent-coloured.
  - The other rows fade back.
- **Subtitle:** it becomes "Orlen won · Need 19", with the name in its class colour.
- **When you win:**
  - The subtitle reads "You won · Need 87".
  - The icon glows twice, and a light sweep crosses the card once.
  - The "Sound when you win" setting plays once.
- **Everyone passed:** the subtitle says "Everyone passed" and there is no crown *(not in the mockup; the history shows the case)*.
- **Ties:** both numbers show. The crown goes to whoever the game names the winner *(not in the mockup)*.

### Done and closing

- **Folding:**
  - A decided card stays whole for about 4 s while its animation plays.
  - If another card is still open, it then folds into one line under a "Done" label: icon, name, arrow, winner, "Need 19".
  - The last decided card stays whole until the window closes.
- **Closing on its own** *(user)*:
  - About 10 seconds after the last roll is decided, the window closes itself.
  - A 1 px accent line under the header runs down, with "closes in 7s".
  - While the mouse is over the window it waits ("kept open") and continues when the mouse leaves.
  - A new roll cancels the countdown.
  - On close, the Done lines go; they live on in Recent rolls.

### Recent rolls

The session's results are one click away *(user)*:
- through the clock in the header;
- through the addon compartment (the minimap's addon menu);
- through `/tutti`.

What it shows:
- It is the same window with a back arrow and the title "Recent rolls".
- It is grouped by instance or zone and day ("City of Dalaran · today").
- Each line has: icon, item name, winner (or "Everyone passed") with pick and number, and the age ("6m").
- Clicking a line opens everyone's picks for that item.
- The footer reads "Kept for this session · /tutti opens this list".

How long it keeps results:
- It holds up to 100 results.
- They survive `/reload` and are cleared at login.

When a roll starts while Recent rolls or Settings is showing, the window switches to the rolls.

### Settings (gear in the header; changes apply at once)

- **Roll in Tutti** (on): Need, Greed and Pass on each card, with Blizzard's roll popups hidden.
  - Turning it off brings Blizzard's popups back after a reload. The row says so and offers a Reload button.
  - Turning it on takes effect at once.
- **Close after the last roll:** 10 seconds. The choices are 5, 10, 20, 30 seconds and Never.
- **Sound when you win:** Soft chime or None.
- **Accent:** Class colour (lifted until it reads at 4.5:1, as in Sotto) or EllesmereUI's accent.
- **Size:** 80–130 %, default 100 %.

Position: drag the header. It is saved and kept on screen.

### Bigger groups

In a raid, a card lists only the members who picked Need or Greed, plus you. Everyone else folds into one line, "13 passed · 2 choosing", which opens to list them. A long card list scrolls inside the window once the window would pass about 70 % of the screen height *(the scrolling is not in the mockup)*.

### Other cases *(not in the mockup)*

- **A member who isn't in the roll** (out of range or dead): their row shows "not in this roll", dimmed, so the whole group stays listed.
- **A roll you're not part of:** if the loot history shows a group roll you got no roll for, the card still appears, without buttons.
- **Group loot is off** (free-for-all, master loot, personal loot): nothing opens.

## Look

The tokens are the Sotto / Polestar "EllesmereUI" scheme, read live from EllesmereUI when it is there. The mockup's CSS is the exact reference.

- **Window:**
  - EllesmereUI's panel colour (#141414 at 93 %);
  - a 1 px white-10 % hairline inside, a 1 px black edge outside, and a soft drop shadow;
  - 300 px wide.
- **Header:**
  - 32 px high, with the panel's light top gradient and a hairline under it;
  - a die mark in the accent and "Loot rolls" in 13.5 px bold;
  - a count pill with the number of open rolls;
  - clock, gear and close buttons, 22 px with 14 px icons.
- **Card:**
  - padding 9/10/7;
  - icon 34 px;
  - name 13.5 px bold;
  - subtitle 11 px muted (#a2a5a9);
  - countdown bar 2 px in the accent.
  - Buttons are 23 px high and share the width: a 14 px icon plus a 12 px label.
- **Rows:**
  - 21 px high, with a 15 px class icon and the name in 12.5 px bold;
  - the pick column is 64 px (13 px icon, 11.5 px word);
  - the roll column is 38 px, right-aligned, 13 px bold, tabular figures.
- **Colours:**
  - Need #6bd999, Greed #fabf4d, Pass #8d9096;
  - text #f8f8f8, #cacccf and #a2a5a9, plus #6f7277 for the faintest;
  - hairlines in white at 6 % and 10 %;
  - quality colours lifted to 4.5:1 for text (rare #2b8cff) with the original for the icon edge (rare #0070dd);
  - accent: class colour (druid #ff7d0a) or EllesmereUI's (#00cfff).
- **Font:** EllesmereUI's font (Expressway; bold names use "Expressway Bold" next to it), no outline, 1 px shadow. Without EllesmereUI: the game font.
- **Animations:**
  - number spin about 0.75 s, then a small landing bump;
  - winner wash sweep 0.7 s;
  - crown pop 0.5 s after 0.3 s;
  - window rises 8 px and fades in 0.35 s, and fades out 0.55 s;
  - a new pick fades in 0.35 s.
- **Class icons:** from the client, as in Sotto's rail. The mockup's icons are placeholders.

## How it works

### Events and APIs (Forever 1.60.1)

- **`START_LOOT_ROLL(rollID, rollTime, lootHandle)`:** a roll for the player.
  - `GetLootRollItemInfo(rollID)` returns texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired and canTransmog.
  - `GetLootRollItemLink(rollID)` gives the link.
  - `GetLootRollTimeLeft(rollID)` and `C_Loot.GetLootRollDuration(rollID)` give the time.
  - At login and reload, `GetActiveLootRollIDs()` lists the rolls still open.
- **`CANCEL_LOOT_ROLL(rollID)` and `CANCEL_ALL_LOOT_ROLLS`:** the player's part of a roll is over (picked or timed out). The card stays until the history decides it.
- **`LOOT_HISTORY_UPDATE_DROP(encounterID, lootListKey)` → `C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey)`:** the group's side.
  - `rollInfos`: every eligible member with name, GUID, class, isSelf, state (NeedMainSpec, NeedOffSpec, Transmog, Greed, NoRoll = still choosing, Pass), roll and isWinner.
  - Also `winner`, `currentLeader`, `isTied`, `allPassed`, `playerRollState`, `startTime` and `duration`.
  - NeedOffSpec shows as Need.
  - Blizzard's tooltip code in `Blizzard_FrameXML/Mainline/LootHistory.lua` shows how to read it, including its "skip rolls in a weird state" rule for several copies of one item.
- **`RollOnLoot(rollID, type)`:** 0 Pass, 1 Need, 2 Greed, 4 Transmog.
  - On a soulbound item the game fires `CONFIRM_LOOT_ROLL`, which stays with Blizzard (its dialog then calls `ConfirmLootRoll`).
- **`GROUP_ROSTER_UPDATE`:** keeps the group list and its order.

### Matching a roll to its loot-history drop

A roll (rollID) and a drop (encounterID, lootListKey) share the item link.

- Match each new roll to the unmatched drop with the same link whose `startTime` is closest to the roll's start.
- Several copies of one item in a single drop are matched in order: first roll to first drop.
- Until a match exists, the card shows the group list with everyone "choosing", so it never waits on the history.
- Drops already decided when Tutti loads (old encounters) are ignored.
- A drop with no matching roll for the player gets a card without buttons.

### Switching Blizzard's popups off

- With "Roll in Tutti" on, Tutti calls `GameEvent.UnregisterInternalEvent("START_LOOT_ROLL")` once at load.
  - That function is defined in `Blizzard_Game/Shared/EventRouting.lua` and called by ElvUI's `E:UnregisterGameEvent`.
  - Blizzard's router then never calls `GroupLootContainer_AddRoll`.
  - Guard: if `GameEvent` or the function is missing, Blizzard's popups stay and Tutti still works next to them.
- Never re-register Blizzard's handler from addon code: it would then run tainted. Bringing the popups back takes a reload.
- **Known gap:** after a `/reload` in the middle of a roll, Blizzard's `PLAYER_ENTERING_WORLD` handler calls `GroupLootContainer_RefreshRolls()` and shows popups for the rolls still open, next to Tutti's cards. Accept that rare case. Do not hide Blizzard's frames from addon code.
- With the popups hidden, EllesmereUI's loot-roll reskin and its "Group Loot" mover have nothing to act on. That is harmless.

### Integrations

- **EllesmereUI:**
  - accent, panel colour and font come through `RegisterSkin` getters, as in Sotto's `Core/Theme.lua`;
  - without EllesmereUI the mockup's values apply, with the game font.
- **NaowhForever_BiS** (optional; another addon's internals, so every call is guarded with type checks and `pcall`):
  - Show the badge when `NaowhForever.BiS.Alerts.On()` and `NaowhForever.BiS.Settings.Get("bisAlertBadge")` are true and `Alerts.Wanted(rank)` holds for `rank = Alerts.Rank(link)`. This is the same rule as its `BiS/View/RollBadge.lua`, which badges Blizzard's popups.
  - Words: rank 1 "BiS", rank 2 "2nd pick", otherwise "#n pick".
  - Star for ranks up to 3.
  - Colour: its rank colour (`NaowhForever.Shared.Parts.RankColor`) when reachable, otherwise the mockup's gold #ffd100.
- **Polestar** (optional, builder's call): Polestar's "a party member still needs this quest item" note (frame `PolestarLootNeeds`) anchors under Blizzard's popups. With those hidden it falls back to the top of the screen. Tutti may anchor it under its window when both show.

### Saved data (`TuttiDB`, per account)

- the settings;
- the window position;
- the session's results, cleared at `PLAYER_ENTERING_WORLD` with `isInitialLogin`.

Each result holds:
- the item link;
- the instance or zone name;
- the time;
- the winner (name, class, pick, roll) or `allPassed`;
- every member's pick and roll, for the open-line view.

### Ways in

- the header's clock;
- the addon compartment (TOC `AddonCompartmentFunc`, as Sotto does it; a click opens Recent rolls);
- `/tutti` (Recent rolls) and `/tutti settings`.

No minimap button.

`/tutti demo` plays the mockup's boss drop in game, with no real rolls. It uses your group's real names when you're grouped, otherwise made-up ones. It lets you check the window's look and animations without waiting for loot. *(My call, added after approval.)*

## Testing

- **Offline, after every change:** LuaJIT tests on a fake client, as in Sotto (`tests/fake_wow.lua`, `tests/harness.lua`). The scripted sequences cover:
  - a two-item boss drop with staggered picks;
  - the history arriving late;
  - identical items;
  - everyone passed;
  - Transmog;
  - Need not allowed;
  - a roll the player isn't part of;
  - a member not in the roll;
  - a reload in the middle of a roll;
  - a raid of 20;
  - with and without NaowhForever;
  - with and without EllesmereUI;
  - every setting;
  - the history across reload versus login.

  Also a syntax check and a load test.
- **Visual:** a render tool like Sotto's `tools/render_ui.lua` draws what the fake client built as HTML, to put next to the mockup.
- **In game, by the user:** a short checklist with `/console taintLog 1`, covering what only the game can confirm (risks below).

## Risks to check in game

1. Is the loot-history drop there as soon as `START_LOOT_ROLL` fires? Tutti copes either way. This only decides how soon the picks fill in.
2. Does `rollInfos` include members who can't roll? If not, the "not in this roll" rows come from the group list.
3. Two copies of the same item in one drop: does the matching hold?
4. Rolls on trash during combat: nothing is expected to be secret, but this needs confirming.
5. Rolling a soulbound item from Tutti brings up Blizzard's bind confirmation.
6. A `/reload` in the middle of a roll (the known gap above).
7. The taint log stays clean after rolls, in and out of combat.

## Repo and release

- **Folder and repo:** `Interface/AddOns/Tutti`, a git repo set up like Sotto's:
  - repo-local identity creazy231 / 13473174+creazy231@users.noreply.github.com;
  - files: MIT LICENSE, README, CHANGELOG and CLAUDE.md;
  - `.pkgmeta` plus the BigWigs packager workflow, ready but unused.
  - The GitHub repo and the CurseForge project are created only when the user asks. `docs/` and `tests/` never ship.
- **TOC:**
  - `## Interface: 16001`;
  - Title Tutti, Author creazy231, `## Version: @project-version@`;
  - SavedVariables TuttiDB, OptionalDeps EllesmereUI and NaowhForever_BiS;
  - IconTexture and the compartment functions.

## Left to the builder

- module layout, frame pooling, and exact pixel offsets and curves (the mockup is the reference);
- the die mark and the other icons (drawn like Sotto's `tools/make_media.py`);
- the chime sound;
- how game words are localized (prefer Blizzard's global strings such as NEED, GREED, PASS and `LOOT_ROLL_INELIGIBLE_REASON*`, and the item type from the item info);
- first names versus full names when two members share a first name;
- the Polestar anchoring.
