local T = T

-- The Classic clients (wow-ui-source branches classic, classic_titan, classic_anniversary and classic_era,
-- 2026-11-14): the older loot history (C_LootHistory.GetNumItems, GetItem, GetPlayerInfo), which names each roll
-- by its roll ID and each player by name; no event router, as UIParent opens Blizzard's popups from its own
-- START_LOOT_ROLL; no Transmog; names "Name" or "Name-Realm". The fake plays such a client with W.classic().

local AXE = 18000

-- A Classic client with the axe in its item cache and a party: Orlen and Corvel of the player's realm, Brisé of
-- another one. -> G, W, ns
local function load(opts)
    opts = opts or {}
    local extra = opts.setup
    opts.setup = function(G, W)
        W.classic()
        if extra then extra(G, W) end
    end
    local G, W, ns = T.load(opts)
    W.items[AXE] = { name = "Ancient Axe", quality = 3, ilvl = 33, classID = 2, subclassID = 1,
        equipLoc = "INVTYPE_2HWEAPON", texture = 135348 }
    W.setGroup({
        { unit = "party1", name = "Orlen", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brise", realm = "Stormrage", classFile = "SHAMAN", guid = "Player-9-0003" },
        { unit = "party3", name = "Corvel", classFile = "MAGE", guid = "Player-1-0004" },
    })
    return G, W, ns
end

local function link(W) return W.itemLink(AXE, "Ancient Axe", 3) end

-- The player's roll `id` for the axe starts. -> its card
local function roll(W, ns, id)
    W.addRoll(id, { link = link(W), name = "Ancient Axe", texture = 135348 })
    for _, card in ipairs(ns.Rolls.Cards()) do
        if card.rollID == id then return card end
    end
end

-- One item of the history: the axe's roll `id`, with its players; `over` sets done, winner, masterLoot.
local function item(W, id, players, over)
    local it = { rollID = id, link = link(W), players = players }
    for k, v in pairs(over or {}) do it[k] = v end
    return it
end

-- The card's rows as "Name:state[ roll][*]" (* the winner), in order.
local function rows(ns, card)
    local out = {}
    for _, row in ipairs(ns.Rolls.Rows(card)) do
        out[#out + 1] = row.name .. ":" .. row.state .. (row.roll and (" " .. row.roll) or "")
            .. (row.isWinner and "*" or "")
    end
    return table.concat(out, ", ")
end

T.it("on a Classic client Blizzard's popups go off at UIParent, which opens them there", function()
    local G, W, ns = load()
    T.eq(G.GameEvent, nil, "no event router on Classic")
    T.no(G.UIParent:IsEventRegistered("START_LOOT_ROLL"), "UIParent no longer opens Blizzard's popups")
    T.ok(G.UIParent:IsEventRegistered("CONFIRM_LOOT_ROLL"), "the bind confirmation stays Blizzard's")
    T.ok(ns.Popups.Suppressed())
    T.ok(ns.Popups.RollInTutti())
    -- "Roll in Tutti" off at login: UIParent keeps the event.
    G, W, ns = load({ db = { settings = { rollInTutti = false } } })
    T.ok(G.UIParent:IsEventRegistered("START_LOOT_ROLL"))
    T.no(ns.Popups.Suppressed())
end)

T.it("a roll's card takes the group's picks from the Classic loot history, by name", function()
    local G, W, ns = load()
    local card = roll(W, ns, 7)
    T.ok(card, "the roll's card")
    T.ok(G.TuttiFrame:IsShown(), "the window opens")
    T.eq(rows(ns, card), "Orlen:wait, Brise:wait, Corvel:wait, Ayla:wait", "everyone choosing until the history says")
    W.setHistory({ item(W, 7, {
        { name = "Orlen", class = "PALADIN", type = 1 },
        { name = "Brise-Stormrage", class = "SHAMAN", type = 2 },
        { name = "Corvel", class = "MAGE", type = 0 },
        { name = "Ayla", class = "DRUID", me = true },
    }) })
    T.eq(rows(ns, card), "Orlen:need, Brise:greed, Corvel:pass, Ayla:wait")
    T.ok(card.history)
    T.eq(#ns.Rolls.Cards(), 1, "the item names its roll: the same card")
end)

T.it("the numbers come in and the item done names the winner; done with none named, everyone passed", function()
    local G, W, ns = load()
    local card = roll(W, ns, 7)
    local decided = 0
    ns.Listen("CARD_DECIDED", function() decided = decided + 1 end)
    local players = {
        { name = "Orlen", class = "PALADIN", type = 1, roll = 87 },
        { name = "Brise-Stormrage", class = "SHAMAN", type = 1, roll = 23 },
        { name = "Corvel", class = "MAGE", type = 0 },
        { name = "Ayla", class = "DRUID", type = 0, me = true },
    }
    W.setHistory({ item(W, 7, players) }, "LOOT_HISTORY_ROLL_CHANGED", 1, 1)
    T.eq(card.status, "live", "numbers, no decision yet")
    T.eq(rows(ns, card), "Orlen:need 87, Brise:need 23, Corvel:pass, Ayla:pass")
    W.setHistory({ item(W, 7, players, { done = true, winner = 1 }) }, "LOOT_HISTORY_ROLL_COMPLETE")
    T.eq(card.status, "decided")
    T.eq(card.winner, "Player-1-0002", "Orlen's GUID")
    T.eq(rows(ns, card), "Orlen:need 87*, Brise:need 23, Corvel:pass, Ayla:pass")
    T.eq(decided, 1)
    W.setHistory({ item(W, 7, players, { done = true, winner = 1 }) })
    T.eq(decided, 1, "a decided card is never decided again")

    local other = roll(W, ns, 8)
    W.setHistory({ item(W, 8, {
        { name = "Orlen", class = "PALADIN", type = 0 }, { name = "Ayla", class = "DRUID", type = 0, me = true },
    }, { done = true }), item(W, 7, players, { done = true, winner = 1 }) })
    T.eq(other.status, "decided")
    T.ok(other.allPassed, "done and nobody named: everyone passed")
    T.eq(other.winner, nil)
end)

T.it("a roll the player is not in gets a card of its own, without buttons; their roll joins it", function()
    local G, W, ns = load()
    W.setHistory({ item(W, 9, { { name = "Orlen", class = "PALADIN", type = 1 } }) })
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 1, "a card for the history's roll")
    local card = cards[1]
    T.no(ns.Rolls.AwaitsMe(card), "nothing for the player to pick")
    T.eq(card.name, "Ancient Axe", "the item from its link")
    T.eq(rows(ns, card), "Orlen:need, Brise:out, Corvel:out, Ayla:out")
    local mine = roll(W, ns, 9)
    T.eq(#ns.Rolls.Cards(), 1, "the player's roll starting after joins that card")
    T.eq(mine, card)
    T.ok(ns.Rolls.AwaitsMe(card), "and the player can pick on it")
    T.eq(rows(ns, card), "Orlen:need, Brise:out, Corvel:out, Ayla:wait")
end)

T.it("master loot, a roll over before Tutti saw it and a roll whose card is gone make no card", function()
    local G, W, ns = load()
    W.setHistory({
        item(W, 3, { { name = "Orlen", class = "PALADIN" } }, { masterLoot = true }),
        item(W, 4, { { name = "Orlen", class = "PALADIN", type = 1, roll = 5 } }, { done = true, winner = 1 }),
    })
    T.eq(#ns.Rolls.Cards(), 0)
    -- A roll nobody decided ends 5 s after its minute; the window forgets it when it closes. The history listing
    -- its roll again, still undone, brings no second card.
    local card = roll(W, ns, 6)
    W.advance(66)
    T.eq(card.status, "ended")
    ns.Rolls.ForgetDecided()
    T.eq(#ns.Rolls.Cards(), 0)
    W.setHistory({ item(W, 6, { { name = "Orlen", class = "PALADIN", type = 1 } }) })
    T.eq(#ns.Rolls.Cards(), 0, "its roll is not made again")
end)

T.it("a Disenchant pick reads as Greed, and a roller the group does not list comes after it", function()
    local G, W, ns = load()
    local card = roll(W, ns, 7)
    W.setHistory({ item(W, 7, {
        { name = "Orlen", class = "PALADIN", type = 2, roll = 12 },
        { name = "Brise-Stormrage", class = "SHAMAN", type = 0 },
        { name = "Corvel", class = "MAGE", type = 3, roll = 61 },
        { name = "Ayla", class = "DRUID", type = 0, me = true },
        { name = "Kestrel", class = "WARRIOR", type = 2, roll = 30 },
    }) })
    T.eq(rows(ns, card), "Orlen:greed 12, Brise:pass, Corvel:greed 61, Ayla:pass, Kestrel:greed 30")
end)

T.it("the player's pick goes to the game and shows at once, Transmog never offered", function()
    local G, W, ns = load()
    local card = roll(W, ns, 7)
    T.eq(card.canTransmog, false, "Classic has no Transmog")
    T.ok(ns.Rolls.Pick(card, "greed"))
    T.eq(W.rolled[1][1], 7)
    T.eq(W.rolled[1][2], 2, "Greed")
    T.eq(rows(ns, card), "Orlen:wait, Brise:wait, Corvel:wait, Ayla:greed")
end)

-------------------------------------------------------------------------------
--  Retail (wow-ui-source branch live, 12.1.5): WoW Forever's loot history and event router, names "Name-Realm",
--  no gamepad interface; its drop field is lootListID where Forever's is lootListKey, which Tutti never reads (the
--  event names the key).
-------------------------------------------------------------------------------
T.it("on Retail the window works from the event router and the newer loot history", function()
    local G, W, ns = T.load({ setup = function(G, W)
        W.run = false
        W.player.name, W.player.realm = "Ayla", "Silvermoon"
        G.RegionalUniqueNamesEnabled = nil
        G.C_InputInterfaceStyle = nil
    end })
    W.items[AXE] = { name = "Ancient Axe", quality = 3, ilvl = 33, classID = 2, subclassID = 1,
        equipLoc = "INVTYPE_2HWEAPON", texture = 135348 }
    W.setGroup({ { unit = "party1", name = "Orlen", realm = "Stormrage", classFile = "PALADIN", guid = "Player-9-0002" } })
    T.eq(W.unregistered[1], "START_LOOT_ROLL", "Blizzard's popups off through the router")
    T.no(ns.Popups.Gamepad())
    local card = roll(W, ns, 1)
    local orlen = { playerName = "Orlen-Stormrage", playerGUID = "Player-9-0002", playerClass = "PALADIN",
        state = G.Enum.EncounterLootDropRollState.NeedMainSpec, roll = 77, isWinner = true }
    W.setDrop(9, 1, { lootListID = 1, itemHyperlink = link(W),
        playerRollState = G.Enum.EncounterLootDropRollState.Pass, isTied = false, allPassed = false,
        rollInfos = { orlen }, winner = orlen, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 })
    T.eq(card.status, "decided")
    T.eq(card.winner, "Player-9-0002")
    T.eq(rows(ns, card), "Orlen:need 77*, Ayla:out", "decided: the player who never picked is out")
end)
