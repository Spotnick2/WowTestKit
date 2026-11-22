-- WoW.reset detaches the discarded frames from parents that survive it
-- (WowTestKit #46); WoW.reset({ keepFrames = true }) keeps them (#80).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local fired = 0
local old = CreateFrame("Frame", nil, UIParent)
old:SetScript("OnHide", function() fired = fired + 1 end)
local grand = CreateFrame("Frame", nil, old)
local before = #UIParent._children

WoW.reset()
eq(#WoW.frames, 0, "reset empties the frame registry")
eq(#UIParent._children, before - 1, "and takes the old frame out of UIParent's children")
UIParent:Hide()
eq(fired, 0, "hiding UIParent no longer reaches the old test's OnHide")
UIParent:Show()

local new = CreateFrame("Frame", nil, UIParent)
eq(UIParent._children[#UIParent._children], new, "a frame made after the reset is UIParent's child")
local seen = 0
new:SetScript("OnHide", function() seen = seen + 1 end)
UIParent:Hide()
eq(seen, 1, "and gets UIParent's OnHide")
UIParent:Show()
eq(grand._parent, old, "a discarded frame keeps its own parent link (it isn't reached anyway)")

-- A state-only reset keeps the frames built at load (WowTestKit #80).
WoW.reset()
local window = CreateFrame("Frame", "KitKeptWindow", UIParent)
local row = CreateFrame("Button", nil, window)
window:CreateTexture()
window:SetPoint("CENTER")
local events, updates, hides = 0, 0, 0
window:RegisterEvent("PLAYER_LOGIN")
window:SetScript("OnEvent", function() events = events + 1 end)
window:SetScript("OnUpdate", function() updates = updates + 1 end)
row:SetScript("OnHide", function() hides = hides + 1 end)
local nFrames, nWidgets, nUIChildren = #WoW.frames, #WoW.widgets, #UIParent._children
print("before the reset")
WoW.combat, WoW.locale = true, "deDE"
C_Timer.After(1, function() end)
table.insert(WoW.blocked, "x:Show")
local got
table.insert(WoW.onReset, function(o) got = o end)

local opts = { keepFrames = true }
WoW.reset(opts)
eq(#WoW.frames, nFrames, "keepFrames: the frame registry is kept")
eq(WoW.frames[1], window, "with the same frames")
eq(KitKeptWindow, window, "keepFrames preserves its published name")
eq(#UIParent._children, nUIChildren, "UIParent keeps its children")
eq(window._children[1], row, "a kept frame keeps its children")
eq(#WoW.widgets, nWidgets, "WoW.widgets is kept")
check(WoW.methodsCalled["Frame:SetPoint"], "and the methods called at load")
WoW.fire("PLAYER_LOGIN")
eq(events, 1, "an event still reaches a kept frame")
WoW.tick()
eq(updates, 1, "and OnUpdate")
UIParent:Hide()
eq(hides, 1, "and a parent's OnHide walk")
UIParent:Show()
eq(#WoW.chat, 0, "the chat is cleared")
eq(WoW.combat, false, "combat is cleared")
eq(WoW.locale, nil, "the locale is cleared")
eq(#WoW.timers, 0, "the timers are cleared")
eq(#WoW.blocked, 0, "WoW.blocked is cleared")
eq(got, opts, "each WoW.onReset function gets the opts")

local texture = window:CreateTexture("KitOldTexture")
window:CreateFontString("KitReplacedName")
KitReplacedName = "consumer value"
WoW.reset({})
eq(#WoW.frames, 0, "without keepFrames the frames are discarded")
eq(#UIParent._children, nUIChildren - 1, "and leave UIParent")
eq(got and got.keepFrames, nil, "and WoW.onReset sees the opts given")
eq(KitKeptWindow, window, "a full reset keeps a discarded frame's name by default")
eq(KitOldTexture, texture, "and a named region's")

-- releaseNames: the names go too, as on a /reload, so a guarded addon builds
-- its frame again (#110).
local ok, err = pcall(WoW.reset, { keepFrames = true, releaseNames = true })
check(not ok and tostring(err):find("releaseNames", 1, true), "releaseNames can't go with keepFrames: " .. tostring(err))
eq(KitKeptWindow, window, "and the refused reset released nothing")
WoW.reset({ releaseNames = true })
eq(KitOldTexture, nil, "releaseNames removes a named region")
eq(KitReplacedName, "consumer value", "and keeps a consumer's replacement global")
eq(KitKeptWindow, nil, "and releases the discarded frame's name")
local reloadEvents = 0
if not KitKeptWindow then
    local rebuilt = CreateFrame("Frame", "KitKeptWindow", UIParent)
    rebuilt:RegisterEvent("PLAYER_LOGIN")
    rebuilt:SetScript("OnEvent", function() reloadEvents = reloadEvents + 1 end)
end
WoW.fire("PLAYER_LOGIN")
eq(reloadEvents, 1, "a guarded reload receives the event exactly once")
eq(events, 1, "the discarded handler receives no second event")
WoW.reset()
eq(got, nil, "or none")

-- A frame's state drivers are its registrations, as its events are (#77):
-- a state-only reset keeps them, a full one drops them.
local driven = CreateFrame("Frame", nil, UIParent)
RegisterStateDriver(driven, "visibility", "[combat] hide; show")
WoW.reset({ keepFrames = true })
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.step(0)
check(not driven:IsShown(), "keepFrames: a state driver registered before is kept, and resolves")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.step(0)
check(driven:IsShown(), "both ways")
WoW.reset()
eq(next(WoW.stateDrivers), nil, "a full reset drops the drivers")

done("test_reset")
