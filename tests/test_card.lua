local T = T

-------------------------------------------------------------------------------
--  The scene: the party of the other tests and their Dualblade
-------------------------------------------------------------------------------
-- A two-hand axe, item 18000, rare, item level 33.
local AXE = 18000
local function axeInfo()
    return { name = "Guardian's Dualblade", quality = 3, ilvl = 33, classID = 2, subclassID = 1,
        equipLoc = "INVTYPE_2HWEAPON", texture = 135348 }
end

-- A holdable, item 18001: its label, "Held In Off-hand", is the longest a subtitle has.
local ORB = 18001
local function orbInfo()
    return { name = "Glass Sphere", quality = 3, ilvl = 33, classID = 4, subclassID = 0, equipLoc = "INVTYPE_HOLDABLE",
        texture = 134333 }
end

-- A roll for the axe; `over` changes or adds fields of the spec.
local function axeSpec(W, over)
    local spec = { link = W.itemLink(AXE, "Guardian's Dualblade", 3), name = "Guardian's Dualblade", texture = 135348 }
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

-- The party in party1..party4; the player is the fake's Ayla Brightwind.
local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- The same five as the loot history names them: full name, GUID, class file.
local ORLEN = { "Orlen Brightmoor", "Player-1-0002", "PALADIN" }
local BRISE = { "Brisé Tidewater", "Player-1-0003", "SHAMAN" }
local CORVEL = { "Corvel Duskmantle", "Player-1-0004", "MAGE" }
local KESTREL = { "Kestrel Ironmark", "Player-1-0005", "WARRIOR" }
local AYLA = { "Ayla Brightwind", "Player-1-00000001", "DRUID", isSelf = true }

-- One EncounterLootDropRollInfo; `state` names an Enum.EncounterLootDropRollState.
local function pick(G, who, state, roll, isWinner)
    return { playerName = who[1], playerGUID = who[2], playerClass = who[3], isSelf = who.isSelf == true,
        state = G.Enum.EncounterLootDropRollState[state], roll = roll, isWinner = isWinner == true }
end

-- The axe's drop as the game hands it out, started now and a minute long; `over` adds or replaces fields.
local function drop(G, W, picks, over)
    local info = { lootListKey = 7, itemHyperlink = W.itemLink(AXE, "Guardian's Dualblade", 3),
        playerRollState = G.Enum.EncounterLootDropRollState.NoRoll, isTied = false, allPassed = false,
        rollInfos = picks, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 }
    for k, v in pairs(over or {}) do info[k] = v end
    return info
end

-- The same drop, decided: `who` won with Need and `roll`.
local function decided(G, W, picks, who, roll)
    return drop(G, W, picks, { winner = pick(G, who, "NeedMainSpec", roll, true) })
end

-- A client with the axe in its item cache and the party grouped, and a 300 px wide frame where the window
-- sits. opts go to T.load. The addon is loaded up to the card and no further: the window shows every card in a view
-- of its own, and a second view of the same card would play every effect twice; what comes after the window may
-- lean on it.
local function setup(opts)
    opts = opts or {}
    if not opts.only then
        opts.only = {}
        for _, file in ipairs(T.tocFiles()) do
            opts.only[#opts.only + 1] = file
            if file == "UI/Card.lua" then break end
        end
    end
    local G, W, ns = T.load(opts)
    W.items[AXE] = axeInfo()
    W.setGroup(party())
    local window = G.CreateFrame("Frame", nil, G.UIParent)
    window:SetSize(300, 600)
    window:SetPoint("TOPLEFT", G.UIParent, "TOPLEFT", 372, -226)
    return G, W, ns, window
end

-- A view of `card` in the window, kept up to date the way the window keeps it: every CARD_CHANGED of its
-- card reaches view:Update.
local function show(ns, window, card)
    local view = ns.Card.Acquire(window)
    view:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    view:Bind(card)
    ns.Listen("CARD_CHANGED", function(changed, changes)
        if changed == view.card then view:Update(changes) end
    end)
    return view
end

-- The player's roll for the axe (roll 7) and a view of its card.
local function roll(W, ns, window, over)
    W.addRoll(7, axeSpec(W, over))
    local cards = ns.Rolls.Cards()
    local card = cards[#cards]
    return show(ns, window, card), card
end

-- The row views a card view shows, in order.
local function rowsOf(view)
    local out = {}
    for i = 1, view.rowCount do out[i] = view.rows[i] end
    return out
end

-- One thing of every shown row as a comma-joined string, so a failure shows the whole list.
local function column(view, fn)
    local out = {}
    for i, row in ipairs(rowsOf(view)) do out[i] = tostring(fn(row)) end
    return table.concat(out, ",")
end

-- What a font string shows: its plain text, "" when it is hidden or empty.
local function shown(W, fs)
    return fs:IsShown() and W.plain(fs:GetText() or "") or ""
end

-- The left side of the subtitle as it reads: its visible pieces, joined by spaces.
local function subtitle(W, view)
    local out = {}
    for _, fs in ipairs(view.parts) do
        if fs:IsShown() then out[#out + 1] = W.plain(fs:GetText() or "") end
    end
    return table.concat(out, " ")
end

-- Is the colour { r, g, b, ... } the one expected (r, g, b)?
local function same(c, r, g, b, msg)
    T.near(c[1], r, 1e-6, (msg or "colour") .. " red")
    T.near(c[2], g, 1e-6, (msg or "colour") .. " green")
    T.near(c[3], b, 1e-6, (msg or "colour") .. " blue")
end

local function textColor(fs) return { fs:GetTextColor() } end

-------------------------------------------------------------------------------
--  The card awaiting the player
-------------------------------------------------------------------------------
T.it("awaiting the player: three buttons, five rows in party order, height 217 with the reason line", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window, { canNeed = false, reasonNeed = 1 })
    local b = view.buttons
    T.ok(b.need:IsShown() and b.greed:IsShown() and b.pass:IsShown(), "Need, Greed and Pass")
    T.no(b.transmog:IsShown(), "no Transmog where the game offers none")
    T.eq(b.need:GetAlpha(), 0.38, "Need is greyed out")
    T.eq(column(view, function(r) return shown(W, r.name) end), "Orlen,Brisé,Corvel,Kestrel,Ayla",
        "the party in party-frame order, the player last")
    T.eq(view:Height(), 9 + 34 + 16 + 30 + 16 + 5 * 21 + 7)
    T.eq(view:Height(), 217)
    T.eq(view:GetHeight(), 217, "the view is as high as it says")
    T.ok(view.reason:IsShown(), "the reason line")
    T.ok(view.edge:IsShown(), "the accent edge of a card that waits on the player")
    T.eq(view.edge:GetWidth(), 2)
    T.eq(view.edge:GetHeight(), 217, "down the whole card")

    -- The mockup's spacing: padding 9/10/7, icon 34, the bar 8 below it, the buttons right under its block (the
    -- buttons' 1 px margin collapses into the bar's 6 px below it, as the mockup draws them).
    local top, left = view:GetTop(), view:GetLeft()
    T.eq(view.icon:GetLeft() - left, 10, "icon: 10 from the left")
    T.eq(top - view.icon:GetTop(), 9, "icon: 9 from the top")
    T.eq(view.icon:GetWidth(), 34)
    T.eq(top - view.track:GetTop(), 51, "the countdown 8 below the icon")
    T.eq(view.track:GetHeight(), 2)
    same(view.track._color, 1, 1, 1, "the track is white")
    T.near(view.track._color[4], 0.08, 1e-9, "at 8 %")
    T.eq(view.track:GetWidth(), 280)
    T.eq(top - b.need:GetTop(), 59, "the buttons 6 below the bar")
    T.eq(b.need:GetLeft() - left, 10)
    T.near(b.pass:GetRight() - left, 290, 1e-6)
    T.near(b.need:GetWidth(), (280 - 8) / 3, 1e-6, "three equal buttons 4 px apart")
    T.near(b.greed:GetLeft() - b.need:GetRight(), 4, 1e-6)
    T.eq(top - view.reason:GetTop(), 86, "the reason 3 into the buttons' block")
    local rows = rowsOf(view)
    T.eq(top - rows[1]:GetTop(), 105, "the rows under the reason")
    T.eq(rows[1]:GetHeight(), 21)
    T.eq(rows[1]:GetWidth(), 280)
    T.eq(top - rows[5]:GetBottom(), 210, "7 under the last row")
    T.near(view.time:GetLeft() - view.yours:GetRight(), 3.5, 1e-9,
        "'Your pick', then a space (Expressway's, 3.5 px at 11) before '· 54s', as the mockup writes it")
end)

T.it("the rows follow the mockup's columns: class icon, name, pick 64 px, roll 38 px", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    local row = rowsOf(view)[1]
    local left, right = row:GetLeft(), row:GetRight()
    T.eq(row.class:GetLeft() - left, 4, "class icon at 4")
    T.eq(row.class:GetWidth(), 15)
    T.eq(row.name:GetLeft() - left, 26, "the name 7 after it")
    T.eq(row.pick:GetLeft() - left, 280 - 4 - 38 - 7 - 64, "the pick column")
    T.eq(row.pick:GetWidth(), 64)
    T.eq(right - row.roll:GetRight(), 4, "the number right-aligned, 4 from the edge")
    local _, size = row.name:GetFont()
    T.eq(size, 12.5, "names 12.5 px")
    _, size = row.word:GetFont()
    T.eq(size, 11.5, "pick words 11.5 px")
    _, size = row.roll:GetFont()
    T.eq(size, 13, "numbers 13 px")
end)

T.it("picks show glyph and word in the pick colour; wait shows dots and 'choosing'", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    W.setDrop(9, 7, drop(G, W, {
        pick(G, ORLEN, "NeedMainSpec"), pick(G, BRISE, "Greed"), pick(G, CORVEL, "Pass"),
        pick(G, KESTREL, "Transmog"), pick(G, AYLA, "NoRoll"),
    }))
    local rows = rowsOf(view)
    local want = { { "need", "Need", "6bd999" }, { "greed", "Greed", "fabf4d" }, { "pass", "Pass", "8d9096" },
        { "transmog", "Transmog", "c58cff" } }
    for i, spec in ipairs(want) do
        local row = rows[i]
        T.ok(row.glyph:IsShown(), spec[1] .. ": a glyph")
        T.ok(row.glyph:GetTexture():find("Icons\\" .. spec[1], 1, true), spec[1] .. ": its own glyph")
        T.eq(row.glyph:GetWidth(), 13, spec[1] .. ": 13 px")
        T.color({ row.glyph:GetVertexColor() }, spec[3], spec[1] .. " glyph colour")
        T.eq(shown(W, row.word), spec[2], spec[1] .. " word")
        T.color(textColor(row.word), spec[3], spec[1] .. " word colour")
        T.no(row.dots:IsShown(), spec[1] .. ": no dots")
    end
    T.eq(rows[3]:GetAlpha(), 0.55, "a pass dims the row")
    T.eq(rows[1]:GetAlpha(), 1)
    local waiting = rows[5]
    T.ok(waiting.dots:IsShown(), "still choosing: the dots")
    T.no(waiting.glyph:IsShown(), "and no glyph")
    T.eq(shown(W, waiting.word), "choosing")
    T.color(textColor(waiting.word), "6f7277", "choosing is faint")
    T.eq(waiting:GetAlpha(), 1)
    T.near(waiting.word:GetLeft() - waiting.pick:GetLeft(), 17, 1e-6, "the word after the 13 px dots and 4 px")
end)

T.it("a member the history leaves out reads 'not in this roll' across both columns, at 0.45", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    W.setDrop(9, 7, drop(G, W, {
        pick(G, ORLEN, "NeedMainSpec"), pick(G, BRISE, "Greed"), pick(G, CORVEL, "Pass"), pick(G, AYLA, "NoRoll"),
    }))
    local out = rowsOf(view)[4]
    T.eq(shown(W, out.word), "not in this roll")
    T.color(textColor(out.word), "6f7277")
    T.no(out.glyph:IsShown(), "no glyph")
    T.no(out.dots:IsShown(), "no dots")
    T.eq(out.word:GetLeft(), out.pick:GetLeft(), "from the start of the pick column")
    T.eq(shown(W, out.roll), "", "no number")
    T.eq(out:GetAlpha(), 0.45)
end)

T.it("the player's row has the YOU tag", function()
    local G, W, ns, window = setup({ eui = true })
    local view = roll(W, ns, window)
    local rows = rowsOf(view)
    local me = rows[5]
    T.eq(me.data.isPlayer, true)
    T.eq(shown(W, me.you), "YOU")
    T.color(textColor(me.you), "6f7277", "the tag is faint")
    local _, size = me.you:GetFont()
    T.eq(size, 9.5)
    T.near(me.you:GetLeft() - me.name:GetRight(), 5, 1e-6, "5 px after the name")
    T.ok(me.me:IsShown(), "the player's row is washed")
    local c = me.me._color
    same(c, 1, 1, 1, "white")
    T.near(c[4], 0.035, 1e-9, "at 3.5 %")
    for i = 1, 4 do
        T.no(rows[i].you:IsShown(), rows[i].data.name .. " has no tag")
        T.no(rows[i].me:IsShown(), rows[i].data.name .. " has no wash")
    end
    same(textColor(me.name), ns.Theme.ClassColor("DRUID"))
    same(textColor(rows[1].name), ns.Theme.ClassColor("PALADIN"))
end)

T.it("clicking Need picks need; a disallowed Need ignores the click and shows 'Need: <reason>'", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window)
    T.no(view.reason:IsShown(), "no reason while Need is allowed")
    T.eq(view:Height(), 9 + 34 + 16 + 30 + 5 * 21 + 7)
    view.buttons.need:Click()
    T.eq(#W.rolled, 1, "one roll")
    T.eq(W.rolled[1][1], 7)
    T.eq(W.rolled[1][2], 1, "Need is roll type 1")
    T.eq(card.mine, "need")
    T.no(view.buttons.need:IsShown(), "the buttons go once the player picked")
    T.no(view.edge:IsShown(), "and the accent edge with them")
    T.eq(shown(W, rowsOf(view)[5].word), "Need", "the player's row shows the pick at once")
    T.eq(view:Height(), 9 + 34 + 16 + 5 * 21 + 7)

    local G2, W2, ns2, window2 = setup()
    local other, refused = roll(W2, ns2, window2, { canNeed = false, reasonNeed = 1 })
    other.buttons.need:Click()
    T.eq(#W2.rolled, 0, "a Need the game refuses is never sent")
    T.eq(refused.mine, nil)
    T.ok(other.buttons.need:IsShown(), "the buttons stay")
    T.eq(shown(W2, other.reason), "Need: Your class may not roll need on this item.")
    T.color(textColor(other.reason), "a2a5a9", "in muted text")
    local _, size = other.reason:GetFont()
    T.eq(size, 10.5)
    other.buttons.greed:Click()
    T.eq(W2.rolled[1][2], 2, "Greed still works")
end)

T.it("transmog replaces greed", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window, { canTransmog = true })
    T.ok(view.buttons.transmog:IsShown(), "Transmog")
    T.no(view.buttons.greed:IsShown(), "in Greed's place")
    T.near(view.buttons.transmog:GetLeft(), view.buttons.need:GetRight() + 4, 1e-6, "between Need and Pass")
    view.buttons.transmog:Click()
    T.eq(W.rolled[1][2], 4, "Transmog is roll type 4")
    local me = rowsOf(view)[5]
    T.eq(shown(W, me.word), "Transmog")
    T.color(textColor(me.word), "c58cff")
end)

T.it("a group update never hides a button under the mouse: the press and its click survive", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window)
    local need = view.buttons.need
    need:_fire("OnEnter")
    need:_fire("OnMouseDown", "LeftButton")
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "NeedMainSpec"), pick(G, AYLA, "NoRoll") }))
    T.ok(need.hovered, "still hovered")
    T.ok(need.pressed, "still pressed")
    need:_fire("OnMouseUp", "LeftButton")
    need:Click()
    T.eq(card.mine, "need", "the click lands")
end)

T.it("a bind confirmation brings the buttons back while Blizzard's dialog is up (R16)", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window)
    view.buttons.greed:Click()
    T.no(view.buttons.greed:IsShown())
    W.fire("CONFIRM_LOOT_ROLL", 7, 2)
    T.eq(card.mine, nil)
    T.ok(view.buttons.need:IsShown() and view.buttons.greed:IsShown() and view.buttons.pass:IsShown(),
        "the card waits on the player again")
    T.eq(shown(W, rowsOf(view)[5].word), "choosing")
    view.buttons.pass:Click()
    T.eq(W.rolled[#W.rolled][2], 0, "and its buttons work")
end)

-------------------------------------------------------------------------------
--  The head
-------------------------------------------------------------------------------
T.it("the head: icon, name in the quality colour, '<label> · ilvl <n>' and 'Your pick · <s>s'", function()
    local G, W, ns, window = setup({ eui = true })
    local view = roll(W, ns, window)
    T.eq(view.icon.icon:GetTexture(), 135348)
    T.eq(shown(W, view.name), "Guardian's Dualblade")
    T.color(textColor(view.name), "2f8dfc", "rare, lifted to read")
    local _, size = view.name:GetFont()
    T.eq(size, 13.5)
    T.eq(subtitle(W, view), "Two-Hand Axe · ilvl 33")
    T.color(textColor(view.parts[1]), "a2a5a9", "the label is muted")
    T.color(textColor(view.parts[2]), "6f7277", "the dot is faint")
    T.near(view.parts[2]:GetLeft() - view.parts[1]:GetRight(), 4, 1e-6, "4 px between the pieces")
    T.eq(shown(W, view.yours), "Your pick")
    T.eq(view.yours:GetFont(), ns.Theme.Font("item"), "in the bold font")
    same(textColor(view.yours), ns.Theme.Accent())
    T.eq(shown(W, view.time), "· 60s")
    T.color(textColor(view.time), "cacccf", "the seconds are dim")
    T.eq(view.time:GetRight(), view:GetRight() - 10, "on the right")
    view.buttons.pass:Click()
    T.no(view.yours:IsShown(), "no 'Your pick' once the player picked")
    T.eq(shown(W, view.time), "60s")
end)

T.it("Tick counts the seconds and the bar down", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    T.eq(view.bar:GetWidth(), 280, "a full bar at the start")
    W.advance(15)
    view:Tick()
    T.eq(shown(W, view.time), "· 45s")
    T.near(view.bar:GetWidth(), 280 * 45 / 60, 1e-6)
    W.advance(0.5)
    view:Tick()
    T.eq(shown(W, view.time), "· 45s", "a second that has begun still counts")
    W.advance(45)
    view:Tick()
    T.eq(shown(W, view.time), "· 0s")
    T.no(view.bar:IsShown(), "an empty bar is not drawn")
end)

T.it("BiS badge text in the subtitle", function()
    local G, W, ns, window = setup()
    ns.BiS.Badge = function(link)
        T.eq(link, W.itemLink(AXE, "Guardian's Dualblade", 3), "asked about the card's item")
        return { text = "BiS", star = true, r = 1, g = 209 / 255, b = 0 }
    end
    local view = roll(W, ns, window)
    local badge = view.badge
    T.ok(badge:IsShown(), "the badge")
    T.eq(shown(W, badge.text), "BiS")
    T.color(textColor(badge.text), "ffd100", "in gold")
    T.ok(badge.star:IsShown(), "with the star")
    T.eq(badge:GetHeight(), 14)
    T.near(badge:GetLeft() - view.parts[3]:GetRight(), 4, 1e-6, "after 'ilvl 33'")
    T.eq(shown(W, view.parts[3]), "ilvl 33")

    ns.BiS.Badge = function() return { text = "#4 pick", star = false, r = 0.5, g = 0.5, b = 1 } end
    view:Update({ item = true })
    T.eq(shown(W, badge.text), "#4 pick")
    T.no(badge.star:IsShown(), "no star past the third pick")
    T.color(textColor(badge.text), "8080ff", "in NaowhForever's colour")
    ns.BiS.Badge = function() return nil end
    view:Update({ item = true })
    T.no(badge:IsShown(), "no badge for an item off the list")
end)

T.it("a card from the loot history shows a placeholder until the game has the item", function()
    local G, W, ns, window = setup()
    W.items[AXE] = nil
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "NeedMainSpec"), pick(G, AYLA, "NoRoll") }))
    local card = ns.Rolls.Cards()[1]
    local view = show(ns, window, card)
    T.eq(view.icon.icon:GetTexture(), 134400, "the question mark")
    T.eq(subtitle(W, view), "", "no label or level yet")
    T.no(view.buttons.need:IsShown(), "no buttons: the player has no roll")
    T.eq(view:Height(), 9 + 34 + 16 + 5 * 21 + 7)
    W.cacheItem(AXE, axeInfo())
    T.eq(view.icon.icon:GetTexture(), 135348, "the real icon")
    T.eq(subtitle(W, view), "Two-Hand Axe · ilvl 33")
    T.eq(shown(W, view.name), "Guardian's Dualblade")
end)

-------------------------------------------------------------------------------
--  Numbers, picks arriving and the winner
-------------------------------------------------------------------------------
T.it("a new number calls Fx.Spin with the final value", function()
    local G, W, ns, window = setup()
    local spins = {}
    ns.Fx.Spin = function(fs, final) spins[#spins + 1] = { fs = fs, final = final } end
    local view = roll(W, ns, window)
    local picks = { pick(G, ORLEN, "NeedMainSpec"), pick(G, BRISE, "Greed"), pick(G, AYLA, "NoRoll") }
    W.setDrop(9, 7, drop(G, W, picks))
    T.eq(#spins, 0, "a pick has no number to spin")
    picks[1].roll = 19
    W.setDrop(9, 7, drop(G, W, picks))
    T.eq(#spins, 1, "one new number")
    T.eq(spins[1].final, 19)
    T.eq(spins[1].fs, rowsOf(view)[1].roll, "in Orlen's row")
    W.setDrop(9, 7, drop(G, W, picks))
    T.eq(#spins, 1, "a number already shown does not spin again")
end)

T.it("a number the game takes back stops spinning and shows none", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "NeedMainSpec"), pick(G, BRISE, "Greed", 40),
        pick(G, AYLA, "NoRoll") }))
    local lys = rowsOf(view)[2]
    W.advance(0.2)
    W.setDrop(9, 7, decided(G, W, { pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, BRISE, "Greed"),
        pick(G, AYLA, "Pass") }, ORLEN, 19))
    W.advance(2)
    T.eq(shown(W, lys.roll), "", "the Greed number is gone once the Need won")
    T.eq(lys.roll:GetTextScale(), 1)
end)

T.it("a new pick fades in", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    local orlen = rowsOf(view)[1]
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "NeedMainSpec"), pick(G, AYLA, "NoRoll") }))
    T.eq(orlen.pick:GetAlpha(), 0, "it starts unseen")
    W.advance(0.35)
    T.eq(orlen.pick:GetAlpha(), 1, "and is there after 0.35 s")
    local me = rowsOf(view)[5]
    view.buttons.greed:Click()
    T.eq(me.pick:GetAlpha(), 0, "the player's own pick fades in too")
end)

T.it("winner: wash shown, crown shown, number in the accent, losers at 0.42, subtitle 'Orlen won · Need 19'", function()
    local G, W, ns, window = setup({ eui = true })
    local view, card = roll(W, ns, window)
    view.buttons.greed:Click()
    W.fire("CANCEL_LOOT_ROLL", 7)
    W.setDrop(9, 7, decided(G, W, {
        pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, BRISE, "Greed"), pick(G, CORVEL, "Pass"),
        pick(G, KESTREL, "Pass"), pick(G, AYLA, "Greed"),
    }, ORLEN, 19))
    T.eq(card.status, "decided")
    local rows = rowsOf(view)
    local orlen = rows[1]
    T.ok(orlen.wash:IsShown(), "the winner's wash")
    T.eq(orlen.wash:GetTexture(), ns.W.MEDIA .. "wash")
    same({ orlen.wash:GetVertexColor() }, ns.Theme.Accent())
    T.near(select(4, orlen.wash:GetVertexColor()), 0.28, 1e-9, "the wash at 28 %")
    T.ok(orlen.edge:IsShown(), "and its 2 px accent edge")
    T.eq(orlen.edge:GetWidth(), 2)
    T.ok(orlen.crown:IsShown(), "the crown")
    same(textColor(orlen.roll), ns.Theme.Accent())
    T.eq(orlen:GetAlpha(), 1, "the winner stays bright")
    for i = 2, 5 do T.eq(rows[i]:GetAlpha(), 0.42, rows[i].data.name .. " fades back") end
    T.eq(subtitle(W, view), "Orlen won · Need 19")
    same(textColor(view.parts[1]), ns.Theme.ClassColor("PALADIN"))
    T.eq(view.parts[1]:GetFont(), ns.Theme.Font("item"), "the name in bold")
    T.color(textColor(view.parts[2]), "a2a5a9", "'won' is muted")
    T.no(view.time:IsShown(), "no seconds on a decided card")
    T.no(view.track:IsShown(), "and no countdown")
    T.eq(view:Height(), 9 + 34 + 16 + 5 * 21 + 7, "the countdown keeps its room")
    W.advance(1)
    T.near(orlen.wash:GetWidth(), 280, 1e-6, "the wash has swept the row")
    T.eq(orlen.crown:GetScale(), 1, "the crown has popped")
    T.eq(column(view, function(r) return shown(W, r.roll) end), "19,,,,",
        "the number has landed; Greed without a number shows none")
end)

T.it("a loser's number is muted and regular", function()
    local G, W, ns, window = setup({ eui = true })
    local view = roll(W, ns, window)
    view.buttons.need:Click()
    W.setDrop(9, 7, decided(G, W, {
        pick(G, ORLEN, "Greed"), pick(G, BRISE, "NeedMainSpec", 52), pick(G, CORVEL, "Pass"),
        pick(G, KESTREL, "Pass"), pick(G, AYLA, "NeedMainSpec", 87, true),
    }, AYLA, 87))
    W.advance(1.2)
    local lys = rowsOf(view)[2]
    T.eq(shown(W, lys.roll), "52")
    T.color(textColor(lys.roll), "a2a5a9", "muted")
    local path, size = lys.roll:GetFont()
    T.eq(path, ns.Theme.Font("sub"), "the regular font")
    T.eq(size, 13)
    local mine = rowsOf(view)[5].roll
    T.eq(mine:GetFont(), ns.Theme.Font("roll"), "the winner's number stays bold")
end)

T.it("the player wins: 'You won · Need 87', glow and shine started", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    view.buttons.need:Click()
    T.no(view.ring:IsShown(), "no glow before")
    T.no(view.shine:IsShown(), "no shine before")
    W.setDrop(9, 7, decided(G, W, {
        pick(G, ORLEN, "Greed"), pick(G, BRISE, "NeedMainSpec", 52), pick(G, CORVEL, "Pass"),
        pick(G, KESTREL, "Pass"), pick(G, AYLA, "NeedMainSpec", 87, true),
    }, AYLA, 87))
    T.eq(subtitle(W, view), "You won · Need 87")
    same(textColor(view.parts[1]), ns.Theme.Accent())
    T.ok(view.ring:IsShown(), "the icon ring glows")
    T.eq(view.ring:GetWidth(), 46)
    T.eq(view.ring:GetHeight(), 46)
    same({ view.ring:GetVertexColor() }, ns.Theme.Accent())
    local rx, ry = view.ring:GetCenter()
    local ix, iy = view.icon:GetCenter()
    T.eq(rx, ix, "centred on the icon")
    T.eq(ry, iy)
    T.ok(view.shine:IsShown(), "the shine crosses")
    T.near(view.shine:GetWidth(), 0.34 * 300, 1e-6, "a third of the card wide")
    local clip, band = view.shine:GetParent(), view.shine
    T.eq(clip:GetTop(), view:GetTop(), "the band slides in a frame over the whole card: its top")
    T.eq(clip:GetBottom(), view:GetBottom(), "its bottom")
    T.eq(clip:GetLeft(), view:GetLeft(), "its left")
    T.eq(clip:GetRight(), view:GetRight(), "its right")
    T.eq(clip._clips, true, "which clips it")
    T.eq(band:GetHeight(), view:GetHeight(), "the band is as high as the card")
    same({ band.tex:GetVertexColor() }, ns.Theme.Accent())
    T.near(select(4, band.tex:GetVertexColor()), 0.2, 1e-9, "the shine at 20 %")
    local me = rowsOf(view)[5]
    T.ok(me.crown:IsShown() and me.wash:IsShown(), "the player's row has the crown and the wash")
    W.advance(0.5)
    T.ok(view.ring:GetAlpha() > 0, "glowing")
    W.advance(3)
    T.no(view.ring:IsShown(), "twice, then gone")
    T.no(view.shine:IsShown(), "once, then gone")
end)

T.it("everyone passed: no crown", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    view.buttons.pass:Click()
    W.setDrop(9, 7, drop(G, W, {
        pick(G, ORLEN, "Pass"), pick(G, BRISE, "Pass"), pick(G, CORVEL, "Pass"), pick(G, KESTREL, "Pass"),
        pick(G, AYLA, "Pass"),
    }, { allPassed = true }))
    T.eq(subtitle(W, view), "Everyone passed")
    for i, row in ipairs(rowsOf(view)) do
        T.no(row.crown:IsShown(), "no crown in row " .. i)
        T.no(row.wash:IsShown(), "no wash in row " .. i)
        T.eq(row:GetAlpha(), 0.42, "row " .. i .. " fades back")
    end
    T.no(view.ring:IsShown())
end)

T.it("an ended card that is decided later shows the winner with the wash and the crown (R21)", function()
    local G, W, ns, window = setup()
    local began = G.C_LootHistory.GetLootHistoryTime() -- the roll's drop begins with it, on the history's clock
    local view, card = roll(W, ns, window)
    view.buttons.greed:Click()
    W.advance(66)
    T.eq(card.status, "ended")
    T.eq(subtitle(W, view), "Roll ended")
    T.eq(column(view, function(r) return r.crown:IsShown() and "crown" or "-" end), "-,-,-,-,-")
    -- The history names the winner late: the roll's own drop, whose minute is up by now.
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, AYLA, "Greed") },
        { winner = pick(G, ORLEN, "NeedMainSpec", 19, true), startTime = began }))
    T.eq(card.status, "decided")
    T.eq(subtitle(W, view), "Orlen won · Need 19")
    local orlen = rowsOf(view)[1]
    T.ok(orlen.crown:IsShown(), "the crown")
    T.ok(orlen.crown:GetScale() < 1, "popping in")
    T.ok(orlen.wash:IsShown(), "the wash")
    T.ok(orlen.wash:GetWidth() < 280, "sweeping")
end)

T.it("a late decision that arrives while the card is folded plays when the card opens", function()
    local G, W, ns, window = setup()
    local began = G.C_LootHistory.GetLootHistoryTime()
    local view, card = roll(W, ns, window)
    view.buttons.need:Click()
    W.advance(66)
    T.eq(card.status, "ended")
    view:SetFolded(true)
    W.setDrop(9, 7, drop(G, W, { pick(G, ORLEN, "Greed"), pick(G, AYLA, "NeedMainSpec", 87, true) },
        { winner = pick(G, AYLA, "NeedMainSpec", 87, true), startTime = began }))
    T.eq(card.status, "decided")
    T.eq(shown(W, view.foldWinner), "You", "the folded line names the winner")
    T.no(view.ring:IsShown(), "nothing plays while the card is folded")
    view:SetFolded(false)
    local me = rowsOf(view)[5]
    T.ok(me.crown:IsShown() and me.crown:GetScale() < 1, "the crown pops when the card opens")
    T.ok(me.wash:IsShown() and me.wash:GetWidth() < 280, "the wash sweeps")
    T.ok(view.ring:IsShown(), "the icon glows: the player won")
    T.ok(view.shine:IsShown(), "and the shine crosses")
    W.advance(4)
    view:SetFolded(true)
    view:SetFolded(false)
    T.eq(me.crown:GetScale(), 1, "once: opening the card again plays nothing")
    T.no(view.ring:IsShown())
end)

T.it("names carry the mockup's text shadow, 1 px under them; the subtitle, picks and numbers have none", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window)
    view.buttons.need:Click()
    W.setDrop(9, 7, decided(G, W, { pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, AYLA, "NeedMainSpec", 7) },
        ORLEN, 19))
    local function shadow(fs)
        local _, y = fs:GetShadowOffset()
        return y == -1 and select(4, fs:GetShadowColor()) == 0.6
    end
    local winner = rowsOf(view)[1]
    T.ok(shadow(view.name), "the item's name")
    T.ok(shadow(winner.name), "a player's name")
    T.ok(shadow(rowsOf(view)[5].you), "the YOU tag, inside the name's shadow in the mockup")
    T.no(shadow(view.parts[1]), "the winner's name in the subtitle (.won)")
    T.no(shadow(view.parts[2]), "the subtitle")
    T.no(shadow(winner.word), "the pick")
    T.no(shadow(winner.roll), "the number")
    view:SetFolded(true)
    T.ok(shadow(view.foldName) and shadow(view.foldWinner), "the folded line's name and winner (.result .ts)")
    T.no(shadow(view.foldResult), "and not its 'Need 19'")
end)

T.it("a view is built in its parent: its hairlines are one physical pixel at any UI scale", function()
    local G, W, ns, window = setup()
    G.UIParent:SetScale(0.5)
    local view = roll(W, ns, window)
    local px = ns.W.Pixel(view)
    T.near(px, 768 / 1080 / 0.5, 1e-9, "a physical pixel at half scale")
    T.near(view.divider:GetHeight(), px, 1e-9, "the card's hairline")
    for i, line in ipairs(view.icon.edge) do
        T.near(i <= 2 and line:GetHeight() or line:GetWidth(), px, 1e-9, "the icon's edge line " .. i)
    end
    T.near(view.icon.rim:GetWidth(), 34 + 2 * px, 1e-9, "the icon's rim")
    T.near(view.foldIcon.edge[1]:GetHeight(), px, 1e-9, "the folded line's icon")
end)

T.it("the subtitle's left side gives way to 'Your pick · <s>s': the label is cut", function()
    local G, W, ns, window = setup()
    W.items[ORB] = orbInfo()
    ns.BiS.Badge = function() return { text = "2nd pick", star = true, r = 1, g = 209 / 255, b = 0 } end
    W.addRoll(8, { link = W.itemLink(ORB, "Glass Sphere", 3), name = "Glass Sphere", texture = 134333 })
    local view = show(ns, window, ns.Rolls.Cards()[1])
    T.eq(subtitle(W, view), "Held In Off-hand · ilvl 33")
    T.ok(view.badge:IsShown() and view.yours:IsShown(), "the badge and 'Your pick'")
    T.ok(view.badge:GetRight() <= view.yours:GetLeft() - 4, "the badge ends 4 px before 'Your pick'")
    T.ok(view.parts[1]:GetWidth() < view.parts[1]:GetUnboundedStringWidth(), "the label is the one that gives way")
    T.near(view.parts[2]:GetLeft() - view.parts[1]:GetRight(), 4, 1e-6, "and the rest follows it")
    view.buttons.pass:Click()
    T.eq(view.parts[1]:GetWidth(), view.parts[1]:GetUnboundedStringWidth(), "with room again it is whole")
end)

T.it("names are cut where the columns need the room: a row's before the pick, the folded line's before the winner",
function()
    local G, W, ns, window = setup({ setup = function(_, W)
        W.player.name = "Aylathelongestnameinazeroth Brightwind"
    end })
    local long = party()
    long[4].name = "Kestrelironmarksforlornesons Ironmark"
    W.setGroup(long)
    local view = roll(W, ns, window, { name = "Guardian's Dualblade of the Everlasting Night" })
    local rows = rowsOf(view)
    T.near(rows[4].name:GetWidth(), 280 - 146, 1e-6, "a long name stops 7 px before the pick column")
    T.near(rows[4].pick:GetLeft() - rows[4].name:GetRight(), 7, 1e-6)
    T.near(rows[5].pick:GetLeft() - rows[5].you:GetRight(), 7, 1e-6, "the player's, with the YOU tag after it")
    T.near(rows[5].you:GetLeft() - rows[5].name:GetRight(), 5, 1e-6)
    view.buttons.need:Click()
    W.setDrop(9, 7, decided(G, W, { pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, AYLA, "Greed") }, ORLEN, 19))
    view:SetFolded(true)
    T.ok(view.foldName:GetWidth() < view.foldName:GetUnboundedStringWidth(), "the folded name gives way")
    T.near(view.foldResult:GetLeft() - view.foldWinner:GetRight(), 7, 1e-6, "to the arrow, the winner and the result")
end)

T.it("the countdown bar measures from the card, not from a track the game has yet to lay out", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    view.track.GetWidth = function() return 0 end -- a track the client has not laid out yet
    view:Tick()
    T.ok(view.bar:IsShown(), "the bar is drawn")
    T.eq(view.bar:GetWidth(), 280, "as wide as the card less its padding")
end)

T.it("a pooled row is shown before it is painted, so it measures a long name right", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    -- A row the game has hidden has no width to read until it shows again.
    W.setGroup({ party()[1] })
    view:Update({})
    T.eq(view.rowCount, 2, "three rows back in the pool, hidden")
    for _, row in ipairs(view.rows) do
        local width = row.GetWidth
        row.GetWidth = function(self) if not self:IsShown() then return 0 end return width(self) end
    end
    local long = party()
    long[4].name = "Kestrelironmarksforlornesons Ironmark"
    W.setGroup(long)
    view:Update({})
    local row = rowsOf(view)[4]
    T.eq(shown(W, row.name), "Kestrelironmarksforlornesons")
    T.near(row.pick:GetLeft() - row.name:GetRight(), 7, 1e-6, "a pooled row cuts a long name all the same")
end)

-------------------------------------------------------------------------------
--  Raid, folding, the item's tooltip, pooling
-------------------------------------------------------------------------------
-- A raid of 20, the player in slot 6; the others are Raider01 to Raider20.
local function raid()
    local list = {}
    for i = 1, 20 do
        if i == 6 then
            list[i] = { unit = "raid6", isPlayer = true }
        else
            list[i] = { unit = "raid" .. i, name = ("Raider%02d Test"):format(i), classFile = "MAGE",
                guid = ("Player-1-1%03d"):format(i) }
        end
    end
    return list
end

local function raider(i)
    return { ("Raider%02d Test"):format(i), ("Player-1-1%03d"):format(i), "MAGE" }
end

T.it("raid: only need/greed rows plus the player, then '13 passed · 2 choosing'; clicking lists them", function()
    local G, W, ns, window = setup()
    W.setGroup(raid(), { raid = true })
    local picks = { pick(G, AYLA, "Pass") }
    local states = { [1] = "NeedMainSpec", [2] = "Greed", [3] = "NoRoll", [4] = "NeedMainSpec", [5] = "Greed",
        [20] = "NoRoll" }
    for i = 1, 20 do
        if i ~= 6 then picks[#picks + 1] = pick(G, raider(i), states[i] or "Pass") end
    end
    W.setDrop(9, 7, drop(G, W, picks))
    local view = show(ns, window, ns.Rolls.Cards()[1])
    T.eq(column(view, function(r) return shown(W, r.name) end), "Raider01,Raider02,Raider04,Raider05,Ayla",
        "need and greed in raid order, and the player")
    local sum = view.summary
    T.ok(sum:IsShown(), "the summary line")
    T.eq(shown(W, sum.passed), "13 passed")
    T.eq(shown(W, sum.choosing), "2 choosing")
    T.no(sum.absent:IsShown(), "no part for a count of 0")
    T.ok(sum.dots:IsShown(), "the dots before 'choosing'")
    T.ok(sum.passIcon:IsShown(), "the Pass glyph before 'passed'")
    T.eq(view:Height(), 9 + 34 + 16 + 5 * 21 + 24 + 7, "the summary's block is 24 px: 2 above it, 22 high (R35)")
    T.eq(view:GetHeight(), view:Height())
    T.eq(sum:GetHeight(), 22)
    T.eq(view:GetTop() - sum:GetTop(), 9 + 34 + 16 + 5 * 21 + 2, "2 under the rows")
    -- .sum has a 1 px border-top: its items are centred on the 21 px under it, 11.5 px down, not on all 22.
    local _, middle = sum.passIcon:GetCenter()
    T.near(sum:GetTop() - middle, 11.5, 1e-9, "the Pass glyph on the 21 px under the hairline")
    _, middle = sum.choosing:GetCenter()
    T.near(sum:GetTop() - middle, 11.5, 1e-9, "the words too")
    _, middle = sum.chevron:GetCenter()
    T.near(sum:GetTop() - middle, 11.5, 1e-9, "and the chevron")
    sum:Click()
    local menu = ns.W.CurrentMenu()
    T.ok(menu and menu:IsShown(), "clicking lists the rest")
    local names = {}
    for i, line in ipairs(menu.rows) do
        if line:IsShown() then names[#names + 1] = W.plain(line.label:GetText()):match("^(%S+)") end
    end
    T.eq(#names, 15, "13 passed and 2 choosing")
    T.eq(names[1], "Raider03")
    T.eq(names[15], "Raider20")
    T.ok(W.plain(menu.rows[1].label:GetText()):find("choosing", 1, true), "with their pick")
    T.ok(W.plain(menu.rows[2].label:GetText()):find("Pass", 1, true))
    sum:Click()
    T.no(menu:IsShown(), "a second click closes the list")
end)

T.it("raid: the summary leaves out a zero part", function()
    local G, W, ns, window = setup()
    W.setGroup(raid(), { raid = true })
    local picks = { pick(G, AYLA, "Pass") }
    for i = 1, 20 do
        if i ~= 6 then picks[#picks + 1] = pick(G, raider(i), i < 3 and "NoRoll" or "NeedMainSpec") end
    end
    W.setDrop(9, 7, drop(G, W, picks))
    local view = show(ns, window, ns.Rolls.Cards()[1])
    T.no(view.summary.passed:IsShown(), "nobody passed")
    T.no(view.summary.passIcon:IsShown())
    T.eq(shown(W, view.summary.choosing), "2 choosing")
end)

T.it("folded line text and 26 px", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    view.buttons.greed:Click()
    W.setDrop(9, 7, decided(G, W, {
        pick(G, ORLEN, "NeedMainSpec", 19, true), pick(G, AYLA, "Greed"),
    }, ORLEN, 19))
    view:SetFolded(true)
    T.eq(view:Height(), 26)
    T.eq(view:GetHeight(), 26)
    T.no(view.full:IsShown(), "the card is one line")
    T.ok(view.fold:IsShown())
    T.eq(view.foldIcon:GetWidth(), 18)
    T.eq(view.foldIcon.icon:GetTexture(), 135348)
    T.eq(shown(W, view.foldName), "Guardian's Dualblade")
    T.color(textColor(view.foldName), "2f8dfc")
    T.ok(view.foldArrow:IsShown(), "the arrow")
    T.eq(shown(W, view.foldWinner), "Orlen")
    same(textColor(view.foldWinner), ns.Theme.ClassColor("PALADIN"))
    T.eq(shown(W, view.foldResult), "Need 19")
    T.color(textColor(view.foldResult), "a2a5a9")
    T.eq(view.foldResult:GetRight(), view:GetRight() - 10)
    local _, size = view.foldName:GetFont()
    T.eq(size, 12)
    view:SetFolded(false)
    T.eq(view:Height(), 9 + 34 + 16 + 5 * 21 + 7)
    T.ok(view.full:IsShown())
end)

T.it("folded: 'You' in the accent, 'Everyone passed' and 'Roll ended' without an arrow", function()
    local G, W, ns, window = setup()
    local view, card = roll(W, ns, window)
    view.buttons.need:Click()
    W.setDrop(9, 7, decided(G, W, { pick(G, AYLA, "NeedMainSpec", 87, true) }, AYLA, 87))
    view:SetFolded(true)
    T.eq(shown(W, view.foldWinner), "You")
    same(textColor(view.foldWinner), ns.Theme.Accent())
    T.eq(shown(W, view.foldResult), "Need 87")

    local G2, W2, ns2, window2 = setup()
    local passed = roll(W2, ns2, window2)
    passed.buttons.pass:Click()
    W2.setDrop(9, 7, drop(G2, W2, { pick(G2, AYLA, "Pass") }, { allPassed = true }))
    passed:SetFolded(true)
    T.no(passed.foldArrow:IsShown())
    T.no(passed.foldWinner:IsShown())
    T.eq(shown(W2, passed.foldResult), "Everyone passed")

    local G3, W3, ns3, window3 = setup()
    local ended = roll(W3, ns3, window3)
    ended.buttons.pass:Click()
    W3.advance(66)
    ended:SetFolded(true)
    T.eq(shown(W3, ended.foldResult), "Roll ended")
end)

T.it("tooltip on hover, HandleModifiedItemClick on shift-click", function()
    local clicked = {}
    local G, W, ns, window = setup({ setup = function(G)
        G.GameTooltip.SetLootRollItem = function(self, rollID) self._rollItem = rollID end
        G.HandleModifiedItemClick = function(link) clicked[#clicked + 1] = link end
    end })
    local view, card = roll(W, ns, window)
    local tip = G.GameTooltip
    view.iconHit:_fire("OnEnter")
    T.eq(tip:GetOwner(), view.iconHit, "the tooltip belongs to the icon")
    T.eq(tip._rollItem, 7, "the roll's own item while the roll is on")
    view.iconHit:_fire("OnLeave")
    T.no(tip:IsShown(), "gone when the mouse leaves")
    view.buttons.greed:Click()
    W.fire("CANCEL_LOOT_ROLL", 7)
    view.nameHit:_fire("OnEnter")
    T.eq(tip:GetOwner(), view.nameHit, "the name shows it too")
    T.eq(tip._link, card.link, "the item's link once the roll is over")
    T.ok(view.nameHit:GetWidth() > 0, "the name can be hovered")
    view.nameHit:Click()
    T.eq(#clicked, 0, "a plain click does nothing")
    W.modified = true
    view.nameHit:Click()
    view.iconHit:Click()
    T.eq(#clicked, 2, "a modified click hands the link to the game")
    T.eq(clicked[1], card.link)
end)

T.it("a roll item the tooltip cannot show falls back to the item's link", function()
    local G, W, ns, window = setup({ setup = function(G)
        G.GameTooltip.SetLootRollItem = function() error("no roll by that ID") end
    end })
    local view, card = roll(W, ns, window)
    view.iconHit:_fire("OnEnter")
    T.eq(G.GameTooltip._link, card.link, "the link's tooltip")
    T.ok(G.GameTooltip:IsShown())
end)

-- R41: a demo card's roll ID is made up, and the game may draw nothing for it without raising.
T.it("a demo card's tooltip is its item's link, never the game's roll (R41)", function()
    local asked = {}
    local G, W, ns, window = setup({ setup = function(G)
        G.GameTooltip.SetLootRollItem = function(self, rollID) asked[#asked + 1] = rollID end
    end })
    local link = W.itemLink(AXE, "Guardian's Dualblade", 3)
    local card = ns.Rolls.AddDemo({ link = link, name = "Guardian's Dualblade", quality = 3, canNeed = true,
        canGreed = true, startedAt = G.GetTime(), duration = 60 })
    local view = show(ns, window, card)
    T.ok(ns.Rolls.AwaitsMe(card), "live and waiting on the player, as a roll is")
    view.iconHit:_fire("OnEnter")
    T.eq(#asked, 0, "the game is never asked for a roll it does not have")
    T.eq(G.GameTooltip._link, link, "the item's link straight away")
    T.ok(G.GameTooltip:IsShown())
    view.iconHit:_fire("OnLeave")
    local real = roll(W, ns, window)
    real.iconHit:_fire("OnEnter")
    T.eq(asked[1], 7, "a real roll still shows its own item")
end)

T.it("a pooled view comes back with its hairline, which the window hides on the first card only", function()
    local G, W, ns, window = setup()
    local view = roll(W, ns, window)
    -- .card's border-top: one pixel just above the card, where the window leaves a pixel between two cards.
    T.eq(view.divider:GetBottom(), view:GetTop(), "the hairline lies just above the card")
    T.eq(view.divider:GetLeft(), view:GetLeft())
    T.eq(view.divider:GetWidth(), 300)
    T.near(view.divider:GetHeight(), ns.W.Pixel(view), 1e-9)
    view.divider:Hide()
    ns.Card.Release(view)
    local again = ns.Card.Acquire(window)
    T.eq(again, view)
    T.ok(again.divider:IsShown())
end)

T.it("a released view stops its effects and comes back for the next card", function()
    local G, W, ns, window = setup()
    G.random = function() return 7 end -- a number that is spinning shows 7
    local view, card = roll(W, ns, window)
    view.buttons.need:Click()
    W.setDrop(9, 7, decided(G, W, {
        pick(G, ORLEN, "Greed"), pick(G, BRISE, "NeedMainSpec", 52), pick(G, AYLA, "NeedMainSpec", 87, true),
    }, AYLA, 87))
    local lys = rowsOf(view)[2]
    T.eq(shown(W, lys.roll), "7", "Brisé's number is spinning")
    T.ok(view.ring:IsShown(), "glowing")
    ns.Card.Release(view)
    T.no(view:IsShown(), "a released view is hidden")
    T.no(view.ring:IsShown(), "its glow stopped")
    T.no(view.shine:IsShown(), "its shine stopped")
    W.advance(0.3)
    T.eq(lys.roll:GetText(), "52", "the spin was put at rest on its number, and spins no more")
    T.eq(lys.roll:GetTextScale(), 1)
    ns.Card.Release(view)
    local again = ns.Card.Acquire(window)
    T.eq(again, view, "the pool hands it out again")
    local other = ns.Card.Acquire(window)
    T.ok(other ~= view, "once: a view released twice is pooled once")
    W.addRoll(8, axeSpec(W))
    local next = ns.Rolls.Cards()[#ns.Rolls.Cards()]
    again:Bind(next)
    T.ok(again:IsShown())
    T.ok(again.buttons.need:IsShown(), "the new card's buttons")
    T.eq(subtitle(W, again), "Two-Hand Axe · ilvl 33")
    T.eq(column(again, function(r) return r.crown:IsShown() and "crown" or "-" end), "-,-,-,-,-",
        "nothing of the last card")
end)

T.it("NewRow paints a row for Recent rolls, 19 px high", function()
    local G, W, ns, window = setup()
    local row = ns.Card.NewRow(window)
    row:SetPoint("TOPLEFT", window, "TOPLEFT", 44, 0)
    row:SetPoint("TOPRIGHT", window, "TOPRIGHT", -10, 0)
    row:Set({ guid = "Player-1-0002", name = "Orlen", class = "PALADIN", isPlayer = false, state = "need", roll = 19,
        isWinner = true }, { decided = true, height = 19 })
    T.eq(row:GetHeight(), 19)
    T.eq(shown(W, row.name), "Orlen")
    T.eq(shown(W, row.word), "Need")
    T.eq(shown(W, row.roll), "19")
    T.ok(row.crown:IsShown() and row.wash:IsShown(), "the winner's crown and wash")
    T.eq(row:GetAlpha(), 1)
    row:Set({ guid = "Player-1-0003", name = "Brisé", class = "SHAMAN", isPlayer = false, state = "greed",
        isWinner = false }, { decided = true, height = 19 })
    T.no(row.crown:IsShown(), "a loser has no crown")
    T.no(row.wash:IsShown())
    T.eq(row:GetAlpha(), 0.42)
    T.eq(shown(W, row.roll), "")
end)
