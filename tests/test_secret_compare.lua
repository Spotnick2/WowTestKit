-- Lua's "attempt to compare ... userdata" error counts as a secret touch only
-- while a secret proxy is alive (WowTestKit #47): a secure handle is
-- userdata too, and the message names no operand.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local f = CreateFrame("Frame", nil, UIParent)
local h = WoW.handleOf(f)
check(not issecretvalue(h), "a handle isn't a secret")
check(not pcall(function() return h < 1 end), "comparing a handle with a number throws")
eq(WoW.secretBlocked, 0, "with no secret alive, it isn't counted")

local s = WoW.Secret("UnitPower")
check(not pcall(function() return s > 0 end), "comparing a secret with a number throws")
eq(WoW.secretBlocked, 1, "with a secret alive, it is counted")
WoW.secretBlocked, WoW.secretBlockedFirst = 0, nil

s = nil
collectgarbage("collect")
check(not pcall(function() return 1 > h end), "a handle compared once the secret is gone")
eq(WoW.secretBlocked, 0, "isn't counted")

done("test_secret_compare")
