local T = T

-- A sample party, in party1..party4. The player is the fake's Ayla
-- Brightwind (a druid); a party's list leaves the player out, as the game's party units do.
local function party()
    return {
        { unit = "party1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "party3", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "party4", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- The same five as a raid, the player in the third slot: a raid's list holds the player.
local function raid()
    return {
        { unit = "raid1", name = "Orlen Brightmoor", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "raid2", name = "Brisé Tidewater", classFile = "SHAMAN", guid = "Player-1-0003" },
        { unit = "raid3", isPlayer = true },
        { unit = "raid4", name = "Corvel Duskmantle", classFile = "MAGE", guid = "Player-1-0004" },
        { unit = "raid5", name = "Kestrel Ironmark", classFile = "WARRIOR", guid = "Player-1-0005" },
    }
end

-- One field of every member as a comma-joined string, so a failure shows the whole list.
local function column(list, key)
    local out = {}
    for i, m in ipairs(list) do out[i] = tostring(m[key]) end
    return table.concat(out, ",")
end

T.it("party order is party1..party4, then the player", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local list = ns.Group.Members()
    T.eq(column(list, "first"), "Orlen,Brisé,Corvel,Kestrel,Ayla")
    T.eq(column(list, "unit"), "party1,party2,party3,party4,player")
    T.eq(column(list, "name"), "Orlen Brightmoor,Brisé Tidewater,Corvel Duskmantle,Kestrel Ironmark,Ayla Brightwind")
    T.eq(column(list, "class"), "PALADIN,SHAMAN,MAGE,WARRIOR,DRUID")
    T.eq(column(list, "guid"), "Player-1-0002,Player-1-0003,Player-1-0004,Player-1-0005,Player-1-00000001")
    T.eq(column(list, "isPlayer"), "false,false,false,false,true", "only the last one is the player")
    T.eq(ns.Group.IsRaid(), false)
end)

T.it("raid order follows raid1..raidN and marks the player", function()
    local G, W, ns = T.load()
    W.setGroup(raid(), { raid = true })
    local list = ns.Group.Members()
    T.eq(column(list, "unit"), "raid1,raid2,raid3,raid4,raid5", "the player stays in their own slot")
    T.eq(column(list, "first"), "Orlen,Brisé,Ayla,Corvel,Kestrel")
    T.eq(column(list, "isPlayer"), "false,false,true,false,false")
    T.eq(list[3].guid, "Player-1-00000001")
    T.eq(list[3].name, "Ayla Brightwind")
    T.eq(list[3].class, "DRUID")
    T.eq(ns.Group.IsRaid(), true)
end)

T.it("the first name is UnitName's first return on Forever", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local first, surname = G.UnitName("party1")
    T.eq(first, "Orlen", "Forever returns the first name ...")
    T.eq(surname, "Brightmoor", "... and the surname")
    local m = ns.Group.Members()[1]
    T.eq(m.first, first)
    T.eq(m.name, "Orlen Brightmoor", "the full name joins both")
end)

T.it("on a client without surnames the second value is a realm", function()
    local G, W, ns = T.load({ setup = function(G, W) W.run = false; W.player.name = "Ayla" end })
    W.setGroup({
        { unit = "party1", name = "Orlen", realm = "Elsewhere", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Corvel", classFile = "MAGE", guid = "Player-1-0004" },
    })
    local list = ns.Group.Members()
    T.eq(column(list, "name"), "Orlen-Elsewhere,Corvel,Ayla", "another realm joins with a hyphen, the own one is left out")
    T.eq(column(list, "first"), "Orlen,Corvel,Ayla")
end)

T.it("FirstName splits 'Orlen Brightmoor' and 'Orlen-Brightmoor' to 'Orlen'", function()
    local G, W, ns = T.load()
    local first = ns.Group.FirstName
    T.eq(first("Orlen Brightmoor"), "Orlen")
    T.eq(first("Orlen-Brightmoor"), "Orlen")
    T.eq(first("Brisé Tidewater"), "Brisé", "an accented name")
    T.eq(first("Orlen"), "Orlen", "one word stays as it is")
    T.eq(first("Orlen Brightmoor-Realm"), "Orlen")
    T.eq(first(""), "")
    T.eq(first(nil), "", "no name, no first name")
    T.eq(first(5), "")
    T.eq(first(T.secret("Orlen Brightmoor")), "", "a secret is never read")
end)

T.it("members with a secret or missing GUID are skipped", function()
    local G, W, ns = T.load()
    local list = party()
    list[2].guid = T.secret("Player-1-9")
    list[3].guid = nil
    W.setGroup(list)
    local members = ns.Group.Members()
    T.eq(column(members, "first"), "Orlen,Kestrel,Ayla")
    T.eq(column(members, "unit"), "party1,party4,player")
    T.eq(ns.Group.ByGUID("Player-1-0002").first, "Orlen")
    T.eq(ns.Group.ByGUID("Player-1-0003"), nil, "the real GUID of the skipped one is not in the list")
end)

T.it("a member whose name the game does not give is skipped", function()
    local G, W, ns = T.load()
    local list = party()
    list[1].name = T.secret("Hidden Name")
    list[2].name = nil
    W.setGroup(list)
    T.eq(column(ns.Group.Members(), "first"), "Corvel,Kestrel,Ayla")
end)

T.it("a member whose class the game does not give stays, without a class", function()
    local G, W, ns = T.load()
    local list = party()
    list[2].classFile = nil
    list[3].classFile = T.secret("MAGE")
    W.setGroup(list)
    local members = ns.Group.Members()
    T.eq(column(members, "first"), "Orlen,Brisé,Corvel,Kestrel,Ayla")
    T.eq(column(members, "class"), "PALADIN,nil,nil,WARRIOR,DRUID")
end)

T.it("every game value passes ns.IsSecret first, not just a type check", function()
    local G, W, ns = T.load()
    -- A secret string in the game still has type "string", so the fake's userdata secrets prove
    -- little. Here plain strings play secrets by being named in `hidden`.
    local hidden = {}
    ns.IsSecret = function(...)
        for i = 1, select("#", ...) do
            if hidden[(select(i, ...))] then return true end
        end
        return false
    end
    hidden["Player-1-0003"], hidden["Corvel"], hidden["WARRIOR"] = true, true, true
    W.setGroup(party())
    local list = ns.Group.Members()
    T.eq(column(list, "first"), "Orlen,Kestrel,Ayla", "a secret GUID and a secret name are skipped")
    T.eq(column(list, "class"), "PALADIN,nil,DRUID", "a secret class is left out")
    hidden["Player-1-0002"], hidden["Orlen Brightmoor"] = true, true
    T.eq(ns.Group.ByGUID("Player-1-0002"), nil, "a secret is never a key")
    T.eq(ns.Group.FirstName("Orlen Brightmoor"), "", "a secret name is never read")
end)

T.it("one GUID is listed once", function()
    local G, W, ns = T.load()
    local list = party()
    list[3].guid = list[1].guid
    W.setGroup(list)
    T.eq(column(ns.Group.Members(), "first"), "Orlen,Brisé,Kestrel,Ayla", "the first slot keeps the GUID")
    T.eq(ns.Group.ByGUID("Player-1-0002").unit, "party1")
end)

T.it("the player is listed even when the game shows no raid members yet", function()
    local G, W, ns = T.load()
    G.IsInRaid = function() return true end
    G.GetNumGroupMembers = function() return 0 end
    W.fire("GROUP_ROSTER_UPDATE")
    local list = ns.Group.Members()
    T.eq(#list, 1)
    T.eq(list[1].isPlayer, true)
    T.eq(list[1].first, "Ayla")
    T.eq(ns.Group.IsRaid(), true)
end)

T.it("ByGUID finds a member by GUID and shrugs at anything else", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local m = ns.Group.ByGUID("Player-1-0003")
    T.eq(m.first, "Brisé")
    T.eq(m, ns.Group.Members()[2], "the very member of the list")
    T.eq(ns.Group.ByGUID("Player-1-00000001").isPlayer, true, "the player too")
    T.eq(ns.Group.ByGUID("Player-1-1234"), nil, "a stranger")
    T.eq(ns.Group.ByGUID(nil), nil)
    T.eq(ns.Group.ByGUID(42), nil)
    T.eq(ns.Group.ByGUID(T.secret("Player-1-0003")), nil, "a secret is never used as a key")
    W.setGroup(nil)
    T.eq(ns.Group.ByGUID("Player-1-0003"), nil, "gone with the group")
    T.eq(ns.Group.ByGUID("Player-1-00000001").first, "Ayla", "the player stays")
end)

T.it("GROUP_ROSTER_UPDATE fires GROUP_CHANGED", function()
    local G, W, ns = T.load()
    local seen = {}
    ns.Listen("GROUP_CHANGED", function() seen[#seen + 1] = #ns.Group.Members() end)
    W.setGroup(party()) -- the fake client fires GROUP_ROSTER_UPDATE, as the game does
    T.eq(#seen, 1, "one message")
    T.eq(seen[1], 5, "the list was rebuilt before the message went out")
    W.fire("GROUP_ROSTER_UPDATE")
    T.eq(#seen, 2, "every roster event says so")
    W.setGroup(nil)
    T.eq(#seen, 3)
    T.eq(seen[3], 1, "back to the player alone")
end)

T.it("PLAYER_ENTERING_WORLD rebuilds the list and says so", function()
    local G, W, ns = T.load()
    local n = 0
    ns.Listen("GROUP_CHANGED", function() n = n + 1 end)
    W.setGroup(party(), { silent = true }) -- the roster changed behind a loading screen
    T.eq(#ns.Group.Members(), 1, "nothing heard yet")
    W.fire("PLAYER_ENTERING_WORLD", false, false)
    T.eq(#ns.Group.Members(), 5)
    T.eq(n, 1)
end)

T.it("the list is built when the addon loads", function()
    local G, W, ns = T.load({ login = false, setup = function(G, W) W.setGroup(party(), { silent = true }) end })
    T.eq(column(ns.Group.Members(), "first"), "Orlen,Brisé,Corvel,Kestrel,Ayla")
end)

T.it("the list follows the roster, and a list already handed out stays as it was", function()
    local G, W, ns = T.load()
    W.setGroup(party())
    local held = ns.Group.Members()
    local small = party()
    small[4], small[3] = nil, nil
    W.setGroup(small)
    T.eq(column(ns.Group.Members(), "first"), "Orlen,Brisé,Ayla", "two left")
    W.setGroup(raid(), { raid = true })
    T.eq(#ns.Group.Members(), 5, "the party became a raid")
    T.eq(ns.Group.IsRaid(), true)
    W.setGroup(nil)
    T.eq(column(ns.Group.Members(), "first"), "Ayla")
    T.eq(ns.Group.IsRaid(), false)
    T.eq(column(held, "first"), "Orlen,Brisé,Corvel,Kestrel,Ayla", "the old list is a snapshot")
end)

T.it("solo: only the player", function()
    local G, W, ns = T.load()
    local list = ns.Group.Members()
    T.eq(#list, 1)
    local me = list[1]
    T.eq(me.unit, "player")
    T.eq(me.guid, "Player-1-00000001")
    T.eq(me.name, "Ayla Brightwind")
    T.eq(me.first, "Ayla")
    T.eq(me.class, "DRUID")
    T.eq(me.isPlayer, true)
    T.eq(ns.Group.IsRaid(), false)
    T.eq(ns.Group.ByGUID("Player-1-00000001"), me)
end)

T.it("the fake client's group follows the list", function()
    local G, W = T.load()
    T.eq(G.IsInGroup(), false)
    T.eq(G.IsInRaid(), false)
    T.eq(G.GetNumGroupMembers(), 0)
    W.setGroup(party())
    T.eq(G.IsInGroup(), true)
    T.eq(G.IsInRaid(), false)
    T.eq(G.GetNumGroupMembers(), 5, "a party counts the player")
    T.eq(G.UnitGUID("party2"), "Player-1-0003")
    local first, surname = G.UnitName("party2")
    T.eq(first, "Brisé")
    T.eq(surname, "Tidewater")
    T.eq(select(2, G.UnitClass("party2")), "SHAMAN")
    T.eq(G.UnitExists("party5"), false)
    W.setGroup(raid(), { raid = true })
    T.eq(G.IsInRaid(), true)
    T.eq(G.GetNumGroupMembers(), 5)
    T.eq(G.UnitGUID("raid3"), G.UnitGUID("player"), "raid3 is the player")
    T.eq(G.UnitExists("party1"), false, "the party's units are gone")
    W.setGroup(nil)
    T.eq(G.IsInGroup(), false)
    T.eq(G.GetNumGroupMembers(), 0)
    T.eq(G.UnitExists("raid1"), false)
end)

T.it("a member the game names Unknown after a raid /reload is listed once its name arrives (final review, item 10)",
    function()
    local G, W, ns = T.load()
    G.UNKNOWNOBJECT = "Unknown"
    local list = raid()
    local real = list[4].name
    list[4].name = "Unknown" -- the game has not got the member's name yet
    W.setGroup(list, { raid = true })
    T.eq(column(ns.Group.Members(), "unit"), "raid1,raid2,raid3,raid5", "not listed as Unknown")
    local changed = 0
    ns.Listen("GROUP_CHANGED", function() changed = changed + 1 end)
    -- The name arrives: the game says so for the unit.
    W.units.raid4.name = real
    W.fire("UNIT_NAME_UPDATE", "raid4")
    T.eq(column(ns.Group.Members(), "unit"), "raid1,raid2,raid3,raid4,raid5", "now listed in its slot")
    T.eq(ns.Group.Members()[4].name, real)
    T.eq(changed, 1, "GROUP_CHANGED")
    -- A name update that changes nothing, or for a unit outside the group, rebuilds nothing.
    W.fire("UNIT_NAME_UPDATE", "raid4")
    W.fire("UNIT_NAME_UPDATE", "target")
    W.fire("UNIT_NAME_UPDATE", "player")
    W.fire("UNIT_NAME_UPDATE", T.secret("raid4"))
    W.fire("UNIT_NAME_UPDATE", nil)
    T.eq(changed, 1, "nothing new")
    -- A party member renamed (a name change while grouped) is picked up too.
    W.setGroup(party())
    W.units.party2.name = "Kestrel Ironmark"
    W.fire("UNIT_NAME_UPDATE", "party2")
    T.eq(ns.Group.Members()[2].first, "Kestrel")
end)

T.it("a raid's size and flag pass ns.Clear (final review, item 10)", function()
    local G, W, ns = T.load()
    W.setGroup(raid(), { raid = true })
    T.eq(#ns.Group.Members(), 5)
    G.GetNumGroupMembers = function() return T.secret(5) end
    W.fire("GROUP_ROSTER_UPDATE")
    T.eq(column(ns.Group.Members(), "unit"), "player", "a size the game keeps secret lists no raid slot")
    T.eq(ns.Group.IsRaid(), true)
    G.GetNumGroupMembers = function() return 5 end
    G.IsInRaid = function() return T.secret(true) end
    W.fire("GROUP_ROSTER_UPDATE")
    T.eq(ns.Group.IsRaid(), false, "a secret raid flag is no raid")
    G.IsInRaid = function() return true end
    G.GetNumGroupMembers = function() return 100 end
    local asked, guid = {}, G.UnitGUID
    G.UnitGUID = function(unit) asked[#asked + 1] = unit; return guid(unit) end
    W.fire("GROUP_ROSTER_UPDATE")
    T.eq(#ns.Group.Members(), 5, "the slots the game fills")
    local last = 0
    for _, unit in ipairs(asked) do last = math.max(last, tonumber(unit:match("^raid(%d+)$")) or 0) end
    T.eq(last, 40, "a raid is 40 slots at most")
end)

T.it("ByName finds a member by the name the Classic loot history gives, with or without the realm", function()
    local G, W, ns = T.load({ setup = function(G, W) W.run = false end })
    W.setGroup({
        { unit = "party1", name = "Orlen", classFile = "PALADIN", guid = "Player-1-0002" },
        { unit = "party2", name = "Brise", realm = "Stormrage", classFile = "SHAMAN", guid = "Player-9-0003" },
    })
    T.eq(ns.Group.ByName("Orlen").guid, "Player-1-0002")
    T.eq(ns.Group.ByName("orlen").guid, "Player-1-0002", "without case")
    T.eq(ns.Group.ByName("Brise-Stormrage").guid, "Player-9-0003")
    T.eq(ns.Group.ByName("Brise").guid, "Player-9-0003", "the history without the realm")
    T.eq(ns.Group.ByName("Orlen-Silvermoon").guid, "Player-1-0002", "the history with the player's own realm")
    T.eq(ns.Group.ByName("Brise-Kazzak"), nil, "another realm's Brise is someone else")
    T.eq(ns.Group.ByName("Kestrel"), nil)
    T.eq(ns.Group.ByName(T.secret("Orlen")), nil, "a secret name is never compared")
end)
