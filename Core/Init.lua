-------------------------------------------------------------------------------
--  Tutti: namespace, strings, secret guards, and two small buses:
--    ns.On / ns.Off        game events (one hidden frame for the addon)
--    ns.Listen / ns.Fire   Tutti's own messages between modules
--  Handlers run protected: one failing handler never stops the others; its
--  error is reported through the game's error handler afterwards.
-------------------------------------------------------------------------------
local ADDON, ns = ...
ns.name = ADDON

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMeta and getMeta(ADDON, "Version")) or "dev"
-- The packager fills in the tag; a copy straight from the repository says so.
if ns.version:find("@", 1, true) then ns.version = "dev" end

-- English strings. A missing key shows the key itself.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

-------------------------------------------------------------------------------
--  Secret values (12.x engine): never compare, index or measure one. Everything the game hands over
--  (an event payload, an API result, a field of either) goes through ns.Clear before it is compared,
--  indexed or stored.
-------------------------------------------------------------------------------
local issecretvalue = issecretvalue
local hasanysecretvalues = hasanysecretvalues

function ns.IsSecret(...)
    if hasanysecretvalues then return hasanysecretvalues(...) and true or false end
    if issecretvalue then
        for i = 1, select("#", ...) do
            if issecretvalue((select(i, ...))) then return true end
        end
    end
    return false
end

-- The value when the game gave it in the clear and it has the type `kind` ("string", "number",
-- "table", "boolean"), else nil. A secret string or number still has type "string" or "number", so a
-- type check alone is not a guard. It asks ns.IsSecret each time, so a test can stand in for the game.
function ns.Clear(value, kind)
    if ns.IsSecret(value) or type(value) ~= kind then return nil end
    return value
end

-------------------------------------------------------------------------------
--  Protected dispatch
-------------------------------------------------------------------------------
local function report(errors)
    local handler = geterrorhandler and geterrorhandler()
    for i = 1, #errors do
        if handler then handler(errors[i]) end
    end
end

local function dispatch(list, ...)
    if not list then return end
    local errors
    -- Copy first: a handler may add or remove handlers.
    local n = #list
    local copy = {}
    for i = 1, n do copy[i] = list[i] end
    for i = 1, n do
        local ok, err = pcall(copy[i], ...)
        if not ok then
            errors = errors or {}
            errors[#errors + 1] = err
        end
    end
    if errors then report(errors) end
end

function ns.Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report({ err }) end
    return ok
end

-------------------------------------------------------------------------------
--  Game events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
    dispatch(eventHandlers[event], event, ...)
end)

function ns.On(event, fn)
    local list = eventHandlers[event]
    if not list then
        -- An event this client does not know must not break the addon.
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

function ns.Off(event, fn)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

-------------------------------------------------------------------------------
--  Messages between modules
-------------------------------------------------------------------------------
local listeners = {}

function ns.Listen(msg, fn)
    local list = listeners[msg]
    if not list then list = {}; listeners[msg] = list end
    list[#list + 1] = fn
end

function ns.Fire(msg, ...)
    dispatch(listeners[msg], ...)
end

-------------------------------------------------------------------------------
--  Small helpers
-------------------------------------------------------------------------------
function ns.After(seconds, fn)
    C_Timer.After(seconds, fn)
end

function ns.Print(text)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage("|cffff7d0aTutti|r: " .. tostring(text))
    end
end
