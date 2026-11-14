local T = T

-- What a font string shows on screen: its plain text, "" when it or a parent is hidden.
local function text(W, fs)
    return fs:IsVisible() and W.plain(fs:GetText() or "") or ""
end

T.it("the compartment toggles Recent", function()
    local G, W, ns = T.load()
    local win = G.TuttiFrame
    for _, name in ipairs({ "Tutti_OnAddonCompartmentClick", "Tutti_OnAddonCompartmentEnter",
        "Tutti_OnAddonCompartmentLeave" }) do
        T.eq(type(G[name]), "function", name)
    end
    -- The game calls them with the addon's name, then the mouse button or the menu's button.
    G.Tutti_OnAddonCompartmentClick("Tutti", "LeftButton")
    T.ok(win:IsShown(), "a click opens the window")
    T.eq(ns.UI.View(), "recent", "on Recent rolls")
    T.eq(text(W, win.head.title), "Recent rolls")
    W.advance(0.35)
    G.Tutti_OnAddonCompartmentClick("Tutti", "RightButton")
    W.advance(0.55)
    T.no(win:IsShown(), "a second click closes it")
    G.Tutti_OnAddonCompartmentClick("Tutti", "LeftButton")
    T.ok(win:IsShown())

    local button = G.CreateFrame("Button", nil, G.UIParent)
    local tip = G.GameTooltip
    G.Tutti_OnAddonCompartmentEnter("Tutti", button)
    T.ok(tip:IsShown(), "a tooltip")
    T.eq(tip:GetOwner(), button, "on the menu's button")
    T.eq(tip._lines[1], "Tutti")
    T.eq(tip._lines[2], "Click: recent rolls")
    G.Tutti_OnAddonCompartmentLeave("Tutti", button)
    T.no(tip:IsShown(), "gone when the mouse leaves")
    G.Tutti_OnAddonCompartmentEnter("Tutti", nil)
    T.no(tip:IsShown(), "no button, no tooltip")
end)

T.it("/tutti, /tutti settings, /tutti demo", function()
    local G, W, ns = T.load()
    local win = G.TuttiFrame
    T.eq(G.SLASH_TUTTI1, "/tutti")
    local slash = G.SlashCmdList.TUTTI
    T.eq(type(slash), "function")

    slash("")
    T.ok(win:IsShown(), "/tutti opens Recent rolls")
    T.eq(ns.UI.View(), "recent")
    W.advance(0.35)
    slash("")
    W.advance(0.55)
    T.no(win:IsShown(), "and closes it again")

    slash("settings")
    T.ok(win:IsShown())
    T.eq(ns.UI.View(), "settings", "/tutti settings opens Settings")
    slash("  Settings ")
    T.eq(ns.UI.View(), "settings", "whatever the case and the spaces")
    T.ok(win:IsShown(), "and keeps it open")

    slash("demo")
    local cards = ns.Rolls.Cards()
    T.eq(#cards, 2, "/tutti demo plays the boss drop")
    T.ok(cards[1].demo and cards[2].demo)
    T.eq(ns.UI.View(), "rolls")

    slash("what")
    T.eq(#W.chatLog, 1, "anything else: what it takes")
    T.ok(W.chatLog[1]:find("/tutti settings", 1, true) and W.chatLog[1]:find("/tutti demo", 1, true))
end)
