local T = T

-- A game that records errors instead of raising them (the default fake handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

T.it("an unpackaged copy reports its version as dev", function()
    local G, W, ns = T.load()
    T.eq(ns.version, "dev")
end)

T.it("IsSecret spots a secret among plain values", function()
    local G, W, ns = T.load()
    T.ok(ns.IsSecret("a", T.secret("x"), 1), "secret found")
    T.no(ns.IsSecret("a", 1, nil, false), "plain values")
end)

T.it("Clear gives a value of the type asked for in the clear, else nil", function()
    local G, W, ns = T.load()
    local tbl = {}
    T.eq(ns.Clear("Orlen", "string"), "Orlen")
    T.eq(ns.Clear("", "string"), "", "an empty string is still a string: what to do with it is the caller's")
    T.eq(ns.Clear(5, "number"), 5)
    T.eq(ns.Clear(0, "number"), 0)
    T.eq(ns.Clear(tbl, "table"), tbl)
    T.eq(ns.Clear(true, "boolean"), true)
    T.eq(ns.Clear(false, "boolean"), false, "a boolean in the clear is itself")
    T.eq(ns.Clear(5, "string"), nil, "a number is no string")
    T.eq(ns.Clear("5", "number"), nil, "a string is no number")
    T.eq(ns.Clear(tbl, "string"), nil)
    T.eq(ns.Clear(nil, "string"), nil)
    T.eq(ns.Clear(T.secret("Orlen"), "string"), nil, "a secret string")
    T.eq(ns.Clear(T.secret(5), "number"), nil, "a secret number")
    T.eq(ns.Clear(T.secret({}), "table"), nil, "a secret table")
    -- A secret string or number still has type "string" or "number" in the game, so a type check alone
    -- lets it through. The guard asks ns.IsSecret each time it runs, so a test can stand in for the game.
    local hidden = {}
    ns.IsSecret = function(...)
        for i = 1, select("#", ...) do
            if hidden[(select(i, ...))] then return true end
        end
        return false
    end
    hidden["Orlen"], hidden[7] = true, true
    T.eq(ns.Clear("Orlen", "string"), nil, "a string ns.IsSecret calls secret")
    T.eq(ns.Clear(7, "number"), nil, "a number ns.IsSecret calls secret")
    T.eq(ns.Clear("Brisé", "string"), "Brisé", "the same call on a value in the clear")
    hidden["Orlen"] = nil
    T.eq(ns.Clear("Orlen", "string"), "Orlen", "and the answer follows ns.IsSecret as it changes")
end)

T.it("On runs handlers for game events and Off removes them", function()
    local G, W, ns = T.load()
    local got = {}
    local function h(event, a) got[#got + 1] = event .. ":" .. tostring(a) end
    T.eq(ns.On("SOME_EVENT", h), true)
    W.fire("SOME_EVENT", 1)
    ns.Off("SOME_EVENT", h)
    W.fire("SOME_EVENT", 2)
    T.eq(#got, 1, "one call")
    T.eq(got[1], "SOME_EVENT:1")
end)

T.it("On says no to an event the client does not know", function()
    local G, W, ns = T.load({ setup = function(G, W) W.unknownEvents.NOT_AN_EVENT = true end })
    local ran = false
    local function h() ran = true end
    T.eq(ns.On("NOT_AN_EVENT", h), false)
    W.fire("NOT_AN_EVENT")
    T.no(ran, "nothing registered")
    ns.Off("NOT_AN_EVENT", h)
    T.eq(ns.On("SOME_EVENT", function() end), true, "other events still work")
end)

T.it("a handler can unregister itself while its event runs", function()
    local G, W, ns = T.load()
    local calls = {}
    local function once() calls[#calls + 1] = "once"; ns.Off("SOME_EVENT", once) end
    ns.On("SOME_EVENT", once)
    ns.On("SOME_EVENT", function() calls[#calls + 1] = "always" end)
    W.fire("SOME_EVENT")
    W.fire("SOME_EVENT")
    T.eq(table.concat(calls, ","), "once,always,always")
end)

T.it("a failing event handler does not stop the next one, and its error is reported", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local ran = false
    ns.On("OTHER_EVENT", function() error("boom") end)
    ns.On("OTHER_EVENT", function() ran = true end)
    W.fire("OTHER_EVENT")
    T.ok(ran, "second handler ran")
    T.eq(#errors, 1)
    T.ok(tostring(errors[1]):find("boom", 1, true), "the error reached the error handler")
end)

T.it("Listen and Fire pass arguments", function()
    local G, W, ns = T.load()
    local seen
    ns.Listen("THING", function(a, b) seen = a .. b end)
    ns.Fire("THING", "x", "y")
    T.eq(seen, "xy")
end)

T.it("a failing message handler does not stop the next one, and its error is reported", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local ran = false
    ns.Listen("THING", function() error("boom") end)
    ns.Listen("THING", function() ran = true end)
    ns.Fire("THING")
    T.ok(ran, "second handler ran")
    T.eq(#errors, 1)
    T.ok(tostring(errors[1]):find("boom", 1, true), "the error reached the error handler")
    ns.Fire("A MESSAGE NOBODY LISTENS TO")
end)

T.it("Safe runs a function protected and says whether it worked", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local sum
    T.eq(ns.Safe(function(a, b) sum = a + b end, 1, 2), true)
    T.eq(sum, 3, "arguments are passed on")
    T.eq(#errors, 0)
    T.eq(ns.Safe(function() error("nope") end), false)
    T.eq(#errors, 1)
    T.ok(tostring(errors[1]):find("nope", 1, true), "the error reached the error handler")
end)

T.it("After runs a callback after the delay", function()
    local G, W, ns = T.load()
    local ran = false
    ns.After(1, function() ran = true end)
    W.advance(0.5)
    T.no(ran, "not yet")
    W.advance(0.6)
    T.ok(ran, "ran")
end)

T.it("Print writes a Tutti line to the chat window", function()
    local G, W, ns = T.load()
    ns.Print("hello there")
    local line = W.chatLog[#W.chatLog]
    T.ok(line, "a line was written")
    T.ok(line:find("Tutti", 1, true), "it starts with the addon name")
    T.ok(line:find("hello there", 1, true), "and carries the text")
end)
