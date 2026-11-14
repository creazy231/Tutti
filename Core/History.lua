-------------------------------------------------------------------------------
--  Tutti: the session's results, for the Recent rolls view. A card that is decided (a winner, or
--  everyone passed) or that ended (nobody decided it) leaves one entry behind when it says so
--  ("CARD_DECIDED"): a snapshot of that moment. The entries live in TuttiDB.recent, newest first, at
--  most 100. They survive a /reload and are cleared at login.
--    ns.History.Entries()        { entry, ... } newest first; a new list on every call, the entries in
--                                it are shared and read-only
--    ns.History.Age(entry, now)  "now" (under a minute), "<n>m" or "<n>h"; `now` is time() by default
--  An entry: { cardId, link, name, icon, quality, count, place, at, winner|nil, allPassed, ended, rows, demo|nil }
--    cardId     the card's id, so that the card finds its entry again (see below); nil without one
--    link, name, icon, quality, count  the item and how many dropped, as the card had them (any may be missing)
--    place      where the player was: the name of the instance, else of the zone ("Unknown" when the
--               game gives neither)
--    at         time() when the card was first decided
--    winner     { name, class, state, roll|nil }, the winner's row: "Orlen", "PALADIN", "need", 87
--    allPassed  everyone passed
--    ended      nobody decided the roll, or the winner has no row to name. Exactly one of winner,
--               allPassed and ended holds, so a view always has a line to write.
--    rows       copies of ns.Rolls.Rows(card) at that moment, strings, numbers and booleans only:
--               everyone's pick and number
--    demo       the card came from /tutti demo
--  "CARD_DECIDED" is a card's result, final or improved: a card that ended with nobody deciding it can
--  be decided later, and the message then comes a second time for the same card. One card is one entry,
--  found by its id: the repeat replaces winner, allPassed, ended and rows in the entry itself, which
--  keeps its place in the list (the order is that of the first time), its time and its place. A card
--  without a numeric id always makes an entry of its own, and a demo card never stands for a real one.
--  Card ids restart at every load (Core/Rolls.lua counts from 1) while the results outlast a /reload, so
--  a load strips the ids from the saved entries: their cards are gone, and an id must never name another.
--  Picks and numbers that reach a card after its entry was made ("CARD_CHANGED" with picks) update the entry
--  the same way, in place, so the open line shows what the card shows.
--  Message "HISTORY_CHANGED" when an entry was added or updated, or the list was cleared.
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

-- What a decision says, as the fields of an entry: the winner's row, or everyone passed, or neither
-- (the roll ended or the winner cannot be named), and everyone's pick.
local function resultOf(card)
    local rows, winner = {}, nil
    for _, row in ipairs(ns.Rolls.Rows(card)) do
        local copy = plainRow(row)
        rows[#rows + 1] = copy
        if copy.isWinner == true then
            winner = { name = copy.name, class = copy.class, state = copy.state, roll = copy.roll }
        end
    end
    local allPassed = not winner and card.allPassed == true
    return winner, allPassed, not winner and not allPassed, rows
end

-- The entry for a card that has just been decided or has ended.
local function entryOf(card)
    local winner, allPassed, ended, rows = resultOf(card)
    return {
        cardId = ns.Clear(card.id, "number"),
        link = ns.Clear(card.link, "string"), name = ns.Clear(card.name, "string"),
        icon = ns.Clear(card.icon, "number") or ns.Clear(card.icon, "string"),
        quality = ns.Clear(card.quality, "number"), count = ns.Clear(card.count, "number"),
        place = placeName(), at = time(),
        winner = winner, allPassed = allPassed, ended = ended, rows = rows,
        demo = card.demo == true or nil,
    }
end

-- The entry this card made earlier, nil when it made none (or has no numeric id to be known by).
local function entryFor(recent, card)
    local id = ns.Clear(card.id, "number")
    if not id then return nil end
    for _, entry in ipairs(recent) do
        if type(entry) == "table" and entry.cardId == id and (entry.demo == true) == (card.demo == true) then
            return entry
        end
    end
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
    local entry = entryFor(recent, card)
    if entry then
        -- The card is announced again with a better result: the entry stays where it is.
        entry.winner, entry.allPassed, entry.ended, entry.rows = resultOf(card)
    else
        table.insert(recent, 1, entryOf(card))
        while #recent > MAX do table.remove(recent) end
    end
    ns.Fire("HISTORY_CHANGED")
end

ns.Listen("CARD_DECIDED", record)

-- A number that comes after the decision (the game can send a Greed's after the winner) shows on the card: the
-- card's entry takes the card's rows again, in place. Only for a card that has an entry, and not for the message
-- of the decision itself, which CARD_DECIDED has just recorded with the same picks.
ns.Listen("CARD_CHANGED", function(card, changes)
    card, changes = ns.Clear(card, "table"), ns.Clear(changes, "table")
    if not (card and changes and changes.picks) or changes.decided then return end
    local recent = saved()
    local entry = recent and entryFor(recent, card)
    if not entry then return end
    entry.winner, entry.allPassed, entry.ended, entry.rows = resultOf(card)
    ns.Fire("HISTORY_CHANGED")
end)

-- The cards of an earlier load are gone, and this load numbers its cards from 1 again.
ns.Listen("DB_READY", function()
    for _, entry in ipairs(saved() or {}) do
        if type(entry) == "table" then entry.cardId = nil end
    end
end)

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
