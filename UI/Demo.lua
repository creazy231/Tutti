-------------------------------------------------------------------------------
--  Tutti: /tutti demo, the approved mockup's "Play a boss drop" in game, with no real rolls. Two items drop and wait
--  on the player; the group picks one by one; the player picks Greed on the axe and Need on the gloves (the cards'
--  own buttons go down and are clicked); the numbers come in; the first member wins the axe, the player the gloves.
--  The window then folds and closes as it does for real rolls, and the results go to Recent rolls, marked as the
--  demo's (gone at the next login). The cards are demo cards (Core/Rolls.lua): Tutti's own ids, a pick never reaches
--  the game. The demo plays its script whatever is clicked on its cards meanwhile.
--  The group: the player's own when grouped, its members playing the mockup's four parts in the party's order (in a
--  raid everyone past them passes), else R30's made-up party: Orlen Brightmoor, Brisé Tidewater, Corvel Duskmantle
--  and Kestrel Ironmark, the player after them as in the mockup.
--    ns.Demo.Start() -> ok    plays the boss drop; false while one plays
-------------------------------------------------------------------------------
local _, ns = ...
local Demo = {}
ns.Demo = Demo

local DURATION, RARE, ILVL = 60, 3, 33 -- the roll's seconds, the items' quality and level

-- The mockup's two items, real Forever items (as Polestar_ItemDB and ForeverDungeonJournal list them), so in game
-- they have their tooltip and their icon; the words and icons here stand in where the client has nothing yet.
local AXE = { id = 273046, name = "Guardian's Dualblade", label = "Two-Hand Axe",
    icon = "Interface\\Icons\\INV_Axe_09", canNeed = false }
local GLOVES = { id = 273054, name = "Cartilage Shapers", label = "Leather Hands",
    icon = "Interface\\Icons\\INV_Gauntlets_05", canNeed = true }
local NEED_REFUSED = "Your class may not roll need on this item." -- the game's reason 1, where it has no text

-- R30's cast, for a player on their own: the mockup's paladin, shaman, mage and warrior.
local CAST = {
    { guid = "Demo-1", name = "Orlen Brightmoor", first = "Orlen", class = "PALADIN", isPlayer = false },
    { guid = "Demo-2", name = "Brisé Tidewater", first = "Brisé", class = "SHAMAN", isPlayer = false },
    { guid = "Demo-3", name = "Corvel Duskmantle", first = "Corvel", class = "MAGE", isPlayer = false },
    { guid = "Demo-4", name = "Kestrel Ironmark", first = "Kestrel", class = "WARRIOR", isPlayer = false },
}

local playing = false

-------------------------------------------------------------------------------
--  The cast and the cards
-------------------------------------------------------------------------------
-- Who plays: { player, parts = { member, ... } (the mockup's parts first, then the rest of a raid), members (the
-- cards' own group, made up; nil for the player's real one), everyone (who has a pick) }.
local function cast()
    local run = { parts = {} }
    for _, member in ipairs(ns.Group.Members()) do
        if member.isPlayer then run.player = member else run.parts[#run.parts + 1] = member end
    end
    if #run.parts == 0 then
        run.parts, run.members = CAST, {}
        for i, member in ipairs(CAST) do run.members[i] = member end
        run.members[#run.members + 1] = run.player
    end
    run.everyone = {}
    for i, member in ipairs(run.parts) do run.everyone[i] = member end
    run.everyone[#run.everyone + 1] = run.player
    return run
end

-- The item as the client has it, else the words here: name, link (nil until the client has it), quality, icon.
local function itemInfo(item)
    local name, link, quality, icon
    local get, instant = C_Item and C_Item.GetItemInfo, C_Item and C_Item.GetItemInfoInstant
    if type(get) == "function" then
        local n, l, q = get(item.id)
        name, link, quality = ns.Text(n), ns.Text(l), ns.Clear(q, "number")
    end
    if type(instant) == "function" then
        icon = ns.Clear(select(5, instant(item.id)), "number")
    end
    return name or item.name, link, quality or RARE, (icon and icon > 0) and icon or item.icon
end

local function fields(run, item)
    local name, link, quality, icon = itemInfo(item)
    local label, ilvl = ns.Items.Describe(link)
    local picks = {}
    for i, member in ipairs(run.everyone) do
        picks[member.guid] = { state = "wait", name = member.name, class = member.class,
            isSelf = member == run.player, order = i }
    end
    return {
        link = link, name = name, icon = icon, quality = quality, count = 1, bop = true,
        label = label or item.label, ilvl = ilvl or ILVL,
        canNeed = item.canNeed, canGreed = true, canTransmog = false,
        reasonNeed = not item.canNeed and (ns.Text(LOOT_ROLL_INELIGIBLE_REASON1) or NEED_REFUSED) or nil,
        startedAt = GetTime(), duration = DURATION, history = true, picks = picks, members = run.members,
    }
end

-------------------------------------------------------------------------------
--  What happens
-------------------------------------------------------------------------------
-- A part's GUID: 1 to 4 the mockup's parts, "me" the player; nil when nobody plays it.
local function guidOf(run, part)
    local member = part == "me" and run.player or run.parts[part]
    return member and member.guid
end

local function choose(run, card, part, state)
    local guid = guidOf(run, part)
    if guid then ns.Rolls.DemoNews(card, { [guid] = { state = state } }) end
end

-- Everyone past the four parts (a raid) picks the same.
local function rest(run, card, state)
    local news = {}
    for i = 5, #run.parts do news[run.parts[i].guid] = { state = state } end
    ns.Rolls.DemoNews(card, news)
end

local function reveal(run, card, numbers)
    local news = {}
    for part, roll in pairs(numbers) do
        local guid = guidOf(run, part)
        if guid then news[guid] = { roll = roll } end
    end
    ns.Rolls.DemoNews(card, news)
end

local function win(run, card, part)
    ns.Rolls.DemoNews(card, nil, guidOf(run, part) or false)
end

-- The card's own button for a pick, while the window shows it.
local function button(card, kind)
    local window = ns.UI and ns.UI.win
    local view = window and window.views and window.views[card]
    local b = view and view.buttons and view.buttons[kind]
    if b and b:IsVisible() then return b end
end

-- The player's pick: the button goes down (press), then comes up and is clicked (pick), as the mouse does it. A card
-- the window does not show takes the pick straight away.
local function press(card, kind)
    local b = button(card, kind)
    local down = b and b:GetScript("OnMouseDown")
    if down then down(b, "LeftButton") end
end

local function pick(card, kind)
    local b = button(card, kind)
    if not b then
        ns.Rolls.Pick(card, kind)
        return
    end
    local up = b:GetScript("OnMouseUp")
    if up then up(b, "LeftButton") end
    b:Click()
end

-- The mockup's PLAY timeline, in seconds from the drop: who picks what, when the numbers come, who wins.
local function timeline(run, axe, gloves)
    return {
        { 0.9, function() choose(run, axe, 1, "need") end },
        { 1.4, function()
            choose(run, axe, 3, "pass")
            choose(run, gloves, 3, "pass")
            rest(run, axe, "pass")
            rest(run, gloves, "pass")
        end },
        { 2.0, function()
            choose(run, axe, 2, "greed")
            choose(run, gloves, 2, "need")
        end },
        { 2.6, function() choose(run, gloves, 4, "pass") end },
        { 3.3, function() press(axe, "greed") end },
        { 3.7, function() pick(axe, "greed") end },
        { 4.4, function() choose(run, axe, 4, "pass") end },
        { 5.0, function() reveal(run, axe, { [1] = 19 }) end },
        { 6.1, function() win(run, axe, 1) end },
        { 7.1, function() choose(run, gloves, 1, "greed") end },
        { 7.9, function() press(gloves, "need") end },
        { 8.3, function() pick(gloves, "need") end },
        { 9.0, function() reveal(run, gloves, { [2] = 52, me = 87 }) end },
        { 10.1, function() win(run, gloves, "me") end },
    }
end

function Demo.Start()
    if playing then return false end
    playing = true
    local run = cast()
    local axe = ns.Rolls.AddDemo(fields(run, AXE))
    local gloves = ns.Rolls.AddDemo(fields(run, GLOVES))
    local steps = timeline(run, axe, gloves)
    for i, step in ipairs(steps) do
        ns.After(step[1], function()
            ns.Safe(step[2])
            if i == #steps then playing = false end
        end)
    end
    return true
end
