local T = T

-- The two-hand axe the other tests roll on: item 18000.
local AXE = 18000

-- A roll for the axe; `over` changes or adds fields of the spec.
local function axeSpec(W, over)
    local spec = { link = W.itemLink(AXE, "Guardian's Dualblade", 3), name = "Guardian's Dualblade", texture = 135348 }
    for k, v in pairs(over or {}) do spec[k] = v end
    return spec
end

-- Starts a roll for the axe and hands back its card (the last one).
local function newCard(W, ns, rollID, over)
    W.addRoll(rollID, axeSpec(W, over))
    local cards = ns.Rolls.Cards()
    return cards[#cards]
end

-- The party the other tests use, in party1..party4; the player is the fake's Ayla Brightwind.
local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- The same five as the history names them: full name, GUID, class file.
local ORLEN = { "Orlen Brightmoor", "Player-1-0002", "PALADIN" }
local BRISE = { "Brisé Tidewater", "Player-1-0003", "SHAMAN" }
local CORVEL = { "Corvel Duskmantle", "Player-1-0004", "MAGE" }
local KESTREL = { "Kestrel Ironmark", "Player-1-0005", "WARRIOR" }
local AYLA = { "Ayla Brightwind", "Player-1-00000001", "DRUID", isSelf = true }

-- One EncounterLootDropRollInfo.
local function rollInfo(who, state, roll, isWinner)
    return { playerName = who[1], playerGUID = who[2], playerClass = who[3], isSelf = who.isSelf == true,
        state = state, roll = roll, isWinner = isWinner == true }
end

-- An EncounterLootDropInfo for the axe as the game hands it out, started now and lasting a minute (its
-- times are milliseconds). `rolls` are its rollInfos; `over` replaces or adds fields.
local function dropInfo(G, W, rolls, over)
    local info = { lootListKey = 7, itemHyperlink = W.itemLink(AXE, "Guardian's Dualblade", 3),
        playerRollState = G.Enum.EncounterLootDropRollState.NoRoll, isTied = false, allPassed = false,
        rollInfos = rolls or {}, startTime = G.C_LootHistory.GetLootHistoryTime(), duration = 60000 }
    for k, v in pairs(over or {}) do info[k] = v end
    return info
end

-- A drop the game has decided: `who` won with `roll`.
local function won(G, W, who, roll, rolls, over)
    local need = G.Enum.EncounterLootDropRollState.NeedMainSpec
    local info = dropInfo(G, W, rolls or { rollInfo(who, need, roll, true) }, over)
    info.winner = rollInfo(who, need, roll, true)
    return info
end

-- One field of every row as a comma-joined string, so a failure shows the whole list.
local function column(rows, key)
    local out = {}
    for i, row in ipairs(rows) do out[i] = tostring(row[key]) end
    return table.concat(out, ",")
end

-- Counts the messages of one kind.
local function count(ns, msg)
    local seen = { n = 0 }
    ns.Listen(msg, function() seen.n = seen.n + 1 end)
    return seen
end

-- A card made by hand, decided with everyone passed: item `i`, named "Item <i>" (the demo and these tests
-- make cards the same way, outside Core/Rolls.lua).
local function handCard(W, i, over)
    local card = { id = i, name = "Item " .. i, link = W.itemLink(20000 + i, "Item " .. i, 3), icon = 1000 + i,
        quality = 3, picks = {}, status = "decided", allPassed = true }
    for k, v in pairs(over or {}) do card[k] = v end
    return card
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

-- A game that records errors instead of raising them (the fake's default handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

T.it("a decided card becomes an entry with every row", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())
    local card = newCard(W, ns, 7)
    local changed = count(ns, "HISTORY_CHANGED")
    W.advance(12)
    T.eq(#ns.History.Entries(), 0, "nothing before the decision")
    W.setDrop(9, 7, won(G, W, ORLEN, 87, {
        rollInfo(ORLEN, ST.NeedMainSpec, 87, true), rollInfo(BRISE, ST.Greed), rollInfo(CORVEL, ST.Pass),
        rollInfo(KESTREL, ST.NoRoll), rollInfo(AYLA, ST.NeedMainSpec, 42),
    }))
    T.eq(card.status, "decided")
    local entries = ns.History.Entries()
    T.eq(#entries, 1, "one entry")
    T.eq(changed.n, 1, "and one message")
    local e = entries[1]
    T.eq(e.link, card.link)
    T.eq(e.name, "Guardian's Dualblade")
    T.eq(e.icon, 135348)
    T.eq(e.quality, 3)
    T.eq(e.place, "Greymist Hollow")
    T.eq(e.at, G.time(), "the time of the decision")
    T.eq(e.at, W.epoch + 12)
    T.eq(e.allPassed, false)
    T.eq(e.ended, false)
    T.eq(e.demo, nil)
    T.eq(e.winner.name, "Orlen", "the winner's row: first name")
    T.eq(e.winner.class, "PALADIN")
    T.eq(e.winner.state, "need")
    T.eq(e.winner.roll, 87)
    T.eq(column(e.rows, "name"), "Orlen,Brisé,Corvel,Kestrel,Ayla", "every member, in the group's order")
    T.eq(column(e.rows, "guid"), "Player-1-0002,Player-1-0003,Player-1-0004,Player-1-0005,Player-1-00000001")
    T.eq(column(e.rows, "class"), "PALADIN,SHAMAN,MAGE,WARRIOR,DRUID")
    T.eq(column(e.rows, "isPlayer"), "false,false,false,false,true")
    T.eq(column(e.rows, "state"), "need,greed,pass,out,need", "nobody is choosing once it is decided")
    T.eq(column(e.rows, "roll"), "87,nil,nil,nil,42")
    T.eq(column(e.rows, "isWinner"), "true,false,false,false,false")
    T.eq(G.TuttiDB.recent[1], e, "the entry is what TuttiDB.recent holds")

    -- Copies: not the tables Rows hands out, and a later change to the card does not reach them.
    local fresh = ns.Rolls.Rows(card)
    for i, row in ipairs(e.rows) do
        T.ok(row ~= fresh[i], "row " .. i .. " is a copy")
        for k, v in pairs(fresh[i]) do T.eq(row[k], v, "row " .. i .. " " .. k) end
    end
    card.picks[KESTREL[2]] = { state = "need", roll = 99, name = KESTREL[1], class = KESTREL[3] }
    T.eq(e.rows[4].state, "out", "a pick that comes in later changes nothing")
    T.eq(e.rows[4].roll, nil)
    T.eq(#ns.History.Entries(), 1, "and adds no entry")
end)

T.it("newest first, capped at 100", function()
    local G, W, ns = T.load()
    local changed = count(ns, "HISTORY_CHANGED")
    for i = 1, 100 do ns.Fire("CARD_DECIDED", handCard(W, i)) end
    local entries = ns.History.Entries()
    T.eq(#entries, 100)
    T.eq(entries[1].name, "Item 100", "the newest first")
    T.eq(entries[100].name, "Item 1")
    ns.Fire("CARD_DECIDED", handCard(W, 101))
    entries = ns.History.Entries()
    T.eq(#entries, 100, "still 100")
    T.eq(entries[1].name, "Item 101")
    T.eq(entries[2].name, "Item 100")
    T.eq(entries[100].name, "Item 2", "the oldest went")
    T.eq(#G.TuttiDB.recent, 100, "the saved list is capped too")
    T.eq(G.TuttiDB.recent[100].name, "Item 2")
    T.eq(changed.n, 101, "one message for every entry")

    -- A list handed out is a snapshot: the caller may keep or change it.
    local kept = ns.History.Entries()
    table.remove(kept, 1)
    kept[#kept + 1] = "junk"
    T.eq(#ns.History.Entries(), 100, "changing the list changes nothing")
    T.eq(ns.History.Entries()[1].name, "Item 101")
    ns.Fire("CARD_DECIDED", handCard(W, 102))
    T.eq(kept[1].name, "Item 100", "the list that was handed out stays as it was")
    T.eq(ns.History.Entries()[1].name, "Item 102")
end)

T.it("kept on /reload, cleared at login", function()
    local G, W, ns = T.load()
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    ns.Fire("CARD_DECIDED", handCard(W, 2))
    T.eq(#ns.History.Entries(), 2)
    local saved = G.TuttiDB -- what the game writes at logout and reads back

    -- A /reload: the same session goes on. A loading screen on a zone change as well.
    G, W, ns = T.load({ db = saved, login = false })
    local changed = count(ns, "HISTORY_CHANGED")
    T.eq(#ns.History.Entries(), 2, "the saved results are there")
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(#ns.History.Entries(), 2, "kept on /reload")
    T.eq(ns.History.Entries()[1].name, "Item 2")
    W.fire("PLAYER_ENTERING_WORLD", false, false)
    T.eq(#ns.History.Entries(), 2, "kept on a zone change")
    T.eq(changed.n, 0, "and nothing was said")

    -- A login: a new session.
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    T.eq(#ns.History.Entries(), 0, "cleared at login")
    T.eq(#G.TuttiDB.recent, 0, "in the saved list too")
    T.eq(changed.n, 1, "and the views are told")
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    T.eq(changed.n, 1, "an empty list is not cleared again")

    -- The whole login, as the harness plays it.
    G, W, ns = T.load({ db = { recent = { handCard(W, 5), handCard(W, 6) } } })
    T.eq(#ns.History.Entries(), 0, "results of an earlier session are gone after login")
end)

T.it("a payload that is not plainly a login keeps the results", function()
    local G, W, ns = T.load()
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    local hidden = withSecrets(ns)
    hidden[true] = true
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    T.eq(#ns.History.Entries(), 1, "a secret yes is no login")
    hidden[true] = nil
    W.fire("PLAYER_ENTERING_WORLD", T.secret(true), false)
    W.fire("PLAYER_ENTERING_WORLD", 1, false)
    W.fire("PLAYER_ENTERING_WORLD", "true", false)
    W.fire("PLAYER_ENTERING_WORLD")
    T.eq(#ns.History.Entries(), 1, "nor is anything that is not a boolean")
end)

T.it("ages", function()
    local G, W, ns = T.load()
    local age = ns.History.Age
    local e = { at = 5000 }
    T.eq(age(e, 5000), "now")
    T.eq(age(e, 5059), "now", "under 60 s")
    T.eq(age(e, 5060), "1m")
    T.eq(age(e, 5119), "1m")
    T.eq(age(e, 5120), "2m")
    T.eq(age(e, 5000 + 6 * 60), "6m")
    T.eq(age(e, 5000 + 3599), "59m")
    T.eq(age(e, 5000 + 3600), "1h")
    T.eq(age(e, 5000 + 7199), "1h")
    T.eq(age(e, 5000 + 7200), "2h")
    T.eq(age(e, 5000 + 26 * 3600), "26h", "no days: a session can run long")
    T.eq(age(e, 4000), "now", "a clock that went back")
    -- Without `now` it is the time: an entry ages with the clock.
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    local entry = ns.History.Entries()[1]
    T.eq(age(entry), "now")
    W.advance(59)
    T.eq(age(entry), "now")
    W.advance(1)
    T.eq(age(entry), "1m")
    W.advance(60 * 60)
    T.eq(age(entry), "1h")
    -- An entry without a readable time has no age.
    T.eq(age({}, 5000), "now")
    T.eq(age(nil, 5000), "now")
    T.eq(age({ at = "later" }, 5000), "now")
end)

T.it("everyone passed and ended entries", function()
    local G, W, ns = T.load()
    local ST = G.Enum.EncounterLootDropRollState
    W.setGroup(party())

    -- Everyone passed: the game says so and names no winner.
    local card = newCard(W, ns, 7)
    W.setDrop(9, 7, dropInfo(G, W, {
        rollInfo(ORLEN, ST.Pass), rollInfo(BRISE, ST.Pass), rollInfo(CORVEL, ST.Pass),
        rollInfo(KESTREL, ST.Pass), rollInfo(AYLA, ST.Pass),
    }, { allPassed = true }))
    T.eq(card.status, "decided")
    local e = ns.History.Entries()[1]
    T.eq(e.allPassed, true)
    T.eq(e.winner, nil, "no winner")
    T.eq(e.ended, false)
    T.eq(column(e.rows, "state"), "pass,pass,pass,pass,pass")
    T.eq(column(e.rows, "isWinner"), "false,false,false,false,false")
    T.eq(e.name, "Guardian's Dualblade")

    -- A roll the history never decides ends 5 s after its time.
    local ended = newCard(W, ns, 8, { time = 30000 })
    W.advance(40)
    T.eq(ended.status, "ended")
    T.eq(#ns.History.Entries(), 2)
    local n = ns.History.Entries()[1]
    T.eq(n.ended, true)
    T.eq(n.allPassed, false)
    T.eq(n.winner, nil)
    T.eq(n.link, ended.link)
    T.eq(n.name, "Guardian's Dualblade")
    T.eq(#n.rows, 5, "every member still has a row")
    T.eq(column(n.rows, "state"), "out,out,out,out,out", "nobody picked: nobody is choosing")
    T.eq(ns.History.Entries()[2], e, "the earlier entry is the next one")

    -- Nothing is recorded twice.
    W.advance(120)
    T.eq(#ns.History.Entries(), 2)
end)

T.it("an ended roll that the player answered keeps their pick", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local card = newCard(W, ns, 7, { time = 20000 })
    T.eq(ns.Rolls.Pick(card, "greed"), true)
    W.advance(30)
    local e = ns.History.Entries()[1]
    T.eq(e.ended, true)
    T.eq(column(e.rows, "state"), "out,out,out,out,greed")
    T.eq(e.rows[5].isPlayer, true)
end)

T.it("a decision that names a winner nobody lists is an ended roll", function()
    local G, W, ns = T.load()
    -- The winner's GUID is in neither the group nor the picks, so no row can say who won.
    ns.Fire("CARD_DECIDED", handCard(W, 1, { winner = "Player-1-7777", allPassed = false }))
    local e = ns.History.Entries()[1]
    T.eq(e.winner, nil, "no one to name")
    T.eq(e.allPassed, false)
    T.eq(e.ended, true, "one of winner, allPassed and ended always holds")
    -- A winner with a row is named.
    ns.Fire("CARD_DECIDED", handCard(W, 2, { winner = "Player-1-00000001", allPassed = false,
        picks = { ["Player-1-00000001"] = { state = "need", roll = 61, name = "Ayla Brightwind", class = "DRUID", isSelf = true } } }))
    e = ns.History.Entries()[1]
    T.eq(e.winner.name, "Ayla")
    T.eq(e.winner.roll, 61)
    T.eq(e.ended, false)
    T.eq(e.rows[1].isWinner, true)
    T.eq(e.rows[1].isPlayer, true)
    -- A card that says both a winner and everyone passed is the winner's.
    ns.Fire("CARD_DECIDED", handCard(W, 3, { winner = "Player-1-00000001", allPassed = true,
        picks = { ["Player-1-00000001"] = { state = "need", roll = 61, name = "Ayla Brightwind", class = "DRUID", isSelf = true } } }))
    e = ns.History.Entries()[1]
    T.eq(e.winner.name, "Ayla")
    T.eq(e.allPassed, false, "exactly one of winner, allPassed and ended")
    T.eq(e.ended, false)
end)

T.it("a late decision updates the card's entry instead of adding one", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local changed = count(ns, "HISTORY_CHANGED")
    -- The roll ended with nobody deciding it.
    local card = handCard(W, 1, { status = "ended", allPassed = false, picks = {
        [ORLEN[2]] = { state = "greed", name = ORLEN[1], class = ORLEN[3] },
    } })
    ns.Fire("CARD_DECIDED", card)
    ns.Fire("CARD_DECIDED", handCard(W, 2)) -- a newer result after it
    local entries = ns.History.Entries()
    T.eq(#entries, 2)
    local entry = entries[2]
    T.eq(entry.cardId, card.id, "the entry knows its card")
    T.eq(entry.ended, true)
    T.eq(entry.winner, nil)
    T.eq(column(entry.rows, "state"), "greed,out,out,out,out")
    local at, place, name = entry.at, entry.place, entry.name

    -- Later the history decides it, and the same card is announced again.
    W.advance(30)
    W.zone = "Duskfall Reach"
    card.status, card.winner = "decided", AYLA[2]
    card.picks[AYLA[2]] = { state = "need", roll = 61, name = AYLA[1], class = AYLA[3], isSelf = true }
    ns.Fire("CARD_DECIDED", card)
    entries = ns.History.Entries()
    T.eq(#entries, 2, "no second entry")
    T.eq(entries[2], entry, "the same entry, still where it was: the newest-first order is the first one")
    T.eq(entries[1].name, "Item 2")
    T.eq(entry.ended, false)
    T.eq(entry.allPassed, false)
    T.eq(entry.winner.name, "Ayla", "now it has its winner")
    T.eq(entry.winner.class, "DRUID")
    T.eq(entry.winner.state, "need")
    T.eq(entry.winner.roll, 61)
    T.eq(column(entry.rows, "state"), "greed,out,out,out,need", "and the picks as they are now")
    T.eq(column(entry.rows, "isWinner"), "false,false,false,false,true")
    T.eq(entry.at, at, "the time of the first decision")
    T.eq(entry.place, place, "and its place")
    T.eq(entry.name, name)
    T.eq(G.TuttiDB.recent[2], entry, "the saved entry is the updated one")
    T.eq(#G.TuttiDB.recent, 2)
    T.eq(changed.n, 3, "HISTORY_CHANGED said so")

    -- Ended and then found to be everyone passed.
    local passed = handCard(W, 3, { status = "ended", allPassed = false })
    ns.Fire("CARD_DECIDED", passed)
    local second = ns.History.Entries()[1]
    T.eq(second.ended, true)
    passed.status, passed.allPassed = "decided", true
    ns.Fire("CARD_DECIDED", passed)
    entries = ns.History.Entries()
    T.eq(#entries, 3, "still one entry for it")
    T.eq(entries[1], second)
    T.eq(second.allPassed, true)
    T.eq(second.ended, false)
    T.eq(second.winner, nil)

    -- An announcement that changes nothing still says so, and adds nothing.
    ns.Fire("CARD_DECIDED", passed)
    T.eq(#ns.History.Entries(), 3)
    T.eq(changed.n, 6)
end)

T.it("a card that ended and is decided later keeps its one entry", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local card = newCard(W, ns, 7, { time = 20000 })
    T.eq(ns.Rolls.Pick(card, "greed"), true)
    W.advance(30)
    T.eq(card.status, "ended")
    local entry = ns.History.Entries()[1]
    T.eq(entry.cardId, card.id, "the id Core/Rolls.lua gave the card")
    T.eq(entry.ended, true)
    T.eq(column(entry.rows, "state"), "out,out,out,out,greed")
    -- What Core/Rolls.lua announces when the history gives a card that ended its decision.
    card.picks[ORLEN[2]] = { state = "need", roll = 87, name = ORLEN[1], class = ORLEN[3] }
    card.status, card.winner = "decided", ORLEN[2]
    ns.Fire("CARD_DECIDED", card)
    T.eq(#ns.History.Entries(), 1)
    T.eq(ns.History.Entries()[1], entry)
    T.eq(entry.ended, false)
    T.eq(entry.winner.name, "Orlen")
    T.eq(entry.winner.roll, 87)
    T.eq(column(entry.rows, "state"), "need,out,out,out,greed", "the player's own click is still there")
end)

T.it("cards without an id, and demo cards, never share an entry", function()
    local G, W, ns = T.load()
    ns.Fire("CARD_DECIDED", handCard(W, 1, { id = false }))
    ns.Fire("CARD_DECIDED", handCard(W, 1, { id = false }))
    ns.Fire("CARD_DECIDED", handCard(W, 1, { id = "one" }))
    ns.Fire("CARD_DECIDED", handCard(W, 1, { id = "one" }))
    T.eq(#ns.History.Entries(), 4, "an id that is no number names no card")
    T.eq(ns.History.Entries()[1].cardId, nil)

    -- A demo card and a real card may count the same number.
    G, W, ns = T.load()
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    ns.Fire("CARD_DECIDED", handCard(W, 1, { demo = true, name = "Demo item" }))
    local entries = ns.History.Entries()
    T.eq(#entries, 2, "a demo card does not take over a real card's entry")
    T.eq(entries[1].name, "Demo item")
    T.eq(entries[1].demo, true)
    T.eq(entries[2].name, "Item 1")
    ns.Fire("CARD_DECIDED", handCard(W, 1, { demo = true, name = "Demo item", allPassed = false }))
    T.eq(#ns.History.Entries(), 2, "but a demo card is its own card again")
    T.eq(ns.History.Entries()[1].ended, true)
    T.eq(ns.History.Entries()[2].ended, false, "and the real entry stays as it was")
    -- A card that says demo = false is a real card.
    local real = handCard(W, 7, { demo = false, status = "ended", allPassed = false })
    ns.Fire("CARD_DECIDED", real)
    real.status, real.allPassed = "decided", true
    ns.Fire("CARD_DECIDED", real)
    T.eq(#ns.History.Entries(), 3, "one entry for it")
    T.eq(ns.History.Entries()[1].allPassed, true)
    T.eq(ns.History.Entries()[1].demo, nil)

    -- An id that ns.IsSecret calls secret names no entry, and none is made for it by that id.
    G, W, ns = T.load()
    local hidden = withSecrets(ns)
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    hidden[1] = true
    ns.Fire("CARD_DECIDED", handCard(W, 1, { name = "Secret id" }))
    entries = ns.History.Entries()
    T.eq(#entries, 2, "a secret id is never compared")
    T.eq(entries[1].cardId, nil)
    T.eq(entries[2].cardId, 1)
end)

T.it("card ids restart at a /reload, so a new card never takes over an old entry", function()
    local G, W, ns = T.load()
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    ns.Fire("CARD_DECIDED", handCard(W, 2))
    T.eq(ns.History.Entries()[1].cardId, 2)
    local saved = G.TuttiDB

    -- The same session goes on after the /reload, and Core/Rolls.lua counts from 1 again.
    G, W, ns = T.load({ db = saved, login = false })
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    local kept = ns.History.Entries()
    T.eq(#kept, 2, "the results are kept")
    T.eq(kept[1].cardId, nil, "but the ids of the cards that are gone are not")
    T.eq(kept[2].cardId, nil)
    ns.Fire("CARD_DECIDED", handCard(W, 1, { name = "After the reload" }))
    local entries = ns.History.Entries()
    T.eq(#entries, 3, "the new card number 1 is a new entry")
    T.eq(entries[1].name, "After the reload")
    T.eq(entries[1].cardId, 1)
    T.eq(entries[2].name, "Item 2")
    T.eq(entries[3].name, "Item 1")
    ns.Fire("CARD_DECIDED", handCard(W, 1, { name = "After the reload", allPassed = false }))
    T.eq(#ns.History.Entries(), 3, "and it is found again by its id")
    T.eq(ns.History.Entries()[1].ended, true)
    T.eq(ns.History.Entries()[3].ended, false, "the old entries are as they were")
end)

T.it("place is the instance name, else the zone", function()
    local G, W, ns = T.load()
    local n = 0
    local function place()
        n = n + 1
        ns.Fire("CARD_DECIDED", handCard(W, n))
        return ns.History.Entries()[1].place
    end
    T.eq(place(), "Greymist Hollow", "outside an instance: the zone, never GetInstanceInfo's continent")
    W.instance = true
    T.eq(place(), "Stonewatch Keep", "inside one: its name")
    W.instanceName = "Hall of Embers"
    T.eq(place(), "Hall of Embers")
    W.instance = false
    W.zone = "Duskfall Reach"
    T.eq(place(), "Duskfall Reach", "back outside")
    T.eq(#ns.History.Entries(), 4)
    T.eq(ns.History.Entries()[4].place, "Greymist Hollow", "an entry keeps the place it was made in")
end)

T.it("a place the game keeps from the addon falls back, down to Unknown", function()
    local G, W, ns = T.load()
    local n = 0
    local function place()
        n = n + 1
        ns.Fire("CARD_DECIDED", handCard(W, n))
        return ns.History.Entries()[1].place
    end
    W.instance = true
    W.instanceName = T.secret("Stonewatch Keep")
    T.eq(place(), "Greymist Hollow", "a secret instance name: the zone")
    W.instanceName = ""
    T.eq(place(), "Greymist Hollow", "an empty one too")
    W.zone = T.secret("Greymist Hollow")
    T.eq(place(), "Unknown", "and with no zone either")
    W.zone = nil
    T.eq(place(), "Unknown")
    G.UNKNOWN = "Unbekannt"
    T.eq(place(), "Unbekannt", "the game's own word when it has one")
    W.instanceName = "Stonewatch Keep"
    T.eq(place(), "Stonewatch Keep")

    local hidden = withSecrets(ns)
    hidden["Stonewatch Keep"] = true
    W.zone = "Duskfall Reach"
    T.eq(place(), "Duskfall Reach", "a name ns.IsSecret calls secret is not read")
    hidden["Stonewatch Keep"] = nil
    hidden[true] = true
    T.eq(place(), "Duskfall Reach", "a secret yes from IsInInstance is no instance: the zone")
end)

T.it("a client without the place functions still records", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    G.GetInstanceInfo, G.GetRealZoneText, G.IsInInstance = nil, nil, nil
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    T.eq(ns.History.Entries()[1].place, "Unknown")
    T.eq(#errors, 0)
end)

T.it("a demo card is recorded, marked, and dropped at the next login", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local real = handCard(W, 1)
    ns.Fire("CARD_DECIDED", real)
    ns.Fire("CARD_DECIDED", handCard(W, 2, { demo = true }))
    local entries = ns.History.Entries()
    T.eq(#entries, 2)
    T.eq(entries[1].demo, true, "marked")
    T.eq(entries[1].name, "Item 2")
    T.eq(entries[2].demo, nil, "a real roll is not")
    T.eq(#entries[1].rows, 5, "with its rows like any other")

    -- Kept on a /reload as any entry is, gone with the next login.
    G, W, ns = T.load({ db = G.TuttiDB, login = false })
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    T.eq(#ns.History.Entries(), 2)
    T.eq(ns.History.Entries()[1].demo, true)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    T.eq(#ns.History.Entries(), 0)
end)

T.it("an entry holds plain values only", function()
    local G, W, ns = T.load()
    local hidden = withSecrets(ns)
    hidden["Item 1"] = true
    ns.Fire("CARD_DECIDED", handCard(W, 1, { link = T.secret("x"), icon = {}, quality = "epic" }))
    local e = ns.History.Entries()[1]
    T.eq(e.link, nil, "a secret link is left out")
    T.eq(e.name, nil, "a name ns.IsSecret calls secret as well")
    T.eq(e.icon, nil, "an icon that is no file ID or path")
    T.eq(e.quality, nil, "a quality that is no number")
    T.eq(e.at, G.time())
    hidden["Item 1"] = nil
    ns.Fire("CARD_DECIDED", handCard(W, 2, { icon = "Interface\\Icons\\INV_Axe_01" }))
    T.eq(ns.History.Entries()[1].icon, "Interface\\Icons\\INV_Axe_01", "a texture path is a fine icon")

    -- Rows keep strings, numbers and booleans; anything else is left out.
    local real = ns.Rolls.Rows
    ns.Rolls.Rows = function()
        return { { guid = "Player-1-0002", name = "Orlen", class = "PALADIN", isPlayer = false, state = "need",
            roll = 87, isWinner = true, junk = function() end, more = {}, hidden = T.secret("x") } }
    end
    ns.Fire("CARD_DECIDED", handCard(W, 3))
    ns.Rolls.Rows = real
    local row = ns.History.Entries()[1].rows[1]
    T.eq(row.name, "Orlen")
    T.eq(row.roll, 87)
    T.eq(row.isWinner, true)
    T.eq(row.isPlayer, false, "a false stays")
    T.eq(row.junk, nil)
    T.eq(row.more, nil)
    T.eq(row.hidden, nil)
    T.eq(ns.History.Entries()[1].winner.name, "Orlen")
end)

T.it("a message that is no card, or comes before the database, records nothing", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local changed = count(ns, "HISTORY_CHANGED")
    ns.Fire("CARD_DECIDED")
    ns.Fire("CARD_DECIDED", "a card")
    ns.Fire("CARD_DECIDED", 5)
    ns.Fire("CARD_DECIDED", T.secret({}))
    local hidden = withSecrets(ns)
    local secretCard = handCard(W, 1)
    hidden[secretCard] = true
    ns.Fire("CARD_DECIDED", secretCard)
    T.eq(#ns.History.Entries(), 0, "a card ns.IsSecret calls secret is never read")
    local db = ns.DB
    ns.DB = nil
    ns.Fire("CARD_DECIDED", handCard(W, 1))
    T.eq(#ns.History.Entries(), 0, "no database: nothing to write to")
    ns.DB = db
    T.eq(#db.recent, 0)
    T.eq(changed.n, 0)
    T.eq(#errors, 0)
end)

T.it("a saved list with damaged items still lists the good ones", function()
    local _, W0 = T.load({ login = false }) -- only for W.itemLink
    local G, W, ns = T.load({ login = false, db = { recent = { "junk", 5, handCard(W0, 1), false, handCard(W0, 2) } } })
    local entries = ns.History.Entries()
    T.eq(#entries, 2)
    T.eq(entries[1].name, "Item 1")
    T.eq(entries[2].name, "Item 2")
    -- A saved value that is no list at all is replaced by one.
    G, W, ns = T.load({ login = false })
    ns.DB.recent = "oops"
    ns.Fire("CARD_DECIDED", handCard(W, 3))
    T.eq(#ns.History.Entries(), 1)
    T.eq(type(ns.DB.recent), "table")
end)
