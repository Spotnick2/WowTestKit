-- RegisterUnitEvent, and unit events delivered only for the registered units
-- (WowTestKit #17; SimpleFrameAPIDocumentation: units with StrideIndex 1).
dofile("kit.lua")
Kit.load({ build = "70532" })

local got = {}
local function frame(name)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetScript("OnEvent", function(_, e, unit) got[#got + 1] = name .. ":" .. e .. ":" .. tostring(unit) end)
    return f
end
local function seen() local s = table.concat(got, " "); got = {}; return s end

local target = frame("target")
eq(target:RegisterUnitEvent("UNIT_HEALTH", "target"), true, "RegisterUnitEvent returns true")
check(not pcall(target.RegisterUnitEvent, target, "NOT_AN_EVENT", "target"), "an unknown event throws")
check(target:IsEventRegistered("UNIT_HEALTH"), "IsEventRegistered sees a unit event")

local both = frame("both")
both:RegisterUnitEvent("UNIT_HEALTH", "player", "pet")
local all = frame("all")
all:RegisterEvent("UNIT_HEALTH")

WoW.fire("UNIT_HEALTH", "target")
eq(seen(), "target:UNIT_HEALTH:target all:UNIT_HEALTH:target", "a unit event reaches its unit's frame and the plain one")
WoW.fire("UNIT_HEALTH", "pet")
eq(seen(), "both:UNIT_HEALTH:pet all:UNIT_HEALTH:pet", "several units: the second one counts")
WoW.fire("UNIT_HEALTH", "focus")
eq(seen(), "all:UNIT_HEALTH:focus", "another unit reaches only the plain registration")
WoW.fire("UNIT_HEALTH")
eq(seen(), "all:UNIT_HEALTH:nil", "no unit: only the plain registration")

-- Re-registering replaces the units; unregistering clears them.
both:RegisterUnitEvent("UNIT_HEALTH", "focus")
WoW.fire("UNIT_HEALTH", "pet")
eq(seen(), "all:UNIT_HEALTH:pet", "a later RegisterUnitEvent replaces the units")
target:UnregisterEvent("UNIT_HEALTH")
check(not target:IsEventRegistered("UNIT_HEALTH"), "UnregisterEvent clears a unit event")
WoW.fire("UNIT_HEALTH", "target")
eq(seen(), "all:UNIT_HEALTH:target", "and it no longer arrives")
both:UnregisterAllEvents()
WoW.fire("UNIT_HEALTH", "focus")
eq(seen(), "all:UNIT_HEALTH:focus", "UnregisterAllEvents clears unit events too")

-- fireAllRegistered: a unit event once per registered unit, with it as payload.
WoW.reset()
local p = frame("p")
p:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "target")
p:RegisterEvent("PLAYER_LOGIN")
local plain = frame("plain")
plain:RegisterEvent("UNIT_POWER_UPDATE")
local list = WoW.fireAllRegistered()
eq(table.concat(list, ","), "PLAYER_LOGIN,UNIT_POWER_UPDATE", "it returns the events it fired, sorted")
eq(seen(), "p:PLAYER_LOGIN:nil p:UNIT_POWER_UPDATE:player plain:UNIT_POWER_UPDATE:player "
    .. "p:UNIT_POWER_UPDATE:target plain:UNIT_POWER_UPDATE:target",
    "a plain event once with no payload, a unit event once per unit (sorted)")

done("test_unit_events")
