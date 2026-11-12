-- A method the build lacks reads as nil, so feature detection behaves as on
-- the client (WowTestKit #22).
dofile("kit.lua")
Kit.load({ build = "70532" })

local model = CreateFrame("PlayerModel", nil, UIParent)
eq(model.GetModel, nil, "PlayerModel:GetModel (absent on Forever) reads as nil")
local branch = type(model.GetModel) == "function" and "GetModel" or "fallback"
eq(branch, "fallback", "so a feature check takes the client's branch")
check(not pcall(function() return model:GetModel() end), "a call to it fails where it's made")
eq(WoW.methodsCalled["PlayerModel:GetModel"], nil, "and isn't recorded")
check(type(model.SetModel) == "function", "a method the build has reads as a function")
check(type(model.Show) == "function", "and an implemented one too")

local f = CreateFrame("Frame", nil, UIParent)
check(type(f.SetClampedToScreen) == "function", "a real method without an implementation reads as a function")
eq(f.GetMapID, nil, "a mixin method reads as nil until allowed")
Kit.allowMethods({ ["Frame:GetMapID"] = "MapCanvasMixin (Blizzard_MapCanvas)" })
check(type(f.GetMapID) == "function", "allowed, it reads as a function")
f:GetMapID()
check(WoW.methodsCalled["Frame:GetMapID"], "and its call is recorded")
eq(CreateFrame("Button").GetMapID, nil, "an allowed pair is that type's only")
check(not pcall(Kit.allowMethods, { ["Frame:SetBackdrop"] = "" }), "allowing without a reason throws")
check(not pcall(Kit.allowMethods, { SetBackdrop = "Backdrop.lua" }), "a pair must read Type:Method")

-- A Methods implementation reads as present on every type (the stub's say).
WoW.Methods.KitOwnMethod = function() return 7 end
eq(f:KitOwnMethod(), 7, "an implemented method is callable")
check(WoW.methodsCalled["Frame:KitOwnMethod"], "and recorded, so checkMethods still catches it")
WoW.Methods.KitOwnMethod = nil

-- Animation subtypes: their own methods or Animation's.
local alpha = CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha")
check(type(alpha.SetFromAlpha) == "function", "an Alpha's own method")
check(type(alpha.SetDuration) == "function", "an Animation method on an Alpha")
eq(alpha.SetScaleFrom, nil, "Scale's method on an Alpha reads as nil")

-- A type the build doesn't have keeps every method, for checkMethods to name.
check(type(WoW.newWidget("Gizmo").Spin) == "function", "an unknown widget type answers as before (Gizmo:Spin)")

-- A table-style lookup with no widget (GlassMiniMapBar, WowTestKit #7).
local lookup = getmetatable(f).__index
check(type(lookup(nil, "SetPoint")) == "function", "__index(nil, k) answers as before")

-- Lower-case keys are fields.
eq(f.someField, nil, "a lower-case key reads as nil")

done("test_absent_methods")
