-------------------------------------------------------------------------------
--  Tutti: Blizzard's group-loot roll popups. With "Roll in Tutti" on the player rolls on Tutti's
--  cards, so the popups for the same rolls are switched off. START_LOOT_ROLL reaches them only
--  through the event router of Blizzard_Game, which holds one handler for it; calling
--  GameEvent.UnregisterInternalEvent("START_LOOT_ROLL") takes that handler out (ElvUI does the
--  same), and the router then never calls GroupLootContainer_AddRoll. Tutti's own handler for the
--  event (Core/Rolls.lua) sits on Tutti's frame and is not touched.
--    ns.Popups.Apply()           makes the game match the setting: with the setting on it switches the
--                                popups off, once. It runs on DB_READY and when "rollInTutti" changes.
--    ns.Popups.Suppressed()      Blizzard's popups are switched off, from the switch-off until the
--                                next /reload: turning the setting off does not bring them back
--    ns.Popups.ReloadNeeded()    the setting is off but the popups were switched off this session
--  Message "POPUPS_CHANGED" when either answer changes.
--  The way back is not Tutti's to take: GameEvent.RegisterInternalEvent is never called, because a
--  handler registered by an addon would run tainted. Bringing the popups back takes a /reload. When
--  GameEvent or its function is missing the popups stay Blizzard's, and Tutti works next to them.
--  Known gaps, accepted and without code (Tutti never hides a Blizzard frame, writes to one, or
--  touches StaticPopup):
--    - after a /reload in the middle of a roll, Blizzard's PLAYER_ENTERING_WORLD handler
--      (GroupLootContainer_RefreshRolls) can still show a popup for the roll;
--    - a Blizzard bind-confirmation dialog whose roll has ended stays open until it is clicked;
--    - with the gamepad interface on, the router's handler does nothing anyway and Blizzard's
--      gamepad roll frame listens for START_LOOT_ROLL by itself, which this does not reach.
-------------------------------------------------------------------------------
local _, ns = ...
local Popups = {}
ns.Popups = Popups

local EVENT = "START_LOOT_ROLL"

local switchedOff = false        -- the router's handler for EVENT was taken out this session
local announced = { false, false } -- what "POPUPS_CHANGED" last stood for: Suppressed, ReloadNeeded

-- "Roll in Tutti" plainly on. A value that is not true (a damaged database) counts as off, and so does
-- the time before the saved settings are in: the popups only come back with a /reload, so they are
-- switched off only when the setting says so.
local function wanted()
    return ns.DB ~= nil and ns.Get("rollInTutti") == true
end

function Popups.Suppressed()
    return switchedOff
end

function Popups.ReloadNeeded()
    return switchedOff and not wanted()
end

-- Takes Blizzard's handler for EVENT out of the router. Without GameEvent or its function there is
-- nothing to call. A call that raises is reported and leaves the popups as they are; the next Apply
-- asks again.
local function switchOff()
    local router = ns.Clear(GameEvent, "table")
    local unregister = router and ns.Clear(router.UnregisterInternalEvent, "function")
    if unregister and ns.Safe(unregister, EVENT) then switchedOff = true end
end

function Popups.Apply()
    if wanted() and not switchedOff then switchOff() end
    local off, reload = switchedOff, Popups.ReloadNeeded()
    if off ~= announced[1] or reload ~= announced[2] then
        announced[1], announced[2] = off, reload
        ns.Fire("POPUPS_CHANGED")
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
ns.Listen("DB_READY", function() Popups.Apply() end)

ns.Listen("SETTING_CHANGED", function(key)
    if key == "rollInTutti" then Popups.Apply() end
end)
