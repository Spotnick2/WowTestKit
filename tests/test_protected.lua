-- A protected frame in combat refuses WoW.PROTECTED's methods and records
-- each refusal in WoW.blocked (WowTestKit #12).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local b = CreateFrame("Button", "KitSecure", UIParent, "KitSecureTemplate")
b:SetSize(10, 10)
b:SetAttribute("type", "macro")
local plain = CreateFrame("Frame", nil, UIParent)

WoW.combat = true
local calls = {
    { "SetAttribute", "type", "item" },
    { "SetWidth", 20 }, { "SetHeight", 30 }, { "SetSize", 40, 50 },
    { "StartMoving" }, { "StopMovingOrSizing" }, { "SetClampedToScreen", false },
    { "RegisterForClicks", "AnyDown" },
    { "SetShown", false }, { "SetPoint", "CENTER" },
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

-- A consumer extends the list.
WoW.PROTECTED.SetScale = true
b:SetScale(2)
eq(WoW.blocked[#WoW.blocked], "KitSecure:SetScale", "a consumer can add a protected method")
WoW.PROTECTED.SetScale = nil

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

done("test_protected")
