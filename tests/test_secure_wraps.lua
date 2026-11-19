-- SecureHandlerWrapScript on OnEnter, OnLeave, OnShow and OnHide, and
-- control:RunFor (WowTestKit #93; SecureHandlers.lua and RestrictedFrames.lua,
-- wow-ui-source forever 70959).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- GlassRaidFrames' hover keys (Cell's and Clique's design): entering a unit
-- tile binds a key to click it, leaving or hiding it clears the binding.
local header = CreateFrame("Frame", "KitHoverHeader", UIParent, "SecureHandlerBaseTemplate")
header:SetAttribute("hoverkeys", [[ self:SetBindingClick(true, "7", self, "LeftButton"); bound = (bound or 0) + 1 ]])
local tile = CreateFrame("Button", "KitTile", UIParent, "SecureActionButtonTemplate")
tile:SetAttribute("type", "spell")
tile:SetAttribute("spell", "Renew")
local own = {}
tile:SetScript("OnEnter", function(_, motion) own[#own + 1] = "enter:" .. tostring(motion) end)
tile:SetScript("OnLeave", function(_, motion) own[#own + 1] = "leave:" .. tostring(motion) end)
local function seen() local s = table.concat(own, " "); own = {}; return s end
SecureHandlerWrapScript(tile, "OnEnter", header, [[ control:RunFor(self, control:GetAttribute("hoverkeys")) ]])
SecureHandlerWrapScript(tile, "OnLeave", header, [[ self:ClearBindings() ]])
SecureHandlerWrapScript(tile, "OnHide", header, [[ self:ClearBindings(); hidden = (hidden or 0) + 1 ]])
local env = WoW.secureEnvironment(header)

WoW.combat = true
WoW.enter(tile)
check(WoW.overrideBindings["7"] and WoW.overrideBindings["7"].name == "KitTile", "entering binds the key, in combat")
eq(env.bound, 1, "RunFor ran the body in the header's environment")
eq(seen(), "enter:true", "then the tile's own OnEnter, with motion")
eq(tile:GetAttribute("_wrapentered"), true, "the enter marks the frame (_wrapentered)")
check(WoW.pressKey("7", true) and #WoW.secureActions == 1 and WoW.secureActions[1].spell == "Renew",
    "the key clicks the hovered tile")
WoW.leave(tile)
eq(WoW.overrideBindings["7"], nil, "leaving clears it")
eq(seen(), "leave:true", "then the tile's own OnLeave")
eq(tile:GetAttribute("_wrapentered"), nil, "and the mark")

-- motion false: no snippet, no mark; a leave of an unentered frame runs none.
WoW.enter(tile, false)
eq(env.bound, 1, "an enter without motion runs no snippet")
eq(seen(), "enter:false", "but the script, with motion false")
WoW.enter(tile)
WoW.leave(tile, false)
check(WoW.overrideBindings["7"] ~= nil, "a leave without motion runs no snippet")
eq(tile:GetAttribute("_wrapentered"), true, "and keeps the mark")
seen()
WoW.combat = false
local plainLeave = CreateFrame("Button", nil, UIParent)
SecureHandlerWrapScript(plainLeave, "OnLeave", header, [[ leftPlain = true ]])
WoW.leave(plainLeave)
eq(env.leftPlain, nil, "leaving a frame never entered runs no snippet")

-- OnHide: the snippet, eligible in combat on a protected frame.
WoW.combat = true
tile:Hide()
check(tile:IsShown(), "(an addon's Hide on the tile is refused in combat)")
WoW.combat = false
tile:Hide()
eq(env.hidden, 1, "hiding runs the OnHide wrap's snippet")
eq(WoW.overrideBindings["7"], nil, "which clears the binding")
tile:Show()

-- false cancels the script; a message runs the post with it.
local panel = CreateFrame("Frame", "KitPanel", UIParent, "SecureFrameTemplate")
local ownShows = 0
panel:SetScript("OnShow", function() ownShows = ownShows + 1 end)
SecureHandlerWrapScript(panel, "OnShow", header, [[
    shows = (shows or 0) + 1
    if blockShow then return false end
    return true, "shown " .. shows
]], [[ lastShow = message; postSelf = self:GetName() ]])
panel:Hide()
panel:Show()
check(env.shows == 1 and ownShows == 1, "OnShow: the snippet, then the panel's own script")
eq(env.lastShow, "shown 1", "the post ran with the pre's message")
eq(env.postSelf, "KitPanel", "with self the frame's handle")
env.blockShow = true
panel:Hide()
panel:Show()
check(env.shows == 2 and ownShows == 1, "false from the pre cancels the script")
eq(env.lastShow, "shown 1", "and the post")
env.blockShow = nil

local hover = CreateFrame("Button", "KitHover", UIParent, "SecureActionButtonTemplate")
local hoverOwn = 0
hover:SetScript("OnEnter", function() hoverOwn = hoverOwn + 1 end)
SecureHandlerWrapScript(hover, "OnEnter", header, [[ if noHover then return false end; return true, "hi" ]],
    [[ hoverMessage = message ]])
WoW.enter(hover)
check(hoverOwn == 1 and env.hoverMessage == "hi", "OnEnter: the script, then the post with the message")
env.noHover = true
WoW.enter(hover)
eq(hoverOwn, 1, "false from the pre cancels the OnEnter script")
env.noHover = nil
local leftOwn = 0
hover:SetScript("OnLeave", function() leftOwn = leftOwn + 1 end)
SecureHandlerWrapScript(hover, "OnLeave", header, [[ if keepHover then return false end; return true, "bye" ]],
    [[ leaveMessage = message ]])
WoW.leave(hover)
check(leftOwn == 1 and env.leaveMessage == "bye", "OnLeave: the script, then the post with the message")
WoW.enter(hover)
env.keepHover = true
WoW.leave(hover)
eq(leftOwn, 1, "false from the pre cancels the OnLeave script")
env.keepHover = nil

-- An unprotected frame in combat isn't eligible: the script runs, no snippet.
local loose = CreateFrame("Frame", nil, UIParent)
local looseShows = 0
loose:SetScript("OnShow", function() looseShows = looseShows + 1 end)
SecureHandlerWrapScript(loose, "OnShow", header, [[ looseSnippet = (looseSnippet or 0) + 1; return false ]])
loose:Hide()
WoW.combat = true
loose:Show()
check(looseShows == 1 and env.looseSnippet == nil, "in combat an unprotected frame's OnShow runs without its snippet")
WoW.combat = false

-- Unwrap restores the script that was there.
local h = SecureHandlerUnwrapScript(hover, "OnEnter")
eq(h, header, "UnwrapScript on OnEnter returns the header")
WoW.enter(hover)
eq(hoverOwn, 3, "and the frame's own OnEnter is back")
WoW.enter(CreateFrame("Frame"))   -- no OnEnter: nothing to run

-- RunFor's own rules (RestrictedFrames.lua:725).
SecureHandlerSetFrameRef(header, "tile", tile)
SecureHandlerExecute(header, [[
    runForSelf = control:RunFor(owner:GetFrameRef("tile"), "return self:GetName()")
    runForNil = control:RunFor(nil, "return self == nil, ...", "x")
]])
eq(env.runForSelf, "KitTile", "RunFor runs with the other frame's handle as self")
eq(env.runForNil, true, "nil is a valid other frame")
check(not pcall(SecureHandlerExecute, header, [[ control:RunFor("KitTile", "x = 1") ]]),
    "anything but a handle or nil is refused")
check(not pcall(SecureHandlerExecute, header, [[ control:RunFor(nil, 42) ]]), "the body must be a string")

done("test_secure_wraps")
