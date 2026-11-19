-- Widget methods consumers had in their own stubs: GetSize (WowTestKit #78).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- GetSize reads what SetSize, SetWidth and SetHeight set.
local f = CreateFrame("Frame", nil, UIParent)
local w, h = f:GetSize()
check(w == 0 and h == 0, "GetSize is 0, 0 before a size is set")
f:SetSize(120, 40)
w, h = f:GetSize()
check(w == 120 and h == 40, "GetSize returns the width and height SetSize set (" .. tostring(w) .. ", " .. tostring(h) .. ")")
f:SetWidth(75)
f:SetHeight(30)
w, h = f:GetSize()
check(w == 75 and h == 30, "and SetWidth / SetHeight's")
eq(select("#", f:GetSize()), 2, "two values")
local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fs:SetSize(50, 12)
w, h = fs:GetSize()
check(w == 50 and h == 12, "a region's too")
check(WoW.methodsCalled["Frame:GetSize"], "the call is recorded")

done("test_frame_methods")
