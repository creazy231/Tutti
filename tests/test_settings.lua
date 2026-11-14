local T = T

local CHIME = "Interface\\AddOns\\Tutti\\Media\\Sounds\\chime.ogg"
local ROLL_LINE = "Need, Greed and Pass on each card; Blizzard's roll popups stay hidden"
local RELOAD_LINE = "Blizzard's popups return after a reload"

-- A client after login (with EllesmereUI unless opts.eui is false) and Settings open. -> G, W, ns, TuttiFrame, view
local function setup(opts)
    opts = opts or {}
    if opts.eui == nil then opts.eui = true end
    if opts.eui == false then opts.eui = nil end
    local G, W, ns = T.load(opts)
    T.eq(ns.UI.Open("settings"), true, "Settings opens")
    W.advance(0.35)
    return G, W, ns, G.TuttiFrame, ns.Settings.view
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

local function middle(W, win, region)
    local _, y, _, h = box(W, win, region)
    return y + h / 2
end

local function same(c, expected, msg)
    T.near(c[1], expected[1], 1e-6, (msg or "colour") .. " red")
    T.near(c[2], expected[2], 1e-6, (msg or "colour") .. " green")
    T.near(c[3], expected[3], 1e-6, (msg or "colour") .. " blue")
end

-- The menu a dropdown opens, as the texts of its rows.
local function menuOf(ns, dropdown)
    dropdown:Click()
    local menu = ns.W.CurrentMenu()
    local out = {}
    for _, r in ipairs(menu.rows) do
        if r:IsShown() then out[#out + 1] = r.label:GetText() end
    end
    return menu, out
end

-- How high a row is: 6 px, its text or its control (the taller, centred), 6 px, and its hairline unless last.
local function rowHeight(r, control, last)
    local textBlock = 15
    if r.desc and r.desc:IsShown() then textBlock = textBlock + 1 + r.desc:GetStringHeight() end
    return 6 + math.max(textBlock, control) + 6 + (last and 0 or 1)
end

-------------------------------------------------------------------------------
--  The rows
-------------------------------------------------------------------------------
T.it("the five rows", function()
    local G, W, ns, win, view = setup()
    T.eq(text(W, view.heads[1].label), "WHEN LOOT DROPS")
    T.eq(text(W, view.heads[2].label), "WHEN YOU WIN")
    T.eq(text(W, view.heads[3].label), "LOOK")
    T.eq(text(W, view.roll.label), "Roll in Tutti")
    T.eq(text(W, view.roll.desc), ROLL_LINE)
    T.ok(view.roll.control.knob, "a switch")
    T.no(view.roll.reload:IsShown(), "nothing to reload")
    T.eq(text(W, view.closeAfter.label), "Close after the last roll")
    T.eq(text(W, view.closeAfter.control.label), "10 seconds")
    T.eq(text(W, view.sound.label), "Sound")
    T.eq(text(W, view.sound.control.label), "Soft chime")
    T.eq(text(W, view.accent.label), "Accent")
    local seg = view.accent.control
    T.eq(text(W, seg.buttons[1].text), "Class colour")
    T.eq(text(W, seg.buttons[2].text), "EllesmereUI")
    T.ok(seg.buttons[1].selected, "the class colour is the setting")
    T.eq(text(W, view.size.label), "Size")
    T.eq(text(W, view.size.control.value), "100%")

    -- The mockup's .settings (padding 2 / 10 / 10), .sh (10 px above, 13 high, 2 below) and .row (6 px padding,
    -- the control 10 px after the text, a hairline under every row but the last).
    local x, y, w = box(W, win, view.heads[1])
    T.eq(x, 10)
    T.eq(y, 32 + 2 + 10)
    T.eq(w, 280)
    T.eq(select(2, view.heads[1].label:GetFont()), 9.5)
    same({ view.heads[1].label:GetTextColor() }, { ns.Theme.Color("muted") })
    local order = {
        { view.roll, 14 }, { view.closeAfter, 22 }, "head", { view.sound, 22 }, "head", { view.accent, 21 },
        { view.size, 16, true },
    }
    local top, heads = 32 + 2 + 10 + 13 + 2, 1
    for _, item in ipairs(order) do
        if item == "head" then
            heads = heads + 1
            _, y = box(W, win, view.heads[heads])
            T.eq(y, top + 10, "a heading 10 px under the row before")
            top = top + 10 + 13 + 2
        else
            local r, control, last = item[1], item[2], item[3]
            local rx, ry, rw, rh = box(W, win, r)
            T.eq(rx, 10, text(W, r.label))
            T.eq(ry, top, text(W, r.label))
            T.eq(rw, 280)
            T.eq(rh, rowHeight(r, control, last), text(W, r.label) .. ": its height")
            T.eq(r.hair:IsShown(), not last, "a hairline under every row but the last")
            T.eq(box(W, win, r.label), 10)
            T.eq(select(2, r.label:GetFont()), 12.5)
            same({ r.label:GetTextColor() }, { ns.Theme.Color("text") })
            local cx, _, cw = box(W, win, r.control)
            T.eq(cx + cw, 290, "the control on the right")
            T.near(middle(W, win, r.control), ry + 6 + (rh - 12 - (last and 0 or 1)) / 2, 1e-6, "centred")
            top = top + rh
        end
    end
    T.eq(view:Height(), top + 10 - 32, "10 px under the last row")
    T.eq(win:GetHeight(), 32 + view:Height())
    T.eq(select(2, view.roll.desc:GetFont()), 10.5)
    same({ view.roll.desc:GetTextColor() }, { ns.Theme.Color("muted") })
    local _, labelTop = box(W, win, view.roll.label)
    local _, descTop = box(W, win, view.roll.desc)
    T.eq(descTop, labelTop + 15 + 1, "the line 1 px under the label's 15 px")
    local cx = box(W, win, view.roll.control)
    local _, _, dw = box(W, win, view.roll.desc)
    T.eq(dw, cx - 10 - 10, "the text column stops 10 px before the control")
end)

T.it("Roll in Tutti off shows the reload hint and button", function()
    local G, W, ns, win, view = setup()
    T.ok(ns.Popups.Suppressed(), "the popups went off at load")
    local height = win:GetHeight()
    view.roll.control:Click()
    T.eq(ns.Get("rollInTutti"), false)
    T.ok(ns.Popups.ReloadNeeded())
    T.eq(text(W, view.roll.desc), RELOAD_LINE)
    local reload = view.roll.reload
    T.ok(reload:IsShown(), "a Reload button")
    T.eq(text(W, reload.text), "Reload")
    local rx, _, rw = box(W, win, reload)
    local sx = box(W, win, view.roll.control)
    T.eq(rx + rw + 10, sx, "10 px before the switch")
    local _, _, dw = box(W, win, view.roll.desc)
    T.eq(dw, rx - 10 - 10, "the line makes room for it")
    T.eq(win:GetHeight(), 32 + view:Height(), "the window follows the row")

    local calls = 0
    G.C_UI = { Reload = function() calls = calls + 1 end }
    reload:Click()
    T.eq(calls, 1, "C_UI.Reload where the game has it")
    T.eq(W.reloads, 0)
    G.C_UI = nil
    reload:Click()
    T.eq(W.reloads, 1, "else ReloadUI")

    view.roll.control:Click()
    T.eq(ns.Get("rollInTutti"), true)
    T.eq(text(W, view.roll.desc), ROLL_LINE, "back on: the popups stay off, nothing to reload")
    T.no(reload:IsShown())
    T.eq(win:GetHeight(), height)
end)

T.it("close-after choices", function()
    local G, W, ns, win, view = setup()
    local dropdown = view.closeAfter.control
    local menu, items = menuOf(ns, dropdown)
    T.eq(table.concat(items, ", "), "5 seconds, 10 seconds, 20 seconds, 30 seconds, Never")
    T.ok(menu.rows[2].check:IsShown(), "10 seconds is the setting")
    menu.rows[5]:Click()
    T.eq(ns.Get("closeAfter"), 0, "Never")
    T.eq(text(W, dropdown.label), "Never")
    for i, seconds in ipairs({ 5, 10, 20, 30 }) do
        menu = menuOf(ns, dropdown)
        menu.rows[i]:Click()
        T.eq(ns.Get("closeAfter"), seconds)
        T.eq(text(W, dropdown.label), seconds .. " seconds")
    end
end)

T.it("the size slider sets scale", function()
    local G, W, ns, win, view = setup()
    local slider = view.size.control
    slider:SetTo(110)
    T.near(ns.Get("scale"), 1.1, 1e-9)
    T.eq(text(W, slider.value), "110%")
    T.near(win:GetScale(), 1.1, 1e-9, "the window follows at once")
    slider:_fire("OnMouseWheel", 1)
    T.near(ns.Get("scale"), 1.15, 1e-9, "a wheel notch: 5 %")
    slider:SetTo(97)
    T.near(ns.Get("scale"), 0.95, 1e-9, "in steps of 5")
    slider:SetTo(200)
    T.near(ns.Get("scale"), 1.3, 1e-9, "130 % at most")
    T.eq(text(W, slider.value), "130%")
    slider:SetTo(10)
    T.near(ns.Get("scale"), 0.8, 1e-9, "80 % at least")
end)

-------------------------------------------------------------------------------
--  Edge cases
-------------------------------------------------------------------------------
T.it("a dragged size applies when the knob is let go", function()
    local G, W, ns, win, view = setup()
    local slider = view.size.control
    -- The window grows under the cursor while the knob is dragged: applied at once, the size would chase itself.
    W.cursorX = slider.track:GetLeft() + 0.6 * slider.track:GetWidth()
    slider:_fire("OnMouseDown", "LeftButton")
    T.eq(text(W, slider.value), "110%", "the knob follows the cursor")
    T.eq(ns.Get("scale"), 1, "the window waits")
    W.cursorX = slider.track:GetLeft() + 0.8 * slider.track:GetWidth()
    W.advance(0.1)
    T.eq(text(W, slider.value), "120%")
    T.eq(ns.Get("scale"), 1)
    slider:_fire("OnMouseUp", "LeftButton")
    T.near(ns.Get("scale"), 1.2, 1e-9, "let go: the size applies")
    T.near(win:GetScale(), 1.2, 1e-9)
    slider:_fire("OnMouseWheel", -1)
    T.near(ns.Get("scale"), 1.15, 1e-9, "the wheel still applies at once")
end)

T.it("sound: Soft chime or None, the chime played when chosen", function()
    local G, W, ns, win, view = setup()
    local dropdown = view.sound.control
    local menu, items = menuOf(ns, dropdown)
    T.eq(table.concat(items, ", "), "Soft chime, None")
    menu.rows[2]:Click()
    T.eq(ns.Get("sound"), "none")
    T.eq(#W.sounds, 0, "no sound for None")
    menu = menuOf(ns, dropdown)
    menu.rows[1]:Click()
    T.eq(ns.Get("sound"), "chime")
    T.eq(#W.sounds, 1, "the chime, to hear it")
    T.eq(W.sounds[1].file, CHIME)
    T.eq(W.sounds[1].channel, "Master")
end)

T.it("the accent choice applies", function()
    local G, W, ns, win, view = setup()
    view.accent.control.buttons[2]:Click()
    T.eq(ns.Get("accent"), "eui")
    same({ ns.Theme.Accent() }, { 0, 0.81, 1 }, "EllesmereUI's accent")
end)

T.it("without EllesmereUI the Accent row is left out", function()
    local G, W, ns, win, view = setup({ eui = false })
    T.no(view.accent:IsShown(), "nothing to choose: the class colour is the accent")
    local _, headY = box(W, win, view.heads[3])
    local _, sizeY = box(W, win, view.size)
    T.eq(sizeY, headY + 13 + 2, "Size right under LOOK")
    T.no(view.size.hair:IsShown())
    T.eq(win:GetHeight(), 32 + view:Height())
end)

T.it("with the setting off at login there is nothing to reload", function()
    local G, W, ns, win, view = setup({ db = { settings = { rollInTutti = false } } })
    T.no(ns.Popups.Suppressed())
    T.eq(text(W, view.roll.desc), ROLL_LINE, "the line says what the setting does")
    T.no(view.roll.reload:IsShown())
    view.roll.control:Click()
    T.ok(ns.Popups.Suppressed(), "on: the popups go at once")
    view.roll.control:Click()
    T.eq(text(W, view.roll.desc), RELOAD_LINE, "off again: now they need a reload")
end)

T.it("a new font that wraps the lines otherwise has the window fit the rows again", function()
    local G, W, ns, win, view = setup()
    local font = ns.Theme.Font
    ns.Theme.Font = function(role)
        local path, size, flags = font(role)
        if role == "small" then size = 14 end -- EllesmereUI's font changed: the line under a label wraps anew
        return path, size, flags
    end
    local before = view:Height()
    ns.Fire("LOOKS_CHANGED")
    T.ok(view:Height() > before, "the row grew")
    T.eq(win:GetHeight(), 32 + view:Height(), "and the window with it")
end)
