-------------------------------------------------------------------------------
--  Tutti: the card model. A card is one item the group is rolling on. A card for the player's
--  own roll appears when the game starts it (START_LOOT_ROLL) or, after a /reload, when the game
--  still lists it (GetActiveLootRollIDs). It carries what the window needs: the item, what the
--  player may choose, the countdown and the player's pick. The group's side comes from the loot
--  history (LOOT_HISTORY_UPDATE_DROP): who chose what, the numbers, the winner.
--    ns.Rolls.Cards()              { card, ... } in arrival order; a new list on every call
--    ns.Rolls.Get(id)              a card by Tutti's own id
--    ns.Rolls.Pick(card, choice)   "need" | "greed" | "transmog" | "pass"; true when it was sent
--    ns.Rolls.TimeLeft(card)       seconds left, never below 0
--    ns.Rolls.AwaitsMe(card)       the player can still choose on this card
--    ns.Rolls.Rows(card)           one row per group member, in the group's order, then one per roller
--                                  the group no longer has (or could not name), in the history's order:
--                                  { guid, name, class, isPlayer, state, roll|nil, isWinner }
--                                  state: "need" (main or off spec) | "greed" | "transmog" | "pass" |
--                                  "wait" (still choosing) | "out" (not in the roll: the history has
--                                  the drop and not this member). Once a card is decided or ended nobody
--                                  is choosing: a "wait" reads "out". The player's row: what the history
--                                  says they chose, else the click they made (it shows at once), else
--                                  "wait" if the history lists them or the game gave them a roll, else
--                                  "out" once the card has the history.
--    ns.Rolls.Forget(card), ns.Rolls.ForgetDecided()
--  A card: id, rollID|nil, link, itemID, name, icon, quality, count, bop, label|nil, ilvl|nil,
--  canNeed, canGreed, canTransmog, reasonNeed|nil (text), startedAt (GetTime), duration (s),
--  mine|nil, pending|nil, over, history, tied, picks, status ("live"|"decided"|"ended"),
--  winner|nil (a GUID), allPassed, decidedAt|nil, demo|nil, and once the history has the drop:
--  encounterID, lootListKey, dropKey ("<encounterID>:<lootListKey>").
--  picks: [guid] = { state, roll|nil, name, class, isSelf, order } as the history lists them.
--  A bind confirmation: Need or Greed on a soulbound item first makes the game ask the player to
--  confirm (CONFIRM_LOOT_ROLL, Blizzard's own dialog; Tutti leaves it alone and never confirms).
--  The roll is not made until the dialog is accepted, so the pick waits as `pending` instead of
--  `mine`: the card awaits the player again and its buttons work meanwhile, and a cancelled dialog,
--  which fires nothing, leaves the card as it is. When the game takes the roll (CANCEL_LOOT_ROLL)
--  the pending pick becomes `mine`. If the time runs out while the dialog is open the game says
--  the same thing, so `mine` then shows a pick the game passed on; the loot history, which names
--  the player's real pick, corrects it.
--  The history and the rolls meet in a card, whichever comes first. A drop (encounterID, lootListKey)
--  joins a card that has a roll and no drop yet and shows the same item: the same link, else the same
--  item; among several, the one whose pick is the player's state in the drop, then the oldest. A drop
--  with no such card, still undecided and not out of time, makes a card of its own: no roll, `over`,
--  no buttons. When the player's roll starts later it joins that card instead of making a second one.
--  A card is decided when the history names a winner or says everyone passed. A card the history
--  never decides ends 5 seconds (ENDED_GRACE) after its time is up (status "ended"); a decision that
--  comes later still decides it, and CARD_DECIDED comes a second time for that card. A decided card is
--  never decided again. A drop key that a card has had is remembered after the card is forgotten, until
--  the game clears its history (LOOT_HISTORY_CLEAR_HISTORY): a drop whose card is gone is old news and
--  is ignored, so an old drop sent again never takes a new roll.
--  Messages:
--    "CARD_ADDED", card
--    "CARD_CHANGED", card, changes     changes: a set of item | mine | over | picks | decided
--                                      picks: [guid] = "state" | "roll", for the picks that are new or
--                                      changed: "state" for a new pick or another state, "roll" when
--                                      only the number is new or different. decided: this message
--                                      is the card's decision (or its end).
--    "CARD_DECIDED", card              a card's result: a decision, or the end of a roll nobody decided;
--                                      once more for a card that ended and is decided later
--    "CARD_REMOVED", card
--  Everything the game hands over passes ns.Clear (ns.IsSecret and a type check) before it is used.
-------------------------------------------------------------------------------
local _, ns = ...
local Rolls = {}
ns.Rolls = Rolls

local DEFAULT_DURATION = 60 -- seconds, when the game names no time for a roll, and for a card the history made
local ENDED_GRACE = 5 -- seconds after a roll's time that the game may still say how it went

-- RollOnLoot's types.
local ROLL_TYPE = { pass = 0, need = 1, greed = 2, transmog = 4 }
-- The choice a type names, for the types a confirmation can be about (Pass is never confirmed).
local CHOICE_OF = { [1] = "need", [2] = "greed", [4] = "transmog" }

-- Why Need can be refused, when the client has no text for it. Only reason 1 is known to read
-- like this; any other number gets the general sentence.
local REASON_FALLBACK = { [1] = "Your class may not roll need on this item." }
local REASON_ANY = "You can't roll Need on this item."

-- A pick in the loot history as a row's state: Enum.EncounterLootDropRollState (NeedMainSpec 0,
-- NeedOffSpec 1, Transmog 2, Greed 3, NoRoll 4, Pass 5).
local STATE_OF = { [0] = "need", [1] = "need", [2] = "transmog", [3] = "greed", [4] = "wait", [5] = "pass" }

local list = {}       -- the cards in arrival order
local byID = {}       -- Tutti's own id -> card
local byDropKey = {}  -- "<encounterID>:<lootListKey>" -> the card that has the drop
local knownDrops = {} -- every such key a card has had, kept after the card is forgotten
local lastID = 0

-------------------------------------------------------------------------------
--  Reading what the game says
-------------------------------------------------------------------------------
-- A value of the given type that the game gave in the clear, else nil (the guard of Core/Init.lua).
local clear = ns.Clear

-- A non-empty string the game gave in the clear, else nil.
local function text(value)
    value = clear(value, "string")
    if value == "" then return nil end
    return value
end

-- A yes/no from the game. Anything unreadable is a no: Need and Greed are only offered when the
-- game plainly says they are open, and Pass never depends on it.
local function yes(value)
    if ns.IsSecret(value) then return false end
    if type(value) == "number" then return value ~= 0 end
    return value == true
end

local function reasonText(code)
    return text(_G["LOOT_ROLL_INELIGIBLE_REASON" .. code]) or REASON_FALLBACK[code] or REASON_ANY
end

-- The roll's item and what the player may choose, or nil without a readable name.
local function readInfo(rollID)
    if type(GetLootRollItemInfo) ~= "function" then return nil end
    local texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, _, _, _, canTransmog =
        GetLootRollItemInfo(rollID)
    name = text(name)
    if not name then return nil end
    count = clear(count, "number")
    local needOK = yes(canNeed)
    local code = clear(reasonNeed, "number")
    return {
        name = name,
        icon = clear(texture, "number") or text(texture),
        count = (count and count >= 1) and count or 1,
        quality = clear(quality, "number"),
        bop = yes(bop),
        canNeed = needOK,
        canGreed = yes(canGreed),
        canTransmog = yes(canTransmog),
        reasonNeed = (not needOK and code and code > 0) and reasonText(code) or nil,
    }
end

-- A roll's time as (duration, elapsed), both in seconds. START_LOOT_ROLL names the time in
-- milliseconds and the roll is just starting. Otherwise (after a /reload, or an unreadable time)
-- the game says how long the roll lasts and how much of it is left.
local function timing(rollID, rollTime)
    local ms = clear(rollTime, "number")
    if ms and ms > 0 then return ms / 1000, 0 end
    ms = C_Loot and C_Loot.GetLootRollDuration and clear(C_Loot.GetLootRollDuration(rollID), "number")
    local duration = (ms and ms > 0) and ms / 1000 or DEFAULT_DURATION
    local leftMs = GetLootRollTimeLeft and clear(GetLootRollTimeLeft(rollID), "number")
    local elapsed = leftMs and math.min(math.max(duration - leftMs / 1000, 0), duration) or 0
    return duration, elapsed
end

-- A pick of the loot history as a row's state, nil when the game gave none or one this client
-- has no word for.
local function stateOf(value)
    value = clear(value, "number")
    return value and STATE_OF[value] or nil
end

-- What the client knows of the item a link names: its name, icon and quality. An item that is not
-- in the client's cache still has its name in the link and, as Forever writes a link, its quality in
-- the colour; the rest follows with GET_ITEM_INFO_RECEIVED. Any of the three may be nil.
local function itemFacts(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, icon, quality
    if type(get) == "function" then
        local n, _, q, _, _, _, _, _, _, texture = get(link)
        name, quality, icon = text(n), clear(q, "number"), clear(texture, "number") or text(texture)
    end
    return name or text(link:match("|h%[(.-)%]|h")), icon, quality or tonumber(link:match("^|cnIQ(%d)"))
end

-------------------------------------------------------------------------------
--  Cards
-------------------------------------------------------------------------------
local function changed(card, changes)
    ns.Fire("CARD_CHANGED", card, changes)
end

-- What a roll says: its item, what the player may choose and its countdown, as card fields. Nil
-- without a readable name.
local function readRoll(rollID, rollTime)
    local info = readInfo(rollID)
    if not info then return nil end
    local link = GetLootRollItemLink and text(GetLootRollItemLink(rollID)) or nil
    local duration, elapsed = timing(rollID, rollTime)
    local label, ilvl = ns.Items.Describe(link)
    return {
        rollID = rollID, link = link, itemID = ns.Items.ID(link),
        name = info.name, icon = info.icon, quality = info.quality, count = info.count, bop = info.bop,
        canNeed = info.canNeed, canGreed = info.canGreed, canTransmog = info.canTransmog,
        reasonNeed = info.reasonNeed, startedAt = GetTime() - elapsed, duration = duration,
        label = label, ilvl = ilvl,
    }
end

-- A card with `fields` (from a roll or a drop) on top of what every new card starts with. It is in
-- the list; the caller announces it.
local function newCard(fields)
    lastID = lastID + 1
    local card = {
        id = lastID, over = false, history = false, tied = false, picks = {}, status = "live", allPassed = false,
    }
    for key, value in pairs(fields) do card[key] = value end
    list[#list + 1] = card
    byID[card.id] = card
    return card
end

-- The cards that `wanted` accepts and that show the item a link names, oldest first: those with that
-- very link or, when there are none, those with that item.
local function showing(link, itemID, wanted)
    local same, item = {}, {}
    for _, card in ipairs(list) do
        if wanted(card) then
            if link and card.link == link then same[#same + 1] = card end
            if itemID and card.itemID == itemID then item[#item + 1] = card end
        end
    end
    return #same > 0 and same or item
end

-- A roll that already has a live card is the same roll: START_LOOT_ROLL and the rebuild after a
-- /reload can both name it.
local function hasLiveCard(rollID)
    for i = 1, #list do
        if list[i].rollID == rollID and list[i].status == "live" then return true end
    end
    return false
end

-- The game named a card's winner, or says everyone passed: the card is decided. A card that had ended
-- is decided too when the history gets to it late; CARD_DECIDED then comes a second time. The caller
-- announces the change and never decides a card that is decided already.
local function decide(card, winnerGUID, allPassed)
    card.status, card.winner, card.allPassed, card.decidedAt = "decided", winnerGUID, allPassed, GetTime()
    ns.Fire("CARD_DECIDED", card)
end

-- Nobody decided the card and ENDED_GRACE seconds have passed since its time ran out: it is over.
local function endCard(card)
    card.status, card.decidedAt = "ended", GetTime()
    ns.Fire("CARD_DECIDED", card)
    changed(card, { decided = true })
end

-- Looks at a card when its roll has been over for ENDED_GRACE seconds, and ends it if the history
-- has not decided it. The card's time can move (the player's roll may join a card the history made),
-- so each look reads the deadline again; a card that is gone or no longer live is left alone.
local function watch(card)
    local function look()
        if card.status ~= "live" or byID[card.id] ~= card then return end
        local left = card.startedAt + card.duration + ENDED_GRACE - GetTime()
        if left > 0.05 then ns.After(left, look) else endCard(card) end
    end
    ns.After(Rolls.TimeLeft(card) + ENDED_GRACE, look)
end

-- The player's roll for an item whose drop the history showed first: it joins the card the history
-- made, which gets what the roll knows (the buttons, the countdown, the roll's own name and icon)
-- and keeps what the history gave it.
local function join(card, roll)
    for key, value in pairs(roll) do card[key] = value end
    card.over, card.mine, card.pending = false, nil, nil
    changed(card, { item = true, over = true })
    watch(card)
end

local function add(rollID, rollTime)
    if hasLiveCard(rollID) then return end
    local roll = readRoll(rollID, rollTime)
    if not roll then return end
    local waiting = showing(roll.link, roll.itemID, function(card)
        return card.status == "live" and card.rollID == nil and card.dropKey ~= nil
    end)[1]
    if waiting then return join(waiting, roll) end
    local card = newCard(roll)
    ns.Fire("CARD_ADDED", card)
    watch(card)
end

-- The player's part of a roll is over (chosen, or out of time). The card stays live: the group may
-- still be rolling. A pick that waited for a bind confirmation is the player's now: the game took
-- the roll.
local function finish(card)
    if card.over then return end
    card.over = true
    local changes = { over = true }
    if card.pending then
        card.mine, card.pending = card.pending, nil
        changes.mine = true
    end
    changed(card, changes)
end

-- The game asks the player to confirm a roll (Need or Greed on a soulbound item) and Blizzard's
-- dialog is up; the roll is not made until it is accepted. What the game is confirming, by its roll
-- type (else the pick on the card), waits as `pending` and comes off `mine`, so the card awaits the
-- player again, buttons and all. A cancelled dialog fires nothing and the card stays as it is.
local function confirming(card, kind)
    if card.over then return end
    card.pending = CHOICE_OF[kind] or card.mine or card.pending
    if card.mine ~= nil then
        card.mine = nil
        changed(card, { mine = true })
    end
end

-- The item info of a card, asked again: it may have reached the client's cache since. A card the
-- loot history made has no roll to name its item, so it takes its name, icon and quality from the
-- item as well, and keeps what it had where the client still says nothing.
local function refreshItem(card)
    local label, ilvl = ns.Items.Describe(card.link)
    local different = label ~= card.label or ilvl ~= card.ilvl
    card.label, card.ilvl = label, ilvl
    if not card.rollID and card.link then
        local name, icon, quality = itemFacts(card.link)
        name, icon, quality = name or card.name, icon or card.icon, quality or card.quality
        different = different or name ~= card.name or icon ~= card.icon or quality ~= card.quality
        card.name, card.icon, card.quality = name, icon, quality
    end
    if different then changed(card, { item = true }) end
end

-------------------------------------------------------------------------------
--  The loot history: the group's side of a roll
-------------------------------------------------------------------------------
-- Takes a drop's picks onto the card, by GUID (an entry that cannot be read, or has no readable GUID,
-- is skipped; a field that cannot be read is left out, and a pick keeps the state it had). Gives
-- { [guid] = "state" | "roll" } for the picks that are new or different, nil when there are none.
local function readPicks(card, info)
    local entries = clear(info.rollInfos, "table")
    local marks
    for i = 1, entries and #entries or 0 do
        local entry = clear(entries[i], "table")
        local guid = entry and text(entry.playerGUID)
        if guid then
            local pick = card.picks[guid]
            local oldState, oldRoll = pick and pick.state, pick and pick.roll
            pick = pick or {}
            pick.state = stateOf(entry.state) or pick.state or "wait"
            pick.roll = clear(entry.roll, "number")
            pick.name = text(entry.playerName) or pick.name
            pick.class = text(entry.playerClass) or pick.class
            pick.isSelf = yes(entry.isSelf)
            pick.order = i
            card.picks[guid] = pick
            local mark = (pick.state ~= oldState and "state") or (pick.roll ~= oldRoll and "roll") or nil
            if mark then
                marks = marks or {}
                marks[guid] = mark
            end
        end
    end
    return marks
end

-- How much of a drop's roll has gone, as a share from 0 to 1, and whether its time is up. The three
-- times are read the way Blizzard's own history window reads them (Blizzard_FrameXML/Mainline/
-- LootHistory.lua:508-516): the history's clock minus the start, against the duration, and as a
-- share of it. Nothing in Blizzard's code says what unit they are in, so they are never turned into
-- seconds and never set against GetTime(); only the share reaches the card, which counts its own
-- minute. A drop that names no readable duration has no age and is never out of time: the game does
-- not say how long the roll lasts.
local function dropAge(info)
    local startTime, duration = clear(info.startTime, "number"), clear(info.duration, "number")
    if not (duration and duration > 0) then return 0, false end
    local now = type(C_LootHistory.GetLootHistoryTime) == "function"
        and clear(C_LootHistory.GetLootHistoryTime(), "number")
    local elapsed = (startTime and now) and math.max(now - startTime, 0) or 0
    return math.min(elapsed / duration, 1), elapsed >= duration
end

-- The fields of a card for a drop the player has no roll on: the item from its link, nothing to
-- choose, so no buttons (`over`). Its countdown is a minute with `gone` (a share) of it used up.
local function dropFields(link, gone)
    local name, icon, quality = itemFacts(link)
    local label, ilvl = ns.Items.Describe(link)
    return {
        link = link, itemID = ns.Items.ID(link),
        name = name or link, icon = icon, quality = quality, count = 1, bop = false,
        canNeed = false, canGreed = false, canTransmog = false,
        startedAt = GetTime() - gone * DEFAULT_DURATION, duration = DEFAULT_DURATION,
        label = label, ilvl = ilvl, over = true,
    }
end

-- The card of the player's roll that a drop belongs to: of the cards with a roll and no drop that show
-- the item (the live ones; and the ended ones when the drop is decided, which may be their late
-- decision), the one whose pick is the player's state in the drop (no pick counts as still choosing),
-- else the oldest. Nil when there is none.
local function rollOfDrop(info, link, isDecided)
    local candidates = showing(link, ns.Items.ID(link), function(card)
        return card.rollID ~= nil and card.dropKey == nil
            and (card.status == "live" or (isDecided and card.status == "ended"))
    end)
    local state = stateOf(info.playerRollState)
    for _, card in ipairs(candidates) do
        if state and (card.mine or "wait") == state then return card end
    end
    return candidates[1]
end

-- A drop of the history has news. The card that has the drop takes it. A drop no card has yet goes to
-- the player's roll for that item or, if it is still undecided and not out of time, to a card of its
-- own. The card then takes the picks, and the decision if the game made one, and is announced.
local function onDrop(encounterID, lootListKey)
    local history = C_LootHistory
    if type(history) ~= "table" or type(history.GetSortedInfoForDrop) ~= "function" then return end
    local info = clear(history.GetSortedInfoForDrop(encounterID, lootListKey), "table")
    local link = info and text(info.itemHyperlink)
    if not link then return end

    -- Decided: the game names a winner, or says everyone passed. A card takes the decision only when
    -- it can say who won.
    local winner = clear(info.winner, "table")
    local winnerGUID = winner and text(winner.playerGUID)
    local allPassed = yes(info.allPassed)
    local isDecided = winner ~= nil or allPassed

    local dropKey = encounterID .. ":" .. lootListKey
    local card = byDropKey[dropKey]
    if not card then
        if knownDrops[dropKey] then return end -- a card had this drop and is gone: old news
        card = rollOfDrop(info, link, isDecided)
        local fresh = card == nil
        if fresh then
            if isDecided then return end -- it was over before Tutti saw it
            local gone, stale = dropAge(info)
            if stale then return end
            card = newCard(dropFields(link, gone))
        end
        card.encounterID, card.lootListKey, card.dropKey = encounterID, lootListKey, dropKey
        byDropKey[dropKey], knownDrops[dropKey] = card, true
        if fresh then
            ns.Fire("CARD_ADDED", card)
            watch(card)
        end
    end

    local firstSight = not card.history
    local changes = { picks = readPicks(card, info) }
    card.history = true
    card.tied = yes(info.isTied)
    if card.status ~= "decided" and (winnerGUID or allPassed) then
        decide(card, winnerGUID, allPassed)
        changes.decided = true
    end
    if firstSight or next(changes) then changed(card, changes) end
end

-------------------------------------------------------------------------------
--  The interface
-------------------------------------------------------------------------------
function Rolls.Cards()
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

function Rolls.Get(id)
    return byID[id]
end

function Rolls.TimeLeft(card)
    if type(card) ~= "table" or type(card.startedAt) ~= "number" or type(card.duration) ~= "number" then return 0 end
    return math.max(0, card.duration - (GetTime() - card.startedAt))
end

function Rolls.AwaitsMe(card)
    return type(card) == "table" and card.rollID ~= nil and not card.over and card.mine == nil
        and card.status == "live"
end

-- Does the game offer this choice on this card? Transmog takes Greed's place when it is offered.
local function offered(card, choice)
    if choice == "need" then return card.canNeed end
    if choice == "greed" then return card.canGreed and not card.canTransmog end
    if choice == "transmog" then return card.canTransmog end
    return choice == "pass"
end

function Rolls.Pick(card, choice)
    local kind = ROLL_TYPE[choice]
    if not kind or not Rolls.AwaitsMe(card) or not offered(card, choice) then return false end
    -- The pick goes on the card first: the game ends the player's part (CANCEL_LOOT_ROLL) from
    -- inside RollOnLoot, and whoever hears of that should already find the pick there. A bind
    -- confirmation takes it off again (see `confirming`).
    card.pending = nil -- a new pick: whatever a confirmation the player cancelled left behind
    card.mine = choice
    if not card.demo and not ns.Safe(RollOnLoot, card.rollID, kind) then
        card.mine = nil -- the game never got it
        return false
    end
    changed(card, { mine = true })
    return true
end

-- The player's own row. The history's entry once it says what they chose; else the click they made
-- (it shows at once, even while the history still lists them as choosing); else choosing, when the
-- history lists them or the game gave them a roll; else out, as for any member the history does not
-- list, once the card has the history.
local function playerState(card, pick)
    if pick and pick.state ~= "wait" then return pick.state end
    if card.mine then return card.mine end
    if pick or card.rollID then return "wait" end
    return card.history and "out" or "wait"
end

-- One row per group member in the group's order, then one per roller the group does not list
-- (someone who left, or whom the group list could not name), from the history, in its order. A
-- member's row is their pick in the history. Until the card has the history everyone is still
-- choosing; once it has, a member it does not list is out. The player's row is `playerState`.
-- Once the card is decided or ended nobody is choosing: a row still at "wait" is out.
function Rolls.Rows(card)
    card = type(card) == "table" and card or {}
    local picks = type(card.picks) == "table" and card.picks or {}
    local over = card.status == "decided" or card.status == "ended"
    local function settled(state)
        if over and state == "wait" then return "out" end
        return state
    end
    local rows, listed = {}, {}
    for _, member in ipairs(ns.Group.Members()) do
        local pick = picks[member.guid]
        local state
        if member.isPlayer then
            state = playerState(card, pick)
        elseif pick then
            state = pick.state
        else
            state = card.history and "out" or "wait"
        end
        rows[#rows + 1] = {
            guid = member.guid, name = member.first, class = member.class, isPlayer = member.isPlayer,
            state = settled(state), roll = pick and pick.roll or nil,
            isWinner = card.winner ~= nil and card.winner == member.guid,
        }
        listed[member.guid] = true
    end
    local rest = {}
    for guid in pairs(picks) do
        if not listed[guid] then rest[#rest + 1] = guid end
    end
    table.sort(rest, function(a, b)
        local x, y = picks[a].order or math.huge, picks[b].order or math.huge
        if x ~= y then return x < y end
        return a < b
    end)
    for _, guid in ipairs(rest) do
        local pick = picks[guid]
        local isPlayer = pick.isSelf == true -- the player, when the group list could not list them
        rows[#rows + 1] = {
            guid = guid, name = ns.Group.FirstName(pick.name), class = pick.class, isPlayer = isPlayer,
            state = settled(isPlayer and playerState(card, pick) or pick.state), roll = pick.roll,
            isWinner = card.winner == guid,
        }
    end
    return rows
end

function Rolls.Forget(card)
    if type(card) ~= "table" or byID[card.id] ~= card then return end
    byID[card.id] = nil
    if card.dropKey and byDropKey[card.dropKey] == card then byDropKey[card.dropKey] = nil end
    for i = 1, #list do
        if list[i] == card then table.remove(list, i); break end
    end
    ns.Fire("CARD_REMOVED", card)
end

function Rolls.ForgetDecided()
    for _, card in ipairs(Rolls.Cards()) do
        if card.status ~= "live" then Rolls.Forget(card) end
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
ns.On("START_LOOT_ROLL", function(_, rollID, rollTime)
    rollID = clear(rollID, "number")
    if rollID then add(rollID, rollTime) end
end)

ns.On("CANCEL_LOOT_ROLL", function(_, rollID)
    rollID = clear(rollID, "number")
    if not rollID then return end
    for _, card in ipairs(Rolls.Cards()) do
        if card.rollID == rollID then finish(card) end
    end
end)

ns.On("CANCEL_ALL_LOOT_ROLLS", function()
    for _, card in ipairs(Rolls.Cards()) do
        if card.rollID then finish(card) end
    end
end)

ns.On("CONFIRM_LOOT_ROLL", function(_, rollID, rollType)
    rollID = clear(rollID, "number")
    if not rollID then return end
    local kind = clear(rollType, "number")
    for _, card in ipairs(Rolls.Cards()) do
        if card.rollID == rollID then confirming(card, kind) end
    end
end)

ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
    itemID = clear(itemID, "number")
    if not itemID then return end
    for _, card in ipairs(Rolls.Cards()) do
        if card.itemID == itemID then refreshItem(card) end
    end
end)

-- The history updates a drop at every choice and at the end.
ns.On("LOOT_HISTORY_UPDATE_DROP", function(_, encounterID, lootListKey)
    encounterID, lootListKey = clear(encounterID, "number"), clear(lootListKey, "number")
    if encounterID and lootListKey then onDrop(encounterID, lootListKey) end
end)

-- The game clears its loot history and may use its keys again: the ones Tutti remembers, and the cards
-- they pointed at, go. A card keeps its own fields and picks.
ns.On("LOOT_HISTORY_CLEAR_HISTORY", function()
    byDropKey, knownDrops = {}, {}
end)

-- After a /reload (and at any loading screen) the game still lists the rolls the player has not
-- chosen on; a card is made for each one that has none.
ns.On("PLAYER_ENTERING_WORLD", function()
    if type(GetActiveLootRollIDs) ~= "function" then return end
    local ids = clear(GetActiveLootRollIDs(), "table")
    if not ids then return end
    for i = 1, #ids do
        local rollID = clear(ids[i], "number")
        if rollID then add(rollID) end
    end
end)
