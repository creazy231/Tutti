-------------------------------------------------------------------------------
--  Tutti: the ways in. The addon compartment (the minimap's addon menu; Tutti.toc names these functions) and
--  /tutti. No minimap button.
--    a click in the compartment   Recent rolls, or closes them
--    /tutti                       the same
--    /tutti settings              Settings
--    /tutti demo                  the demo's boss drop (UI/Demo.lua)
--  The compartment functions and the slash command are Tutti's own globals, the game's way to reach them.
-------------------------------------------------------------------------------
local _, ns = ...

local TIP_TITLE, TIP_LINE = "Tutti", "Click: recent rolls"
local USAGE = "/tutti opens the recent rolls · /tutti settings · /tutti demo"

-- The game calls these with the addon's name, then the mouse button (a click) or the menu's button (enter, leave).
function Tutti_OnAddonCompartmentClick()
    ns.UI.Toggle("recent")
end

function Tutti_OnAddonCompartmentEnter(_, button)
    button = ns.Clear(button, "table")
    if button then ns.W.Tip(button, TIP_TITLE, { TIP_LINE }, "ANCHOR_LEFT") end
end

function Tutti_OnAddonCompartmentLeave(_, button)
    button = ns.Clear(button, "table")
    if button then ns.W.HideTip(button) end
end

SLASH_TUTTI1 = "/tutti"
SlashCmdList.TUTTI = function(msg)
    local command = (ns.Clear(msg, "string") or ""):lower():match("^%s*(.-)%s*$")
    if command == "" then
        ns.UI.Toggle("recent")
    elseif command == "settings" then
        ns.UI.Open("settings")
    elseif command == "demo" then
        ns.Demo.Start()
    else
        ns.Print(USAGE)
    end
end
