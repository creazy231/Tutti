local T = T

local function rgb(c) return { c[1], c[2], c[3] } end

local EUI_FONTS = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
local BOLD_ROLES = { "title", "item", "row", "roll" }
local REGULAR_ROLES = { "sub", "pick", "button", "fold", "section", "small", "you" }

T.it("without EllesmereUI the palette matches the mockup tokens", function()
    local G, W, ns = T.load()
    local P = ns.Theme.P
    T.color(rgb(P.bg), "141414")
    T.color(rgb(P.panel), "191919")
    T.color(rgb(P.sidebar), "0e0e0e")
    T.color(rgb(P.panelAlt), "212121")
    T.color(rgb(P.sky), "2a2a2a")
    T.color(rgb(P.text), "f8f8f8")
    T.color(rgb(P.dim), "cacccf")
    T.color(rgb(P.muted), "a2a5a9")
    T.color(rgb(P.faint), "6f7277")
    T.color(rgb(P.accent), "ff7d0a", "druid orange")
    T.near(P.bg[4], 0.92)
end)

T.it("Color, Hex and Accent read the palette", function()
    local G, W, ns = T.load()
    local Th, P = ns.Theme, ns.Theme.P
    local r, g, b, a = Th.Color("panel")
    T.eq(r, P.panel[1])
    T.eq(g, P.panel[2])
    T.eq(b, P.panel[3])
    T.eq(a, P.panel[4])
    T.eq(Th.Hex("text"), "fff8f8f8")
    T.color({ Th.Accent() }, "ff7d0a")
    T.color({ Th.Color("no such colour") }, "f8f8f8", "an unknown name reads as the text colour")
end)

T.it("with EllesmereUI the panel colour and font follow its skin", function()
    local G, W, ns = T.load({ eui = { panel = { 0.2, 0.1, 0.1, 0.8 }, font = "Interface\\AddOns\\X\\Foo.ttf" } })
    local P = ns.Theme.P
    T.near(P.bg[1], 0.2, 0.01)
    T.near(P.bg[4], 0.8)
    local path = ns.Theme.Font("row")
    T.eq(path, "Interface\\AddOns\\X\\Foo.ttf")
end)

T.it("registers its skin with EllesmereUI as Tutti", function()
    local G, W, ns = T.load({ eui = true })
    T.eq(W.eui.name, "Tutti")
end)

T.it("accent 'eui' uses EllesmereUI's accent and follows live changes", function()
    local G, W, ns = T.load({ eui = { accent = { 0, 0.81, 1 } } })
    local fired = 0
    ns.Listen("LOOKS_CHANGED", function() fired = fired + 1 end)
    ns.Set("accent", "eui")
    T.color(rgb(ns.Theme.P.accent), "00cfff")
    T.eq(fired, 1, "the setting refreshed the look")
    W.euiChange({ accent = { 1, 0, 0 } })
    T.color(rgb(ns.Theme.P.accent), "ff0000")
    T.eq(fired, 2, "EllesmereUI's change refreshed it again")
end)

T.it("accent 'eui' without EllesmereUI falls back to the class colour", function()
    local G, W, ns = T.load()
    ns.Set("accent", "eui")
    T.color(rgb(ns.Theme.P.accent), "ff7d0a")
end)

T.it("the class accent is lifted to read on the panel", function()
    local G, W, ns = T.load({ setup = function(G, W) W.player.classFile = "SHAMAN"; W.player.class = "Shaman" end })
    T.color(rgb(ns.Theme.P.accent), "2585e2")
end)

T.it("ClassColor lifts dark class colours", function()
    local G, W, ns = T.load()
    local r, g, b = ns.Theme.ClassColor("SHAMAN")
    T.color({ r, g, b }, "2585e2")
    r, g, b = ns.Theme.ClassColor("WARRIOR")
    T.color({ r, g, b }, "c79c6e")
end)

T.it("every font role has its fixed size and no outline flag", function()
    local G, W, ns = T.load()
    local sizes = { title = 13.5, item = 13.5, sub = 11, row = 12.5, pick = 11.5, roll = 13, button = 12,
        fold = 12, section = 9.5, small = 10.5, you = 9.5 }
    for role, size in pairs(sizes) do
        local _, got, flags = ns.Theme.Font(role)
        T.eq(got, size, role .. " size")
        T.eq(flags, "", role .. " flags")
    end
    local _, size = ns.Theme.Font("no such role")
    T.eq(size, 11, "an unknown role reads as the subtitle")
end)

T.it("name, title and number roles use Expressway Bold when the EllesmereUI font is Expressway", function()
    local G, W, ns = T.load({ eui = { font = EUI_FONTS .. "Expressway.TTF" } })
    for _, role in ipairs(BOLD_ROLES) do T.eq((ns.Theme.Font(role)), EUI_FONTS .. "Expressway Bold.ttf", role) end
    for _, role in ipairs(REGULAR_ROLES) do T.eq((ns.Theme.Font(role)), EUI_FONTS .. "Expressway.TTF", role) end
end)

T.it("without EllesmereUI the game font is used", function()
    local G, W, ns = T.load()
    T.eq((ns.Theme.Font("row")), G.STANDARD_TEXT_FONT)
    T.eq((ns.Theme.Font("title")), G.STANDARD_TEXT_FONT)
end)

T.it("ApplyFont sets the role's font", function()
    local G, W, ns = T.load()
    local fs = G.UIParent:CreateFontString()
    ns.Theme.ApplyFont(fs, "roll")
    local path, size = fs:GetFont()
    T.eq(path, G.STANDARD_TEXT_FONT)
    T.eq(size, 13)
end)

T.it("ApplyFont falls back to the regular font when the bold file is missing", function()
    local G, W, ns = T.load({ eui = { font = EUI_FONTS .. "Expressway.TTF" },
        setup = function(G, W) W.missingFonts = { [EUI_FONTS .. "Expressway Bold.ttf"] = true } end })
    local fs = G.UIParent:CreateFontString()
    ns.Theme.ApplyFont(fs, "title")
    T.eq((fs:GetFont()), EUI_FONTS .. "Expressway.TTF")
end)

T.it("pick colours", function()
    local G, W, ns = T.load()
    local Th = ns.Theme
    T.color({ Th.Pick("need") }, "6bd999")
    T.color({ Th.Pick("greed") }, "fabf4d")
    T.color({ Th.Pick("pass") }, "8d9096")
    T.color({ Th.Pick("transmog") }, "c58cff")
    T.color({ Th.Pick("wait") }, "6f7277", "choosing")
    T.color({ Th.Pick("out") }, "6f7277", "not in this roll")
    T.color({ Th.Pick("something else") }, "6f7277", "an unknown state reads as choosing")
    T.eq(Th.Hex("need"), "ff6bd999", "a pick colour is a palette name too")
end)

T.it("quality text reads at 4.5:1 and the edge stays raw", function()
    local G, W, ns = T.load()
    local Th, P = ns.Theme, ns.Theme.P
    for q = 0, 8 do
        T.ok(ns.Color.Contrast({ Th.Quality(q) }, P.panel) >= 4.5, "quality " .. q .. " reads on the panel")
        local c = G.ITEM_QUALITY_COLORS[q]
        local r, g, b = Th.QualityEdge(q)
        T.eq(r, c.r, "edge red " .. q)
        T.eq(g, c.g, "edge green " .. q)
        T.eq(b, c.b, "edge blue " .. q)
    end
    local rare = G.ITEM_QUALITY_COLORS[3]
    local _, g, b = Th.Quality(3)
    T.ok(g > rare.g and b > rare.b, "rare blue is lifted toward the text colour")
    T.color({ Th.Quality(1) }, "ffffff", "a colour that already reads is left alone")
end)

T.it("quality text is lifted again when the panel colour changes", function()
    local G, W, ns = T.load({ eui = { panel = { 0.08, 0.08, 0.08, 0.92 } } })
    local Th, P = ns.Theme, ns.Theme.P
    local dark = { Th.Quality(3) }                  -- lifted for the dark panel, and cached
    W.euiChange({ panel = { 0.3, 0.3, 0.3, 1 } })   -- a much lighter panel
    T.ok(ns.Color.Contrast(dark, P.panel) < 4.5, "the old lift no longer reads on the lighter panel")
    local light = { Th.Quality(3) }
    T.ok(ns.Color.Contrast(light, P.panel) >= 4.5, "the new lift does")
    T.ok(light[2] > dark[2], "and sits closer to the text colour")
end)

T.it("an unknown, missing or secret quality reads as Common", function()
    local G, W, ns = T.load()
    local Th = ns.Theme
    T.color({ Th.Quality(nil) }, "ffffff")
    T.color({ Th.Quality(99) }, "ffffff")
    T.color({ Th.Quality("3") }, "ffffff")
    T.color({ Th.Quality(T.secret(3)) }, "ffffff")
    T.color({ Th.QualityEdge(nil) }, "ffffff")
    T.color({ Th.QualityEdge(99) }, "ffffff")
    T.color({ Th.QualityEdge(T.secret(3)) }, "ffffff")
end)

T.it("a quality number the game marks secret reads as Common too", function()
    -- The fake's secrets are userdata; in the client a secret number still has type "number".
    local G, W, ns = T.load({ setup = function(G) G.hasanysecretvalues = function(...) return (...) == 3 end end })
    T.color({ ns.Theme.Quality(3) }, "ffffff")
    T.color({ ns.Theme.QualityEdge(3) }, "ffffff")
    T.color({ ns.Theme.QualityEdge(4) }, "a335ee", "other numbers are untouched")
end)
