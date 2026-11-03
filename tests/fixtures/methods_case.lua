-- One Kit.checkMethods case, run by tests/test_methods.lua as its own process.
dofile("kit.lua")
Kit.load({ build = "70532" })

local case = arg[1]
local allow
if case == "missing" then
    CreateFrame("Frame"):NotARealMethod()
elseif case == "wrongtype" then
    CreateFrame("Frame"):CreateTexture():RegisterEvent("PLAYER_LOGIN")
elseif case == "unknowntype" then
    WoW.newWidget("Gizmo"):Show()
elseif case == "subtype" then
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetFromAlpha(0)
elseif case == "noreason" or case == "allowed" then
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetFromAlpha(0)
    allow = { ["Alpha:SetFromAlpha"] = case == "allowed" and "Blizzard_SharedXML uses it on Alpha animations" or "" }
end
Kit.checkMethods({ allow = allow })
done("methods_case " .. tostring(case))
