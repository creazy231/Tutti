local T = T

-- A game that records errors instead of raising them (the fake's default handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

-- A saved database that has "Roll in Tutti" switched off.
local function rollingOff()
    return { settings = { rollInTutti = false } }
end

-- Every message of one kind, in order (their arguments, as one string each).
local function listen(ns, msg)
    local seen = {}
    ns.Listen(msg, function(...) seen[#seen + 1] = table.concat({ ... }, ",") end)
    return seen
end

-- The events the addon asked the game's router to drop, as one string.
local function unregistered(W)
    return table.concat(W.unregistered, ",")
end

T.it("on at load: START_LOOT_ROLL is unregistered once", function()
    local G, W, ns = T.load()
    T.eq(unregistered(W), "START_LOOT_ROLL", "Blizzard's roll popups are off after login")
    ns.Popups.Apply()
    T.eq(unregistered(W), "START_LOOT_ROLL", "a second Apply asks the router nothing more")
    ns.Popups.Apply()
    T.eq(#W.unregistered, 1)
    T.eq(ns.Popups.Suppressed(), true)
    T.eq(ns.Popups.ReloadNeeded(), false, "the setting is on: nothing to reload")
    T.eq(#W.registered, 0, "Blizzard's handler is never registered from an addon")
end)

T.it("off at load: nothing unregistered", function()
    local G, W, ns = T.load({ db = rollingOff() })
    T.eq(#W.unregistered, 0, "the popups stay Blizzard's")
    T.eq(ns.Popups.Suppressed(), false)
    T.eq(ns.Popups.ReloadNeeded(), false, "they were never switched off: nothing to bring back")
    ns.Popups.Apply()
    T.eq(#W.unregistered, 0, "Apply with the setting off changes nothing")
    ns.Set("scale", 1.2)
    ns.Set("sound", "none")
    T.eq(#W.unregistered, 0, "another setting changing does not switch them off")
    T.eq(#W.registered, 0)
end)

T.it("on later: unregistered at once", function()
    local G, W, ns = T.load({ db = rollingOff() })
    ns.Set("rollInTutti", true)
    T.eq(unregistered(W), "START_LOOT_ROLL", "no reload needed to switch the popups off")
    T.eq(ns.Popups.Suppressed(), true)
    T.eq(ns.Popups.ReloadNeeded(), false)
    ns.Popups.Apply()
    T.eq(#W.unregistered, 1, "still once")
    T.eq(#W.registered, 0)
end)

T.it("off later: ReloadNeeded, and Blizzard's handler is never registered again", function()
    local G, W, ns = T.load()
    ns.Set("rollInTutti", false)
    T.eq(ns.Popups.ReloadNeeded(), true, "the popups only come back after a reload")
    T.eq(ns.Popups.Suppressed(), true, "and until then they stay off")
    T.eq(#W.unregistered, 1, "turning it off asks the router nothing")
    T.eq(#W.registered, 0, "a handler registered from an addon would run tainted")
    ns.Set("rollInTutti", true)
    T.eq(ns.Popups.ReloadNeeded(), false, "turned on again before the reload: nothing to bring back")
    T.eq(ns.Popups.Suppressed(), true)
    T.eq(#W.unregistered, 1, "they are off already, so nothing is asked again")
    T.eq(#W.registered, 0)
end)

T.it("no GameEvent: no error, Suppressed false", function()
    local errors = {}
    local G, W, ns = T.load({ noGameEvent = true, setup = recordErrors(errors) })
    T.eq(G.GameEvent, nil, "the client has no router")
    T.eq(ns.Popups.Suppressed(), false, "Blizzard's popups stay, and Tutti works next to them")
    T.eq(ns.Popups.ReloadNeeded(), false)
    ns.Set("rollInTutti", false)
    ns.Set("rollInTutti", true)
    ns.Popups.Apply()
    T.eq(ns.Popups.Suppressed(), false)
    T.eq(ns.Popups.ReloadNeeded(), false)
    T.eq(#errors, 0, "nothing was reported")
end)

T.it("a GameEvent without the function, or with something else in its place, is left alone", function()
    local errors = {}
    local G, W, ns = T.load({ db = rollingOff(), setup = recordErrors(errors) })
    G.GameEvent = {}
    ns.Set("rollInTutti", true)
    T.eq(ns.Popups.Suppressed(), false, "no UnregisterInternalEvent: nothing to call")
    G.GameEvent = { UnregisterInternalEvent = "not a function" }
    ns.Popups.Apply()
    T.eq(ns.Popups.Suppressed(), false)
    G.GameEvent = "not a table"
    ns.Popups.Apply()
    T.eq(ns.Popups.Suppressed(), false)
    T.eq(#W.unregistered, 0)
    T.eq(#errors, 0, "nothing was reported either")
end)

-- A secret table or function in the game still has type "table" or "function", so the fake's userdata
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

T.it("an unreadable GameEvent or function is left alone", function()
    local errors = {}
    local G, W, ns = T.load({ db = rollingOff(), setup = recordErrors(errors) })
    G.GameEvent = T.secret({ UnregisterInternalEvent = function() end })
    ns.Set("rollInTutti", true)
    T.eq(ns.Popups.Suppressed(), false)
    G.GameEvent = { UnregisterInternalEvent = T.secret(function() end) }
    ns.Popups.Apply()
    T.eq(ns.Popups.Suppressed(), false)

    local hidden = withSecrets(ns)
    local router = { UnregisterInternalEvent = function(event) W.unregistered[#W.unregistered + 1] = event end }
    G.GameEvent = router
    hidden[router] = true
    ns.Popups.Apply()
    T.eq(#W.unregistered, 0, "a table ns.IsSecret calls secret is never used")
    hidden[router] = nil
    hidden[router.UnregisterInternalEvent] = true
    ns.Popups.Apply()
    T.eq(#W.unregistered, 0, "nor a function it calls secret")
    T.eq(ns.Popups.Suppressed(), false)
    hidden[router.UnregisterInternalEvent] = nil
    ns.Popups.Apply()
    T.eq(unregistered(W), "START_LOOT_ROLL", "the same router in the clear works")
    T.eq(#errors, 0)
end)

T.it("a router that raises is reported, and the next Apply asks again", function()
    local errors, calls, working = {}, 0, false
    local G, W, ns = T.load({ setup = function(G, W)
        recordErrors(errors)(G)
        G.GameEvent.UnregisterInternalEvent = function(event)
            calls = calls + 1
            if not working then error("router broke") end
            W.unregistered[#W.unregistered + 1] = event
        end
    end })
    T.eq(calls, 1, "asked at load")
    T.eq(ns.Popups.Suppressed(), false, "the call did not go through")
    T.eq(#errors, 1, "the error reached the error handler")
    T.ok(tostring(errors[1]):find("router broke", 1, true))
    ns.Set("scale", 1.2)
    T.eq(calls, 1, "another setting is no reason to ask again")
    working = true
    ns.Popups.Apply()
    T.eq(calls, 2)
    T.eq(ns.Popups.Suppressed(), true, "the retry worked")
    T.eq(unregistered(W), "START_LOOT_ROLL")
    ns.Popups.Apply()
    T.eq(calls, 2, "and is not repeated")
end)

T.it("only a setting that plainly says on switches the popups off", function()
    local G, W, ns = T.load({ db = { settings = { rollInTutti = "yes" } } })
    T.eq(#W.unregistered, 0, "a damaged value is no yes")
    T.eq(ns.Popups.Suppressed(), false)
    ns.Set("rollInTutti", true)
    T.eq(#W.unregistered, 1)
end)

T.it("before the saved settings are in, Apply switches nothing off", function()
    local G, W, ns = T.load({ db = rollingOff() })
    local db = ns.DB
    ns.DB = nil -- the setting is not known yet, and the default would say on
    ns.Popups.Apply()
    T.eq(#W.unregistered, 0, "the popups only come back with a reload: no guessing")
    T.eq(ns.Popups.Suppressed(), false)
    ns.DB = db
    ns.Popups.Apply()
    T.eq(#W.unregistered, 0, "and with the settings in, the saved 'off' holds")
end)

T.it("POPUPS_CHANGED says when the popups were switched off and when a reload becomes needed", function()
    local G, W, ns = T.load()
    local seen = listen(ns, "POPUPS_CHANGED")
    T.eq(#seen, 0, "the switch-off at load went out before anyone listened")
    ns.Popups.Apply()
    T.eq(#seen, 0, "Apply with nothing new says nothing")
    ns.Set("rollInTutti", false)
    T.eq(#seen, 1, "a reload is needed now")
    ns.Set("rollInTutti", true)
    T.eq(#seen, 2, "and now it is not")
    ns.Set("scale", 1.2)
    T.eq(#seen, 2, "another setting says nothing")

    -- Switched off later.
    G, W, ns = T.load({ db = rollingOff() })
    seen = listen(ns, "POPUPS_CHANGED")
    ns.Set("rollInTutti", true)
    T.eq(#seen, 1, "the popups went off")
    ns.Set("rollInTutti", true)
    T.eq(#seen, 1, "the same value again says nothing")

    -- Off with nothing switched off: no state changed.
    G, W, ns = T.load({ db = rollingOff(), noGameEvent = true })
    seen = listen(ns, "POPUPS_CHANGED")
    ns.Set("rollInTutti", true)
    ns.Set("rollInTutti", false)
    T.eq(#seen, 0, "without a router nothing ever changes")
end)

T.it("DB_READY switches the popups off and says so", function()
    -- T.load fires ADDON_LOADED itself, so load Init and DB alone, listen, then bring the module in.
    local G, W, ns = T.load({ only = { "Core/Init.lua", "Core/DB.lua" }, login = false })
    local chunk = assert(loadfile("Core/Popups.lua"))
    setfenv(chunk, G)
    chunk("Tutti", ns)
    local seen = listen(ns, "POPUPS_CHANGED")
    T.eq(ns.Popups.Suppressed(), false, "nothing before the database is ready")
    T.eq(#W.unregistered, 0)
    ns.Fire("DB_READY")
    T.eq(unregistered(W), "START_LOOT_ROLL")
    T.eq(ns.Popups.Suppressed(), true)
    T.eq(#seen, 1, "one message")
end)

-------------------------------------------------------------------------------
--  WoW Forever's gamepad interface: Blizzard's gamepad roll frame takes every roll
-------------------------------------------------------------------------------
-- Every GAMEPAD_CHANGED, in order, as "true" or "false".
local function gamepadNews(ns)
    local seen = {}
    ns.Listen("GAMEPAD_CHANGED", function(on) seen[#seen + 1] = tostring(on) end)
    return seen
end

T.it("in the gamepad interface the player does not roll in Tutti", function()
    local G, W, ns = T.load({ gamepad = true })
    T.eq(ns.Popups.Gamepad(), true)
    T.eq(ns.Popups.RollInTutti(), false, "Blizzard's gamepad roll frame takes the rolls")
    T.eq(unregistered(W), "START_LOOT_ROLL", "the mouse interface's popups still go off, for when it comes back")
    T.eq(#W.registered, 0)
    G, W, ns = T.load()
    T.eq(ns.Popups.Gamepad(), false, "the mouse interface")
    T.eq(ns.Popups.RollInTutti(), true)
end)

T.it("GAMEPAD_CHANGED comes a frame after the interface style changes, once per change", function()
    local G, W, ns = T.load()
    local seen = gamepadNews(ns)
    W.switchStyle("Gamepad")
    T.eq(#seen, 0, "not during the game's event: the style reads right only afterwards")
    W.advance(0)
    T.eq(table.concat(seen, ","), "true")
    T.eq(ns.Popups.RollInTutti(), false)
    W.switchStyle("Mkb")
    W.switchStyle("Gamepad")
    W.advance(0)
    T.eq(table.concat(seen, ","), "true", "a burst that ends where it began says nothing")
    W.switchStyle("Mkb")
    W.advance(0)
    T.eq(table.concat(seen, ","), "true,false")
    T.eq(ns.Popups.RollInTutti(), true, "back in the mouse interface, the cards again")
    W.advance(1)
    T.eq(#seen, 2, "and nothing more")
end)

T.it("a style the client lacks or keeps secret counts as the mouse interface", function()
    local errors = {}
    local G, W, ns = T.load({ gamepad = true, setup = recordErrors(errors) })
    G.C_InputInterfaceStyle = nil
    T.eq(ns.Popups.Gamepad(), false, "no API")
    G.C_InputInterfaceStyle = { GetCurrentStyle = "not a function" }
    T.eq(ns.Popups.Gamepad(), false)
    G.C_InputInterfaceStyle = { GetCurrentStyle = function() return T.secret(1) end }
    T.eq(ns.Popups.Gamepad(), false, "a secret style is never compared")
    G.C_InputInterfaceStyle = { GetCurrentStyle = function() error("style broke") end }
    T.eq(ns.Popups.Gamepad(), false, "a call that raises")
    G.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
    G.Enum.InputDeviceInterfaceType = nil
    T.eq(ns.Popups.Gamepad(), false, "no enum to compare with")
    G.Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    T.eq(ns.Popups.Gamepad(), true, "everything there again")
    T.eq(#errors, 0, "nothing was reported")
end)

T.it("a client without the style's event still reads the style", function()
    local errors = {}
    local G, W, ns = T.load({ gamepad = true, setup = function(G, W)
        recordErrors(errors)(G)
        W.unknownEvents.INPUT_DEVICE_INTERFACE_TRANSITION = true
    end })
    T.eq(ns.Popups.Gamepad(), true)
    T.eq(ns.Popups.RollInTutti(), false)
    T.eq(#errors, 0)
end)
