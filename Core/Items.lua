-------------------------------------------------------------------------------
--  Tutti: what an item is, in the words of a card's subtitle.
--    ns.Items.Describe(link)  label, ilvl     "Two-Hand Axe", 33
--    ns.Items.ID(link)        the item ID a link names, or nil
--  The label reads like the game's tooltip: the slot, with the armor type or the weapon kind
--  beside it ("Leather Hands", "Mail Feet", "Two-Hand Axe", "Held In Off-hand"). The words come
--  from the game: the slot's global string and the armor type of the item info. Only the weapon
--  kinds are Tutti's own, in English, because the game has them in the plural.
--  An item that is not in the client's cache has no label and no level (both nil); the game
--  fetches it and says so with GET_ITEM_INFO_RECEIVED, and the caller asks again.
-------------------------------------------------------------------------------
local _, ns = ...
local Items = {}
ns.Items = Items

-- A weapon's kind in the singular, by item subclass (Enum.ItemWeaponSubclass).
local WEAPON = {
    [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm",
    [7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown",
    [18] = "Crossbow", [19] = "Wand",
}

-- Armor that is no material (Enum.ItemArmorSubclass): the word names the item by itself, and a
-- slot beside it would only repeat it or read oddly ("Shields Off Hand").
local ARMOR_ALONE = { [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem", [10] = "Sigil", [11] = "Relic" }

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
local SUBCLASS_MISC = 0

-- A non-empty string the game gave in the clear, else nil. A secret value must never be
-- compared, indexed or stored.
local function text(value)
    if ns.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

function Items.ID(link)
    link = text(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

-- The game's word for an equip location ("INVTYPE_HAND" -> "Hands"), nil when it has none.
local function slotName(equipLoc)
    if not (text(equipLoc) and equipLoc:find("^INVTYPE_")) then return nil end
    return text(_G[equipLoc])
end

local function labelOf(classID, subclassID, equipLoc, itemType, subType)
    local slot = slotName(equipLoc)
    local label
    if classID == CLASS_WEAPON then
        local kind = WEAPON[subclassID]
        if slot and kind and slot ~= kind then label = slot .. " " .. kind else label = slot or kind end
    elseif classID == CLASS_ARMOR then
        if ARMOR_ALONE[subclassID] then
            label = ARMOR_ALONE[subclassID]
        elseif slot and subType and subclassID ~= SUBCLASS_MISC and equipLoc ~= "INVTYPE_HOLDABLE" then
            label = subType .. " " .. slot
        else
            label = slot -- a ring, a neck, a holdable: no material to name
        end
    else
        label = slot
    end
    -- Nothing to wear (a recipe, a potion): what the game calls the item.
    return label or itemType
end

function Items.Describe(link)
    link = text(link)
    if not link then return nil, nil end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(get) ~= "function" then return nil, nil end
    local name, _, _, level, _, itemType, subType, _, equipLoc, _, _, classID, subclassID = get(link)
    if ns.IsSecret(name, level, itemType, subType, equipLoc, classID, subclassID) or type(name) ~= "string" then
        return nil, nil
    end
    if type(level) ~= "number" or level < 1 then level = nil end
    return labelOf(classID, subclassID, equipLoc, text(itemType), text(subType)), level
end
