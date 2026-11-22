-- Run in a fresh Lua process for each committed client build.
dofile("kit.lua")
Kit.load({ build = assert(arg[1]), api = Kit.API })
Kit.checkCore()
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
local calls = 0
frame:SetScript("OnEvent", function() calls = calls + 1 end)
frame:Show()
WoW.fire("PLAYER_LOGIN")
eq(calls, 1, "dispatches the registered event")
Kit.checkMethods()
done("build " .. Kit.BUILD)
