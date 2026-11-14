-------------------------------------------------------------------------------
--  Tutti: Settings, the window's view of the five settings (the approved mockup's .settings, .sh and .row; Sotto's
--  settings view, cut to Tutti's). Three headings, each over its rows; a row is its label (and a line about it) on
--  the left and its control on the right, centred on each other, a faint line under every row but the last.
--  Changes apply at once.
--    WHEN LOOT DROPS   Roll in Tutti (a switch; once Blizzard's popups went off this session and the setting is
--                      off again, "Blizzard's popups return after a reload" and a Reload button), Close after the
--                      last roll (5, 10, 20, 30 seconds or never)
--    WHEN YOU WIN      Sound (Soft chime, played when it is chosen, or None)
--    LOOK              Accent (only with EllesmereUI: without it the class colour is the only accent), Size (80 to
--                      130 % in steps of 5; a dragged knob applies when it is let go, as the window grows under it)
--    ns.Settings.view  the view's frame, once the window has built it (registered as "settings")
-------------------------------------------------------------------------------
local _, ns = ...
local Settings = {}
ns.Settings = Settings

local W = ns.W
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

-- Sizes in px: the mockup's CSS.
local WIDTH, PAD_X, PAD_TOP, PAD_BOTTOM = 300, 10, 2, 10   -- .settings padding 2 / 10 / 10
local HEAD_ABOVE, HEAD_H, HEAD_BELOW = 10, 13, 2          -- .sh: 10 px above its 13.3 px line, 2 below
local ROW_PAD, GAP = 6, 10                                -- .row padding and gap
local LABEL_H, LABEL_SIZE, DESC_GAP = 15, 12.5, 1         -- .rl b: regular 12.5 on a 15 px line; .rl small 1 px under
local RELOAD_H, RELOAD_PAD = 20, 9                        -- the Reload button: Sotto's in-line action

local SIZE_MIN, SIZE_MAX, SIZE_STEP = 80, 130, 5          -- the size, in percent
local CHIME = W.MEDIA .. "Sounds\\chime.ogg"

-- Words.
local ROLL_LINE = "Need, Greed and Pass on each card; Blizzard's roll popups stay hidden"
local RELOAD_LINE, RELOAD = "Blizzard's popups return after a reload", "Reload"
local CLOSE_AFTER = {
    { value = 5, text = "5 seconds" }, { value = 10, text = "10 seconds" }, { value = 20, text = "20 seconds" },
    { value = 30, text = "30 seconds" }, { value = 0, text = "Never" },
}
local SOUNDS = { { value = "chime", text = "Soft chime" }, { value = "none", text = "None" } }
local ACCENTS = { { value = "class", text = "Class colour" }, { value = "eui", text = "EllesmereUI" } }

-------------------------------------------------------------------------------
--  Settings and actions
-------------------------------------------------------------------------------
local function getter(key) return function() return ns.Get(key) end end

local function setter(key, after)
    return function(value)
        ns.Set(key, value)
        if after then after(value) end
    end
end

-- The chime, to hear what was chosen.
local function preview(sound)
    if sound == "chime" then PlaySoundFile(CHIME, "Master") end
end

-- EllesmereUI as the theme reads it: its skin API is there.
local function hasEllesmereUI()
    local eui = ns.Clear(EllesmereUI, "table")
    return eui ~= nil and ns.Clear(eui.RegisterSkin, "function") ~= nil
end

local function reload()
    local ui = ns.Clear(C_UI, "table")
    local fn = (ui and ns.Clear(ui.Reload, "function")) or ns.Clear(ReloadUI, "function")
    if fn then fn() end
end

-- The size setting in percent, as the slider has it: in steps of 5, from 80 to 130.
local function sizeNow()
    local scale = ns.Clear(ns.Get("scale"), "number")
    if not scale or scale ~= scale then scale = 1 end
    local percent = floor(scale * 100 / SIZE_STEP + 0.5) * SIZE_STEP
    return max(SIZE_MIN, min(SIZE_MAX, percent))
end

-- The size slider. Dragging the knob would rescale the window, and the slider in it, under the cursor, and the
-- size would chase itself; so a size picked with the mouse held is kept, shown on the slider, and applied when the
-- mouse lets go (or the slider hides). The wheel applies at once.
local function sizeSlider(parent)
    local holding, held = false, nil
    local slider = W.Slider(parent, SIZE_MIN, SIZE_MAX, SIZE_STEP,
        function() return held or sizeNow() end,
        function(percent)
            if holding then held = percent else ns.Set("scale", percent / 100) end
        end,
        function(percent) return percent .. "%" end)
    local down, up = slider:GetScript("OnMouseDown"), slider:GetScript("OnMouseUp")
    local function letGo(self)
        up(self)
        holding = false
        local percent = held
        held = nil
        if percent then ns.Set("scale", percent / 100) end
        self:Refresh()
    end
    slider:SetScript("OnMouseDown", function(self, ...)
        holding = true
        down(self, ...)
    end)
    slider:SetScript("OnMouseUp", letGo)
    slider:SetScript("OnHide", function(self) if holding then letGo(self) end end)
    return slider
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function heading(view, words)
    local h = CreateFrame("Frame", nil, view)
    h.kind = "heading"
    h:SetHeight(HEAD_H)
    h.label = W.Text(h, "section", "muted")
    h.label:SetPoint("LEFT")
    h.label:SetText(words)
    view.heads[#view.heads + 1] = h
    view.items[#view.items + 1] = h
end

-- A row with its label and, given `desc`, the line under it; its control comes next (row.control).
local function newRow(view, label, desc)
    local r = CreateFrame("Frame", nil, view)
    r.kind = "row"
    r.label = W.Text(r, "sub", "text", nil, LABEL_SIZE)
    r.label:SetHeight(LABEL_H)
    r.label:SetText(label)
    if desc then
        r.desc = W.Text(r, "small", "muted")
        r.desc:SetWordWrap(true)
        r.desc:SetText(desc)
    end
    r.hair = W.Hair(r, "BOTTOM", "hairSoft")
    view.items[#view.items + 1] = r
    return r
end

-- The Reload button: the accent's wash and outline, "Reload" in the accent.
local function reloadButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b.ground = W.Fill(b, "accentWash")
    b.ground:SetAllPoints()
    W.Border(b, "accentBorder")
    b.text = W.Text(b, "small", "accent")
    b.text:SetPoint("CENTER")
    b.text:SetText(RELOAD)
    b:SetSize(ceil(b.text:GetStringWidth()) + 2 * RELOAD_PAD, RELOAD_H)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", reload)
    b:Hide()
    return b
end

-- One row at `y`: the controls on the right (the row's own control last), GAP apart, the text in the room left of
-- them, both centred in the row. -> its height
local function placeRow(view, r, y, last)
    local controls, width, height = { r.control }, 0, 0
    if r.reload and r.reload:IsShown() then controls[2] = r.reload end
    for i, c in ipairs(controls) do
        width = width + c:GetWidth() + (i > 1 and GAP or 0)
        height = max(height, c:GetHeight())
    end
    local column = WIDTH - 2 * PAD_X - width - GAP
    r.label:SetWidth(column)
    local text = LABEL_H
    if r.desc then
        W.SetRole(r.desc, "small") -- the font as it is now: the line's height follows from it
        r.desc:SetWidth(column)
        text = text + DESC_GAP + r.desc:GetStringHeight()
    end
    local content = max(text, height)
    local h = ROW_PAD + content + ROW_PAD + (last and 0 or 1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", view, "TOPLEFT", PAD_X, -y)
    r:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PAD_X, -y)
    r:SetHeight(h)
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(ROW_PAD + (content - text) / 2))
    if r.desc then
        r.desc:ClearAllPoints()
        r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -DESC_GAP)
    end
    local x = 0
    for _, c in ipairs(controls) do
        c:ClearAllPoints()
        c:SetPoint("RIGHT", r, "TOPRIGHT", -x, -(ROW_PAD + content / 2))
        x = x + c:GetWidth() + GAP
    end
    r.hair:SetShown(not last)
    r:Show()
    return h
end

-- Headings and rows from the top; a row that is not wanted (Accent without EllesmereUI) is left out.
local function layout(view)
    local last
    for _, item in ipairs(view.items) do
        if item.kind == "row" and item.wanted ~= false then last = item end
    end
    local y = PAD_TOP
    for _, item in ipairs(view.items) do
        if item.kind == "heading" then
            y = y + HEAD_ABOVE
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", view, "TOPLEFT", PAD_X, -y)
            item:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PAD_X, -y)
            y = y + HEAD_H + HEAD_BELOW
        elseif item.wanted == false then
            item:Hide()
        else
            y = y + placeRow(view, item, y, item == last)
        end
    end
    view.height = y + PAD_BOTTOM
    view:SetHeight(view.height)
end

-- Every control from the settings, the reload hint, the rows that are wanted, and the layout.
local function refresh(view)
    for _, r in ipairs({ view.roll, view.closeAfter, view.sound, view.accent, view.size }) do r.control:Refresh() end
    local reloadNeeded = ns.Popups.ReloadNeeded() == true
    view.roll.desc:SetText(reloadNeeded and RELOAD_LINE or ROLL_LINE)
    view.roll.reload:SetShown(reloadNeeded)
    view.accent.wanted = hasEllesmereUI()
    layout(view)
end

local function build(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetWidth(WIDTH)
    view.heads, view.items, view.height = {}, {}, 0

    heading(view, "WHEN LOOT DROPS")
    view.roll = newRow(view, "Roll in Tutti", ROLL_LINE)
    view.roll.control = W.Switch(view.roll, getter("rollInTutti"), setter("rollInTutti"))
    view.roll.reload = reloadButton(view.roll)
    view.closeAfter = newRow(view, "Close after the last roll")
    view.closeAfter.control = W.Dropdown(view.closeAfter, CLOSE_AFTER, getter("closeAfter"), setter("closeAfter"))

    heading(view, "WHEN YOU WIN")
    view.sound = newRow(view, "Sound")
    view.sound.control = W.Dropdown(view.sound, SOUNDS, getter("sound"), setter("sound", preview))

    heading(view, "LOOK")
    view.accent = newRow(view, "Accent")
    view.accent.control = W.Segmented(view.accent, ACCENTS, getter("accent"), setter("accent"))
    view.size = newRow(view, "Size")
    view.size.control = sizeSlider(view.size)

    function view:Refresh() refresh(self) end
    function view:Height() return self.height end
    -- The looks changed: the fonts, and with them how the lines wrap; the window fits the rows again (not while it
    -- is building the view: it fits it itself).
    W.Paint(view, function(self)
        layout(self)
        if self.built and self:IsVisible() then ns.UI.Relayout() end
    end)
    view.built = true
    Settings.view = view
    return view
end

ns.UI.RegisterView("settings", build)

-- A setting changed (here or elsewhere), or the popups did: the rows say so at once.
local function update()
    local view = Settings.view
    if not view then return end
    refresh(view)
    if view:IsVisible() then ns.UI.Relayout() end
end
ns.Listen("SETTING_CHANGED", update)
ns.Listen("POPUPS_CHANGED", update)
