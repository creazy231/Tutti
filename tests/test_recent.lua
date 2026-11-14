local T = T

-------------------------------------------------------------------------------
--  The scene: the session's results as Core/History.lua keeps them (TuttiDB.recent, newest first), shown in the
--  window's Recent rolls. The party is R30's cast; the player is the fake's Ayla Brightwind.
-------------------------------------------------------------------------------
local AYLA = { guid = "Player-1-00000001", name = "Ayla", class = "DRUID", isPlayer = true }
local ORLEN = { guid = "Player-1-0002", name = "Orlen", class = "PALADIN" }
local BRISE = { guid = "Player-1-0003", name = "Brisé", class = "SHAMAN" }
local CORVEL = { guid = "Player-1-0004", name = "Corvel", class = "MAGE" }
local KESTREL = { guid = "Player-1-0005", name = "Kestrel", class = "WARRIOR" }

-- A line (.hl) as the mockup measures it (R40): 5 px, the name's 15 px line, the winner's 13 px line, 5 px.
local LINE, INSET = 38, 5

-- One row as History keeps it: a copy of a row of ns.Rolls.Rows.
local function row(who, state, roll, won)
    return { guid = who.guid, name = who.name, class = who.class, isPlayer = who.isPlayer == true, state = state,
        roll = roll, isWinner = won == true }
end

-- A result `ago` seconds old, as History keeps it: the rows in the party's order, the winner the row that won
-- (else everyone passed, or the roll ended).
local function result(G, spec)
    local entry = { name = spec.name, quality = spec.quality or 3, icon = spec.icon or 135348,
        place = spec.place or "Stonewatch Keep", at = G.time() - (spec.ago or 0), rows = spec.rows or {},
        allPassed = spec.allPassed == true }
    for _, r in ipairs(entry.rows) do
        if r.isWinner then entry.winner = { name = r.name, class = r.class, state = r.state, roll = r.roll } end
    end
    entry.ended = not entry.winner and not entry.allPassed
    return entry
end

-- History takes a result: in at the top, then HISTORY_CHANGED.
local function add(ns, entry)
    table.insert(ns.DB.recent, 1, entry)
    ns.Fire("HISTORY_CHANGED")
    return entry
end

-- The player's gloves (now), Brisé's treads (6 min) at Stonewatch Keep, Kestrel's grips (22 min) at Greymist Hollow.
local function session(G, ns)
    local grips = add(ns, result(G, { name = "Ephemeral Grips", place = "Greymist Hollow", ago = 22 * 60,
        rows = { row(ORLEN, "pass"), row(BRISE, "pass"), row(CORVEL, "pass"), row(KESTREL, "greed", 45, true),
            row(AYLA, "pass") } }))
    local treads = add(ns, result(G, { name = "Manascale Treads", ago = 6 * 60,
        rows = { row(ORLEN, "pass"), row(BRISE, "need", 74, true), row(CORVEL, "pass"), row(KESTREL, "greed"),
            row(AYLA, "greed") } }))
    local gloves = add(ns, result(G, { name = "Cartilage Shapers", ago = 0,
        rows = { row(ORLEN, "greed"), row(BRISE, "need", 52), row(CORVEL, "pass"), row(KESTREL, "pass"),
            row(AYLA, "need", 87, true) } }))
    return gloves, treads, grips
end

-- A client after login with Recent rolls open. -> G, W, ns, TuttiFrame, the view
local function setup()
    local G, W, ns = T.load()
    return G, W, ns, G.TuttiFrame
end

local function open(W, ns)
    T.eq(ns.UI.Open("recent"), true, "Recent rolls opens")
    W.advance(0.35)
    return ns.Recent.view
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

-- How far below the window's top a region's middle is.
local function middle(W, win, region)
    local _, y, _, h = box(W, win, region)
    return y + h / 2
end

-- Is the colour { r, g, b, ... } the expected one?
local function same(c, expected, msg)
    T.near(c[1], expected[1], 1e-6, (msg or "colour") .. " red")
    T.near(c[2], expected[2], 1e-6, (msg or "colour") .. " green")
    T.near(c[3], expected[3], 1e-6, (msg or "colour") .. " blue")
end

local function color(fs) return { fs:GetTextColor() } end

-- The lines that show, top to bottom.
local function shownLines(view)
    local out = {}
    for _, line in ipairs(view.lines) do
        if line:IsShown() then out[#out + 1] = line end
    end
    return out
end

-------------------------------------------------------------------------------
--  The list
-------------------------------------------------------------------------------
T.it("lines newest first under their place", function()
    local G, W, ns, win = setup()
    session(G, ns)
    local view = open(W, ns)
    local lines = shownLines(view)
    T.eq(#lines, 3)
    T.eq(text(W, lines[1].name), "Cartilage Shapers", "the newest on top")
    T.eq(text(W, lines[2].name), "Manascale Treads")
    T.eq(text(W, lines[3].name), "Ephemeral Grips")
    T.eq(text(W, lines[1].age), "now")
    T.eq(text(W, lines[2].age), "6m")
    T.eq(text(W, lines[3].age), "22m")

    -- Under the header: the first place's label (22 px, no hairline under the header's), its two lines (38 px),
    -- the second place's label (23 px, its hairline), its line, 4 px, the footer (29 px).
    local first, second = view.sections[1], view.sections[2]
    T.eq(text(W, first.label), "STONEWATCH KEEP · TODAY")
    T.eq(text(W, second.label), "GREYMIST HOLLOW · TODAY")
    T.no(view.sections[3] and view.sections[3]:IsShown(), "two places")
    local x, y, _, h = box(W, win, first)
    T.eq(y, 32, "right under the header")
    T.eq(h, 22)
    T.no(first.hair:IsShown(), "no hairline under the header's")
    T.eq(box(W, win, first.label), 10)
    T.near(middle(W, win, first.label), 32 + 7 + 13.3 / 2, 1e-6, "its line 7 px down")
    T.eq(select(2, first.label:GetFont()), 9.5)
    same(color(first.label), { ns.Theme.Color("muted") })
    local rx, ry, rw, rh = box(W, win, first.rule)
    local lx, _, lw = box(W, win, first.label)
    T.near(rx, lx + lw + 8, 1e-6, "the line after the label 8 px on")
    T.near(rx + rw, 290, 1e-6, "to 10 px from the right")
    T.near(ry + rh / 2, 32 + 7 + 13.3 / 2, 0.5, "through the label's middle")
    _, y = box(W, win, lines[1])
    T.eq(y, 32 + 22)
    _, y, _, h = box(W, win, lines[2])
    T.eq(y, 32 + 22 + LINE, "38 px a line")
    T.eq(h, LINE)
    _, y, _, h = box(W, win, second)
    T.eq(y, 32 + 22 + 2 * LINE)
    T.eq(h, 23)
    T.ok(second.hair:IsShown(), "a hairline over the next place")
    T.near(middle(W, win, second.label), 32 + 22 + 2 * LINE + 1 + 7 + 13.3 / 2, 1e-6)
    _, y = box(W, win, lines[3])
    T.eq(y, 32 + 22 + 2 * LINE + 23)
    _, y, _, h = box(W, win, view.footer)
    T.eq(y, 32 + 22 + 2 * LINE + 23 + LINE + 4, "4 px after the last line")
    T.eq(h, 29)
    T.eq(view:Height(), 22 + 2 * LINE + 23 + LINE + 4 + 29)
    T.eq(win:GetHeight(), 32 + view:Height(), "the window fits the list")

    -- A line: the icon 26 px, the name and who won beside it, the age on the right.
    local line = lines[1]
    x, y, _, h = box(W, win, line.icon)
    T.eq(x, 10)
    T.eq(h, 26)
    T.eq(y, 32 + 22 + (LINE - 26) / 2, "centred on the line")
    T.eq(box(W, win, line.name), 44, "8 px after the icon")
    T.near(middle(W, win, line.name), 32 + 22 + INSET + 7.5, 1e-6, "the name's 15 px line")
    T.near(middle(W, win, line.who), 32 + 22 + INSET + 15 + 6.5, 1e-6, "and the 13 px line under it")
    local ax, _, aw = box(W, win, line.age)
    T.eq(ax + aw, 290, "the age 10 px from the right")
    T.near(middle(W, win, line.age), 32 + 22 + INSET + 1 + 14.7 / 2, 1e-6, "at the top, 1 px down")
    T.eq(select(2, line.name:GetFont()), 12.5)
    same(color(line.name), { ns.Theme.Quality(3) }, "the name in its quality's colour")
    T.eq(select(2, line.age:GetFont()), 10.5)
    same(color(line.age), { ns.Theme.Color("faint") })
end)

T.it("'You · Need 87' in the accent", function()
    local G, W, ns, win = setup()
    session(G, ns)
    add(ns, result(G, { name = "Blightleaf Rope", allPassed = true,
        rows = { row(ORLEN, "pass"), row(AYLA, "pass") } }))
    add(ns, result(G, { name = "Ponderous Orb", rows = { row(ORLEN, "out"), row(AYLA, "out") } }))
    local view = open(W, ns)
    local lines = shownLines(view)
    T.eq(#lines, 5)

    local ended, passed, gloves, treads = lines[1], lines[2], lines[3], lines[4]
    T.eq(text(W, gloves.who), "You", "the player won")
    same(color(gloves.who), { ns.Theme.Accent() }, "in the accent")
    T.eq(select(2, gloves.who:GetFont()), 11)
    T.eq(text(W, gloves.dot), "·")
    same(color(gloves.dot), { ns.Theme.Color("faint") })
    T.eq(text(W, gloves.how), "Need 87")
    same(color(gloves.how), { ns.Theme.Color("muted") })
    local wx, _, ww = box(W, win, gloves.who)
    local dx, _, dw = box(W, win, gloves.dot)
    T.eq(wx, 44)
    T.near(dx, wx + ww + 4, 1e-6, "4 px apart")
    T.near(box(W, win, gloves.how), dx + dw + 4, 1e-6)

    T.eq(text(W, treads.who), "Brisé", "someone else: their first name")
    same(color(treads.who), { ns.Theme.ClassColor("SHAMAN") }, "in their class colour")
    T.eq(text(W, treads.how), "Need 74")

    T.eq(text(W, passed.who), "")
    T.eq(text(W, passed.dot), "")
    T.eq(text(W, passed.how), "Everyone passed")
    T.eq(box(W, win, passed.how), 44)
    same(color(passed.how), { ns.Theme.Color("muted") })
    T.eq(text(W, ended.how), "Roll ended", "nobody decided it")
    T.eq(text(W, ended.who), "")
end)

T.it("click opens the picks, second click closes", function()
    local G, W, ns, win = setup()
    session(G, ns)
    local view = open(W, ns)
    local height = win:GetHeight()
    local lines = shownLines(view)
    local gloves, treads = lines[1], lines[2]
    T.no(view.picks:IsShown(), "closed at first")
    gloves:Click()
    T.ok(view.picks:IsShown(), "the click opens everyone's pick")
    T.ok(gloves.selected:IsShown(), "the line is selected")
    local _, y, w, h = box(W, win, view.picks)
    T.eq(y, 32 + 22 + LINE, "right under its line")
    T.eq(w, 300)
    T.eq(h, 2 + 5 * 19 + 6, "2 px, a 19 px row each, 6 px")
    _, y = box(W, win, treads)
    T.eq(y, 32 + 22 + LINE + h, "the next line moves down")
    T.eq(win:GetHeight(), height + h, "and the window grows")

    local rows = {}
    for _, r in ipairs(view.picks.rows) do
        if r:IsShown() then rows[#rows + 1] = r end
    end
    T.eq(#rows, 5, "one row each")
    local x, ry, rw, rh = box(W, win, rows[1])
    T.eq(x, 44, "indented 44 px")
    T.eq(ry, 32 + 22 + LINE + 2)
    T.eq(rw, 246, "to 10 px from the right")
    T.eq(rh, 19)
    T.eq(text(W, rows[1].name), "Orlen")
    T.eq(text(W, rows[1].word), "Greed")
    T.eq(rows[1]:GetAlpha(), 1, "drawn by its pick, as the mockup's open line")
    T.eq(rows[3]:GetAlpha(), 0.55, "a pass dimmed")
    T.eq(text(W, rows[5].name), "Ayla")
    T.ok(rows[5].wash:IsShown() and rows[5].crown:IsShown(), "the winner's wash and crown")
    T.eq(text(W, rows[5].roll), "87")

    gloves:Click()
    T.no(view.picks:IsShown(), "a second click closes them")
    T.no(gloves.selected:IsShown())
    T.eq(win:GetHeight(), height, "and the window is as it was")

    gloves:Click()
    treads:Click()
    T.no(gloves.selected:IsShown(), "another line takes the open place")
    T.ok(treads.selected:IsShown())
    _, y = box(W, win, view.picks)
    T.eq(y, 32 + 22 + 2 * LINE)
    T.eq(text(W, view.picks.rows[2].name), "Brisé")
end)

T.it("footer text", function()
    local G, W, ns, win = setup()
    session(G, ns)
    local view = open(W, ns)
    T.eq(text(W, view.footer.label), "Kept for this session · /tutti opens this list")
    T.eq(select(2, view.footer.label:GetFont()), 10.5)
    same(color(view.footer.label), { ns.Theme.Color("faint") })
    T.eq(box(W, win, view.footer.label), 10)
    local _, y = box(W, win, view.footer)
    T.near(middle(W, win, view.footer.label), y + 1 + 5 + 14.7 / 2, 1e-6, "under a hairline, 5 px down")
    T.ok(view.footer.hair:IsShown())
end)

-------------------------------------------------------------------------------
--  Edge cases
-------------------------------------------------------------------------------
T.it("an empty session says so", function()
    local G, W, ns, win = setup()
    local view = open(W, ns)
    T.eq(#shownLines(view), 0)
    T.eq(text(W, view.empty), "No rolls yet")
    T.eq(box(W, win, view.empty), 10)
    local _, y = box(W, win, view.footer)
    T.eq(y, 32 + 28, "the footer under it")
    T.eq(view:Height(), 28 + 29)
    T.eq(win:GetHeight(), 32 + 28 + 29)
end)

T.it("a result that comes in while the list shows goes on top, and a late decision redraws its line", function()
    local G, W, ns, win = setup()
    local gloves = session(G, ns)
    local view = open(W, ns)
    local height = win:GetHeight()
    local late = add(ns, result(G, { name = "Violet Sorcerer's Robes",
        rows = { row(CORVEL, "out"), row(AYLA, "out") } }))
    local lines = shownLines(view)
    T.eq(#lines, 4)
    T.eq(text(W, lines[1].name), "Violet Sorcerer's Robes")
    T.eq(text(W, lines[1].how), "Roll ended")
    T.eq(win:GetHeight(), height + LINE, "the window grows with it")
    -- The history updates the entry in place (R21): the same line says who won.
    late.rows = { row(CORVEL, "need", 88, true), row(AYLA, "pass") }
    late.winner, late.ended = { name = "Corvel", class = "MAGE", state = "need", roll = 88 }, false
    ns.Fire("HISTORY_CHANGED")
    T.eq(text(W, lines[1].who), "Corvel")
    T.eq(text(W, lines[1].how), "Need 88")
    T.eq(text(W, shownLines(view)[2].name), gloves.name, "the others where they were")
    T.eq(#shownLines(view), 4)
end)

T.it("ages move on while the list shows", function()
    local G, W, ns, win = setup()
    session(G, ns)
    local view = open(W, ns)
    T.eq(text(W, view.lines[1].age), "now")
    W.advance(61)
    T.eq(text(W, view.lines[1].age), "1m")
    T.eq(text(W, view.lines[2].age), "7m")
end)

T.it("an earlier day has a label of its own", function()
    local G, W, ns, win = setup()
    add(ns, result(G, { name = "Ephemeral Grips", ago = 86400, rows = { row(AYLA, "need", 12, true) } }))
    add(ns, result(G, { name = "Manascale Treads", ago = 60, rows = { row(AYLA, "need", 40, true) } }))
    local view = open(W, ns)
    T.eq(text(W, view.sections[1].label), "STONEWATCH KEEP · TODAY")
    T.eq(text(W, view.sections[2].label), "STONEWATCH KEEP · YESTERDAY", "the same place, another day")
end)
