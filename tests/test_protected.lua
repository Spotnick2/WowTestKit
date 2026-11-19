-- A protected frame in combat refuses WoW.PROTECTED's methods and records
-- each refusal in WoW.blocked (WowTestKit #12).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local b = CreateFrame("Button", "KitSecure", UIParent, "KitSecureTemplate")
b:SetSize(10, 10)
b:SetAttribute("type", "macro")
b:EnableMouse(true)
local plain = CreateFrame("Frame", nil, UIParent)

WoW.combat = true
local calls = {
    { "SetAttribute", "type", "item" },
    { "SetWidth", 20 }, { "SetHeight", 30 }, { "SetSize", 40, 50 },
    { "StartMoving" }, { "StopMovingOrSizing" }, { "SetClampedToScreen", false },
    { "RegisterForClicks", "AnyDown" },
    { "SetShown", false }, { "SetPoint", "CENTER" },
    -- LibGroupBuffsProbe's combat sweep, 70959 (#83).
    { "SetScale", 2 }, { "SetFrameStrata", "HIGH" }, { "SetFrameLevel", 9 },
    { "EnableMouse", false },
}
for i, c in ipairs(calls) do
    b[c[1]](b, select(2, unpack(c)))
    eq(WoW.blocked[i], "KitSecure:" .. c[1], c[1] .. " is refused and recorded")
end
eq(#WoW.blocked, #calls, "one record per refused call")
eq(b:GetAttribute("type"), "macro", "the refused SetAttribute changed nothing")
eq(b:GetWidth(), 10, "the refused SetWidth changed nothing")
eq(b:GetHeight(), 10, "nor SetHeight / SetSize")
check(b:IsShown(), "the refused SetShown(false) left it shown")
check(b:GetFrameStrata() ~= "HIGH", "the refused SetFrameStrata changed nothing")
check(b:GetFrameLevel() ~= 9, "nor SetFrameLevel")
check(b:IsMouseEnabled(), "nor EnableMouse(false)")
check(WoW.methodsCalled["Button:SetAttribute"], "a refused call is still recorded for the methods check")

-- A consumer's replacement keeps the refusal.
local ran, coreSetSize = false, WoW.Methods.SetSize
WoW.Methods.SetSize = function() ran = true end
b:SetSize(1, 1)
check(not ran, "a consumer's SetSize doesn't run on a refused call")
WoW.Methods.SetSize = coreSetSize

-- A stub calling the core's SetAttribute directly is refused too.
local n = #WoW.blocked
WoW.Methods.SetAttribute(b, "type", "spell")
eq(b:GetAttribute("type"), "macro", "a direct Methods.SetAttribute is refused in combat")
eq(WoW.blocked[n + 1], "KitSecure:SetAttribute", "and recorded")

-- Measured as allowed on 70959 (#83): SetAlpha on the protected frame, and
-- its regions' writes.
local n2 = #WoW.blocked
b:SetAlpha(0.5)
eq(b:GetAlpha(), 0.5, "SetAlpha on a protected frame goes through in combat")
local tex = b:CreateTexture()
local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tex:Hide(); fs:Hide()
check(not tex:IsShown() and not fs:IsShown(), "a protected frame's regions hide in combat")
tex:Show(); fs:SetShown(true)
check(tex:IsShown() and fs:IsShown(), "and show")
tex:SetTexture("Interface\\Buttons\\WHITE8X8")
eq(#WoW.blocked, n2, "with nothing recorded")

-- A consumer extends the list.
WoW.PROTECTED.SetParent = true
b:SetParent(UIParent)
eq(WoW.blocked[#WoW.blocked], "KitSecure:SetParent", "a consumer can add a protected method")
WoW.PROTECTED.SetParent = nil

-- Not protected, or not in combat: everything goes through.
local before = #WoW.blocked
plain:SetSize(5, 6)
plain:SetAttribute("k", 1)
eq(plain:GetWidth(), 5, "an unprotected frame resizes in combat")
eq(plain:GetAttribute("k"), 1, "and takes attributes")
eq(#WoW.blocked, before, "with nothing recorded")
WoW.combat = false
b:SetAttribute("type", "item")
b:SetSize(40, 50)
eq(b:GetAttribute("type"), "item", "out of combat a protected frame takes attributes")
eq(b:GetWidth(), 40, "and resizes")

-- A frame that parents a protected frame is protected too (#42; porting
-- guide, measured on 69913).
local grand = CreateFrame("Frame", "KitGrand", UIParent)
local parent = CreateFrame("Frame", "KitParent", grand)
local secureChild = CreateFrame("Button", "KitChild", parent, "KitSecureTemplate")
local hid = 0
secureChild:SetScript("OnHide", function() hid = hid + 1 end)
local imp, exp = parent:IsProtected()
check(imp and not exp, "IsProtected: the parent is protected, not explicitly")
imp, exp = secureChild:IsProtected()
check(imp and exp, "the secure frame: both")
local lone = CreateFrame("Frame", nil, UIParent)
check(not lone:IsProtected(), "a frame with no protected descendant isn't")
WoW.combat = true
WoW.blocked = {}
parent:Hide()
check(parent:IsShown(), "the parent of a secure frame refuses to hide in combat")
check(secureChild:IsVisible() and hid == 0, "so the secure child stays visible, with no OnHide")
eq(WoW.blocked[1], "KitParent:Hide", "the refusal is recorded")
grand:SetPoint("TOP")
eq(WoW.blocked[2], "KitGrand:SetPoint", "a grandparent too")
lone:Hide()
check(not lone:IsShown(), "a frame with no protected descendant still hides in combat")
WoW.combat = false
parent:Hide()
check(not parent:IsShown() and hid == 1, "out of combat it hides, and the child gets its OnHide")

done("test_protected")
