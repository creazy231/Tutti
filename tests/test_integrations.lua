local T = T

-- The two-hand axe the other tests roll on: item 18000.
local AXE = 18000

-- A game that records errors instead of raising them (the fake's default handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

-- NaowhForever's rank colours, as its BiS list paints them: BiS orange, silver, bronze, and its muted
-- grey for any other rank.
local COLORS = {
    [1] = { r = 1, g = 0.5, b = 0 },
    [2] = { r = 0xc7 / 255, g = 0xcc / 255, b = 0xdb / 255 },
    [3] = { r = 0xa0 / 255, g = 0x52 / 255, b = 0x2d / 255 },
}
local MUTED = { r = 0x9a / 255, g = 0x9e / 255, b = 0xa6 / 255 }

-- A stand-in for NaowhForever with the pieces its roll badge reads: Alerts.On, Alerts.Rank,
-- Alerts.Wanted, the setting reader and Parts.RankColor. Every answer is a field of the returned `s`
-- and can change at any time; `s.asked` records what Tutti asked, one "Name:argument" string per call.
local function nfStub(over)
    local s = { on = true, badge = true, rank = 1, wanted = true, asked = {} }
    for k, v in pairs(over or {}) do s[k] = v end
    local function note(name, arg) s.asked[#s.asked + 1] = name .. (arg ~= nil and (":" .. tostring(arg)) or "") end
    s.NaowhForever = {
        BiS = {
            Alerts = {
                On = function() note("On"); return s.on end,
                Rank = function(link) note("Rank", link); return s.rank end,
                Wanted = function(rank) note("Wanted", rank); return s.wanted end,
            },
            Settings = {
                Get = function(key)
                    note("Get", key)
                    if key == "bisAlertBadge" then return s.badge end
                end,
            },
        },
        Shared = {
            Parts = {
                RankColor = function(rank)
                    note("RankColor", rank)
                    if s.color ~= nil then return s.color end
                    return COLORS[rank] or MUTED
                end,
            },
        },
    }
    return s
end

-- Loads Tutti with the stand-in as the game's NaowhForever.
local function load(s, opts)
    opts = opts or {}
    opts.setup = opts.setup or function() end
    local inner = opts.setup
    opts.setup = function(G, W)
        G.NaowhForever = s and s.NaowhForever
        inner(G, W)
    end
    local G, W, ns = T.load(opts)
    return G, W, ns
end

-- A link for the axe, as the game writes one.
local function axe(W, quality)
    return W.itemLink(AXE, "Guardian's Dualblade", quality or 3)
end

-- A secret string or number in the game still has type "string" or "number", so the fake's userdata
-- secrets prove little about a check that stops at type(). Here plain values play secrets by being
-- named in `hidden`.
local function withSecrets(ns)
    local hidden = {}
    ns.IsSecret = function(...)
        for i = 1, select("#", ...) do
            if hidden[(select(i, ...))] then return true end
        end
        return false
    end
    return hidden
end

T.it("no NaowhForever: nil", function()
    local G, W, ns = T.load()
    T.eq(G.NaowhForever, nil)
    T.eq(ns.BiS.Badge(axe(W)), nil)
    -- Part of it there, part not: the BiS module is off or too old.
    G.NaowhForever = {}
    T.eq(ns.BiS.Badge(axe(W)), nil, "no BiS")
    G.NaowhForever = { BiS = {} }
    T.eq(ns.BiS.Badge(axe(W)), nil, "no Alerts")
    G.NaowhForever = { BiS = { Alerts = {}, Settings = {} } }
    T.eq(ns.BiS.Badge(axe(W)), nil, "no functions")
    G.NaowhForever = "not a table"
    T.eq(ns.BiS.Badge(axe(W)), nil)
    G.NaowhForever = 5
    T.eq(ns.BiS.Badge(axe(W)), nil)
end)

T.it("alerts off or badge setting off: nil", function()
    local s = nfStub({ on = false })
    local G, W, ns = load(s)
    T.eq(ns.BiS.Badge(axe(W)), nil, "Drop Alert is off")
    s.on, s.badge = true, false
    T.eq(ns.BiS.Badge(axe(W)), nil, "the roll frame badge is off")
    s.on, s.badge = false, false
    T.eq(ns.BiS.Badge(axe(W)), nil, "both off")
    s.on, s.badge = true, true
    T.ok(ns.BiS.Badge(axe(W)), "both on: a badge")
    -- The setting asked for is the badge's own.
    T.has(s.asked, "Get:bisAlertBadge")
    for _, call in ipairs(s.asked) do
        if call:find("^Get:") then T.eq(call, "Get:bisAlertBadge", "no other setting is read") end
    end
end)

T.it("a setting that is missing, or no yes, is no", function()
    local s = nfStub()
    local G, W, ns = load(s)
    for _, answer in ipairs({ "yes", 1, 0, {} }) do
        s.on, s.badge = true, answer
        T.eq(ns.BiS.Badge(axe(W)), nil, "a badge setting of " .. type(answer) .. " is no yes")
        s.on, s.badge = answer, true
        T.eq(ns.BiS.Badge(axe(W)), nil, "an On of " .. type(answer) .. " is no yes")
    end
    s.on, s.badge = true, nil
    T.eq(ns.BiS.Badge(axe(W)), nil, "no answer")
    s.on, s.badge, s.wanted = true, true, "yes"
    T.eq(ns.BiS.Badge(axe(W)), nil, "Wanted must be a yes too")
end)

T.it("rank 1 BiS with star, 2 '2nd pick' with star, 5 '#5 pick' without", function()
    local s = nfStub()
    local G, W, ns = load(s)
    local link = axe(W)
    local function badge(rank)
        s.rank = rank
        return ns.BiS.Badge(link)
    end
    local one = badge(1)
    T.eq(one.text, "BiS")
    T.eq(one.star, true)
    local two = badge(2)
    T.eq(two.text, "2nd pick")
    T.eq(two.star, true)
    local three = badge(3)
    T.eq(three.text, "#3 pick")
    T.eq(three.star, true, "the star goes up to the third pick")
    local four = badge(4)
    T.eq(four.text, "#4 pick")
    T.eq(four.star, false, "and stops there")
    local five = badge(5)
    T.eq(five.text, "#5 pick")
    T.eq(five.star, false)
    T.eq(badge(12).text, "#12 pick")
    -- The rule's questions, in its order, with the link and the rank handed on.
    s.asked = {}
    badge(2)
    T.eq(table.concat(s.asked, ","), "On,Get:bisAlertBadge,Rank:" .. link .. ",Wanted:2,RankColor:2")
end)

T.it("Wanted false: nil", function()
    local s = nfStub({ rank = 5, wanted = false })
    local G, W, ns = load(s)
    T.eq(ns.BiS.Badge(axe(W)), nil, "the player's Alert For setting does not want a #5 pick")
    T.has(s.asked, "Wanted:5", "it was asked about this rank")
    s.rank = 1
    s.wanted = true
    T.ok(ns.BiS.Badge(axe(W)))
    -- An item that is not on the list has no rank: nothing to ask Wanted about.
    s.rank = nil
    s.asked = {}
    T.eq(ns.BiS.Badge(axe(W)), nil, "not on the player's list")
    T.eq(table.concat(s.asked, ","), "On,Get:bisAlertBadge,Rank:" .. axe(W), "Wanted is not asked")
    s.rank = false
    T.eq(ns.BiS.Badge(axe(W)), nil)
end)

T.it("a rank that is no pick number is no badge", function()
    local s = nfStub()
    local G, W, ns = load(s)
    for _, rank in ipairs({ 0, -1, 1.5, "1", "BiS", true, {}, math.huge, -math.huge, 0 / 0 }) do
        s.rank = rank
        T.eq(ns.BiS.Badge(axe(W)), nil, "rank " .. tostring(rank))
    end
    s.rank = 1
    T.ok(ns.BiS.Badge(axe(W)))
end)

T.it("an erroring NaowhForever is ignored", function()
    local errors = {}
    local s = nfStub()
    local G, W, ns = load(s, { setup = recordErrors(errors) })
    local alerts, parts = s.NaowhForever.BiS.Alerts, s.NaowhForever.Shared.Parts
    local function breaks(owner, name, run)
        local real = owner[name]
        owner[name] = function() error("NaowhForever broke: " .. name) end
        local ok, badge = pcall(run)
        owner[name] = real
        T.ok(ok, name .. " raising reached Tutti")
        return badge
    end
    local function ask() return ns.BiS.Badge(axe(W)) end
    T.eq(breaks(alerts, "On", ask), nil, "On raises")
    T.eq(breaks(s.NaowhForever.BiS.Settings, "Get", ask), nil, "the setting reader raises")
    T.eq(breaks(alerts, "Rank", ask), nil, "Rank raises")
    T.eq(breaks(alerts, "Wanted", ask), nil, "Wanted raises")
    -- A colour that cannot be had is not a reason to lose the badge: gold.
    local badge = breaks(parts, "RankColor", ask)
    T.eq(badge.text, "BiS", "RankColor raises: the badge stays")
    T.near(badge.r, 1)
    T.near(badge.g, 209 / 255)
    T.near(badge.b, 0)
    T.ok(ask(), "and everything works again once NaowhForever does")
    T.eq(#errors, 0, "another addon's failure is not Tutti's error to report")

    -- Tables that are not what they were: a metatable that raises on a read.
    local hostile = setmetatable({}, { __index = function() error("no reading me") end })
    G.NaowhForever = { BiS = hostile, Shared = hostile }
    T.eq(ns.BiS.Badge(axe(W)), nil)
    G.NaowhForever = setmetatable({}, { __index = function() error("no reading me") end })
    T.eq(ns.BiS.Badge(axe(W)), nil)
    -- A colour table that raises when it is read.
    G.NaowhForever = s.NaowhForever
    s.color = hostile
    badge = ns.BiS.Badge(axe(W))
    T.eq(badge.text, "BiS")
    T.near(badge.g, 209 / 255, 1e-6, "the colour falls back to gold")
    T.eq(#errors, 0)
end)

T.it("rank colour, else gold", function()
    local s = nfStub()
    local G, W, ns = load(s)
    local link = axe(W)
    local function badge(rank)
        s.rank = rank
        return ns.BiS.Badge(link)
    end
    local function rgb(b) return { b.r, b.g, b.b } end
    T.color(rgb(badge(1)), "ff8000", "BiS orange, as NaowhForever paints it")
    T.color(rgb(badge(2)), "c7ccdb", "silver")
    T.color(rgb(badge(3)), "a0522d", "bronze")
    T.color(rgb(badge(5)), "9a9ea6", "any other rank: its muted grey")

    -- NaowhForever gives no colour: the gold of the approved look, #ffd100.
    local gold = function(b) T.color(rgb(b), "ffd100", "gold") end
    s.color = {}
    s.rank = 1
    gold(badge(1))
    gold(badge(5))
    local junk = {
        { r = 1, g = 1 }, { r = "1", g = 1, b = 0 },                        -- a channel missing, one a string
        { r = 2, g = 0, b = 0 }, { r = -0.5, g = 0, b = 0 },                -- red out of range, both ways
        { r = 1, g = 2, b = 0 }, { r = 1, g = -0.1, b = 0 },                -- green
        { r = 1, g = 0, b = 2 }, { r = 1, g = 0, b = -0.5 },                -- blue
        { r = 1, g = 0.5, b = 0 / 0 }, { r = math.huge, g = 0, b = 0 },     -- not a number, not finite
        "orange", 5, true, false,                                           -- not a table at all
    }
    for _, color in ipairs(junk) do
        s.color = color
        gold(badge(1))
    end
    -- The colour has to be a table with all three channels in the clear.
    s.color = { r = T.secret(1), g = 0.5, b = 0 }
    gold(badge(1))
    local hidden = withSecrets(ns)
    hidden[0.25] = true
    s.color = { r = 0.25, g = 0.5, b = 0.75 }
    gold(badge(1))
    hidden[0.25] = nil
    T.color(rgb(badge(1)), "4080bf", "the same colour in the clear is used")

    -- No Parts at all, or no RankColor.
    s.color = nil
    s.NaowhForever.Shared = nil
    gold(badge(1))
    s.NaowhForever.Shared = { Parts = {} }
    gold(badge(2))
    s.NaowhForever.Shared = { Parts = { RankColor = "not a function" } }
    gold(badge(2))
end)

T.it("the badge is Tutti's own table, and carries NaowhForever's colour by value", function()
    local theirs = { r = 1, g = 0.5, b = 0 }
    local s = nfStub({ color = theirs })
    local G, W, ns = load(s)
    local link = axe(W)
    local a = ns.BiS.Badge(link)
    local b = ns.BiS.Badge(link)
    T.ok(a ~= b, "a table of its own on every call")
    T.ok(a ~= theirs, "not NaowhForever's colour table")
    T.eq(a.r, theirs.r)
    a.r, a.g, a.b = 0, 0, 0
    T.eq(theirs.r, 1, "changing the badge leaves NaowhForever's colour alone")
    T.eq(theirs.g, 0.5)
    local theirsBefore = { theirs.r, theirs.g, theirs.b }
    theirs.r = 0.1 -- NaowhForever repaints its colour later
    T.eq(b.r, theirsBefore[1], "a badge already made keeps its colour")
    local keys = {}
    for k in pairs(ns.BiS.Badge(link)) do keys[#keys + 1] = k end
    table.sort(keys)
    T.eq(table.concat(keys, ","), "b,g,r,star,text", "text, star, r, g, b and nothing else")
end)

T.it("a link that is no readable string is no badge, and NaowhForever is not asked", function()
    local s = nfStub()
    local G, W, ns = load(s)
    T.eq(ns.BiS.Badge(nil), nil)
    T.eq(ns.BiS.Badge(""), nil)
    T.eq(ns.BiS.Badge(5), nil)
    T.eq(ns.BiS.Badge({}), nil)
    T.eq(ns.BiS.Badge(T.secret("link")), nil)
    local link = axe(W)
    local hidden = withSecrets(ns)
    hidden[link] = true
    T.eq(ns.BiS.Badge(link), nil, "a link ns.IsSecret calls secret is never handed on")
    T.eq(#s.asked, 0, "nothing was asked of NaowhForever")
    hidden[link] = nil
    T.ok(ns.BiS.Badge(link))
end)

T.it("what NaowhForever answers goes through the secret guard", function()
    local s = nfStub()
    local G, W, ns = load(s)
    local hidden = withSecrets(ns)
    local link = axe(W)
    hidden[true] = true
    T.eq(ns.BiS.Badge(link), nil, "a yes that ns.IsSecret calls secret is no yes")
    hidden[true] = nil
    s.rank = 1
    hidden[1] = true
    T.eq(ns.BiS.Badge(link), nil, "a rank that ns.IsSecret calls secret is no rank")
    hidden[1] = nil
    T.ok(ns.BiS.Badge(link))
    s.on = T.secret(true)
    T.eq(ns.BiS.Badge(link), nil, "a secret value from the game's own secrets as well")
    s.on, s.rank = true, T.secret(1)
    T.eq(ns.BiS.Badge(link), nil)
    s.rank, s.wanted = 1, T.secret(true)
    T.eq(ns.BiS.Badge(link), nil)
end)

T.it("a table, function or colour that ns.IsSecret calls secret is never used", function()
    local s = nfStub()
    local G, W, ns = load(s)
    local hidden = withSecrets(ns)
    local link = axe(W)
    local nf = s.NaowhForever
    T.ok(ns.BiS.Badge(link), "it works to begin with")
    -- Every step of the rule: a table walked through, a function called.
    local rule = { nf, nf.BiS, nf.BiS.Alerts, nf.BiS.Alerts.On, nf.BiS.Settings, nf.BiS.Settings.Get,
        nf.BiS.Alerts.Rank, nf.BiS.Alerts.Wanted }
    for i, thing in ipairs(rule) do
        hidden[thing] = true
        T.eq(ns.BiS.Badge(link), nil, "step " .. i .. " of the rule is secret")
        hidden[thing] = nil
    end
    T.ok(ns.BiS.Badge(link))
    -- The colour's path and the colour itself: the badge stays, in gold.
    local color = { nf.Shared, nf.Shared.Parts, nf.Shared.Parts.RankColor, COLORS[1] }
    for i, thing in ipairs(color) do
        hidden[thing] = true
        local badge = ns.BiS.Badge(link)
        T.eq(badge.text, "BiS", "part " .. i .. " of the colour is secret: the badge stays")
        T.color({ badge.r, badge.g, badge.b }, "ffd100", "and is gold")
        hidden[thing] = nil
    end
    local badge = ns.BiS.Badge(link)
    T.color({ badge.r, badge.g, badge.b }, "ff8000", "the colour in the clear is used")
end)

T.it("NaowhForever is looked up when it is asked, not when Tutti loads", function()
    local G, W, ns = T.load()
    T.eq(ns.BiS.Badge(axe(W)), nil, "not there yet")
    local s = nfStub()
    G.NaowhForever = s.NaowhForever
    T.eq(ns.BiS.Badge(axe(W)).text, "BiS", "it arrived later")
    G.NaowhForever = nil
    T.eq(ns.BiS.Badge(axe(W)), nil, "and went again")
end)
