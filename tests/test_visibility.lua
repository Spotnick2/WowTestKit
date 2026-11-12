-- OnShow / OnHide reach shown descendants when a parent's visibility changes,
-- and fire only on a change (WowTestKit #21).
dofile("kit.lua")
Kit.load({ build = "70532" })

local log = {}
local function watch(f, name)
    f:SetScript("OnShow", function() log[#log + 1] = name .. "+" end)
    f:SetScript("OnHide", function() log[#log + 1] = name .. "-" end)
    return f
end
local function seen() local s = table.concat(log, " "); log = {}; return s end

local ring = watch(CreateFrame("Frame", nil, UIParent), "ring")
local art = watch(CreateFrame("Frame", nil, ring), "art")
local glow = watch(CreateFrame("Frame", nil, art), "glow")
local off = watch(CreateFrame("Frame", nil, ring), "off")
off:Hide()
seen()

ring:Hide()
eq(seen(), "ring- art- glow-", "hiding a parent runs OnHide on it and its shown descendants, parents first")
ring:Show()
eq(seen(), "ring+ art+ glow+", "showing it runs their OnShow; a hidden child gets none")
ring:Show()
eq(seen(), "", "Show on a shown frame fires nothing")
off:Hide()
eq(seen(), "", "Hide on a hidden frame fires nothing")

ring:Hide()
seen()
art:Hide()
eq(seen(), "", "hiding a frame that isn't visible fires nothing")
art:Show()
eq(seen(), "", "a frame shown under a hidden ancestor gets no OnShow yet")
check(art:IsShown() and not art:IsVisible(), "it's shown but not visible")
ring:Show()
eq(seen(), "ring+ art+ glow+", "it gets OnShow when the ancestor shows")

ring:SetShown(false)
eq(seen(), "ring- art- glow-", "SetShown goes the same way")
ring:SetShown(true)
seen()

-- Reparenting moves the frame between children.
local other = CreateFrame("Frame", nil, UIParent)
glow:SetParent(other)
eq(select("#", art:GetChildren()), 0, "the old parent no longer lists it")
eq((other:GetChildren()), glow, "the new one does")
art:Hide()
eq(seen(), "art-", "the old parent's hide doesn't reach it")
other:Hide()
eq(seen(), "glow-", "the new parent's does")
local tex = art:CreateTexture()
tex:SetParent(other)
eq(select("#", art:GetRegions()), 0, "a texture leaves its old parent's regions")
eq((other:GetRegions()), tex, "and joins the new one's")

-- WoW.setShown: the same, without the combat refusal (secure code's path).
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local secure = watch(CreateFrame("Frame", nil, UIParent, "KitSecureTemplate"), "secure")
local child = watch(CreateFrame("Frame", nil, secure), "child")
WoW.combat = true
secure:Hide()
eq(seen(), "", "Hide on a protected frame in combat is refused, nothing fires")
WoW.setShown(secure, false)
eq(seen(), "secure- child-", "WoW.setShown hides it anyway, with the scripts")
check(not secure:IsShown(), "and it's hidden")
WoW.combat = false

done("test_visibility")
