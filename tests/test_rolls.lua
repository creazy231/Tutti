local T = T

-- The mockup's Dualblade: a two-hand axe, item 18000.
local AXE = 18000
local function axeInfo()
    return { name = "Guardian's Dualblade", quality = 3, ilvl = 33, classID = 2, subclassID = 1,
        equipLoc = "INVTYPE_2HWEAPON", texture = 135348 }
end

-- A roll for the axe; `over` changes or adds fields of the spec.
local function axeSpec(W, over)
    local spec = { link = W.itemLink(AXE, "Guardian's Dualblade", 3), name = "Guardian's Dualblade", texture = 135348 }
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

-- Starts a roll for the axe and hands back its card.
local function newCard(W, ns, rollID, over)
    W.addRoll(rollID, axeSpec(W, over))
    local cards = ns.Rolls.Cards()
    return cards[#cards]
end

-- Every message of one kind, in order: { card, changes }.
local function listen(ns, msg)
    local seen = {}
    ns.Listen(msg, function(card, changes) seen[#seen + 1] = { card = card, changes = changes } end)
    return seen
end

local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- A game that records errors instead of raising them (the fake's default handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

-- A secret string in the game still has type "string", so the fake's userdata secrets prove little
-- about a check that stops at type(). Here plain values play secrets by being named in `hidden`.
local function withSecrets(ns)
    local hidden = {}
    ns.IsSecret = function(...)
        for i = 1, select("#", ...) do
            if hidden[(select(i, ...))] then return true end
        end
        return false
    end
    return hidden
end

T.it("START_LOOT_ROLL adds one live card", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    W.addRoll(7, axeSpec(W))
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 1, "one card")
    local card = cards[1]
    T.eq(#added, 1, "CARD_ADDED fired once")
    T.eq(added[1].card, card, "with the card")
    T.eq(card.name, "Guardian's Dualblade")
    T.eq(card.quality, 3)
    T.eq(card.duration, 60, "the game's 60000 ms")
    T.eq(card.rollID, 7)
    T.eq(card.status, "live")
end)

T.it("a card carries what the roll shows", function()
    local G, W, ns = T.load()
    local spec = axeSpec(W, { count = 2, bop = false, canGreed = false })
    W.addRoll(7, spec)
    local card = ns.Rolls.Cards()[1]
    T.eq(card.id, 1, "Tutti's own counter")
    T.eq(card.link, spec.link)
    T.eq(card.itemID, AXE, "read out of the link")
    T.eq(card.icon, 135348)
    T.eq(card.count, 2)
    T.eq(card.bop, false)
    T.eq(card.canNeed, true)
    T.eq(card.canGreed, false)
    T.eq(card.canTransmog, false)
    T.eq(card.reasonNeed, nil, "Need is allowed: nothing to explain")
    T.eq(card.startedAt, W.clock, "it started now")
    T.eq(card.over, false)
    T.eq(card.history, false, "no loot history yet")
    T.eq(card.mine, nil)
    T.eq(card.pending, nil, "no bind confirmation waiting")
    T.eq(card.winner, nil)
    T.eq(card.allPassed, false)
    T.eq(card.decidedAt, nil)
    T.eq(card.demo, nil)
    T.eq(type(card.picks), "table")
    T.eq(next(card.picks), nil, "the group's picks come from the loot history")
    T.eq(ns.Rolls.Get(card.id), card)
    T.eq(ns.Rolls.Get(999), nil)
end)

T.it("a cached item is described at once", function()
    local G, W, ns = T.load()
    W.items[AXE] = axeInfo()
    local card = newCard(W, ns, 7)
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
end)

T.it("a roll without a name (GetLootRollItemInfo nil) adds no card", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    W.fire("START_LOOT_ROLL", 99, 60000) -- the game knows no such roll: GetLootRollItemInfo answers nothing
    W.addRoll(8, { link = W.itemLink(AXE, "x") }) -- an answer without a name
    W.addRoll(9, axeSpec(W, { name = "" }))
    W.addRoll(10, axeSpec(W, { name = T.secret("Guardian's Dualblade") })) -- a name the game keeps secret
    T.eq(#ns.Rolls.Cards(), 0, "no card")
    T.eq(#added, 0, "nothing announced")
    local card = newCard(W, ns, 11)
    T.eq(card.id, 1, "the counter only counts cards")
end)

T.it("secret or malformed payloads are ignored", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("START_LOOT_ROLL", T.secret(8), 60000)
    W.fire("START_LOOT_ROLL", "8", 60000)
    W.fire("START_LOOT_ROLL")
    W.fire("CANCEL_LOOT_ROLL", T.secret(7))
    W.fire("CANCEL_LOOT_ROLL")
    W.fire("GET_ITEM_INFO_RECEIVED", T.secret(AXE), true)
    W.fire("GET_ITEM_INFO_RECEIVED")
    T.eq(#ns.Rolls.Cards(), 1, "no new card")
    T.eq(card.over, false, "the roll is still the player's")
    T.eq(#changed, 0, "nothing changed")
end)

T.it("a secret name, link or time on a roll is not read", function()
    local G, W, ns = T.load()
    local hidden = withSecrets(ns)
    hidden["Guardian's Dualblade"] = true
    W.addRoll(1, axeSpec(W))
    T.eq(#ns.Rolls.Cards(), 0, "a secret name adds no card")
    hidden["Guardian's Dualblade"] = nil

    local spec = axeSpec(W)
    hidden[spec.link] = true
    W.items[AXE] = axeInfo()
    W.addRoll(2, spec)
    local card = ns.Rolls.Cards()[1]
    T.eq(card.rollID, 2, "the roll still gets its card")
    T.eq(card.link, nil, "but not a link it cannot read")
    T.eq(card.itemID, nil)
    T.eq(card.label, nil, "nor the item facts that hang on it")
    hidden[spec.link] = nil

    hidden[45000] = true -- START_LOOT_ROLL's time, and the game's answer to C_Loot as well
    W.addRoll(3, axeSpec(W, { time = 45000 }))
    T.eq(ns.Rolls.Cards()[2].duration, 60, "no readable time: a minute")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[2]), 60, 0.01)
end)

T.it("a secret roll ID, item ID or roll list in an event is not used", function()
    local G, W, ns = T.load()
    local hidden = withSecrets(ns)
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    hidden[7] = true
    W.fire("CANCEL_LOOT_ROLL", 7)
    T.eq(card.over, false, "a secret roll ID names no card")
    hidden[7] = nil

    hidden[AXE] = true
    W.cacheItem(AXE, axeInfo())
    T.eq(card.label, nil, "a secret item ID refreshes nothing")
    hidden[AXE] = nil

    W.addRoll(8, axeSpec(W), { silent = true })
    W.activeRolls = { 8 }
    hidden[8] = true
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    W.fire("START_LOOT_ROLL", 8, 60000)
    T.eq(#ns.Rolls.Cards(), 1, "a secret roll ID makes no card")
    T.eq(#changed, 0, "nothing changed")
end)

T.it("a secret yes or no is a no", function()
    local G, W, ns = T.load()
    local hidden = withSecrets(ns)
    hidden[true] = true
    local card = newCard(W, ns, 7)
    T.eq(card.canNeed, false)
    T.eq(card.canGreed, false)
    T.eq(card.canTransmog, false)
    T.eq(card.bop, false)
    T.eq(ns.Rolls.Pick(card, "need"), false, "Need is only offered when the game plainly says so")
    T.eq(ns.Rolls.Pick(card, "greed"), false)
    T.eq(#W.rolled, 0)
    T.eq(ns.Rolls.Pick(card, "pass"), true, "Pass never depends on it")
end)

T.it("a secret reason number gives no reason", function()
    local G, W, ns = T.load()
    local hidden = withSecrets(ns)
    hidden[5] = true
    local card = newCard(W, ns, 7, { canNeed = false, reasonNeed = 5 })
    T.eq(card.canNeed, false)
    T.eq(card.reasonNeed, nil)
end)

T.it("a second START_LOOT_ROLL for the same roll adds no second card", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    newCard(W, ns, 7)
    W.fire("START_LOOT_ROLL", 7, 60000)
    T.eq(#ns.Rolls.Cards(), 1)
    T.eq(#added, 1)
end)

T.it("the roll's time is in milliseconds, with the game's answer as the fallback", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 1, { time = 30000 })
    T.eq(card.duration, 30, "START_LOOT_ROLL's time, in seconds")
    W.advance(5)
    -- The event's time is unreadable: the game still knows how long the roll lasts.
    W.addRoll(2, axeSpec(W, { time = 45000 }), { silent = true })
    W.fire("START_LOOT_ROLL", 2, T.secret(45000))
    card = ns.Rolls.Cards()[2]
    T.eq(card.duration, 45)
    -- And when it does not say, a roll lasts a minute.
    G.C_Loot.GetLootRollDuration = function() return nil end
    W.addRoll(3, axeSpec(W), { silent = true })
    W.fire("START_LOOT_ROLL", 3, "soon")
    T.eq(ns.Rolls.Cards()[3].duration, 60)
end)

T.it("Need not allowed carries the game's reason", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7, { canNeed = false, reasonNeed = 1 })
    T.eq(card.canNeed, false)
    T.eq(card.reasonNeed, G.LOOT_ROLL_INELIGIBLE_REASON1, "the client's own text")
    local other = newCard(W, ns, 8, { canNeed = false, reasonNeed = 5 })
    T.eq(other.reasonNeed, G.LOOT_ROLL_INELIGIBLE_REASON5)
    T.eq(newCard(W, ns, 9, { canNeed = false, reasonNeed = 0 }).reasonNeed, nil, "no reason given, none shown")
    T.eq(newCard(W, ns, 10, { canNeed = true, reasonNeed = 1 }).reasonNeed, nil, "a Need that is allowed has no reason")
end)

T.it("a reason falls back to English when the client has no text for it", function()
    local G, W, ns = T.load()
    G.LOOT_ROLL_INELIGIBLE_REASON1, G.LOOT_ROLL_INELIGIBLE_REASON5 = nil, nil
    T.eq(newCard(W, ns, 7, { canNeed = false, reasonNeed = 1 }).reasonNeed,
        "Your class may not roll need on this item.")
    local generic = newCard(W, ns, 8, { canNeed = false, reasonNeed = 5 }).reasonNeed
    T.eq(type(generic), "string", "still a reason")
    T.ok(generic ~= "", "not empty")
end)

T.it("Pick need rolls 1 and marks mine", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    T.eq(ns.Rolls.AwaitsMe(card), true, "the player's choice is open")
    T.eq(ns.Rolls.Pick(card, "need"), true)
    T.eq(#W.rolled, 1, "one RollOnLoot")
    T.eq(W.rolled[1][1], 7, "for this roll")
    T.eq(W.rolled[1][2], 1, "Need is 1")
    T.eq(card.mine, "need")
    T.eq(#changed, 1, "one change")
    T.eq(changed[1].card, card)
    T.eq(changed[1].changes.mine, true, "mine")
    T.eq(ns.Rolls.AwaitsMe(card), false, "chosen")
    T.eq(ns.Rolls.Pick(card, "greed"), false, "one pick per roll")
    T.eq(#W.rolled, 1, "the game is not asked twice")
end)

T.it("Pick greed 2, pass 0, transmog 4", function()
    local G, W, ns = T.load()
    T.eq(ns.Rolls.Pick(newCard(W, ns, 1), "greed"), true)
    T.eq(W.rolled[1][1], 1)
    T.eq(W.rolled[1][2], 2, "Greed is 2")
    local passing = newCard(W, ns, 2)
    T.eq(ns.Rolls.Pick(passing, "pass"), true)
    T.eq(W.rolled[2][1], 2)
    T.eq(W.rolled[2][2], 0, "Pass is 0")
    T.eq(passing.mine, "pass")
    W.rolled = {}

    -- Transmog only when the game offers it, and then it takes Greed's place.
    local plain = newCard(W, ns, 3)
    T.eq(ns.Rolls.Pick(plain, "transmog"), false, "no Transmog on this item")
    T.eq(#W.rolled, 0)
    T.eq(plain.mine, nil)

    local offered = newCard(W, ns, 4, { canTransmog = true })
    T.eq(ns.Rolls.Pick(offered, "greed"), false, "Transmog takes Greed's place")
    T.eq(#W.rolled, 0)
    T.eq(ns.Rolls.Pick(offered, "transmog"), true)
    T.eq(W.rolled[1][1], 4)
    T.eq(W.rolled[1][2], 4, "Transmog is 4")
    T.eq(offered.mine, "transmog")

    local still = newCard(W, ns, 5, { canTransmog = true })
    T.eq(ns.Rolls.Pick(still, "need"), true, "Need is still there")
    T.eq(W.rolled[2][2], 1)
    T.eq(ns.Rolls.Pick(newCard(W, ns, 6, { canTransmog = true }), "pass"), true, "and Pass")
    T.eq(W.rolled[3][2], 0)
end)

T.it("Pick need is refused when Need isn't allowed", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7, { canNeed = false, reasonNeed = 1 })
    local changed = listen(ns, "CARD_CHANGED")
    T.eq(ns.Rolls.Pick(card, "need"), false)
    T.eq(#W.rolled, 0, "the game never hears of it")
    T.eq(card.mine, nil)
    T.eq(#changed, 0)
    T.eq(ns.Rolls.AwaitsMe(card), true, "the player can still choose")
    T.eq(ns.Rolls.Pick(card, "pass"), true, "something else")
    T.eq(W.rolled[1][2], 0)
end)

T.it("Pick greed is refused when Greed isn't allowed", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7, { canGreed = false })
    T.eq(ns.Rolls.Pick(card, "greed"), false)
    T.eq(#W.rolled, 0)
    T.eq(ns.Rolls.Pick(card, "need"), true)
end)

T.it("Pick refuses a choice that does not exist and a card the player cannot choose on", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    for _, choice in ipairs({ "disenchant", "", 1, true }) do
        T.eq(ns.Rolls.Pick(card, choice), false, "choice " .. tostring(choice))
    end
    T.eq(ns.Rolls.Pick(card, nil), false, "no choice")
    T.eq(ns.Rolls.Pick(card, T.secret("need")), false, "a secret choice")
    T.eq(ns.Rolls.Pick(nil, "need"), false, "no card")
    local noRoll = newCard(W, ns, 8)
    noRoll.rollID = nil -- a roll the player is not part of
    T.eq(ns.Rolls.Pick(noRoll, "pass"), false)
    local over = newCard(W, ns, 9)
    over.over = true
    T.eq(ns.Rolls.Pick(over, "pass"), false)
    local decided = newCard(W, ns, 10)
    decided.status = "decided"
    T.eq(ns.Rolls.Pick(decided, "pass"), false)
    T.eq(#W.rolled, 0, "nothing reached the game")
    T.eq(card.mine, nil)
end)

T.it("Pick on a demo card never calls RollOnLoot", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    card.demo = true
    local changed = listen(ns, "CARD_CHANGED")
    T.eq(ns.Rolls.Pick(card, "need"), true, "the demo takes the pick")
    T.eq(#W.rolled, 0, "the game is never asked")
    T.eq(card.mine, "need")
    T.eq(#changed, 1)
    T.eq(changed[1].changes.mine, true)
end)

T.it("the pick is on the card before the game hears of it", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local seen
    G.RollOnLoot = function(rollID, kind) seen = card.mine end
    ns.Rolls.Pick(card, "greed")
    T.eq(seen, "greed", "the game ends the player's part from inside the call, so it must already show")
end)

T.it("the game ending the player's part inside RollOnLoot leaves a coherent card", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local trail = {}
    ns.Listen("CARD_CHANGED", function(c, changes)
        local what = (changes.over and "over" or "") .. (changes.mine and "mine" or "")
        trail[#trail + 1] = what .. ":" .. tostring(c.mine)
    end)
    G.RollOnLoot = function(rollID, kind)
        W.rolled[#W.rolled + 1] = { rollID, kind }
        W.fire("CANCEL_LOOT_ROLL", rollID) -- as the game does, from inside the call
    end
    T.eq(ns.Rolls.Pick(card, "need"), true)
    T.eq(table.concat(trail, ","), "over:need,mine:need", "the pick is there whenever the card is announced")
    T.eq(card.mine, "need")
    T.eq(card.over, true)
    T.eq(card.status, "live", "the group may still be rolling")
end)

T.it("a RollOnLoot that fails is not a pick", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    G.RollOnLoot = function() error("not now") end
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    T.eq(ns.Rolls.Pick(card, "need"), false)
    T.eq(card.mine, nil, "the card does not claim a pick the game never got")
    T.eq(#changed, 0)
    T.eq(#errors, 1, "the error is reported")
    T.ok(tostring(errors[1]):find("not now", 1, true), "the game's error")
    T.eq(ns.Rolls.AwaitsMe(card), true, "the player can try again")
end)

T.it("CANCEL_LOOT_ROLL ends the player's part, the card stays live", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local other = newCard(W, ns, 8)
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CANCEL_LOOT_ROLL", 7)
    T.eq(card.over, true)
    T.eq(card.status, "live", "the group may still be rolling")
    T.eq(#changed, 1)
    T.eq(changed[1].card, card)
    T.eq(changed[1].changes.over, true)
    T.eq(ns.Rolls.AwaitsMe(card), false)
    T.eq(ns.Rolls.Pick(card, "need"), false, "too late")
    T.eq(#W.rolled, 0)
    T.eq(other.over, false, "another roll is not touched")
    W.fire("CANCEL_LOOT_ROLL", 7)
    T.eq(#changed, 1, "a second cancel changes nothing")
    W.fire("CANCEL_LOOT_ROLL", 404)
    T.eq(#changed, 1, "a roll with no card is not an error")
end)

T.it("CANCEL_ALL_LOOT_ROLLS ends every part", function()
    local G, W, ns = T.load()
    local a, b = newCard(W, ns, 7), newCard(W, ns, 8)
    ns.Rolls.Pick(b, "greed") -- chosen already
    local c = newCard(W, ns, 9)
    c.rollID = nil -- a card the player has no roll for
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CANCEL_ALL_LOOT_ROLLS")
    T.eq(a.over, true)
    T.eq(b.over, true)
    T.eq(c.over, false, "no roll, no part to end")
    T.eq(#changed, 2, "one change per card")
    T.eq(changed[1].changes.over, true)
    T.eq(a.status, "live")
    T.eq(b.mine, "greed", "the pick stays")
    W.fire("CANCEL_ALL_LOOT_ROLLS")
    T.eq(#changed, 2, "nothing left to end")
end)

T.it("a bind confirmation keeps the buttons until the game takes the roll", function()
    local G, W, ns = T.load()
    local confirmed = 0
    G.ConfirmLootRoll = function() confirmed = confirmed + 1 end -- Blizzard's dialog calls it, never Tutti
    local card = newCard(W, ns, 7, { bop = true })
    T.eq(ns.Rolls.Pick(card, "need"), true)
    T.eq(card.mine, "need", "the pick is on the card at once")
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CONFIRM_LOOT_ROLL", 7, 1, "LOOT_BIND") -- the game asks the player to confirm the bind
    T.eq(card.mine, nil, "the roll is not made yet")
    T.eq(card.pending, "need", "the game is confirming Need")
    T.eq(ns.Rolls.AwaitsMe(card), true, "the buttons work while Blizzard's dialog is up")
    T.eq(card.over, false, "the player's part is not over")
    T.eq(#changed, 1, "one message")
    T.eq(changed[1].card, card)
    T.eq(changed[1].changes.mine, true)
    -- The player accepts the dialog: the game takes the roll and ends the player's part.
    W.fire("CANCEL_LOOT_ROLL", 7)
    T.eq(card.mine, "need", "the pick is the player's now")
    T.eq(card.pending, nil)
    T.eq(card.over, true)
    T.eq(ns.Rolls.AwaitsMe(card), false)
    T.eq(#changed, 2, "one message for the end")
    T.eq(changed[2].changes.mine, true, "both keys in the one message")
    T.eq(changed[2].changes.over, true)
    T.eq(#W.rolled, 1, "the game was asked once")
    T.eq(confirmed, 0, "Tutti never confirms; the dialog stays with Blizzard")
end)

T.it("a cancelled confirmation leaves the roll open", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    T.eq(ns.Rolls.Pick(card, "need"), true)
    W.fire("CONFIRM_LOOT_ROLL", 7, 1)
    -- The player cancels Blizzard's dialog: the game says nothing, and the card still awaits them.
    T.eq(ns.Rolls.AwaitsMe(card), true)
    T.eq(ns.Rolls.Pick(card, "greed"), true, "another choice goes out")
    T.eq(#W.rolled, 2)
    T.eq(W.rolled[2][1], 7)
    T.eq(W.rolled[2][2], 2, "Greed is 2")
    T.eq(card.mine, "greed")
    T.eq(card.pending, nil, "a new pick clears what the cancelled confirmation left")
end)

T.it("a secret confirmation payload is ignored", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    ns.Rolls.Pick(card, "need")
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CONFIRM_LOOT_ROLL", T.secret(7), 1)
    W.fire("CONFIRM_LOOT_ROLL", "7", 1)
    W.fire("CONFIRM_LOOT_ROLL")
    T.eq(card.mine, "need", "the pick stays")
    T.eq(card.pending, nil)
    T.eq(#changed, 0, "nothing changed")
    -- A plain value can play a secret: only ns.IsSecret can tell a secret number from a number.
    local hidden = withSecrets(ns)
    hidden[7] = true
    W.fire("CONFIRM_LOOT_ROLL", 7, 1)
    T.eq(card.mine, "need", "a secret roll ID names no card")
    T.eq(card.pending, nil)
    T.eq(#changed, 0)
    hidden[7] = nil
    W.fire("CONFIRM_LOOT_ROLL", 7, 1) -- the same event in the clear is heard
    T.eq(card.pending, "need")
    T.eq(#changed, 1)
end)

T.it("the game's roll type names the choice it is confirming, else the pick on the card", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    ns.Rolls.Pick(card, "need")
    W.fire("CONFIRM_LOOT_ROLL", 7, 2) -- the game says Greed
    T.eq(card.pending, "greed", "the game's word wins")
    T.eq(card.mine, nil)

    local transmog = newCard(W, ns, 8, { canTransmog = true })
    ns.Rolls.Pick(transmog, "transmog")
    W.fire("CONFIRM_LOOT_ROLL", 8, 4)
    T.eq(transmog.pending, "transmog")

    local unreadable = newCard(W, ns, 9)
    ns.Rolls.Pick(unreadable, "greed")
    W.fire("CONFIRM_LOOT_ROLL", 9, T.secret(1))
    T.eq(unreadable.pending, "greed", "an unreadable type: the pick on the card")
    T.eq(unreadable.mine, nil)

    local unknown = newCard(W, ns, 10)
    ns.Rolls.Pick(unknown, "need")
    W.fire("CONFIRM_LOOT_ROLL", 10, 3) -- a type Tutti has no choice for
    T.eq(unknown.pending, "need", "the pick on the card")

    -- A confirmation for a roll the player did not start from Tutti (no pick on the card): the
    -- game's word is kept for when it takes the roll, and nothing is announced, as nothing changed.
    local elsewhere = newCard(W, ns, 11)
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CONFIRM_LOOT_ROLL", 11, T.secret(1))
    T.eq(elsewhere.pending, nil, "nothing to wait for")
    W.fire("CONFIRM_LOOT_ROLL", 11, 1)
    T.eq(elsewhere.pending, "need")
    T.eq(elsewhere.mine, nil)
    T.eq(#changed, 0, "nothing was announced")
    W.fire("CANCEL_LOOT_ROLL", 11)
    T.eq(elsewhere.mine, "need", "the pick the game took")
    T.eq(#changed, 1)
end)

T.it("the game asking for the confirmation inside RollOnLoot leaves a coherent card", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local seen = {}
    ns.Listen("CARD_CHANGED", function(c) seen[#seen + 1] = tostring(c.mine) .. "/" .. tostring(c.pending) end)
    G.RollOnLoot = function(rollID, kind)
        W.rolled[#W.rolled + 1] = { rollID, kind }
        W.fire("CONFIRM_LOOT_ROLL", rollID, kind, "LOOT_BIND") -- as the game does, from inside the call
    end
    T.eq(ns.Rolls.Pick(card, "need"), true)
    T.eq(card.mine, nil, "the roll is not made yet")
    T.eq(card.pending, "need")
    T.eq(ns.Rolls.AwaitsMe(card), true)
    T.ok(#seen >= 1, "the card was announced")
    for i, state in ipairs(seen) do
        T.eq(state, "nil/need", "message " .. i .. " finds the card as it is")
    end
    W.fire("CANCEL_LOOT_ROLL", 7) -- the player accepts
    T.eq(card.mine, "need")
    T.eq(card.pending, nil)
end)

T.it("CANCEL_ALL_LOOT_ROLLS gives a pending pick to the player", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    ns.Rolls.Pick(card, "greed")
    W.fire("CONFIRM_LOOT_ROLL", 7, 2)
    local plain = newCard(W, ns, 8)
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CANCEL_ALL_LOOT_ROLLS")
    T.eq(card.mine, "greed")
    T.eq(card.pending, nil)
    T.eq(card.over, true)
    T.eq(plain.mine, nil, "no pick pending, none made up")
    T.eq(plain.over, true)
    T.eq(#changed, 2, "one message per card")
    T.eq(changed[1].changes.mine, true, "the pending pick, with the end")
    T.eq(changed[1].changes.over, true)
    T.eq(changed[2].changes.mine, nil)
    T.eq(changed[2].changes.over, true)
end)

T.it("a confirmation for a roll that is over or unknown changes nothing", function()
    local G, W, ns = T.load()
    local over = newCard(W, ns, 7)
    ns.Rolls.Pick(over, "need")
    W.fire("CANCEL_LOOT_ROLL", 7) -- the player's part is over
    local live = newCard(W, ns, 8)
    ns.Rolls.Pick(live, "need")
    local changed = listen(ns, "CARD_CHANGED")
    W.fire("CONFIRM_LOOT_ROLL", 7, 1)
    W.fire("CONFIRM_LOOT_ROLL", 404, 1)
    T.eq(over.mine, "need", "a late confirmation takes nothing back")
    T.eq(over.pending, nil)
    T.eq(#changed, 0)
    W.fire("CONFIRM_LOOT_ROLL", 8, 1) -- the one that counts is heard
    T.eq(live.pending, "need")
    T.eq(#changed, 1)
end)

T.it("TimeLeft counts down", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    T.near(ns.Rolls.TimeLeft(card), 60, 0.01, "at the start")
    W.advance(10)
    T.near(ns.Rolls.TimeLeft(card), 50, 0.01, "ten seconds in")
    W.advance(45.5)
    T.near(ns.Rolls.TimeLeft(card), 4.5, 0.01, "a float")
    W.advance(100)
    T.eq(ns.Rolls.TimeLeft(card), 0, "never below zero")
    T.eq(ns.Rolls.TimeLeft(nil), 0, "no card")
end)

T.it("a reload during a roll rebuilds the cards", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    W.addRoll(7, axeSpec(W), { silent = true }) -- the roll was open before the reload; nobody announced it
    T.eq(#ns.Rolls.Cards(), 0, "no card yet")
    W.activeRolls = { 7 }
    W.advance(25)
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 1, "one card")
    T.eq(#added, 1)
    local card = cards[1]
    T.eq(card.rollID, 7)
    T.eq(card.name, "Guardian's Dualblade")
    T.eq(card.status, "live")
    T.eq(card.duration, 60, "from C_Loot.GetLootRollDuration, in seconds")
    T.near(ns.Rolls.TimeLeft(card), 35, 0.01, "25 of the 60 seconds are gone")
    T.near(ns.Rolls.TimeLeft(card), G.GetLootRollTimeLeft(7) / 1000, 0.01, "as the game counts it")
    W.advance(5)
    T.near(ns.Rolls.TimeLeft(card), G.GetLootRollTimeLeft(7) / 1000, 0.01, "and as it goes on counting")
    W.fire("PLAYER_ENTERING_WORLD", false, false)
    T.eq(#ns.Rolls.Cards(), 1, "a roll that has its card gets no second one")
    T.eq(#added, 1)
end)

T.it("a roll the player has picked on is not rebuilt after a reload; the others are", function()
    local G, W, ns = T.load()
    W.addRoll(7, axeSpec(W))
    W.addRoll(8, axeSpec(W, { link = W.itemLink(AXE + 1, "Other axe") }))
    T.eq(ns.Rolls.Pick(ns.Rolls.Cards()[1], "greed"), true)
    T.eq(#W.activeRolls, 1, "the game no longer lists a roll the player chose on")
    T.eq(W.activeRolls[1], 8)
    -- The /reload: Tutti starts afresh, the game still has both rolls but lists only the open one.
    local G2, W2, ns2 = T.load({ setup = function(G2, W2)
        W2.rolls, W2.activeRolls = W.rolls, W.activeRolls
    end })
    local cards = ns2.Rolls.Cards()
    T.eq(#cards, 1, "one card after the reload")
    T.eq(cards[1].rollID, 8, "the open roll's")
    T.ok(ns2.Rolls.AwaitsMe(cards[1]))
end)

T.it("a rebuilt card takes its time from the game, else a minute", function()
    local G, W, ns = T.load()
    W.addRoll(7, axeSpec(W, { time = 30000 }), { silent = true })
    W.advance(10)
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(ns.Rolls.Cards()[1].duration, 30, "this roll lasts half a minute")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[1]), 20, 0.01)

    G.C_Loot.GetLootRollDuration = function() return nil end
    W.addRoll(8, axeSpec(W), { silent = true })
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(ns.Rolls.Cards()[2].duration, 60, "the game says nothing: a minute")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[2]), 60, 0.01)
end)

T.it("a rebuild skips what the game gives in the clear or not at all", function()
    local G, W, ns = T.load()
    W.addRoll(7, axeSpec(W), { silent = true })
    W.activeRolls = { T.secret(7), "x", 7 }
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(#ns.Rolls.Cards(), 1, "only the roll that can be read")
    G.GetActiveLootRollIDs = function() return T.secret(1) end
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    G.GetActiveLootRollIDs = function() return nil end
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    G.GetActiveLootRollIDs = nil
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(#ns.Rolls.Cards(), 1, "no error, nothing new")
end)

T.it("an item the client lets go of keeps the card's label and level (final review, item 10)", function()
    local G, W, ns = T.load()
    W.cacheItem(AXE, axeInfo())
    local card = newCard(W, ns, 7)
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
    local changed = listen(ns, "CARD_CHANGED")
    W.items[AXE] = nil -- the client's cache lets the item go, and says something about it
    W.fire("GET_ITEM_INFO_RECEIVED", AXE, false)
    T.eq(card.label, "Two-Hand Axe", "the label stays")
    T.eq(card.ilvl, 33, "and the level")
    T.eq(#changed, 0, "nothing changed")
end)

T.it("item info with no card to fill reads nothing (final review, item 10)", function()
    local G, W, ns = T.load()
    -- Every read of a game value asks ns.IsSecret (ns.Clear does, through ns, on every call).
    local reads, isSecret = 0, ns.IsSecret
    local function counting(...) reads = reads + 1; return isSecret(...) end
    ns.IsSecret = counting
    W.cacheItem(AXE, axeInfo())
    T.eq(reads, 0, "no card: the event is let go at once")
    ns.IsSecret = isSecret
    newCard(W, ns, 7)
    ns.IsSecret = counting
    W.cacheItem(AXE, axeInfo())
    T.ok(reads > 0, "with a card it is read")
end)

T.it("an uncached item fills in its label later", function()
    local G, W, ns = T.load()
    local changed = listen(ns, "CARD_CHANGED")
    local card = newCard(W, ns, 7) -- the axe is not in the client's cache
    T.eq(card.label, nil, "no label yet")
    T.eq(card.ilvl, nil)
    T.eq(card.name, "Guardian's Dualblade", "the roll's own name")
    T.eq(card.icon, 135348, "and its own icon")
    W.cacheItem(AXE, axeInfo())
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
    T.eq(#changed, 1, "one change")
    T.eq(changed[1].card, card)
    T.eq(changed[1].changes.item, true)
    T.eq(card.name, "Guardian's Dualblade", "the name stays the roll's")
    T.eq(card.icon, 135348)
    W.cacheItem(AXE)
    T.eq(#changed, 1, "the same answer again changes nothing")
    W.cacheItem(AXE + 1, axeInfo())
    T.eq(#changed, 1, "another item is not this card's business")
end)

T.it("every card of an item hears when it is cached", function()
    local G, W, ns = T.load()
    local first, second = newCard(W, ns, 1), newCard(W, ns, 2)
    local other = newCard(W, ns, 3)
    other.itemID = AXE + 1
    local changed = listen(ns, "CARD_CHANGED")
    W.cacheItem(AXE, axeInfo())
    T.eq(first.label, "Two-Hand Axe")
    T.eq(second.label, "Two-Hand Axe")
    T.eq(other.label, nil)
    T.eq(#changed, 2)
end)

T.it("cards are listed in arrival order and a list handed out stays as it was", function()
    local G, W, ns = T.load()
    local a = newCard(W, ns, 7)
    local held = ns.Rolls.Cards()
    local b, c = newCard(W, ns, 3), newCard(W, ns, 9)
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 3)
    T.eq(cards[1], a)
    T.eq(cards[2], b)
    T.eq(cards[3], c)
    T.eq(a.id .. b.id .. c.id, "123", "ids count up")
    T.eq(ns.Rolls.Get(2), b)
    T.eq(#held, 1, "the earlier list is a snapshot")
end)

T.it("AwaitsMe wants a roll, no pick, no end and a live card", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local function awaits() return ns.Rolls.AwaitsMe(card) end
    T.eq(awaits(), true)
    card.over = true
    T.eq(awaits(), false, "over")
    card.over = false
    card.mine = "pass"
    T.eq(awaits(), false, "chosen")
    card.mine = nil
    card.status = "decided"
    T.eq(awaits(), false, "decided")
    card.status = "ended"
    T.eq(awaits(), false, "ended")
    card.status = "live"
    card.rollID = nil
    T.eq(awaits(), false, "no roll")
    card.rollID = 7
    T.eq(awaits(), true, "and back again")
    T.eq(ns.Rolls.AwaitsMe(nil), false)
end)

T.it("Rows lists the group in party order and the player's row shows the pick", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local rows = ns.Rolls.Rows(card)
    T.eq(#rows, 5, "one row per member")
    local names, guids = {}, {}
    for i, row in ipairs(rows) do names[i], guids[i] = row.name, row.guid end
    T.eq(table.concat(names, ","), "Orlen,Brisé,Corvel,Kestrel,Ayla", "first names, the player last")
    T.eq(table.concat(guids, ","), "Player-1-0002,Player-1-0003,Player-1-0004,Player-1-0005,Player-1-00000001")
    T.eq(rows[1].class, "PALADIN")
    T.eq(rows[5].class, "DRUID")
    T.eq(rows[1].isPlayer, false)
    T.eq(rows[5].isPlayer, true)
    for i, row in ipairs(rows) do
        T.eq(row.state, "wait", "everyone is still choosing: row " .. i)
        T.eq(row.roll, nil)
        T.eq(row.isWinner, false)
    end
    ns.Rolls.Pick(card, "greed")
    rows = ns.Rolls.Rows(card)
    T.eq(rows[5].state, "greed", "the player's row shows the pick at once")
    T.eq(rows[1].state, "wait", "the others are unchanged")
    W.setGroup(nil)
    T.eq(#ns.Rolls.Rows(card), 1, "the rows follow the group")
    T.eq(ns.Rolls.Rows(card)[1].state, "greed")
end)

T.it("Forget removes a card and says so", function()
    local G, W, ns = T.load()
    local a, b, c = newCard(W, ns, 1), newCard(W, ns, 2), newCard(W, ns, 3)
    local removed = listen(ns, "CARD_REMOVED")
    local seenInList
    ns.Listen("CARD_REMOVED", function() seenInList = #ns.Rolls.Cards() end)
    ns.Rolls.Forget(b)
    T.eq(#removed, 1)
    T.eq(removed[1].card, b)
    T.eq(seenInList, 2, "gone from the list before the message")
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 2)
    T.eq(cards[1], a)
    T.eq(cards[2], c)
    T.eq(ns.Rolls.Get(b.id), nil)
    ns.Rolls.Forget(b)
    ns.Rolls.Forget(nil)
    T.eq(#removed, 1, "a card that is gone cannot go twice")
    local again = newCard(W, ns, 4)
    T.eq(again.id, 4, "an id is not given out twice")
end)

T.it("ForgetDecided removes decided and ended cards and keeps the live ones", function()
    local G, W, ns = T.load()
    local live, decided, ended = newCard(W, ns, 1), newCard(W, ns, 2), newCard(W, ns, 3)
    decided.status, ended.status = "decided", "ended"
    local removed = listen(ns, "CARD_REMOVED")
    ns.Rolls.ForgetDecided()
    T.eq(#removed, 2)
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 1)
    T.eq(cards[1], live)
    T.eq(ns.Rolls.Get(decided.id), nil)
    ns.Rolls.ForgetDecided()
    T.eq(#removed, 2, "nothing more to forget")
end)

-------------------------------------------------------------------------------
--  Demo cards (/tutti demo)
-------------------------------------------------------------------------------
local PLAYER_GUID = "Player-1-00000001" -- the fake's player

T.it("a demo card: Tutti's own id, a roll ID below 0, announced, and its pick never rolls", function()
    local G, W, ns = T.load()
    local real = newCard(W, ns, 1)
    local added = listen(ns, "CARD_ADDED")
    local card = ns.Rolls.AddDemo({ name = "Guardian's Dualblade", quality = 3, canNeed = false, canGreed = true,
        startedAt = G.GetTime(), duration = 60 })
    T.eq(card.id, real.id + 1, "the next id of Tutti's own count")
    T.eq(card.demo, true)
    T.ok(card.rollID < 0, "a roll ID no roll of the game has")
    T.eq(card.status, "live")
    T.eq(#added, 1, "announced as a roll is")
    T.eq(added[1].card, card)
    T.eq(ns.Rolls.Get(card.id), card)
    T.ok(ns.Rolls.AwaitsMe(card), "it shows the buttons")
    W.fire("CANCEL_LOOT_ROLL", 1)
    T.ok(real.over and not card.over, "the game's events reach its own rolls only")
    W.addRoll(-card.rollID, axeSpec(W))
    T.eq(#ns.Rolls.Cards(), 3, "a roll of the game with the card's number still gets its own card")
    T.eq(ns.Rolls.Pick(card, "greed"), true)
    T.eq(#W.rolled, 0, "the game never hears of its pick")
    W.advance(65.1)
    T.eq(card.status, "ended", "nobody decided it: it ends as a roll does")
end)

T.it("a demo card's news: picks, numbers and the decision, as the history would bring them", function()
    local G, W, ns = T.load()
    local card = ns.Rolls.AddDemo({
        name = "Cartilage Shapers", startedAt = G.GetTime(), duration = 60, history = true,
        members = {
            { guid = "Demo-1", first = "Orlen", class = "PALADIN" },
            { guid = PLAYER_GUID, first = "Ayla", class = "DRUID", isPlayer = true },
        },
        picks = {
            ["Demo-1"] = { state = "wait", name = "Orlen Brightmoor", class = "PALADIN", order = 1 },
            [PLAYER_GUID] = { state = "wait", name = "Ayla Brightwind", class = "DRUID", isSelf = true, order = 2 },
        },
    })
    local rows = ns.Rolls.Rows(card)
    T.eq(#rows, 2, "its own group: the made-up member and the player")
    T.eq(rows[1].name, "Orlen")
    T.eq(rows[1].class, "PALADIN")
    T.eq(rows[2].isPlayer, true, "in the order it brings")
    local changed, decided = listen(ns, "CARD_CHANGED"), listen(ns, "CARD_DECIDED")
    ns.Rolls.DemoNews(card, { ["Demo-1"] = { state = "need" } })
    T.eq(#changed, 1)
    T.eq(changed[1].changes.picks["Demo-1"], "state", "a new pick")
    T.eq(ns.Rolls.Rows(card)[1].state, "need")
    ns.Rolls.DemoNews(card, { ["Demo-1"] = { roll = 19 } })
    T.eq(changed[2].changes.picks["Demo-1"], "roll", "a number")
    T.eq(ns.Rolls.Rows(card)[1].roll, 19)
    ns.Rolls.DemoNews(card, { ["Demo-1"] = { roll = 19 } })
    T.eq(#changed, 2, "nothing new, nothing said")
    ns.Rolls.DemoNews(card, nil, "Demo-1")
    T.eq(card.status, "decided")
    T.eq(card.winner, "Demo-1")
    T.eq(#decided, 1)
    T.eq(changed[3].changes.decided, true)
    T.eq(ns.Rolls.Rows(card)[1].isWinner, true)
    ns.Rolls.DemoNews(card, nil, PLAYER_GUID)
    T.eq(card.winner, "Demo-1", "decided once")
    T.eq(#decided, 1)

    local passed = ns.Rolls.AddDemo({ name = "x", startedAt = G.GetTime(), duration = 60 })
    ns.Rolls.DemoNews(passed, nil, false)
    T.eq(passed.status, "decided")
    T.eq(passed.allPassed, true, "false: everyone passed")

    local real = newCard(W, ns, 5)
    ns.Rolls.DemoNews(real, { [PLAYER_GUID] = { state = "need" } }, PLAYER_GUID)
    T.eq(real.status, "live", "a real card takes no news from the demo")
    T.eq(next(real.picks), nil)
    real.members = { { guid = "Demo-1", first = "Orlen", class = "PALADIN" } }
    T.eq(ns.Rolls.Rows(real)[1].isPlayer, true, "and keeps the group's rows")
end)

T.it("no roll event of the game reaches a demo card: CANCEL_ALL_LOOT_ROLLS, nor a drop of the same item", function()
    local G, W, ns = T.load()
    local link = W.itemLink(AXE, "Guardian's Dualblade", 3)
    local demo = ns.Rolls.AddDemo({ link = link, itemID = AXE, name = "Guardian's Dualblade", quality = 3,
        canNeed = true, canGreed = true, startedAt = G.GetTime(), duration = 60 })
    local real = newCard(W, ns, 7)
    W.fire("CANCEL_ALL_LOOT_ROLLS")
    T.ok(real.over, "the player's part of the real roll is over")
    T.eq(demo.over, false, "the demo card's is not")
    T.ok(ns.Rolls.AwaitsMe(demo), "its buttons stay")
    -- The history's drop of the same item: the demo card is older and would come first, but it is no roll of the game.
    W.setDrop(9, 1, { lootListKey = 1, itemHyperlink = link,
        playerRollState = G.Enum.EncounterLootDropRollState.NoRoll, isTied = false, allPassed = false,
        rollInfos = {}, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 })
    T.eq(demo.dropKey, nil, "the drop never joins the demo card")
    T.eq(real.dropKey, "9:1", "it goes to the real roll")
end)
