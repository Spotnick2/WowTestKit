-- RegisterEvent refuses the events the client refuses (WowTestKit #79;
-- porting guide: registering COMBAT_LOG_EVENT_UNFILTERED returns false and
-- raises ADDON_ACTION_FORBIDDEN).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

check(WoW.KNOWN_EVENTS.COMBAT_LOG_EVENT_UNFILTERED, "the build lists the event")
local f = CreateFrame("Frame", "KitCombatLog", UIParent)
local got = 0
f:SetScript("OnEvent", function() got = got + 1 end)
eq(f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED"), false, "RegisterEvent refuses it with false")
eq(f:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), false, "and registers nothing")
WoW.fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(got, 0, "so it never arrives")
eq(table.concat(WoW.forbidden, ","), "KitCombatLog:RegisterEvent:COMBAT_LOG_EVENT_UNFILTERED", "the refusal is recorded")
eq(#WoW.blocked, 0, "as forbidden, not blocked")
eq(f:RegisterEvent("UNIT_DIED"), true, "another event still registers")
eq(#WoW.forbidden, 1, "without a record")
eq(table.concat(WoW.fireAllRegistered(), ","), "UNIT_DIED", "fireAllRegistered doesn't fire the refused one")
check(not pcall(f.RegisterEvent, f, "NOT_AN_EVENT"), "an unknown event still throws")

-- A consumer adds an event it measured; an unnamed frame records its type.
WoW.REFUSED_EVENTS.PLAYER_LOGIN = true
local anon = CreateFrame("Frame")
eq(anon:RegisterEvent("PLAYER_LOGIN"), false, "a consumer's refused event is refused")
eq(WoW.forbidden[2], "Frame:RegisterEvent:PLAYER_LOGIN", "an unnamed frame is recorded by its type")
WoW.REFUSED_EVENTS.PLAYER_LOGIN = nil

WoW.reset()
eq(#WoW.forbidden, 0, "WoW.reset clears the record")

done("test_refused_events")
