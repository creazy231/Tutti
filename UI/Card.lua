-------------------------------------------------------------------------------
--  Tutti: one card, the window's view of one item (the approved mockup's .card). The item's head (icon,
--  name in its quality colour, the subtitle), the countdown, the roll buttons while the card waits on the
--  player, then one row per group member with their pick and number, and the winner. Folded, the card is
--  one line (.result). Everything is drawn from the card as it is now (ns.Rolls), never from a message's
--  change keys: those only say which effects to play.
--    ns.Card.Acquire(parent) -> view   a card view from the pool, shown, in `parent`, 300 px wide; anchor it
--    ns.Card.Release(view)             back to the pool: its effects stop, it is hidden, unanchored, unbound
--    view:Bind(card)                   show a card as it is, without effects
--    view:Update(changes)              the card as it is now (after CARD_CHANGED; after GROUP_CHANGED with {}),
--                                      with the effects of what is new since the view last drew it: a new pick
--                                      fades in, a new number spins; with changes.decided and a winner, the
--                                      winner's wash sweeps and the crown pops, and when the winner is the
--                                      player the icon ring glows twice and the shine crosses the card once
--    view:Height() -> px               9 + 34 + 16 [+ 31 buttons [+ 16 reason]] + 21 a row [+ 22 summary] + 7,
--                                      or 26 folded; the view's own height follows it
--    view:SetFolded(bool)              the 26 px line: icon, name → winner, "Need 19"
--    view:Tick()                       the countdown's seconds and bar; the window calls it every second
--    view.divider                      the hairline along the card's top: the window hides it on the first card
--    ns.Card.NewRow(parent) -> row     one row (.pr), anchored by the caller; Recent rolls paints with it
--    row:Set(data, opts)               data: a row of ns.Rolls.Rows (or a copy of one); opts = { decided = bool,
--                                      height = 21 | 19 }: decided, everyone but the winner fades back
--  The rows of a view are pooled with it. In a raid (ns.Group.IsRaid()) a card lists who picks Need, Greed or
--  Transmog, the winner and the player; a summary line counts the rest ("13 passed · 2 choosing") and lists
--  them when clicked.
-------------------------------------------------------------------------------
local _, ns = ...
local Card = {}
ns.Card = Card

local W, Fx, Th, Rolls = ns.W, ns.Fx, ns.Theme, ns.Rolls
local ceil, max, min = math.ceil, math.max, math.min

-- Sizes in px: the mockup's CSS and the Global Constraints.
local WIDTH = 300                                         -- the window's
local PAD_TOP, PAD_X, PAD_BOTTOM = 9, 10, 7               -- .card padding
local ICON, ICON_GAP = 34, 9                              -- .ico, the .ihead gap
local NAME_H, SUB_GAP, SUB_H = 16, 2, 13                  -- .in line height, .is margin and line height
local TIMER_BLOCK, TIMER_GAP, TIMER_H = 16, 8, 2          -- .timer: 8 above, 2 high, 6 below
local BUTTONS_BLOCK, BUTTONS_GAP, BUTTON_GAP = 31, 1, 4   -- .btns: 1 above, 23 high, 7 below; 4 between
local REASON_BLOCK, REASON_GAP, REASON_H = 16, -3, 12     -- .why: -3 above, 12 high, 7 below
local ROW_H, SUMMARY_H, FOLD_H = 21, 22, 26               -- .pr, .sum, .result
local EDGE = 2                                            -- .card.yours::before, the winner's inset edge
local PIECE_GAP, YOURS_GAP = 4, 3                         -- .is gap; a space before " · 54s"
local RING = 46                                           -- the glow ring, centred on the 34 px icon
local SHINE_SHARE, SHINE_ALPHA, GLOWS = 0.34, 0.2, 2      -- the shine band: a third of the card, at 20 %
local TRACK = { 1, 1, 1, 0.08 }                           -- .timer's ground

-- Rows (.pr): 4 px padding and 7 px gaps; class icon 15, pick column 64 (glyph 13, 4 px), roll column 38.
local ROW_PAD, ROW_GAP, CLASS_ICON, YOU_GAP = 4, 7, 15, 5
local PICK_W, ROLL_W, GLYPH, GLYPH_GAP, CROWN, CROWN_GAP = 64, 38, 13, 4, 12, 3
local NAME_X = ROW_PAD + CLASS_ICON + ROW_GAP             -- 26 from the left
local PICK_X = ROW_PAD + ROLL_W + ROW_GAP + PICK_W        -- 113 from the right
local NAME_END = PICK_X + ROW_GAP                         -- the name stops 120 from the right
local NUMBER = 13                                         -- .rn font size
local WASH_ALPHA, ME_ALPHA = 0.28, 0.035                  -- the winner's wash, the player's row
local DIM = { pass = 0.55, out = 0.45 }                   -- a row's alpha while the roll is on
local LOSER = 0.42                                        -- everyone but the winner once it is over

-- The summary line (.sum), the folded line (.result) and the BiS badge (.bis).
local SUM_GAP, SUM_ICON, SUM_CHEVRON = 6, 12, 9
local FOLD_ICON, FOLD_GAP, FOLD_SIZE = 18, 7, 12
local FOLD_NAME_X = PAD_X + FOLD_ICON + FOLD_GAP          -- 35
local ARROW, ARROW_SIDE = 14, 2.5                         -- the turned arrow glyph, and its clear sides
local BADGE_H, BADGE_LEFT, BADGE_RIGHT, BADGE_SIZE = 14, 4, 5, 10
local STAR, STAR_GAP = 9, 3
local BADGE_FILL, BADGE_RING = 0.12, 0.35                 -- the badge colour over the ground, its outline
local SUB_SIZE = 11                                       -- .is font size

-- Words. A pick's is the game's where it has one, else English; Transmog is always the short word (R27).
local WORDS = { need = { "NEED", "Need" }, greed = { "GREED", "Greed" }, pass = { "PASS", "Pass" },
    transmog = { false, "Transmog" } }
local CHOOSING, ABSENT = "choosing", "not in this roll"
local YOUR_PICK, YOU_WON, WON, YOU = "Your pick", "You won", "won", "You"
local EVERYONE_PASSED, ROLL_ENDED = "Everyone passed", "Roll ended"
local NEED_REASON, NO_REASON = "Need: ", "not available"

local PICKED = { need = true, greed = true, transmog = true, pass = true } -- a state with a glyph
local WINNING = { need = true, greed = true, transmog = true }            -- a state that can win
local BOLD, REGULAR = "item", "sub" -- font roles whose files are the bold and the regular font

local function word(state)
    local w = WORDS[state]
    if w then return ns.Text(w[1] and _G[w[1]]) or w[2] end
    return state == "wait" and CHOOSING or ABSENT
end

-- "Need 19": how the winner won, nil for a state that cannot win (an unreadable pick).
local function howWon(data)
    if not WINNING[data.state] then return nil end
    return word(data.state) .. (data.roll and " " .. data.roll or "")
end

-------------------------------------------------------------------------------
--  Text
-------------------------------------------------------------------------------
-- Sets a font string's font: a theme role, or a role's file at a size the roles lack (the subtitle's bold
-- 11 px, the badge's bold 10, the folded line's bold 12, a loser's regular 13).
local function font(fs, role, size)
    Th.ApplyFont(fs, role)
    if size then
        local path, _, flags = fs:GetFont()
        if path then fs:SetFont(path, size, flags) end
    end
end

-- A font string with its font set at once (the client refuses text before a font): one line, from the left.
local function newText(parent, role, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    font(fs, role, size)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A colour: a palette name or { r, g, b [, a] }.
local function rgb(c)
    if type(c) == "table" then return c[1], c[2], c[3], c[4] or 1 end
    return Th.Color(c)
end

local function paint(fs, c) fs:SetTextColor(rgb(c)) end

local function classColor(file) return { Th.ClassColor(file) } end

-- How wide a text is. Unbounded: the client holds GetStringWidth to the width a font string has.
local function textWidth(fs) return fs:GetUnboundedStringWidth() end

-- Lays regions out left to right, `gap` px apart, the first `x` from the left of `anchor`, each centred on it.
local function chain(list, anchor, x, gap)
    for i, region in ipairs(list) do
        region:ClearAllPoints()
        if i == 1 then
            region:SetPoint("LEFT", anchor, "LEFT", x, 0)
        else
            region:SetPoint("LEFT", list[i - 1], "RIGHT", gap, 0)
        end
    end
end

-- "54s": the seconds left, a second that has begun counted whole (a hair of float noise is not a second).
local function seconds(card)
    local left = Rolls.TimeLeft(card) - 1e-6
    return (left > 0 and ceil(left) or 0) .. "s"
end

-------------------------------------------------------------------------------
--  Still choosing: three pulsing dots (.dots)
-------------------------------------------------------------------------------
local DOT, DOT_PITCH, DOT_TEX = 3, 5, 16 -- 3 px dots 2 px apart; the dot glyph is 3 px drawn at 16 px
local PULSE, PULSE_STAGGER = 1.2, 0.2    -- one pulse per 1.2 s, each dot 0.2 s after the one before
local PULSE_TOP, PULSE_LOW, FAINT_DOT = 0.4, 0.8, 0.25

-- A dot's alpha `p` seconds into its pulse: 25 % up to full at 40 %, down to 25 % at 80 %, resting after.
local function dotAlpha(p)
    local up, down = PULSE_TOP * PULSE, PULSE_LOW * PULSE
    if p < up then return FAINT_DOT + (1 - FAINT_DOT) * p / up end
    if p < down then return 1 - (1 - FAINT_DOT) * (p - up) / (down - up) end
    return FAINT_DOT
end

-- The looping alpha of a dot `delay` seconds behind the first: one 1.2 s loop cut at the pulse's turns, so
-- every dot keeps the period and its own phase.
local function pulse(tex, delay)
    local group = tex:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local marks = { 0, PULSE }
    for _, turn in ipairs({ 0, PULSE_TOP * PULSE, PULSE_LOW * PULSE }) do marks[#marks + 1] = (turn + delay) % PULSE end
    table.sort(marks)
    local order = 0
    for i = 1, #marks - 1 do
        local from, to = marks[i], marks[i + 1]
        if to - from > 1e-6 then
            order = order + 1
            local fade = group:CreateAnimation("Alpha")
            fade:SetFromAlpha(dotAlpha((from - delay) % PULSE))
            fade:SetToAlpha(dotAlpha((to - delay) % PULSE))
            fade:SetDuration(to - from)
            fade:SetOrder(order)
        end
    end
    return group
end

local function newDots(parent, colorName)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(2 * DOT_PITCH + DOT, DOT_TEX)
    f.dots = {}
    for i = 1, 3 do
        local tex = W.Icon(f, "dot", DOT_TEX, colorName)
        tex:SetPoint("CENTER", f, "LEFT", DOT / 2 + (i - 1) * DOT_PITCH, 0)
        tex.pulse = pulse(tex, (i - 1) * PULSE_STAGGER)
        tex.pulse:Play()
        f.dots[i] = tex
    end
    -- The game stops an animation whose region hides: the dots pulse again whenever they show.
    f:SetScript("OnShow", function(self) for _, tex in ipairs(self.dots) do tex.pulse:Play() end end)
    f:SetScript("OnHide", function(self) for _, tex in ipairs(self.dots) do tex.pulse:Stop() end end)
    return f
end

-------------------------------------------------------------------------------
--  A row (.pr)
-------------------------------------------------------------------------------
local Row = {}

-- The name is cut with an ellipsis where it would run into the pick column (and the YOU tag after it).
local function fitName(row)
    local width = row:GetWidth()
    if not (width and width > 0) then return end
    local room = width - NAME_END - NAME_X
    if row.you:IsShown() then room = room - YOU_GAP - textWidth(row.you) end
    row.name:SetWidth(textWidth(row.name) > room and max(room, 1) or 0)
end

local function paintRow(row)
    local data, opts = row.data, row.opts
    if not data then return end
    local state, winner, mine = data.state, data.isWinner == true, data.isPlayer == true
    row:SetHeight(opts.height or ROW_H)

    -- The player's row: a white wash and the YOU tag.
    row.me:SetShown(mine)
    row.you:SetShown(mine)
    font(row.you, "you")
    paint(row.you, "faint")

    -- The class icon in its black rim, the first name in the class colour.
    row.rim:SetShown(W.ClassIcon(row.class, data.class))
    font(row.name, "row")
    row.name:SetText(data.name or "")
    paint(row.name, classColor(data.class))

    -- The pick: glyph and word in its colour; dots and "choosing"; or "not in this roll" across both columns.
    local picked = PICKED[state] == true
    font(row.word, "pick")
    row.word:SetText(word(state))
    paint(row.word, picked and state or "faint")
    row.word:ClearAllPoints()
    row.word:SetPoint("LEFT", row.pick, "LEFT", (picked or state == "wait") and GLYPH + GLYPH_GAP or 0, 0)
    if picked then
        row.glyph:SetTexture(W.MEDIA .. "Icons\\" .. state)
        W.SetIconColor(row.glyph, state)
    end
    row.glyph:SetShown(picked)
    row.dots:SetShown(state == "wait")

    -- The number: the winner's in the accent, by the crown; a loser's muted and regular once it is over.
    local loser = opts.decided and not winner and data.roll ~= nil
    if loser then font(row.roll, REGULAR, NUMBER) else font(row.roll, "roll") end
    paint(row.roll, winner and "accent" or loser and "muted" or "text")
    if data.roll == nil then Fx.Stop(row.roll) end -- a number the game took back spins no more
    row.roll:SetText(data.roll and tostring(data.roll) or "")
    row.crown:SetShown(winner)
    row.wash:SetShown(winner)
    row.edge:SetShown(winner)
    local r, g, b = Th.Accent()
    row.wash:SetVertexColor(r, g, b, WASH_ALPHA)

    -- Once the roll is over everyone but the winner fades back; before, a pass and who is not in the roll.
    if opts.decided then
        row:SetAlpha(winner and 1 or LOSER)
    else
        row:SetAlpha(DIM[state] or 1)
    end
    fitName(row)
end

function Row:Set(data, opts)
    self.data = type(data) == "table" and data or nil
    self.opts = type(opts) == "table" and opts or {}
    paintRow(self)
end

function Card.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.me = W.Fill(row, { 1, 1, 1, ME_ALPHA }, "BACKGROUND", -1)
    row.me:SetAllPoints()
    -- The winner's wash: the accent fading out to the right (Media\wash at 28 %), with a 2 px edge.
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetTexture(W.MEDIA .. "wash")
    row.wash:SetAllPoints()
    row.edge = W.Fill(row, "accent", "BORDER")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(EDGE)

    row.class = row:CreateTexture(nil, "ARTWORK")
    row.class:SetSize(CLASS_ICON, CLASS_ICON)
    row.class:SetPoint("LEFT", ROW_PAD, 0)
    row.rim = row:CreateTexture(nil, "BORDER", nil, 1)
    W.Paint(row.rim, function(rim) -- one physical pixel of black around the class icon, at any UI scale
        local px = W.Pixel(row)
        rim:SetColorTexture(0, 0, 0, 1)
        rim:ClearAllPoints()
        rim:SetPoint("TOPLEFT", row.class, "TOPLEFT", -px, px)
        rim:SetPoint("BOTTOMRIGHT", row.class, "BOTTOMRIGHT", px, -px)
    end)
    row.name = newText(row, "row")
    row.name:SetPoint("LEFT", NAME_X, 0)
    row.you = newText(row, "you")
    row.you:SetPoint("LEFT", row.name, "RIGHT", YOU_GAP, 0)
    row.you:SetText("YOU")

    row.pick = CreateFrame("Frame", nil, row)
    row.pick:SetPoint("TOPLEFT", row, "TOPRIGHT", -PICK_X, 0)
    row.pick:SetPoint("BOTTOMLEFT", row, "BOTTOMRIGHT", -PICK_X, 0)
    row.pick:SetWidth(PICK_W)
    row.glyph = W.Icon(row.pick, "need", GLYPH, "need")
    row.glyph:SetPoint("LEFT")
    row.dots = newDots(row.pick, "faint")
    row.dots:SetPoint("LEFT")
    row.word = newText(row.pick, "pick")

    row.roll = newText(row, "roll")
    row.roll:SetJustifyH("RIGHT")
    row.roll:SetPoint("RIGHT", -ROW_PAD, 0)
    row.crown = CreateFrame("Frame", nil, row) -- a frame, so that it can pop
    row.crown:SetSize(CROWN, CROWN)
    row.crown:SetPoint("CENTER", row.roll, "LEFT", -(CROWN_GAP + CROWN / 2), 0)
    row.crown.icon = W.Icon(row.crown, "crown", CROWN, "accent")
    row.crown.icon:SetAllPoints()

    for _, part in ipairs({ row.me, row.wash, row.edge, row.you, row.crown, row.dots }) do part:Hide() end
    for key, fn in pairs(Row) do row[key] = fn end
    W.Paint(row, paintRow)
    return row
end

-- Puts a row's effects at rest: a row about to show someone else, or a view going back to the pool.
local function stopRow(row)
    Fx.Stop(row.roll)
    Fx.Stop(row.pick)
    Fx.Stop(row.wash)
    Fx.Stop(row.crown)
end

-------------------------------------------------------------------------------
--  The item: its tooltip and a modified click (icon and name, on the card and the folded line)
-------------------------------------------------------------------------------
-- The roll's own tooltip while the game still has the roll, else the link's.
local function showItem(owner, card)
    if not card then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if card.rollID and card.status == "live" and not card.over then
        shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, card.rollID)
    elseif card.link then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, card.link)
    end
    if shown then GameTooltip:Show() else GameTooltip:Hide() end
end

local function itemHit(view, parent)
    local hit = CreateFrame("Button", nil, parent)
    hit:RegisterForClicks("LeftButtonUp")
    hit:SetScript("OnEnter", function(self) showItem(self, view.card) end)
    hit:SetScript("OnLeave", function(self) W.HideTip(self) end)
    -- Shift puts the link in chat, Ctrl opens the dressing room: the game's own modified click.
    hit:SetScript("OnClick", function()
        local card = view.card
        if card and card.link and IsModifiedClick() and type(HandleModifiedItemClick) == "function" then
            HandleModifiedItemClick(card.link)
        end
    end)
    return hit
end

-------------------------------------------------------------------------------
--  Parts of the card
-------------------------------------------------------------------------------
-- The BiS badge (.bis): a pill in the badge's colour at 12 % with a 35 % outline, a star, the words.
local function stadium(frame, inset, sub)
    local h = BADGE_H - 2 * inset
    local l, m, r = frame:CreateTexture(nil, "ARTWORK", nil, sub), frame:CreateTexture(nil, "ARTWORK", nil, sub),
        frame:CreateTexture(nil, "ARTWORK", nil, sub)
    for _, t in ipairs({ l, m, r }) do t:SetTexture(W.MEDIA .. "circle") end
    l:SetTexCoord(0, 0.5, 0, 1)
    l:SetPoint("TOPLEFT", inset, -inset)
    l:SetPoint("BOTTOMLEFT", inset, inset)
    l:SetWidth(h / 2)
    r:SetTexCoord(0.5, 1, 0, 1)
    r:SetPoint("TOPRIGHT", -inset, -inset)
    r:SetPoint("BOTTOMRIGHT", -inset, inset)
    r:SetWidth(h / 2)
    m:SetTexCoord(0.49, 0.51, 0, 1)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT")
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return { l, m, r }
end

local function newBadge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(BADGE_H)
    b.outline = stadium(b, 0, 0)
    b.fill = stadium(b, 1, 1) -- opaque over the outline, so the outline shows as a 1 px ring
    b.star = W.Icon(b, "star", STAR, "text", "OVERLAY")
    b.star:SetPoint("LEFT", BADGE_LEFT, 0)
    b.text = newText(b, BOLD, BADGE_SIZE)
    b:Hide()
    return b
end

local function paintBadge(b, badge)
    local r, g, bl = badge.r, badge.g, badge.b
    local ground = { Th.Color("bg") }
    for _, t in ipairs(b.outline) do t:SetVertexColor(r, g, bl, BADGE_RING) end
    for _, t in ipairs(b.fill) do
        t:SetVertexColor(ground[1] + (r - ground[1]) * BADGE_FILL, ground[2] + (g - ground[2]) * BADGE_FILL,
            ground[3] + (bl - ground[3]) * BADGE_FILL, 1)
    end
    b.star:SetShown(badge.star == true)
    W.SetIconColor(b.star, { r, g, bl })
    font(b.text, BOLD, BADGE_SIZE)
    b.text:SetText(badge.text)
    paint(b.text, { r, g, bl })
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", BADGE_LEFT + (badge.star and STAR + STAR_GAP or 0), 0)
    b:SetWidth(BADGE_LEFT + (badge.star and STAR + STAR_GAP or 0) + textWidth(b.text) + BADGE_RIGHT)
end

-- Opens the list of who the raid summary counts: name, then their pick.
local function listRest(view, anchor)
    local items = {}
    for _, data in ipairs(view.rest or {}) do
        items[#items + 1] = { text = ("|c%s%s|r |c%s·|r |c%s%s|r"):format(ns.Color.Hex(Th.ClassColor(data.class)),
            data.name or "", Th.Hex("faint"), Th.Hex(PICKED[data.state] and data.state or "faint"), word(data.state)) }
    end
    if #items > 0 then W.Menu(anchor, items) end
end

local function newSummary(view, parent)
    local sum = CreateFrame("Button", nil, parent)
    sum:SetHeight(SUMMARY_H)
    sum:RegisterForClicks("LeftButtonUp")
    W.Hair(sum, "TOP", "hairSoft")
    sum.passIcon = W.Icon(sum, "pass", SUM_ICON, "pass")
    sum.passed = newText(sum, "pick")
    sum.seps = { newText(sum, "pick"), newText(sum, "pick") }
    for _, sep in ipairs(sum.seps) do sep:SetText("·") end
    sum.dots = newDots(sum, "muted")
    sum.choosing = newText(sum, "pick")
    sum.absent = newText(sum, "pick")
    sum.chevron = W.Icon(sum, "chevron", SUM_CHEVRON, "faint")
    sum.chevron:SetPoint("RIGHT", -ROW_PAD, 0)
    sum:SetScript("OnClick", function(self) listRest(view, self) end)
    sum:Hide()
    return sum
end

-- "13 passed · 2 choosing", leaving out a part whose count is 0 (and "<n> not in this roll" when there are any).
local function paintSummary(sum, rest)
    local passed, choosing, absent = 0, 0, 0
    for _, data in ipairs(rest) do
        if data.state == "pass" then
            passed = passed + 1
        elseif data.state == "wait" then
            choosing = choosing + 1
        else
            absent = absent + 1
        end
    end
    local list = {}
    local function add(...)
        for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
    end
    if passed > 0 then add(sum.passIcon, sum.passed) end
    if choosing > 0 then
        if #list > 0 then add(sum.seps[1]) end
        add(sum.dots, sum.choosing)
    end
    if absent > 0 then
        if #list > 0 then add(sum.seps[2]) end
        add(sum.absent)
    end
    for _, region in ipairs({ sum.passIcon, sum.passed, sum.seps[1], sum.dots, sum.choosing, sum.seps[2],
        sum.absent }) do region:Hide() end
    for _, fs in ipairs({ sum.passed, sum.seps[1], sum.seps[2], sum.choosing, sum.absent }) do
        font(fs, "pick")
        paint(fs, "muted")
    end
    for _, sep in ipairs(sum.seps) do paint(sep, "faint") end
    sum.passed:SetText(passed .. " passed")
    sum.choosing:SetText(choosing .. " " .. CHOOSING)
    sum.absent:SetText(absent .. " " .. ABSENT)
    for _, region in ipairs(list) do region:Show() end
    chain(list, sum, ROW_PAD, SUM_GAP)
end

-------------------------------------------------------------------------------
--  Drawing a card
-------------------------------------------------------------------------------
local View = {}
local pool = {}

-- The subtitle's left side as pieces { text, colour, bold }.
local function subtitlePieces(card, winner)
    local pieces = {}
    local function add(text, c, bold) pieces[#pieces + 1] = { text, c, bold } end
    if card.status == "live" then
        if card.label then add(card.label, "muted") end
        if card.ilvl then
            if card.label then add("·", "faint") end
            add("ilvl " .. card.ilvl, "muted")
        end
    elseif card.status == "decided" and winner then
        if winner.isPlayer then
            add(YOU_WON, "accent", true)
        else
            add(winner.name or "", classColor(winner.class), true)
            add(WON, "muted")
        end
        local how = howWon(winner)
        if how then
            add("·", "faint")
            add(how, "muted")
        end
    elseif card.status == "decided" and card.allPassed then
        add(EVERYONE_PASSED, "muted")
    else -- ended, or decided by a winner nobody can name (Recent rolls says the same)
        add(ROLL_ENDED, "muted")
    end
    return pieces
end

-- The countdown: the seconds on the right ("Your pick · 54s" while the card waits on the player) and the bar.
local function countdown(view, card)
    view.time:SetText((view.yours:IsShown() and "· " or "") .. seconds(card))
    local share = (card.duration or 0) > 0 and Rolls.TimeLeft(card) / card.duration or 0
    local width = view.track:GetWidth() * share
    view.bar:SetShown(view.track:IsShown() and width > 0)
    if width > 0 then view.bar:SetWidth(width) end
end

local function paintHead(view, card, winner, awaits)
    local live = card.status == "live"
    view.icon:SetItem(card.icon, card.quality)
    font(view.name, "item")
    view.name:SetText(card.name or "")
    paint(view.name, { Th.Quality(card.quality) })
    view.nameHit:SetWidth(max(min(textWidth(view.name), view.name:GetWidth()), 1))

    local pieces, shown = subtitlePieces(card, winner), {}
    for i, fs in ipairs(view.parts) do
        local piece = pieces[i]
        fs:SetShown(piece ~= nil)
        if piece then
            if piece[3] then font(fs, BOLD, SUB_SIZE) else font(fs, REGULAR) end
            fs:SetText(piece[1])
            paint(fs, piece[2])
            shown[#shown + 1] = fs
        end
    end
    local badge = live and ns.BiS.Badge(card.link) or nil
    view.badge:SetShown(badge ~= nil)
    if badge then
        paintBadge(view.badge, badge)
        shown[#shown + 1] = view.badge
    end
    chain(shown, view.line, 0, PIECE_GAP)

    view.yours:SetShown(awaits)
    font(view.yours, BOLD, SUB_SIZE)
    paint(view.yours, "accent")
    view.time:SetShown(live)
    font(view.time, REGULAR)
    paint(view.time, "dim")
    view.track:SetShown(live) -- a card that is over keeps the countdown's room, empty
    view.bar:SetShown(live)
    if live then countdown(view, card) end

    view.edge:SetShown(awaits)
    local r, g, b = Th.Accent()
    view.ring:SetVertexColor(r, g, b, 1)
    view.shine.tex:SetVertexColor(r, g, b, SHINE_ALPHA)
end

-- Whether a roll button takes a pick (the game's flags; Transmog shows only where the game offers it).
local function allowed(card, kind)
    if kind == "need" then return card.canNeed == true end
    if kind == "greed" then return card.canGreed == true end
    return true
end

-- Buttons, reason, rows and summary, from the top of the card down. -> the card's height
local function paintBody(view, card, rows, awaits)
    local over = card.status == "decided" or card.status == "ended"
    local y = PAD_TOP + ICON + TIMER_BLOCK
    -- A button that stays is never hidden on the way: hiding it would drop the hover and cancel a press, and
    -- with it the click that was coming.
    local kinds = awaits and { "need", card.canTransmog and "transmog" or "greed", "pass" } or {}
    local wanted = {}
    for _, kind in ipairs(kinds) do wanted[kind] = true end
    for kind, button in pairs(view.buttons) do
        if not wanted[kind] then button:Hide() end
    end
    view.reason:Hide()
    if awaits then
        local width = (view:GetWidth() - 2 * PAD_X - (#kinds - 1) * BUTTON_GAP) / #kinds
        for i, kind in ipairs(kinds) do
            local button = view.buttons[kind]
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", PAD_X + (i - 1) * (width + BUTTON_GAP), -(y + BUTTONS_GAP))
            button:SetWidth(width)
            button:SetAllowed(allowed(card, kind))
            button:Show()
        end
        y = y + BUTTONS_BLOCK
        if not card.canNeed then
            font(view.reason, "small")
            view.reason:SetText(NEED_REASON .. (card.reasonNeed or NO_REASON))
            paint(view.reason, "muted")
            view.reason:ClearAllPoints()
            view.reason:SetPoint("TOPLEFT", PAD_X, -(y + REASON_GAP))
            view.reason:SetPoint("TOPRIGHT", -PAD_X, -(y + REASON_GAP))
            view.reason:Show()
            y = y + REASON_BLOCK
        end
    end

    -- In a raid only who picks Need, Greed or Transmog, the winner and the player get a row.
    local shown, rest = rows, nil
    if ns.Group.IsRaid() then
        shown, rest = {}, {}
        for _, data in ipairs(rows) do
            local list = (data.isPlayer or data.isWinner or WINNING[data.state]) and shown or rest
            list[#list + 1] = data
        end
    end
    for i, data in ipairs(shown) do
        local row = view.rows[i]
        if not row then
            row = Card.NewRow(view.full)
            view.rows[i] = row
        end
        if row.data and row.data.guid ~= data.guid then stopRow(row) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD_X, -(y + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", -PAD_X, -(y + (i - 1) * ROW_H))
        row:Set(data, { decided = over, height = ROW_H })
        row:Show()
    end
    for i = #shown + 1, #view.rows do
        local row = view.rows[i]
        stopRow(row)
        row.data = nil
        row:Hide()
    end
    view.rowCount = #shown
    y = y + #shown * ROW_H

    view.rest = rest
    if rest and #rest > 0 then
        paintSummary(view.summary, rest)
        view.summary:ClearAllPoints()
        view.summary:SetPoint("TOPLEFT", PAD_X, -y)
        view.summary:SetPoint("TOPRIGHT", -PAD_X, -y)
        view.summary:Show()
        y = y + SUMMARY_H
    else
        view.summary:Hide()
    end
    return y + PAD_BOTTOM
end

-- The folded line: icon, name → winner on the left, "Need 19" on the right; the name gives way.
local function paintFold(view, card, winner)
    view.foldIcon:SetItem(card.icon, card.quality)
    font(view.foldName, BOLD, FOLD_SIZE)
    view.foldName:SetText(card.name or "")
    paint(view.foldName, { Th.Quality(card.quality) })
    local who, result
    if card.status == "live" then
        result = seconds(card)
    elseif card.status == "decided" and winner then
        who = winner.isPlayer and { YOU, "accent" } or { winner.name or "", classColor(winner.class) }
        result = howWon(winner) or ""
    elseif card.status == "decided" and card.allPassed then
        result = EVERYONE_PASSED
    else
        result = ROLL_ENDED
    end
    view.foldArrow:SetShown(who ~= nil)
    view.foldWinner:SetShown(who ~= nil)
    if who then
        font(view.foldWinner, BOLD, FOLD_SIZE)
        view.foldWinner:SetText(who[1])
        paint(view.foldWinner, who[2])
    end
    font(view.foldResult, "fold")
    view.foldResult:SetText(result)
    paint(view.foldResult, "muted")

    local room = view:GetWidth() - FOLD_NAME_X - PAD_X - FOLD_GAP - textWidth(view.foldResult)
    if who then room = room - 2 * FOLD_GAP - (ARROW - 2 * ARROW_SIDE) - textWidth(view.foldWinner) end
    local full = textWidth(view.foldName)
    view.foldName:SetWidth(full > room and max(room, 1) or 0)
    view.foldNameHit:SetWidth(max(min(full, room), 1))
end

-- The view as its card is now. `rows` may be given (Update has them already). Remembers what it shows.
local function render(view, rows)
    local card = view.card
    if not card then return end
    rows = rows or Rolls.Rows(card)
    local winner
    for _, data in ipairs(rows) do
        if data.isWinner then winner = data end
    end
    view.full:SetShown(not view.folded)
    view.fold:SetShown(view.folded)
    if view.folded then
        paintFold(view, card, winner)
        view.height = FOLD_H
    else
        local awaits = Rolls.AwaitsMe(card)
        paintHead(view, card, winner, awaits)
        view.height = paintBody(view, card, rows, awaits)
    end
    view:SetHeight(view.height)
    view.seen = {}
    for _, data in ipairs(rows) do view.seen[data.guid] = { state = data.state, roll = data.roll } end
end

local function stopEffects(view)
    for _, row in ipairs(view.rows) do stopRow(row) end
    Fx.Stop(view.ring)
    Fx.Stop(view.shine)
    Fx.Stop(view.fold)
end

-- The winner's moment: the wash sweeps in and the crown pops; the player's own win also glows and shines.
local function celebrate(view)
    for i = 1, view.rowCount do
        local row = view.rows[i]
        if row.data.isWinner then
            Fx.Wash(row.wash)
            Fx.Pop(row.crown)
            if row.data.isPlayer then
                Fx.Glow(view.ring, GLOWS)
                Fx.Shine(view.shine, view:GetWidth() * SHINE_SHARE)
            end
        end
    end
end

function View:Bind(card)
    if card ~= self.card then
        stopEffects(self)
        self.folded = false
    end
    self.card = type(card) == "table" and card or nil
    render(self)
end

function View:Update(changes)
    local card = self.card
    if not card then return end
    changes = type(changes) == "table" and changes or {}
    local rows, seen = Rolls.Rows(card), self.seen or {}
    render(self, rows)
    if self.folded then return end
    for i = 1, self.rowCount do
        local row = self.rows[i]
        local data = row.data
        local was = seen[data.guid] or {}
        if PICKED[data.state] and was.state ~= data.state then Fx.FadeIn(row.pick) end
        if data.roll ~= nil and was.roll ~= data.roll then Fx.Spin(row.roll, data.roll) end
    end
    if changes.decided and card.status == "decided" then celebrate(self) end
end

function View:Height() return self.height or 0 end

function View:SetFolded(folded)
    folded = folded == true
    if folded == (self.folded == true) then return end
    self.folded = folded
    stopEffects(self)
    render(self)
    if folded then Fx.FadeIn(self.fold) end
end

function View:Tick()
    local card = self.card
    if not card or card.status ~= "live" then return end
    if self.folded then
        self.foldResult:SetText(seconds(card))
    else
        countdown(self, card)
    end
end

-------------------------------------------------------------------------------
--  Building a view, and the pool
-------------------------------------------------------------------------------
local function newView()
    local view = CreateFrame("Frame")
    view:SetWidth(WIDTH)
    view.rows, view.rowCount, view.seen, view.height = {}, 0, {}, 0

    local full = CreateFrame("Frame", nil, view)
    full:SetAllPoints()
    view.full = full
    view.divider = W.Hair(full, "TOP", "hairSoft")
    view.edge = W.Fill(full, "accent", "ARTWORK")
    view.edge:SetPoint("TOPLEFT")
    view.edge:SetPoint("BOTTOMLEFT")
    view.edge:SetWidth(EDGE)

    -- The head: icon (with the ring that glows around it), name, and the subtitle line under it, both lines
    -- centred on the icon.
    view.icon = W.ItemIcon(full, ICON)
    view.icon:SetPoint("TOPLEFT", PAD_X, -PAD_TOP)
    view.ring = full:CreateTexture(nil, "BACKGROUND")
    view.ring:SetTexture(W.MEDIA .. "ring")
    view.ring:SetSize(RING, RING)
    view.ring:SetPoint("CENTER", view.icon, "CENTER")
    view.ring:Hide()
    local textX = PAD_X + ICON + ICON_GAP
    local textTop = PAD_TOP + (ICON - (NAME_H + SUB_GAP + SUB_H)) / 2
    view.name = newText(full, "item")
    view.name:SetPoint("TOPLEFT", textX, -textTop)
    view.name:SetPoint("TOPRIGHT", -PAD_X, -textTop)
    view.name:SetHeight(NAME_H)
    local line = CreateFrame("Frame", nil, full)
    line:SetPoint("TOPLEFT", textX, -(textTop + NAME_H + SUB_GAP))
    line:SetPoint("TOPRIGHT", -PAD_X, -(textTop + NAME_H + SUB_GAP))
    line:SetHeight(SUB_H)
    view.line = line
    view.parts = {}
    for i = 1, 4 do view.parts[i] = newText(line, REGULAR) end
    view.badge = newBadge(line)
    view.time = newText(line, REGULAR)
    view.time:SetJustifyH("RIGHT")
    view.time:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    view.yours = newText(line, BOLD, SUB_SIZE)
    view.yours:SetPoint("RIGHT", view.time, "LEFT", -YOURS_GAP, 0)
    view.yours:SetText(YOUR_PICK)
    view.iconHit = itemHit(view, view.icon)
    view.iconHit:SetAllPoints(view.icon)
    view.nameHit = itemHit(view, full)
    view.nameHit:SetPoint("TOPLEFT", view.name, "TOPLEFT")
    view.nameHit:SetHeight(NAME_H)

    -- The countdown: a 2 px bar in the accent on a faint track.
    view.track = W.Fill(full, TRACK, "ARTWORK")
    view.track:SetPoint("TOPLEFT", PAD_X, -(PAD_TOP + ICON + TIMER_GAP))
    view.track:SetPoint("TOPRIGHT", -PAD_X, -(PAD_TOP + ICON + TIMER_GAP))
    view.track:SetHeight(TIMER_H)
    view.bar = W.Fill(full, "accent", "ARTWORK", 1)
    view.bar:SetPoint("TOPLEFT", view.track, "TOPLEFT")
    view.bar:SetHeight(TIMER_H)

    view.buttons = {}
    for _, kind in ipairs({ "need", "greed", "transmog", "pass" }) do
        view.buttons[kind] = W.RollButton(full, kind, function(button)
            if view.card then Rolls.Pick(view.card, button.kind) end
        end)
        view.buttons[kind]:Hide()
    end
    view.reason = newText(full, "small")
    view.reason:SetHeight(REASON_H)
    view.reason:Hide()
    view.summary = newSummary(view, full)

    -- The shine slides across the card inside a frame that clips it.
    local clip = CreateFrame("Frame", nil, full)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)
    view.shine = CreateFrame("Frame", nil, clip)
    view.shine.tex = view.shine:CreateTexture(nil, "OVERLAY")
    view.shine.tex:SetTexture(W.MEDIA .. "shine")
    view.shine.tex:SetAllPoints()
    view.shine:Hide()

    -- Folded: one line.
    local fold = CreateFrame("Frame", nil, view)
    fold:SetAllPoints()
    fold:Hide()
    view.fold = fold
    view.foldIcon = W.ItemIcon(fold, FOLD_ICON)
    view.foldIcon:SetPoint("LEFT", PAD_X, 0)
    view.foldName = newText(fold, BOLD, FOLD_SIZE)
    view.foldName:SetPoint("LEFT", view.foldIcon, "RIGHT", FOLD_GAP, 0)
    view.foldArrow = W.Icon(fold, "down", ARROW, "faint") -- the down arrow, turned to point right
    view.foldArrow:SetRotation(math.pi / 2)
    view.foldArrow:SetPoint("LEFT", view.foldName, "RIGHT", FOLD_GAP - ARROW_SIDE, 0)
    view.foldWinner = newText(fold, BOLD, FOLD_SIZE)
    view.foldWinner:SetPoint("LEFT", view.foldArrow, "RIGHT", FOLD_GAP - ARROW_SIDE, 0)
    view.foldResult = newText(fold, "fold")
    view.foldResult:SetJustifyH("RIGHT")
    view.foldResult:SetPoint("RIGHT", -PAD_X, 0)
    view.foldIconHit = itemHit(view, view.foldIcon)
    view.foldIconHit:SetAllPoints(view.foldIcon)
    view.foldNameHit = itemHit(view, fold)
    view.foldNameHit:SetPoint("LEFT", view.foldName, "LEFT")
    view.foldNameHit:SetHeight(FOLD_H)

    for key, fn in pairs(View) do view[key] = fn end
    W.Paint(view, function(self) render(self) end) -- the looks changed: fonts and colours again
    return view
end

function Card.Acquire(parent)
    local view = table.remove(pool) or newView()
    view.pooled = nil
    view:SetParent(parent)
    view:ClearAllPoints()
    view:Show()
    return view
end

function Card.Release(view)
    if type(view) ~= "table" or view.pooled or view.Bind ~= View.Bind then return end
    stopEffects(view)
    for _, row in ipairs(view.rows) do
        row.data = nil
        row:Hide()
    end
    view.card, view.folded, view.seen, view.rest, view.rowCount, view.height = nil, false, {}, nil, 0, 0
    view:Hide()
    view:ClearAllPoints()
    view.pooled = true
    pool[#pool + 1] = view
end
