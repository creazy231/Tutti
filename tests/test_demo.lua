local T = T

local PLAYER = "Player-1-00000001" -- the fake's Ayla Brightwind
local CHIME = "Interface\\AddOns\\Tutti\\Media\\Sounds\\chime.ogg"

local function setup(opts)
    local G, W, ns = T.load(opts)
    return G, W, ns, G.TuttiFrame
end

-- The demo's clock: to(t) moves the game to t seconds after the demo started.
local function timeline(W)
    local start = W.clock
    return function(t) W.advance(start + t - W.clock + 1e-6) end
end

-- What a font string shows on screen: its plain text, "" when it or a parent is hidden.
local function text(W, fs)
    return fs:IsVisible() and W.plain(fs:GetText() or "") or ""
end

local function names(ns, card)
    local out = {}
    for i, row in ipairs(ns.Rolls.Rows(card)) do out[i] = row.name end
    return table.concat(out, ", ")
end

local function row(ns, card, i) return ns.Rolls.Rows(card)[i] end

local function chimes(W)
    local n = 0
    for _, s in ipairs(W.sounds) do
        if s.file == CHIME then n = n + 1 end
    end
    return n
end

T.it("the boss drop plays: Orlen wins the axe, the player the gloves, RollOnLoot never called, " ..
    "the window closes 10 s after", function()
    local G, W, ns, win = setup()
    local to = timeline(W)
    T.eq(ns.Demo.Start(), true)
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 2, "two items drop")
    local axe, gloves = cards[1], cards[2]
    T.eq(axe.name, "Guardian's Dualblade")
    T.eq(axe.label, "Two-Hand Axe")
    T.eq(gloves.name, "Cartilage Shapers")
    T.eq(gloves.label, "Leather Hands")
    T.ok(axe.demo and gloves.demo, "demo cards")
    T.ok(win:IsShown(), "the window opens with them")
    T.ok(ns.Rolls.AwaitsMe(axe) and ns.Rolls.AwaitsMe(gloves), "both wait on the player")
    T.eq(axe.canNeed, false, "Need refused on the axe, with the game's reason")
    T.eq(axe.reasonNeed, G.LOOT_ROLL_INELIGIBLE_REASON1)
    T.eq(gloves.canNeed, true)
    T.eq(names(ns, axe), "Orlen, Brisé, Corvel, Kestrel, Ayla", "solo: a made-up party, then the player")
    T.eq(row(ns, axe, 1).class, "PALADIN")
    T.eq(row(ns, gloves, 2).class, "SHAMAN")
    for i = 1, 5 do T.eq(row(ns, axe, i).state, "wait", "everyone choosing") end

    to(0.9)
    T.eq(row(ns, axe, 1).state, "need", "Orlen needs the axe")
    to(1.4)
    T.eq(row(ns, axe, 3).state, "pass")
    T.eq(row(ns, gloves, 3).state, "pass", "Corvel passes on both")
    to(2.0)
    T.eq(row(ns, axe, 2).state, "greed")
    T.eq(row(ns, gloves, 2).state, "need", "Brisé needs the gloves")
    to(2.6)
    T.eq(row(ns, gloves, 4).state, "pass")
    to(3.3)
    T.ok(win.views[axe].buttons.greed.pressed, "the player's Greed goes down")
    T.eq(axe.mine, nil)
    to(3.7)
    T.eq(axe.mine, "greed", "and the player greeds the axe")
    T.eq(row(ns, axe, 5).state, "greed")
    T.no(ns.Rolls.AwaitsMe(axe))
    to(4.4)
    T.eq(row(ns, axe, 4).state, "pass")
    to(5.0)
    T.eq(row(ns, axe, 1).roll, 19, "Orlen's number")
    T.eq(axe.status, "live")
    to(6.1)
    T.eq(axe.status, "decided")
    T.ok(row(ns, axe, 1).isWinner, "Orlen wins the axe")
    to(7.1)
    T.eq(row(ns, gloves, 1).state, "greed")
    to(7.9)
    T.ok(win.views[gloves].buttons.need.pressed)
    to(8.3)
    T.eq(gloves.mine, "need", "the player needs the gloves")
    to(10.05)
    T.ok(win.views[axe]:Height() > 26, "the axe still whole")
    to(10.1)
    T.eq(win.views[axe]:Height(), 26, "the axe folds 4 s after its win, in the wait before the gloves' numbers")
    T.eq(gloves.status, "live")
    T.eq(row(ns, gloves, 5).roll, nil)
    to(11.2)
    T.eq(row(ns, gloves, 2).roll, 52)
    T.eq(row(ns, gloves, 5).roll, 87)
    T.eq(chimes(W), 0)
    to(12.25)
    T.eq(gloves.status, "live", "2.2 s between the fold and the gloves' win, as the mockup keeps")
    to(12.3)
    T.eq(gloves.status, "decided")
    T.ok(row(ns, gloves, 5).isWinner, "the player wins the gloves")
    T.eq(chimes(W), 1, "the win's chime")
    T.eq(#W.rolled, 0, "RollOnLoot never called")

    local entries = ns.History.Entries()
    T.eq(#entries, 2, "Recent rolls has both")
    T.eq(entries[1].name, "Cartilage Shapers")
    T.eq(entries[1].winner.name, "Ayla")
    T.eq(entries[2].winner.name, "Orlen")
    T.ok(entries[1].demo and entries[2].demo, "marked as the demo's")

    T.eq(text(W, win.head.closes), "closes in 10s", "the window closes 10 s after")
    to(22.25)
    T.ok(win:IsShown())
    to(22.35)
    to(22.95)
    T.no(win:IsShown(), "closed")
    T.eq(#ns.Rolls.Cards(), 0, "and the demo's cards are gone")
end)

-------------------------------------------------------------------------------
--  Edge cases
-------------------------------------------------------------------------------
T.it("grouped, the player's real group plays the parts", function()
    local G, W, ns = setup()
    W.setGroup({
        { unit = "party1", name = "Tamsin Reedwell", classFile = "PRIEST", guid = "Player-1-0011" },
        { unit = "party2", name = "Doran Ashgrove", classFile = "ROGUE", guid = "Player-1-0012" },
    })
    local to = timeline(W)
    ns.Demo.Start()
    local axe, gloves = ns.Rolls.Cards()[1], ns.Rolls.Cards()[2]
    T.eq(names(ns, axe), "Tamsin, Doran, Ayla", "the party's names, in its order")
    to(12.4)
    T.eq(axe.winner, "Player-1-0011", "the first plays Orlen: the axe")
    T.eq(row(ns, axe, 1).roll, 19)
    T.eq(row(ns, gloves, 2).roll, 52, "the second plays Brisé")
    T.eq(gloves.winner, PLAYER)
    T.eq(#W.rolled, 0)
end)

T.it("in a raid everyone past the four parts passes", function()
    local G, W, ns = setup()
    local raid = {}
    for i = 1, 7 do
        raid[i] = { unit = "raid" .. i, name = "Member" .. i .. " Testname", classFile = "MAGE",
            guid = "Player-1-01" .. i }
    end
    raid[8] = { unit = "raid8", isPlayer = true }
    W.setGroup(raid, { raid = true })
    local to = timeline(W)
    ns.Demo.Start()
    local axe = ns.Rolls.Cards()[1]
    to(1.0)
    T.eq(row(ns, axe, 5).state, "wait")
    to(1.4)
    for i = 5, 7 do T.eq(row(ns, axe, i).state, "pass", "member " .. i) end
    T.eq(row(ns, axe, 3).state, "pass", "the third part passes as Corvel does")
    T.eq(row(ns, axe, 8).isPlayer, true)
    T.eq(row(ns, axe, 8).state, "wait")
end)

T.it("a second demo waits for the first, and says so", function()
    local G, W, ns = setup()
    local to = timeline(W)
    T.eq(ns.Demo.Start(), true)
    to(5)
    T.eq(ns.Demo.Start(), false, "one boss drop at a time")
    T.eq(#ns.Rolls.Cards(), 2)
    T.eq(#W.chatLog, 1, "one line says so")
    T.ok(W.chatLog[1]:find("already playing", 1, true), W.chatLog[1])
    to(12.4)
    T.eq(ns.Demo.Start(), true, "and the next after it")
    T.eq(#ns.Rolls.Cards(), 4)
end)

T.it("a start that fails does not keep the next one from playing", function()
    local G, W, ns = setup()
    local add = ns.Rolls.AddDemo
    ns.Rolls.AddDemo = function() error("no cards today") end
    T.raises(function() ns.Demo.Start() end, "no cards today")
    ns.Rolls.AddDemo = add
    T.eq(ns.Demo.Start(), true, "the next /tutti demo plays")
    T.eq(#ns.Rolls.Cards(), 2)
end)

-- Fix 1 of the review: the player's own clicks on the demo's cards do not change its finale.
T.it("a Pass on the gloves at 2.5 s still ends with the scripted finale", function()
    local G, W, ns, win = setup()
    local to = timeline(W)
    ns.Demo.Start()
    local gloves = ns.Rolls.Cards()[2]
    to(2.5)
    win.views[gloves].buttons.pass:Click()
    T.eq(gloves.mine, "pass", "the player's own click")
    to(12.3)
    local me = row(ns, gloves, 5)
    T.eq(me.state, "need", "the history says the script's Need")
    T.eq(me.roll, 87)
    T.ok(me.isWinner)
    local parts = {}
    for _, fs in ipairs(win.views[gloves].parts) do
        if fs:IsShown() then parts[#parts + 1] = W.plain(fs:GetText() or "") end
    end
    T.eq(table.concat(parts, " "), "You won · Need 87")
    T.eq(ns.History.Entries()[1].winner.state, "need")
    T.eq(#W.rolled, 0)
end)

T.it("the demo asks the client for its items and takes them in when they come", function()
    local requested = {}
    local G, W, ns = setup({ setup = function(G)
        G.C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
    end })
    ns.Demo.Start()
    T.eq(table.concat(requested, ","), "273046,273054", "both items asked for")
    local axe = ns.Rolls.Cards()[1]
    T.eq(axe.itemID, 273046)
    T.eq(axe.link, "item:273046", "the item's own link until the client has a better one")
    T.eq(axe.name, "Guardian's Dualblade")
    T.eq(axe.label, "Two-Hand Axe")
    local changes
    ns.Listen("CARD_CHANGED", function(card, c) if card == axe then changes = c end end)
    local link = W.itemLink(273046, "Klinge des Wächters", 3)
    W.cacheItem(273046, { name = "Klinge des Wächters", link = link, quality = 3, ilvl = 33, classID = 2,
        subclassID = 1, equipLoc = "INVTYPE_2HWEAPON", texture = 135575 })
    T.eq(axe.name, "Klinge des Wächters", "the client's name")
    T.eq(axe.link, link, "and its link")
    T.eq(axe.icon, 135575, "and its icon")
    T.eq(axe.label, "Two-Hand Axe")
    T.eq(axe.ilvl, 33)
    T.ok(changes and changes.item, "the card draws it")
    T.ok(ns.Rolls.AwaitsMe(axe), "and still waits on the player")
end)
