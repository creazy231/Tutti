local T = T

-- The only globals the addon may create; everything else lives in its namespace.
local ALLOWED = {
    TuttiDB = true, SLASH_TUTTI1 = true,
    Tutti_OnAddonCompartmentClick = true, Tutti_OnAddonCompartmentEnter = true, Tutti_OnAddonCompartmentLeave = true,
}

-- The "## Key: value" lines of Tutti.toc.
local function toc()
    local fields = {}
    for line in io.lines("Tutti.toc") do
        line = line:gsub("\r", "")
        local key, value = line:match("^## ([%w%-]+):%s*(.-)%s*$")
        if key then fields[key] = value end
    end
    return fields
end

T.it("every TOC file loads", function()
    local G, W, ns = T.load()
    T.ok(ns.Theme and ns.DB, "the theme and the database exist")
    T.ok(#T.tocFiles() >= 4, "the TOC lists the core files")
end)

T.it("only the allowed globals are created", function()
    local G, W = T.load()
    for k in pairs(W.globalsWritten) do
        if not ALLOWED[k] then error("unexpected global: " .. tostring(k)) end
    end
end)

-- One number per client, as Sotto's TOC has them (warcraft.wiki.gg/wiki/TOC_format): Retail 12.1.5 and 12.1.7,
-- Mists of Pandaria Classic 5.5.4, Cataclysm Classic 4.4.2, Titan-Reforged 3.80.2, Wrath Classic 3.4.5, TBC
-- Anniversary 2.5.6, WoW Forever 1.60.1, Classic Era 1.15.9. Retail loads only an exact match: a patched client
-- needs its new number here and in Tutti.toc.
local INTERFACES = "120105, 120107, 50504, 40402, 38002, 30405, 20506, 16001, 11509"

T.it("the TOC names every client, Author creazy231, SavedVariables TuttiDB", function()
    local t = toc()
    T.eq(t.Interface, INTERFACES, "Interface")
    T.eq(t.Author, "creazy231", "Author")
    T.eq(t.SavedVariables, "TuttiDB", "SavedVariables")
    T.eq(t.Title, "Tutti", "Title")
    T.eq(t.Version, "@project-version@", "the packager fills in the version")
    T.eq(t.OptionalDeps, "EllesmereUI, NaowhForever_BiS", "OptionalDeps")
    T.eq(t.IconTexture, "Interface\\AddOns\\Tutti\\Media\\mark", "IconTexture")
end)

-- A version tag uploads to the CurseForge project this line names (docs/RELEASING.md); without it the packager skips
-- the upload.
T.it("the TOC names Tutti's CurseForge project", function()
    T.eq(toc()["X-Curse-Project-ID"], "1805550", "X-Curse-Project-ID")
end)

T.it("the TOC names the addon compartment functions", function()
    local G = T.load()
    local t = toc()
    local names = {
        AddonCompartmentFunc = "Tutti_OnAddonCompartmentClick",
        AddonCompartmentFuncOnEnter = "Tutti_OnAddonCompartmentEnter",
        AddonCompartmentFuncOnLeave = "Tutti_OnAddonCompartmentLeave",
    }
    for key, name in pairs(names) do
        T.eq(t[key], name, key)
        -- UI/Launcher.lua defines them; until it is in the TOC their absence is fine.
        if G[name] ~= nil then T.eq(type(G[name]), "function", name) end
    end
end)
