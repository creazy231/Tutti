-------------------------------------------------------------------------------
--  Tutti: Recent rolls, the window's view of the session's results (ns.History; the approved mockup's .sec, .hl,
--  .hx and .hint). One line per item, newest first, under a label for the place and the day ("STONEWATCH KEEP ·
--  TODAY"): the item's icon and name, who won and how ("Orlen · Need 19", "You · Need 87" in the accent), or
--  "Everyone passed" / "Roll ended", and the result's age on the right, after a muted "DEMO" on a result of
--  /tutti demo, so it never passes for a real roll; the icon shows a stack's count. A click opens everyone's pick
--  under the line (the card's own rows, 19 px high, 44 px in); a second click, or a click on another line, closes
--  it. A footer says how long the list is kept. While the view shows, it redraws when the history changes and its ages
--  every 10 seconds. A damaged saved list never stops it: what cannot be read shows as unknown (a time without an
--  age or a day, a place as "Unknown"), and a redraw that fails anyway is reported, not repeated every frame.
--    ns.Recent.view   the view's frame, once the window has built it (registered as "recent")
--  Labels follow each other in time: a place visited again after another starts a label of its own.
-------------------------------------------------------------------------------
local _, ns = ...
local Recent = {}
ns.Recent = Recent

local W, Th = ns.W, ns.Theme

-- Sizes in px: the mockup's CSS and the Global Constraints.
local WIDTH, PAD_X = 300, 10                                  -- the window; .sec, .hl and .hint padding
local SEC_H, SEC_FIRST_H, SEC_TEXT = 23, 22, 7 + 13.3 / 2      -- .sec: 1 + 7 + 13.3 + 2, without its hairline right
                                                               -- under the header's (.hd + .sec); its line's middle
local SEC_GAP = 8                                              -- the line after the label
local LINE_H = 38                                              -- .hl: 5 + 15 + 13 + 5, as the mockup measures (R40)
local ICON, ICON_GAP, COUNT = 26, 8, 10                       -- .hl .ico, .hl gap; the stack count's bold 10
local TEXT_X = PAD_X + ICON + ICON_GAP                         -- 44
local NAME_H, WHO_H, AGE_H = 15, 13, 14.7                      -- .hl .in, .hl .hw, .hl time line heights
local TEXT_TOP = (LINE_H - NAME_H - WHO_H) / 2                 -- the two lines centred on the line
local NAME_MIDDLE = TEXT_TOP + NAME_H / 2
local WHO_MIDDLE = TEXT_TOP + NAME_H + WHO_H / 2
local AGE_MIDDLE = TEXT_TOP + 1 + AGE_H / 2                    -- time: at the top of the text, 1 px down
local WHO_GAP, AGE_GAP = 4, 8                                  -- .hw gap; the .hl gap before the age
local WHO_SIZE = 11                                            -- .hw: the winner's name is bold 11
local PICKS_TOP, PICKS_BOTTOM, PICKS_X, ROW_H = 2, 6, 44, 19  -- .hx padding, its rows (.hx .pr)
local LIST_BOTTOM = 4                                          -- .hist padding-bottom
local HINT_H, HINT_TEXT = 29, 1 + 5 + 14.7 / 2                 -- .hint: its hairline, 5 + 14.7 + 8; its middle
local EMPTY_H, EMPTY_TEXT = 28, 5 + 14.7 / 2                   -- no results: a line in the .hint look

local AGES_EVERY = 10 -- seconds between redraws of the ages
local DAY = 86400
local LAST_TIME = 2 ^ 32 -- a time() past this (the year 2106) is a damaged one

-- Words. A pick's is the game's where it has one, else English; Transmog is always the short word (R27).
local WORDS = { need = { "NEED", "Need" }, greed = { "GREED", "Greed" }, transmog = { false, "Transmog" } }
local YOU, EVERYONE_PASSED, ROLL_ENDED = "You", "Everyone passed", "Roll ended"
local TODAY, YESTERDAY, SOMEWHERE = "today", "yesterday", "Unknown"
local FOOTER = "Kept for this session · /tutti opens this list"
local EMPTY = "No rolls yet"
local DEMO = "DEMO" -- the tag of a result of /tutti demo, as the section labels write their words

-------------------------------------------------------------------------------
--  What a result says
-------------------------------------------------------------------------------
-- The results are Tutti's own saved data: read with the guards all the same, as a damaged list may hold anything.
local function rowsOf(entry) return type(entry.rows) == "table" and entry.rows or {} end

-- "Need 87": the winner's pick and number; nil for a pick that cannot win (an unreadable one).
local function howWon(winner)
    local word = WORDS[winner.state]
    if not word then return nil end
    word = ns.Text(word[1] and _G[word[1]]) or word[2]
    local roll = ns.Clear(winner.roll, "number")
    return roll and (word .. " " .. roll) or word
end

-- Did the player win? The winner's row says so (the winner's record has no flag of its own).
local function playerWon(entry)
    for _, data in ipairs(rowsOf(entry)) do
        if type(data) == "table" and data.isWinner == true then return data.isPlayer == true end
    end
    return false
end

-- A row as the card's painter takes it: only what the saved list holds in the clear and of the right kind.
local function cleanRow(data)
    return {
        guid = ns.Text(data.guid), name = ns.Text(data.name), class = ns.Text(data.class), state = ns.Text(data.state),
        roll = ns.Clear(data.roll, "number"), isPlayer = data.isPlayer == true, isWinner = data.isWinner == true,
    }
end

-- A time the clock can read: a whole date, not a damaged number.
local function readable(at)
    at = ns.Clear(at, "number")
    return at ~= nil and at == at and at >= 0 and at < LAST_TIME
end

local function ageOf(entry, now)
    return readable(entry.at) and ns.History.Age(entry, now) or ""
end

local function itemName(entry)
    local link = ns.Text(entry.link)
    return ns.Text(entry.name) or (link and link:match("|h%[(.-)%]|h")) or ""
end

-- "today", "yesterday", else the date ("12 Nov"), by the clock's own days; today for a time it cannot read.
local function dayOf(at, now)
    if not readable(at) then return TODAY end
    local day = date("%Y-%m-%d", at) or ""
    if day == (date("%Y-%m-%d", now) or "") then return TODAY end
    if day == (date("%Y-%m-%d", now - DAY) or "") then return YESTERDAY end
    return ((date("%d %b", at) or ""):gsub("^0", ""))
end

-------------------------------------------------------------------------------
--  Parts
-------------------------------------------------------------------------------
-- A place's label (.sec): the words in capitals (the client has no letter spacing), a line after them to the right.
local function newSection(view)
    local sec = CreateFrame("Frame", nil, view)
    sec.hair = W.Hair(sec, "TOP", "hairSoft")
    sec.label = W.Text(sec, "section", "muted")
    sec.rule = sec:CreateTexture(nil, "BORDER")
    W.Paint(sec.rule, function(t)
        t:SetColorTexture(Th.Color("hairSoft"))
        t:SetHeight(W.Pixel(sec))
    end)
    view.sections[#view.sections + 1] = sec
    return sec
end

local function placeSection(view, sec, first, words, y)
    local h, middle = first and SEC_FIRST_H or SEC_H, (first and 0 or 1) + SEC_TEXT
    sec:ClearAllPoints()
    sec:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
    sec:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -y)
    sec:SetHeight(h)
    sec.hair:SetShown(not first)
    W.SetRole(sec.label, "section")
    sec.label:SetWidth(0)
    sec.label:SetText(words:upper())
    local room = WIDTH - 2 * PAD_X - SEC_GAP -- a label too long is cut where the line would start
    if sec.label:GetUnboundedStringWidth() > room then sec.label:SetWidth(room) end
    sec.label:ClearAllPoints()
    sec.label:SetPoint("LEFT", sec, "TOPLEFT", PAD_X, -middle)
    sec.rule:ClearAllPoints()
    sec.rule:SetPoint("LEFT", sec.label, "RIGHT", SEC_GAP, 0)
    sec.rule:SetPoint("RIGHT", sec, "TOPRIGHT", -PAD_X, -middle)
    sec:Show()
    return h
end

local toggle -- below: opens or closes a line's picks

-- A line (.hl): hover and selected grounds, the icon, the name over who won, the age on the right.
local function newLine(view)
    local line = CreateFrame("Button", nil, view)
    line:SetHeight(LINE_H)
    line:RegisterForClicks("LeftButtonUp")
    line.hover = W.Fill(line, "hover")
    line.hover:SetAllPoints()
    line.hover:Hide()
    line.selected = W.Fill(line, "selected")
    line.selected:SetAllPoints()
    line.selected:Hide()
    line.icon = W.ItemIcon(line, ICON, COUNT)
    line.icon:SetPoint("LEFT", PAD_X, 0)
    line.age = W.Text(line, "small", "faint")
    line.age:SetJustifyH("RIGHT")
    line.age:SetPoint("RIGHT", line, "TOPRIGHT", -PAD_X, -AGE_MIDDLE)
    -- A demo's result: "DEMO" before the age, in the section labels' small muted capitals.
    line.demo = W.Text(line, "section", "muted")
    line.demo:SetText(DEMO)
    line.demo:SetPoint("RIGHT", line.age, "LEFT", -AGE_GAP, 0)
    line.demo:Hide()
    line.name = W.Text(line, "row")
    line.who = W.Text(line, "item", "text", nil, WHO_SIZE)
    line.who:SetPoint("LEFT", line, "TOPLEFT", TEXT_X, -WHO_MIDDLE)
    line.dot = W.Text(line, "sub", "faint")
    line.dot:SetText("·")
    line.dot:SetPoint("LEFT", line.who, "RIGHT", WHO_GAP, 0)
    line.how = W.Text(line, "sub", "muted")
    line:SetScript("OnEnter", function(self) if not self.selected:IsShown() then self.hover:Show() end end)
    line:SetScript("OnLeave", function(self) self.hover:Hide() end)
    line:SetScript("OnClick", function(self) toggle(view, self.entry) end)
    view.lines[#view.lines + 1] = line
    return line
end

local function paintLine(line, entry, now, open)
    line.entry = entry
    line.icon:SetItem(entry.icon, entry.quality, entry.count)
    -- The name runs to 8 px before the age (or the demo's tag), cut there; its right end is moved to its own middle.
    local demo = entry.demo == true
    line.demo:SetShown(demo)
    line.name:ClearAllPoints()
    line.name:SetPoint("LEFT", line, "TOPLEFT", TEXT_X, -NAME_MIDDLE)
    line.name:SetPoint("RIGHT", demo and line.demo or line.age, "LEFT", -AGE_GAP, AGE_MIDDLE - NAME_MIDDLE)
    line.name:SetText(itemName(entry))
    W.SetTextColor(line.name, { Th.Quality(ns.Clear(entry.quality, "number")) })
    line.age:SetText(ageOf(entry, now))

    -- Who won: "<First>" in the class colour or "You" in the accent, "·", "Need 87"; else what happened instead.
    local winner = type(entry.winner) == "table" and entry.winner or nil
    local how = winner and howWon(winner)
    line.who:SetShown(winner ~= nil)
    line.dot:SetShown(how ~= nil)
    line.how:ClearAllPoints()
    if winner then
        local mine = playerWon(entry)
        line.who:SetText(mine and YOU or ns.Text(winner.name) or "")
        W.SetTextColor(line.who, mine and "accent" or { Th.ClassColor(ns.Text(winner.class)) })
        line.how:SetPoint("LEFT", line.dot, "RIGHT", WHO_GAP, 0)
    else
        how = entry.allPassed == true and EVERYONE_PASSED or ROLL_ENDED
        line.how:SetPoint("LEFT", line, "TOPLEFT", TEXT_X, -WHO_MIDDLE)
    end
    line.how:SetShown(how ~= nil)
    if how then line.how:SetText(how) end

    line.selected:SetShown(open)
    if open then line.hover:Hide() end
end

-- Everyone's pick under the open line (.hx): the card's rows, drawn as the mockup draws them there (R44): decided,
-- the winner washed and crowned and a loser's number muted, but not faded back as a decided card's rows are: each
-- row dims by its pick (a pass at 55 %). -> its height
local function placePicks(view, entry, y)
    local picks = view.picks
    picks:ClearAllPoints()
    picks:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
    picks:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -y)
    picks:Show()
    local n = 0
    for _, data in ipairs(rowsOf(entry)) do
        if type(data) == "table" then
            n = n + 1
            local row = picks.rows[n]
            if not row then
                row = ns.Card.NewRow(picks)
                picks.rows[n] = row
            end
            local top = PICKS_TOP + (n - 1) * ROW_H
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", picks, "TOPLEFT", PICKS_X, -top)
            row:SetPoint("TOPRIGHT", picks, "TOPRIGHT", -PAD_X, -top)
            row:Show() -- before Set: a row the game has hidden has no width to fit a name to
            row:Set(cleanRow(data), { decided = true, fade = false, height = ROW_H })
        end
    end
    for i = n + 1, #picks.rows do picks.rows[i]:Hide() end
    local h = PICKS_TOP + n * ROW_H + PICKS_BOTTOM
    picks:SetHeight(h)
    return h
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
-- The whole list from the history as it is now. Remembers its height and when it drew (first: a draw that fails
-- is not tried again before the next tick).
local function draw(view)
    view.drawnAt = GetTime()
    local now = time()
    local y, sections, lines, open, label = 0, 0, 0, false, nil
    for _, entry in ipairs(ns.History.Entries()) do
        local words = (ns.Text(entry.place) or SOMEWHERE) .. " · " .. dayOf(entry.at, now)
        if words ~= label then
            label = words
            sections = sections + 1
            local sec = view.sections[sections] or newSection(view)
            y = y + placeSection(view, sec, sections == 1, words, y)
        end
        lines = lines + 1
        local line = view.lines[lines] or newLine(view)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
        line:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -y)
        line:Show()
        local isOpen = entry == view.openEntry
        paintLine(line, entry, now, isOpen)
        y = y + LINE_H
        if isOpen then
            open = true
            y = y + placePicks(view, entry, y)
        end
    end
    for i = sections + 1, #view.sections do view.sections[i]:Hide() end
    for i = lines + 1, #view.lines do
        view.lines[i]:Hide()
        view.lines[i].entry = nil
    end
    if not open then
        view.openEntry = nil -- its result is gone (a new session)
        view.picks:Hide()
    end
    view.empty:SetShown(lines == 0)
    y = lines == 0 and EMPTY_H or y + LIST_BOTTOM
    view.footer:ClearAllPoints()
    view.footer:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
    view.footer:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -y)
    view.height = y + HINT_H
    view:SetHeight(view.height)
end

-- Draws the list again and has the window fit it.
local function redraw(view)
    draw(view)
    ns.UI.Relayout()
end

-- A click on a line opens its picks (when it has any), on the open line closes them.
function toggle(view, entry)
    if not entry then return end
    if view.openEntry == entry then
        view.openEntry = nil
    elseif #rowsOf(entry) > 0 then
        view.openEntry = entry
    else
        return
    end
    redraw(view)
end

local function build(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetWidth(WIDTH)
    view.sections, view.lines, view.height = {}, {}, 0

    view.picks = CreateFrame("Frame", nil, view)
    view.picks.ground = W.Fill(view.picks, "selected")
    view.picks.ground:SetAllPoints()
    view.picks.rows = {}
    view.picks:Hide()

    view.empty = W.Text(view, "small", "faint")
    view.empty:SetPoint("LEFT", view, "TOPLEFT", PAD_X, -EMPTY_TEXT)
    view.empty:SetText(EMPTY)

    view.footer = CreateFrame("Frame", nil, view)
    view.footer:SetHeight(HINT_H)
    view.footer.hair = W.Hair(view.footer, "TOP", "hairSoft")
    view.footer.label = W.Text(view.footer, "small", "faint")
    view.footer.label:SetPoint("LEFT", view.footer, "TOPLEFT", PAD_X, -HINT_TEXT)
    view.footer.label:SetText(FOOTER)

    function view:Refresh() draw(self) end
    function view:Height() return self.height end
    -- The ages move on while the list shows (a hidden view gets no OnUpdate).
    view:SetScript("OnUpdate", function(self)
        if GetTime() - (self.drawnAt or 0) >= AGES_EVERY then ns.Safe(redraw, self) end
    end)
    -- The looks changed: the fonts, and with them the labels' room. Protected: the other painters go on.
    W.Paint(view, function(self) ns.Safe(draw, self) end)
    Recent.view = view
    return view
end

ns.UI.RegisterView("recent", build)

-- A result came in, or one was updated or cleared: the list shows it at once.
ns.Listen("HISTORY_CHANGED", function()
    local view = Recent.view
    if view and view:IsVisible() then redraw(view) end
end)
