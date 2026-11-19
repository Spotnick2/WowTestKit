-- A hook on every widget call: WoW.onMethodCall (WowTestKit #81).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

eq(#WoW.onMethodCall, 0, "the list starts empty")

local f = CreateFrame("Frame", "KitHooked", UIParent)
local seen = {}
table.insert(WoW.onMethodCall, function(w, k, ...)
    seen[#seen + 1] = { w = w, k = k, n = select("#", ...), args = { ... },
                        logged = (w._log[#w._log] or {})[1] == k, recorded = WoW.methodsCalled[w._type .. ":" .. k] == true }
end)

f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 2, nil)
eq(#seen, 1, "a call runs the hook")
local c = seen[1]
eq(c.w, f, "with the widget")
eq(c.k, "SetPoint", "the method's name")
eq(c.n, 5, "and every argument, a trailing nil counted")
check(c.args[1] == "TOPLEFT" and c.args[2] == UIParent and c.args[4] == 2, "in order")
check(c.logged, "after the call is logged")
check(c.recorded, "and recorded")
f:GetWidth()
eq(seen[2].k, "GetWidth", "a getter runs it too")
f:SetClampRectInsets(1, 2, 3, 4)   -- on the build, no implementation
eq(seen[3].k, "SetClampRectInsets", "and a method with no implementation")
local W = getmetatable(f).__index
W.SetAlpha(f, 0.5)
eq(seen[4].k, "SetAlpha", "and a call through the method table")

-- What a stub function does inside a method isn't another call.
local n = #seen
f:SetShown(false)
eq(#seen, n + 1, "SetShown runs it once, not for Hide too")
WoW.Methods.Show(f)
eq(#seen, n + 1, "a direct Methods call doesn't run it")

-- Several hooks run in the order added; what they return is ignored.
local order = {}
WoW.onMethodCall = {
    function() order[#order + 1] = "a"; return false end,
    function() order[#order + 1] = "b" end,
}
f:SetSize(7, 8)
eq(table.concat(order, ","), "a,b", "each hook runs, in order")
eq(f:GetWidth(), 7, "and a hook returning false doesn't stop the call")

-- Before the combat refusal: a refused call is seen, with the state at the call.
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local parent = CreateFrame("Frame", "KitHookParent", UIParent)
CreateFrame("Button", "KitHookSecure", parent, "KitSecureTemplate")
local at
WoW.onMethodCall = { function(w, k)
    at = { combat = WoW.combat, protected = WoW.isProtected(w), blocked = #WoW.blocked }
end }
WoW.combat = true
WoW.blocked = {}
parent:Hide()
eq(#WoW.blocked, 1, "the call is refused")
check(at and at.combat and at.protected, "the hook saw combat and the protected frame")
eq(at.blocked, 0, "before the refusal was recorded")
WoW.combat = false

-- An error a hook raises fails the call.
WoW.onMethodCall = { function(_, k) if k == "SetHeight" then error("kit: hook refused " .. k) end end }
local ok, err = WoW.rawpcall(f.SetHeight, f, 3)
check(not ok and tostring(err):find("kit: hook refused SetHeight", 1, true), "an error in a hook fails the call")
eq(f:GetHeight(), 8, "and nothing ran")

-- LibGroupBuffs' rule: in combat, no state write at all to a protected
-- frame, refused or not (WoW.combatTouches in its stub).
WoW.combatTouches = {}
local WRITES = { "^Set", "^Show$", "^Hide$", "^EnableMouse$", "^Raise$", "^Lower$", "^Start", "^Stop", "^Clear" }
WoW.onMethodCall = { function(w, k)
    if not WoW.combat or k == "SetScript" or k == "HookScript" or not WoW.isProtected(w) then return end
    for _, p in ipairs(WRITES) do
        if k:match(p) then table.insert(WoW.combatTouches, (w._name or w._type) .. ":" .. k); return end
    end
end }
WoW.combat = true
parent:SetAlpha(0.5)                       -- allowed by the client (WowTestKit #83), still a touch
parent:SetScript("OnShow", function() end)
parent:GetWidth()
f:SetAlpha(1)                              -- not protected
WoW.combat = false
parent:SetAlpha(1)                         -- out of combat
eq(table.concat(WoW.combatTouches, ","), "KitHookParent:SetAlpha", "a combatTouches recorder built on it")

-- WoW.reset keeps the hooks, with or without keepFrames.
local hits = 0
WoW.onMethodCall = { function() hits = hits + 1 end }
WoW.reset()
CreateFrame("Frame"):Show()
eq(hits, 1, "WoW.reset keeps the hooks")
WoW.reset({ keepFrames = true })
f:Show()
eq(hits, 2, "and so does a state-only reset")

-- A fresh client starts with none.
Kit.freshClient()
eq(#WoW.onMethodCall, 0, "a fresh client's list is empty")
CreateFrame("Frame"):Show()
eq(hits, 2, "and the old client's hook no longer runs")

done("test_method_hook")
