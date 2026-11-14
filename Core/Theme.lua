-------------------------------------------------------------------------------
--  Tutti: the look. Polestar's "EllesmereUI" scheme rebuilt from
--  EllesmereUI's live panel colour: the grounds are that colour moved in OKLab
--  lightness (sidebar -0.03, footer -0.02, panel +0.02, panelAlt +0.055,
--  sky +0.09), the text ladder is Polestar's graphite one, hairlines and
--  washes are white at low alpha. The accent is the player's class colour
--  (lifted until it reads at 4.5:1 on the panel) or EllesmereUI's accent.
--  The picks (Need, Greed, Pass, Transmog) have colours of their own. An item's
--  quality as text is brightened in OKLab lightness, hue and chroma kept, until
--  it reads at 5.5:1 on the window background (not the accent's 4.5:1 mix toward
--  the text colour); its icon edge keeps the game's colour.
--  EllesmereUI is read only through its skinning API (RegisterSkin getters,
--  OnLooksChanged); without it the same palette comes from EUI's defaults.
-------------------------------------------------------------------------------
local _, ns = ...
local Th = {}
ns.Theme = Th

local P = {}
Th.P = P

local S -- EllesmereUI's skin facade, once its callback ran

local DEFAULT_PANEL = { 0.08, 0.08, 0.08, 0.92 }
local DERIVE = { sidebar = -0.03, footer = -0.02, bg = 0, panel = 0.02, panelAlt = 0.055, sky = 0.09 }

-- "6bd999" -> { r, g, b, 1 }
local function fromHex(rrggbb)
    return { tonumber(rrggbb:sub(1, 2), 16) / 255, tonumber(rrggbb:sub(3, 4), 16) / 255,
        tonumber(rrggbb:sub(5, 6), 16) / 255, 1 }
end

local FIXED = {
    text = { 0.974, 0.974, 0.974, 1 }, dim = { 0.793, 0.801, 0.813, 1 }, muted = { 0.635, 0.646, 0.663, 1 },
    faint = { 0.435, 0.447, 0.467, 1 },
    hair = { 1, 1, 1, 0.10 }, hairSoft = { 1, 1, 1, 0.06 }, hover = { 1, 1, 1, 0.07 }, selected = { 1, 1, 1, 0.11 },
    track = { 1, 1, 1, 0.16 }, chip = { 1, 1, 1, 0.07 }, scroll = { 1, 1, 1, 0.16 },
    inset = { 0.039, 0.039, 0.039, 0.85 }, euiBorder = { 0.2, 0.2, 0.2, 1 }, shadow = { 0, 0, 0, 0.55 },
    black = { 0, 0, 0, 1 }, white = { 1, 1, 1, 1 },
    need = fromHex("6bd999"), greed = fromHex("fabf4d"), pass = fromHex("8d9096"), transmog = fromHex("c58cff"),
}
-- A pick's palette name. Still choosing and not in this roll share the faintest grey.
local PICK_COLOR = { need = "need", greed = "greed", pass = "pass", transmog = "transmog", wait = "faint", out = "faint" }
local DEFAULT_ACCENT = { 1, 0.49, 0.04 } -- druid orange, used before the class is known

local REGULAR_FALLBACK = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local fonts = { regular = REGULAR_FALLBACK, bold = REGULAR_FALLBACK }

-- Font roles: { which file, size in px }. The sizes are fixed; the window scales as a whole.
local ROLES = {
    title = { "bold", 13.5 }, item = { "bold", 13.5 }, sub = { "regular", 11 },
    row = { "bold", 12.5 }, pick = { "regular", 11.5 }, roll = { "bold", 13 },
    button = { "regular", 12 }, fold = { "regular", 12 }, section = { "regular", 9.5 },
    small = { "regular", 10.5 }, you = { "regular", 9.5 },
}

local classCache = {}
local qualityCache = {}

local function copy(c) return { c[1], c[2], c[3], c[4] or 1 } end

local function euiCall(name)
    if not (S and S[name]) then return nil end
    local ok, a, b, c, d = pcall(S[name])
    if not ok or a == nil then return nil end
    return a, b, c, d
end

local function rawClassColor(file)
    local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(file))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file])
    if c and type(c.r) == "number" then return c.r, c.g, c.b end
end

-- A class colour that reads at 4.5:1 on the panel. -> r, g, b
function Th.ClassColor(file)
    if not file then return P.text[1], P.text[2], P.text[3] end
    local cached = classCache[file]
    if cached then return cached[1], cached[2], cached[3] end
    local r, g, b = rawClassColor(file)
    if not r then return P.text[1], P.text[2], P.text[3] end
    r, g, b = ns.Color.Lift(P.panel, P.text, { r, g, b }, 4.5)
    classCache[file] = { r, g, b }
    return r, g, b
end

-- The quality to read colours for: a known one, else Common.
local function knownQuality(q)
    if type(q) == "number" and not ns.IsSecret(q) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then return q end
    return 1
end

-- The game's own colour of an item quality, for the icon edge. -> r, g, b
function Th.QualityEdge(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[knownQuality(q)]
    if c and type(c.r) == "number" then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- The colour brightened in OKLab lightness (Color.Shift keeps hue and chroma), in steps of
-- 0.0025, until it reads at 5.5:1 on `ground`. A colour that already reads is returned as it
-- is. The loop is bounded: 400 steps reach full lightness. -> r, g, b
local QUALITY_RATIO, LIGHTNESS_STEP, LIGHTNESS_STEPS = 5.5, 0.0025, 400

local function readableOn(ground, r, g, b)
    local raw = { r, g, b }
    if ns.Color.Contrast(raw, ground) >= QUALITY_RATIO then return r, g, b end
    local c = raw
    for i = 1, LIGHTNESS_STEPS do
        c = ns.Color.Shift(raw, i * LIGHTNESS_STEP)
        if ns.Color.Contrast(c, ground) >= QUALITY_RATIO then break end
    end
    return c[1], c[2], c[3]
end

-- An item quality as text: its colour brightened until it reads at 5.5:1 on the window
-- background (P.bg, EllesmereUI's panel colour), cached per quality. -> r, g, b
function Th.Quality(q)
    q = knownQuality(q)
    local cached = qualityCache[q]
    if not cached then
        local r, g, b = Th.QualityEdge(q)
        r, g, b = readableOn(P.bg, r, g, b)
        cached = { r, g, b }
        qualityCache[q] = cached
    end
    return cached[1], cached[2], cached[3]
end

-- The colour of a pick: "need", "greed", "pass", "transmog", "wait" (still choosing) or "out"
-- (not in this roll); anything else reads as still choosing. -> r, g, b
function Th.Pick(state)
    local c = P[PICK_COLOR[state] or "faint"]
    return c[1], c[2], c[3]
end

local function resolveAccent()
    if ns.Get("accent") == "eui" then
        local r, g, b = euiCall("GetAccentColor")
        if type(r) == "number" then return { r, g, b, 1 } end
    end
    local _, file = UnitClass("player")
    if file and rawClassColor(file) then
        local r, g, b = Th.ClassColor(file)
        return { r, g, b, 1 }
    end
    local r, g, b = ns.Color.Lift(P.panel, P.text, DEFAULT_ACCENT, 4.5)
    return { r, g, b, 1 }
end

local function resolveFonts()
    local path = euiCall("GetFont")
    if type(path) ~= "string" or path == "" then path = REGULAR_FALLBACK end
    fonts.regular = path
    -- EllesmereUI ships "Expressway Bold.ttf" next to "Expressway.TTF".
    local dir = path:match("^(.*[\\/])[Ee]xpressway%.[Tt][Tt][Ff]$")
    fonts.bold = dir and (dir .. "Expressway Bold.ttf") or path
end

function Th.Refresh()
    local pr, pg, pb, pa = euiCall("GetPanelColor")
    local base
    if type(pr) == "number" then
        base = { pr, pg, pb, type(pa) == "number" and pa or 1 }
    else
        base = copy(DEFAULT_PANEL)
    end
    for name, dL in pairs(DERIVE) do
        P[name] = ns.Color.Shift(base, dL, name == "sky" and 1.6 or 1)
    end
    P.bg[4] = base[4]
    P.sidebar[4] = math.min(1, base[4] + 0.05)
    P.panel[4] = 0.98
    P.footer[4], P.panelAlt[4], P.sky[4] = 1, 1, 1
    for name, c in pairs(FIXED) do P[name] = copy(c) end

    -- Class colours (lifted on the panel) and item qualities (brightened on the window
    -- background) are worked out again for the new grounds.
    for k in pairs(classCache) do classCache[k] = nil end
    for k in pairs(qualityCache) do qualityCache[k] = nil end
    P.accent = resolveAccent()
    local dark = { 0.051, 0.051, 0.059, 1 }
    P.onAccent = ns.Color.Contrast(P.text, P.accent) > ns.Color.Contrast(dark, P.accent) and copy(P.text) or dark
    local a = P.accent
    P.focus = { a[1], a[2], a[3], 0.8 }         -- a focused control's border
    P.accentLine = { a[1], a[2], a[3], 0.55 }   -- accent hairlines
    P.accentWash = { a[1], a[2], a[3], 0.13 }   -- haze, highlights
    P.accentBorder = { a[1], a[2], a[3], 0.32 }
    P.edge = { 0, 0, 0, 0.75 }                  -- 1 px outside every window

    resolveFonts()
    ns.Fire("LOOKS_CHANGED")
end

function Th.Color(name)
    local c = P[name] or P.text
    return c[1], c[2], c[3], c[4]
end

function Th.Accent()
    return P.accent[1], P.accent[2], P.accent[3]
end

-- "ffrrggbb" for |c escapes.
function Th.Hex(name)
    local c = P[name] or P.text
    return ns.Color.Hex(c[1], c[2], c[3])
end

-- -> path, size, flags
function Th.Font(role)
    local spec = ROLES[role] or ROLES.sub
    return fonts[spec[1]], spec[2], ""
end

-- The roles whose text carries the mockup's shadow (.ts): the window's title,
-- an item's name, a player's name and the YOU tag after it. Other text has none.
local SHADOWED = { title = true, item = true, row = true, you = true }

-- A 1 px shadow straight under the text, black at 60 % (the mockup's
-- text-shadow: 0 1px 0 rgba(0,0,0,.6)), or none.
function Th.Shadow(fs, on)
    fs:SetShadowOffset(0, on and -1 or 0)
    fs:SetShadowColor(0, 0, 0, on and 0.6 or 0)
end

-- Font, no outline (EllesmereUI's no-outline look), and the shadow where its
-- role has one. `size`, given, is a size the roles lack: the role's file at
-- that size, a detail without the role's shadow (a subtitle's bold 11, the
-- count pill). A bold file the client cannot load falls back to the regular font.
function Th.ApplyFont(fs, role, size)
    local path, own, flags = Th.Font(role)
    size = size or own
    if not fs:SetFont(path, size, flags) then
        if not fs:SetFont(fonts.regular, size, flags) then fs:SetFont(REGULAR_FALLBACK, size, flags) end
    end
    Th.Shadow(fs, SHADOWED[role] == true and size == own)
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
Th.Refresh()

ns.On("PLAYER_LOGIN", function() Th.Refresh() end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == "accent" then Th.Refresh() end
end)

if EllesmereUI and EllesmereUI.RegisterSkin then
    pcall(EllesmereUI.RegisterSkin, "Tutti", function(skin)
        S = skin
        if S.OnLooksChanged then S.OnLooksChanged(function() Th.Refresh() end) end
        Th.Refresh()
    end)
end
