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
    to(9.0)
    T.eq(row(ns, gloves, 2).roll, 52)
    T.eq(row(ns, gloves, 5).roll, 87)
    T.eq(chimes(W), 0)
    to(10.1)
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
    to(20.05)
    T.ok(win:IsShown())
    to(20.15)
    to(20.75)
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
    to(10.2)
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

T.it("a second demo waits for the first", function()
    local G, W, ns = setup()
    local to = timeline(W)
    T.eq(ns.Demo.Start(), true)
    to(5)
    T.eq(ns.Demo.Start(), false, "one boss drop at a time")
    T.eq(#ns.Rolls.Cards(), 2)
    to(10.2)
    T.eq(ns.Demo.Start(), true, "and the next after it")
    T.eq(#ns.Rolls.Cards(), 4)
end)
