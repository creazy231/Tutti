local T = T

-- One item put into the fake's cache, then described through the link a roll would carry.
local lastID = 5000
local function describe(W, ns, item)
    lastID = lastID + 1
    item.name = item.name or "Test Item"
    W.items[lastID] = item
    return ns.Items.Describe(W.itemLink(lastID, item.name))
end

-- label(classID, subclassID, equipLoc [, extra fields of the item]) -> the label alone
local function labeler(W, ns)
    return function(classID, subclassID, equipLoc, extra)
        local item = { classID = classID, subclassID = subclassID, equipLoc = equipLoc, ilvl = 33 }
        for k, v in pairs(extra or {}) do item[k] = v end
        return (describe(W, ns, item))
    end
end

T.it("type labels as the mockup shows them", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    T.eq(label(2, 1, "INVTYPE_2HWEAPON"), "Two-Hand Axe", "a two-hand axe")
    T.eq(label(4, 2, "INVTYPE_HAND"), "Leather Hands", "leather gloves")
    T.eq(label(4, 0, "INVTYPE_HOLDABLE"), "Held In Off-hand", "a holdable drops the subtype")
    T.eq(label(4, 3, "INVTYPE_FEET"), "Mail Feet", "mail boots")
    T.eq(label(4, 1, "INVTYPE_CHEST"), "Cloth Chest", "a cloth chest")
    T.eq(label(4, 1, "INVTYPE_ROBE"), "Cloth Chest", "a robe reads as a chest")
end)

T.it("weapons name their kind after the slot", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    local words = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm",
        [7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown",
        [18] = "Crossbow", [19] = "Wand" }
    for subclass, word in pairs(words) do
        T.eq(label(2, subclass, "INVTYPE_WEAPON"), "One-Hand " .. word, "subclass " .. subclass)
    end
    T.eq(label(2, 2, "INVTYPE_RANGED"), "Ranged Bow")
    T.eq(label(2, 19, "INVTYPE_RANGEDRIGHT"), "Ranged Wand")
    T.eq(label(2, 10, "INVTYPE_2HWEAPON"), "Two-Hand Staff")
    T.eq(label(2, 4, "INVTYPE_WEAPONMAINHAND"), "Main Hand Mace")
    T.eq(label(2, 16, "INVTYPE_THROWN"), "Thrown", "a slot and a kind that are the same word are said once")
    T.eq(label(2, 20, "INVTYPE_2HWEAPON"), "Two-Hand", "a kind without a word: the slot alone")
    T.eq(label(2, 9, "INVTYPE_WEAPON"), "One-Hand", "a warglaive has no word either")
end)

T.it("armor that is no material reads as its slot", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    T.eq(label(4, 0, "INVTYPE_FINGER"), "Finger")
    T.eq(label(4, 0, "INVTYPE_NECK"), "Neck")
    T.eq(label(4, 0, "INVTYPE_TRINKET"), "Trinket")
    T.eq(label(4, 1, "INVTYPE_CLOAK"), "Cloth Back", "a cloak is cloth worn on the back")
end)

T.it("shields and class relics read as their own word", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    T.eq(label(4, 6, "INVTYPE_SHIELD"), "Shield", "not 'Shields Off Hand'")
    T.eq(label(4, 7, "INVTYPE_RELIC"), "Libram")
    T.eq(label(4, 8, "INVTYPE_RELIC"), "Idol")
    T.eq(label(4, 9, "INVTYPE_RELIC"), "Totem")
    T.eq(label(4, 10, "INVTYPE_RELIC"), "Sigil")
    T.eq(label(4, 11, "INVTYPE_RELIC"), "Relic")
end)

T.it("the armor type comes from the game, in its language", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    T.eq(label(4, 2, "INVTYPE_HAND", { subType = "Leder" }), "Leder Hands", "the item info's own word")
    T.eq(label(4, 2, "INVTYPE_HAND", { subType = "" }), "Hands", "no word, the slot alone")
end)

T.it("an item without a slot reads as the game's item type", function()
    local G, W, ns = T.load()
    local label = labeler(W, ns)
    T.eq(label(0, 0, ""), "Consumable")
    T.eq(label(9, 0, ""), "Recipe")
    T.eq(label(4, 2, "ITEM_QUALITY_COLORS"), "Armor", "a name that is no slot is not read as one")
    T.eq(label(4, 2, "INVTYPE_NOT_IN_THIS_CLIENT"), "Armor", "a slot the client has no word for")
end)

T.it("uncached → nil, nil", function()
    local G, W, ns = T.load()
    local label, ilvl = ns.Items.Describe(W.itemLink(6001, "Never Seen"))
    T.eq(label, nil, "label")
    T.eq(ilvl, nil, "ilvl")
    for _, junk in ipairs({ "", 42, true, T.secret("x") }) do
        label, ilvl = ns.Items.Describe(junk)
        T.eq(label, nil, "label of " .. T.fmt(type(junk)))
        T.eq(ilvl, nil, "ilvl of " .. T.fmt(type(junk)))
    end
    label, ilvl = ns.Items.Describe(nil)
    T.eq(label, nil)
    T.eq(ilvl, nil)
    W.items[6002] = { name = T.secret("Hidden"), classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND", ilvl = 33 }
    label, ilvl = ns.Items.Describe(W.itemLink(6002, "x"))
    T.eq(label, nil, "an item the game keeps secret is as good as uncached")
    T.eq(ilvl, nil)
end)

T.it("every game value passes ns.IsSecret first, not just a type check", function()
    local G, W, ns = T.load()
    -- A secret string in the game still has type "string", so the fake's userdata secrets prove
    -- little. Here plain values play secrets by being named in `hidden`.
    local hidden = {}
    ns.IsSecret = function(...)
        for i = 1, select("#", ...) do
            if hidden[(select(i, ...))] then return true end
        end
        return false
    end
    W.items[7001] = { name = "Gauntlets", classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND", ilvl = 33 }
    local link = W.itemLink(7001, "Gauntlets")
    local label, ilvl = ns.Items.Describe(link)
    T.eq(label, "Leather Hands", "readable at first")
    T.eq(ilvl, 33)
    for _, value in ipairs({ "INVTYPE_HAND", "Gauntlets", "Leather", 33, 2, 4 }) do
        hidden[value] = true
        label, ilvl = ns.Items.Describe(link)
        T.eq(label, nil, "a secret " .. tostring(value) .. " makes the answer unreadable")
        T.eq(ilvl, nil)
        hidden[value] = nil
    end
    hidden[link] = true
    label, ilvl = ns.Items.Describe(link)
    T.eq(label, nil, "a secret link is never passed on")
    T.eq(ilvl, nil)
    T.eq(ns.Items.ID(link), nil, "or read")
    hidden[link] = nil
    T.eq((ns.Items.Describe(link)), "Leather Hands", "readable again")
end)

T.it("item level comes from GetItemInfo", function()
    local G, W, ns = T.load()
    local label, ilvl = describe(W, ns, { classID = 2, subclassID = 1, equipLoc = "INVTYPE_2HWEAPON", ilvl = 33 })
    T.eq(label, "Two-Hand Axe")
    T.eq(ilvl, 33)
    label, ilvl = describe(W, ns, { classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND", ilvl = 0 })
    T.eq(label, "Leather Hands", "the label stays")
    T.eq(ilvl, nil, "level 0 is no level")
    label, ilvl = describe(W, ns, { classID = 4, subclassID = 2, equipLoc = "INVTYPE_HAND" })
    T.eq(ilvl, nil, "the game gave none")
end)

T.it("ID reads the item ID out of a link", function()
    local G, W, ns = T.load()
    T.eq(ns.Items.ID(W.itemLink(18000, "Guardian's Dualblade")), 18000)
    T.eq(ns.Items.ID("item:77"), 77, "a bare item string")
    T.eq(ns.Items.ID("|cffffffff|Hspell:1234|h[Not an item]|h|r"), nil)
    T.eq(ns.Items.ID(""), nil)
    T.eq(ns.Items.ID(nil), nil)
    T.eq(ns.Items.ID(18000), nil, "only a link names an item here")
    T.eq(ns.Items.ID(T.secret("item:77")), nil, "a secret is never read")
end)
