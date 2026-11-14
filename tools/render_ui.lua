-------------------------------------------------------------------------------
--  Tutti dev tool: draws what the addon built inside the fake client as an HTML
--  page, so the real window can be put next to the approved mockup
--  (docs/mockup/tutti-mockup.html, same state) without the game, and so the
--  listing's screenshots (tools/make_listing.py) and animations
--  (tools/make_gifs.py) show the real window. Every visible texture and font
--  string under the addon's frames is placed from its resolved anchors, with its
--  colour, tint, texture crop, rotation, gradient, font, size, alpha, scale and
--  draw order. Text is measured with the real font (the page's fonts/*.ttf,
--  read here: advances and kerning), so whatever the addon lays out from a
--  measured width sits where the client would put it.
--
--  Usage (from the addon folder):
--    luajit tools/render_ui.lua <out.html> <scene> [eui]
--        one page: the scene's state
--    luajit tools/render_ui.lua <out-prefix> <film>
--        a film: the client plays a scenario in steps of 1/15 s and each step is a page,
--        <out-prefix>-0001.html, -0002.html, ..., and <out-prefix>.json says how many, the frame
--        rate and where the window's top-left corner rests (a camera that keeps still needs it)
--  scenes (the mockup's states): pick rolling winner youwon closing recent settings big;
--  for the listing: glow (the player's win while the icon's ring glows and the shine crosses)
--  films (the listing's animations): drop (a boss drop, from the window rising to its closing),
--  click (the player rolls Need from the card), won (the player wins)
--  "eui" as the third argument sets the accent to EllesmereUI's, not the class colour.
--  Media must be converted first: python3 -I tools/tga2png.py <render-dir>
--  The page expects, next to it (the mockup assets are in docs/mockup/assets):
--    media/            written by tools/tga2png.py
--    fonts/expressway.ttf, fonts/expressway-bold.ttf   (read here too, to measure text)
--    class/class-<class>.png     the nine class icons
--    icons/<key>.png             the scenes' item icons: axe gloves treads orb robes rope grips
--                                (icon-dualblade.png is the axe, icon-shapers.png the gloves, the
--                                others go by their names)
--    backdrop.jpg                the mockup's screenshot (bd-dalaran.jpg there, renamed). Private: drawn
--                                only when a page asks for it (?bg=backdrop.jpg), to compare with the
--                                mockup; never in a public image. A page asks for no backdrop by default
--    icon.png                    the project icon, for the hero banner only
--    bg-*.jpg                    the listing's generated backdrops (?bg=)
--  Serve the dir over http (the fonts need it). ?bg=backdrop.jpg puts the mockup's backdrop behind
--  the window (to compare with the mockup); ?shot=1&scale=2&bg=<image> frames the window for the
--  listing's shots and films (see the script at the end).
--
--  The scenes and films play the mockup's boss drop through the fake client's real
--  events (START_LOOT_ROLL, the loot history, the player's clicks) with R30's made-up
--  cast: the player Maelis Ashvale (druid), Orlen Brightmoor (paladin), Brisé
--  Tidewater (shaman), Corvel Duskmantle (mage), Kestrel Ironmark (warrior). The
--  items are the mockup's, real Forever items (game data). Each scene's and film's
--  comment says what it shows. The effects draw as the client shows them at that
--  moment: alphas, a frame's scale (the crown's pop, a pressed button), a text's own
--  scale (a number's landing bump), widths and offsets (the wash, the shine), and
--  the dots' pulse (an animation group, played here from the clock). A film's cursor
--  is the page's, not the addon's: it shows where the player's mouse is. There is no
--  letter spacing.
-------------------------------------------------------------------------------
package.path = "./?.lua;" .. package.path
local T = dofile("tests/harness.lua")

local out, sceneName, variant = arg[1] or "render.html", arg[2] or "pick", arg[3]
math.randomseed(14) -- a spinning number's random faces: the same on every run
local EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local ICON = "Interface\\Icons\\render_" -- a scene item's texture: ICON .. key, drawn as icons/<key>.png
local ENC = 9                            -- the encounter ID of the scenes' loot history
local BIS_RANK = {}                      -- item ID -> rank on the player's NaowhForever list

local CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }

-------------------------------------------------------------------------------
--  The real font's advances (cmap format 4, hmtx, kern format 0), to measure text as the client does
-------------------------------------------------------------------------------
local function readFont(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    local function u16(o) local a, b = data:byte(o + 1, o + 2); return a * 256 + b end
    local function s16(o) local v = u16(o); return v >= 32768 and v - 65536 or v end
    local function u32(o) return u16(o) * 65536 + u16(o + 2) end
    local tables = {}
    for i = 0, u16(4) - 1 do
        local rec = 12 + 16 * i
        tables[data:sub(rec + 1, rec + 4)] = u32(rec + 8)
    end
    local font = { upem = u16(tables.head + 18), kern = {} }
    local metrics, hmtx = u16(tables.hhea + 34), tables.hmtx
    function font.advance(glyph) return u16(hmtx + 4 * math.min(glyph, metrics - 1)) end
    local sub
    for i = 0, u16(tables.cmap + 2) - 1 do
        local rec = tables.cmap + 4 + 8 * i
        if u16(rec) == 3 and u16(rec + 2) == 1 then sub = tables.cmap + u32(rec + 4) end
    end
    local segs = u16(sub + 6) / 2
    local ends, starts = sub + 14, sub + 16 + 2 * segs
    local deltas, ranges = sub + 16 + 4 * segs, sub + 16 + 6 * segs
    function font.glyph(cp)
        for i = 0, segs - 1 do
            if cp <= u16(ends + 2 * i) then
                local first = u16(starts + 2 * i)
                if cp < first then return 0 end
                local delta, range = u16(deltas + 2 * i), u16(ranges + 2 * i)
                if range == 0 then return (cp + delta) % 65536 end
                local g = u16(ranges + 2 * i + range + 2 * (cp - first))
                return g == 0 and 0 or (g + delta) % 65536
            end
        end
        return 0
    end
    if tables.kern then
        local at = tables.kern + 4
        for _ = 1, u16(tables.kern + 2) do
            local length, coverage = u16(at + 2), u16(at + 4)
            if math.floor(coverage / 256) == 0 and coverage % 2 == 1 then -- format 0, horizontal
                for p = 0, u16(at + 6) - 1 do
                    local pair = at + 14 + 6 * p
                    font.kern[u16(pair) * 65536 + u16(pair + 2)] = s16(pair + 4)
                end
            end
            at = at + length
        end
    end
    return font
end

-- The code points of a UTF-8 string.
local function codepoints(s)
    local list, i = {}, 1
    while i <= #s do
        local c = s:byte(i)
        local n = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
        local cp = n == 1 and c or c % (2 ^ (7 - n))
        for k = 1, n - 1 do cp = cp * 64 + (s:byte(i + k) or 0x80) % 64 end
        list[#list + 1] = cp
        i = i + n
    end
    return list
end

local dir = out:match("^(.*)[/\\]") or "."
local FONTS = {
    regular = readFont(dir .. "/fonts/expressway.ttf"), bold = readFont(dir .. "/fonts/expressway-bold.ttf"),
}
if not (FONTS.regular and FONTS.bold) then
    io.stderr:write("render_ui: no fonts/expressway*.ttf next to the page: text keeps the fake client's width guess\n")
end

-- How wide `text` is in `fontPath` at `size`, in px: the glyphs' advances and the kerning between them.
local function measure(text, fontPath, size)
    local font = (fontPath or ""):find("Bold") and FONTS.bold or FONTS.regular
    local width, last = 0, nil
    for _, cp in ipairs(codepoints(text)) do
        local glyph = font.glyph(cp)
        width = width + font.advance(glyph) + (last and font.kern[last * 65536 + glyph] or 0)
        last = glyph
    end
    return width * size / font.upem
end

-------------------------------------------------------------------------------
--  The client
-------------------------------------------------------------------------------
-- The fake's animation groups do nothing. These keep their Alpha steps and when they began to play, so a page
-- drawn at any moment shows an animated region at its alpha then (the dots' pulse, `pulse` in UI/Card.lua). As in
-- the client, a playing Alpha animation sets the region's alpha; the steps run one after the other by their order.
local function recordAnimations(G, W)
    local Object = getmetatable(G.UIParent)
    function Object:CreateAnimationGroup()
        local owner = self
        local group = { owner = owner, steps = {}, playing = false, scripts = {} }
        function group:CreateAnimation(kind)
            local step = { kind = kind, from = 1, to = 1, duration = 0, order = 1 }
            function step:SetFromAlpha(v) self.from = v end
            function step:SetToAlpha(v) self.to = v end
            function step:SetDuration(v) self.duration = v end
            function step:SetOrder(v) self.order = v end
            setmetatable(step, { __index = function() return function() end end })
            group.steps[#group.steps + 1] = step
            return step
        end
        local function fire(name) local fn = group.scripts[name]; if fn then fn(group) end end
        function group:Play() self.playing, self.started = true, W.clock; fire("OnPlay") end
        function group:Stop() self.playing = false; fire("OnStop") end
        function group:Finish() self.playing = false; fire("OnFinished") end
        function group:IsPlaying() return self.playing end
        function group:SetScript(name, fn) self.scripts[name] = fn end
        function group:SetLooping(mode) self.looping = mode end
        function group:SetToFinalAlpha() end
        owner._groups = owner._groups or {}
        owner._groups[#owner._groups + 1] = group
        return group
    end
end

local G, W, ns = T.load({
    -- The mockup's colours: EllesmereUI's panel #141414 at 93 %, its accent #00cfff.
    eui = { font = EXPRESSWAY, accent = { 0, 0.81, 1 }, panel = { 20 / 255, 20 / 255, 20 / 255, 0.93 } },
    setup = function(G, W)
        recordAnimations(G, W)
        W.player.name = "Maelis Ashvale" -- R30: the player, a druid (the fake's own player is one)
        -- The page is "real size": a UI unit is a screen pixel, as at a pixel-perfect UI scale (768 / 1080), so a
        -- hairline (W.Pixel) is one unit. The fake's UIParent is 1920 x 1080 units: its screen is said to be
        -- 768 pixels high to match.
        G.GetPhysicalScreenSize = function() return 1920 * 768 / 1080, 768 end
        if FONTS.regular and FONTS.bold then
            local plain = W.plain
            function W.textWidth(fs)
                local font = fs._font
                return font and measure(plain(fs._text or ""), font[1], font[2]) or 0
            end
        end
        -- Class icons as the game draws them (atlas classicon-<class>); the page maps them to class/class-<class>.png.
        for _, class in ipairs(CLASSES) do W.atlases["classicon-" .. class] = {} end
        W.instance = true -- inside an instance, so Recent's place is the dungeon ("Stonewatch Keep")
        -- NaowhForever's BiS list, as the card's badge asks it (Core/Integrations.lua). No RankColor: gold.
        G.NaowhForever = { BiS = {
            Alerts = {
                On = function() return true end,
                Rank = function(link) return BIS_RANK[tonumber(link:match("item:(%d+)"))] end,
                Wanted = function() return true end,
            },
            Settings = { Get = function(key) return key == "bisAlertBadge" end },
        } }
    end,
})

-------------------------------------------------------------------------------
--  Scene toolkit: the cast and the items, and the calls a scene makes
-------------------------------------------------------------------------------
local ST = G.Enum.EncounterLootDropRollState
local STATE = { need = ST.NeedMainSpec, greed = ST.Greed, transmog = ST.Transmog, pass = ST.Pass, wait = ST.NoRoll }

-- R30's party in party1..party4 order; the player is last in a party, as the party frames show it.
local PARTY = {
    { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
    { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
    { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
    { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
}
-- The same five as the loot history names them (full name, GUID, class file), by the key a scene's picks use.
local ME = { name = W.player.name, guid = W.player.guid, classFile = "DRUID", isSelf = true }
local WHO = {
    paladin = { name = PARTY[1].name, guid = PARTY[1].guid, classFile = "PALADIN" },
    shaman = { name = PARTY[2].name, guid = PARTY[2].guid, classFile = "SHAMAN" },
    mage = { name = PARTY[3].name, guid = PARTY[3].guid, classFile = "MAGE" },
    warrior = { name = PARTY[4].name, guid = PARTY[4].guid, classFile = "WARRIOR" },
    me = ME,
}
local ORDER = { "paladin", "shaman", "mage", "warrior", "me" }

-- The mockup's seven items, all rare, ilvl 33 (real Forever items: their names are game data). `icon` is the
-- page's icons/<key>.png; classID / subclassID / equipLoc give the card's label ("Two-Hand Axe", ...).
local ITEMS = {
    axe = { id = 273046, name = "Guardian's Dualblade", classID = 2, subclassID = 1, equipLoc = "INVTYPE_2HWEAPON" },
    gloves = { id = 273054, name = "Cartilage Shapers", classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND" },
    treads = { id = 18002, name = "Manascale Treads", classID = 4, subclassID = 3, equipLoc = "INVTYPE_FEET" },
    orb = { id = 18003, name = "Ponderous Orb", classID = 4, subclassID = 0, equipLoc = "INVTYPE_HOLDABLE" },
    robes = { id = 18004, name = "Violet Sorcerer's Robes", classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE" },
    rope = { id = 18005, name = "Blightleaf Rope", classID = 4, subclassID = 1, equipLoc = "INVTYPE_WAIST" },
    grips = { id = 18006, name = "Ephemeral Grips", classID = 4, subclassID = 1, equipLoc = "INVTYPE_HAND" },
}
for key, item in pairs(ITEMS) do
    item.key, item.ilvl = key, 33
    item.link, item.texture = W.itemLink(item.id, item.name, 3), ICON .. key
    W.items[item.id] = { name = item.name, link = item.link, quality = 3, ilvl = item.ilvl, classID = item.classID,
        subclassID = item.subclassID, equipLoc = item.equipLoc, texture = item.texture }
end
BIS_RANK[ITEMS.gloves.id] = 1 -- the gloves carry the BiS star, as the mockup's do

local function party() W.setGroup(PARTY) end

-- Time passes, in quarter seconds (so the clock stays exact and "54s" is not "54.000000001s").
local function wait(seconds)
    for _ = 1, math.floor(seconds * 4 + 0.5) do W.advance(0.25) end
end

-- The game starts a roll for the player; `over` changes the roll's fields (canNeed, reasonNeed, ...).
local function startRoll(rollID, item, over)
    local spec = { link = item.link, name = item.name, texture = item.texture, quality = 3, bop = true }
    for k, v in pairs(over or {}) do spec[k] = v end
    W.addRoll(rollID, spec)
end

local function cardOf(rollID)
    for _, card in ipairs(ns.Rolls.Cards()) do
        if card.rollID == rollID then return card end
    end
    error("no card for roll " .. rollID)
end

-- The player clicks a button on the card; the game then ends their part of the roll from inside RollOnLoot.
local function choose(rollID, choice)
    local view = G.TuttiFrame.views[cardOf(rollID)]
    local button = view and view.buttons[choice]
    assert(button and button:IsVisible(), "render_ui: no " .. choice .. " button on roll " .. rollID)
    button:Click()
    W.fire("CANCEL_LOOT_ROLL", rollID)
end

-- The loot history's drop for an item. picks: [who] = "need" | "greed" | "transmog" | "pass" | "wait", or
-- { state, roll } with the number the game has given by then. A key left out is not in the roll.
-- opts.winner is the key of the winner; opts.who / opts.order replace the party (the raid scene does).
local function setDrop(item, key, picks, opts)
    opts = opts or {}
    local who, order = opts.who or WHO, opts.order or ORDER
    local infos, mine = {}, "wait"
    for _, k in ipairs(order) do
        local pick = picks[k]
        if pick ~= nil then
            local state, roll = pick, nil
            if type(pick) == "table" then state, roll = pick[1], pick[2] end
            local w = who[k]
            infos[#infos + 1] = { playerName = w.name, playerGUID = w.guid, playerClass = w.classFile,
                isSelf = w.isSelf == true, state = STATE[state], roll = roll, isWinner = k == opts.winner }
            if w.isSelf then mine = state end
        end
    end
    local info = { lootListKey = key, itemHyperlink = item.link, playerRollState = STATE[mine], isTied = false,
        allPassed = opts.allPassed == true, rollInfos = infos, duration = 60000,
        startTime = opts.startTime or G.C_LootHistory.GetLootHistoryTime() }
    for _, entry in ipairs(infos) do
        if entry.isWinner then info.winner = entry end
    end
    W.setDrop(ENC, key, info)
end

-------------------------------------------------------------------------------
--  The boss drop of the mockup's "Play a boss drop", in the stretches the scenes stop at
--    t = 0    both items drop: the axe (a druid cannot Need it) and the gloves (BiS rank 1)
--    t = 8    the player clicks Greed on the axe
--    t = 17   the game decides the axe: Orlen wins with Need 19
--    t = 21   the axe folds under "DONE" (4 s after its decision, the gloves still being open)
--    t = 26   the player clicks Need on the gloves
--    t = 30   the game decides the gloves: the player wins with Need 87 (Brisé rolled 52)
-------------------------------------------------------------------------------
local drops = {} -- item key -> the drop's start on the history's clock

local function axeDecided()
    party()
    startRoll(1, ITEMS.axe, { canNeed = false, reasonNeed = 1 })
    startRoll(2, ITEMS.gloves)
    drops.axe, drops.gloves = G.C_LootHistory.GetLootHistoryTime(), G.C_LootHistory.GetLootHistoryTime()
    setDrop(ITEMS.axe, 1, { paladin = "need", shaman = "wait", mage = "pass", warrior = "wait", me = "wait" })
    setDrop(ITEMS.gloves, 2, { paladin = "wait", shaman = "need", mage = "pass", warrior = "wait", me = "wait" })
    wait(8)
    choose(1, "greed")
    setDrop(ITEMS.axe, 1, { paladin = "need", shaman = "greed", mage = "pass", warrior = "pass", me = "greed" },
        { startTime = drops.axe })
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = "need", mage = "pass", warrior = "pass", me = "wait" },
        { startTime = drops.gloves })
    wait(9)
    setDrop(ITEMS.axe, 1, { paladin = { "need", 19 }, shaman = "greed", mage = "pass", warrior = "pass", me = "greed" },
        { winner = "paladin", startTime = drops.axe })
end

local function glovesDecided()
    axeDecided()
    wait(9) -- t = 26 (the axe folded at t = 21)
    choose(2, "need")
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = "need", mage = "pass", warrior = "pass", me = "need" },
        { startTime = drops.gloves })
    wait(4)
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = { "need", 52 }, mage = "pass", warrior = "pass",
        me = { "need", 87 } }, { winner = "me", startTime = drops.gloves })
end

-------------------------------------------------------------------------------
--  Scenes: the mockup's states of the same name (docs/mockup/tutti-mockup.html: SCENES, CAPTIONS, PLAY),
--  each taken with its effects at rest.
-------------------------------------------------------------------------------
local SCENES = {}

-- pick ("Your pick"): two items just dropped, both waiting on the player, 54 s left. Two cards with the accent
-- edge and three buttons; the axe's Need greyed out with the game's reason under the buttons (the mockup's
-- "your class can't use this" is a stand-in); the BiS star on the gloves; the count pill "2".
function SCENES.pick()
    party()
    startRoll(1, ITEMS.axe, { canNeed = false, reasonNeed = 1 })
    startRoll(2, ITEMS.gloves)
    setDrop(ITEMS.axe, 1, { paladin = "need", shaman = "wait", mage = "pass", warrior = "wait", me = "wait" })
    setDrop(ITEMS.gloves, 2, { paladin = "wait", shaman = "need", mage = "pass", warrior = "wait", me = "wait" })
    wait(6)
end

-- rolling ("Rolling"): the axe alone, everyone has picked but Kestrel; the player's Greed in their row; 38 s
-- left. One card without buttons, five rows in party order.
function SCENES.rolling()
    party()
    startRoll(1, ITEMS.axe, { canNeed = false, reasonNeed = 1 })
    setDrop(ITEMS.axe, 1, { paladin = "need", shaman = "greed", mage = "pass", warrior = "wait", me = "wait" })
    wait(20)
    choose(1, "greed")
    setDrop(ITEMS.axe, 1, { paladin = "need", shaman = "greed", mage = "pass", warrior = "wait", me = "greed" },
        { startTime = G.C_LootHistory.GetLootHistoryTime() - 20000 })
    wait(2)
end

-- winner ("Winner"): Orlen has won the axe (Need 19: the wash, the crown, the others faded, "Orlen won · Need
-- 19"); the gloves still wait on the player, 41 s left; the count pill "1".
function SCENES.winner()
    axeDecided()
    wait(2)
end

-- youwon ("You won"): the player wins the gloves (Need 87 over Brisé's 52, "You won · Need 87"); the axe has
-- folded under "DONE" ("Guardian's Dualblade → Orlen   Need 19"). The mockup's still is the moment before its
-- countdown starts (its PLAY begins it 2.7 s after the win); the window counts down from the decision, so the
-- scene has "Close after the last roll" on Never to show that state. "closing" shows the countdown.
function SCENES.youwon()
    ns.Set("closeAfter", 0)
    glovesDecided()
    wait(3)
end

-- closing ("Closing"): everything is decided, 3 s later: "closes in 7s" in the header and the accent line
-- under it at 70 %.
function SCENES.closing()
    glovesDecided()
    wait(3)
end

-- glow (the listing's "you won"): youwon's moment, taken while it plays. The gloves' numbers come first and land
-- (as /tutti demo plays them: the numbers, then the decision); 0.45 s after the decision the icon's ring is at the
-- peak of its first glow, the shine is crossing the card and the crown is still popping.
function SCENES.glow()
    ns.Set("closeAfter", 0)
    axeDecided()
    wait(9)
    choose(2, "need")
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = "need", mage = "pass", warrior = "pass", me = "need" },
        { startTime = drops.gloves })
    wait(3)
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = { "need", 52 }, mage = "pass", warrior = "pass",
        me = { "need", 87 } }, { startTime = drops.gloves })
    wait(1.25)
    setDrop(ITEMS.gloves, 2, { paladin = "greed", shaman = { "need", 52 }, mage = "pass", warrior = "pass",
        me = { "need", 87 } }, { winner = "me", startTime = drops.gloves })
    for _ = 1, 9 do W.advance(0.05) end
end

-- recent ("Recent rolls"): the session's results, the axe's line open: the two real results of the boss drop
-- and five older ones made up here, "STONEWATCH KEEP · TODAY", seven 38 px lines, the footer.
function SCENES.recent()
    glovesDecided()
    local now = G.time()
    local recent = ns.DB.recent -- the two real results, newest first
    local function made(item, who, state, roll, minutes)
        local w = who and WHO[who]
        local winner = w and { name = ns.Group.FirstName(w.name), class = w.classFile, state = state, roll = roll }
        return { link = item.link, name = item.name, icon = item.texture, quality = 3, place = W.instanceName,
            at = now - minutes * 60, allPassed = who == nil, ended = false, rows = {}, winner = winner }
    end
    recent[1].at, recent[2].at = now - 5, now - 70
    table.insert(recent, made(ITEMS.treads, "shaman", "need", 74, 6))
    table.insert(recent, made(ITEMS.orb, "shaman", "need", 41, 9))
    table.insert(recent, made(ITEMS.robes, "mage", "need", 88, 14))
    table.insert(recent, made(ITEMS.rope, nil, nil, nil, 17))
    table.insert(recent, made(ITEMS.grips, "warrior", "greed", 45, 22))
    ns.Fire("HISTORY_CHANGED")
    ns.UI.Open("recent")
    ns.Recent.view.lines[2]:Click() -- the axe's line
    wait(1)
end

-- settings ("Settings"): the five rows with their defaults (the accent EllesmereUI's with the third argument
-- "eui", as the mockup's accent switch shows it).
function SCENES.settings()
    if variant == "eui" then ns.Set("accent", "eui") end
    ns.UI.Open("settings")
    wait(1)
end

-- big ("Bigger group"): a raid of 20, one card, 33 s left. Rows for the two Needs and the two Greeds and for the
-- player (who passed), then "13 passed · 2 choosing". The raid's names are made up here (Corvel is R30's).
function SCENES.big()
    local named = {
        [1] = { "Wynnfield Sorrow", "MAGE" }, [2] = { "Tova Greymantle", "SHAMAN" }, [3] = { PARTY[3].name, "MAGE" },
        [4] = { "Halvard Pyke", "WARLOCK" }, [5] = { "Ismene Dawnhollow", "PRIEST" },
    }
    local firsts = { "Alder", "Brisa", "Cael", "Dessa", "Edrin", "Fenna", "Garrow", "Hollis", "Isra", "Joren",
        "Lark", "Linnea", "Marek", "Nerys" }
    local lasts = { "Marsh", "Vale", "Thorne", "Ridley", "Holt", "Wren", "Cobb", "Ames", "Dunn", "Lowe", "Pell",
        "Sedge", "Tarn", "Voss" }
    local raid, who, order, picks, n = {}, {}, {}, {}, 0
    local rolled = { [1] = "need", [2] = "greed", [3] = "need", [5] = "greed", [4] = "wait", [19] = "wait" }
    for slot = 1, 20 do
        local key = "r" .. slot
        order[slot] = key
        if slot == 6 then
            raid[slot] = { unit = "raid6", isPlayer = true }
            who[key], picks[key] = ME, "pass"
        else
            local name, class = named[slot] and named[slot][1], named[slot] and named[slot][2]
            if not name then
                n = n + 1
                name, class = firsts[n] .. " " .. lasts[n], CLASSES[n % #CLASSES + 1]:upper()
            end
            local guid = slot == 3 and PARTY[3].guid or string.format("Player-1-%04d", 100 + slot)
            raid[slot] = { unit = "raid" .. slot, name = name, classFile = class, guid = guid }
            who[key], picks[key] = { name = name, guid = guid, classFile = class }, rolled[slot] or "pass"
        end
    end
    W.setGroup(raid, { raid = true })
    startRoll(1, ITEMS.robes)
    choose(1, "pass")
    setDrop(ITEMS.robes, 1, picks, { who = who, order = order })
    wait(27)
end

-------------------------------------------------------------------------------
--  Drawing: the page for the client as it is now
-------------------------------------------------------------------------------
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8 }
local SH = 1080

-- How much bigger than its own units an object draws: its scale times its parents' (a popping crown, a pressed
-- button's body).
local function scaleOf(o)
    local s = 1
    while o and not o._isRoot do
        s = s * (o._scale or 1)
        o = o._parent
    end
    return s
end

-- Where an object is on the screen, { left, bottom, width, height }: the fake client's W.rect, with the scale the
-- client applies (an object's size and its anchor offsets are in its own scaled units). With every scale 1 it is
-- W.rect.
local function pointXY(rect, p)
    local l, b, w, h = rect[1], rect[2], rect[3], rect[4]
    local x = p:find("LEFT") and l or (p:find("RIGHT") and l + w) or l + w / 2
    local y = p:find("TOP") and b + h or (p:find("BOTTOM") and b) or b + h / 2
    return x, y
end
local resolving = {}
local function rectOf(o)
    if o._isRoot then return { 0, 0, 1920, 1080 } end
    local s = scaleOf(o)
    -- A scroll child hangs from its scroll frame's top-left, moved by the scroll.
    if o._scrollParent and #o._points == 0 then
        local sp = o._scrollParent
        local p, h = rectOf(sp), (o._h or 0) * s
        return { p[1], p[2] + p[4] - h + (sp._vscroll or 0) * scaleOf(sp), (o._w or 0) * s, h }
    end
    if resolving[o] then return { 0, 0, (o._w or 0) * s, (o._h or 0) * s } end
    resolving[o] = true
    local L, R, TP, BT, CX, CY
    for _, pt in ipairs(o._points) do
        local x, y = pointXY(rectOf(pt[2]), pt[3])
        x, y = x + (pt[4] or 0) * s, y + (pt[5] or 0) * s
        local p = pt[1]
        if p:find("LEFT") then L = x elseif p:find("RIGHT") then R = x else CX = x end
        if p:find("TOP") then TP = y elseif p:find("BOTTOM") then BT = y else CY = y end
    end
    resolving[o] = nil
    local w = (L and R) and (R - L) or (o._w or 0) * s
    local h = (TP and BT) and (TP - BT) or (o._h or 0) * s
    -- A font string without a set width is as wide as its text, as in the client.
    if o._type == "FontString" then
        local size = (o._font and o._font[2]) or 12
        if not (L and R) and w == 0 then w = W.textWidth(o) * s end
        if not (TP and BT) and h == 0 then
            local lines = 1
            if o._wrap ~= false and ((L and R) or (o._w or 0) > 0) and w > 0 then
                lines = math.max(1, math.ceil(W.textWidth(o) * s / w))
            end
            h = lines * (size + 2) * s
        end
    end
    local l = L or (R and R - w) or (CX and CX - w / 2) or 0
    local b = BT or (TP and TP - h) or (CY and CY - h / 2) or 0
    return { l, b, w, h }
end

local function strataOf(f)
    while f do
        if f._strata then return STRATA[f._strata] or 3 end
        f = f._parent
    end
    return 3
end

-- The alpha a playing animation group gives the object now (its Alpha steps one after the other, looping or held at
-- the end), or nil when none plays.
local function animatedAlpha(o)
    for _, group in ipairs(o._groups or {}) do
        if group.playing and #group.steps > 0 then
            local steps, total = {}, 0
            for i, step in ipairs(group.steps) do
                steps[i] = step
                total = total + step.duration
            end
            table.sort(steps, function(a, b) return a.order < b.order end)
            if total > 0 then
                local t = W.clock - group.started
                t = group.looping == "REPEAT" and t % total or math.min(t, total)
                for i, step in ipairs(steps) do
                    if t <= step.duration or i == #steps then
                        local u = step.duration > 0 and math.min(t / step.duration, 1) or 1
                        return step.from + (step.to - step.from) * u
                    end
                    t = t - step.duration
                end
            end
        end
    end
end

local function alphaOf(o)
    local a = 1
    while o do
        a = a * (animatedAlpha(o) or o._alpha or 1)
        o = o._parent
    end
    return a
end

-- The clipping box (left, bottom, right, top) of the frames above a region that clip their children.
local function clipOf(o)
    local f, box = o._parent, nil
    while f do
        if f._clips then
            local r = rectOf(f)
            local c = { r[1], r[2], r[1] + r[3], r[2] + r[4] }
            if box then
                box = { math.max(box[1], c[1]), math.max(box[2], c[2]), math.min(box[3], c[3]), math.min(box[4], c[4]) }
            else
                box = c
            end
        end
        f = f._parent
    end
    return box
end

local function rgba(c, a)
    return string.format("rgba(%d,%d,%d,%.3f)", (c[1] or 1) * 255 + 0.5, (c[2] or 1) * 255 + 0.5,
        (c[3] or 1) * 255 + 0.5, (c[4] or 1) * (a or 1))
end

local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

-- |cffrrggbb ... |r colour runs; links and inline textures lose their markup.
local function richText(text)
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    local html, pos, open = {}, 1, false
    while pos <= #text do
        local s, e, hex = text:find("|c%x%x(%x%x%x%x%x%x)", pos)
        local rs, re = text:find("|r", pos, true)
        if s and (not rs or s < rs) then
            html[#html + 1] = esc(text:sub(pos, s - 1))
            if open then html[#html + 1] = "</span>" end
            html[#html + 1] = '<span style="color:#' .. hex .. '">'
            open, pos = true, e + 1
        elseif rs then
            html[#html + 1] = esc(text:sub(pos, rs - 1))
            if open then html[#html + 1] = "</span>"; open = false end
            pos = re + 1
        else
            html[#html + 1] = esc(text:sub(pos))
            break
        end
    end
    if open then html[#html + 1] = "</span>" end
    return table.concat(html)
end

-- The page's file for a texture: the addon's media, a class icon (atlas classicon-<class>), an item icon
-- (a scene's Interface\Icons\render_<key>, or a numeric file ID), else nil (not drawn).
local function texturePath(r)
    if r._atlas then return "class/" .. r._atlas:gsub("classicon%-", "class-") .. ".png" end
    local tex = r._texture
    if type(tex) == "number" then return "icons/" .. tex .. ".png" end
    if type(tex) ~= "string" then return nil end
    local media = tex:match("^Interface\\AddOns\\Tutti\\Media\\(.+)$")
    if media then return "media/" .. media:gsub("\\", "/") .. ".png" end
    local icon = tex:match("^Interface\\Icons\\(.+)$")
    if icon then return "icons/" .. icon:gsub("^render_", ""):lower() .. ".png" end
end

-- A film's mouse pointer: { x, y }, its tip on the page (px from the stage's top-left), or nil while it is off the
-- page. An arrow drawn by the page, white with a dark edge, over everything; the addon draws no cursor.
local cursor
local POINTER = '<svg width="13" height="20" viewBox="0 0 13 20" style="position:absolute;left:%.2fpx;top:%.2fpx;'
    .. 'z-index:100000;overflow:visible;filter:drop-shadow(0 1px 1.5px rgba(0,0,0,.55))">'
    .. '<path d="M0.5,0.5 L0.5,15.6 L4.1,12.3 L6.6,18.4 L9.1,17.3 L6.7,11.5 L11.6,11.5 Z" fill="#fff" '
    .. 'stroke="#111" stroke-width="1" stroke-linejoin="round"/></svg>'

-- Writes the page for the client as it is now (`path`), and returns how many regions it drew. A hidden window
-- draws nothing: a film's frame before the window rises or after it has sunk. `home` is where the window's top-left
-- corner rests on the page (TUTTI_HOME, for a film's camera); a scene's is where it is.
local function draw(path, home)
    local items, seq = {}, 0
    local function visit(f)
        if not f:IsVisible() then return end
        local level = f._level or 1
        for _, r in ipairs(f._regions) do
            if r._shown ~= false then
                seq = seq + 1
                local layer = LAYERS[r._layer or "ARTWORK"] or 3
                items[#items + 1] = { r = r, z = { strataOf(f), level, layer, r._sub or 0, seq } }
            end
        end
        for _, c in ipairs(f._children) do visit(c) end
    end
    -- Every top-level frame of the addon (TuttiFrame, TuttiMenu).
    for _, root in ipairs(G.UIParent._children) do
        if root._name and root._name:find("^Tutti") then visit(root) end
    end
    table.sort(items, function(a, b)
        for k = 1, 5 do if a.z[k] ~= b.z[k] then return a.z[k] < b.z[k] end end
        return false
    end)

    local html = {}
    local function emit(div, clip, z)
        if clip then
            local inset = string.format("%.2fpx %.2fpx %.2fpx %.2fpx", SH - clip[4], 1920 - clip[3], clip[2], clip[1])
            html[#html + 1] = '<div style="position:absolute;left:0;top:0;width:1920px;height:1080px;z-index:' .. z
                .. ';clip-path:inset(' .. inset .. ')">' .. div .. "</div>"
        else
            html[#html + 1] = div
        end
    end

    for z, it in ipairs(items) do
        local r = it.r
        local a = alphaOf(r)
        if a > 0.001 then
            local rc = rectOf(r)
            local left, bottom, w, h = rc[1], rc[2], rc[3], rc[4]
            local top = SH - bottom - h
            local clip = clipOf(r)
            if r._type == "Texture" then
                if w > 0 and h > 0 then
                    local style = string.format("position:absolute;left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;"
                        .. "opacity:%.3f;", left, top, w, h, a)
                    if r._blend == "ADD" then style = style .. "mix-blend-mode:plus-lighter;" end
                    -- A crop given right to left or bottom to top mirrors the texture.
                    local tc = r._texcoord or { 0, 1, 0, 1 }
                    local flipX, flipY = tc[2] < tc[1], tc[4] < tc[3]
                    local turns = {}
                    -- SetRotation turns a texture about its centre, anticlockwise: CSS turns clockwise.
                    if r._rot and r._rot ~= 0 then turns[#turns + 1] = string.format("rotate(%.4frad)", -r._rot) end
                    if flipX or flipY then
                        turns[#turns + 1] = string.format("scale(%d,%d)", flipX and -1 or 1, flipY and -1 or 1)
                    end
                    if #turns > 0 then style = style .. "transform:" .. table.concat(turns, " ") .. ";" end
                    if r._color and r._gradient then
                        -- SetGradient(orientation, min, max): VERTICAL runs bottom to top, HORIZONTAL left to right.
                        local mn, mx = r._gradient[2], r._gradient[3]
                        local to = r._gradient[1] == "HORIZONTAL" and "to right" or "to top"
                        style = style .. string.format("background:linear-gradient(%s,%s,%s);", to,
                            rgba({ mn.r, mn.g, mn.b, mn.a }), rgba({ mx.r, mx.g, mx.b, mx.a }))
                    elseif r._color then
                        style = style .. "background:" .. rgba(r._color) .. ";"
                    else
                        local file = texturePath(r)
                        if file then
                            local l, rr = math.min(tc[1], tc[2]), math.max(tc[1], tc[2])
                            local t, b = math.min(tc[3], tc[4]), math.max(tc[3], tc[4])
                            local fw, fh = w / (rr - l), h / (b - t)
                            local size = string.format("%.2fpx %.2fpx", fw, fh)
                            local pos = string.format("%.2fpx %.2fpx", -l * fw, -t * fh)
                            if r._vertex and not r._atlas and file:find("^media/") then
                                -- a white glyph or shape tinted in code: the vertex colour, painted through the alpha
                                style = style .. "background:" .. rgba(r._vertex) .. ";"
                                    .. "-webkit-mask-image:url(" .. file .. ");-webkit-mask-size:" .. size
                                    .. ";-webkit-mask-position:" .. pos .. ";-webkit-mask-repeat:no-repeat;"
                            else
                                style = style .. "background-image:url(" .. file .. ");background-size:" .. size
                                    .. ";background-position:" .. pos .. ";background-repeat:no-repeat;"
                            end
                            if r._desat then style = style .. "filter:grayscale(1);" end
                        else
                            style = nil
                        end
                    end
                    if style then emit('<div style="' .. style .. 'z-index:' .. z .. '"></div>', clip, z) end
                end
            elseif r._type == "FontString" and r._text and r._text ~= "" then
                local font = r._font or { "", 12 }
                -- Its own scale (a number's landing bump) and its frames' (a pressed button's word).
                local s = scaleOf(r)
                local size = font[2] * (r._textScale or 1) * s
                local family = font[1]:find("Bold") and "ExpresswayBold"
                    or (font[1]:find("Expressway") and "Expressway" or "sans-serif")
                local color = r._textColor and rgba(r._textColor) or "#fff"
                local offset, tint = r._shadow, r._shadowColor or { 0, 0, 0, 1 }
                local shadow = ""
                if offset and (offset[1] ~= 0 or offset[2] ~= 0) and (tint[4] or 1) > 0 then
                    shadow = string.format("text-shadow:%gpx %gpx 0 %s;", offset[1] * s, -offset[2] * s, rgba(tint))
                end
                -- The text's box as the client resolves it (with the real font's widths). Its height is kept where
                -- the addon gave one (SetHeight, or anchors at its top and bottom): one line is centred in it, as the
                -- client centres a font string's text. A single line anchored by its middle, with the fake's guess
                -- for a height, gets the page's own line box round the same middle (1.4 times its size, as the
                -- mockup's text where it sets no line height): Chrome rounds a line's half-leading, so the same box
                -- puts it on the same half pixel as the mockup's. Wrapped text keeps the fake's line pitch (size + 2).
                local hasL, hasR, hasT, hasB = false, false, false, false
                for _, p in ipairs(r._points) do
                    hasL = hasL or p[1]:find("LEFT") ~= nil
                    hasR = hasR or p[1]:find("RIGHT") ~= nil
                    hasT = hasT or p[1]:find("TOP") ~= nil
                    hasB = hasB or p[1]:find("BOTTOM") ~= nil
                end
                local ownW = (hasL and hasR) or (r._w and r._w > 0)
                local ownH = (hasT and hasB) or (r._h and r._h > 0)
                local lines = (r._wrap ~= false) and math.max(1, math.floor(h / (size + 2 * s) + 0.5)) or 1
                local boxTop, boxH, pitch = top, h, h / lines
                if not ownH and lines == 1 and not hasT and not hasB then
                    boxH = size * 1.4
                    boxTop, pitch = top + h / 2 - boxH / 2, boxH
                end
                local style = string.format("position:absolute;font-family:%s;font-size:%.2fpx;line-height:%.2fpx;"
                    .. "color:%s;%sopacity:%.3f;z-index:%d;top:%.2fpx;height:%.2fpx;text-align:%s;", family, size,
                    pitch, color, shadow, a, z, boxTop, boxH, (r._justifyH or "LEFT"):lower())
                -- Across: placed by layout, not by a transform, so the text keeps to the pixel grid as the mockup's:
                -- its own width where it has one, else from its anchored side (only a centred one shifts by half).
                if ownW then
                    style = style .. string.format("left:%.2fpx;width:%.2fpx;", left, w)
                    if r._wrap == false then
                        -- Cut with an ellipsis only where the text is wider than its box (the client cuts it there).
                        local cut = W.textWidth(r) * s > w + 0.5
                        style = style .. (cut and "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"
                            or "white-space:nowrap;")
                    else
                        style = style .. "white-space:normal;overflow-wrap:anywhere;"
                    end
                elseif hasR then
                    style = style .. string.format("right:%.2fpx;white-space:pre;", 1920 - (left + w))
                elseif hasL or #r._points == 0 then
                    style = style .. string.format("left:%.2fpx;white-space:pre;", left)
                else
                    style = style .. string.format("left:%.2fpx;transform:translateX(-50%%);white-space:pre;",
                        left + w / 2)
                end
                emit('<div style="' .. style .. '">' .. richText(r._text):gsub("\n", "<br>") .. "</div>", clip, z)
            end
        end
    end
    if cursor then html[#html + 1] = string.format(POINTER, cursor.x, cursor.y) end

    local win = rectOf(G.TuttiFrame)
    home = home or { x = win[1], y = SH - win[2] - win[4] }
    local doc = [==[<!DOCTYPE html><html><head><meta charset="utf-8"><title>Tutti render</title><style>
@font-face{font-family:Expressway;src:url(fonts/expressway.ttf)}
@font-face{font-family:ExpresswayBold;src:url(fonts/expressway-bold.ttf)}
html,body{margin:0;background:#0b0b0c}
#stage{position:relative;width:1920px;height:1080px;overflow:hidden;background:none;
  -webkit-font-smoothing:antialiased;transform-origin:0 0}
</style></head><body><div id="stage">]==] .. table.concat(html, "\n") .. [==[</div>
<script>window.TUTTI_WIN={x:]==] .. win[1] .. [==[,y:]==] .. (SH - win[2] - win[4]) .. [==[,w:]==] .. win[3]
    .. [==[,h:]==] .. win[4] .. [==[};window.TUTTI_HOME={x:]==] .. home.x .. [==[,y:]==] .. home.y .. [==[};
(function(){
  // Listing shots (tools/make_listing.py) and film frames (tools/make_gifs.py). Parameters: w, h, scale, bg (a
  // generated backdrop; none without it), cx, cy, m (the side margin); layout=left|right|top puts the text on that
  // side and the window on the other; eyebrow, title, sub, pills (comma separated), accent, size, ty; hero=1 for
  // the banner, with tagline (and eyebrow). A film keeps its camera
  // still: wx, wy put the window's resting top-left corner (TUTTI_HOME) there on the page, and wh is the window
  // height the layout reckons with. In title, sub and tagline, | breaks the line and *word* takes the accent.
  var q = new URLSearchParams(location.search), st = document.getElementById('stage');
  if (!q.has('shot')) {
    // A page to compare with the mockup: a backdrop only when one is asked for (?bg=backdrop.jpg, the private
    // screenshot, for that comparison alone).
    if (q.has('bg')) st.style.background = 'url(' + q.get('bg') + ') 0 0/1920px 1080px';
    return;
  }
  var W = parseInt(q.get('w') || '1920'), H = parseInt(q.get('h') || '1080'), s = parseFloat(q.get('scale') || '2');
  var f = window.TUTTI_WIN, home = window.TUTTI_HOME;
  var layout = q.get('layout') || 'center', accent = q.get('accent') || '#ff7d0a';
  var M = q.has('m') ? parseFloat(q.get('m')) : 130, fw = f.w * s, fh = (q.has('wh') ? parseFloat(q.get('wh')) : f.h) * s;
  var cx = W / 2, cy = H / 2;
  if (layout === 'left') cx = W - M - fw / 2;
  if (layout === 'right') cx = M + fw / 2;
  if (layout === 'top') cy = H - 170 - fh / 2;
  if (q.has('cx')) cx = parseFloat(q.get('cx'));
  if (q.has('cy')) cy = parseFloat(q.get('cy'));
  document.documentElement.style.cssText = 'width:' + W + 'px;height:' + H + 'px;overflow:hidden';
  document.body.style.cssText = 'margin:0;position:relative;width:' + W + 'px;height:' + H + 'px;overflow:hidden;background:#0b0b0c' + (q.has('bg') ? ' url(' + q.get('bg') + ') center/cover no-repeat' : '');
  if (q.has('wx')) {
    var wx = parseFloat(q.get('wx')), wy = parseFloat(q.get('wy'));
    cx = wx + fw / 2;
    cy = wy + fh / 2;
    st.style.transform = 'translate(' + (wx - home.x * s) + 'px,' + (wy - home.y * s) + 'px) scale(' + s + ')';
  } else {
    st.style.transform = 'translate(' + (cx - (f.x + f.w / 2) * s) + 'px,' + (cy - (f.y + f.h / 2) * s) + 'px) scale(' + s + ')';
  }
  st.style.overflow = 'visible';
  st.style.zIndex = '2';

  function rgba(hex, a) {
    var n = parseInt(hex.slice(1), 16);
    return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')';
  }
  function esc(t) { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function rich(t) {
    return esc(t).split('|').join('<br>').replace(/\*([^*]+)\*/g, '<span style="color:' + accent + '">$1</span>');
  }
  function add(html, css) {
    var d = document.createElement('div');
    d.innerHTML = html;
    d.style.cssText = 'position:absolute;pointer-events:none;' + css;
    document.body.appendChild(d);
    return d;
  }
  if (!q.has('title') && !q.has('hero')) return;

  // The text side darkens so the copy reads on any backdrop; a soft glow in the
  // accent sits behind the window.
  var dir = layout === 'right' ? '270deg' : (layout === 'top' ? '180deg' : '90deg');
  add('', 'left:0;top:0;width:' + W + 'px;height:' + H + 'px;z-index:0;background:'
    + 'linear-gradient(' + dir + ',rgba(9,9,11,.88) 0%,rgba(9,9,11,.58) 38%,rgba(9,9,11,0) 66%),'
    + 'radial-gradient(ellipse at 50% 50%,rgba(0,0,0,0) 50%,rgba(0,0,0,.5) 100%)');
  var g = Math.max(fw, fh) * 0.85;
  add('', 'z-index:1;left:' + (cx - g) + 'px;top:' + (cy - g) + 'px;width:' + 2 * g + 'px;height:' + 2 * g + 'px;'
    + 'background:radial-gradient(circle,' + rgba(accent, 0.2) + ' 0%,' + rgba(accent, 0.07) + ' 38%,' + rgba(accent, 0) + ' 64%)');

  var center = layout === 'top';
  function eyebrow(t) {
    return '<div style="font-family:ExpresswayBold;font-size:22px;letter-spacing:4px;text-transform:uppercase;color:' + accent
      + ';display:flex;align-items:center;gap:16px' + (center ? ';justify-content:center' : '') + '">'
      + '<span style="width:36px;height:2px;background:' + accent + '"></span>' + esc(t) + '</div>';
  }
  var html = '';
  if (q.has('hero')) {
    html = eyebrow(q.get('eyebrow') || 'For WoW Forever')
      + '<div style="display:flex;align-items:center;gap:30px;margin-top:30px">'
      + '<img src="icon.png" style="width:118px;height:118px;border-radius:24px;box-shadow:0 0 0 1px rgba(255,255,255,.08),0 18px 40px rgba(0,0,0,.55)">'
      + '<div style="font-family:ExpresswayBold;font-size:118px;line-height:1;color:#f8f8f8;text-shadow:0 2px 0 rgba(0,0,0,.5)">Tutti</div></div>'
      + '<div style="font-family:Expressway;font-size:34px;line-height:1.35;color:#cacccf;margin-top:30px;text-shadow:0 1px 0 rgba(0,0,0,.6)">'
      + rich(q.get('tagline') || '') + '</div>';
  } else {
    if (q.has('eyebrow')) html += eyebrow(q.get('eyebrow'));
    html += '<div class="headline" style="font-family:ExpresswayBold;font-size:' + (q.get('size') || '94') + 'px;line-height:1.04;color:#f8f8f8;'
      + 'margin-top:24px;white-space:nowrap;display:inline-block;text-shadow:0 2px 0 rgba(0,0,0,.45)">' + rich(q.get('title')) + '</div>';
    if (q.has('sub')) {
      html += '<div style="font-family:Expressway;font-size:32px;line-height:1.38;color:#cacccf;margin-top:26px;max-width:660px;'
        + (center ? 'margin-left:auto;margin-right:auto;' : '') + 'text-shadow:0 1px 0 rgba(0,0,0,.6)">' + rich(q.get('sub')) + '</div>';
    }
    if (q.has('pills')) {
      html += '<div style="display:flex;flex-wrap:wrap;gap:12px;margin-top:36px;max-width:700px">'
        + q.get('pills').split(',').map(function (p) {
          return '<span style="font-family:Expressway;font-size:23px;color:#e9eaec;padding:10px 20px;border-radius:999px;'
            + 'background:rgba(255,255,255,.07);box-shadow:inset 0 0 0 1px rgba(255,255,255,.13)">' + esc(p.trim()) + '</span>';
        }).join('') + '</div>';
    }
  }
  var col = W - fw - 2 * M - 110;
  var css = 'z-index:3;';
  if (layout === 'right') css += 'right:' + M + 'px;top:50%;transform:translateY(-50%);width:' + col + 'px';
  else if (center) css += 'left:0;width:' + W + 'px;top:' + (q.get('ty') || '110') + 'px;text-align:center';
  else css += 'left:' + M + 'px;top:50%;transform:translateY(-50%);width:' + (q.has('hero') ? 900 : col) + 'px';
  var block = add(html, css);
  var head = block.querySelector('.headline');
  if (head && !center) {
    document.fonts.ready.then(function () {
      var size = parseFloat(head.style.fontSize);
      while (head.offsetWidth > col && size > 56) { size -= 2; head.style.fontSize = size + 'px'; }
    });
  }
})();
</script>
</body></html>]==]
    local fh = assert(io.open(path, "w"))
    fh:write(doc)
    fh:close()
    return #items
end

-------------------------------------------------------------------------------
--  Films: a scenario played a frame at a time, every frame a page (tools/make_gifs.py makes the GIFs)
-------------------------------------------------------------------------------
local FPS = 15
local film = { frames = 0, tallest = 0 }

-- The page as it is now, as the film's next frame.
local function shoot()
    film.frames = film.frames + 1
    draw(string.format("%s-%04d.html", film.prefix, film.frames), film.home)
    if G.TuttiFrame:IsVisible() then film.tallest = math.max(film.tallest, rectOf(G.TuttiFrame)[4]) end
end

-- `seconds` of the film: each frame the client's clock moves on by 1/15 s (its timers and OnUpdates run), then
-- `each(t)` runs if given (t from 0 to 1 over the stretch), then the page is shot.
local function play(seconds, each)
    local n = math.max(math.floor(seconds * FPS + 0.5), 0)
    for i = 1, n do
        W.advance(1 / FPS)
        if each then each(i / n) end
        shoot()
    end
end

-- Where a region's middle is on the page (px from the stage's top-left).
local function middle(region)
    local r = rectOf(region)
    return r[1] + r[3] / 2, SH - r[2] - r[4] / 2
end

-- The cursor glides to (x, y) in `seconds`, eased in and out.
local function glide(x, y, seconds)
    local fromX, fromY = cursor.x, cursor.y
    play(seconds, function(t)
        local e = t < 0.5 and 4 * t * t * t or 1 - (2 - 2 * t) ^ 3 / 2
        cursor.x, cursor.y = fromX + (x - fromX) * e, fromY + (y - fromY) * e
    end)
end

local function buttonOf(rollID, choice)
    local view = G.TuttiFrame.views[cardOf(rollID)]
    local b = view and view.buttons[choice]
    assert(b and b:IsVisible(), "render_ui: no " .. choice .. " button on roll " .. rollID)
    return b
end

-- How wide the window is on the page: its own width at its scale (300 at 100 %).
local function windowWidth()
    return rectOf(G.TuttiFrame)[3]
end

-- Off the page to the right of the window, at the height of `region` (`down` px lower): where the cursor comes from
-- and goes to.
local function aside(region, down)
    local _, y = middle(region)
    return film.home.x + windowWidth() + 150, y + (down or 0)
end

-- Just right of the window, at the height of `region` (`down` px lower): where the cursor rests between clicks,
-- off the window and still on the page.
local function beside(region, down)
    local _, y = middle(region)
    return film.home.x + windowWidth() + 12, y + (down or 0)
end

-- The player rolls with the mouse: the cursor glides onto the card's button (it lights under the mouse), presses it
-- (it goes down) and lets go: the click is the pick, and the game ends the player's part of the roll.
local function rollWithMouse(rollID, choice, seconds)
    local b = buttonOf(rollID, choice)
    local x, y = middle(b)
    glide(x + 24, y + 4, seconds) -- the tip on the button just after its word, so the word stays in sight
    b:GetScript("OnEnter")(b)
    play(0.3)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    play(0.2)
    b:GetScript("OnMouseUp")(b, "LeftButton")
    b:Click()
    W.fire("CANCEL_LOOT_ROLL", rollID)
end

-- A drop's picks so far, by item: news(item, { [member] = pick }, opts) adds the news and hands the history the drop
-- (setDrop), from the drop's own start.
local known = {}
local function news(item, picks, opts)
    known[item] = known[item] or {}
    for who, pick in pairs(picks) do known[item][who] = pick end
    local o = { startTime = drops[item.key] }
    for k, v in pairs(opts or {}) do o[k] = v end
    setDrop(item, item == ITEMS.axe and 1 or 2, known[item], o)
end

local function dropped(item, rollID, over)
    startRoll(rollID, item, over)
    drops[item.key] = G.C_LootHistory.GetLootHistoryTime()
end

local EVERYONE_CHOOSING = { paladin = "wait", shaman = "wait", mage = "wait", warrior = "wait", me = "wait" }
local THE_PARTY_PICKED = { paladin = "greed", shaman = "need", mage = "pass", warrior = "pass", me = "wait" }

local FILMS = {}

-- drop (01-a-boss-drop.gif): the axe (which a druid cannot Need) and the gloves drop and the window rises; the
-- party's picks fade in one by one while the dots of who is still choosing pulse; the player clicks Greed on the axe;
-- Orlen's number spins in and he wins it (the wash, the crown); the player clicks Need on the gloves; their numbers
-- spin in; the axe folds under DONE; the player wins the gloves (the ring glows twice, the shine crosses); "closes in
-- 5s" runs down with the line under the header (Close after the last roll on 5 seconds) and the window sinks away.
-- About 15 s.
function FILMS.drop()
    ns.Set("closeAfter", 5)
    party()
    shoot()
    play(0.25)
    dropped(ITEMS.axe, 1, { canNeed = false, reasonNeed = 1 })
    dropped(ITEMS.gloves, 2)
    news(ITEMS.axe, EVERYONE_CHOOSING)
    news(ITEMS.gloves, EVERYONE_CHOOSING)
    play(0.4)
    news(ITEMS.axe, { paladin = "need" })
    play(0.3)
    news(ITEMS.axe, { mage = "pass" })
    news(ITEMS.gloves, { mage = "pass" })
    play(0.3)
    news(ITEMS.axe, { shaman = "greed" })
    news(ITEMS.gloves, { shaman = "need" })
    play(0.25)
    news(ITEMS.axe, { warrior = "pass" })
    news(ITEMS.gloves, { warrior = "pass" })
    local x, y = aside(buttonOf(1, "greed"), 40)
    cursor = { x = x, y = y }
    rollWithMouse(1, "greed", 0.5)
    news(ITEMS.axe, { me = "greed" })
    play(0.15)
    news(ITEMS.axe, { paladin = { "need", 19 } }) -- everyone has picked: the number spins in
    x, y = beside(buttonOf(2, "need"), 30)
    glide(x, y, 0.4) -- meanwhile the cursor rests beside the gloves, whose buttons still wait
    play(0.75)
    news(ITEMS.axe, {}, { winner = "paladin" }) -- the axe folds 4 s later
    play(0.5)
    news(ITEMS.gloves, { paladin = "greed" })
    rollWithMouse(2, "need", 0.4)
    news(ITEMS.gloves, { me = "need" })
    play(0.15)
    x, y = aside(G.TuttiFrame.views[cardOf(2)], 60)
    glide(x, y, 0.45)
    cursor = nil
    play(0.3)
    news(ITEMS.gloves, { shaman = { "need", 52 }, me = { "need", 87 } })
    play(2.9) -- the axe folds in here, 1.2 s before the gloves are decided
    news(ITEMS.gloves, {}, { winner = "me" })
    play(5.6) -- "closes in 5s", then the window sinks away
    play(0.3)
end

-- click (02-roll-from-the-window.gif): the gloves wait on the player, the rest of the party has picked and the
-- player's own dots pulse; the cursor, resting beside the window, rolls Need on the card (the button lights under it,
-- goes down, and the click is the pick): the buttons go, the player's row turns Need; the cursor goes back to rest
-- and the numbers spin in. About 5 s.
function FILMS.click()
    party()
    dropped(ITEMS.gloves, 2)
    news(ITEMS.gloves, THE_PARTY_PICKED)
    wait(5)
    local restX, restY = beside(buttonOf(2, "need"), 26)
    cursor = { x = restX, y = restY }
    shoot()
    play(0.4)
    rollWithMouse(2, "need", 0.6)
    news(ITEMS.gloves, { me = "need" })
    play(0.3)
    glide(restX, restY, 0.5)
    play(0.3)
    news(ITEMS.gloves, { shaman = { "need", 52 }, me = { "need", 87 } })
    play(1.9)
end

-- won (03-you-won.gif): the gloves' numbers are in (Brisé 52, the player 87); the game decides: the player's row
-- washes in the accent and its crown pops, the subtitle reads "You won · Need 87", the item's ring glows twice and
-- the shine crosses the card once (in game the soft chime plays). Close after the last roll is on Never, so the
-- window stays. About 4 s.
function FILMS.won()
    ns.Set("closeAfter", 0)
    party()
    dropped(ITEMS.gloves, 2)
    news(ITEMS.gloves, THE_PARTY_PICKED)
    wait(8)
    choose(2, "need")
    news(ITEMS.gloves, { me = "need" })
    wait(3)
    news(ITEMS.gloves, { shaman = { "need", 52 }, me = { "need", 87 } })
    wait(2)
    shoot()
    play(0.5)
    news(ITEMS.gloves, {}, { winner = "me" })
    play(3.5)
end

-------------------------------------------------------------------------------
--  Run: a film's frames, or a scene's page and what the model holds
-------------------------------------------------------------------------------
if FILMS[sceneName] then
    film.prefix = out
    local saved = (ns.DB and ns.DB.window) or ns.DEFAULTS.window
    film.home = { x = saved.x or ns.DEFAULTS.window.x, y = -(saved.y or ns.DEFAULTS.window.y) }
    FILMS[sceneName]()
    local fh = assert(io.open(out .. ".json", "w"))
    fh:write(string.format('{"film": "%s", "frames": %d, "fps": %d, "home": {"x": %g, "y": %g}, "tallest": %g}\n',
        sceneName, film.frames, FPS, film.home.x, film.home.y, film.tallest))
    fh:close()
    print(string.format("film %s: %d frames at %d fps (%.1f s), the window up to %g px high", sceneName, film.frames,
        FPS, film.frames / FPS, film.tallest))
else
    local scene = SCENES[sceneName]
    if not scene then
        local names = {}
        for k in pairs(SCENES) do names[#names + 1] = k end
        for k in pairs(FILMS) do names[#names + 1] = k end
        table.sort(names)
        error("render_ui: no scene or film \"" .. tostring(sceneName) .. "\"; there are: " .. table.concat(names, " "))
    end
    scene()
    W.advance(0)

    print(string.format("scene %s%s", sceneName, variant and (" (" .. variant .. ")") or ""))
    for _, card in ipairs(ns.Rolls.Cards()) do
        local rows = {}
        for _, row in ipairs(ns.Rolls.Rows(card)) do
            rows[#rows + 1] = row.name .. ":" .. row.state .. (row.roll and ("=" .. row.roll) or "") ..
                (row.isWinner and "*" or "")
        end
        print(string.format("  card %d %s [%s] %ds left, mine=%s: %s", card.id, card.name or "?", card.status,
            math.ceil(ns.Rolls.TimeLeft(card)), tostring(card.mine), table.concat(rows, " ")))
    end
    print("  window view: " .. tostring(ns.UI.View()))

    if not (G.TuttiFrame and G.TuttiFrame:IsVisible()) then
        io.stderr:write("render_ui: nothing to draw: TuttiFrame is hidden (the scene did not open it)\n")
        os.exit(1)
    end
    print("wrote " .. out .. " (" .. draw(out) .. " regions)")
end
