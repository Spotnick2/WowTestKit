-- WoW.reset detaches the discarded frames from parents that survive it
-- (WowTestKit #46).
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

done("test_reset")
