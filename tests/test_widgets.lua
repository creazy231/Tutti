local T = T

local function load(opts)
    local G, W, ns = T.load(opts)
    local parent = G.CreateFrame("Frame", nil, G.UIParent)
    parent:SetSize(300, 200)
    parent:SetPoint("CENTER")
    return G, W, ns, ns.W, parent
end

-- Is the colour { r, g, b, a } the one expected?
local function same(c, r, g, b, a, msg)
    msg = msg or "colour"
    T.ok(type(c) == "table", msg .. ": no colour")
    T.near(c[1], r, 1e-6, msg .. " red")
    T.near(c[2], g, 1e-6, msg .. " green")
    T.near(c[3], b, 1e-6, msg .. " blue")
    T.near(c[4], a, 1e-6, msg .. " alpha")
end

-- A colour of the theme's as { r, g, b, a }.
local function theme(ns, name)
    local r, g, b, a = ns.Theme.Color(name)
    return { r, g, b, a }
end

-------------------------------------------------------------------------------
--  Sotto's widgets, as they were
-------------------------------------------------------------------------------
T.it("the widget kit draws from Tutti's media folder", function()
    local G, W, ns, Wd = load()
    T.eq(Wd.MEDIA, "Interface\\AddOns\\Tutti\\Media\\")
end)

T.it("switch toggles its value and repaints", function()
    local G, W, ns, Wd, parent = load()
    local v = false
    local sw = Wd.Switch(parent, function() return v end, function(x) v = x end)
    local before = { sw.track:GetVertexColor() }
    sw:Click()
    T.eq(v, true)
    local after = { sw.track:GetVertexColor() }
    T.ok(before[1] ~= after[1] or before[4] ~= after[4], "track colour changed")
    sw:Click()
    T.eq(v, false)
end)

T.it("segmented control selects a choice", function()
    local G, W, ns, Wd, parent = load()
    local v = "a"
    local seg = Wd.Segmented(parent, { { value = "a", text = "Always" }, { value = "b", text = "Never" } },
        function() return v end, function(x) v = x end)
    T.ok(seg.buttons[1].selected, "first selected")
    seg.buttons[2]:Click()
    T.eq(v, "b")
    T.ok(seg.buttons[2].selected and not seg.buttons[1].selected, "selection moved")
    T.ok(seg:GetWidth() > 0, "sized to its labels")
end)

T.it("slider clamps and steps", function()
    local G, W, ns, Wd, parent = load()
    local v = 13
    local sl = Wd.Slider(parent, 11, 16, 1, function() return v end, function(x) v = x end)
    sl:SetTo(17.4)
    T.eq(v, 16)
    sl:SetTo(12.4)
    T.eq(v, 12)
    sl:_fire("OnMouseWheel", 1)
    T.eq(v, 13)
    sl:_fire("OnMouseWheel", -1)
    T.eq(v, 12)
    T.eq(sl.value:GetText(), "12")
end)

T.it("dropdown opens a menu and sets the value", function()
    local G, W, ns, Wd, parent = load()
    local v = "chime"
    local dd = Wd.Dropdown(parent, { { value = "chime", text = "Soft chime" }, { value = "none", text = "None" } },
        function() return v end, function(x) v = x end)
    T.eq(dd.label:GetText(), "Soft chime")
    dd:Click()
    local menu = Wd.CurrentMenu()
    T.ok(menu and menu:IsShown(), "menu open")
    T.eq(#menu.rows >= 2 and menu.rows[2].label:GetText(), "None")
    menu.rows[2]:Click()
    T.eq(v, "none")
    T.no(menu:IsShown(), "menu closed")
    T.eq(dd.label:GetText(), "None")
end)

T.it("a text takes a size its role lacks, kept through a repaint", function()
    local G, W, ns, Wd, parent = load({ eui = true })
    local bold = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway Bold.ttf"
    local regular = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local fs = Wd.Text(parent, "item", "muted", nil, 11)
    local path, size = fs:GetFont()
    T.eq(path, bold, "the role's file: its weight")
    T.eq(size, 11, "at the size asked for")
    ns.Fire("LOOKS_CHANGED")
    T.eq(select(2, fs:GetFont()), 11, "kept through a repaint")
    Wd.SetRole(fs, "sub", 12.5)
    path, size = fs:GetFont()
    T.eq(path, regular)
    T.eq(size, 12.5)
    Wd.SetRole(fs, "sub")
    T.eq(select(2, fs:GetFont()), 11, "a role without a size: the role's own")
    ns.Fire("LOOKS_CHANGED")
    T.eq(select(2, fs:GetFont()), 11)
end)

-- The approved mockup's .segc, .dd and .sl (docs/mockup): Tutti's settings view is cut to them.
T.it("the settings controls follow the mockup: .segc 11 px, .dd 11.5 px, .sl a 64 px track and its value", function()
    local G, W, ns, Wd, parent = load()
    local accent = "class"
    local seg = Wd.Segmented(parent,
        { { value = "class", text = "Class colour" }, { value = "eui", text = "EllesmereUI" } },
        function() return accent end, function(x) accent = x end)
    local first, second = seg.buttons[1], seg.buttons[2]
    T.eq(select(2, first.text:GetFont()), 11, "11 px")
    T.eq(first:GetHeight(), 21, "3 px above and below the 15.4 px line")
    T.eq(first:GetWidth(), math.ceil(first.text:GetStringWidth()) + 12, "6 px either side")
    T.eq(seg:GetHeight(), 21)
    T.eq(seg:GetWidth(), first:GetWidth() + second:GetWidth())

    local after = 10
    local dd = Wd.Dropdown(parent, { { value = 10, text = "10 seconds" }, { value = 0, text = "Never" } },
        function() return after end, function(x) after = x end)
    T.eq(select(2, dd.label:GetFont()), 11.5, "11.5 px")
    T.eq(dd:GetHeight(), 22, "3 px above and below the 16.1 px line")
    local probe = Wd.Text(parent, "pick")
    probe:SetText("10 seconds")
    T.eq(dd:GetWidth(), math.ceil(probe:GetStringWidth()) + 35, "7 + the widest choice + 12 + a 9 px chevron + 7")
    T.eq(dd.chev:GetWidth(), 9)
    T.near(dd.chev:GetRight(), dd:GetRight() - 7, 1e-6, "the chevron 7 px in")
    T.near(dd.label:GetLeft(), dd:GetLeft() + 7, 1e-6, "the label 7 px in")

    local size = 100
    local sl = Wd.Slider(parent, 80, 130, 5, function() return size end, function(x) size = x end,
        function(v) return v .. "%" end)
    T.eq(sl.value:GetText(), "100%", "the caller's format")
    T.eq(select(2, sl.value:GetFont()), 11.5, "11.5 px")
    T.eq(sl:GetHeight(), 16)
    T.eq(sl.track:GetWidth(), 64, "a 64 px track")
    probe:SetText("130%")
    T.eq(sl.value:GetWidth(), math.ceil(probe:GetStringWidth()), "the value as wide as the widest end")
    T.near(sl.value:GetRight(), sl:GetRight(), 1e-6, "the value on the right")
    T.near(sl.track:GetRight() + 8, sl.value:GetLeft(), 1e-6, "8 px before it")
    T.near(sl.track:GetLeft(), sl:GetLeft() + 5, 1e-6, "half a knob in from the left")
    T.eq(sl.ring:GetWidth(), 12, "the knob's dark ring, 1 px around it")
    sl:SetTo(85)
    T.eq(sl.value:GetText(), "85%")
end)

T.it("a right-aligned menu opens to the left of its anchor", function()
    local G, W, ns, Wd, parent = load()
    local anchor = G.CreateFrame("Button", nil, parent)
    anchor:SetSize(24, 24)
    anchor:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    local menu = Wd.Menu(anchor, { { text = "Soft chime" }, { text = "None" } }, 170, "RIGHT")
    T.near(menu:GetRight(), anchor:GetRight(), 0.01, "right edges line up")
    T.ok(menu:GetLeft() < anchor:GetLeft(), "opens leftwards")
end)

T.it("the menu is Tutti's own frame, closes on Escape and on a click elsewhere", function()
    local G, W, ns, Wd, parent = load()
    local anchor = G.CreateFrame("Button", nil, parent)
    anchor:SetSize(24, 24)
    local menu = Wd.Menu(anchor, { { text = "Soft chime" }, { text = "None" } })
    T.eq(G.TuttiMenu, menu, "named for Tutti")
    T.eq(G.SottoMenu, nil)
    T.has(G.UISpecialFrames, "TuttiMenu", "Escape closes it")
    T.ok(menu:IsShown())
    W.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    T.no(menu:IsShown(), "a click outside closes it")
end)

T.it("text and fills repaint when the looks change", function()
    local G, W, ns, Wd, parent = load()
    local fill = Wd.Fill(parent, "accent")
    local fs = Wd.Text(parent, "small", "accent")
    ns.Set("accent", "eui")
    ns.Theme.P.accent = { 1, 0, 0, 1 } -- simulate a new accent, then repaint
    ns.Fire("LOOKS_CHANGED")
    T.eq(fill._color[1], 1)
    T.eq(select(1, fs:GetTextColor()), 1)
end)

T.it("icon buttons show a tooltip and click", function()
    local G, W, ns, Wd, parent = load()
    local clicked = false
    local b = Wd.IconButton(parent, "gear", "Settings", function() clicked = true end)
    b:_fire("OnEnter")
    T.eq(G.GameTooltip._lines[1], "Settings")
    b:_fire("OnLeave")
    b:Click()
    T.ok(clicked)
    T.ok(b.icon:GetTexture():find("Media\\Icons\\gear", 1, true), "icon path")
end)

T.it("Pixel is one physical pixel in frame units", function()
    local G, W, ns, Wd, parent = load()
    T.near(Wd.Pixel(parent), 768 / 1080, 1e-6)
end)

T.it("a fill, a hairline or a glyph takes a colour of its own and keeps it through a repaint", function()
    local G, W, ns, Wd, parent = load()
    local fill = Wd.Fill(parent, { 0.1, 0.2, 0.3, 0.4 })
    same(fill._color, 0.1, 0.2, 0.3, 0.4, "a table with alpha")
    Wd.SetFill(fill, { 0.5, 0.6, 0.7 })
    same(fill._color, 0.5, 0.6, 0.7, 1, "a table without alpha is opaque")
    local lines = Wd.Border(parent, { 1, 0, 0, 0.5 })
    local glyph = Wd.Icon(parent, "check", 12, { 0, 1, 0, 1 })
    ns.Fire("LOOKS_CHANGED")
    same(fill._color, 0.5, 0.6, 0.7, 1, "the fill after a repaint")
    for _, line in ipairs(lines) do same(line._color, 1, 0, 0, 0.5, "a hairline after a repaint") end
    same({ glyph:GetVertexColor() }, 0, 1, 0, 1, "the glyph after a repaint")
    Wd.SetFill(fill, "accent")
    same(fill._color, ns.Theme.Color("accent"))
end)

T.it("a border's sides run between its top and bottom lines: a translucent colour once at each corner", function()
    local G, W, ns, Wd, parent = load()
    local px = Wd.Pixel(parent)
    local top, bottom, left, right = unpack(Wd.Border(parent, "hair"))
    local frame = W.rect(parent)
    for name, line in pairs({ top = top, bottom = bottom }) do
        local r = W.rect(line)
        T.eq(r[1], frame[1], name .. " line from the left edge")
        T.eq(r[3], 300, name .. " line to the right edge")
        T.near(r[4], px, 1e-9, name .. " line one pixel high")
    end
    for name, line in pairs({ left = left, right = right }) do
        local r = W.rect(line)
        T.near(r[2], frame[2] + px, 1e-9, name .. " side starts above the bottom line")
        T.near(r[2] + r[4], frame[2] + 200 - px, 1e-9, name .. " side ends under the top line")
        T.near(r[3], px, 1e-9, name .. " side one pixel wide")
    end
    T.eq(W.rect(left)[1], frame[1], "the left side on the left edge")
    T.near(W.rect(right)[1] + px, frame[1] + 300, 1e-9, "the right side on the right edge")
end)

-------------------------------------------------------------------------------
--  The roll button
-------------------------------------------------------------------------------
T.it("roll button: not allowed is 0.38 alpha and ignores clicks", function()
    local G, W, ns, Wd, parent = load()
    local clicks = {}
    local b = Wd.RollButton(parent, "need", function(button) clicks[#clicks + 1] = button end)
    T.eq(b:GetAlpha(), 1)
    b:Click()
    T.eq(#clicks, 1, "a click picks")
    T.eq(clicks[1], b, "the callback gets the button")
    b:SetAllowed(false)
    T.eq(b:GetAlpha(), 0.38)
    b:Click()
    T.eq(#clicks, 1, "a click is ignored")
    b:SetAllowed(true)
    T.eq(b:GetAlpha(), 1)
    b:Click()
    T.eq(#clicks, 2, "and works again")
    local quiet = Wd.RollButton(parent, "pass")
    quiet:Click() -- no callback: nothing happens
end)

T.it("roll button: 23 px high, a 14 px glyph, a 12 px label, a white 6 % fill with a 10 % hairline", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "need")
    b:SetWidth(90)
    T.eq(b:GetHeight(), 23)
    T.eq(b.glyph:GetWidth(), 14)
    T.eq(b.glyph:GetHeight(), 14)
    T.ok(b.glyph:GetTexture():find("Media\\Icons\\need", 1, true), "the glyph is the pick's own")
    local _, size = b.label:GetFont()
    T.eq(size, 12, "label size")
    T.eq(b.label:GetText(), "Need")
    same(b.fill._color, 1, 1, 1, 0.06, "fill")
    T.eq(#b.edge, 4, "four hairlines")
    for i, line in ipairs(b.edge) do same(line._color, 1, 1, 1, 0.10, "hairline " .. i) end
    local r, g, bl = ns.Theme.Pick("need")
    same({ b.glyph:GetVertexColor() }, r, g, bl, 1, "the glyph is in the pick colour")
    local text = theme(ns, "text")
    same({ b.label:GetTextColor() }, text[1], text[2], text[3], text[4], "the label is in the text colour")
end)

T.it("roll button: glyph and word sit together in the middle, 5 px apart", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "greed")
    b:SetSize(90, 23)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -10)
    local centre = (b:GetLeft() + b:GetRight()) / 2
    T.near((b.glyph:GetLeft() + b.label:GetRight()) / 2, centre, 0.51, "the pair is centred")
    T.near(b.label:GetLeft() - b.glyph:GetRight(), 5, 0.01, "5 px between glyph and word")
    local _, glyphY = b.glyph:GetCenter()
    local _, buttonY = b:GetCenter()
    T.near(glyphY, buttonY, 0.01, "and centred on the button's height")
end)

T.it("roll button: hover is a 10 % fill and a 70 % hairline in the pick colour", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "greed")
    local r, g, bl = ns.Theme.Pick("greed")
    b:_fire("OnEnter")
    same(b.fill._color, 1, 1, 1, 0.10, "hover fill")
    for i, line in ipairs(b.edge) do same(line._color, r, g, bl, 0.7, "hover hairline " .. i) end
    same({ b.glyph:GetVertexColor() }, r, g, bl, 1, "the glyph keeps its colour")
    b:_fire("OnLeave")
    same(b.fill._color, 1, 1, 1, 0.06, "rest fill")
    for i, line in ipairs(b.edge) do same(line._color, 1, 1, 1, 0.10, "rest hairline " .. i) end
end)

T.it("roll button: press scales to 0.95 with a 20 % fill, and lets go on release or on leaving", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "need")
    b:SetSize(90, 23)
    local r, g, bl = ns.Theme.Pick("need")
    b:_fire("OnEnter")
    b:_fire("OnMouseDown", "LeftButton")
    T.eq(b.body:GetScale(), 0.95, "pressed: scale 0.95")
    T.eq(b:GetScale(), 1, "the button itself keeps its size and its hit area")
    same(b.fill._color, r, g, bl, 0.2, "pressed fill")
    for i, line in ipairs(b.edge) do same(line._color, r, g, bl, 0.8, "pressed hairline " .. i) end
    T.eq(b.body:GetWidth(), 90, "the pressed body is the button's size, shrunk from its middle")
    T.eq(b.body:GetHeight(), 23)
    b:_fire("OnMouseUp", "LeftButton")
    T.eq(b.body:GetScale(), 1, "released")
    same(b.fill._color, 1, 1, 1, 0.10, "the mouse is still over it: the hover look")
    b:_fire("OnMouseDown", "LeftButton")
    b:_fire("OnLeave")
    T.eq(b.body:GetScale(), 1, "leaving lets go")
    same(b.fill._color, 1, 1, 1, 0.06)
    b:_fire("OnEnter")
    b:_fire("OnMouseDown", "LeftButton")
    b:Hide()
    b:Show()
    T.eq(b.body:GetScale(), 1, "hiding lets go too")
    same(b.fill._color, 1, 1, 1, 0.06, "and forgets the hover")
end)

T.it("roll button: one that is not allowed shows no hover or press, and a faint glyph", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "need")
    b:SetAllowed(false)
    b:_fire("OnEnter")
    b:_fire("OnMouseDown", "LeftButton")
    same(b.fill._color, 1, 1, 1, 0.06, "no hover fill")
    for i, line in ipairs(b.edge) do same(line._color, 1, 1, 1, 0.06, "a soft hairline " .. i) end
    T.eq(b.body:GetScale(), 1, "no press")
    local faint = theme(ns, "faint")
    same({ b.glyph:GetVertexColor() }, faint[1], faint[2], faint[3], 1, "a faint glyph")
    b:SetAllowed(true)
    local r, g, bl = ns.Theme.Pick("need")
    same({ b.glyph:GetVertexColor() }, r, g, bl, 1, "the pick colour is back")
    same(b.fill._color, 1, 1, 1, 0.10, "the mouse is over it: the hover look")
    T.eq(b.body:GetScale(), 1, "a press made while it was not allowed is not remembered")
end)

T.it("roll button: pressing and then not being allowed leaves nothing pressed behind", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "need")
    b:SetSize(90, 23)
    b:_fire("OnMouseDown", "LeftButton")
    T.eq(b.body:GetScale(), 0.95)
    b:SetAllowed(false)
    T.eq(b.body:GetScale(), 1, "not allowed: not pressed")
    b:SetAllowed(true)
    T.eq(b.body:GetScale(), 1, "and not pressed again when it is allowed")
    same(b.fill._color, 1, 1, 1, 0.06)
end)

T.it("roll button: a kind it does not know is drawn as Pass", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "bogus")
    T.eq(b.label:GetText(), "Pass")
    T.ok(b.glyph:GetTexture():find("Media\\Icons\\pass", 1, true))
    T.eq(b.kind, "pass")
end)

T.it("roll button: measures its word again when the looks change", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "greed")
    b:SetSize(90, 23)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -10)
    b.label.GetUnboundedStringWidth = function() return 40 end -- a wider font
    ns.Fire("LOOKS_CHANGED")
    T.eq(b.label:GetWidth(), 40)
    local centre = (b:GetLeft() + b:GetRight()) / 2
    T.near((b.glyph:GetLeft() + b.label:GetRight()) / 2, centre, 0.01, "still centred")
end)

T.it("roll button: each pick has its own glyph, colour and word", function()
    local G, W, ns, Wd, parent = load()
    local want = {
        need = { "Need", "6bd999" }, greed = { "Greed", "fabf4d" }, pass = { "Pass", "8d9096" },
        transmog = { "Transmog", "c58cff" },
    }
    for kind, spec in pairs(want) do
        local b = Wd.RollButton(parent, kind)
        T.eq(b.label:GetText(), spec[1], kind .. " word")
        T.ok(b.glyph:GetTexture():find("Media\\Icons\\" .. kind, 1, true), kind .. " glyph")
        T.color({ b.glyph:GetVertexColor() }, spec[2], kind .. " colour")
    end
end)

T.it("roll button: the words are the game's where it has them", function()
    local G, W, ns, Wd, parent = load({ setup = function(G)
        G.NEED, G.GREED, G.PASS = "Bedarf", "Gier", T.secret("Passen")
    end })
    T.eq(Wd.RollButton(parent, "need").label:GetText(), "Bedarf")
    T.eq(Wd.RollButton(parent, "greed").label:GetText(), "Gier")
    T.eq(Wd.RollButton(parent, "pass").label:GetText(), "Pass", "a word the game keeps secret is English")
end)

T.it("roll button: Transmog says the short word, never the game's long noun (R27)", function()
    local G, W, ns, Wd, parent = load({ setup = function(G) G.TRANSMOGRIFICATION = "Transmogrification" end })
    T.eq(Wd.RollButton(parent, "transmog").label:GetText(), "Transmog")
end)

T.it("roll button: a word too long for the button is cut, not spilled", function()
    local G, W, ns, Wd, parent = load({ setup = function(G) G.NEED = "Bedarfsanmeldung" end })
    local b = Wd.RollButton(parent, "need")
    b:SetSize(90, 23)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -10)
    T.ok(b.label:GetWidth() <= 58, "the word is held to 58 px")
    T.ok(b.glyph:GetLeft() >= b:GetLeft() + 6, "glyph inside the button")
    T.ok(b.label:GetRight() <= b:GetRight() - 6, "word inside the button")
end)

T.it("roll button: keeps its state through a repaint and follows the button's size", function()
    local G, W, ns, Wd, parent = load()
    local b = Wd.RollButton(parent, "need")
    b:SetSize(90, 23)
    b:_fire("OnEnter")
    ns.Fire("LOOKS_CHANGED")
    same(b.fill._color, 1, 1, 1, 0.10, "still hovered")
    b:SetAllowed(false)
    ns.Fire("LOOKS_CHANGED")
    T.eq(b:GetAlpha(), 0.38, "still not allowed")
    b:SetSize(120, 23)
    b:_fire("OnSizeChanged", 120, 23)
    T.eq(b.body:GetWidth(), 120, "the drawn body follows the button's size")
end)

-------------------------------------------------------------------------------
--  The item icon
-------------------------------------------------------------------------------
T.it("item icon edge is the quality edge colour", function()
    local G, W, ns, Wd, parent = load()
    local icon = Wd.ItemIcon(parent, 34)
    T.eq(icon:GetWidth(), 34)
    T.eq(icon:GetHeight(), 34)
    icon:SetItem(135349, 3)
    T.eq(icon.icon:GetTexture(), 135349)
    local r, g, b = ns.Theme.QualityEdge(3)
    T.color({ r, g, b }, "0070dd", "rare: the game's blue, not the text colour lifted to read")
    T.eq(#icon.edge, 4, "four edge lines")
    for i, line in ipairs(icon.edge) do same(line._color, r, g, b, 1, "edge " .. i) end
    icon:SetItem(135349, 4)
    r, g, b = ns.Theme.QualityEdge(4)
    for i, line in ipairs(icon.edge) do same(line._color, r, g, b, 1, "epic edge " .. i) end
    ns.Fire("LOOKS_CHANGED")
    for i, line in ipairs(icon.edge) do same(line._color, r, g, b, 1, "edge " .. i .. " after a repaint") end
end)

T.it("item icon without a texture shows the question mark and the edge until the real one arrives", function()
    local G, W, ns, Wd, parent = load()
    local icon = Wd.ItemIcon(parent, 34)
    T.eq(icon.icon:GetTexture(), 134400, "a new icon, before any SetItem, is the question mark")
    icon:SetItem(nil, 4)
    T.eq(icon.icon:GetTexture(), 134400, "the question mark")
    local r, g, b = ns.Theme.QualityEdge(4)
    for i, line in ipairs(icon.edge) do same(line._color, r, g, b, 1, "edge " .. i) end
    icon:SetItem(135349, 4)
    T.eq(icon.icon:GetTexture(), 135349, "the next SetItem takes the real texture")
    icon:SetItem(nil, 4)
    T.eq(icon.icon:GetTexture(), 134400, "and a texture that goes missing again falls back")
end)

T.it("item icon takes a texture path, and nothing it cannot read", function()
    local G, W, ns, Wd, parent = load()
    local icon = Wd.ItemIcon(parent, 34)
    icon:SetItem("Interface\\Icons\\INV_Axe_01", 2)
    T.eq(icon.icon:GetTexture(), "Interface\\Icons\\INV_Axe_01")
    for _, bad in ipairs({ T.secret(135349), T.secret("Interface\\Icons\\X"), 0, -5, "", true, {} }) do
        icon:SetItem(135349, 3)
        icon:SetItem(bad, 3)
        T.eq(icon.icon:GetTexture(), 134400, "unreadable: the question mark")
    end
end)

T.it("item icon: an unknown or secret quality reads as common", function()
    local G, W, ns, Wd, parent = load()
    local icon = Wd.ItemIcon(parent, 34)
    for _, q in ipairs({ 99, -1, "x", T.secret(3) }) do
        icon:SetItem(135349, q)
        for i, line in ipairs(icon.edge) do same(line._color, 1, 1, 1, 1, "common edge " .. i) end
    end
    icon:SetItem(135349, nil)
    for i, line in ipairs(icon.edge) do same(line._color, 1, 1, 1, 1, "no quality: common edge " .. i) end
end)

T.it("item icon: a black rim one physical pixel outside, 1 px edge lines above the artwork", function()
    local G, W, ns, Wd, parent = load()
    local icon = Wd.ItemIcon(parent, 34)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    local px = Wd.Pixel(icon)
    same(icon.rim._color, 0, 0, 0, 1, "rim")
    T.near(icon.rim:GetWidth(), 34 + 2 * px, 1e-6, "the rim is a pixel outside on each side")
    T.near(icon.rim:GetHeight(), 34 + 2 * px, 1e-6)
    T.near(icon.rim:GetLeft(), icon:GetLeft() - px, 1e-6)
    T.eq(icon.icon:GetWidth(), 34, "the artwork fills the icon")
    T.eq(icon.icon:GetHeight(), 34)
    T.near(icon.edge[1]:GetHeight(), px, 1e-6, "top line is one pixel thick")
    T.near(icon.edge[3]:GetWidth(), px, 1e-6, "left line is one pixel thick")
    T.eq(icon.icon._layer, "ARTWORK")
    for i, line in ipairs(icon.edge) do T.eq(line._layer, "OVERLAY", "edge " .. i .. " above the artwork") end
    T.eq(icon.rim._layer, "BACKGROUND")
    local small = Wd.ItemIcon(parent, 26)
    T.eq(small:GetWidth(), 26, "any size")
end)

-------------------------------------------------------------------------------
--  Class icons
-------------------------------------------------------------------------------
T.it("ClassIcon uses the atlas when it exists", function()
    local G, W, ns, Wd, parent = load()
    W.atlases["classicon-druid"] = { width = 64, height = 64 }
    local tex = parent:CreateTexture()
    tex:Hide()
    T.eq(Wd.ClassIcon(tex, "DRUID"), true)
    T.eq(tex._atlas, "classicon-druid")
    T.ok(tex:IsShown(), "and shows it")
end)

T.it("ClassIcon falls back to the class sheet's coordinates with the bevel cropped", function()
    local G, W, ns, Wd, parent = load()
    local tex = parent:CreateTexture()
    T.eq(Wd.ClassIcon(tex, "DRUID"), true)
    T.eq(tex._atlas, nil, "no atlas: the sheet")
    T.eq(tex:GetTexture(), "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    local c = G.CLASS_ICON_TCOORDS.DRUID
    local ix, iy = (c[2] - c[1]) * 0.08, (c[4] - c[3]) * 0.08
    local l, r, t, b = tex:GetTexCoord()
    T.near(l, c[1] + ix, 1e-9)
    T.near(r, c[2] - ix, 1e-9)
    T.near(t, c[3] + iy, 1e-9)
    T.near(b, c[4] - iy, 1e-9)
    T.ok(tex:IsShown())
end)

T.it("ClassIcon takes a class in any case", function()
    local G, W, ns, Wd, parent = load()
    local tex = parent:CreateTexture()
    T.eq(Wd.ClassIcon(tex, "druid"), true)
    T.eq(tex:GetTexture(), "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", "the sheet's cell of DRUID")
    W.atlases["classicon-druid"] = {}
    T.eq(Wd.ClassIcon(tex, "Druid"), true)
    T.eq(tex._atlas, "classicon-druid")
end)

T.it("ClassIcon switches between the atlas and the sheet on one texture", function()
    local G, W, ns, Wd, parent = load()
    local tex = parent:CreateTexture()
    Wd.ClassIcon(tex, "MAGE")
    T.eq(tex:GetTexture(), "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    W.atlases["classicon-druid"] = {}
    Wd.ClassIcon(tex, "DRUID")
    T.eq(tex._atlas, "classicon-druid")
    W.atlases["classicon-druid"] = nil
    Wd.ClassIcon(tex, "MAGE")
    T.eq(tex._atlas, nil, "the sheet again")
    T.eq(tex:GetTexture(), "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
end)

T.it("ClassIcon hides the texture for a class it does not know or cannot read", function()
    local G, W, ns, Wd, parent = load()
    local tex = parent:CreateTexture()
    for i, class in ipairs({ "NOSUCHCLASS", "", 5, true, T.secret("DRUID") }) do
        tex:Show()
        T.eq(Wd.ClassIcon(tex, class), false, "case " .. i)
        T.no(tex:IsShown(), "hidden in case " .. i)
    end
    tex:Show()
    T.eq(Wd.ClassIcon(tex, nil), false, "no class")
    T.no(tex:IsShown())
    T.eq(Wd.ClassIcon(tex, "WARRIOR"), true)
    T.ok(tex:IsShown(), "a class it knows shows it again")
end)

T.it("ClassIcon takes nothing secret from the game, and copes without the atlas API", function()
    local G, W, ns, Wd, parent = load()
    W.atlases["classicon-druid"] = T.secret({})
    local tex = parent:CreateTexture()
    T.eq(Wd.ClassIcon(tex, "DRUID"), true, "a secret atlas answer is no atlas: the sheet")
    T.eq(tex._atlas, nil)
    T.ok(tex:GetTexture():find("CLASSES", 1, true))
    G.C_Texture = nil
    local other = parent:CreateTexture()
    T.eq(Wd.ClassIcon(other, "DRUID"), true, "no C_Texture at all")
    T.ok(other:GetTexture():find("CLASSES", 1, true))
    G.CLASS_ICON_TCOORDS = nil
    T.eq(Wd.ClassIcon(parent:CreateTexture(), "DRUID"), false, "and no sheet either")
    G.CLASS_ICON_TCOORDS = { DRUID = { 0.1, T.secret(0.2), 0.3, 0.4 } }
    T.eq(Wd.ClassIcon(parent:CreateTexture(), "DRUID"), false, "a coordinate the game keeps secret")
    G.CLASS_ICON_TCOORDS = { DRUID = { 0.1, 0.2 } }
    T.eq(Wd.ClassIcon(parent:CreateTexture(), "DRUID"), false, "a short list of coordinates")
end)
