-- Secure handlers: wrapped OnClick snippets, frame refs, handles, the secure
-- action, and clicks to drive them (WowTestKit #20; Blizzard's
-- Blizzard_RestrictedAddOnEnvironment, wow-ui-source 70862).
dofile("kit.lua")
Kit.load({ build = "70532" })

Kit.checkCore()   -- the secure handler globals are the build's

-- A wheel like Apotheca's: a secure ring, an insecure art child on it, and a
-- secure button whose wrapped click opens the ring.
local header = CreateFrame("Frame", "KitHeader", UIParent, "SecureHandlerBaseTemplate")
local ring = CreateFrame("Frame", "KitRing", UIParent, "SecureFrameTemplate")
ring:Hide()
local art = CreateFrame("Frame", nil, ring)
local log = {}
art:SetScript("OnShow", function() log[#log + 1] = "art+" end)
art:SetScript("OnHide", function() log[#log + 1] = "art-" end)
local button = CreateFrame("Button", "KitUse", UIParent, "SecureActionButtonTemplate")
button:SetAttribute("type", "item")
button:SetAttribute("item", "Healing Potion")
button:SetAttribute("target-slot", 16)
local pre, post = {}, {}
button:SetScript("PreClick", function(_, b, d) log[#log + 1] = "pre:" .. b .. ":" .. tostring(d) end)
button:SetScript("PostClick", function() log[#log + 1] = "post" end)
local function seen() local s = table.concat(log, " "); log = {}; return s end

check(header._protected and ring._protected and button._protected, "the secure templates protect")
SecureHandlerSetFrameRef(header, "ring", ring)
check(type(header:GetAttribute("frameref-ring")) == "userdata", "a frame ref is a handle (userdata) attribute")
SecureHandlerWrapScript(button, "OnClick", header, [[
    local ring = owner:GetFrameRef("ring")
    if ring:IsShown() then ring:Hide() else ring:Show() end
    clicks = (clicks or 0) + 1
    if button == "RightButton" then return "LeftButton" end
    return nil, "opened " .. clicks
]], [[
    lastMessage = message
    posts = (posts or 0) + 1
]])

-- In combat: the snippet changes the protected ring; the item is used on
-- the key-down edge only.
WoW.combat = true
WoW.click(button, "LeftButton", true)
eq(seen(), "pre:LeftButton:true art+ post", "PreClick, the snippet (the ring shows, its art gets OnShow), PostClick")
check(ring:IsShown(), "a snippet shows a protected frame in combat")
eq(#WoW.blocked, 0, "with nothing blocked")
eq(#WoW.secureActions, 1, "the secure action ran on the down edge (ActionButtonUseKeyDown)")
local act = WoW.secureActions[1]
check(act.button == "KitUse" and act.type == "item" and act.item == "Healing Potion" and act.targetSlot == 16,
    "and recorded the item and target-slot")
local env = WoW.secureEnvironment(header)
eq(env.clicks, 1, "a snippet's global lives in the header's environment")
eq(env.lastMessage, "opened 1", "the post snippet ran with the pre's message")
WoW.click(button, "LeftButton", false)
eq(#WoW.secureActions, 1, "the up edge of the same click doesn't use it again")
check(not ring:IsShown(), "(the up edge's snippet toggled the ring back)")
eq(seen(), "pre:LeftButton:false art- post", "and the art got OnHide")

-- A string from the pre replaces the button; no message, no post.
local posts = env.posts
WoW.click(button, "RightButton", true)
eq(WoW.secureActions[2].mouse, "LeftButton", "a string from the pre snippet replaces the button")
eq(env.posts, posts, "no message: the post snippet doesn't run")

-- false cancels the click.
local cancel = CreateFrame("Button", "KitCancel", UIParent, "SecureActionButtonTemplate")
cancel:SetAttribute("type", "item")
WoW.combat = false   -- wrapping is refused in combat (below)
SecureHandlerWrapScript(cancel, "OnClick", header, "return false")
WoW.combat = true
local n = #WoW.secureActions
WoW.click(cancel, "LeftButton", true)
eq(#WoW.secureActions, n, "false from the pre snippet cancels the click")

-- An unprotected frame in combat isn't eligible: no snippet, its script runs.
local plain = CreateFrame("Button", nil, UIParent)
local ran = 0
plain:SetScript("OnClick", function() ran = ran + 1 end)
WoW.combat = false
SecureHandlerWrapScript(plain, "OnClick", header, "plainRuns = (plainRuns or 0) + 1")
WoW.combat = true
WoW.click(plain, "LeftButton", false)
eq(ran, 1, "an unprotected frame's own script still runs in combat")
eq(env.plainRuns, nil, "but its wrap's snippet doesn't (IsWrapEligible)")
WoW.combat = false
WoW.click(plain, "LeftButton", false)
eq(env.plainRuns, 1, "out of combat it does")

-- The API is refused in combat (through Blizzard's protected frame).
WoW.blocked = {}
WoW.combat = true
SecureHandlerSetFrameRef(header, "late", plain)
eq(header:GetAttribute("frameref-late"), nil, "SecureHandlerSetFrameRef does nothing in combat")
check(WoW.blocked[1] and WoW.blocked[1]:find("SecureHandlerSetFrameRef", 1, true), "and the refusal is recorded")
WoW.combat = false
WoW.blocked = {}

-- Unwrap: the outermost wrap comes off, with its details.
local h, p, q = SecureHandlerUnwrapScript(plain, "OnClick")
check(h == header and p:find("plainRuns", 1, true) and q == nil, "UnwrapScript returns the header and snippets")
WoW.click(plain)
eq(env.plainRuns, 1, "the unwrapped snippet no longer runs")

-- What a snippet may not do.
check(not pcall(SecureHandlerExecute, header, "local f = function() end"), "the function keyword is refused")
check(not pcall(SecureHandlerExecute, header, "local t = {}"), "direct table creation is refused")
check(not pcall(SecureHandlerExecute, header, "print('x')"), "an insecure global (print) isn't there")
check(not pcall(SecureHandlerWrapScript, plain, "OnClick", CreateFrame("Frame"), "x = 1"),
    "a header must be explicitly protected")
check(not pcall(SecureHandlerWrapScript, button, "OnEnter", header, "x = 1"), "only OnClick is modelled, and says so")

-- SecureHandlerExecute, RunAttribute, newtable, control.
SecureHandlerExecute(header, [[
    list = newtable()
    table.insert(list, "a")
    tinsert(list, "b")
    self:SetAttribute("_toggle", "toggled = (toggled or 0) + select('#', ...)")
    me = self:GetName()
]])
eq(table.concat(env.list, ","), "a,b", "Execute runs in the header's environment, with the table helpers")
eq(env.me, "KitHeader", "with self the header's handle")
SecureHandlerExecute(header, [[ self:RunAttribute("_toggle", 1, 2, 3) ]])
eq(env.toggled, 3, "RunAttribute runs the attribute's snippet with its arguments")

-- Handles: points, GetMousePosition, bindings.
ring._left, ring._bottom, ring._width, ring._height = 100, 100, 200, 100
WoW.cursorX, WoW.cursorY = 150, 175
SecureHandlerExecute(header, [[
    local r = owner:GetFrameRef("ring")
    mx, my = r:GetMousePosition()
    r:ClearAllPoints()
    r:SetPoint("CENTER", owner, "CENTER", 0, 10)
    self:SetBindingClick(true, "ESCAPE", "KitUse", "LeftButton")
]])
eq(env.mx, 0.25, "GetMousePosition: the cursor's x as a fraction of the rect")
eq(env.my, 0.75, "and its y")
local pt = ring._points[1]
check(pt[1] == "CENTER" and pt[2] == header and pt[5] == 10, "SetPoint takes another handle as the relative frame")
WoW.cursorX = 50
SecureHandlerExecute(header, [[ out = owner:GetFrameRef("ring"):GetMousePosition() ]])
eq(env.out, nil, "outside the rect it's nil")
n = #WoW.secureActions
check(WoW.pressKey("ESCAPE", true), "a key on an override binding clicks its button")
eq(#WoW.secureActions, n + 1, "and the button acts")
SecureHandlerExecute(header, "self:ClearBindings()")
check(not WoW.pressKey("ESCAPE", true), "ClearBindings removes the frame's bindings")

-- The edge: the useOnKeyDown attribute, else the CVar.
local up = CreateFrame("Button", "KitUp", UIParent, "SecureActionButtonTemplate")
up:SetAttribute("useOnKeyDown", false)
up:SetAttribute("type", "item")
n = #WoW.secureActions
up:Click("LeftButton", true)
eq(#WoW.secureActions, n, "useOnKeyDown = false: the down edge does nothing")
up:Click("LeftButton", false)
eq(#WoW.secureActions, n + 1, "the up edge acts (Button:Click is WoW.click)")
up:SetAttribute("useOnKeyDown", nil)
WoW.useKeyDown = false
up:Click("LeftButton", false)
eq(#WoW.secureActions, n + 2, "no attribute: the ActionButtonUseKeyDown CVar decides")
up:Disable()
up:Click("LeftButton", false)
eq(#WoW.secureActions, n + 2, "a disabled button doesn't click")

done("test_secure_handlers")
