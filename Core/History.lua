-------------------------------------------------------------------------------
--  Tutti: the session's results, for the Recent rolls view. A card that is decided (a winner, or
--  everyone passed) or that ended (nobody decided it) leaves one entry behind when it says so
--  ("CARD_DECIDED"): a snapshot, so what happens to the card afterwards does not change it. The
--  entries live in TuttiDB.recent, newest first, at most 100. They survive a /reload and are cleared
--  at login.
--    ns.History.Entries()        { entry, ... } newest first; a new list on every call, the entries in
--                                it are shared and read-only
--    ns.History.Age(entry, now)  "now" (under a minute), "<n>m" or "<n>h"; `now` is time() by default
--  An entry: { link, name, icon, quality, place, at, winner|nil, allPassed, ended, rows, demo|nil }
--    link, name, icon, quality  the item, as the card had it (any of them may be missing)
--    place      where the player was: the name of the instance, else of the zone ("Unknown" when the
--               game gives neither)
--    at         time() when the card was decided
--    winner     { name, class, state, roll|nil }, the winner's row: "Orlen", "PALADIN", "need", 87
--    allPassed  everyone passed
--    ended      nobody decided the roll, or the winner has no row to name. Exactly one of winner,
--               allPassed and ended holds, so a view always has a line to write.
--    rows       copies of ns.Rolls.Rows(card) at that moment, strings, numbers and booleans only:
--               everyone's pick and number
--    demo       the card came from /tutti demo
--  Message "HISTORY_CHANGED" when an entry was added or the list was cleared.
--  Everything the game hands over (the place's names, the login flag) passes ns.Clear.
-------------------------------------------------------------------------------
local _, ns = ...
local History = {}
ns.History = History

local MAX = 100 -- entries kept
local MINUTE, HOUR = 60, 3600

-- The saved list (TuttiDB.recent), nil before the saved variables are in. A value that is no list
-- is replaced by one.
local function saved()
    local db = ns.DB
    if type(db) ~= "table" then return nil end
    if type(db.recent) ~= "table" then db.recent = {} end
    return db.recent
end

-- A non-empty string the game gave in the clear, else nil.
local function text(value)
    value = ns.Clear(value, "string")
    if value == "" then return nil end
    return value
end

-- Where the player is: the instance's name inside an instance, else the zone's. GetInstanceInfo
-- names the continent outside an instance, so it is asked only inside one.
local function placeName()
    local name
    if type(IsInInstance) == "function" and ns.Clear(IsInInstance(), "boolean") == true
        and type(GetInstanceInfo) == "function" then
        name = text((GetInstanceInfo()))
    end
    if not name and type(GetRealZoneText) == "function" then name = text(GetRealZoneText()) end
    return name or text(UNKNOWN) or "Unknown"
end

-- A row as plain data, so it can live in the saved variables: strings, numbers and booleans only.
local function plainRow(row)
    local out = {}
    for key, value in pairs(row) do
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then out[key] = value end
    end
    return out
end

-- The entry for a card that has just been decided or has ended.
local function entryOf(card)
    local rows, winner = {}, nil
    for _, row in ipairs(ns.Rolls.Rows(card)) do
        local copy = plainRow(row)
        rows[#rows + 1] = copy
        if copy.isWinner == true then
            winner = { name = copy.name, class = copy.class, state = copy.state, roll = copy.roll }
        end
    end
    local allPassed = not winner and card.allPassed == true
    return {
        link = ns.Clear(card.link, "string"), name = ns.Clear(card.name, "string"),
        icon = ns.Clear(card.icon, "number") or ns.Clear(card.icon, "string"),
        quality = ns.Clear(card.quality, "number"),
        place = placeName(), at = time(),
        winner = winner, allPassed = allPassed, ended = not winner and not allPassed,
        rows = rows, demo = card.demo == true or nil,
    }
end

-------------------------------------------------------------------------------
--  The interface
-------------------------------------------------------------------------------
function History.Entries()
    local out, recent = {}, saved()
    for i = 1, recent and #recent or 0 do
        if type(recent[i]) == "table" then out[#out + 1] = recent[i] end
    end
    return out
end

function History.Age(entry, now)
    local at = type(entry) == "table" and entry.at
    if type(at) ~= "number" then return "now" end
    local seconds = (type(now) == "number" and now or time()) - at
    if seconds < MINUTE then return "now" end
    if seconds < HOUR then return math.floor(seconds / MINUTE) .. "m" end
    return math.floor(seconds / HOUR) .. "h"
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local function record(card)
    card = ns.Clear(card, "table")
    local recent = saved()
    if not (card and recent) then return end
    table.insert(recent, 1, entryOf(card))
    while #recent > MAX do table.remove(recent) end
    ns.Fire("HISTORY_CHANGED")
end

ns.Listen("CARD_DECIDED", record)

-- A login starts a new session and the results go; a /reload and a loading screen go on with the
-- same one.
ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
    if ns.Clear(isInitialLogin, "boolean") ~= true then return end
    local recent = saved()
    if recent and next(recent) ~= nil then
        ns.DB.recent = {}
        ns.Fire("HISTORY_CHANGED")
    end
end)
