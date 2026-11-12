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
    -- A method the build lacks reads as nil, unless a stub implements it:
    -- then the call is recorded, and checkMethods catches it.
    WoW.Methods.NotARealMethod = function() end
    CreateFrame("Frame"):NotARealMethod()
elseif case == "wrongtype" then
    CreateFrame("Frame"):CreateTexture():RegisterEvent("PLAYER_LOGIN")
elseif case == "unknowntype" then
    WoW.newWidget("Gizmo"):Show()
elseif case == "subtype" then
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetFromAlpha(0)
elseif case == "othersubtype" then
    WoW.Methods.SetScaleFrom = function() end   -- implemented for Scale, called on an Alpha
    CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Alpha"):SetScaleFrom(1, 1)
elseif case == "noreason" or case == "allowedlate" then
    -- Allowed only at the check: it must be implemented to be called at all.
    WoW.Methods.GetMapID = function() return 1 end
    CreateFrame("Frame"):GetMapID()
    allow = { ["Frame:GetMapID"] = case == "allowedlate" and "MapCanvasMixin (Blizzard_MapCanvas)" or "" }
elseif case == "allowed" then
    Kit.allowMethods({ ["Frame:GetMapID"] = "MapCanvasMixin (Blizzard_MapCanvas)" })
    CreateFrame("Frame"):GetMapID()
end
Kit.checkMethods({ allow = allow })
done("methods_case " .. tostring(case))
