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
--    ns.Popups.RollInTutti()     the player rolls on Tutti's cards: the setting is on, or the popups are
--                                switched off (until a /reload the cards are then the only way to roll,
--                                whatever the setting says). Off at login, the popups are Blizzard's and the
--                                cards show no roll buttons. Never in the gamepad interface (below).
--    ns.Popups.Gamepad()         WoW Forever's gamepad interface is on (the game's Gamepad settings): Blizzard's
--                                gamepad roll frame takes every roll then, and Tutti stays out of its way (the
--                                window opens for no roll, UI/Window.lua). Read live, with Blizzard's own test.
--  Message "POPUPS_CHANGED" when either answer of Suppressed and ReloadNeeded changes.
--  Message "GAMEPAD_CHANGED"(on) a frame after the interface style changed, when Gamepad()'s answer did.
--  The way back is not Tutti's to take: GameEvent.RegisterInternalEvent is never called, because a
--  handler registered by an addon would run tainted. Bringing the popups back takes a /reload. When
--  GameEvent or its function is missing the popups stay Blizzard's, and Tutti works next to them.
--  The gamepad interface needs none of this: the router's handler does nothing in it
--  (GameEvent.HandleStartLootRoll returns early), and Blizzard's gamepad roll frame
--  (GamepadGroupLootRollFrame, Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua) registers
--  START_LOOT_ROLL on itself when the style comes on, lists the rolls still running, and lets them go
--  when the style goes.
--  Known gaps, accepted and without code (Tutti never hides a Blizzard frame, writes to one, or
--  touches StaticPopup):
--    - after a /reload in the middle of a roll, Blizzard's PLAYER_ENTERING_WORLD handler
--      (GroupLootContainer_RefreshRolls) can still show a popup for the roll;
--    - the same when the player leaves the gamepad interface in the middle of a roll: Blizzard puts
--      its popups back for the rolls still running (GroupLootContainer_UninitGamepad), next to the
--      cards that wait on the player;
--    - a Blizzard bind-confirmation dialog whose roll has ended stays open until it is clicked.
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

-- Blizzard's own test (InputUtil.IsGamepadUIEnabled), every part through ns.Clear: a style the client lacks, keeps
-- secret or fails to give counts as the mouse interface.
function Popups.Gamepad()
    local api = ns.Clear(C_InputInterfaceStyle, "table")
    local current = api and ns.Clear(api.GetCurrentStyle, "function")
    local enum = ns.Clear(Enum, "table")
    local styles = enum and ns.Clear(enum.InputDeviceInterfaceType, "table")
    local gamepad = styles and ns.Clear(styles.Gamepad, "number")
    if not (current and gamepad) then return false end
    local ok, style = pcall(current)
    return ok and ns.Clear(style, "number") == gamepad
end

function Popups.RollInTutti()
    if Popups.Gamepad() then return false end
    return ns.Get("rollInTutti") == true or switchedOff
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

-- The interface style. The game says it changes before the style reads right (EllesmereUI: a frame later), so it is
-- read a frame after the event, once for a burst of them. What "GAMEPAD_CHANGED" stands for starts as the answer at
-- login, taken again then in case the client knew it only by then.
local gamepadSaid = Popups.Gamepad()
local gamepadDue = false

local function gamepadCheck()
    gamepadDue = false
    local on = Popups.Gamepad()
    if on == gamepadSaid then return end
    gamepadSaid = on
    ns.Fire("GAMEPAD_CHANGED", on)
end

ns.On("PLAYER_LOGIN", function() gamepadSaid = Popups.Gamepad() end)

ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function()
    if gamepadDue then return end
    gamepadDue = true
    ns.After(0, gamepadCheck)
end)
