-- The widget metatable's __index is a method table per widget type, as on
-- the client (WowTestKit #7).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

-- GlassMiniMapBar's Compat.lua, at file scope: API.W = getmetatable(CreateFrame("Frame")).__index
local W = getmetatable(CreateFrame("Frame")).__index
eq(type(W), "table", "a widget's metatable has a method table as its __index")
eq(type(W.SetPoint), "function", "with the type's methods in it")

-- The type's method on a widget whose own field shadows it.
local btn = CreateFrame("Button", "KitGrabbed", UIParent)
local shadowed = 0
btn.SetPoint = function() shadowed = shadowed + 1 end   -- the addon pins the button
btn:SetPoint("TOP")
eq(shadowed, 1, "the button's own SetPoint is the no-op")
W.SetPoint(btn, "CENTER", UIParent, "CENTER", 5, 0)
eq(#btn._points, 1, "the method table's SetPoint moves it anyway")
eq(btn._points[1][1], "CENTER", "to where it was asked")
check(WoW.methodsCalled["Button:SetPoint"], "recorded for the widget it was called on")

-- The same function on every read, as on the client.
local f1, f2 = CreateFrame("Frame"), CreateFrame("Frame")
check(f1.SetPoint == f2.SetPoint and f1.SetPoint == W.SetPoint, "a type's method is one function")
check(f1.Show == W.Show, "an implemented one the type has too")

-- One table per type: each with its own methods.
local B = getmetatable(btn).__index
check(B ~= W, "a Button has its own method table")
eq(type(B.SetNormalTexture), "function", "with Button:SetNormalTexture")
eq(W.SetNormalTexture, nil, "which a Frame doesn't have")
eq(getmetatable(CreateFrame("PlayerModel")).__index.GetModel, nil, "a method the build lacks reads as nil there too")

-- An implementation-only method isn't kept: removing it takes effect.
WoW.Methods.KitOnly = function() return 1 end
eq(f1:KitOnly(), 1, "an implementation-only method is callable")
WoW.Methods.KitOnly = nil
eq(f1.KitOnly, nil, "and gone once the implementation is")

-- Through the method table, a protected frame still refuses in combat.
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local secure = CreateFrame("Frame", "KitSecure", UIParent, "KitSecureTemplate")
WoW.combat = true
W.Hide(secure)
check(secure:IsShown(), "W.Hide on a protected frame in combat is refused")
eq(WoW.blocked[#WoW.blocked], "KitSecure:Hide", "and recorded")
WoW.combat = false

done("test_method_table")
