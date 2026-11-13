-------------------------------------------------------------------------------
--  Tutti: the card model. A card is one item the group is rolling on. A card for the player's
--  own roll appears when the game starts it (START_LOOT_ROLL) or, after a /reload, when the game
--  still lists it (GetActiveLootRollIDs). It carries what the window needs: the item, what the
--  player may choose, the countdown and the player's pick.
--    ns.Rolls.Cards()              { card, ... } in arrival order; a new list on every call
--    ns.Rolls.Get(id)              a card by Tutti's own id
--    ns.Rolls.Pick(card, choice)   "need" | "greed" | "transmog" | "pass"; true when it was sent
--    ns.Rolls.TimeLeft(card)       seconds left, never below 0
--    ns.Rolls.AwaitsMe(card)       the player can still choose on this card
--    ns.Rolls.Rows(card)           one row per group member:
--                                  { guid, name, class, isPlayer, state, roll, isWinner }
--    ns.Rolls.Forget(card), ns.Rolls.ForgetDecided()
--  A card: id, rollID|nil, link, itemID, name, icon, quality, count, bop, label|nil, ilvl|nil,
--  canNeed, canGreed, canTransmog, reasonNeed|nil (text), startedAt (GetTime), duration (s),
--  mine|nil, pending|nil, over, history, picks, status ("live"|"decided"|"ended"), winner|nil,
--  allPassed, decidedAt|nil, demo|nil.
--  A bind confirmation: Need or Greed on a soulbound item first makes the game ask the player to
--  confirm (CONFIRM_LOOT_ROLL, Blizzard's own dialog; Tutti leaves it alone and never confirms).
--  The roll is not made until the dialog is accepted, so the pick waits as `pending` instead of
--  `mine`: the card awaits the player again and its buttons work meanwhile, and a cancelled dialog,
--  which fires nothing, leaves the card as it is. When the game takes the roll (CANCEL_LOOT_ROLL)
--  the pending pick becomes `mine`. If the time runs out while the dialog is open the game says
--  the same thing, so `mine` then shows a pick the game passed on; the loot history, which names
--  the player's real pick, corrects it.
--  Messages:
--    "CARD_ADDED", card
--    "CARD_CHANGED", card, changes     changes: a set of item | mine | over | picks | decided
--    "CARD_DECIDED", card              once per card
--    "CARD_REMOVED", card
--  Everything the game hands over passes ns.IsSecret and a type check before it is used.
-------------------------------------------------------------------------------
local _, ns = ...
local Rolls = {}
ns.Rolls = Rolls

local DEFAULT_DURATION = 60 -- seconds, when the game names no time for a roll

-- RollOnLoot's types.
local ROLL_TYPE = { pass = 0, need = 1, greed = 2, transmog = 4 }
-- The choice a type names, for the types a confirmation can be about (Pass is never confirmed).
local CHOICE_OF = { [1] = "need", [2] = "greed", [4] = "transmog" }

-- Why Need can be refused, when the client has no text for it. Only reason 1 is known to read
-- like this; any other number gets the general sentence.
local REASON_FALLBACK = { [1] = "Your class may not roll need on this item." }
local REASON_ANY = "You can't roll Need on this item."

local list = {}  -- the cards in arrival order
local byID = {}  -- Tutti's own id -> card
local lastID = 0

-------------------------------------------------------------------------------
--  Reading what the game says
-------------------------------------------------------------------------------
-- A value of the given type that the game gave in the clear, else nil.
local function clear(value, kind)
    if ns.IsSecret(value) or type(value) ~= kind then return nil end
    return value
end

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

-------------------------------------------------------------------------------
--  Cards
-------------------------------------------------------------------------------
local function changed(card, changes)
    ns.Fire("CARD_CHANGED", card, changes)
end

local function build(rollID, rollTime)
    local info = readInfo(rollID)
    if not info then return nil end
    local link = GetLootRollItemLink and text(GetLootRollItemLink(rollID)) or nil
    local duration, elapsed = timing(rollID, rollTime)
    lastID = lastID + 1
    local card = {
        id = lastID, rollID = rollID,
        link = link, itemID = ns.Items.ID(link),
        name = info.name, icon = info.icon, quality = info.quality, count = info.count, bop = info.bop,
        canNeed = info.canNeed, canGreed = info.canGreed, canTransmog = info.canTransmog,
        reasonNeed = info.reasonNeed,
        startedAt = GetTime() - elapsed, duration = duration,
        over = false, history = false, picks = {},
        status = "live", allPassed = false,
    }
    card.label, card.ilvl = ns.Items.Describe(link)
    return card
end

-- A roll that already has a live card is the same roll: START_LOOT_ROLL and the rebuild after a
-- /reload can both name it.
local function hasLiveCard(rollID)
    for i = 1, #list do
        if list[i].rollID == rollID and list[i].status == "live" then return true end
    end
    return false
end

local function add(rollID, rollTime)
    if hasLiveCard(rollID) then return end
    local card = build(rollID, rollTime)
    if not card then return end
    list[#list + 1] = card
    byID[card.id] = card
    ns.Fire("CARD_ADDED", card)
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

-- The item info of a card, asked again: it may have reached the client's cache since.
local function refreshItem(card)
    local label, ilvl = ns.Items.Describe(card.link)
    if label == card.label and ilvl == card.ilvl then return end
    card.label, card.ilvl = label, ilvl
    changed(card, { item = true })
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

-- One row per group member in the group's order. The group's picks come from the loot history;
-- until a card has them everyone is still choosing, and the player's row shows their own pick.
function Rolls.Rows(card)
    local mine = type(card) == "table" and card.mine or nil
    local rows = {}
    for _, member in ipairs(ns.Group.Members()) do
        rows[#rows + 1] = {
            guid = member.guid, name = member.first, class = member.class, isPlayer = member.isPlayer,
            state = (member.isPlayer and mine) or "wait", isWinner = false, -- no roll yet
        }
    end
    return rows
end

function Rolls.Forget(card)
    if type(card) ~= "table" or byID[card.id] ~= card then return end
    byID[card.id] = nil
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

-- After a /reload (and at any loading screen) the game still lists the rolls the player has not
-- chosen on; a card is made for each one that has none.
ns.On("PLAYER_ENTERING_WORLD", function()
    if type(GetActiveLootRollIDs) ~= "function" then return end
    local ids = GetActiveLootRollIDs()
    if ns.IsSecret(ids) or type(ids) ~= "table" then return end
    for i = 1, #ids do
        local rollID = clear(ids[i], "number")
        if rollID then add(rollID) end
    end
end)
