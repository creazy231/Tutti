-------------------------------------------------------------------------------
--  Tutti: other addons. For now NaowhForever's BiS list, which badges Blizzard's roll popups for an
--  item on the player's list. Those popups are switched off (Core/Popups.lua), so the card shows the
--  badge itself.
--    ns.BiS.Badge(link)   nil, or { text, star, r, g, b }
--                         text   "BiS", "2nd pick" or "#<n> pick"
--                         star   the first three picks
--                         r g b  NaowhForever's colour for the rank, else the gold #ffd100
--  The rule is that of NaowhForever's own roll badge (NaowhForever_BiS/BiS/View/RollBadge.lua): its
--  Drop Alert is on (Alerts.On()), its "Roll Frame Badge" setting is on (Settings.Get("bisAlertBadge")),
--  the item has a rank on the player's list (Alerts.Rank(link)), and the player's "Alert For" choice
--  wants that rank (Alerts.Wanted(rank)).
--  NaowhForever is optional and these are another addon's internals: it is looked up when it is asked,
--  every call goes through pcall, every answer through ns.Clear and a type check, and anything
--  unexpected means no badge (a colour that cannot be had means gold). Tutti writes nothing to it and
--  keeps nothing of it: the colour is copied by value.
-------------------------------------------------------------------------------
local _, ns = ...
local BiS = {}
ns.BiS = BiS

local STARRED = 3                  -- the first three picks get the star, as in NaowhForever's badge
local GOLD = { 1, 209 / 255, 0 }   -- #ffd100: the colour when NaowhForever gives none

-- The functions the rule asks, as paths from NaowhForever's namespace.
local ALERTS_ON = { "BiS", "Alerts", "On" }
local SETTING = { "BiS", "Settings", "Get" }
local RANK = { "BiS", "Alerts", "Rank" }
local WANTED = { "BiS", "Alerts", "Wanted" }
local RANK_COLOR = { "Shared", "Parts", "RankColor" }

-- NaowhForever's function at `path`, nil when it is not there. Reads another addon's tables, so it
-- only runs inside a pcall.
local function find(path)
    local node = NaowhForever
    for i = 1, #path do
        node = ns.Clear(node, "table")
        if not node then return nil end
        node = node[path[i]]
    end
    return ns.Clear(node, "function")
end

-- Calls that function protected and gives its first answer: nil when NaowhForever or the function is
-- missing, or the call raises.
local function ask(path, ...)
    local ok, answer = pcall(function(...)
        local fn = find(path)
        if fn then return fn(...) end
    end, ...)
    if ok then return answer end
end

-- A yes from NaowhForever: the boolean true in the clear, nothing else.
local function yes(path, ...)
    return ns.Clear(ask(path, ...), "boolean") == true
end

-- The item's rank on the player's list: a whole number from 1, else nil.
local function rankOf(link)
    local rank = ns.Clear(ask(RANK, link), "number")
    if rank and rank >= 1 and rank % 1 == 0 then return rank end
end

local function channels(color)
    return color.r, color.g, color.b
end

-- NaowhForever's colour for a rank as r, g, b (each from 0 to 1), else gold.
local function colorOf(rank)
    local color = ns.Clear(ask(RANK_COLOR, rank), "table")
    if color then
        local _, r, g, b = pcall(channels, color) -- a read that raised leaves g and b empty
        r, g, b = ns.Clear(r, "number"), ns.Clear(g, "number"), ns.Clear(b, "number")
        if r and g and b and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
            return r, g, b
        end
    end
    return GOLD[1], GOLD[2], GOLD[3]
end

local function textOf(rank)
    if rank == 1 then return "BiS" end
    if rank == 2 then return "2nd pick" end
    return "#" .. rank .. " pick"
end

function BiS.Badge(link)
    link = ns.Clear(link, "string")
    if not link or link == "" then return nil end
    if not (yes(ALERTS_ON) and yes(SETTING, "bisAlertBadge")) then return nil end
    local rank = rankOf(link)
    if not rank or not yes(WANTED, rank) then return nil end
    local r, g, b = colorOf(rank)
    return { text = textOf(rank), star = rank <= STARRED, r = r, g = g, b = b }
end
