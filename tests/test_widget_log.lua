-- Every call on a widget with its arguments (w._log), and every widget made
-- in creation order (WoW.widgets) (WowTestKit #67).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

eq(#WoW.widgets, 0, "UIParent, made before the first reset, isn't in WoW.widgets")
check(type(UIParent._log) == "table", "but it has a log")

local f = CreateFrame("Frame", "KitLogFrame", UIParent)
local t = f:CreateTexture(nil, "ARTWORK")
local fs = f:CreateFontString(nil, "OVERLAY")
local m = f:CreateMaskTexture()
local bar = CreateFrame("StatusBar", nil, f)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
local ag = f:CreateAnimationGroup()
local a = ag:CreateAnimation("Alpha")

local made = { f, t, fs, m, bar, bar:GetStatusBarTexture(), ag, a }
eq(#WoW.widgets, #made, "every widget made is in WoW.widgets")
for i, w in ipairs(made) do
    eq(WoW.widgets[i], w, "in creation order (" .. i .. ", " .. w._type .. ")")
end

-- The calls, in order, with their arguments; nils and their count kept.
t:SetColorTexture(1, 0.5, 0, 0.25)
t:SetPoint("TOPLEFT", f, "TOPLEFT", 2, nil)
t:SetBlendMode("ADD")
eq(#t._log, 3, "each call is logged")
local c = t._log[1]
eq(c[1], "SetColorTexture", "the method's name first")
eq(c.n, 4, "the argument count")
check(c[2] == 1 and c[3] == 0.5 and c[4] == 0 and c[5] == 0.25, "then the arguments")
eq(t._log[2][1], "SetPoint", "in the order called")
eq(t._log[2].n, 5, "a trailing nil counts")
eq(t._log[2][3], f, "a widget argument is kept as is")
eq(t._log[3][2], "ADD", "the third call's argument")
f:GetWidth()
eq(f._log[#f._log][1], "GetWidth", "a getter is logged too")
eq(f._log[#f._log].n, 0, "with no arguments")
f:SetClampRectInsets(1, 2, 3, 4)   -- on the build, no implementation
eq(f._log[#f._log][1], "SetClampRectInsets", "a method with no implementation is logged")
eq(#fs._log, 0, "a widget nothing was called on has an empty log")

-- What a stub function does inside a method isn't another call on the widget.
local before = #f._log
f:SetShown(false)
eq(#f._log, before + 1, "SetShown is one entry, not SetShown and Hide")

-- A call the combat lockdown refuses is still logged.
local secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
WoW.combat = true
secure:SetPoint("CENTER")
WoW.combat = false
eq(#WoW.blocked, 1, "the call is refused")
eq(secure._log[#secure._log][1], "SetPoint", "and logged")

-- A secure hook on a widget logs itself, then the calls through it.
hooksecurefunc(bar, "SetValue", function() end)
local hook = bar._log[#bar._log]
eq(hook[1], "hooksecurefunc:SetValue", "the hook is logged")
eq(hook.n, 0, "with no arguments")
bar:SetValue(0.5)
eq(bar._log[#bar._log][1], "SetValue", "a call through the hook is logged once")
eq(bar._log[#bar._log - 1], hook, "right after the hook")
local plain = {}
function plain.Go() end
hooksecurefunc(plain, "Go", function() end)
check(rawget(plain, "_log") == nil, "a hook on a plain table logs nothing")
hooksecurefunc("print", function() end)
check(rawget(_G, "_log") == nil, "nor a global hook")

-- "Nothing repainted": the log's length before and after.
local n = #t._log
f:GetName()
eq(#t._log, n, "a call on another widget leaves this log alone")

-- A stub's own widget (WoW.newWidget) is a widget like the others.
local own = WoW.newWidget("Texture", f)
eq(WoW.widgets[#WoW.widgets], own, "WoW.newWidget's is in WoW.widgets")
own:SetTexture(123)
eq(own._log[1][1], "SetTexture", "and logs")
check(WoW.isWidget(own) and not WoW.isWidget({}), "WoW.isWidget tells a widget from a table")

-- WoW.reset clears the list; a widget made afterwards starts it again.
WoW.reset()
eq(#WoW.widgets, 0, "WoW.reset clears WoW.widgets")
local after = CreateFrame("Frame")
eq(WoW.widgets[1], after, "the next widget is first")

-- A fresh client starts its own list.
Kit.freshClient()
eq(#WoW.widgets, 0, "a fresh client's list is empty")
CreateFrame("Button")
eq(#WoW.widgets, 1, "and fills from its own widgets")

done("test_widget_log")
