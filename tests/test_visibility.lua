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

-- Scripts that show or hide while the walk runs (Codex review on #30).
local p1 = watch(CreateFrame("Frame", nil, UIParent), "p1")
local c1 = watch(CreateFrame("Frame", nil, p1), "c1")
p1:Hide()
seen()
p1:SetScript("OnShow", function(self) log[#log + 1] = "p1+"; self:Hide() end)
p1:Show()
eq(seen(), "p1+ p1-", "an OnShow that hides its own frame: the frame gets OnShow then OnHide")
check(not c1:IsVisible(), "the child never became visible")
p1:SetScript("OnShow", function() log[#log + 1] = "p1+" end)
p1:Show()
seen()
p1:SetScript("OnHide", function() log[#log + 1] = "p1-"; c1:Hide() end)
p1:Hide()
eq(seen(), "p1- c1-", "an OnHide that hides a visible child: the child gets its OnHide once")
p1:SetScript("OnHide", function() log[#log + 1] = "p1-" end)
p1:Show()
eq(seen(), "p1+", "showing the parent again doesn't show the child it hid")
local c2 = watch(CreateFrame("Frame", nil, p1), "c2")
c2:Hide()
p1:Hide()
seen()
p1:SetScript("OnShow", function() log[#log + 1] = "p1+"; c2:Show() end)
p1:Show()
eq(seen(), "p1+ c2+", "an OnShow that shows a hidden child: the child gets one OnShow")
p1:SetScript("OnShow", function() log[#log + 1] = "p1+" end)

-- Reparenting moves the frame between children.
local other = CreateFrame("Frame", nil, UIParent)
glow:SetParent(other)
eq(select("#", art:GetChildren()), 0, "the old parent no longer lists it")
eq((other:GetChildren()), glow, "the new one does")
art:Hide()
eq(seen(), "art-", "the old parent's hide doesn't reach it")
other:Hide()
eq(seen(), "glow-", "the new parent's does")
local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
local mover = watch(CreateFrame("Frame", nil, UIParent), "mover")
mover:SetParent(hiddenParent)
eq(seen(), "", "reparenting fires nothing (not modelled)")
hiddenParent:Show()
eq(seen(), "mover+", "but a later show of the new parent gives it OnShow, as it became visible")
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
