-------------------------------------------------------------------------------
--  Tutti: the window (the approved mockup's .win, .hd, .sec and .result). A 32 px header over one of three
--  views, in a scroll frame once the window would pass 70 % of the screen's height: the rolls (one card per
--  item in arrival order; a decided card folds into a line under "DONE" 4 s after its decision while another
--  card is open), Recent rolls and Settings (Task 12's views, registered here). It opens on every new roll,
--  closes itself `closeAfter` seconds after the last roll is decided (the mouse over it keeps it open), plays
--  the chime when the player wins, remembers where it was dragged and follows the size setting.
--  A card that waits on the player is never left out of sight (R45, "Keeping the waiting cards in sight"): the
--  rolls bring the oldest of them whole into view after every change and on every return to them, nothing moves
--  under the mouse right after the player's own pick or while that card's buttons show (R50), and no fold happens
--  under it while a card waits. The count pill shows in every view, in the accent outside the rolls while a card
--  waits there, and a click on it leads back; with URGENT seconds left on such a card the window goes back to the
--  rolls by itself.
--  In WoW Forever's gamepad interface (ns.Popups.Gamepad) Blizzard's gamepad roll frame takes the rolls and the window
--  stays out of its way: no roll opens it or chimes (the demo, the player's own, still does), its cards show no
--  buttons, the switch to that interface closes it, and closed it keeps no card that is over. Back in the mouse
--  interface, a card that waits on the player brings it back.
--    TuttiFrame (ns.UI.win)          UIParent's child, strata HIGH, kept on screen, moved by its header
--    ns.UI.Open(view) -> ok          "rolls" (the default), "recent" or "settings"; it rises when it was
--                                    hidden. A view nobody registered does not open (false); nor does another
--                                    view while a card that waits on the player has URGENT seconds or less
--                                    left: the rolls show instead (false).
--    ns.UI.Toggle(view) -> ok        closes the window when it shows `view`, else opens `view`
--    ns.UI.Close() -> ok             sinks and hides it and forgets the decided cards; never while a card
--                                    waits on the player: it shows the rolls instead (false)
--    ns.UI.View() -> name            the view it shows (or showed last)
--    ns.UI.Relayout()                fits the window to its view again: a view calls it when its height changed
--    ns.UI.RegisterView(name, build) a view for the header's clock ("recent") or gear ("settings"):
--                                    build(parent) is called once, the first time the view opens, and returns a
--                                    frame with :Refresh() (called every time the view opens) and :Height()
--                                    (read at every layout); the window anchors it to the top of its scroll
--                                    area, 300 px wide. Call it any time after this file has loaded.
--  The cards draw themselves from the model (ns.Card); the window only routes the messages to them and keeps
--  their order, their folds and the timers. Polestar (optional): its note about an item a party member still
--  needs sits under the window while both show (see "Polestar" below).
-------------------------------------------------------------------------------
local _, ns = ...
local UI = {}
ns.UI = UI

local W, Fx, Th, Rolls, Card = ns.W, ns.Fx, ns.Theme, ns.Rolls, ns.Card
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- Sizes in px: the mockup's CSS and the Global Constraints.
local WIDTH, HEAD_H, HEAD_ROW = 300, 32, 31                 -- .win; .hd, and its 31 px above the hairline
local PAD_LEFT, PAD_RIGHT, GAP = 10, 5, 7                   -- .hd padding and gap
local MARK, BUTTON, GLYPH = 15, 22, 14                      -- .mk; .ibtn and its glyph
local PILL_H, PILL_MIN, PILL_PAD, PILL_SIZE = 15, 17, 5, 10.5 -- .ct: height, min-width, padding, bold 10.5
local CLOSES_MARGIN = 3                                     -- .cl margin-right
local BAR_ALPHA = 0.85                                      -- .cbar: the accent at 85 %
local PAD_X = 10                                            -- .sec and .result padding
local SEC_H, SEC_MIDDLE, SEC_GAP = 23, 14.65, 8             -- .sec: 1 + 7 + 13.3 + 2; its line's middle; gap
local DIVIDER = 1                                           -- .card's border-top, above every card but the first
local LAST_PAD = 2                                          -- .result:last-child padding-bottom
local EMPTY_H, EMPTY_MIDDLE = 28, 12.35                     -- .hint: 5 + 14.7 + 8, its line's middle
local MAX_SHARE = 0.7                                       -- the window's height, of the screen's
local WHEEL = 40                                            -- px per wheel notch (Sotto's log)
local THUMB_W, THUMB_MIN, THUMB_INSET = 2, 16, 3            -- Sotto's scroll thumb
local NOTE_GAP = -4                                         -- Polestar's note under the window
-- The drop shadow (.win's box-shadow 0 10px 28px rgba(0,0,0,.55); tools/make_media.py works it out): its alpha, the
-- bands' reach past the sides, above and below, the side texture's two parts (under the top edge, above the bottom
-- edge) and the share of its rows the upper part has.
local DROP_ALPHA, DROP_SIDE, DROP_ABOVE, DROP_BELOW = 0.55, 40, 28, 52
local DROP_TOP, DROP_BOTTOM, DROP_ROWS = 46, 26, 40 / 64

-- Seconds.
local FOLD_AFTER = 4
local HOLD = 1     -- after the player's own pick, the rolls do not scroll under the mouse for this long
local URGENT = 10  -- a card that waits on the player with this little time left brings the rolls back
local EPSILON = 1e-6 -- times are sums of floats: "4 s after" is 4 to within this

local SCALE_MIN, SCALE_MAX = 0.5, 2 -- a size outside this (a damaged setting) reads as 100 %
local CHIME = W.MEDIA .. "Sounds\\chime.ogg"

-- Words.
local TITLES = { rolls = "Loot rolls", recent = "Recent rolls", settings = "Settings" }
local DONE, NO_ROLLS, KEPT_OPEN, CLOSES_IN = "DONE", "No rolls right now", "kept open", "closes in %ds"
local TIP_BACK, TIP_RECENT, TIP_SETTINGS, TIP_CLOSE = "Back to loot rolls", "Recent rolls", "Settings", "Close"

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local current = "rolls"    -- the view shown
local order = {}           -- the cards, in arrival order
local views = {}           -- card -> its view
local folded = {}          -- card -> true while it is a line under "DONE"
local unfolding = {}       -- card -> its late decision (R21) unfolds it once the mouse lets folds happen
local wholeSince = {}      -- card -> when it last came back whole from a fold: it stays whole FOLD_AFTER from then
local awaited = {}         -- card -> whether it waited on the player when the window last looked
local chimed = setmetatable({}, { __mode = "k" }) -- card -> the chime played for it
local stalled = setmetatable({}, { __mode = "k" }) -- view -> its Tick failed: it ticks no more until reused
local tops = {}            -- card -> where its view begins in the rolls, at the last layout
local builders, pages = {}, {} -- the registered views: name -> build, and once built, name -> frame
local broken = {}          -- name -> its builder failed: it is not asked again until registered anew
local countdown            -- { total, left, endsAt, paused } while the window counts down to closing
local closing              -- the Sink while the window fades out
local closingByItself      -- that fade is the countdown's (not a close the player asked for)
local contentHeight, visibleHeight = 0, 0
local byHand = false       -- the player has scrolled the rolls with the wheel (see `reveal`)
local pickedAt             -- GetTime() of the player's last own pick (see `reveal`)
local heldScroll = false   -- a reveal waits for the mouse (see `reveal`); it is done when the hold ends
local applied = 1          -- the size last given to the window (a new frame's scale is 1)

-------------------------------------------------------------------------------
--  Small helpers
-------------------------------------------------------------------------------
-- Sets a font string's font: a theme role, or a role's file at a size the roles lack (the pill's bold 10.5).
local function font(fs, role, size)
    Th.ApplyFont(fs, role, size)
end

-- A font string with its font set at once: the client refuses text before a font.
local function newText(parent, role, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    font(fs, role, size)
    fs:SetWordWrap(false)
    return fs
end

local function over(card) return card.status == "decided" or card.status == "ended" end

local function liveCount()
    local n = 0
    for _, card in ipairs(order) do
        if card.status == "live" then n = n + 1 end
    end
    return n
end

-- Every card is decided or ended (true without cards: there is nothing left to wait for).
local function allOver()
    for _, card in ipairs(order) do
        if not over(card) then return false end
    end
    return true
end

-- A card that waits on the player: its roll buttons show (with "Roll in Tutti" off at login, no card waits here:
-- Blizzard's popups take the pick, and the window closes as it does after a roll).
local function waits(card) return Card.Waits(card) end

local function anyAwaits()
    for _, card in ipairs(order) do
        if waits(card) then return true end
    end
    return false
end

-- A card that waits on the player has URGENT seconds or less left: the rolls are where the player has to be.
-- (The oldest waiting card is the first to get there, unless a newer roll is shorter: any of them counts.)
local function urgent()
    for _, card in ipairs(order) do
        if waits(card) and Rolls.TimeLeft(card) <= URGENT + EPSILON then return true end
    end
    return false
end

local function playerWon(card)
    for _, row in ipairs(Rolls.Rows(card)) do
        if row.isWinner and row.isPlayer then return true end
    end
    return false
end

-- The "close after the last roll" setting in seconds; 0 (never) for anything but a number above 0.
local function closeAfter()
    local seconds = ns.Clear(ns.Get("closeAfter"), "number")
    return (seconds and seconds > 0) and seconds or 0
end

-- The size setting as a scale.
local function sizeSetting()
    local scale = ns.Clear(ns.Get("scale"), "number")
    if not scale or scale ~= scale or scale < SCALE_MIN or scale > SCALE_MAX then return 1 end
    return scale
end

-------------------------------------------------------------------------------
--  The frame
-------------------------------------------------------------------------------
local win = CreateFrame("Frame", "TuttiFrame", UIParent)
UI.win = win
win.views = views
win:SetSize(WIDTH, HEAD_H)
win:SetFrameStrata("HIGH")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
if win.SetDontSavePosition then win:SetDontSavePosition(true) end -- Tutti keeps its own place
win:Hide()

-- EllesmereUI's panel colour, a 1 px white-10 % hairline inside, a 1 px dark edge outside, the drop shadow.
local ground = W.Fill(win, "bg", "BACKGROUND", -7)
ground:SetAllPoints()
W.Outline(win, "edge")
W.Border(win, "hair", "OVERLAY")

-- The mockup's drop shadow: a box the window's size, 10 px lower, blurred by 14 px, drawn only outside the window
-- (none under its 93 % ground). The bands above and below reach 40 px past the sides; each side has an upper and a
-- lower part, where the blur turns round the corners, and between them its alike rows stretched (fitDrop).
local function dropPiece(texture, flip)
    local t = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(texture, "CLAMP", "CLAMP")
    t:SetVertexColor(0, 0, 0, DROP_ALPHA)
    t.flip = flip
    return t
end
local drop = {
    above = dropPiece(W.MEDIA .. "dropabove"), below = dropPiece(W.MEDIA .. "dropbelow"), sides = {},
}
win.drop = drop
drop.above:SetPoint("BOTTOMLEFT", win, "TOPLEFT", -DROP_SIDE, 0)
drop.above:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", DROP_SIDE, 0)
drop.above:SetHeight(DROP_ABOVE)
drop.below:SetPoint("TOPLEFT", win, "BOTTOMLEFT", -DROP_SIDE, 0)
drop.below:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", DROP_SIDE, 0)
drop.below:SetHeight(DROP_BELOW)
for _, edge in ipairs({ "LEFT", "RIGHT" }) do
    local out = edge == "LEFT" and "RIGHT" or "LEFT" -- the side's edge that touches the window
    local flip = edge == "RIGHT" -- the right side is the left one, mirrored
    local side = {
        upper = dropPiece(W.MEDIA .. "dropside", flip), middle = dropPiece(W.MEDIA .. "dropside", flip),
        lower = dropPiece(W.MEDIA .. "dropside", flip),
    }
    side.upper:SetPoint("TOP" .. out, win, "TOP" .. edge)
    side.lower:SetPoint("BOTTOM" .. out, win, "BOTTOM" .. edge)
    side.middle:SetPoint("TOP" .. out, side.upper, "BOTTOM" .. out)
    side.middle:SetPoint("BOTTOM" .. out, side.lower, "TOP" .. out)
    for _, part in pairs(side) do part:SetWidth(DROP_SIDE) end
    drop.sides[edge] = side
end

-- The sides' parts for a window `height` high: a short one gives the upper and lower parts its height in their
-- shares, cut from their textures where they meet the middle, which then has no height.
local function fitDrop(height)
    local upper, lower = DROP_TOP, DROP_BOTTOM
    if height < upper + lower then
        upper, lower = height * DROP_TOP / (DROP_TOP + DROP_BOTTOM), height * DROP_BOTTOM / (DROP_TOP + DROP_BOTTOM)
    end
    for _, side in pairs(drop.sides) do
        local l, r = 0, 1
        if side.upper.flip then l, r = 1, 0 end
        side.upper:SetTexCoord(l, r, 0, DROP_ROWS * upper / DROP_TOP)
        side.upper:SetHeight(upper)
        side.middle:SetTexCoord(l, r, DROP_ROWS - 0.5 / 64, DROP_ROWS + 0.5 / 64)
        side.lower:SetTexCoord(l, r, 1 - (1 - DROP_ROWS) * lower / DROP_BOTTOM, 1)
        side.lower:SetHeight(lower)
    end
end

-- The header (.hd): the sky's gradient over the 31 px above its hairline, its items centred on them. Under the
-- hairline lies the gradient's first row again, the sky at 55 %, as the mockup's background (sized to the padding
-- box and repeated) draws it there: the line under the header reads a little brighter than a plain hairline.
local head = CreateFrame("Frame", nil, win)
win.head = head
head:SetPoint("TOPLEFT")
head:SetPoint("TOPRIGHT")
head:SetHeight(HEAD_H)
head:EnableMouse(true)
head:RegisterForDrag("LeftButton")
local sky = head:CreateTexture(nil, "BACKGROUND", nil, 1)
head.sky = sky
head.under = head:CreateTexture(nil, "BACKGROUND", nil, 1)
W.Paint(sky, function(t)
    local r, g, b = Th.Color("sky")
    local px = W.Pixel(head)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.55))
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT")
    t:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, px)
    head.under:SetColorTexture(r, g, b, 0.55)
    head.under:ClearAllPoints()
    head.under:SetPoint("BOTTOMLEFT")
    head.under:SetPoint("BOTTOMRIGHT")
    head.under:SetHeight(px)
end)
head.hair = W.Hair(head, "BOTTOM")

local items = CreateFrame("Frame", nil, head) -- the header's items, centred on it
items:SetPoint("TOPLEFT")
items:SetPoint("TOPRIGHT")
items:SetHeight(HEAD_ROW)

-- Lead: the mark in the rolls, the back arrow in Recent rolls and Settings.
head.mark = W.Icon(items, W.MEDIA .. "mark", MARK, "accent")
head.mark:SetPoint("LEFT", PAD_LEFT, 0)
head.back = W.IconButton(items, "back", TIP_BACK, function() UI.Open("rolls") end, BUTTON, GLYPH)
head.back:SetPoint("LEFT", PAD_LEFT, 0)
head.back:Hide()
head.title = W.Text(items, "title", "text")

-- The count of live cards (.ct): a pill of white at 10 %, the number bold 10.5 in the dim grey. A click on it leads
-- to the rolls, to the card that waits on the player (drawHeader colours it).
head.pill = W.Pill(items, PILL_H, "hair")
head.pill:SetPoint("LEFT", head.title, "RIGHT", GAP, 0)
head.count = newText(head.pill, "title", PILL_SIZE)
head.count:SetPoint("CENTER")
head.pill.hit = CreateFrame("Button", nil, head.pill)
head.pill.hit:SetAllPoints()
head.pill.hit:RegisterForClicks("LeftButtonUp")
head.pill.hit:SetScript("OnClick", function()
    byHand = false -- the player asks for the rolls: the waiting card comes into sight whatever they scrolled
    UI.Open("rolls")
end)
head.pill.hit:SetScript("OnEnter", function(self)
    if current ~= "rolls" then W.Tip(self, TIP_BACK) end
end)
head.pill.hit:SetScript("OnLeave", function(self) W.HideTip(self) end)
head.pill:Hide()

-- On the right: clock, gear, close; before them "closes in 7s" or "kept open".
head.close = W.IconButton(items, "close", TIP_CLOSE, function() UI.Close() end, BUTTON, GLYPH)
head.close:SetPoint("RIGHT", -PAD_RIGHT, 0)
head.gear = W.IconButton(items, "gear", TIP_SETTINGS, function()
    UI.Open(current == "settings" and "rolls" or "settings")
end, BUTTON, GLYPH)
head.gear:SetPoint("RIGHT", head.close, "LEFT", -GAP, 0)
head.clock = W.IconButton(items, "clock", TIP_RECENT, function()
    UI.Open(current == "recent" and "rolls" or "recent")
end, BUTTON, GLYPH)
head.clock:SetPoint("RIGHT", head.gear, "LEFT", -GAP, 0)
head.closes = W.Text(items, "small", "muted")
head.closes:SetJustifyH("RIGHT")
head.closes:SetPoint("RIGHT", head.clock, "LEFT", -(GAP + CLOSES_MARGIN), 0)
head.closes:Hide()

-- The countdown's line (.cbar): one pixel of the accent on the header's hairline, from the left.
head.bar = head:CreateTexture(nil, "ARTWORK")
head.bar:SetPoint("BOTTOMLEFT")
W.Paint(head.bar, function(t)
    local r, g, b = Th.Accent()
    t:SetColorTexture(r, g, b, BAR_ALPHA)
    t:SetHeight(W.Pixel(head))
end)
head.bar:Hide()

-- The body: a scroll frame under the header, its scroll child holding the views.
local scroll = CreateFrame("ScrollFrame", nil, win)
win.scroll = scroll
scroll:SetPoint("TOPLEFT", 0, -HEAD_H)
scroll:SetPoint("TOPRIGHT", 0, -HEAD_H)
scroll:SetHeight(0)
scroll:EnableMouseWheel(true)
local content = CreateFrame("Frame", nil, scroll)
win.content = content
content:SetSize(WIDTH, 0)
scroll:SetScrollChild(content)
local thumb = W.Fill(win, "scroll", "OVERLAY")
win.thumb = thumb
thumb:SetWidth(THUMB_W)
thumb:Hide()

-- The rolls: the cards, the "DONE" section (.sec) with the folded lines, or a line when there are no cards.
local rolls = CreateFrame("Frame", nil, content)
win.rolls = rolls
rolls:SetPoint("TOPLEFT")
rolls:SetPoint("TOPRIGHT")

local done = CreateFrame("Frame", nil, rolls)
win.done = done
done:SetHeight(SEC_H)
done.hair = W.Hair(done, "TOP", "hairSoft")
done.label = W.Text(done, "section", "muted")
done.label:SetPoint("LEFT", done, "TOPLEFT", PAD_X, -SEC_MIDDLE)
done.label:SetText(DONE)
done.rule = done:CreateTexture(nil, "BORDER") -- the line after the label, to the right edge
done.rule:SetPoint("LEFT", done.label, "RIGHT", SEC_GAP, 0)
done.rule:SetPoint("RIGHT", done, "TOPRIGHT", -PAD_X, -SEC_MIDDLE)
W.Paint(done.rule, function(t)
    t:SetColorTexture(Th.Color("hairSoft"))
    t:SetHeight(W.Pixel(done))
end)
done:Hide()

local empty = W.Text(rolls, "small", "faint")
win.empty = empty
empty:SetPoint("LEFT", rolls, "TOPLEFT", PAD_X, -EMPTY_MIDDLE)
empty:SetText(NO_ROLLS)
empty:Hide()

-------------------------------------------------------------------------------
--  Place and size
-------------------------------------------------------------------------------
local function fading() return closing ~= nil and closing:IsRunning() end

-- A fade-out in progress is called off: the window stays, where it belongs and fully drawn.
local function stayOpen()
    if fading() then Fx.Stop(win) end
    closing, closingByItself = nil, nil
end

-- The size setting, and the saved top-left corner. The corner is kept in UIParent's units and the anchor's
-- offsets are in the window's own (they grow with its scale), so they are divided by the scale: the corner
-- stays where it was saved, whatever the size. A hairline is one physical pixel at the scale it was painted
-- for (W.Pixel), so a new size paints everything again, the cards included, as new looks do. Whether the size is
-- new is asked of the size last given, not of GetScale: the client keeps a scale as a 32-bit float, so 1.1 reads
-- back as 1.100000023841858 and would look new at every opening and every drag.
local function place()
    local saved = ns.DB and ns.DB.window or {}
    local home = ns.DEFAULTS.window
    local x, y = ns.Clear(saved.x, "number") or home.x, ns.Clear(saved.y, "number") or home.y
    local scale = sizeSetting()
    local resized = scale ~= applied
    applied = scale
    win:SetScale(scale)
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / scale, y / scale)
    if resized then ns.Fire("LOOKS_CHANGED") end
end

-- After a drag: the top-left corner, in UIParent's units from its top-left, whole pixels.
local function savePosition()
    local saved = ns.DB and ns.DB.window
    local left, top = ns.Clear(win:GetLeft(), "number"), ns.Clear(win:GetTop(), "number")
    local scale = ns.Clear(win:GetEffectiveScale(), "number")
    local parentScale = ns.Clear(UIParent:GetEffectiveScale(), "number")
    local parentTop = ns.Clear(UIParent:GetTop(), "number")
    if not (saved and left and top and scale and parentScale and parentScale > 0 and parentTop) then return end
    scale = scale / parentScale -- the window's own scale against UIParent's: its units to UIParent's
    saved.point = "TOPLEFT"
    saved.x, saved.y = floor(left * scale + 0.5), floor(top * scale - parentTop + 0.5)
    place()
end

-- Scrolls to `offset` (kept between the top and the last card) and places the thumb.
local function scrollTo(offset)
    local range = max(contentHeight - visibleHeight, 0)
    offset = max(0, min(range, offset))
    scroll:SetVerticalScroll(offset)
    if range > 0 then
        local h = max(THUMB_MIN, visibleHeight * visibleHeight / contentHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -THUMB_INSET, -(offset / range) * (visibleHeight - h))
        thumb:SetHeight(h)
        thumb:Show()
    else
        thumb:Hide()
    end
end

-- Stacks the rolls: the whole cards in arrival order, a hairline between two (the card's divider, in the pixel
-- left for it), then "DONE" and the folded lines, 2 px after the last. -> their height
local function layoutRolls()
    local y, first, anyFolded = 0, true, false
    for _, card in ipairs(order) do
        local view = views[card]
        if folded[card] then
            anyFolded = true
        else
            if not first then y = y + DIVIDER end
            view:ClearAllPoints()
            view:SetPoint("TOPLEFT", rolls, "TOPLEFT", 0, -y)
            view.divider:SetShown(not first) -- no hairline between the header and the first card
            first = false
            tops[card] = y
            y = y + view:Height()
        end
    end
    done:SetShown(anyFolded)
    if anyFolded then
        done:ClearAllPoints()
        done:SetPoint("TOPLEFT", rolls, "TOPLEFT", 0, -y)
        done:SetPoint("TOPRIGHT", rolls, "TOPRIGHT", 0, -y)
        done.hair:SetShown(not first)
        y = y + SEC_H
        for _, card in ipairs(order) do
            if folded[card] then
                local view = views[card]
                view:ClearAllPoints()
                view:SetPoint("TOPLEFT", rolls, "TOPLEFT", 0, -y)
                tops[card] = y
                y = y + view:Height()
            end
        end
        y = y + LAST_PAD
    end
    empty:SetShown(#order == 0)
    if #order == 0 then y = EMPTY_H end
    rolls:SetHeight(y)
    return y
end

-- A registered view's height, 0 when it cannot say (an error in it is reported, as every handler's is).
local function pageHeight(page)
    local h
    ns.Safe(function() h = page:Height() end)
    return max(ns.Clear(h, "number") or 0, 0)
end

local function scrolled() return ns.Clear(scroll:GetVerticalScroll(), "number") or 0 end

local function hovered() return ns.Clear(win:IsMouseOver(), "boolean") == true end

local reveal -- below: brings the oldest card that waits on the player whole into sight

-- The window as high as its view, up to 70 % of the screen (the scroll frame shows the rest). The screen's
-- share is in UIParent's units, the window's height in its own, scaled ones. Every layout of the rolls ends with
-- the reveal, so a change anywhere in them (a card added, changed, decided, folded or gone, the group, the size)
-- never leaves the card the player has to roll on out of sight.
local function relayout()
    local height
    if current == "rolls" then
        height = layoutRolls()
    else
        local page = pages[current]
        height = page and pageHeight(page) or 0
        if page then page:SetHeight(height) end
    end
    local screen = ns.Clear(UIParent:GetHeight(), "number") or 768
    local scale = ns.Clear(win:GetScale(), "number") or 1
    contentHeight = height
    visibleHeight = max(min(height, MAX_SHARE * screen / scale - HEAD_H), 0)
    content:SetHeight(contentHeight)
    scroll:SetHeight(visibleHeight)
    win:SetHeight(HEAD_H + visibleHeight)
    fitDrop(HEAD_H + visibleHeight)
    scrollTo(scrolled())
    if current == "rolls" then reveal() end
end

-------------------------------------------------------------------------------
--  Keeping the waiting cards in sight (R45)
-------------------------------------------------------------------------------
-- Do px `top` to `bottom` of the rolls show, between the header and the window's bottom, at the scroll now? A
-- stretch higher than what shows counts as shown when it starts at the top.
local function inSight(top, bottom)
    local offset = scrolled()
    bottom = min(bottom, top + visibleHeight)
    return top >= offset - EPSILON and bottom <= offset + visibleHeight + EPSILON
end

-- A waiting card is in sight while its buttons show whole: the player can roll on it as the rolls stand.
local function buttonsInSight(card)
    local from, to = views[card]:ButtonsAt()
    return from ~= nil and tops[card] ~= nil and inSight(tops[card] + from, tops[card] + to)
end

-- The player has just picked, with the mouse over the window, and a card still waits: the rolls hold still under
-- the cursor that has just clicked.
local function holding()
    return pickedAt ~= nil and GetTime() - pickedAt < HOLD - EPSILON and hovered() and anyAwaits()
end

-- The one rule for the rolls' scroll. It runs after every layout of the rolls and on every return to them. The
-- oldest card that waits on the player is brought whole into sight, its top to the top of what shows (as far as
-- the scroll goes; a boss drop lands at once and the player works down from the top), and only when it is not
-- whole in sight already: nothing moves for a card that shows. The player's own scroll (the wheel) holds that off
-- only while some waiting card's buttons still show; a new waiting card ends it, and so does a new view. While the
-- mouse is over the window the scroll waits (`heldScroll`) as long as that card's buttons show whole (R50): the
-- player can click it as the rolls stand, and nothing slides under a cursor aiming at it; the scroll is done when
-- the mouse leaves. With its buttons out of sight it waits only HOLD seconds after the player's own pick, so the
-- next card's buttons do not land under the cursor in the moment after its click (a mouse that rests on the window
-- does not hold a card out of sight for longer).
function reveal()
    heldScroll = false
    if current ~= "rolls" then return end
    local first
    for _, card in ipairs(order) do
        if waits(card) and not folded[card] and tops[card] then first = card; break end
    end
    if not first then return end
    local top = tops[first]
    if inSight(top, top + views[first]:Height()) then return end
    if byHand then
        for _, card in ipairs(order) do
            if waits(card) and buttonsInSight(card) then return end
        end
    end
    if (hovered() and buttonsInSight(first)) or holding() then
        heldScroll = true
        return
    end
    byHand = false
    scrollTo(top)
end

-------------------------------------------------------------------------------
--  The header
-------------------------------------------------------------------------------
-- The clock and the gear are in the accent while their view shows (.ibtn.on), hovered or not.
local function paintButton(button, on)
    button.activeColor = on and "accent" or nil
    W.SetIconColor(button.icon, on and "accent" or (button.hover:IsShown() and "text" or button.restColor))
end

-- "closes in 7s" with the line at 70 %, or "kept open" with the line whole while the mouse is over the window.
local function drawCountdown()
    local shown, share = current == "rolls" and countdown ~= nil, 0
    head.closes:SetShown(shown)
    if shown and countdown.paused then
        head.closes:SetText(KEPT_OPEN)
        share = 1
    elseif shown then
        head.closes:SetText(CLOSES_IN:format(max(ceil(countdown.left - EPSILON), 0)))
        share = max(0, min(1, countdown.left / countdown.total))
    end
    head.bar:SetShown(share > 0)
    if share > 0 then head.bar:SetWidth(WIDTH * share) end
end

-- The count pill shows the live cards in every view. Outside the rolls, while a card there waits on the player, it
-- is in the accent (the accent's wash, the number in the accent), the only sign of that card in Recent rolls or
-- Settings; in the rolls it keeps the mockup's grey, as the waiting card shows its own accent there.
local function drawHeader()
    local onRolls = current == "rolls"
    head.mark:SetShown(onRolls)
    head.back:SetShown(not onRolls)
    head.title:SetText(TITLES[current] or current)
    head.title:ClearAllPoints()
    head.title:SetPoint("LEFT", PAD_LEFT + (onRolls and MARK or BUTTON) + GAP, 0)
    local live = liveCount()
    head.pill:SetShown(live > 0)
    if live > 0 then
        local alert = not onRolls and anyAwaits()
        font(head.count, "title", PILL_SIZE)
        head.count:SetText(live)
        head.count:SetTextColor(Th.Color(alert and "accent" or "dim"))
        head.pill:SetPillColor(alert and "accentWash" or "hair")
        head.pill:SetWidth(max(PILL_MIN, ceil(head.count:GetUnboundedStringWidth()) + 2 * PILL_PAD))
    end
    paintButton(head.clock, current == "recent")
    paintButton(head.gear, current == "settings")
    head.close:SetShown(not anyAwaits()) -- a card waiting on the player cannot be closed away
    drawCountdown()
end
W.Paint(head, drawHeader) -- the looks changed: the pill's font and the buttons' colours again

-------------------------------------------------------------------------------
--  Closing by itself
-------------------------------------------------------------------------------
-- The countdown runs while the window shows the rolls and every card is over; `restart` starts it again from
-- the full time (a decision, late or not, gets the whole time on screen).
local function updateCountdown(restart)
    local seconds = closeAfter()
    if win:IsShown() and not fading() and current == "rolls" and seconds > 0 and allOver() then
        if restart or not countdown then
            countdown = { total = seconds, left = seconds, endsAt = GetTime() + seconds, paused = hovered() }
        end
    else
        countdown = nil
    end
    drawCountdown()
end

-- One frame of the countdown, on the clock: it waits while the mouse is over the window, and goes on from
-- there when it leaves.
local function stepCountdown()
    local now = GetTime()
    if hovered() then
        if not countdown.paused then
            countdown.left, countdown.paused = max(countdown.endsAt - now, 0), true
        end
    else
        if countdown.paused then
            countdown.endsAt, countdown.paused = now + countdown.left, false
        end
        countdown.left = countdown.endsAt - now
    end
end

-- The window sinks away; hidden, it forgets the decided cards (Recent rolls keeps them).
local function fadeOut(byItself)
    countdown = nil
    closingByItself = byItself
    closing = Fx.Sink(win, function()
        closing, closingByItself = nil, nil
        win:Hide()
        Rolls.ForgetDecided()
    end)
end

-------------------------------------------------------------------------------
--  Folding
-------------------------------------------------------------------------------
-- While the mouse is over the window and a card waits on the player, no card folds or unfolds: either moves the
-- cards, and with them a waiting card's buttons, under the mouse. What was held happens when the mouse leaves or no
-- card waits any more.
local function foldsHeld() return hovered() and anyAwaits() end

-- A folded card decided late (R21) comes back whole, and stays whole FOLD_AFTER seconds from then.
local function unfold(card)
    unfolding[card] = nil
    if not folded[card] then return end
    folded[card] = nil
    wholeSince[card] = GetTime()
    views[card]:SetFolded(false)
end

-- A decided or ended card folds 4 s after its decision (or after it came back whole) while another card is still
-- whole; of several due at once the earliest folds first, so the last decided card is the one that stays. Held
-- under the mouse (foldsHeld). -> any folded or unfolded
local function refold()
    if foldsHeld() then return false end
    local changed = false
    for _, card in ipairs(order) do
        if unfolding[card] then
            unfold(card)
            changed = true
        end
    end
    local open = 0
    for _, card in ipairs(order) do
        if not folded[card] then open = open + 1 end
    end
    if open < 2 then return changed end
    local now, due = GetTime(), nil
    for i, card in ipairs(order) do
        local at = card.decidedAt
        if type(at) == "number" and wholeSince[card] then at = max(at, wholeSince[card]) end
        if not folded[card] and over(card) and type(at) == "number" and now - at >= FOLD_AFTER - EPSILON then
            due = due or {}
            due[#due + 1] = { card = card, at = at, i = i }
        end
    end
    if not due then return changed end
    table.sort(due, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.i < b.i
    end)
    for _, entry in ipairs(due) do
        if open > 1 then
            folded[entry.card] = true
            views[entry.card]:SetFolded(true)
            open = open - 1
            changed = true
        end
    end
    return changed
end

-------------------------------------------------------------------------------
--  Polestar
-------------------------------------------------------------------------------
-- Polestar's note about an item a party member still needs (frame PolestarLootNeeds, which Polestar makes
-- when it first has a line) sits under Blizzard's roll popups, or at the top of the screen (anchored to
-- UIParent) when it finds no Blizzard frame showing: that is where it ends up with Tutti's cards in their
-- place. While the note and the window both show, a note at the top of the screen hangs under the window
-- instead, and gets Polestar's own anchor back when the window hides. Polestar places the note again before
-- every Show, so a hook on its Show (hooksecurefunc) takes it in again each time. A note under a Blizzard frame
-- stays there. Tutti never writes anything else of Polestar's.
local note, noteHome

-- Only a note at the top of the screen, and only with an anchor that can be read, to be given back.
local function adoptNote()
    if not (note and win:IsVisible() and note:IsVisible()) then return end
    local point, rel, relPoint, x, y = note:GetPoint(1)
    point, rel, relPoint = ns.Text(point), ns.Clear(rel, "table"), ns.Text(relPoint)
    if not (point and relPoint) or rel ~= UIParent then return end
    noteHome = { point, rel, relPoint, ns.Clear(x, "number") or 0, ns.Clear(y, "number") or 0 }
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, NOTE_GAP)
end

local function releaseNote()
    if not (note and noteHome) then return end
    local home = noteHome
    noteHome = nil
    local _, rel = note:GetPoint(1)
    if ns.Clear(rel, "table") ~= win then return end
    note:ClearAllPoints()
    note:SetPoint(home[1], home[2], home[3], home[4], home[5])
end

-- Looks for the note until Polestar has made it (never, without Polestar), then hooks it once.
local function findNote()
    local frame = ns.Clear(_G.PolestarLootNeeds, "table")
    if not (frame and type(frame.GetPoint) == "function" and type(frame.Show) == "function") then return end
    note = frame
    hooksecurefunc(note, "Show", function() ns.Safe(adoptNote) end)
    adoptNote()
end

-------------------------------------------------------------------------------
--  Views
-------------------------------------------------------------------------------
-- A registered view's frame, built the first time it is wanted. Nil when nobody registered it, or when its
-- builder failed or gave no frame with :Refresh() and :Height(): that is reported once and the builder is not
-- asked again (it would make its frames anew each time), until a builder is registered for the name again.
local function pageOf(name)
    if pages[name] then return pages[name] end
    local build = builders[name]
    if not build or broken[name] then return nil end
    local frame
    local ok = ns.Safe(function() frame = build(content) end)
    if ok and not (type(frame) == "table" and type(frame.Refresh) == "function"
        and type(frame.Height) == "function") then
        ok = false
        ns.Safe(error, ("Tutti: the view %q gave no frame with :Refresh() and :Height()"):format(name))
    end
    if not ok then
        broken[name] = true
        return nil
    end
    frame:SetParent(content)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT")
    frame:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    frame:Hide()
    pages[name] = frame
    return frame
end

-- A new view starts at its top: the player's own scroll was of another, and the rolls bring their waiting card
-- into sight again on the way back (the layout's reveal).
local function switchTo(name)
    current = name
    rolls:SetShown(name == "rolls")
    for other, page in pairs(pages) do page:SetShown(other == name) end
    byHand = false
    scroll:SetVerticalScroll(0)
end

function UI.Open(name)
    if name == nil then name = "rolls" end
    if name ~= "rolls" and not pageOf(name) then return false end
    local refused = name ~= "rolls" and urgent() -- a roll about to end: the rolls instead
    if refused then name = "rolls" end
    local appearing = not win:IsShown()
    stayOpen()
    if appearing then byHand = false end
    if appearing or name ~= current then switchTo(name) end
    if name ~= "rolls" then ns.Safe(pages[name].Refresh, pages[name]) end
    if appearing then
        place()
        win:Show()
    end
    updateCountdown()
    relayout()
    drawHeader()
    if appearing then Fx.Rise(win) end
    return not refused
end

function UI.Close()
    if not win:IsShown() or fading() then return false end
    if anyAwaits() then
        UI.Open("rolls")
        return false
    end
    fadeOut(false)
    return true
end

function UI.Toggle(name)
    if name == nil then name = "rolls" end
    if win:IsShown() and not fading() and current == name then return UI.Close() end
    return UI.Open(name)
end

function UI.View() return current end

function UI.Relayout() relayout() end

function UI.RegisterView(name, build)
    if type(name) ~= "string" or name == "rolls" or type(build) ~= "function" then return false end
    builders[name], broken[name] = build, nil
    return true
end

-------------------------------------------------------------------------------
--  Scripts
-------------------------------------------------------------------------------
head:SetScript("OnDragStart", function()
    if fading() then
        stayOpen() -- the player took hold of it: it stays
        updateCountdown(true)
    end
    Fx.Stop(win) -- a rise in progress ends where the window belongs
    win:StartMoving()
end)
head:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    savePosition()
end)

-- Only a wheel that moved the rolls counts as the player's own scroll (`byHand`, see `reveal`): a notch at either
-- end, or one in Recent rolls or Settings, leaves the rolls bringing their waiting card into sight. The wheel
-- itself never brings it back: the player may look elsewhere until the rolls change.
scroll:SetScript("OnMouseWheel", function(_, delta)
    delta = ns.Clear(delta, "number")
    if not delta then return end
    local before = scrolled()
    scrollTo(before - delta * WHEEL)
    if current == "rolls" and scrolled() ~= before then byHand = true end
end)

-- Every frame while the window shows: the cards' seconds and bars, the folds, a reveal that waited for the mouse,
-- the way back to the rolls, the countdown, and Polestar's note until it exists. Each runs protected, so one that
-- fails stops none of the others (the window always closes); a card whose Tick failed is reported once and ticks
-- no more.
local function tickCards()
    for _, card in ipairs(order) do
        local view = views[card]
        if not stalled[view] and not ns.Safe(view.Tick, view) then stalled[view] = true end
    end
end

local function foldStep()
    if refold() then relayout() end
end

local function holdStep()
    if heldScroll and not holding() then reveal() end
end

-- Recent rolls or Settings while a card that waits on the player is about to end: back to the rolls.
local function urgentStep()
    if current ~= "rolls" and urgent() then UI.Open("rolls") end
end

local function countdownStep()
    if not countdown or fading() then return end
    stepCountdown()
    drawCountdown()
    if not countdown.paused and countdown.left <= EPSILON then fadeOut(true) end
end

win:SetScript("OnUpdate", function()
    tickCards()
    ns.Safe(foldStep)
    ns.Safe(holdStep)
    ns.Safe(urgentStep)
    ns.Safe(countdownStep)
    if not note then ns.Safe(findNote) end
end)

win:SetScript("OnShow", function() adoptNote() end)

win:SetScript("OnHide", function()
    releaseNote()
    -- A list a raid card's summary opened goes with the window.
    local menu = W.CurrentMenu()
    if menu and menu:IsShown() and menu.anchor and not menu.anchor:IsVisible() then W.CloseMenu() end
end)

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
-- WoW Forever's gamepad interface: Blizzard's gamepad roll frame takes the game's rolls, so none of them opens the
-- window or chimes. The demo is the player's own: it plays as ever.
local function standsDown(card) return not card.demo and ns.Popups.Gamepad() end

-- Closed in the gamepad interface, the window keeps no card that is over, as a window that closes forgets them: a
-- frame after a decision (not during it, while Core/Rolls.lua is still at work on the card), the cards that are over
-- are forgotten. Recent rolls keeps them.
local sweepDue = false
local function sweep()
    sweepDue = false
    if ns.Popups.Gamepad() and not win:IsShown() then Rolls.ForgetDecided() end
end

-- A new card: in at the bottom of the open cards, and the window shows the rolls (rising if it was hidden); in the
-- gamepad interface it stays as it is. A new card that waits on the player ends the player's own scroll (`byHand`):
-- the layout's reveal brings the oldest waiting card into sight.
ns.Listen("CARD_ADDED", function(card)
    if type(card) ~= "table" or views[card] then return end
    local view = Card.Acquire(rolls)
    views[card], stalled[view] = view, nil
    order[#order + 1] = card
    view:Bind(card)
    awaited[card] = waits(card)
    if awaited[card] then byHand = false end
    refold()
    if standsDown(card) then
        updateCountdown()
        relayout()
        drawHeader()
    else
        UI.Open("rolls")
    end
end)

-- The card draws what changed, and the rolls are laid out again (the reveal with them). The player's own pick
-- starts the HOLD under the mouse. A card that starts waiting on the player (its roll joined a card the history
-- made, or a bind confirmation gave the pick back) is a new waiting card: it brings the rolls up, hidden or not.
ns.Listen("CARD_CHANGED", function(card, changes)
    local view = views[card]
    if not view then return end
    if type(changes) == "table" and changes.mine and card.mine ~= nil then pickedAt = GetTime() end
    view:Update(changes)
    local awaits = waits(card)
    local started = awaits and not awaited[card]
    awaited[card] = awaits
    if started then
        byHand = false
        UI.Open("rolls")
    else
        relayout()
        drawHeader()
    end
end)

-- A result. A card decided after it ended (R21) and already folded comes back whole (once the mouse lets folds
-- happen) and folds again 4 s after that; the countdown starts over, so the result stays on screen its whole time,
-- and a fade-out of the countdown's own is called off for it. The chime when the player won (not in the gamepad
-- interface). Closed in the gamepad interface, the window forgets the card a frame later (`sweep`).
ns.Listen("CARD_DECIDED", function(card)
    local view = views[card]
    if not view then return end
    if folded[card] then
        if foldsHeld() then unfolding[card] = true else unfold(card) end
    end
    if card.status == "decided" and not chimed[card] and playerWon(card) then
        chimed[card] = true
        if ns.Get("sound") == "chime" and not standsDown(card) then PlaySoundFile(CHIME, "Master") end
    end
    if fading() and closingByItself then stayOpen() end
    relayout()
    updateCountdown(true)
    drawHeader()
    if ns.Popups.Gamepad() and not win:IsShown() and not sweepDue then
        sweepDue = true
        ns.After(0, sweep)
    end
end)

ns.Listen("CARD_REMOVED", function(card)
    local view = views[card]
    if not view then return end
    Card.Release(view)
    views[card], folded[card], awaited[card], tops[card] = nil, nil, nil, nil
    unfolding[card], wholeSince[card] = nil, nil
    for i, c in ipairs(order) do
        if c == card then table.remove(order, i); break end
    end
    relayout()
    updateCountdown()
    drawHeader()
end)

-- The rows come from the group.
ns.Listen("GROUP_CHANGED", function()
    for _, card in ipairs(order) do views[card]:Update({}) end
    relayout()
end)

-- Whether the player rolls in Tutti may have changed ("Roll in Tutti", or Blizzard's popups switched off): every
-- card draws its buttons, or none, again. A card that starts waiting so is a new waiting card; the window stays in
-- the view it shows (Settings, where the switch is), and comes back with the rolls if it was closed.
local function rollRuleChanged()
    local started = false
    for _, card in ipairs(order) do
        views[card]:Update({})
        local awaits = waits(card)
        if awaits and not awaited[card] then started = true end
        awaited[card] = awaits
    end
    if started then byHand = false end
    if started and not win:IsShown() then
        UI.Open("rolls")
    else
        relayout()
        drawHeader()
    end
end

ns.Listen("POPUPS_CHANGED", rollRuleChanged)

-- The interface style changed (a frame after the game's event, Core/Popups.lua). Into the gamepad interface,
-- Blizzard's gamepad roll frame takes every roll still running (it lists them itself): the cards lose their buttons
-- and the window goes or, closed already, forgets the cards that are over. Back in the mouse interface the cards are
-- the way to roll again: one that waits on the player brings the rolls back, as turning "Roll in Tutti" on does.
ns.Listen("GAMEPAD_CHANGED", function(on)
    rollRuleChanged()
    if on ~= true then return end
    if win:IsShown() then UI.Close() else Rolls.ForgetDecided() end
end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == "scale" then
        if fading() then return end -- on its way out: the next open places it at the new size
        Fx.Stop(win) -- a rise in progress would put the old place back
        place()
        relayout()
    elseif key == "closeAfter" then
        updateCountdown(true)
    elseif key == "rollInTutti" then
        rollRuleChanged()
    end
end)

ns.Listen("DB_READY", function() place() end)
ns.On("UI_SCALE_CHANGED", function() relayout() end)
ns.On("DISPLAY_SIZE_CHANGED", function() relayout() end)

fitDrop(HEAD_H)
place()
