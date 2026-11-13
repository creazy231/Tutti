-------------------------------------------------------------------------------
--  Tutti: saved variables (TuttiDB, account-wide) and settings.
--    settings   the five options of the settings view
--    window     where the window sits
--    recent     the session's results, for the Recent rolls view
-------------------------------------------------------------------------------
local ADDON, ns = ...

ns.DEFAULTS = {
    settings = {
        rollInTutti = true,    -- Need, Greed and Pass on the cards, Blizzard's roll popups hidden
        closeAfter = 10,       -- seconds after the last roll is decided; 0 = never
        sound = "chime",       -- "chime" | "none"
        accent = "class",      -- "class" | "eui"
        scale = 1,             -- 0.8 - 1.3
    },
    window = { point = "TOPLEFT", x = 372, y = -226 },
    recent = {},
    schema = 1,
}

local function fill(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            fill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function ns.Get(key)
    local db = ns.DB
    local v = db and db.settings[key]
    if v == nil then v = ns.DEFAULTS.settings[key] end
    return v
end

function ns.Set(key, value)
    if not ns.DB then return end
    if ns.DB.settings[key] == value then return end
    ns.DB.settings[key] = value
    ns.Fire("SETTING_CHANGED", key, value)
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    if type(TuttiDB) ~= "table" then TuttiDB = {} end
    fill(TuttiDB, ns.DEFAULTS)
    ns.DB = TuttiDB
    ns.Fire("DB_READY")
end)
