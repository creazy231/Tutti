-------------------------------------------------------------------------------
--  Tutti: the group's members in the order of the party frames: party1..party4
--  and then the player; in a raid raid1..raidN, the player in their own slot.
--    ns.Group.Members()        the list; a member is { unit, guid, name, first, class, isPlayer }
--                              (name "Orlen Brightmoor", first "Orlen", class "PALADIN")
--    ns.Group.ByGUID(guid)     one member
--    ns.Group.IsRaid()         the group is a raid
--    ns.Group.FirstName(name)  "Orlen Brightmoor" or "Orlen-Brightmoor" -> "Orlen"
--  The list is rebuilt on GROUP_ROSTER_UPDATE and PLAYER_ENTERING_WORLD (and once at
--  load), then "GROUP_CHANGED" goes out. A rebuild makes a new list and never touches
--  the old one, so a list a card holds stays a snapshot; treat it as read-only.
--  A member needs a readable GUID and name: the 12.x engine can hide identities, and
--  the game can be a moment late with a new member. The class may be missing.
-------------------------------------------------------------------------------
local _, ns = ...
local Group = {}
ns.Group = Group

local MAX_PARTY = 4 -- party1..party4; the player is not among them

local members, byGUID, raid = {}, {}, false

local readable = ns.Text -- a non-empty string the game gave in the clear, else nil

-- The first word of a name. Forever names are a first name and a surname ("Orlen Brightmoor"),
-- and its chat box takes them as "Orlen-Brightmoor" too. Not a readable string: "".
function Group.FirstName(fullName)
    local name = readable(fullName)
    return name and name:match("^[%s%-]*([^%s%-]+)") or ""
end

local function surnames()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() and true or false
end

local function separator()
    local c = Constants and Constants.CharacterNameSeparatorConsts
    return (c and c.CHARACTERNAME_SURNAME_SEPARATOR) or " "
end

-- The unit's full name and first name ("Orlen Brightmoor", "Orlen"), nil when the game gives none or
-- keeps it secret. On Forever UnitName returns the first name and the surname; on another
-- client the name and, for a player of another realm, the realm.
local function namesOf(unit)
    local first, second = UnitName(unit)
    if ns.IsSecret(first, second) or type(first) ~= "string" or first == "" then return nil end
    if type(second) ~= "string" or second == "" then return first, first end
    return first .. (surnames() and separator() or "-") .. second, first
end

-- One member, nil when the unit has no readable GUID or name.
local function memberOf(unit, playerGUID)
    local guid = readable(UnitGUID(unit))
    if not guid then return nil end
    local name, first = namesOf(unit)
    if not name then return nil end
    local _, class = UnitClass(unit)
    return { unit = unit, guid = guid, name = name, first = first, class = readable(class),
        isPlayer = guid == playerGUID }
end

local function rebuild()
    local list, index = {}, {}
    local inRaid = IsInRaid() and true or false
    local playerGUID = readable(UnitGUID("player"))

    -- One GUID is one member: the first slot that shows it keeps it.
    local function add(unit)
        local member = memberOf(unit, playerGUID)
        if member and not index[member.guid] then
            list[#list + 1] = member
            index[member.guid] = member
        end
    end

    -- A raid is raid1..GetNumGroupMembers(); a party is party1..party4, and a unit that is not
    -- there has no GUID.
    if inRaid then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        for i = 1, MAX_PARTY do add("party" .. i) end
    end
    -- The player closes a party; a raid shows them in a slot already. Either way they are listed.
    if not (playerGUID and index[playerGUID]) then add("player") end

    members, byGUID, raid = list, index, inRaid
end

function Group.Members() return members end

function Group.ByGUID(guid)
    guid = readable(guid)
    return guid and byGUID[guid] or nil
end

function Group.IsRaid() return raid end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local function refresh()
    rebuild()
    ns.Fire("GROUP_CHANGED")
end

ns.On("GROUP_ROSTER_UPDATE", refresh)
ns.On("PLAYER_ENTERING_WORLD", refresh)

-- The game may not know the group yet; PLAYER_ENTERING_WORLD builds it again.
ns.Safe(rebuild)
