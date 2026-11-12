-- The stub core's mechanics, against the newest build's data.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

-- The core's client globals are the client's.
Kit.checkCore()

-- Secrets throw on use; MarkSecret returns its value.
local s = WoW.Secret("test")
check(issecretvalue(s), "a secret is secret")
check(not pcall(function() return s .. "x" end), "concat on a secret throws")
check(not pcall(function() return s + 1 end), "arithmetic on a secret throws")
check(not pcall(tostring, s), "tostring on a secret throws")
local plain = {}
eq(WoW.MarkSecret(plain), plain, "MarkSecret returns the value")
check(issecretvalue(plain), "a marked value is secret")

-- Events: the build's names only.
local f = CreateFrame("Frame", "KitTestFrame", UIParent)
eq(rawget(_G, "KitTestFrame"), f, "a named frame is a global")
check(f:RegisterEvent("PLAYER_LOGIN"), "a known event registers")
check(not pcall(f.RegisterEvent, f, "NOT_AN_EVENT"), "an unknown event throws")
local got
f:SetScript("OnEvent", function(_, e, a) got = e .. ":" .. tostring(a) end)
WoW.fire("PLAYER_LOGIN", 1)
eq(got, "PLAYER_LOGIN:1", "fire reaches the registered frame")
check(WoW.methodsCalled["Frame:RegisterEvent"] and WoW.methodsCalled["Frame:SetScript"], "method calls are recorded")
eq(f:SetClampedToScreen(true), nil, "a real method the core doesn't implement returns nil")
check(WoW.methodsCalled["Frame:SetClampedToScreen"], "and is recorded for the methods check")
eq(f.SomethingUnstubbed, nil, "a method the build lacks reads as nil (test_absent_methods covers it)")

-- Templates and combat refusals.
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local b = CreateFrame("Button", nil, UIParent, "KitSecureTemplate, UIPanelButtonTemplate")
check(b._protected, "a template in a comma list applies")
WoW.combat = true
b:Hide()
check(b:IsShown(), "a protected frame doesn't hide in combat")
eq(WoW.blocked[1], "Button:Hide", "the refusal is recorded")
b:SetAllPoints(UIParent)
eq(#b._points, 0, "nor re-anchors with SetAllPoints")
eq(WoW.blocked[2], "Button:SetAllPoints", "that refusal is recorded too")
WoW.combat = false
b:Hide()
check(not b:IsShown(), "it hides out of combat")

-- Measured client quirks the core models.
local t = f:CreateTexture()
t:SetAlpha(0.5)
t:SetGradient("VERTICAL", {}, {})
t:SetAlpha(0)
eq(t:GetAlpha(), 0.5, "SetAlpha after SetGradient doesn't change GetAlpha (70374)")
t:SetAtlas("x")
t:SetColorTexture(1, 1, 1, 1)
check(t._atlas == nil and t._file == nil, "a colour replaces the atlas")
local slider = CreateFrame("Slider", nil, UIParent)
local changed
slider:SetScript("OnValueChanged", function(_, v) changed = v end)
slider:SetValue(3)
eq(changed, 3, "a slider's SetValue fires OnValueChanged")
eq(select("#", f:GetRegions()), 1, "regions are listed")

-- Timers: flush and the clock.
local order = {}
C_Timer.After(2, function() order[#order + 1] = "b" end)
C_Timer.After(1, function()
    order[#order + 1] = "a"
    C_Timer.After(1, function() order[#order + 1] = "c" end)
end)
WoW.advance(1)
eq(table.concat(order), "a", "advance runs what is due")
WoW.advance(1)
eq(table.concat(order), "abc", "in due order, a timer made inside one counting from then")
C_Timer.After(5, function() order[#order + 1] = "d" end)
WoW.flushTimers(1)
eq(#WoW.timers, 1, "flushTimers(upTo) keeps later timers")
WoW.flushTimers()
eq(order[#order], "d", "flushTimers() runs the rest")
local fired = 0
C_Timer.NewTicker(1, function() fired = fired + 1 end):Cancel()
WoW.advance(2)
eq(fired, 0, "a ticker cancelled before it falls due never fires under advance")
C_Timer.NewTicker(1, function() fired = fired + 1 end):Cancel()
WoW.flushTimers()
eq(fired, 0, "nor under flushTimers")

-- print and stray pipes.
print("plain |cffff0000red|r and ||")
eq(#WoW.strays, 0, "well-formed escapes aren't strays")
print("off|watch")
eq(#WoW.strays, 1, "a stray | is recorded")
WoW.strays = {}

-- hooksecurefunc.
local calls = {}
rawset(_G, "KitHooked", function() calls[#calls + 1] = "orig"; return 7 end)
hooksecurefunc("KitHooked", function() calls[#calls + 1] = "hook" end)
eq(KitHooked(), 7, "a hook keeps the original's return")
eq(table.concat(calls, ","), "orig,hook", "the hook runs after")
eq(WoW.hooked[_G].KitHooked, 1, "hooks are counted")
rawset(_G, "KitTrailing", function() return true, nil end)
hooksecurefunc("KitTrailing", function() end)
eq(select("#", KitTrailing()), 2, "a hook keeps trailing nil returns")

-- WoW.reset runs the consumer's hooks.
local resets = 0
table.insert(WoW.onReset, function() resets = resets + 1 end)
WoW.reset()
eq(resets, 1, "onReset runs")
eq(#WoW.frames, 0, "frames cleared")

-- TOC helpers and the TOC check.
eq(table.concat(Kit.tocLines("tests/fixtures/Fixture.toc"), ","), "Libs\\Lib.xml,A.lua,Sub\\B.lua", "tocLines")
eq(table.concat(Kit.tocFiles("Fixture.toc", "tests/fixtures/"), ","), "tests/fixtures/A.lua,tests/fixtures/Sub/B.lua", "tocFiles")
Kit.checkToc("Fixture.toc", { dir = "tests/fixtures/" })

-- Strict globals, last.
Kit.strict({ KitMayBeNil = true })
eq(KitMayBeNil, nil, "an allowed name reads nil")
check(not pcall(function() return KitNotDefined end), "any other undefined read throws")

done("test_core")
