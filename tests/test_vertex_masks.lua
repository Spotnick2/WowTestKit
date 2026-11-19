-- A texture's vertex colour and mask count read back (WowTestKit #97):
-- GetVertexColor returns what SetVertexColor set, GetNumMaskTextures counts
-- what AddMaskTexture / RemoveMaskTexture left.
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local f = CreateFrame("Frame", nil, UIParent)
local t = f:CreateTexture()

local function rgba(w) return { w:GetVertexColor() } end
local function same(got, want, msg)
    eq(#got, 4, msg .. ": four values")
    for i = 1, 4 do eq(got[i], want[i], msg .. " (" .. i .. ")") end
end

same(rgba(t), { 1, 1, 1, 1 }, "unset, a texture's vertex colour reads white")
t:SetVertexColor(0.2, 0.4, 0.6, 0.8)
same(rgba(t), { 0.2, 0.4, 0.6, 0.8 }, "it reads what SetVertexColor set")
t:SetVertexColor(1, 0, 0)
same(rgba(t), { 1, 0, 0, 1 }, "an alpha left out reads 1")
t:SetVertexColor(0, 0, 0, 0)
same(rgba(t), { 0, 0, 0, 0 }, "an alpha of 0 stays 0")

local fs = f:CreateFontString(nil, "OVERLAY")
fs:SetVertexColor(0.5, 0.5, 0.5, 0.5)
same(rgba(fs), { 0.5, 0.5, 0.5, 0.5 }, "a font string's too")
check(WoW.methodsCalled["Texture:GetVertexColor"] and WoW.methodsCalled["FontString:GetVertexColor"],
    "recorded on each type for the methods check")

-- A status bar's colour is its fill's vertex colour.
local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(0, 1, 0, 1)
same(rgba(bar:GetStatusBarTexture()), { 0, 1, 0, 1 }, "a status bar's fill reads SetStatusBarColor")

-- Masks.
local m1, m2 = f:CreateMaskTexture(), f:CreateMaskTexture()
eq(t:GetNumMaskTextures(), 0, "no mask: 0")
t:AddMaskTexture(m1)
t:AddMaskTexture(m2)
eq(t:GetNumMaskTextures(), 2, "each mask added counts")
t:RemoveMaskTexture(m1)
eq(t:GetNumMaskTextures(), 1, "a removed one doesn't")
t:RemoveMaskTexture(m1)
eq(t:GetNumMaskTextures(), 1, "removing one it doesn't have changes nothing")
check(WoW.methodsCalled["Texture:GetNumMaskTextures"], "recorded for the methods check")

Kit.checkMethods()

done("test_vertex_masks")
