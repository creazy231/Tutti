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

-- Starts a roll for the axe and hands back its card (the last one).
local function newCard(W, ns, rollID, over)
    W.addRoll(rollID, axeSpec(W, over))
    local cards = ns.Rolls.Cards()
    return cards[#cards]
end

-- A roll for another item (its link is the only difference), so it never competes with the axe.
local function otherSpec(W, over)
    local spec = axeSpec(W, { link = W.itemLink(AXE + 1, "Other axe") })
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

-- Every message of one kind, in order: { card, changes }.
local function listen(ns, msg)
    local seen = {}
    ns.Listen(msg, function(card, changes) seen[#seen + 1] = { card = card, changes = changes } end)
    return seen
end

-- The party the other tests use, in party1..party4; the player is the fake's Ayla Brightwind.
local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- The same five as the history names them: full name, GUID, class file.
local ORLEN = { "Orlen Brightmoor", "Player-1-0002", "PALADIN" }
local BRISE = { "Brisé Tidewater", "Player-1-0003", "SHAMAN" }
local CORVEL = { "Corvel Duskmantle", "Player-1-0004", "MAGE" }
local KESTREL = { "Kestrel Ironmark", "Player-1-0005", "WARRIOR" }
local AYLA = { "Ayla Brightwind", "Player-1-00000001", "DRUID", isSelf = true }

-- One EncounterLootDropRollInfo.
local function rollInfo(who, state, roll, isWinner)
    return { playerName = who[1], playerGUID = who[2], playerClass = who[3], isSelf = who.isSelf == true,
        state = state, roll = roll, isWinner = isWinner == true }
end

-- An EncounterLootDropInfo for the axe as the game hands it out, started now and lasting a minute (its
-- times are milliseconds). `rolls` are its rollInfos; `over` replaces or adds fields (a nil in it adds
-- nothing: take a field away on the result).
local function dropInfo(G, W, rolls, over)
    local info = { lootListKey = 7, itemHyperlink = W.itemLink(AXE, "Guardian's Dualblade", 3),
        playerRollState = G.Enum.EncounterLootDropRollState.NoRoll, isTied = false, allPassed = false,
        rollInfos = rolls or {}, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 }
    for k, v in pairs(over or {}) do info[k] = v end
    return info
end

-- A drop the game has decided: `who` won with `roll`; without `rolls` theirs is the only one.
local function won(G, W, who, roll, rolls, over)
    local need = G.Enum.EncounterLootDropRollState.NeedMainSpec
    local info = dropInfo(G, W, rolls or { rollInfo(who, need, roll, true) }, over)
    info.winner = rollInfo(who, need, roll, true)
    return info
end

-- One field of every row as a comma-joined string, so a failure shows the whole list.
local function column(rows, key)
    local out = {}
    for i, row in ipairs(rows) do out[i] = tostring(row[key]) end
    return table.concat(out, ",")
end

local function size(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- A secret string or number in the game still has type "string" or "number", so the fake's userdata
-- secrets prove little about a check that stops at type(). Here plain values play secrets by being
-- named in `hidden`.
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

-- A game that records errors instead of raising them (the fake's default handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

-- Counts the calls that reach C_LootHistory.GetSortedInfoForDrop.
local function countCalls(G)
    local calls = { n = 0 }
    local real = G.C_LootHistory.GetSortedInfoForDrop
    G.C_LootHistory.GetSortedInfoForDrop = function(...)
        calls.n = calls.n + 1
        return real(...)
    end
    return calls
end

T.it("the history attaches to its roll and fills every pick", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local added, changed = listen(ns, "CARD_ADDED"), listen(ns, "CARD_CHANGED")
    T.eq(card.history, false, "no history yet")
    T.eq(column(ns.Rolls.Rows(card), "state"), "wait,wait,wait,wait,wait", "before it, everyone is choosing")
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Greed), rollInfo(CORVEL, ST.Pass),
        rollInfo(KESTREL, ST.NoRoll), rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(#ns.Rolls.Cards(), 1, "the drop joined the player's card")
    T.eq(#added, 0, "no card was added")
    T.eq(card.encounterID, 9)
    T.eq(card.lootListKey, 7)
    T.eq(card.dropKey, "9:7")
    T.eq(card.history, true)
    T.eq(card.tied, false)
    T.eq(card.status, "live", "nobody has won")
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "name"), "Orlen,Brisé,Corvel,Kestrel,Ayla", "party order, first names")
    T.eq(column(rows, "guid"), "Player-1-0002,Player-1-0003,Player-1-0004,Player-1-0005,Player-1-00000001")
    T.eq(column(rows, "class"), "PALADIN,SHAMAN,MAGE,WARRIOR,DRUID")
    T.eq(column(rows, "isPlayer"), "false,false,false,false,true")
    T.eq(column(rows, "state"), "need,greed,pass,wait,wait")
    T.eq(column(rows, "roll"), "nil,nil,nil,nil,nil", "no numbers yet")
    T.eq(column(rows, "isWinner"), "false,false,false,false,false")
    T.eq(#changed, 1, "one message")
    T.eq(changed[1].card, card)
    T.eq(size(changed[1].changes.picks), 5, "five picks arrived")
    for _, who in ipairs({ ORLEN, BRISE, CORVEL, KESTREL, AYLA }) do
        T.eq(changed[1].changes.picks[who[2]], "state", who[1] .. "'s pick is new")
    end
    T.eq(changed[1].changes.decided, nil)
end)

T.it("every history state maps", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedOffSpec), rollInfo(BRISE, ST.Transmog), rollInfo(CORVEL, ST.Greed),
        rollInfo(KESTREL, ST.NoRoll), rollInfo(AYLA, ST.Pass),
    }))
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,transmog,greed,wait,pass", "off-spec is Need, NoRoll is choosing")
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Transmog), rollInfo(CORVEL, ST.Greed),
        rollInfo(KESTREL, ST.NoRoll), rollInfo(AYLA, ST.Pass),
    }))
    T.eq(ns.Rolls.Rows(card)[1].state, "need", "main-spec Need is Need too")
    T.eq(card.picks[ORLEN[2]].state, "need")
    -- A number the game has no state for leaves what was.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, 42), rollInfo(KESTREL, 42) }))
    T.eq(ns.Rolls.Rows(card)[1].state, "need", "a state this client does not know changes nothing")
    T.eq(ns.Rolls.Rows(card)[4].state, "wait", "and one that is new is choosing")
end)

T.it("a member missing from the history is out", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    T.eq(column(ns.Rolls.Rows(card), "state"), "wait,wait,wait,wait,wait", "before the history: choosing, not out")
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) }))
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,out,out,out,wait", "the three the history leaves out are out")
    T.eq(column(ns.Rolls.Rows(card), "roll"), "nil,nil,nil,nil,nil")
    -- One of them turns up in a later update: choosing now.
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(KESTREL, ST.NoRoll), rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,out,out,wait,wait")
end)

T.it("numbers arrive: changes.picks marks them 'roll'", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    local function everyone(orlenRoll, aylaRoll, briseState)
        return dropInfo(G, W, {
            rollInfo(ORLEN, ST.NeedMainSpec, orlenRoll), rollInfo(BRISE, briseState or ST.Greed),
            rollInfo(CORVEL, ST.Greed), rollInfo(KESTREL, ST.Pass), rollInfo(AYLA, ST.NeedMainSpec, aylaRoll),
        })
    end
    W.setDrop(9, 7, everyone(nil, nil))
    T.eq(size(changed[1].changes.picks), 5)
    W.setDrop(9, 7, everyone(73, 41)) -- the two Needs rolled; Greed has no number while a Need is in
    T.eq(#changed, 2)
    local picks = changed[2].changes.picks
    T.eq(size(picks), 2, "only the two numbers changed")
    T.eq(picks[ORLEN[2]], "roll")
    T.eq(picks[AYLA[2]], "roll")
    T.eq(column(ns.Rolls.Rows(card), "roll"), "73,nil,nil,nil,41")
    -- One number moves, nothing else does.
    W.setDrop(9, 7, everyone(73, 42))
    T.eq(size(changed[3].changes.picks), 1)
    T.eq(changed[3].changes.picks[AYLA[2]], "roll")
    -- A pick that changes its state is a 'state'.
    W.setDrop(9, 7, everyone(73, 42, ST.Pass))
    T.eq(size(changed[4].changes.picks), 1)
    T.eq(changed[4].changes.picks[BRISE[2]], "state")
    -- A new pick that arrives with its number is a 'state' first: the pick is what is new.
    local other = newCard(W, ns, 8, otherSpec(W))
    W.setDrop(9, 8, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec, 12) },
        { lootListKey = 8, itemHyperlink = other.link }))
    T.eq(changed[5].changes.picks[ORLEN[2]], "state")
    T.eq(ns.Rolls.Rows(other)[1].roll, 12, "the number is on the row all the same")
end)

T.it("a winner decides the card once", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local decided, changed = listen(ns, "CARD_DECIDED"), listen(ns, "CARD_CHANGED")
    local function rolls()
        return {
            rollInfo(ORLEN, ST.NeedMainSpec, 73, true), rollInfo(AYLA, ST.NeedMainSpec, 41), rollInfo(BRISE, ST.Greed),
            rollInfo(CORVEL, ST.Greed), rollInfo(KESTREL, ST.Pass),
        }
    end
    W.setDrop(9, 7, won(G, W, ORLEN, 73, rolls()))
    T.eq(card.status, "decided")
    T.eq(card.winner, ORLEN[2], "the winner's GUID")
    T.eq(card.allPassed, false)
    T.eq(card.decidedAt, W.clock, "when it was decided")
    T.eq(#decided, 1, "CARD_DECIDED fired")
    T.eq(decided[1].card, card)
    T.eq(#changed, 1)
    T.eq(changed[1].changes.decided, true)
    T.eq(size(changed[1].changes.picks), 5, "the picks come in the same message")
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "isWinner"), "true,false,false,false,false")
    T.eq(column(rows, "roll"), "73,nil,nil,nil,41")
    T.eq(ns.Rolls.AwaitsMe(card), false, "decided: no more buttons")
    -- A later update (a number turns up for a Greed) changes the picks and nothing about the decision.
    W.advance(3)
    local again = rolls()
    again[3].roll = 12 -- Brisé
    W.setDrop(9, 7, won(G, W, ORLEN, 73, again))
    T.eq(#decided, 1, "decided once")
    T.eq(card.decidedAt, W.clock - 3, "the time of the decision stays")
    T.eq(card.winner, ORLEN[2])
    T.eq(#changed, 2)
    T.eq(changed[2].changes.decided, nil, "the second message is no decision")
    T.eq(changed[2].changes.picks[BRISE[2]], "roll")
    -- The same news again changes nothing at all.
    W.setDrop(9, 7, won(G, W, ORLEN, 73, again))
    T.eq(#changed, 2, "no message for an update that says nothing new")
    T.eq(#decided, 1)
end)

T.it("everyone passed decides without a winner", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local decided, changed = listen(ns, "CARD_DECIDED"), listen(ns, "CARD_CHANGED")
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.Pass), rollInfo(BRISE, ST.Pass), rollInfo(CORVEL, ST.Pass), rollInfo(KESTREL, ST.Pass),
        rollInfo(AYLA, ST.Pass),
    }, { allPassed = true, playerRollState = ST.Pass }))
    T.eq(card.status, "decided")
    T.eq(card.allPassed, true)
    T.eq(card.winner, nil, "no winner")
    T.eq(card.decidedAt, W.clock)
    T.eq(#decided, 1)
    T.eq(changed[1].changes.decided, true)
    T.eq(column(ns.Rolls.Rows(card), "isWinner"), "false,false,false,false,false", "no crown")
    T.eq(column(ns.Rolls.Rows(card), "state"), "pass,pass,pass,pass,pass")
end)

T.it("the player's row: history first, then the optimistic pick", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local function me() return ns.Rolls.Rows(card)[5] end
    T.eq(me().isPlayer, true)
    T.eq(me().state, "wait", "nothing known: choosing")
    ns.Rolls.Pick(card, "greed")
    T.eq(me().state, "greed", "the pick shows before the history knows")
    -- The history has no entry for the player: the pick stays.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec) }))
    T.eq(me().state, "greed", "no entry for the player: the pick on the card")
    -- The history has one: it speaks first.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NeedMainSpec, 55) }))
    T.eq(me().state, "need", "the history's entry wins over the pick")
    T.eq(me().roll, 55)
    T.eq(card.mine, "greed", "the card's own pick is left as it was")

    -- A card with no pick and no entry stays choosing, history or not.
    local G2, W2, ns2 = T.load()
    W2.setGroup(party())
    local plain = newCard(W2, ns2, 7)
    W2.setDrop(9, 7, dropInfo(G2, W2, { rollInfo(ORLEN, G2.Enum.EncounterLootDropRollState.Greed) }))
    T.eq(ns2.Rolls.Rows(plain)[5].state, "wait", "otherwise choosing")
end)

T.it("the history corrects a pick the game never made (R16's timeout)", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    ns.Rolls.Pick(card, "need")
    W.fire("CONFIRM_LOOT_ROLL", 7, 1) -- Blizzard's bind dialog opens and stays open
    T.eq(ns.Rolls.Rows(card)[5].state, "wait", "the roll is not made yet")
    W.fire("CANCEL_LOOT_ROLL", 7) -- the time runs out; Tutti takes the pending pick for the player's
    T.eq(card.mine, "need")
    T.eq(ns.Rolls.Rows(card)[5].state, "need", "until the history says otherwise")
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.Pass) }))
    T.eq(ns.Rolls.Rows(card)[5].state, "pass", "the history's own entry for the player wins")
end)

T.it("two copies of one item match two cards", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local first, second = newCard(W, ns, 7), newCard(W, ns, 8) -- the same link twice
    ns.Rolls.Pick(second, "greed")
    -- The first drop the history shows is the one the player chose Greed on: the second card's.
    W.setDrop(9, 1, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.Greed) },
        { lootListKey = 1, playerRollState = ST.Greed }))
    T.eq(second.dropKey, "9:1", "the pick finds its own card")
    T.eq(first.dropKey, nil, "the older card is not taken for it")
    T.eq(ns.Rolls.Rows(second)[5].state, "greed")
    -- The other drop, where the player has not chosen, is the first card's.
    W.setDrop(9, 2, dropInfo(G, W, { rollInfo(ORLEN, ST.Pass), rollInfo(AYLA, ST.NoRoll) },
        { lootListKey = 2, playerRollState = ST.NoRoll }))
    T.eq(first.dropKey, "9:2")
    T.eq(#ns.Rolls.Cards(), 2, "no third card")
    T.eq(ns.Rolls.Rows(first)[1].state, "pass", "each card has its own drop's picks")
    T.eq(ns.Rolls.Rows(second)[1].state, "need")
    -- Later news of either drop goes where it belongs.
    W.setDrop(9, 1, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec, 80), rollInfo(AYLA, ST.Greed) },
        { lootListKey = 1, playerRollState = ST.Greed }))
    T.eq(ns.Rolls.Rows(second)[1].roll, 80)
    T.eq(ns.Rolls.Rows(first)[1].roll, nil)
end)

T.it("with nothing to tell the copies apart the oldest card takes the drop", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local first, second, third, fourth = newCard(W, ns, 7), newCard(W, ns, 8), newCard(W, ns, 9), newCard(W, ns, 10)
    ns.Rolls.Pick(fourth, "need")
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, playerRollState = ST.NoRoll }))
    T.eq(first.dropKey, "9:1", "nobody has chosen: the oldest")
    -- A drop that says Pass fits no card (the pick on the fourth is Need): the oldest free one again.
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2, playerRollState = ST.Pass }))
    T.eq(second.dropKey, "9:2", "no card matches: the oldest")
    -- Off-spec Need is Need: the card with the Need on it, though the third is older.
    W.setDrop(9, 3, dropInfo(G, W, {}, { lootListKey = 3, playerRollState = ST.NeedOffSpec }))
    T.eq(fourth.dropKey, "9:3", "the pick on the card matches the player's state in the game")
    T.eq(third.dropKey, nil)
    W.setDrop(9, 4, dropInfo(G, W, {}, { lootListKey = 4, playerRollState = ST.NoRoll }))
    T.eq(third.dropKey, "9:4")
    T.eq(#ns.Rolls.Cards(), 4, "four drops, four cards")
end)

T.it("the link decides first, the item second", function()
    local G, W, ns = T.load()
    local plain = W.itemLink(AXE, "Guardian's Dualblade", 3)
    local bonus = "|cnIQ3:|Hitem:18000::::::::60:1484::1::1:28:4512:::::|h[Guardian's Dualblade]|h|r"
    local variant = "|cnIQ3:|Hitem:18000::::::::60:1484::1::1:28:9999:::::|h[Guardian's Dualblade]|h|r"
    local a = newCard(W, ns, 7, { link = plain })
    local b = newCard(W, ns, 8, { link = bonus })
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, itemHyperlink = bonus }))
    T.eq(b.dropKey, "9:1", "the same link, though the other card is older")
    T.eq(a.dropKey, nil)
    -- A link that neither card has: the same item is enough.
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2, itemHyperlink = variant }))
    T.eq(a.dropKey, "9:2", "the same item: the card still free")
    T.eq(#ns.Rolls.Cards(), 2)
    -- Another item altogether is a drop of its own.
    W.setDrop(9, 3, dropInfo(G, W, {}, { lootListKey = 3, itemHyperlink = W.itemLink(AXE + 1, "Other axe") }))
    T.eq(#ns.Rolls.Cards(), 3, "a drop with no card to join gets its own")
    T.eq(ns.Rolls.Cards()[3].dropKey, "9:3")
end)

T.it("a card with the very link wins over a card whose pick fits better", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local plain = W.itemLink(AXE, "Guardian's Dualblade", 3)
    local bonus = "|cnIQ3:|Hitem:18000::::::::60:1484::1::1:28:4512:::::|h[Guardian's Dualblade]|h|r"
    local older = newCard(W, ns, 7, { link = plain })
    local newer = newCard(W, ns, 8, { link = bonus })
    ns.Rolls.Pick(older, "greed")
    -- The player's Greed fits the older card, the link fits the newer one: the link names the drop's card.
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, itemHyperlink = bonus, playerRollState = ST.Greed }))
    T.eq(newer.dropKey, "9:1")
    T.eq(older.dropKey, nil)
end)

T.it("a link that names no item still matches itself", function()
    local G, W, ns = T.load()
    local pet = "|cff0070dd|Hbattlepet:1:2:3|h[Odd thing]|h|r"
    local card = newCard(W, ns, 7, { link = pet })
    T.eq(card.itemID, nil)
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, itemHyperlink = pet }))
    T.eq(card.dropKey, "9:1", "the same string is the same link")
    T.eq(#ns.Rolls.Cards(), 1)
end)

T.it("history first, roll second: one card", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local added, changed = listen(ns, "CARD_ADDED"), listen(ns, "CARD_CHANGED")
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Greed), rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(#ns.Rolls.Cards(), 1, "the drop has a card")
    local card = ns.Rolls.Cards()[1]
    T.eq(card.rollID, nil, "no roll yet")
    T.eq(ns.Rolls.AwaitsMe(card), false)
    T.eq(#added, 1)
    local before = #changed

    W.addRoll(7, axeSpec(W, { canNeed = false, reasonNeed = 1, bop = false }))
    T.eq(#ns.Rolls.Cards(), 1, "one card, not two")
    T.eq(ns.Rolls.Cards()[1], card, "the same card")
    T.eq(#added, 1, "announced once")
    T.eq(card.rollID, 7, "the roll joined it")
    T.eq(card.over, false, "the player's part is open")
    T.eq(card.mine, nil)
    T.eq(card.status, "live")
    T.eq(ns.Rolls.AwaitsMe(card), true, "the buttons are on")
    T.eq(card.canNeed, false, "what the roll says about the choices")
    T.eq(card.reasonNeed, G.LOOT_ROLL_INELIGIBLE_REASON1)
    T.eq(card.bop, false)
    T.eq(card.dropKey, "9:7", "it keeps its drop")
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,greed,out,out,wait", "and the picks the history gave it")
    T.near(ns.Rolls.TimeLeft(card), 60, 0.01, "the countdown is the roll's")
    T.eq(#changed, before + 1, "the join is announced")
    T.eq(changed[#changed].card, card)
    T.eq(changed[#changed].changes.over, true, "the player's part opened")
    T.eq(changed[#changed].changes.item, true)
    T.eq(ns.Rolls.Pick(card, "pass"), true)
    T.eq(W.rolled[1][1], 7, "and the pick goes out for this roll")
    -- The same roll again is no second join and no second card.
    W.fire("START_LOOT_ROLL", 7, 60000)
    T.eq(#ns.Rolls.Cards(), 1)
    -- Cards count: the roll that joined used no number.
    T.eq(newCard(W, ns, 8, otherSpec(W)).id, 2, "ids count cards")
end)

T.it("two drops first, two rolls second: each roll joins one card, in order", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1 }))
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2 }))
    local one, two = ns.Rolls.Cards()[1], ns.Rolls.Cards()[2]
    T.eq(#ns.Rolls.Cards(), 2, "a card for each drop")
    W.addRoll(7, axeSpec(W))
    T.eq(one.rollID, 7, "the first roll joins the older card")
    T.eq(two.rollID, nil)
    W.addRoll(8, axeSpec(W))
    T.eq(two.rollID, 8, "the second joins the next")
    T.eq(#ns.Rolls.Cards(), 2, "no card was made for a roll")
    T.eq(#added, 2)
    W.addRoll(9, axeSpec(W))
    T.eq(#ns.Rolls.Cards(), 3, "a third roll has no drop waiting: its own card")
    T.eq(ns.Rolls.Cards()[3].dropKey, nil)
end)

T.it("a click shows at once while the history still says choosing", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local function me() return ns.Rolls.Rows(card)[5] end
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) }))
    T.eq(me().state, "wait", "the history lists the player as choosing and they have not clicked")
    ns.Rolls.Pick(card, "need")
    T.eq(me().state, "need", "the click shows at once")
    -- An update the server sent before it took the click still says NoRoll for the player: the click stays.
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Greed), rollInfo(CORVEL, ST.Pass),
        rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(me().state, "need", "a history that has not caught up does not take the click back")
    T.eq(me().roll, nil)
    -- The history catches up: its own entry, with the number.
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec, 40), rollInfo(AYLA, ST.NeedMainSpec, 55), rollInfo(BRISE, ST.Greed),
    }))
    T.eq(me().state, "need")
    T.eq(me().roll, 55)
    -- A decided entry that says something else wins over the click: the pick was never made.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec, 40), rollInfo(AYLA, ST.Pass) }))
    T.eq(me().state, "pass", "the history's decided entry is the truth")
    T.eq(me().roll, nil)
end)

T.it("while Blizzard's bind dialog is open the player's row is choosing", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) }))
    ns.Rolls.Pick(card, "need")
    W.fire("CONFIRM_LOOT_ROLL", 7, 1) -- the roll is not made until the player accepts
    T.eq(card.mine, nil)
    T.eq(ns.Rolls.Rows(card)[5].state, "wait", "no click on the card, the history says choosing")
    W.fire("CANCEL_LOOT_ROLL", 7) -- accepted: the game took the roll
    T.eq(ns.Rolls.Rows(card)[5].state, "need")
end)

T.it("a player who isn't in the roll is out", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    -- A drop the player has no roll on, and the history does not list them.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Greed) }))
    local card = ns.Rolls.Cards()[1]
    T.eq(card.rollID, nil)
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "state"), "need,greed,out,out,out", "the player is out like anyone the history leaves out")
    T.eq(rows[5].isPlayer, true)
    -- Their roll starts after all (the history came first): now they are in it.
    W.addRoll(7, axeSpec(W))
    T.eq(card.rollID, 7)
    T.eq(ns.Rolls.Rows(card)[5].state, "wait", "a roll for the player makes them part of it: choosing")
    ns.Rolls.Pick(card, "greed")
    T.eq(ns.Rolls.Rows(card)[5].state, "greed")
    -- A history that lists the player as choosing is the same.
    W.setDrop(9, 8, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) },
        { lootListKey = 8, itemHyperlink = W.itemLink(AXE + 1, "Other axe") }))
    T.eq(ns.Rolls.Rows(ns.Rolls.Cards()[2])[5].state, "wait", "listed as choosing: choosing")
end)

T.it("nobody is choosing after the end", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local gone = { "Baz Qux", "Player-9-0002", "ROGUE" } -- someone the group no longer has
    local card = newCard(W, ns, 7)
    local function undecided()
        return dropInfo(G, W, {
            rollInfo(ORLEN, ST.NeedMainSpec, 73), rollInfo(BRISE, ST.Greed), rollInfo(CORVEL, ST.NoRoll),
            rollInfo(AYLA, ST.NoRoll), rollInfo(gone, ST.NoRoll),
        })
    end
    W.setDrop(9, 7, undecided())
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,greed,wait,out,wait,wait", "while it goes on they are choosing")
    -- Decided: whoever never chose, the player and the leaver included, is out.
    local info = undecided()
    info.winner = rollInfo(ORLEN, ST.NeedMainSpec, 73, true)
    W.setDrop(9, 7, info)
    T.eq(card.status, "decided")
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "state"), "need,greed,out,out,out,out")
    T.eq(rows[6].name, "Baz")
    T.eq(rows[5].isPlayer, true)

    -- Ended: the same, and the player's own click stays.
    local G2, W2, ns2 = T.load()
    W2.setGroup(party())
    local ended = newCard(W2, ns2, 7)
    ns2.Rolls.Pick(ended, "greed")
    W2.setDrop(9, 7, dropInfo(G2, W2, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(CORVEL, ST.NoRoll), rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(column(ns2.Rolls.Rows(ended), "state"), "need,out,wait,out,greed", "the click is the player's")
    W2.advance(66)
    T.eq(ended.status, "ended")
    T.eq(column(ns2.Rolls.Rows(ended), "state"), "need,out,out,out,greed", "ended: Corvel is out, the click stays")

    -- An ended card that never had the history: nobody known is choosing either.
    local G3, W3, ns3 = T.load()
    W3.setGroup(party())
    local bare = newCard(W3, ns3, 7)
    T.eq(column(ns3.Rolls.Rows(bare), "state"), "wait,wait,wait,wait,wait")
    W3.advance(66)
    T.eq(bare.status, "ended")
    T.eq(column(ns3.Rolls.Rows(bare), "state"), "out,out,out,out,out")
end)

T.it("item info that arrives later fills in a card the history made", function()
    local G, W, ns = T.load()
    -- A link whose text names the item wrongly and whose colour is no quality code: the cache corrects both.
    W.setDrop(9, 7, dropInfo(G, W, {}, { itemHyperlink = W.itemLink(AXE, "Name in the link", 3) }))
    local card = ns.Rolls.Cards()[1]
    T.eq(card.name, "Name in the link", "the link's own text, for now")
    T.eq(card.quality, nil)
    T.eq(card.icon, nil)
    T.eq(card.label, nil)
    T.eq(card.ilvl, nil)
    local changed = listen(ns, "CARD_CHANGED")
    W.cacheItem(AXE, axeInfo())
    T.eq(card.name, "Guardian's Dualblade", "the client's name")
    T.eq(card.quality, 3)
    T.eq(card.icon, 135348)
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
    T.eq(#changed, 1, "one message")
    T.eq(changed[1].card, card)
    T.eq(changed[1].changes.item, true)
end)

T.it("a roll does not join a card the history already decided", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setDrop(9, 8, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec) }, { lootListKey = 8 }))
    local card = ns.Rolls.Cards()[1]
    W.setDrop(9, 8, won(G, W, ORLEN, 70, nil, { lootListKey = 8 }))
    T.eq(card.status, "decided")
    local roll = newCard(W, ns, 7)
    T.eq(#ns.Rolls.Cards(), 2, "a new roll for the item is a new card")
    T.ok(roll ~= card)
    T.eq(roll.rollID, 7)
    T.eq(card.rollID, nil)
end)

T.it("a fresh drop without a roll for the player gets a card without buttons", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    W.items[AXE] = axeInfo()
    local trail = {}
    ns.Listen("CARD_ADDED", function() trail[#trail + 1] = "added" end)
    ns.Listen("CARD_CHANGED", function() trail[#trail + 1] = "changed" end)
    local link = W.itemLink(AXE, "Guardian's Dualblade", 3)
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(BRISE, ST.Greed), rollInfo(AYLA, ST.NoRoll),
    }))
    T.eq(#ns.Rolls.Cards(), 1)
    local card = ns.Rolls.Cards()[1]
    T.eq(ns.Rolls.AwaitsMe(card), false, "nothing for the player to choose")
    T.eq(ns.Rolls.Pick(card, "pass"), false)
    T.eq(#W.rolled, 0)
    T.eq(card.rollID, nil)
    T.eq(card.over, true)
    T.eq(card.status, "live")
    T.eq(card.history, true)
    T.eq(card.dropKey, "9:7")
    T.eq(card.encounterID, 9)
    T.eq(card.lootListKey, 7)
    T.eq(card.link, link)
    T.eq(card.itemID, AXE)
    T.eq(card.name, "Guardian's Dualblade")
    T.eq(card.quality, 3)
    T.eq(card.icon, 135348)
    T.eq(card.count, 1)
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
    T.eq(card.canNeed, false)
    T.eq(card.canGreed, false)
    T.eq(card.canTransmog, false)
    T.eq(card.mine, nil)
    T.near(ns.Rolls.TimeLeft(card), 60, 0.01, "the drop started now and lasts a minute")
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,greed,out,out,wait")
    T.eq(table.concat(trail, ","), "added,changed", "the card is announced before its picks")
    -- Its start comes from the game's own clock: a drop that began 20 s ago has 40 s left.
    W.setDrop(9, 8, dropInfo(G, W, {}, { lootListKey = 8, startTime = G.C_LootHistory.GetLootHistoryTime() - 20000 }))
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[2]), 40, 0.01)
end)

T.it("a drop the client has not cached is named by its link and filled in later", function()
    local G, W, ns = T.load()
    local link = "|cnIQ4:|Hitem:18000::::::::60:::::::|h[Guardian's Dualblade]|h|r" -- as Forever writes a link
    W.setDrop(9, 7, dropInfo(G, W, {}, { itemHyperlink = link }))
    local card = ns.Rolls.Cards()[1]
    T.eq(card.name, "Guardian's Dualblade", "the link has the name")
    T.eq(card.quality, 4, "and the colour")
    T.eq(card.icon, nil, "the icon needs the item")
    T.eq(card.label, nil)
    T.eq(card.ilvl, nil)
    local changed = listen(ns, "CARD_CHANGED")
    W.cacheItem(AXE, axeInfo())
    T.eq(card.icon, 135348)
    T.eq(card.label, "Two-Hand Axe")
    T.eq(card.ilvl, 33)
    T.eq(card.quality, 3, "the client's word")
    T.eq(card.name, "Guardian's Dualblade")
    T.eq(#changed, 1)
    T.eq(changed[1].changes.item, true)
    W.cacheItem(AXE)
    T.eq(#changed, 1, "the same answer again changes nothing")
    -- A card made by a roll keeps the roll's own name and icon whatever the cache says.
    local rolled = newCard(W, ns, 8, otherSpec(W, { name = "The roll's name", texture = 111 }))
    W.cacheItem(AXE + 1, { name = "The cache's name", quality = 2, texture = 222 })
    T.eq(rolled.name, "The roll's name")
    T.eq(rolled.icon, 111)
end)

T.it("drops decided before Tutti saw them are ignored", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local added = listen(ns, "CARD_ADDED")
    W.setDrop(9, 1, won(G, W, ORLEN, 70, nil, { lootListKey = 1 }))
    W.setDrop(9, 2, dropInfo(G, W, { rollInfo(ORLEN, ST.Pass) }, { lootListKey = 2, allPassed = true }))
    T.eq(#ns.Rolls.Cards(), 0, "no card for a drop that was over already")
    T.eq(#added, 0)
    -- A card that waits for the history takes the same news: that is its decision.
    local card = newCard(W, ns, 7)
    W.setDrop(9, 3, won(G, W, ORLEN, 70, nil, { lootListKey = 3 }))
    T.eq(card.status, "decided", "a roll the player has is decided by it")
    T.eq(#ns.Rolls.Cards(), 1)
end)

T.it("stale drops are ignored", function()
    local G, W, ns = T.load()
    local added = listen(ns, "CARD_ADDED")
    local start = G.C_LootHistory.GetLootHistoryTime()
    W.historyTime = start + 61000 -- a minute and a second on
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, startTime = start, duration = 60000 }))
    T.eq(#ns.Rolls.Cards(), 0, "its time is up")
    W.historyTime = start + 60000
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2, startTime = start, duration = 60000 }))
    T.eq(#ns.Rolls.Cards(), 0, "up exactly now is up")
    W.historyTime = start + 59000
    W.setDrop(9, 3, dropInfo(G, W, {}, { lootListKey = 3, startTime = start, duration = 60000 }))
    T.eq(#ns.Rolls.Cards(), 1, "a second to go is not stale")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[1]), 1, 0.01, "and the card has that second")
    -- No duration, no staleness: the game does not say how long the roll lasts.
    W.historyTime = start + 999999
    W.setDrop(9, 4, dropInfo(G, W, {}, { lootListKey = 4, startTime = start, duration = 0 }))
    T.eq(#ns.Rolls.Cards(), 2)
    T.eq(ns.Rolls.Cards()[2].duration, 60, "a minute")
    T.eq(#added, 2)
end)

T.it("a drop's age is a share of its duration, whatever unit the history keeps", function()
    local G, W, ns = T.load()
    -- Milliseconds, on a clock of their own: 20 s of a minute gone.
    local now = G.C_LootHistory.GetLootHistoryTime()
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, startTime = now - 20000, duration = 60000 }))
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[1]), 40, 0.01)
    -- The same age in seconds, on a clock that has nothing to do with GetTime(): the history's start, clock and
    -- duration are read against each other and never against Tutti's seconds, so the card counts the same.
    W.historyTime = 5000
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2, startTime = 4980, duration = 60 }))
    T.eq(#ns.Rolls.Cards(), 2)
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[2]), 40, 0.01)
    T.eq(ns.Rolls.Cards()[2].duration, 60, "a card counts a minute: the game's own length is never turned into seconds")
    -- Out of time is out of time in either unit.
    W.setDrop(9, 3, dropInfo(G, W, {}, { lootListKey = 3, startTime = 4940, duration = 60 }))
    T.eq(#ns.Rolls.Cards(), 2, "a drop whose minute is up (60 of 60) is stale")
    W.setDrop(9, 4, dropInfo(G, W, {}, { lootListKey = 4, startTime = 4941, duration = 60 }))
    T.eq(#ns.Rolls.Cards(), 3, "one second to go is not")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[3]), 1, 0.01)
    -- A roll that lasts half a minute is a share of its own length, but the card has no seconds for it.
    W.historyTime = 800000
    W.setDrop(9, 5, dropInfo(G, W, {}, { lootListKey = 5, startTime = 795000, duration = 30000 }))
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[4]), 50, 0.01, "5 s of 30 gone: a sixth of the card's minute")
end)

T.it("a drop whose times cannot be read is not stale", function()
    local G, W, ns = T.load()
    local start = G.C_LootHistory.GetLootHistoryTime()
    W.historyTime = start + 999999 -- far past any minute, if it could be compared
    W.setDrop(9, 1, dropInfo(G, W, {}, { lootListKey = 1, startTime = T.secret(start) }))
    T.eq(#ns.Rolls.Cards(), 1, "a start time that is secret makes no age")
    T.near(ns.Rolls.TimeLeft(ns.Rolls.Cards()[1]), 60, 0.01)
    W.setDrop(9, 2, dropInfo(G, W, {}, { lootListKey = 2, startTime = start, duration = T.secret(60000) }))
    T.eq(#ns.Rolls.Cards(), 2, "nor a duration that is secret")
    local third = dropInfo(G, W, {}, { lootListKey = 3, startTime = start })
    local fourth = dropInfo(G, W, {}, { lootListKey = 4, startTime = start })
    G.C_LootHistory.GetLootHistoryTime = function() return T.secret(start) end
    W.setDrop(9, 3, third)
    T.eq(#ns.Rolls.Cards(), 3, "nor a clock that is secret")
    G.C_LootHistory.GetLootHistoryTime = nil
    W.setDrop(9, 4, fourth)
    T.eq(#ns.Rolls.Cards(), 4, "nor a game without the clock")
end)

T.it("secret or missing history is ignored", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local changed, added = listen(ns, "CARD_CHANGED"), listen(ns, "CARD_ADDED")
    local calls = countCalls(G)

    -- The event itself: a secret or a malformed payload never reaches the game's API.
    W.fire("LOOT_HISTORY_UPDATE_DROP", T.secret(9), 7)
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, T.secret(7))
    W.fire("LOOT_HISTORY_UPDATE_DROP", "9", 7)
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, "7")
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9)
    W.fire("LOOT_HISTORY_UPDATE_DROP")
    T.eq(calls.n, 0, "the game was never asked")

    -- The game's answer: nothing, a secret, a table without a readable link.
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, 7) -- the game knows no such drop: nil
    T.eq(calls.n, 1, "this one was asked")
    local function broken(field, value)
        local info = dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec) })
        info[field] = value
        W.setDrop(9, 7, info)
    end
    broken("itemHyperlink", 12345)
    broken("itemHyperlink", T.secret("link"))
    broken("itemHyperlink", "")
    broken("itemHyperlink", nil)
    G.C_LootHistory.GetSortedInfoForDrop = function() return T.secret({}) end
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, 7)
    G.C_LootHistory.GetSortedInfoForDrop = function() return "info" end
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, 7)
    T.eq(card.dropKey, nil, "no card took any of it")
    T.eq(card.history, false)
    T.eq(next(card.picks), nil)
    T.eq(#changed, 0, "nothing changed")
    T.eq(#added, 0, "nothing was added")
    T.eq(#ns.Rolls.Cards(), 1)
    T.eq(column(ns.Rolls.Rows(card), "state"), "wait,wait,wait,wait,wait", "the card is as it was")

    -- Without the history API at all.
    G.C_LootHistory = nil
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, 7)
    T.eq(#changed, 0)
end)

T.it("a rollInfo with a secret GUID is skipped, a secret field is left out", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local info = dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec, 73),
        { playerName = BRISE[1], playerGUID = T.secret(BRISE[2]), playerClass = BRISE[3], isSelf = false,
            state = ST.Greed, isWinner = false },
        T.secret({}), -- a whole entry the game keeps secret
        "not an entry",
        { playerName = CORVEL[1], playerClass = CORVEL[3], state = ST.Greed }, -- no GUID at all
        { playerName = KESTREL[1], playerGUID = KESTREL[2], playerClass = T.secret("WARRIOR"), isSelf = false,
            state = T.secret(ST.Pass), roll = T.secret(12), isWinner = T.secret(false) },
        rollInfo(AYLA, ST.NoRoll),
    })
    W.setDrop(9, 7, info) -- no error
    T.eq(card.dropKey, "9:7")
    T.eq(card.picks[BRISE[2]], nil, "no pick under a GUID that cannot be read")
    T.eq(size(card.picks), 3, "Orlen, Kestrel and the player")
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,out,out,wait,wait", "Kestrel's unreadable state is choosing")
    T.eq(column(ns.Rolls.Rows(card), "roll"), "73,nil,nil,nil,nil", "an unreadable number is none")
    T.eq(card.picks[KESTREL[2]].class, nil, "nor is an unreadable class kept")
    -- A secret state does not take back a pick that was read before.
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(KESTREL, ST.Pass) }))
    T.eq(ns.Rolls.Rows(card)[4].state, "pass")
    W.setDrop(9, 7, dropInfo(G, W, { { playerName = KESTREL[1], playerGUID = KESTREL[2], playerClass = KESTREL[3],
        isSelf = false, state = T.secret(ST.NoRoll), isWinner = false } }))
    T.eq(ns.Rolls.Rows(card)[4].state, "pass", "a state that cannot be read leaves the one that was")
end)

T.it("every value of a drop passes ns.IsSecret first, not just a type check", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local hidden = withSecrets(ns)
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    local calls = countCalls(G)
    local link = W.itemLink(AXE, "Guardian's Dualblade", 3)
    local function full()
        return dropInfo(G, W, {
            rollInfo(ORLEN, ST.NeedMainSpec, 77), rollInfo(BRISE, ST.Greed), rollInfo(CORVEL, ST.Pass),
            rollInfo(AYLA, ST.NoRoll),
        })
    end

    -- The event's numbers.
    hidden[9] = true
    W.setDrop(9, 7, full())
    T.eq(calls.n, 0, "a secret encounter ID never reaches the API")
    hidden[9] = nil
    hidden[7] = true
    W.setDrop(9, 7, full())
    T.eq(calls.n, 0, "nor a secret key")
    hidden[7] = nil

    -- The link.
    hidden[link] = true
    W.setDrop(9, 7, full())
    T.eq(calls.n, 1, "the game was asked, and its answer unusable")
    T.eq(card.dropKey, nil, "a secret link is no drop")
    hidden[link] = nil
    T.eq(#changed, 0)

    -- A GUID, a number, a state, a name and a class each keep to themselves.
    hidden[BRISE[2]], hidden[77], hidden[ST.Pass], hidden[AYLA[1]], hidden[CORVEL[3]] = true, true, true, true, true
    W.setDrop(9, 7, full())
    T.eq(card.dropKey, "9:7", "the rest of the drop is read")
    T.eq(card.picks[BRISE[2]], nil, "a secret GUID is never a key")
    T.eq(card.picks[ORLEN[2]].roll, nil, "a secret number is no number")
    T.eq(card.picks[CORVEL[2]].state, "wait", "a secret state is choosing")
    T.eq(card.picks[AYLA[2]].name, nil, "a secret name is not kept")
    T.eq(card.picks[CORVEL[2]].class, nil, "nor a secret class")
    T.eq(card.picks[ORLEN[2]].state, "need")
    -- The same data in the clear is read in full: the checks above were not vacuous.
    hidden[BRISE[2]], hidden[77], hidden[ST.Pass], hidden[AYLA[1]], hidden[CORVEL[3]] = nil, nil, nil, nil, nil
    W.setDrop(9, 7, full())
    T.eq(card.picks[BRISE[2]].state, "greed")
    T.eq(card.picks[ORLEN[2]].roll, 77)
    T.eq(card.picks[CORVEL[2]].state, "pass")
    T.eq(card.picks[AYLA[2]].name, AYLA[1])
    T.eq(card.picks[CORVEL[2]].class, "MAGE")
end)

T.it("a winner the game keeps secret decides nothing", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local decided = listen(ns, "CARD_DECIDED")
    local rolls = { rollInfo(ORLEN, ST.NeedMainSpec, 73, true), rollInfo(AYLA, ST.NeedMainSpec, 41) }
    W.setDrop(9, 7, dropInfo(G, W, rolls, { winner = T.secret({}) }))
    T.eq(card.status, "live", "a winner that cannot be read is not a decision")
    local nameless = rollInfo(ORLEN, ST.NeedMainSpec, 73, true)
    nameless.playerGUID = T.secret(ORLEN[2])
    W.setDrop(9, 7, dropInfo(G, W, rolls, { winner = nameless }))
    T.eq(card.status, "live", "nor one without a readable GUID")
    T.eq(#decided, 0)
    W.setDrop(9, 7, won(G, W, ORLEN, 73, rolls, { allPassed = T.secret(false) }))
    T.eq(card.status, "decided", "the readable winner is")
    T.eq(#decided, 1)

    -- A drop nobody saw begin, whose winner has no readable GUID, was over all the same: no card.
    local G2, W2, ns2 = T.load()
    W2.setDrop(9, 5, dropInfo(G2, W2, {}, { lootListKey = 5, winner = nameless }))
    T.eq(#ns2.Rolls.Cards(), 0)
    W2.setDrop(9, 6, dropInfo(G2, W2, {}, { lootListKey = 6, winner = T.secret({}) }))
    T.eq(#ns2.Rolls.Cards(), 1, "a winner that cannot be read at all counts as no winner")
end)

T.it("a roll with no decision ends 5 s after its time", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local decided, changed = listen(ns, "CARD_DECIDED"), listen(ns, "CARD_CHANGED")
    W.advance(64)
    T.eq(card.status, "live", "its minute and four seconds: not yet")
    T.eq(#decided, 0)
    W.advance(2)
    T.eq(card.status, "ended")
    T.eq(card.winner, nil)
    T.eq(card.decidedAt, W.clock)
    T.eq(#decided, 1, "CARD_DECIDED fired")
    T.eq(decided[1].card, card)
    T.eq(#changed, 1)
    T.eq(changed[1].changes.decided, true)
    T.eq(ns.Rolls.AwaitsMe(card), false)
    W.advance(100)
    T.eq(#decided, 1, "once")
end)

T.it("a roll the history decides does not end", function()
    local G, W, ns = T.load()
    local card = newCard(W, ns, 7)
    local decided = listen(ns, "CARD_DECIDED")
    W.advance(30)
    W.setDrop(9, 7, won(G, W, ORLEN, 70))
    T.eq(card.status, "decided")
    W.advance(100)
    T.eq(card.status, "decided", "its time running out changes nothing")
    T.eq(#decided, 1)
end)

T.it("an ended card still takes the picks but is not decided later", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) }))
    local decided, changed = listen(ns, "CARD_DECIDED"), listen(ns, "CARD_CHANGED")
    W.advance(66)
    T.eq(card.status, "ended")
    T.eq(#decided, 1)
    -- The history, late, names a winner.
    W.setDrop(9, 7, won(G, W, ORLEN, 70, { rollInfo(ORLEN, ST.NeedMainSpec, 70, true), rollInfo(AYLA, ST.Pass) }))
    T.eq(card.status, "ended", "the card is over; the history is late")
    T.eq(card.winner, nil)
    T.eq(#decided, 1, "CARD_DECIDED is once per card")
    T.eq(column(ns.Rolls.Rows(card), "state"), "need,out,out,out,pass", "but the rows show what the game says")
    T.eq(changed[#changed].changes.decided, nil)
    T.eq(changed[#changed].changes.picks[AYLA[2]], "state")
end)

T.it("a card the history made ends the same way", function()
    local G, W, ns = T.load()
    local decided = listen(ns, "CARD_DECIDED")
    W.setDrop(9, 7, dropInfo(G, W, {}, { startTime = G.C_LootHistory.GetLootHistoryTime() - 20000 }))
    local card = ns.Rolls.Cards()[1]
    W.advance(44)
    T.eq(card.status, "live", "20 s of its minute were gone: it ends 45 s on, not 44")
    W.advance(2)
    T.eq(card.status, "ended")
    T.eq(#decided, 1)
end)

T.it("a roll that joins a card moves its deadline", function()
    local G, W, ns = T.load()
    -- The history shows the drop 50 s into its minute: its card would end 15 s from now ...
    W.setDrop(9, 7, dropInfo(G, W, {}, { startTime = G.C_LootHistory.GetLootHistoryTime() - 50000 }))
    local card = ns.Rolls.Cards()[1]
    W.advance(5)
    -- ... but the player's own roll starts now, with a full minute.
    W.addRoll(7, axeSpec(W))
    T.eq(ns.Rolls.Cards()[1], card)
    W.advance(14) -- 19 s on: past the history's deadline
    T.eq(card.status, "live", "the old deadline no longer ends it")
    W.advance(46) -- the roll's minute is up, its 5 s are not
    T.eq(card.status, "live")
    W.advance(6)
    T.eq(card.status, "ended")

    -- A roll with less time than the card was counting on brings the deadline forward.
    local G2, W2, ns2 = T.load()
    W2.setDrop(9, 7, dropInfo(G2, W2, {}))
    local card2 = ns2.Rolls.Cards()[1] -- a minute, so 65 s
    W2.advance(1)
    W2.addRoll(7, axeSpec(W2, { time = 30000 }))
    W2.advance(34) -- 34 s into the roll: its half minute is over, its 5 s are not
    T.eq(card2.status, "live", "the roll's own 35 s are not up yet")
    W2.advance(2)
    T.eq(card2.status, "ended", "the card does not wait for the history's 65")
end)

T.it("a forgotten card is not ended and its drop is forgotten with it", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local card = newCard(W, ns, 7)
    local decided = listen(ns, "CARD_DECIDED")
    ns.Rolls.Forget(card)
    W.advance(100)
    T.eq(#decided, 0, "nobody is left to end")
    T.eq(card.status, "live")

    -- Late news of a drop whose card is gone does not bring it back, nor reach the old card.
    local second = newCard(W, ns, 8)
    W.setDrop(9, 8, won(G, W, ORLEN, 70))
    T.eq(second.status, "decided")
    local changed = listen(ns, "CARD_CHANGED")
    ns.Rolls.Forget(second)
    W.setDrop(9, 8, won(G, W, ORLEN, 70, { rollInfo(ORLEN, ST.NeedMainSpec, 70, true), rollInfo(BRISE, ST.Greed, 12) }))
    T.eq(#ns.Rolls.Cards(), 0, "a drop that was over is not a card again")
    T.eq(#changed, 0, "and the card that was forgotten hears nothing")
end)

T.it("a member who leaves keeps their row from the history", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, won(G, W, ORLEN, 73, {
        rollInfo(ORLEN, ST.NeedMainSpec, 73, true), rollInfo(CORVEL, ST.NeedMainSpec, 41), rollInfo(AYLA, ST.Greed),
        rollInfo(BRISE, ST.Greed), rollInfo(KESTREL, ST.Pass),
    }))
    T.eq(column(ns.Rolls.Rows(card), "name"), "Orlen,Brisé,Corvel,Kestrel,Ayla")
    -- Corvel and Brisé leave the group.
    local rest = party()
    table.remove(rest, 3) -- Corvel
    table.remove(rest, 2) -- Brisé
    rest[2].unit = "party2"
    W.setGroup(rest)
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "name"), "Orlen,Kestrel,Ayla,Corvel,Brisé", "the group first, then who only the history has")
    T.eq(column(rows, "state"), "need,pass,greed,need,greed")
    T.eq(column(rows, "roll"), "73,nil,nil,41,nil")
    T.eq(column(rows, "class"), "PALADIN,WARRIOR,DRUID,MAGE,SHAMAN", "the class comes from the history")
    T.eq(column(rows, "isPlayer"), "false,false,true,false,false")
    T.eq(column(rows, "isWinner"), "true,false,false,false,false")
    T.eq(rows[4].guid, "Player-1-0004")
    T.eq(rows[4].name, "Corvel", "the first name of the history's full name")
    -- The winner leaves too: the row is still the winner's, and the leavers keep the history's order.
    W.setGroup({})
    rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "name"), "Ayla,Orlen,Corvel,Brisé,Kestrel")
    T.eq(rows[2].isWinner, true)
    T.eq(rows[1].isPlayer, true)
end)

T.it("a member the group list could not name still has a row from the history", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    local list = party()
    list[2].name = T.secret("Hidden Name") -- Group skips a member whose name it cannot read
    W.setGroup(list)
    T.eq(#ns.Group.Members(), 4)
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.NeedMainSpec, 60), rollInfo(BRISE, ST.NeedMainSpec, 80), rollInfo(CORVEL, ST.Greed),
        rollInfo(KESTREL, ST.Pass), rollInfo(AYLA, ST.Greed),
    }))
    local rows = ns.Rolls.Rows(card)
    T.eq(#rows, 5, "nobody who rolled vanishes")
    T.eq(column(rows, "name"), "Orlen,Corvel,Kestrel,Ayla,Brisé")
    T.eq(rows[5].state, "need")
    T.eq(rows[5].roll, 80)
    T.eq(rows[5].class, "SHAMAN")
    T.eq(rows[5].isPlayer, false)

    -- The player, when the group list cannot list them, is the history's isSelf entry.
    local G2, W2, ns2 = T.load({ setup = function(g)
        local real = g.UnitGUID
        g.UnitGUID = function(unit) if unit ~= "player" then return real(unit) end end
    end })
    W2.setGroup(party())
    T.eq(#ns2.Group.Members(), 4, "the player has no readable GUID: not listed")
    local card2 = newCard(W2, ns2, 7)
    local ST2 = G2.Enum.EncounterLootDropRollState
    ns2.Rolls.Pick(card2, "need")
    W2.setDrop(9, 7, dropInfo(G2, W2, { rollInfo(ORLEN, ST2.NeedMainSpec), rollInfo(AYLA, ST2.NoRoll) }))
    local rows2 = ns2.Rolls.Rows(card2)
    T.eq(#rows2, 5)
    T.eq(rows2[5].name, "Ayla")
    T.eq(rows2[5].isPlayer, true, "isSelf says who they are")
    T.eq(rows2[5].state, "need", "their click shows here too, while the history still says choosing")
    W2.setDrop(9, 7, dropInfo(G2, W2, { rollInfo(ORLEN, ST2.NeedMainSpec), rollInfo(AYLA, ST2.Greed) }))
    T.eq(ns2.Rolls.Rows(card2)[5].state, "greed", "and the history's decided entry wins")
end)

T.it("a tie is the game's word", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local rolls = { rollInfo(ORLEN, ST.NeedMainSpec, 50), rollInfo(AYLA, ST.NeedMainSpec, 50) }
    W.setDrop(9, 7, dropInfo(G, W, rolls, { isTied = true }))
    T.eq(card.tied, true)
    T.eq(card.status, "live", "a tie is no winner")
    W.setDrop(9, 7, dropInfo(G, W, rolls, { isTied = false }))
    T.eq(card.tied, false)
end)

T.it("an update that says nothing new says nothing", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local changed = listen(ns, "CARD_CHANGED")
    local info = dropInfo(G, W, { rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.NoRoll) })
    W.setDrop(9, 7, info)
    W.setDrop(9, 7, info)
    T.eq(#changed, 1, "the first told everything")
    T.ok(card.history)
    -- A first sight with nobody in it is still news: the rows say who is out.
    local empty = newCard(W, ns, 8, otherSpec(W))
    W.setDrop(9, 8, dropInfo(G, W, {}, { lootListKey = 8, itemHyperlink = empty.link }))
    T.eq(empty.history, true)
    T.eq(#changed, 2, "the first sight of a drop is always announced")
    T.eq(column(ns.Rolls.Rows(empty), "state"), "out,out,out,out,wait")
end)

T.it("Rows of nothing is the group, choosing", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    T.eq(column(ns.Rolls.Rows(nil), "state"), "wait,wait,wait,wait,wait")
    T.eq(column(ns.Rolls.Rows({}), "state"), "wait,wait,wait,wait,wait")
    T.eq(column(ns.Rolls.Rows({ history = true, picks = {} }), "state"), "out,out,out,out,out",
        "the history has the drop and lists nobody: the player is out too")
end)

T.it("a two-item boss drop with staggered picks", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local axe = newCard(W, ns, 7)
    local ring = newCard(W, ns, 8, otherSpec(W, { name = "Band of the Forsaken" }))
    local decided = listen(ns, "CARD_DECIDED")
    local changed = listen(ns, "CARD_CHANGED")
    ns.Rolls.Pick(axe, "greed")
    ns.Rolls.Pick(ring, "need")
    local base = #changed -- the two picks

    local function axeDrop(rolls, over)
        return dropInfo(G, W, rolls, over)
    end
    local function ringDrop(rolls, over)
        local info = dropInfo(G, W, rolls, over)
        info.lootListKey, info.itemHyperlink = 2, ring.link
        return info
    end
    -- The picks come one at a time ...
    W.setDrop(9, 1, axeDrop({ rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(AYLA, ST.Greed) },
        { playerRollState = ST.Greed }))
    W.setDrop(9, 2, ringDrop({ rollInfo(BRISE, ST.Pass), rollInfo(AYLA, ST.NeedMainSpec) },
        { playerRollState = ST.NeedMainSpec }))
    W.setDrop(9, 1, axeDrop({ rollInfo(ORLEN, ST.NeedMainSpec), rollInfo(CORVEL, ST.Greed), rollInfo(AYLA, ST.Greed) },
        { playerRollState = ST.Greed }))
    T.eq(axe.dropKey, "9:1", "each item finds its own drop")
    T.eq(ring.dropKey, "9:2")
    T.eq(column(ns.Rolls.Rows(axe), "state"), "need,out,greed,out,greed")
    T.eq(column(ns.Rolls.Rows(ring), "state"), "out,pass,out,out,need")
    T.eq(#decided, 0, "nobody has won yet")

    -- ... and the numbers all at once at the end, with the winners.
    W.setDrop(9, 1, won(G, W, ORLEN, 73, {
        rollInfo(ORLEN, ST.NeedMainSpec, 73, true), rollInfo(CORVEL, ST.Greed), rollInfo(AYLA, ST.Greed),
        rollInfo(BRISE, ST.Pass), rollInfo(KESTREL, ST.Pass),
    }, { playerRollState = ST.Greed }))
    W.setDrop(9, 2, ringDrop({ rollInfo(AYLA, ST.NeedMainSpec, 87, true), rollInfo(BRISE, ST.Pass) },
        { playerRollState = ST.NeedMainSpec, winner = rollInfo(AYLA, ST.NeedMainSpec, 87, true) }))
    T.eq(#decided, 2)
    T.eq(decided[1].card, axe, "decided in the order the history said so")
    T.eq(decided[2].card, ring)
    T.eq(axe.winner, ORLEN[2])
    T.eq(ring.winner, AYLA[2], "the player won the ring")
    T.eq(column(ns.Rolls.Rows(axe), "roll"), "73,nil,nil,nil,nil")
    T.eq(column(ns.Rolls.Rows(axe), "isWinner"), "true,false,false,false,false")
    T.eq(column(ns.Rolls.Rows(ring), "roll"), "nil,nil,nil,nil,87")
    T.eq(column(ns.Rolls.Rows(ring), "isWinner"), "false,false,false,false,true")
    T.eq(ns.Rolls.Rows(ring)[5].isPlayer, true)
    T.eq(#changed - base, 5, "five history updates changed a card each")
    W.advance(120)
    T.eq(#decided, 2, "nothing ends later")
    T.eq(axe.status, "decided")
    T.eq(ring.status, "decided")
end)

T.it("picks made by hand still make rows", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    -- The shape the card documents, without the history's own bookkeeping (order, isSelf).
    local card = { history = true, winner = "Player-9-0001", picks = {
        ["Player-9-0001"] = { state = "need", roll = 87, name = "Foo Bar", class = "MAGE" },
        ["Player-1-0002"] = { state = "greed", roll = 12, name = "Orlen Brightmoor", class = "PALADIN" },
        ["Player-9-0002"] = { state = "pass", name = "Baz Qux", class = "ROGUE" },
    } }
    local rows = ns.Rolls.Rows(card)
    T.eq(column(rows, "name"), "Orlen,Brisé,Corvel,Kestrel,Ayla,Foo,Baz", "the group, then the others by GUID")
    T.eq(column(rows, "state"), "greed,out,out,out,out,need,pass")
    T.eq(column(rows, "roll"), "12,nil,nil,nil,nil,87,nil")
    T.eq(column(rows, "isWinner"), "false,false,false,false,false,true,false")
    T.eq(column(rows, "isPlayer"), "false,false,false,false,true,false,false")
    -- A card made by hand has no status: nobody is taken for out because the roll is over.
    card.picks["Player-9-0003"] = { state = "wait", name = "Corge Grault", class = "PRIEST" }
    T.eq(ns.Rolls.Rows(card)[8].state, "wait")
end)

T.it("an error in the history handler is reported, not thrown", function()
    local errors = {}
    local G, W = T.load({ setup = recordErrors(errors) })
    G.C_LootHistory.GetSortedInfoForDrop = function() error("the game is not ready") end
    W.fire("LOOT_HISTORY_UPDATE_DROP", 9, 7)
    T.eq(#errors, 1, "reported once")
    T.ok(tostring(errors[1]):find("the game is not ready", 1, true))
end)
