local T = T

-------------------------------------------------------------------------------
--  The scene: the party the other tests use and five items, each with a roll for the player
-------------------------------------------------------------------------------
-- Item n is AXE + n - 1; its roll has the roll ID n and its drop the key 9:n.
local AXE = 18000
local ITEMS = { "Guardian's Dualblade", "Other axe", "Third axe", "Fourth axe", "Fifth axe" }
local CHIME = "Interface\\AddOns\\Tutti\\Media\\Sounds\\chime.ogg"

-- The party in party1..party4; the player is the fake's Ayla Brightwind.
local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- The same as the loot history names them: full name, GUID, class file.
local ORLEN = { "Orlen Brightmoor", "Player-1-0002", "PALADIN" }
local BRISE = { "Brisé Tidewater", "Player-1-0003", "SHAMAN" }
local AYLA = { "Ayla Brightwind", "Player-1-00000001", "DRUID", isSelf = true }

-- A client with the axe in its item cache and the party grouped. -> G, W, ns, TuttiFrame
-- The addon is loaded up to the window and no further: Task 12's views (UI/Recent.lua and the files after it)
-- register at load, and these tests put stand-ins in their place.
local function setup(opts)
    opts = opts or {}
    if not opts.only then
        opts.only = {}
        for _, file in ipairs(T.tocFiles()) do
            opts.only[#opts.only + 1] = file
            if file == "UI/Window.lua" then break end
        end
    end
    local G, W, ns = T.load(opts)
    W.items[AXE] = { name = ITEMS[1], quality = 3, ilvl = 33, classID = 2, subclassID = 1,
        equipLoc = "INVTYPE_2HWEAPON", texture = 135348 }
    W.setGroup(party())
    return G, W, ns, G.TuttiFrame
end

local function link(W, n) return W.itemLink(AXE + n - 1, ITEMS[n], 3) end

-- The player's roll for item n starts; `over` changes the spec. -> its card
local function roll(W, ns, n, over)
    local spec = { link = link(W, n), name = ITEMS[n], texture = 135348 }
    for k, v in pairs(over or {}) do spec[k] = v end
    W.addRoll(n, spec)
    local cards = ns.Rolls.Cards()
    return cards[#cards]
end

-- One EncounterLootDropRollInfo; `state` names an Enum.EncounterLootDropRollState.
local function rollInfo(G, who, state, number, isWinner)
    return { playerName = who[1], playerGUID = who[2], playerClass = who[3], isSelf = who.isSelf == true,
        state = G.Enum.EncounterLootDropRollState[state], roll = number, isWinner = isWinner == true }
end

-- Item n's drop as the game hands it out, begun now (or at `began`, on the history's clock) and a minute long.
local function drop(G, W, n, infos, over)
    local info = { lootListKey = n, itemHyperlink = link(W, n),
        playerRollState = G.Enum.EncounterLootDropRollState.NoRoll, isTied = false, allPassed = false,
        rollInfos = infos or {}, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 }
    for k, v in pairs(over or {}) do info[k] = v end
    return info
end

-- The history decides item n: `who` won it with Need `number`.
local function decide(G, W, n, who, number, over)
    local info = drop(G, W, n, { rollInfo(G, who, "NeedMainSpec", number, true) }, over)
    info.winner = rollInfo(G, who, "NeedMainSpec", number, true)
    W.setDrop(9, n, info)
end

-- What a font string shows on screen: its plain text, "" when it or a parent is hidden.
local function text(W, fs)
    return fs:IsVisible() and W.plain(fs:GetText() or "") or ""
end

-- A region's box in the window: x from the window's left, y from the window's top down to the region's top.
local function box(W, win, region)
    local w, r = W.rect(win), W.rect(region)
    return r[1] - w[1], (w[2] + w[4]) - (r[2] + r[4]), r[3], r[4]
end

-- How far below the window's top a region begins.
local function at(W, win, region)
    local _, y = box(W, win, region)
    return y
end

-- The chimes played so far.
local function chimes(W)
    local out = {}
    for _, s in ipairs(W.sounds) do
        if s.file == CHIME then out[#out + 1] = s end
    end
    return out
end

-- Stand-ins for Task 12's two views: 120 px high, counting their refreshes.
local function stubViews(G, ns)
    local made = {}
    for _, name in ipairs({ "recent", "settings" }) do
        T.eq(ns.UI.RegisterView(name, function(parent)
            local f = G.CreateFrame("Frame", nil, parent)
            f.refreshed = 0
            function f:Refresh() self.refreshed = self.refreshed + 1 end
            function f:Height() return 120 end
            made[name] = f
            return f
        end), true, "registered " .. name)
    end
    return made
end

local function iconColor(button) return { button.icon:GetVertexColor() } end

-- A client whose error handler records the errors (the fake's own raises them). -> opts for setup
local function recording(errors)
    return { setup = function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
    end }
end

-- Is the colour c ({ r, g, b, ... }) the expected one ({ r, g, b, ... })?
local function same(c, expected, msg)
    T.near(c[1], expected[1], 1e-6, (msg or "colour") .. " red")
    T.near(c[2], expected[2], 1e-6, (msg or "colour") .. " green")
    T.near(c[3], expected[3], 1e-6, (msg or "colour") .. " blue")
end

-- How high the window's cards are, together (the card decides its own height: view:Height()).
local function heights(win, cards)
    local sum = 0
    for _, card in ipairs(cards) do sum = sum + win.views[card]:Height() end
    return sum
end

-------------------------------------------------------------------------------
--  Opening and stacking
-------------------------------------------------------------------------------
T.it("a new roll opens the window at TOPLEFT 372/−226", function()
    local G, W, ns, win = setup()
    T.ok(win, "the global frame TuttiFrame")
    T.no(win:IsShown(), "hidden until a roll starts")
    T.eq(win:GetParent(), G.UIParent)
    T.eq(win:GetFrameStrata(), "HIGH")
    T.ok(win._clamped, "kept on screen")
    T.ok(win._movable, "movable")
    local card = roll(W, ns, 1)
    T.ok(win:IsShown(), "the roll opens it")
    T.eq(ns.UI.View(), "rolls")
    T.eq(win:GetAlpha(), 0, "it rises: from nothing")
    local _, _, _, _, y = win:GetPoint(1)
    T.eq(y, -226 - 8, "from 8 px below its place")
    W.advance(0.35)
    local point, rel, relPoint, x
    point, rel, relPoint, x, y = win:GetPoint(1)
    T.eq(point, "TOPLEFT")
    T.eq(rel, G.UIParent)
    T.eq(relPoint, "TOPLEFT")
    T.eq(x, 372)
    T.eq(y, -226)
    T.eq(win:GetAlpha(), 1)
    T.eq(win:GetScale(), 1)
    T.eq(win:GetWidth(), 300)
    T.eq(win:GetHeight(), 32 + heights(win, { card }), "the header and the card")
    T.eq(text(W, win.head.title), "Loot rolls")
    T.ok(win.head.mark:IsShown(), "the mark leads")
    T.no(win.head.back:IsShown())
    local view = win.views[card]
    T.eq(text(W, view.time), "· 60s")
    local bar = view.bar:GetWidth()
    W.advance(10)
    T.eq(text(W, view.time), "· 50s", "the window ticks its cards' countdowns")
    T.ok(view.bar:GetWidth() < bar, "and their bars")
end)

T.it("cards stack in arrival order and the pill counts live cards", function()
    local G, W, ns, win = setup()
    local a, b, c = roll(W, ns, 1), roll(W, ns, 2), roll(W, ns, 3)
    W.advance(0.35)
    local va, vb, vc = win.views[a], win.views[b], win.views[c]
    T.eq(at(W, win, va), 32, "the first card right under the header")
    T.eq(at(W, win, vb), 32 + va:Height(), "the second under it")
    T.eq(at(W, win, vc), 32 + va:Height() + vb:Height(), "the third last: the order they came in")
    T.no(va.divider:IsShown(), "no hairline between the header and the first card")
    T.ok(vb.divider:IsShown() and vc.divider:IsShown(), "a hairline above the others")
    T.eq(win:GetHeight(), 32 + heights(win, { a, b, c }))
    T.eq(text(W, win.head.count), "3", "three live cards")
    local before = vb:Height()
    vb.buttons.pass:Click()
    decide(G, W, 2, ORLEN, 19)
    T.eq(text(W, win.head.count), "2", "a decided card is not counted")
    T.ok(vb:Height() < before, "the decided card lost its buttons")
    T.eq(at(W, win, vc), 32 + va:Height() + vb:Height(), "and the next one moved up")
    va.buttons.pass:Click()
    vc.buttons.pass:Click()
    decide(G, W, 1, ORLEN, 20)
    decide(G, W, 3, ORLEN, 21)
    T.no(win.head.pill:IsShown(), "no pill without live cards")
end)

T.it("the header follows the mockup: mark, title, pill, buttons and the line under it", function()
    local G, W, ns, win = setup()
    local card = roll(W, ns, 1)
    W.advance(0.35)
    local head = win.head
    T.eq(head:GetHeight(), 32)
    local x, y, w, h = box(W, win, head.mark)
    T.eq(x, 10, "the mark 10 px in")
    T.eq(w, 15)
    T.eq(y + h / 2, 15.5, "centred on the 31 px above the hairline")
    local tx, _, tw = box(W, win, head.title)
    T.eq(tx, 32, "the title 7 px after the mark")
    x, y, w, h = box(W, win, head.pill)
    T.eq(x, tx + tw + 7, "the pill 7 px after the title")
    T.eq(w, 17, "17 px wide for one digit")
    T.eq(h, 15)
    T.eq(y + h / 2, 15.5)
    x, _, w = box(W, win, head.close)
    T.eq(x + w, 295, "the close button 5 px from the right")
    T.eq(w, 22)
    x, _, w = box(W, win, head.gear)
    T.eq(x + w, 266, "the gear 7 px before it")
    x, _, w = box(W, win, head.clock)
    T.eq(x + w, 237, "the clock 7 px before the gear")
    same(iconColor(head.clock), { ns.Theme.Color("dim") })
    T.eq(head.clock.icon:GetWidth(), 14, "14 px glyphs")

    win.views[card].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    x, _, w = box(W, win, head.closes)
    T.eq(x + w, 205, "'closes in' ends 3 px and a gap before the clock")
    x, y, w, h = box(W, win, head.bar)
    T.eq(x, 0, "the accent line from the left edge")
    T.near(y + h, 32, 1e-6, "on the header's bottom pixel")
    T.near(h, ns.W.Pixel(head), 1e-6, "one pixel high")
    T.eq(w, 300)
    local r, g, b = ns.Theme.Accent()
    local c = head.bar._color
    same(c, { r, g, b }, "the accent")
    T.near(c[4], 0.85, 1e-6, "at 85 %")
end)

-------------------------------------------------------------------------------
--  Folding
-------------------------------------------------------------------------------
T.it("a decided card folds after 4 s while another is open; the last stays", function()
    local G, W, ns, win = setup()
    local a, b = roll(W, ns, 1), roll(W, ns, 2)
    W.advance(1)
    win.views[a].buttons.greed:Click()
    decide(G, W, 1, ORLEN, 19)
    W.advance(3.9)
    T.no(win.done:IsShown(), "whole for 4 s")
    T.ok(win.views[a]:Height() > 26)
    W.advance(0.1)
    T.ok(win.done:IsShown(), "then a line under DONE")
    T.eq(text(W, win.done.label), "DONE")
    T.eq(win.views[a]:Height(), 26, "folded")
    local open = win.views[b]:Height()
    T.eq(at(W, win, win.views[b]), 32, "the open card moves to the top")
    T.no(win.views[b].divider:IsShown())
    T.eq(at(W, win, win.done), 32 + open, "the section under the open cards")
    T.ok(win.done.hair:IsShown(), "with its hairline")
    T.eq(at(W, win, win.views[a]), 32 + open + 23, "the folded line under the label")
    T.eq(win:GetHeight(), 32 + open + 23 + 26 + 2, "and 2 px after the last folded line")

    -- The last decided card stays whole.
    win.views[b].buttons.pass:Click()
    decide(G, W, 2, BRISE, 52)
    W.advance(5)
    T.ok(win.views[b]:Height() > 26, "the last decided card stays whole")
    T.eq(win.views[a]:Height(), 26, "the other stays folded")
    T.eq(win:GetHeight(), 32 + win.views[b]:Height() + 23 + 26 + 2)
end)

-------------------------------------------------------------------------------
--  Closing
-------------------------------------------------------------------------------
T.it("closing: 'closes in 10s', hidden after 10 s, cards forgotten", function()
    local G, W, ns, win = setup()
    local card = roll(W, ns, 1)
    W.advance(0.35)
    T.eq(text(W, win.head.closes), "", "no countdown while a roll is on")
    win.views[card].buttons.greed:Click()
    decide(G, W, 1, ORLEN, 19)
    T.eq(text(W, win.head.closes), "closes in 10s")
    T.ok(win.head.bar:IsShown())
    T.eq(win.head.bar:GetWidth(), 300, "the line full at the start")
    W.advance(3)
    T.eq(text(W, win.head.closes), "closes in 7s")
    T.near(win.head.bar:GetWidth(), 210, 1e-6, "and running down with it")
    W.advance(6.9)
    T.ok(win:IsShown())
    T.eq(text(W, win.head.closes), "closes in 1s")
    W.advance(0.1)
    T.ok(win:IsShown(), "at 0 it sinks first")
    T.eq(#ns.Rolls.Cards(), 1, "the card is still there while it fades")
    W.advance(0.3)
    T.ok(win:GetAlpha() < 1, "fading")
    W.advance(0.25)
    T.no(win:IsShown(), "then it is hidden")
    T.eq(#ns.Rolls.Cards(), 0, "and the decided cards are forgotten")
    T.eq(win.views[card], nil, "their views are back in the pool")
    T.eq(win:GetAlpha(), 1, "at rest for the next time")
end)

T.it("hover pauses, leave resumes", function()
    local G, W, ns, win = setup()
    local card = roll(W, ns, 1)
    win.views[card].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    W.advance(4)
    T.eq(text(W, win.head.closes), "closes in 6s")
    win._mouseOver = true
    W.advance(0.01)
    T.eq(text(W, win.head.closes), "kept open")
    T.eq(win.head.bar:GetWidth(), 300, "the line full while it waits")
    W.advance(30)
    T.ok(win:IsShown(), "it waits as long as the mouse is over it")
    T.eq(text(W, win.head.closes), "kept open")
    win._mouseOver = false
    W.advance(0.01)
    T.eq(text(W, win.head.closes), "closes in 6s", "it goes on from where it stopped")
    T.near(win.head.bar:GetWidth(), 300 * 5.99 / 10, 1e-6)
    W.advance(5.9)
    T.ok(win:IsShown())
    W.advance(0.2)
    W.advance(0.55)
    T.no(win:IsShown())
end)

T.it("closeAfter 0 never closes", function()
    local G, W, ns, win = setup()
    ns.Set("closeAfter", 0)
    local card = roll(W, ns, 1)
    win.views[card].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    T.eq(text(W, win.head.closes), "", "no countdown")
    T.no(win.head.bar:IsShown())
    W.advance(600)
    T.ok(win:IsShown(), "still there")
    -- Another choice applies to the next countdown at once.
    ns.Set("closeAfter", 5)
    T.eq(text(W, win.head.closes), "closes in 5s")
    W.advance(5.1)
    W.advance(0.55)
    T.no(win:IsShown())
end)

-- Review focus 4.
T.it("a new roll cancels the countdown", function()
    local G, W, ns, win = setup()
    local a = roll(W, ns, 1)
    win.views[a].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    W.advance(4)
    T.eq(text(W, win.head.closes), "closes in 6s")
    local b = roll(W, ns, 2)
    T.eq(text(W, win.head.closes), "", "the countdown stops")
    T.no(win.head.bar:IsShown(), "and its line goes")
    W.advance(30)
    T.ok(win:IsShown(), "the window stays")

    -- Even while it fades out.
    win.views[b].buttons.pass:Click()
    decide(G, W, 2, ORLEN, 40)
    W.advance(10)
    W.advance(0.2)
    T.ok(win:IsShown() and win:GetAlpha() < 1, "fading out")
    local c = roll(W, ns, 3)
    T.ok(win:IsShown(), "a roll during the fade keeps the window")
    T.eq(win:GetAlpha(), 1, "back at once")
    W.advance(1)
    T.ok(win:IsShown())
    T.eq(ns.Rolls.Get(a.id), a, "the decided cards are not forgotten")
    T.ok(win.views[c], "and the new card is in")
    T.eq(text(W, win.head.closes), "")
end)

-- Review focus 4.
T.it("a new roll leaves Recent or Settings", function()
    local G, W, ns, win = setup()
    local pages = stubViews(G, ns)
    T.eq(ns.UI.Open("recent"), true)
    T.eq(ns.UI.View(), "recent")
    T.eq(text(W, win.head.title), "Recent rolls")
    local a = roll(W, ns, 1)
    T.eq(ns.UI.View(), "rolls", "the roll brings the rolls")
    T.eq(text(W, win.head.title), "Loot rolls")
    T.no(pages.recent:IsShown(), "Recent rolls makes way")
    T.ok(win.rolls:IsVisible())
    ns.UI.Open("settings")
    T.eq(ns.UI.View(), "settings")
    T.eq(text(W, win.head.title), "Settings")
    local b = roll(W, ns, 2)
    T.eq(ns.UI.View(), "rolls", "from Settings too")
    T.no(pages.settings:IsShown())
    T.eq(win:GetHeight(), 32 + heights(win, { a, b }))
end)

T.it("the close button hides while a card awaits the player", function()
    local G, W, ns, win = setup()
    local a = roll(W, ns, 1)
    T.no(win.head.close:IsShown(), "hidden: the card waits on the player")
    win.views[a].buttons.greed:Click()
    T.ok(win.head.close:IsShown(), "back once the player picked")
    local b = roll(W, ns, 2)
    T.no(win.head.close:IsShown(), "hidden again for the next card")
    win.views[b].buttons.pass:Click()
    T.ok(win.head.close:IsShown())
    win.head.close:Click()
    W.advance(0.55)
    T.no(win:IsShown(), "it closes the window")
end)

T.it("Close never hides a card that waits on the player", function()
    local G, W, ns, win = setup()
    stubViews(G, ns)
    local card = roll(W, ns, 1)
    ns.UI.Open("recent")
    T.eq(ns.UI.Toggle("recent"), false, "a toggle cannot close it")
    T.eq(ns.UI.View(), "rolls", "it shows the card instead")
    W.advance(1)
    T.ok(win:IsShown())
    win.views[card].buttons.greed:Click()
    T.eq(ns.UI.Close(), true)
    W.advance(0.55)
    T.no(win:IsShown())
    T.eq(#ns.Rolls.Cards(), 1, "a card still rolling stays")
end)

T.it("a card that starts waiting on the player brings the window back", function()
    local G, W, ns, win = setup()
    -- The history has the drop before the player's roll starts: a card without buttons.
    W.setDrop(9, 1, drop(G, W, 1, { rollInfo(G, ORLEN, "NeedMainSpec") }))
    T.ok(win:IsShown())
    T.ok(win.head.close:IsShown(), "nothing waits on the player yet")
    ns.UI.Close()
    W.advance(0.55)
    T.no(win:IsShown())
    local card = roll(W, ns, 1)
    T.eq(#ns.Rolls.Cards(), 1, "the roll joins the history's card")
    T.ok(win:IsShown(), "and the window comes back for it")
    T.eq(ns.UI.View(), "rolls")
    T.ok(win.views[card].buttons.need:IsVisible())
    T.no(win.head.close:IsShown())
end)

-------------------------------------------------------------------------------
--  Views
-------------------------------------------------------------------------------
T.it("the clock and the gear open Recent rolls and Settings, the back arrow comes back", function()
    local G, W, ns, win = setup()
    T.eq(ns.UI.Open("recent"), false, "nothing to open before the view is registered")
    T.no(win:IsShown())
    local pages = stubViews(G, ns)
    local card = roll(W, ns, 1)
    W.advance(0.35)
    local head = win.head
    head.clock:Click()
    T.eq(ns.UI.View(), "recent")
    T.eq(text(W, head.title), "Recent rolls")
    T.ok(head.back:IsShown() and not head.mark:IsShown(), "the back arrow leads")
    T.eq(box(W, win, head.back), 10)
    T.eq(box(W, win, head.title), 39, "the title 7 px after the arrow")
    T.ok(pages.recent:IsVisible())
    T.eq(pages.recent.refreshed, 1)
    T.no(win.rolls:IsVisible(), "the cards make way")
    T.eq(win:GetHeight(), 32 + 120, "the view's own height")
    T.no(head.pill:IsShown(), "no count outside the rolls")
    same(iconColor(head.clock), { ns.Theme.Accent() }, "the clock in the accent while its view shows")
    same(iconColor(head.gear), { ns.Theme.Color("dim") })
    head.clock:_fire("OnEnter")
    same(iconColor(head.clock), { ns.Theme.Accent() }, "hovered too")
    head.clock:Click()
    T.eq(ns.UI.View(), "rolls", "the clock again goes back")
    same(iconColor(head.clock), { ns.Theme.Color("text") }, "still under the mouse: the hover's white")
    head.clock:_fire("OnLeave")
    same(iconColor(head.clock), { ns.Theme.Color("dim") })
    head.gear:Click()
    T.eq(ns.UI.View(), "settings")
    T.eq(text(W, head.title), "Settings")
    same(iconColor(head.gear), { ns.Theme.Accent() })
    T.eq(pages.settings.refreshed, 1)
    head.back:Click()
    T.eq(ns.UI.View(), "rolls")
    T.eq(text(W, head.title), "Loot rolls")
    T.ok(head.mark:IsShown())
    T.eq(win:GetHeight(), 32 + heights(win, { card }))
end)

T.it("without cards the rolls view says so and closes itself", function()
    local G, W, ns, win = setup()
    stubViews(G, ns)
    ns.UI.Open("recent")
    W.advance(0.35)
    T.ok(win:IsShown())
    T.eq(text(W, win.head.closes), "", "Recent rolls never closes by itself")
    W.advance(30)
    T.ok(win:IsShown())
    win.head.back:Click()
    T.eq(text(W, win.empty), "No rolls right now")
    T.eq(win:GetHeight(), 32 + 28)
    T.eq(text(W, win.head.closes), "closes in 10s")
    W.advance(10.1)
    W.advance(0.55)
    T.no(win:IsShown())
end)

-------------------------------------------------------------------------------
--  Position, scale, height
-------------------------------------------------------------------------------
T.it("dragging saves the position", function()
    local G, W, ns, win = setup()
    roll(W, ns, 1)
    W.advance(0.35)
    win.head:_fire("OnDragStart")
    T.ok(win._moving, "the header moves the window")
    -- The game moves the window with the mouse and anchors it its own way.
    win:ClearAllPoints()
    win:SetPoint("BOTTOMLEFT", G.UIParent, "BOTTOMLEFT", 500.4, 300)
    win.head:_fire("OnDragStop")
    T.no(win._moving)
    local saved = ns.DB.window
    T.eq(saved.point, "TOPLEFT")
    T.eq(saved.x, 500)
    T.eq(saved.y, 300 + win:GetHeight() - 1080, "its top, from the top of the screen")
    local point, rel, relPoint, x, y = win:GetPoint(1)
    T.eq(point, "TOPLEFT")
    T.eq(rel, G.UIParent)
    T.eq(relPoint, "TOPLEFT")
    T.eq(x, 500)
    T.eq(y, saved.y)
    T.eq(win:GetNumPoints(), 1, "anchored by its top-left only, so it grows downwards")

    -- The next session opens it there.
    local G2, W2, ns2, win2 = setup({ db = { window = { point = "TOPLEFT", x = 500, y = saved.y } } })
    roll(W2, ns2, 1)
    W2.advance(0.35)
    point, rel, relPoint, x, y = win2:GetPoint(1)
    T.eq(x, 500)
    T.eq(y, saved.y)
end)

T.it("scale applies", function()
    local G, W, ns, win = setup({ db = { settings = { scale = 0.8 } } })
    T.eq(win:GetScale(), 0.8, "the saved size from the start")
    roll(W, ns, 1)
    W.advance(0.35)
    local _, _, _, x, y = win:GetPoint(1)
    T.near(x * 0.8, 372, 1e-6, "the top-left corner stays where it was saved")
    T.near(y * 0.8, -226, 1e-6)
    ns.Set("scale", 1.2)
    T.eq(win:GetScale(), 1.2, "a new size applies at once")
    _, _, _, x, y = win:GetPoint(1)
    T.near(x * 1.2, 372, 1e-6, "and the corner stays put")
    T.near(y * 1.2, -226, 1e-6)
end)

T.it("many cards: height capped at 70 % and scrolling", function()
    local G, W, ns, win = setup()
    local cards = {}
    for n = 1, 5 do cards[n] = roll(W, ns, n) end
    W.advance(0.35)
    local total = heights(win, cards)
    T.ok(32 + total > 0.7 * 1080, "five cards would pass 70 % of the screen")
    T.eq(win:GetHeight(), 0.7 * 1080, "so the window stops at 70 %")
    T.eq(win.scroll:GetHeight(), 0.7 * 1080 - 32, "and the cards scroll under the header")
    T.eq(win.content:GetHeight(), total)
    T.ok(win.thumb:IsShown(), "a thumb shows there is more")
    T.eq(win.scroll:GetVerticalScroll(), 0)
    win.scroll:_fire("OnMouseWheel", -1)
    T.eq(win.scroll:GetVerticalScroll(), 40, "the wheel scrolls")
    T.eq(at(W, win, win.views[cards[1]]), 32 - 40, "the cards move up")
    for _ = 1, 30 do win.scroll:_fire("OnMouseWheel", -1) end
    T.eq(win.scroll:GetVerticalScroll(), total - (0.7 * 1080 - 32), "as far as the last card")
    for _, card in ipairs(cards) do win.views[card].buttons.pass:Click() end
    total = heights(win, cards)
    T.eq(win.content:GetHeight(), total)
    T.eq(win.scroll:GetVerticalScroll(), total - (0.7 * 1080 - 32), "the scroll follows a shorter list")
    for _ = 1, 30 do win.scroll:_fire("OnMouseWheel", 1) end
    T.eq(win.scroll:GetVerticalScroll(), 0, "and back to the top")
    -- Bigger, the window still keeps to 70 % of the screen.
    ns.Set("scale", 1.2)
    T.near(win:GetHeight() * 1.2, 0.7 * 1080, 1e-6)
    -- Few cards: no scrolling.
    for n = 1, 5 do decide(G, W, n, ORLEN, 10 + n) end
    W.advance(10.1)
    W.advance(0.55)
    T.no(win:IsShown())
    local card = roll(W, ns, 1)
    T.eq(win:GetHeight(), 32 + heights(win, { card }))
    T.no(win.thumb:IsShown())
    T.eq(win.scroll:GetVerticalScroll(), 0)
end)

-- A card whose Need is refused: the reason under its buttons makes it 218 px, more than a scale of 1.3 leaves
-- room for under two cards the player has rolled on (2 × 171 + 218 > 549.5).
local REFUSED = { canNeed = false, reasonNeed = 1 }

-- Whether a card shows whole between the header and the window's bottom.
local function whole(W, win, card)
    local y = at(W, win, win.views[card])
    return y >= 32 - 1e-6 and y + win.views[card]:Height() <= 32 + win.scroll:GetHeight() + 1e-6
end

T.it("cards that wait on the player bring the first of them into sight, unless the player scrolled by hand", function()
    local G, W, ns, win = setup()
    ns.Set("scale", 1.3) -- the largest size: a boss drop of three is more than the window holds
    local cards = {}
    for n = 1, 3 do cards[n] = roll(W, ns, n, REFUSED) end -- three rolls at once
    W.advance(0.35)
    local visible = win.scroll:GetHeight()
    T.ok(heights(win, cards) > visible, "the window scrolls")
    T.eq(at(W, win, win.views[cards[1]]), 32, "the first card at the top of what shows: the player works down")
    -- The player has rolled on the first two; the third is cut off at the bottom until the next roll comes.
    win.views[cards[1]].buttons.pass:Click()
    win.views[cards[2]].buttons.pass:Click()
    T.no(whole(W, win, cards[3]), "cut off at the bottom")
    cards[4] = roll(W, ns, 4)
    T.ok(whole(W, win, cards[3]), "the first card still waiting comes into sight, whole")
    T.eq(win.scroll:GetVerticalScroll(), win.content:GetHeight() - visible, "its top to the top, as far as it goes")
    -- The player scrolls by hand: nothing scrolls by itself any more.
    for _ = 1, 30 do win.scroll:_fire("OnMouseWheel", 1) end
    T.no(whole(W, win, cards[3]))
    cards[5] = roll(W, ns, 5)
    T.eq(win.scroll:GetVerticalScroll(), 0, "the player's own scroll stays")
    -- Until the window has closed and opened again.
    for n = 1, 5 do
        if ns.Rolls.AwaitsMe(cards[n]) then win.views[cards[n]].buttons.pass:Click() end
        decide(G, W, n, ORLEN, 10 + n)
    end
    W.advance(10.1)
    W.advance(0.55)
    T.no(win:IsShown())
    for n = 1, 3 do cards[n] = roll(W, ns, n, REFUSED) end
    win.views[cards[1]].buttons.pass:Click()
    win.views[cards[2]].buttons.pass:Click()
    cards[4] = roll(W, ns, 4)
    T.ok(whole(W, win, cards[3]), "a new opening, a new start")
end)

-------------------------------------------------------------------------------
--  Sound
-------------------------------------------------------------------------------
T.it("the chime plays once when the player wins; never with sound none", function()
    local G, W, ns, win = setup()
    local a = roll(W, ns, 1)
    win.views[a].buttons.need:Click()
    decide(G, W, 1, AYLA, 87)
    local played = chimes(W)
    T.eq(#played, 1, "the chime")
    T.eq(played[1].channel, "Master")
    W.advance(5)
    T.eq(#chimes(W), 1, "once")
    local b = roll(W, ns, 2)
    win.views[b].buttons.need:Click()
    decide(G, W, 2, ORLEN, 99)
    T.eq(#chimes(W), 1, "not for someone else's win")
    ns.Set("sound", "none")
    local c = roll(W, ns, 3)
    win.views[c].buttons.need:Click()
    decide(G, W, 3, AYLA, 90)
    T.eq(#chimes(W), 1, "never with sound none")
end)

-------------------------------------------------------------------------------
--  A decision after the end (R21)
-------------------------------------------------------------------------------
T.it("a late decision restarts the countdown and plays the chime (R21)", function()
    local G, W, ns, win = setup()
    local began = G.C_LootHistory.GetLootHistoryTime() -- the roll's drop begins with it, on the history's clock
    local card = roll(W, ns, 1)
    win.views[card].buttons.need:Click()
    W.advance(66)
    T.eq(card.status, "ended")
    T.eq(text(W, win.head.closes), "closes in 10s", "an ended roll counts as over")
    W.advance(6)
    T.eq(text(W, win.head.closes), "closes in 4s")
    decide(G, W, 1, AYLA, 87, { startTime = began })
    T.eq(card.status, "decided")
    T.eq(text(W, win.head.closes), "closes in 10s", "the late winner gets the whole countdown")
    T.eq(#chimes(W), 1, "the player won: the chime")
    W.advance(9)
    T.ok(win:IsShown())
end)

T.it("a folded card decided late comes back whole and folds again 4 s later (R21)", function()
    local G, W, ns, win = setup()
    local washes, pops = {}, {}
    ns.Fx.Wash = function(tex) washes[#washes + 1] = tex end
    ns.Fx.Pop = function(frame) pops[#pops + 1] = frame end
    local began = G.C_LootHistory.GetLootHistoryTime()
    local a = roll(W, ns, 1)
    win.views[a].buttons.greed:Click()
    W.advance(30)
    local b = roll(W, ns, 2)
    W.advance(36)
    T.eq(a.status, "ended")
    local whole = win.views[a]:Height()
    W.advance(4)
    T.eq(win.views[a]:Height(), 26, "the ended card folds while the other is open")
    T.eq(#washes + #pops, 0, "an end without a winner plays nothing")
    decide(G, W, 1, ORLEN, 19, { startTime = began })
    T.eq(a.status, "decided")
    T.eq(win.views[a]:Height(), whole, "the late winner shows on the whole card")
    local orlen = win.views[a].rows[1]
    T.eq(#washes, 1, "one wash")
    T.eq(washes[1], orlen.wash, "on the winner's row")
    T.eq(#pops, 1, "one crown pop")
    T.eq(pops[1], orlen.crown)
    T.no(win.done:IsShown())
    T.eq(at(W, win, win.views[a]), 32, "back in its place among the open cards")
    W.advance(3.9)
    T.eq(win.views[a]:Height(), whole)
    W.advance(0.1)
    T.eq(win.views[a]:Height(), 26, "4 s after the new decision it folds again")
    T.eq(b.status, "live")
    T.eq(#washes, 1, "and nothing plays twice")
    T.eq(#pops, 1)
end)

-------------------------------------------------------------------------------
--  The group, Polestar
-------------------------------------------------------------------------------
T.it("a group change redraws every card and the window's height", function()
    local G, W, ns, win = setup()
    local a, b = roll(W, ns, 1), roll(W, ns, 2)
    local five = win.views[a]:Height()
    T.eq(win:GetHeight(), 32 + heights(win, { a, b }))
    local four = party()
    table.remove(four, 4)
    W.setGroup(four)
    T.eq(win.views[a]:Height(), five - 21, "one row of 21 px less")
    T.eq(at(W, win, win.views[b]), 32 + five - 21)
    T.eq(win:GetHeight(), 32 + heights(win, { a, b }))
    T.eq(win:GetHeight(), 32 + 2 * (five - 21))
end)

T.it("Polestar's note sits under the window while both show", function()
    local G, W, ns, win = setup()
    -- Polestar's frame, placed as Polestar places it when it finds no Blizzard roll frame showing.
    local note = G.CreateFrame("Frame", "PolestarLootNeeds", G.UIParent)
    note:Hide()
    local function paint()
        note:ClearAllPoints()
        note:SetPoint("TOP", G.UIParent, "TOP", 0, -160)
        note:Show()
    end
    local a = roll(W, ns, 1)
    paint()
    W.advance(0.1)
    local point, rel, relPoint, x, y = note:GetPoint(1)
    T.eq(rel, win, "under the window")
    T.eq(point, "TOPLEFT")
    T.eq(relPoint, "BOTTOMLEFT")
    T.eq(x, 0)
    T.eq(y, -4)
    paint()
    T.eq(select(2, note:GetPoint(1)), win, "Polestar placing it again: under the window at once")
    win.views[a].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    W.advance(10.1)
    W.advance(0.55)
    T.no(win:IsShown())
    point, rel, relPoint, x, y = note:GetPoint(1)
    T.eq(rel, G.UIParent, "the window gone, the note goes back where Polestar put it")
    T.eq(point, "TOP")
    T.eq(y, -160)
    -- Under a Blizzard frame Polestar chose, it stays.
    local loot = G.CreateFrame("Frame", "LootFrame", G.UIParent)
    roll(W, ns, 2)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", loot, "BOTTOMLEFT", 0, -4)
    note:Show()
    W.advance(0.1)
    T.eq(select(2, note:GetPoint(1)), loot, "left under the loot window")
    -- A place the game will not say is not taken: it could not be given back.
    note.GetPoint = function() return T.secret("TOP"), G.UIParent, T.secret("TOP"), 0, -160 end
    note:Show()
    T.eq(note._points[1][2], loot, "a note whose anchor is secret stays where it is")
end)

-------------------------------------------------------------------------------
--  Review round 1
-------------------------------------------------------------------------------
T.it("a new size repaints every hairline at once", function()
    local G, W, ns, win = setup()
    roll(W, ns, 1)
    local b = roll(W, ns, 2) -- the second card shows its hairline
    W.advance(0.35)
    ns.Set("scale", 1.2)
    local view = win.views[b]
    T.near(ns.W.Pixel(view), 768 / 1080 / 1.2, 1e-9, "a pixel is less in the window's own units")
    T.near(view.divider:GetHeight(), ns.W.Pixel(view), 1e-9, "a card's hairline is one pixel at the new size")
    T.near(win.head.hair:GetHeight(), ns.W.Pixel(win.head), 1e-9, "and so is the header's")
end)

T.it("a card whose countdown fails stops neither the folds nor the closing", function()
    local errors = {}
    local G, W, ns, win = setup(recording(errors))
    local a, b = roll(W, ns, 1), roll(W, ns, 2)
    win.views[a].Tick = function() error("broken countdown") end
    W.advance(1)
    T.eq(#errors, 1, "the error is reported")
    T.ok(errors[1]:find("broken countdown", 1, true))
    W.advance(1)
    T.eq(#errors, 1, "once")
    win.views[a].buttons.pass:Click()
    win.views[b].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19)
    W.advance(1)
    decide(G, W, 2, ORLEN, 20)
    W.advance(4)
    T.eq(win.views[a]:Height(), 26, "the folds go on")
    T.eq(text(W, win.head.closes), "closes in 6s", "and the countdown")
    W.advance(6.1)
    W.advance(0.55)
    T.no(win:IsShown(), "the window closes")
end)

T.it("a view whose builder fails is built once and reported once", function()
    local errors = {}
    local G, W, ns, win = setup(recording(errors))
    local built, raised = 0, 0
    ns.UI.RegisterView("recent", function(parent)
        built = built + 1
        return G.CreateFrame("Frame", nil, parent) -- no :Refresh(), no :Height()
    end)
    ns.UI.RegisterView("settings", function()
        raised = raised + 1
        error("no settings today")
    end)
    T.eq(ns.UI.Open("recent"), false, "a view without Refresh and Height does not open")
    T.eq(ns.UI.Open("recent"), false)
    T.eq(ns.UI.Toggle("recent"), false)
    T.eq(built, 1, "its frames are made once")
    T.eq(ns.UI.Open("settings"), false, "a builder that raises does not open")
    T.eq(ns.UI.Open("settings"), false)
    T.eq(raised, 1, "and is not called again")
    T.eq(#errors, 2, "each is reported once")
    T.ok(errors[1]:find("recent", 1, true), "naming the view")
    T.ok(errors[2]:find("no settings today", 1, true))
    T.no(win:IsShown())
end)

-------------------------------------------------------------------------------
--  Review round 2 (R42)
-------------------------------------------------------------------------------
T.it("a fold above the first waiting card leaves that card whole in sight", function()
    local G, W, ns, win = setup()
    ns.Set("scale", 1.3)
    local a, b = roll(W, ns, 1), roll(W, ns, 2)
    W.advance(0.35)
    win.views[a].buttons.pass:Click()
    win.views[b].buttons.pass:Click()
    decide(G, W, 1, ORLEN, 19) -- the first card folds 4 s from now
    -- Three drops the history shows first: cards without buttons, nothing to bring into sight yet.
    for n = 3, 5 do W.setDrop(9, n, drop(G, W, n, { rollInfo(G, ORLEN, "NeedMainSpec") })) end
    T.eq(win.scroll:GetVerticalScroll(), 0)
    -- The player's roll for the third joins its card, which now waits on them and is cut off at the bottom.
    roll(W, ns, 3, REFUSED)
    local c = ns.Rolls.Cards()[3]
    T.ok(ns.Rolls.AwaitsMe(c), "the third card waits on the player")
    T.eq(at(W, win, win.views[c]), 32, "it comes to the top of what shows")
    W.advance(4)
    T.eq(win.views[a]:Height(), 26, "the decided card above it folds")
    T.eq(at(W, win, win.views[c]), 32, "the waiting card stays where it was, whole")
    T.ok(whole(W, win, c))
end)

T.it("a waiting card already whole in sight is not scrolled to", function()
    local G, W, ns, win = setup()
    ns.Set("scale", 1.3)
    local a, b = roll(W, ns, 1), roll(W, ns, 2)
    W.advance(0.35)
    win.views[a].buttons.pass:Click() -- the second card, still waiting, shows whole under the first
    T.ok(whole(W, win, b))
    roll(W, ns, 3) -- more than the window holds now
    T.ok(win.content:GetHeight() > win.scroll:GetHeight(), "the rolls can scroll")
    T.eq(win.scroll:GetVerticalScroll(), 0, "nothing moves under the mouse")
    T.eq(at(W, win, win.views[b]), 32 + win.views[a]:Height())
end)

T.it("only a wheel that moves the rolls stops them coming into sight by themselves", function()
    local G, W, ns, win = setup()
    ns.UI.RegisterView("recent", function(parent) -- a long list of results, which scrolls
        local f = G.CreateFrame("Frame", nil, parent)
        function f:Refresh() end
        function f:Height() return 2000 end
        return f
    end)
    ns.Set("scale", 1.3)
    local cards = {}
    for n = 1, 3 do cards[n] = roll(W, ns, n, REFUSED) end
    W.advance(0.35)
    win.scroll:_fire("OnMouseWheel", 1) -- at the top already: it moves nothing
    T.eq(win.scroll:GetVerticalScroll(), 0)
    ns.UI.Open("recent")
    win.scroll:_fire("OnMouseWheel", -1)
    T.eq(win.scroll:GetVerticalScroll(), 40, "Recent rolls scrolls")
    ns.UI.Open("rolls")
    win.views[cards[1]].buttons.pass:Click()
    win.views[cards[2]].buttons.pass:Click()
    T.no(whole(W, win, cards[3]))
    cards[4] = roll(W, ns, 4)
    T.ok(win.scroll:GetVerticalScroll() > 0, "the rolls still scroll by themselves")
    T.ok(whole(W, win, cards[3]), "to the first card still waiting")
end)

T.it("a size the client reads back rounded is not a new size", function()
    local G, W, ns, win = setup({ db = { settings = { scale = 1.1 } } })
    -- The client keeps a frame's scale as a 32-bit float: 1.1 reads back as 1.100000023841858.
    local ffi = require("ffi")
    local float = ffi.new("float[1]")
    win.GetScale = function(self)
        float[0] = self._scale
        return tonumber(float[0])
    end
    T.ok(win:GetScale() ~= 1.1, "the read-back differs from the setting")
    local repaints = 0
    ns.Listen("LOOKS_CHANGED", function() repaints = repaints + 1 end)
    roll(W, ns, 1)
    W.advance(0.35)
    T.eq(repaints, 0, "opening at the saved size repaints nothing")
    win.head:_fire("OnDragStart")
    win.head:_fire("OnDragStop")
    T.eq(repaints, 0, "nor does a drag")
    ns.Set("scale", 1.2)
    T.eq(repaints, 1, "a new size repaints, once")
end)
