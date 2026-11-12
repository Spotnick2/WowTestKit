-- SetStatusBarColor colours the fill and drops its gradient (WowTestKit #19,
-- measured on 70450, LibGlass#64).
dofile("kit.lua")
Kit.load({ build = "70532" })

local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetStatusBarColor(0.2, 0.4, 0.6, 0.8)
eq(bar._color[4], 0.8, "with no fill yet, the colour is still recorded (alpha too)")

bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
local fill = bar:GetStatusBarTexture()
fill:SetAlpha(0.3)
fill:SetGradient("HORIZONTAL", {}, {})
fill:SetAlpha(1)
eq(fill:GetAlpha(), 0.3, "a gradient fill ignores SetAlpha (70374)")

bar:SetStatusBarColor(0.67, 0.83, 0.45)
eq(fill._gradient, nil, "a recolour drops the fill's gradient")
local v = fill._vertex
check(v and v[1] == 0.67 and v[2] == 0.83 and v[3] == 0.45, "and sets the fill's vertex colour")
eq(bar._color[1], 0.67, "the bar records the colour")

-- LibGlass' repaint after a recolour: SetAlpha, then its gradient again.
fill:SetAlpha(0.5)
eq(fill:GetAlpha(), 0.5, "after the recolour, the repaint's SetAlpha takes")
fill:SetGradient("HORIZONTAL", {}, {})
bar:SetStatusBarColor(0.67, 0.83, 0.45)
eq(fill._gradient, nil, "the same colour again drops the gradient too (bars 2, 4, 6 in the measurement)")

done("test_statusbar")
