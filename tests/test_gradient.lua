-- SetGradient drops an alpha set before it, and takes colour objects
-- (WowTestKit #37; measured on 70374, porting guide section 3).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local f = CreateFrame("Frame", nil, UIParent)
local function color(r, g, b, a) return { r = r, g = g, b = b, a = a } end   -- a CreateColor stand-in

-- The probe's squares: SetAlpha before (A), after (D), none (C).
local a = f:CreateTexture()
a:SetColorTexture(1, 1, 1, 1)
a:SetAlpha(0)
a:SetGradient("VERTICAL", color(1, 1, 1, 0), color(1, 1, 1, 1))
eq(a:GetAlpha(), 1, "SetAlpha(0) before SetGradient: the gradient drops it, GetAlpha reads 1")
local d = f:CreateTexture()
d:SetGradient("VERTICAL", color(1, 1, 1, 0), color(1, 1, 1, 1))
d:SetAlpha(0.2)
eq(d:GetAlpha(), 1, "SetAlpha after SetGradient does nothing")
local c = f:CreateTexture()
c:SetGradient("VERTICAL", color(1, 1, 1, 0), color(1, 1, 1, 1))
eq(c:GetAlpha(), 1, "no SetAlpha: 1")

-- A recoloured status bar fill (no gradient any more) takes SetAlpha again.
local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetStatusBarTexture("x")
local fill = bar:GetStatusBarTexture()
fill:SetGradient("HORIZONTAL", color(1, 1, 1, 1), color(1, 1, 1, 1))
bar:SetStatusBarColor(1, 0, 0)
fill:SetAlpha(0.4)
eq(fill:GetAlpha(), 0.4, "once SetStatusBarColor drops the gradient, SetAlpha works again")

-- Colour objects only.
check(not pcall(a.SetGradient, a, "VERTICAL", 1, 1), "numbers for the colours throw")
local ok, err = pcall(a.SetGradient, a, "VERTICAL", color(1, 1, 1, 1), 0.5)
check(not ok and tostring(err):find("colour objects", 1, true), "naming what it takes: " .. tostring(err))

done("test_gradient")
