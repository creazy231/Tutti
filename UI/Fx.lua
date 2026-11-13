-------------------------------------------------------------------------------
--  Tutti: tweens and the animations (the mockup's @keyframes, in code). One hidden frame, Fx.driver, has
--  the only OnUpdate: every tween runs from it, and it hides itself when none is left, so an idle addon costs
--  nothing. Callbacks run protected (ns.Safe): one that raises is reported and its tween stops, the others go on.
--
--    Fx.Tween(seconds, onStep(t, age), onDone, delay) -> tween
--        t runs 0 to 1, eased out (cubic); age is the seconds it has run, after the delay. onStep(0, 0) is
--        called at once, so a start state is drawn before the first frame. tween:Cancel() stops it where it is
--        (no onDone); tween:IsRunning().
--
--  The effects are tweens that know their object. Each returns an effect with Cancel() and IsRunning(), and:
--    * an object has one effect at a time: a new one first puts the old one at rest;
--    * Cancel() on an effect, and Fx.Stop(object), put the object at rest (what the effect leaves when it
--      ends) and call no callback. A pooled view calls Fx.Stop on its regions when it is released, so an
--      effect never goes on in a view that belongs to another card now.
--
--    Spin(fs, final, seconds)   random 1-100 on every frame for 0.75 s, then `final`, landing at 1.5 times its
--                               size and shrinking in 0.35 s. The text grows from where the font string is
--                               anchored (a right-aligned number grows to the left).
--    Wash(tex, seconds)         0.7 s: the texture grows from its left edge, width 0 to the width it has
--                               (however it is anchored: SetAllPoints will do), and its alpha from 30 % to
--                               its own. It is shown, and stays when it is done.
--    Pop(frame, delay, seconds) scale 0, then 1.45 after `delay` (0.3 s), then 1, 0.5 s in all. The frame
--                               grows from its anchor point and its offsets are kept in place: anchor the
--                               crown by its CENTER to have it pop from its middle.
--    Glow(ring, times)          the ring's alpha 0 to 0.55 to 0, once per 1.4 s, `times` times (2): it shows
--                               the ring and hides it at the end. Tint the ring yourself.
--    Shine(band, width)         the band, `width` wide (34 % of the card) and as high as its parent, slides from
--                               clear of the parent's left edge to clear of its right one in 1.1 s after 0.2 s,
--                               then it is hidden. The parent should clip its children. Alpha is yours.
--    FadeIn(region, seconds)    alpha 0 to 1, 0.35 s.
--    Rise(frame)                alpha 0 to 1 and 8 px up to its place, 0.35 s. It moves every anchor.
--    Sink(frame, onDone)        alpha to 0 and 6 px down, 0.55 s, then onDone (the frame is faded out; hide
--                               it there), then the frame is put back as it was, so the next Show needs no Rise.
--    Stop(object)               put the object's running effect, if any, at rest.
-------------------------------------------------------------------------------
local _, ns = ...
local Fx = {}
ns.Fx = Fx

local floor, max = math.floor, math.max

-- Seconds and sizes: the mockup's keyframes, and the Global Constraints' timings.
local SPIN, BUMP, BUMP_FROM = 0.75, 0.35, 1.5                      -- a number spins, lands big, shrinks
local WASH, WASH_FROM = 0.7, 0.3                                   -- the wash grows, from 30 % of its alpha
local POP_DELAY, POP, POP_PEAK, POP_AT = 0.3, 0.5, 1.45, 0.6       -- the crown: waits, pops, peaks at 60 %
local GLOW, GLOW_PEAK, GLOW_AT = 1.4, 0.55, 0.3                    -- one pulse of the ring, its peak at 30 %
local SHINE, SHINE_DELAY, SHINE_FROM, SHINE_TO = 1.1, 0.2, -1.2, 3.2 -- the sweep, from and to in band widths
local FADE = 0.35                                                  -- a new pick
local RISE, RISE_PX = 0.35, 8                                      -- the window opens
local SINK, SINK_PX = 0.55, 6                                      -- the window closes
local TINY = 0.001 -- the least scale or width drawn: the game refuses a scale of 0
local EPSILON = 1e-9 -- times are sums of floats: "at 0.75 s" is 0.75 to within this

-- Ease-out cubic.
local function ease(u)
    if u <= 0 then return 0 end
    if u >= 1 then return 1 end
    local v = 1 - u
    return 1 - v * v * v
end

-- A number the caller gave, else the default.
local function num(value, default) return ns.Clear(value, "number") or default end

-------------------------------------------------------------------------------
--  The driver and the tweens
-------------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:Hide()
Fx.driver = driver

local live = {}       -- the running tweens, in the order they started
local stepping = false -- the driver is walking `live`: nothing may be taken out of it now

-- Takes the stopped tweens out, and hides the driver when none is left.
local function compact()
    local n = 0
    for i = 1, #live do
        local tween = live[i]
        if tween.alive then
            n = n + 1
            live[n] = tween
        end
    end
    for i = #live, n + 1, -1 do live[i] = nil end
    if n == 0 then driver:Hide() end
end

local Handle = {}
Handle.__index = Handle

function Handle:Cancel()
    if not self.alive then return end
    self.alive = false
    if not stepping then compact() end
end

function Handle:IsRunning() return self.alive end

-- One frame of one tween: `dt` seconds more.
local function advance(tween, dt)
    tween.age = tween.age + dt
    if tween.age < 0 then return end -- still waiting
    local length = tween.length
    local finished = tween.age >= length - EPSILON
    local age = finished and length or tween.age
    if tween.step and not ns.Safe(tween.step, ease(length > 0 and age / length or 1), age) then
        tween.alive = false -- a step that raised is not called again
        return
    end
    if finished and tween.alive then
        tween.alive = false
        if tween.done then ns.Safe(tween.done) end
    end
end

driver:SetScript("OnUpdate", function(_, dt)
    dt = num(dt, 0)
    stepping = true
    -- The count is read once: a tween started by a callback runs from the next frame.
    for i = 1, #live do
        local tween = live[i]
        if tween.alive then advance(tween, dt) end
    end
    stepping = false
    compact()
end)

function Fx.Tween(seconds, onStep, onDone, delay)
    local tween = setmetatable({
        length = max(num(seconds, 0), 0), step = onStep, done = onDone, age = -max(num(delay, 0), 0), alive = true,
    }, Handle)
    live[#live + 1] = tween
    driver:Show()
    if onStep and not ns.Safe(onStep, 0, 0) then tween:Cancel() end
    return tween
end

-------------------------------------------------------------------------------
--  Effects: a tween with an object it works on and a state it leaves that object in
-------------------------------------------------------------------------------
local Effect = {}
Effect.__index = Effect

local tracked = setmetatable({}, { __mode = "k" }) -- object -> the effect running on it

function Effect:IsRunning() return self.tween:IsRunning() end

function Effect:Cancel()
    if not self.tween:IsRunning() then return end
    self.tween:Cancel()
    if tracked[self.target] == self then tracked[self.target] = nil end
    self.rest()
end

function Fx.Stop(target)
    local effect = tracked[target]
    if effect then effect:Cancel() end
end

-- Starts an effect on `target`: step(t, age) is its frame, rest() leaves the object as it belongs when it
-- ends or is cancelled, after(), if given, is called when it ends (not when it is cancelled), before rest.
local function run(target, seconds, step, rest, delay, after)
    Fx.Stop(target)
    local effect = setmetatable({ target = target, rest = rest }, Effect)
    tracked[target] = effect
    effect.tween = Fx.Tween(seconds, step, function()
        if tracked[target] == effect then tracked[target] = nil end
        if after then ns.Safe(after) end
        rest()
    end, delay)
    return effect
end

-- A font string's size: SetTextScale where the client has it (the anchors stay put), else SetScale.
local function setTextScale(fs, scale)
    if fs.SetTextScale then
        fs:SetTextScale(scale)
    elseif fs.SetScale then
        fs:SetScale(scale)
    end
end

-- A frame's anchors, to move the frame and put it back. The effect that moves a frame sets every anchor
-- again from this list, so a frame with several keeps its size.
local function anchorsOf(frame)
    local list = {}
    for i = 1, frame:GetNumPoints() do
        local point, relTo, relPoint, x, y = frame:GetPoint(i)
        list[#list + 1] = { point, relTo, relPoint, ns.Clear(x, "number") or 0, ns.Clear(y, "number") or 0 }
    end
    return list
end

local function moveBy(frame, anchors, dy)
    for _, a in ipairs(anchors) do frame:SetPoint(a[1], a[2], a[3], a[4], a[5] + dy) end
end

-------------------------------------------------------------------------------
--  The effects
-------------------------------------------------------------------------------
function Fx.Spin(fs, final, seconds)
    seconds = num(seconds, SPIN)
    local landed = false
    return run(fs, seconds + BUMP, function(_, age)
        if age < seconds - EPSILON then
            fs:SetText(random(1, 100))
            return
        end
        if not landed then
            landed = true
            fs:SetText(final)
        end
        setTextScale(fs, 1 + (BUMP_FROM - 1) * (1 - ease((age - seconds) / BUMP)))
    end, function()
        fs:SetText(final)
        setTextScale(fs, 1)
    end)
end

function Fx.Wash(tex, seconds)
    Fx.Stop(tex)
    local home = anchorsOf(tex)
    local full, height = tex:GetWidth(), tex:GetHeight()
    if not (full > 0) then -- a texture hung from the left with no width of its own is as wide as its row
        local parent = tex:GetParent()
        full = parent and parent:GetWidth() or 0
    end
    local alpha = tex:GetAlpha()
    -- It grows from its left edge, so only the anchors on its left stay, and it keeps the height the others
    -- gave it. (A texture laid out too early to have a size is shown as it is.)
    local left = {}
    for _, a in ipairs(home) do
        if a[1] and a[1]:find("LEFT", 1, true) then left[#left + 1] = a end
    end
    if #left > 0 and full > 0 and height > 0 then
        tex:ClearAllPoints()
        moveBy(tex, left, 0)
        tex:SetHeight(height)
    end
    tex:Show()
    return run(tex, num(seconds, WASH), function(t)
        tex:SetWidth(max(full * t, TINY))
        tex:SetAlpha(alpha * (WASH_FROM + (1 - WASH_FROM) * t))
    end, function()
        if #home > 0 then
            tex:ClearAllPoints()
            moveBy(tex, home, 0)
        end
        tex:SetWidth(full)
        tex:SetAlpha(alpha)
    end)
end

function Fx.Pop(frame, delay, seconds)
    Fx.Stop(frame)
    seconds = num(seconds, POP)
    local home = anchorsOf(frame)
    -- A frame's anchor offsets are in its own scale, so they grow with it: they are divided by the scale to
    -- keep the frame where it is. It grows from its anchor point (the center, for a CENTER anchor).
    local function scaleTo(scale)
        scale = max(scale, TINY)
        frame:SetScale(scale)
        for _, a in ipairs(home) do frame:SetPoint(a[1], a[2], a[3], a[4] / scale, a[5] / scale) end
    end
    return run(frame, seconds, function(_, age)
        local u = seconds > 0 and age / seconds or 1
        if u < POP_AT then
            scaleTo(POP_PEAK * ease(u / POP_AT))
        else
            scaleTo(POP_PEAK - (POP_PEAK - 1) * ease((u - POP_AT) / (1 - POP_AT)))
        end
    end, function()
        scaleTo(1)
    end, num(delay, POP_DELAY))
end

function Fx.Glow(ring, times)
    Fx.Stop(ring)
    times = max(floor(num(times, 2)), 1)
    ring:Show()
    return run(ring, GLOW * times, function(_, age)
        local u = (age % GLOW) / GLOW
        if u < GLOW_AT then
            ring:SetAlpha(GLOW_PEAK * ease(u / GLOW_AT))
        else
            ring:SetAlpha(GLOW_PEAK * (1 - ease((u - GLOW_AT) / (1 - GLOW_AT))))
        end
    end, function()
        ring:SetAlpha(0)
        ring:Hide()
    end)
end

function Fx.Shine(band, width)
    Fx.Stop(band)
    local card = band:GetParent()
    width = num(width, band:GetWidth())
    band:SetWidth(width)
    band:Show()
    return run(band, SHINE, function(t)
        local x = (SHINE_FROM + (SHINE_TO - SHINE_FROM) * t) * width
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", card, "TOPLEFT", x, 0)
        band:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 0)
    end, function()
        band:Hide()
    end, SHINE_DELAY)
end

function Fx.FadeIn(region, seconds)
    return run(region, num(seconds, FADE), function(t)
        region:SetAlpha(t)
    end, function()
        region:SetAlpha(1)
    end)
end

function Fx.Rise(frame)
    Fx.Stop(frame)
    local home = anchorsOf(frame)
    return run(frame, RISE, function(t)
        frame:SetAlpha(t)
        moveBy(frame, home, -RISE_PX * (1 - t))
    end, function()
        moveBy(frame, home, 0)
        frame:SetAlpha(1)
    end)
end

function Fx.Sink(frame, onDone)
    Fx.Stop(frame)
    local home, alpha = anchorsOf(frame), frame:GetAlpha()
    return run(frame, SINK, function(t)
        frame:SetAlpha(alpha * (1 - t))
        moveBy(frame, home, -SINK_PX * t)
    end, function()
        moveBy(frame, home, 0)
        frame:SetAlpha(alpha)
    end, nil, onDone)
end
