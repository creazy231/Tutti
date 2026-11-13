local T = T

-- A game that records errors instead of raising them (the fake's handler raises).
local function recordErrors(errors)
    return function(G)
        G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    end
end

-- A plain frame where the window would sit: the screen's top left, 372 right and 226 down.
local function frame(G, w, h)
    local f = G.CreateFrame("Frame", nil, G.UIParent)
    f:SetSize(w or 300, h or 200)
    f:SetPoint("TOPLEFT", G.UIParent, "TOPLEFT", 372, -226)
    return f
end

-- A font string for a roll number, with its font: the client refuses text on a font string without one.
local function number(ns, parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.Theme.ApplyFont(fs, "roll")
    return fs
end

-- The x and y of a frame's first anchor.
local function offsets(f)
    local _, _, _, x, y = f:GetPoint(1)
    return x, y
end

-- Ease-out cubic, the curve of Tween.
local function out(u) return 1 - (1 - u) ^ 3 end

-- How many frames have an OnUpdate script.
local function updaters(W)
    local n = 0
    for _, f in ipairs(W.allFrames) do
        if f._scripts.OnUpdate then n = n + 1 end
    end
    return n
end

-------------------------------------------------------------------------------
--  Tween and its one driver frame
-------------------------------------------------------------------------------
T.it("Tween reaches 1 after its time and calls done once", function()
    local G, W, ns = T.load()
    local steps, done = {}, 0
    ns.Fx.Tween(0.5, function(t) steps[#steps + 1] = t end, function() done = done + 1 end)
    T.eq(steps[1], 0, "the start state is drawn at once")
    W.advance(0.25)
    T.near(steps[#steps], out(0.5), 1e-9, "halfway in time is 87.5 % of the way: ease-out cubic")
    T.eq(done, 0, "not done before its time")
    W.advance(0.25)
    T.eq(steps[#steps], 1, "the last step is exactly 1")
    T.eq(done, 1, "done once, after the last step")
    local n = #steps
    W.advance(1)
    T.eq(#steps, n, "no step after the end")
    T.eq(done, 1, "and done is not called again")
end)

T.it("Tween can wait before it runs, and tells each step how long it has run", function()
    local G, W, ns = T.load()
    local steps = {}
    ns.Fx.Tween(0.5, function(t, age) steps[#steps + 1] = { t, age } end, nil, 0.3)
    T.eq(#steps, 1, "the start state is drawn at once, even in the delay")
    T.eq(steps[1][1], 0)
    W.advance(0.2)
    T.eq(#steps, 1, "no step while it waits")
    W.advance(0.2) -- 0.1 s into its run
    T.eq(#steps, 2)
    T.near(steps[2][1], out(0.2), 1e-6)
    T.near(steps[2][2], 0.1, 1e-6, "age counts from the end of the delay")
    W.advance(2)
    T.eq(steps[#steps][1], 1)
    T.near(steps[#steps][2], 0.5, 1e-9, "age stops at the length")
end)

T.it("Cancel stops a tween", function()
    local G, W, ns = T.load()
    local steps, done = 0, 0
    local handle = ns.Fx.Tween(1, function() steps = steps + 1 end, function() done = done + 1 end)
    T.ok(handle:IsRunning())
    W.advance(0.3)
    local n = steps
    T.ok(n > 1, "it ran")
    handle:Cancel()
    T.no(handle:IsRunning())
    W.advance(2)
    T.eq(steps, n, "no step after Cancel")
    T.eq(done, 0, "and no done")
    handle:Cancel() -- again: nothing happens
end)

T.it("a tween can start and cancel others from its callbacks", function()
    local G, W, ns = T.load()
    local order = {}
    ns.Fx.Tween(0.1, nil, function()
        order[#order + 1] = "first"
        ns.Fx.Tween(0.1, nil, function() order[#order + 1] = "second" end)
    end)
    W.advance(0.1)
    T.eq(table.concat(order, ","), "first", "the one it started runs from the next frame")
    W.advance(0.1)
    T.eq(table.concat(order, ","), "first,second")

    local doomed = ns.Fx.Tween(1, nil, function() order[#order + 1] = "doomed" end)
    ns.Fx.Tween(0.5, function(t) if t > 0 then doomed:Cancel() end end)
    W.advance(0.1) -- the second tween's first step after its start cancels the first
    W.advance(2)
    T.eq(table.concat(order, ","), "first,second", "cancelled from another tween's step: it never finishes")
end)

T.it("one driver frame runs every tween and hides when none is left", function()
    local G, W, ns = T.load()
    local driver = ns.Fx.driver
    T.no(driver:IsShown(), "idle: nothing to drive")
    local frames = updaters(W)
    T.ok(frames >= 1, "the driver has the OnUpdate")
    ns.Fx.Tween(1)
    ns.Fx.Tween(2)
    ns.Fx.Spin(number(ns, G.CreateFrame("Frame", nil, G.UIParent)), 5)
    ns.Fx.Rise(frame(G))
    T.ok(driver:IsShown())
    T.eq(updaters(W), frames, "no frame of its own for a tween or an effect")
    W.advance(1.5)
    T.ok(driver:IsShown(), "the 2 s tween is still going")
    W.advance(1)
    T.no(driver:IsShown(), "all done: the driver hides itself")
    local c = ns.Fx.Tween(5)
    T.ok(driver:IsShown())
    c:Cancel()
    T.no(driver:IsShown(), "cancelling the last tween hides it at once")
end)

T.it("a step that raises is reported once, stops its own tween and leaves the others", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local good = 0
    local bad = ns.Fx.Tween(1, function(t) if t > 0 then error("boom") end end)
    ns.Fx.Tween(1, function() good = good + 1 end)
    W.advance(0.1)
    T.eq(#errors, 1, "the error goes to the game's handler")
    T.ok(errors[1]:find("boom", 1, true))
    T.no(bad:IsRunning(), "the failing tween is stopped")
    local n = good
    W.advance(0.1)
    T.eq(#errors, 1, "and not reported again")
    T.ok(good > n, "the other tween went on")
end)

T.it("an onDone that raises is reported once, and an effect is still put back", function()
    local errors = {}
    local G, W, ns = T.load({ setup = recordErrors(errors) })
    local f = frame(G)
    ns.Fx.Sink(f, function() error("boom in sink") end)
    local good = 0
    ns.Fx.Tween(2, function() good = good + 1 end)
    W.advance(0.6)
    T.eq(#errors, 1)
    T.ok(errors[1]:find("boom in sink", 1, true))
    T.eq(f:GetAlpha(), 1, "the frame is put back all the same")
    ns.Fx.Tween(0.1, nil, function() error("boom in done") end)
    W.advance(0.2)
    T.eq(#errors, 2, "a plain tween's done is protected too")
    T.ok(errors[2]:find("boom in done", 1, true))
    local n = good
    W.advance(0.2)
    T.ok(good > n, "the other tween went on")
end)

T.it("a tween that cancels itself in its last step does not call done", function()
    local G, W, ns = T.load()
    local done, handle = 0, nil
    handle = ns.Fx.Tween(0.2, function(t) if t == 1 then handle:Cancel() end end, function() done = done + 1 end)
    W.advance(0.5)
    T.eq(done, 0)
    T.no(handle:IsRunning())
end)

T.it("a tween of no length is drawn at 0 at once and at 1 on the next frame", function()
    local G, W, ns = T.load()
    local steps, done = {}, 0
    ns.Fx.Tween(0, function(t) steps[#steps + 1] = t end, function() done = done + 1 end)
    T.eq(steps[1], 0)
    T.eq(done, 0)
    W.advance(0.016)
    T.eq(steps[#steps], 1)
    T.eq(done, 1)
    ns.Fx.Tween(-3, nil, function() done = done + 1 end) -- a negative time is none
    W.advance(0.016)
    T.eq(done, 2)
end)

-------------------------------------------------------------------------------
--  Spin
-------------------------------------------------------------------------------
T.it("Spin lands on the final number after 0.75 s", function()
    local G, W, ns = T.load()
    local fs = number(ns, frame(G))
    ns.Fx.Spin(fs, 87)
    local first = tonumber(fs:GetText())
    T.ok(first and first >= 1 and first <= 100, "a number is there at once")
    for _ = 1, 14 do -- 0.7 s
        W.advance(0.05)
        local n = tonumber(fs:GetText())
        T.ok(n and n == math.floor(n) and n >= 1 and n <= 100, "a whole number from 1 to 100 while it spins")
        T.eq(fs:GetTextScale(), 1, "no bump while it spins")
    end
    W.advance(0.05) -- 0.75 s
    T.eq(fs:GetText(), "87", "lands on the final number")
    T.near(fs:GetTextScale(), 1.5, 1e-6, "and lands big")
    W.advance(0.175)
    T.near(fs:GetTextScale(), 1 + 0.5 * (1 - out(0.5)), 1e-6, "the bump shrinks, ease-out, in 0.35 s")
    T.eq(fs:GetText(), "87", "the number stays")
    W.advance(0.2)
    T.eq(fs:GetTextScale(), 1, "back to normal size")
    T.eq(fs:GetText(), "87")
    T.no(ns.Fx.driver:IsShown(), "and the effect is over")
end)

T.it("Spin shows a new random number from 1 to 100 every frame", function()
    local G, W, ns = T.load()
    local calls = {}
    G.random = function(lo, hi)
        calls[#calls + 1] = { lo, hi }
        return 10 + #calls
    end
    local fs = number(ns, frame(G))
    ns.Fx.Spin(fs, 5)
    T.eq(fs:GetText(), "11", "the first number at once")
    W.advance(0.016)
    T.eq(fs:GetText(), "12", "a new one every frame")
    W.advance(0.016)
    T.eq(fs:GetText(), "13")
    T.eq(calls[1][1], 1)
    T.eq(calls[1][2], 100)
end)

T.it("Spin takes its own time, and scales with SetScale where the font string has no SetTextScale", function()
    local G, W, ns = T.load()
    local fs = number(ns, frame(G))
    fs.SetTextScale = false -- a client without it
    ns.Fx.Spin(fs, 42, 0.5)
    W.advance(0.45)
    T.ok(tonumber(fs:GetText()), "still spinning at 0.45 s")
    W.advance(0.05)
    T.eq(fs:GetText(), "42", "lands after the 0.5 s asked for")
    T.near(fs:GetScale(), 1.5, 1e-6, "the bump goes through SetScale")
    W.advance(1)
    T.eq(fs:GetScale(), 1)
end)

-------------------------------------------------------------------------------
--  Rise and Sink
-------------------------------------------------------------------------------
T.it("Rise lifts the frame 8 px and fades it in over 0.35 s", function()
    local G, W, ns = T.load()
    local f = frame(G)
    ns.Fx.Rise(f)
    T.eq(f:GetAlpha(), 0, "invisible at once")
    local x, y = offsets(f)
    T.eq(x, 372)
    T.eq(y, -234, "8 px below its place")
    W.advance(0.175)
    T.near(f:GetAlpha(), out(0.5), 1e-6)
    x, y = offsets(f)
    T.near(y, -226 - 8 * (1 - out(0.5)), 1e-6, "rising")
    T.eq(x, 372, "sideways it stays")
    W.advance(0.2)
    T.eq(f:GetAlpha(), 1)
    x, y = offsets(f)
    T.eq(y, -226, "in its place")
    T.eq(x, 372)
    T.eq(f:GetNumPoints(), 1, "with the anchors it had")
end)

T.it("Rise moves every anchor of a frame that has several, and keeps what is relative", function()
    local G, W, ns = T.load()
    local f = G.CreateFrame("Frame", nil, G.UIParent)
    f:SetPoint("TOPLEFT", G.UIParent, "TOPLEFT", 10, -20)
    f:SetPoint("BOTTOMRIGHT", G.UIParent, "TOPLEFT", 110, -120)
    ns.Fx.Rise(f)
    T.eq(f:GetNumPoints(), 2)
    T.eq(f:GetHeight(), 100, "the frame keeps its size while it moves")
    W.advance(1)
    local _, rel, relPoint, x, y = f:GetPoint(1)
    T.eq(rel, G.UIParent)
    T.eq(relPoint, "TOPLEFT")
    T.eq(x, 10)
    T.eq(y, -20)
    local _, _, _, x2, y2 = f:GetPoint(2)
    T.eq(x2, 110)
    T.eq(y2, -120)
end)

T.it("Sink fades out and calls done after 0.55 s", function()
    local G, W, ns = T.load()
    local f = frame(G)
    local done, alpha, y = 0, nil, nil
    ns.Fx.Sink(f, function()
        done = done + 1
        alpha, y = f:GetAlpha(), select(2, offsets(f))
    end)
    T.eq(f:GetAlpha(), 1, "it starts as it is")
    W.advance(0.2)
    T.near(f:GetAlpha(), 1 - out(0.2 / 0.55), 1e-6)
    T.near(select(2, offsets(f)), -226 - 6 * out(0.2 / 0.55), 1e-6, "sinking")
    W.advance(0.34) -- 0.54 s
    T.near(f:GetAlpha(), 1 - out(0.54 / 0.55), 1e-6, "nearly gone")
    T.eq(done, 0, "not before 0.55 s")
    W.advance(0.02)
    T.eq(done, 1, "done once")
    T.eq(alpha, 1, "done finds the frame put back, at its alpha (the caller hides it there, in the same frame)")
    T.eq(y, -226, "and in its place")
    T.eq(f:GetAlpha(), 1)
    T.eq(select(2, offsets(f)), -226)
    W.advance(2)
    T.eq(done, 1)
end)

T.it("an effect that a Sink's done starts on the frame starts from the frame at rest", function()
    local G, W, ns = T.load()
    local f = frame(G)
    local seen
    ns.Fx.Sink(f, function()
        seen = { f:GetAlpha(), select(2, offsets(f)) }
        ns.Fx.Rise(f)
    end)
    W.advance(0.6)
    T.eq(seen[1], 1, "done sees the frame back at its alpha")
    T.eq(seen[2], -226, "and in its place")
    W.advance(1)
    T.eq(select(2, offsets(f)), -226, "so a Rise from there ends where the frame belongs, not 6 px low")
    T.eq(f:GetAlpha(), 1)
    T.eq(f:GetNumPoints(), 1)
end)

T.it("Sink goes on from the alpha the frame has", function()
    local G, W, ns = T.load()
    local f = frame(G)
    f:SetAlpha(0.5)
    ns.Fx.Sink(f)
    W.advance(0.2)
    T.near(f:GetAlpha(), 0.5 * (1 - out(0.2 / 0.55)), 1e-6)
    W.advance(1)
    T.eq(f:GetAlpha(), 0.5, "and is put back at it")
end)

T.it("a frame without anchors is only faded", function()
    local G, W, ns = T.load()
    local f = G.CreateFrame("Frame", nil, G.UIParent)
    ns.Fx.Rise(f)
    W.advance(0.1)
    T.ok(f:GetAlpha() > 0)
    W.advance(1)
    T.eq(f:GetAlpha(), 1)
    T.eq(f:GetNumPoints(), 0, "no anchor made up")
end)

-------------------------------------------------------------------------------
--  Wash, Pop, Glow, Shine, FadeIn
-------------------------------------------------------------------------------
T.it("Wash grows a texture from no width to its full width in 0.7 s", function()
    local G, W, ns = T.load()
    local row = frame(G, 280, 21)
    local wash = row:CreateTexture(nil, "BACKGROUND")
    wash:SetPoint("TOPLEFT", row, "TOPLEFT")
    wash:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    wash:SetWidth(280)
    wash:SetAlpha(0.28)
    wash:Hide()
    ns.Fx.Wash(wash)
    T.ok(wash:IsShown(), "it shows the wash")
    T.ok(wash:GetWidth() < 0.01, "from no width")
    T.near(wash:GetAlpha(), 0.28 * 0.3, 1e-6, "and at 30 % of its alpha, as the mockup's sweep")
    W.advance(0.35)
    T.near(wash:GetWidth(), 280 * out(0.5), 1e-6, "ease-out")
    T.near(wash:GetAlpha(), 0.28 * (0.3 + 0.7 * out(0.5)), 1e-6)
    W.advance(0.34) -- 0.69 s
    T.ok(wash:GetWidth() < 280, "not at full width before 0.7 s")
    W.advance(0.02)
    T.eq(wash:GetWidth(), 280, "full width")
    T.eq(wash:GetAlpha(), 0.28, "and its own alpha")
    T.eq(wash:GetHeight(), 21, "the height is the row's all along")
end)

T.it("Wash takes its seconds, and the parent's width for a texture without one", function()
    local G, W, ns = T.load()
    local row = frame(G, 250, 21)
    local wash = row:CreateTexture(nil, "BACKGROUND")
    wash:SetPoint("TOPLEFT", row, "TOPLEFT")
    wash:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    ns.Fx.Wash(wash, 0.2)
    W.advance(0.1)
    T.near(wash:GetWidth(), 250 * out(0.5), 1e-6)
    W.advance(0.2)
    T.eq(wash:GetWidth(), 250)
end)

T.it("Wash grows a texture stretched over its row with SetAllPoints all the same", function()
    local G, W, ns = T.load()
    local row = frame(G, 280, 21)
    local wash = row:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints(row)
    wash:SetAlpha(0.28)
    ns.Fx.Wash(wash)
    T.ok(wash:GetWidth() < 0.01, "from no width")
    T.eq(wash:GetHeight(), 21, "it keeps the row's height")
    W.advance(0.35)
    T.near(wash:GetWidth(), 280 * out(0.5), 1e-6)
    T.near(wash:GetLeft(), row:GetLeft(), 1e-6, "from the row's left edge")
    T.eq(wash:GetHeight(), 21)
    W.advance(1)
    T.eq(wash:GetNumPoints(), 2, "stretched over the row again, as it was")
    local first, _, _, x1, y1 = wash:GetPoint(1)
    local second, rel, relPoint, x2, y2 = wash:GetPoint(2)
    T.eq(first, "TOPLEFT")
    T.eq(second, "BOTTOMRIGHT")
    T.eq(rel, row)
    T.eq(relPoint, "BOTTOMRIGHT")
    T.eq(x1 + y1 + x2 + y2, 0)
    T.eq(wash:GetWidth(), 280)
    T.eq(wash:GetHeight(), 21)
    T.eq(wash:GetAlpha(), 0.28)
end)

T.it("Wash keeps the insets of a texture that has them, and Stop gives them back", function()
    local G, W, ns = T.load()
    local row = frame(G, 280, 21)
    local wash = row:CreateTexture(nil, "BACKGROUND")
    wash:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1)
    wash:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 1)
    ns.Fx.Wash(wash)
    W.advance(0.35)
    T.near(wash:GetLeft(), row:GetLeft() + 2, 1e-6, "its left inset holds while it grows")
    T.eq(wash:GetHeight(), 19, "and its height")
    T.near(wash:GetWidth(), 275 * out(0.5), 1e-6, "growing to the width it has: 275")
    ns.Fx.Stop(wash)
    T.eq(wash:GetNumPoints(), 2)
    T.eq(wash:GetWidth(), 275)
    T.eq(wash:GetHeight(), 19)
    local _, _, _, x, y = wash:GetPoint(2)
    T.eq(x, -3)
    T.eq(y, 1)
end)

T.it("Pop scales a frame from 0 to 1.45 to 1 after its delay", function()
    local G, W, ns = T.load()
    local crown = frame(G, 12, 12)
    ns.Fx.Pop(crown) -- 0.3 s delay, 0.5 s
    T.ok(crown:GetScale() > 0, "never a scale of 0, which the game refuses")
    T.ok(crown:GetScale() <= 0.01, "too small to see at once")
    W.advance(0.25)
    T.ok(crown:GetScale() <= 0.01, "and so while it waits")
    W.advance(0.2) -- 0.15 s into the pop
    local rising = crown:GetScale()
    T.ok(rising > 0.5 and rising < 1.45, "growing")
    W.advance(0.15) -- 0.3 s into the pop: the peak, at 60 % of 0.5 s
    T.near(crown:GetScale(), 1.45, 1e-3, "the peak is 1.45")
    W.advance(0.1)
    local settling = crown:GetScale()
    T.ok(settling > 1 and settling < 1.45, "coming back")
    W.advance(0.2)
    T.eq(crown:GetScale(), 1, "settled at 1")
    T.no(ns.Fx.driver:IsShown())
end)

T.it("Pop takes a delay and seconds of its own", function()
    local G, W, ns = T.load()
    local crown = frame(G, 12, 12)
    ns.Fx.Pop(crown, 0, 0.2)
    W.advance(0.12) -- the peak at 60 % of 0.2 s
    T.near(crown:GetScale(), 1.45, 1e-3)
    W.advance(0.1)
    T.eq(crown:GetScale(), 1)
end)

T.it("Pop keeps the frame where it is: its offsets shrink as its scale grows", function()
    local G, W, ns = T.load()
    local crown = G.CreateFrame("Frame", nil, G.UIParent)
    crown:SetSize(12, 12)
    crown:SetPoint("CENTER", G.UIParent, "LEFT", 100, 50)
    ns.Fx.Pop(crown, 0, 0.5)
    for _, dt in ipairs({ 0.05, 0.1, 0.15, 0.2, 0.1 }) do
        W.advance(dt)
        local _, _, _, x, y = crown:GetPoint(1)
        T.near(x * crown:GetScale(), 100, 1e-6, "x at scale " .. crown:GetScale())
        T.near(y * crown:GetScale(), 50, 1e-6, "y at scale " .. crown:GetScale())
    end
    W.advance(1)
    local point, rel, relPoint, x, y = crown:GetPoint(1)
    T.eq(point, "CENTER")
    T.eq(rel, G.UIParent)
    T.eq(relPoint, "LEFT")
    T.eq(x, 100)
    T.eq(y, 50)
    T.eq(crown:GetScale(), 1)
end)

T.it("Glow pulses the ring twice, then hides it", function()
    local G, W, ns = T.load()
    local ring = frame(G, 46, 46):CreateTexture(nil, "OVERLAY")
    ns.Fx.Glow(ring, 2)
    T.ok(ring:IsShown(), "it shows the ring")
    T.eq(ring:GetAlpha(), 0, "dark at the start of a pulse")
    W.advance(0.42) -- the peak, 30 % of a 1.4 s pulse
    T.near(ring:GetAlpha(), 0.55, 1e-6, "up to 55 %")
    W.advance(0.56)
    local fading = ring:GetAlpha()
    T.ok(fading > 0 and fading < 0.55, "fading")
    W.advance(0.42) -- 1.4 s: the end of the first pulse
    T.near(ring:GetAlpha(), 0, 1e-6, "dark between the pulses")
    W.advance(0.42)
    T.near(ring:GetAlpha(), 0.55, 1e-6, "the second pulse peaks the same")
    T.ok(ring:IsShown())
    W.advance(1.0) -- 2.82 s
    T.eq(ring:GetAlpha(), 0, "dark")
    T.no(ring:IsShown(), "hidden at the end of the second pulse")
end)

T.it("Glow pulses once or as often as asked", function()
    local G, W, ns = T.load()
    local ring = frame(G, 46, 46):CreateTexture(nil, "OVERLAY")
    ns.Fx.Glow(ring, 1)
    W.advance(1.41)
    T.no(ring:IsShown(), "one pulse is 1.4 s")
    ns.Fx.Glow(ring, 3)
    W.advance(2.9)
    T.ok(ring:IsShown(), "three pulses are not over at 2.9 s")
    W.advance(1.4)
    T.no(ring:IsShown())
    ns.Fx.Glow(ring)
    W.advance(1.5)
    T.ok(ring:IsShown(), "twice when it is not said: still pulsing after one pulse")
    W.advance(1.4)
    T.no(ring:IsShown())
end)

T.it("Shine slides the band across the card once, then hides it", function()
    local G, W, ns = T.load()
    local card = frame(G, 300, 100)
    local band = card:CreateTexture(nil, "ARTWORK")
    band:SetSize(10, 10)
    band:Hide()
    ns.Fx.Shine(band, 102) -- 34 % of the card
    T.ok(band:IsShown(), "it shows the band")
    T.eq(band:GetWidth(), 102, "the band is that wide")
    T.eq(band:GetHeight(), 100, "and as high as the card")
    T.near(band:GetLeft() - card:GetLeft(), -1.2 * 102, 1e-6, "clear of the card's left edge")
    W.advance(0.2)
    T.near(band:GetLeft() - card:GetLeft(), -1.2 * 102, 1e-6, "it waits 0.2 s")
    W.advance(0.55) -- halfway through its 1.1 s
    T.near(band:GetLeft() - card:GetLeft(), (-1.2 + 4.4 * out(0.5)) * 102, 1e-6, "crossing, ease-out")
    T.ok(band:IsShown())
    W.advance(0.56)
    T.no(band:IsShown(), "gone after 1.3 s")
end)

T.it("Shine ends clear of the card's right edge", function()
    local G, W, ns = T.load()
    local card = frame(G, 300, 100)
    local band = card:CreateTexture(nil, "ARTWORK")
    ns.Fx.Shine(band, 102)
    W.advance(1.29) -- 1.09 s into its 1.1 s
    T.ok(band:IsShown())
    local x = band:GetLeft() - card:GetLeft()
    T.ok(x > 300, "past the card's right edge by the end of the sweep, at " .. tostring(x))
end)

T.it("FadeIn fades a region in over 0.35 s", function()
    local G, W, ns = T.load()
    local pick = frame(G):CreateTexture(nil, "ARTWORK")
    ns.Fx.FadeIn(pick)
    T.eq(pick:GetAlpha(), 0, "invisible at once")
    W.advance(0.175)
    T.near(pick:GetAlpha(), out(0.5), 1e-6)
    W.advance(0.17)
    T.ok(pick:GetAlpha() < 1, "not there before 0.35 s")
    W.advance(0.01)
    T.eq(pick:GetAlpha(), 1)
    ns.Fx.FadeIn(pick, 1)
    W.advance(0.5)
    T.near(pick:GetAlpha(), out(0.5), 1e-6, "its own seconds")
end)

-------------------------------------------------------------------------------
--  One effect per object, and putting an object at rest
-------------------------------------------------------------------------------
T.it("a new effect on an object takes over from the one running", function()
    local G, W, ns = T.load()
    local fs = number(ns, frame(G))
    local texts = {}
    local setText = fs.SetText
    fs.SetText = function(self, text) -- every text the font string is given
        texts[#texts + 1] = tostring(text)
        return setText(self, text)
    end
    ns.Fx.Spin(fs, 10)
    W.advance(0.3)
    ns.Fx.Spin(fs, 20) -- puts the first at rest (it shows its number for that instant), then spins on its own
    texts = {}
    W.advance(0.8)
    T.eq(fs:GetText(), "20")
    W.advance(2)
    T.eq(fs:GetText(), "20")
    T.eq(fs:GetTextScale(), 1)
    for _, text in ipairs(texts) do T.ok(text ~= "10", "the first spin's number is never shown again") end

    local pick = frame(G):CreateTexture(nil, "ARTWORK")
    ns.Fx.FadeIn(pick, 1)
    W.advance(0.5)
    ns.Fx.FadeIn(pick, 0.2)
    T.eq(pick:GetAlpha(), 0, "a second fade starts from the start")
    W.advance(0.3)
    T.eq(pick:GetAlpha(), 1)
    W.advance(2)
    T.eq(pick:GetAlpha(), 1, "and the first one is gone")

    local f = frame(G)
    ns.Fx.Rise(f)
    W.advance(0.1)
    local done = 0
    ns.Fx.Sink(f, function() done = done + 1 end)
    W.advance(2)
    T.eq(done, 1)
    T.eq(f:GetAlpha(), 1)
    T.eq(select(2, offsets(f)), -226, "a Rise cut short by a Sink leaves the frame where it belongs")
    T.eq(f:GetNumPoints(), 1)
end)

T.it("Cancel on an effect and Stop put the object back at rest", function()
    local G, W, ns = T.load()
    local card = frame(G, 300, 100)

    local fs = number(ns, card)
    local spin = ns.Fx.Spin(fs, 77)
    W.advance(0.3)
    spin:Cancel()
    T.eq(fs:GetText(), "77", "a spin cut short shows its number")
    T.eq(fs:GetTextScale(), 1)
    W.advance(1)
    T.eq(fs:GetText(), "77")
    spin = ns.Fx.Spin(fs, 78)
    W.advance(0.85)
    T.ok(fs:GetTextScale() > 1, "in the bump")
    ns.Fx.Stop(fs)
    T.eq(fs:GetTextScale(), 1, "a bump cut short is over")
    T.eq(fs:GetText(), "78")

    local f = frame(G)
    ns.Fx.Rise(f)
    W.advance(0.1)
    ns.Fx.Stop(f)
    T.eq(f:GetAlpha(), 1)
    T.eq(select(2, offsets(f)), -226)
    T.no(ns.Fx.driver:IsShown(), "nothing runs any more")

    local ring = card:CreateTexture(nil, "OVERLAY")
    ns.Fx.Glow(ring, 2)
    W.advance(0.3)
    ns.Fx.Stop(ring)
    T.eq(ring:GetAlpha(), 0)
    T.no(ring:IsShown())

    local crown = frame(G, 12, 12)
    ns.Fx.Pop(crown)
    W.advance(0.4)
    ns.Fx.Stop(crown)
    T.eq(crown:GetScale(), 1)
    local cx, cy = offsets(crown)
    T.eq(cx, 372, "and its anchors are as they were")
    T.eq(cy, -226)

    local wash = card:CreateTexture(nil, "BACKGROUND")
    wash:SetPoint("TOPLEFT", card, "TOPLEFT")
    wash:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
    wash:SetWidth(200)
    wash:SetAlpha(0.28)
    ns.Fx.Wash(wash)
    W.advance(0.2)
    ns.Fx.Stop(wash)
    T.eq(wash:GetWidth(), 200)
    T.eq(wash:GetAlpha(), 0.28)

    local pick = card:CreateTexture(nil, "ARTWORK")
    ns.Fx.FadeIn(pick)
    W.advance(0.1)
    ns.Fx.Stop(pick)
    T.eq(pick:GetAlpha(), 1)

    local band = card:CreateTexture(nil, "ARTWORK")
    ns.Fx.Shine(band, 100)
    W.advance(0.5)
    ns.Fx.Stop(band)
    T.no(band:IsShown())

    ns.Fx.Stop(card) -- an object with no effect: nothing to do
    ns.Fx.Stop(ring)
end)

T.it("Cancel on a Sink puts the frame back and never calls done", function()
    local G, W, ns = T.load()
    local f = frame(G)
    local done = 0
    local sink = ns.Fx.Sink(f, function() done = done + 1 end)
    W.advance(0.3)
    T.ok(f:GetAlpha() < 1)
    T.ok(sink:IsRunning())
    sink:Cancel()
    T.no(sink:IsRunning())
    T.eq(f:GetAlpha(), 1, "the window comes back when a new roll arrives mid-fade")
    T.eq(select(2, offsets(f)), -226)
    W.advance(2)
    T.eq(done, 0)
    T.eq(f:GetAlpha(), 1)
end)

T.it("a finished effect is no longer running, and Cancel after the end changes nothing", function()
    local G, W, ns = T.load()
    local pick = frame(G):CreateTexture(nil, "ARTWORK")
    local fade = ns.Fx.FadeIn(pick)
    T.ok(fade:IsRunning())
    W.advance(1)
    T.no(fade:IsRunning())
    pick:SetAlpha(0.4) -- the caller's own change after the effect
    fade:Cancel()
    ns.Fx.Stop(pick)
    T.eq(pick:GetAlpha(), 0.4, "a finished effect has nothing left to put right")
end)
