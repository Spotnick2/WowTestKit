-- One Kit.checkMethods case, run by tests/test_methods.lua as its own process.
dofile("kit.lua")
Kit.load({ build = "70532" })

local case = arg[1]
local allow
if case == "stubcalls" then
    -- A stub building its prebuilt frames records calls; Kit.strict forgets them.
    CreateFrame("Frame"):SetSize(1, 1)
    Kit.strict({})
elseif case == "missing" then
    CreateFrame("Frame"):NotARealMethod()
elseif case == "wrongtype" then
    CreateFrame("Frame"):CreateTexture():RegisterEvent("PLAYER_LOGIN")
elseif case == "unknowntype" then
    WoW.newWidget("Gizmo"):Show()
elseif case == "subtype" then
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetFromAlpha(0)
elseif case == "othersubtype" then
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetScaleFrom(1, 1)
elseif case == "noreason" or case == "allowed" then
    CreateFrame("Frame"):GetMapID()
    allow = { ["Frame:GetMapID"] = case == "allowed" and "MapCanvasMixin (Blizzard_MapCanvas)" or "" }
end
Kit.checkMethods({ allow = allow })
done("methods_case " .. tostring(case))
