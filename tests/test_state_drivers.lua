-- Secure state drivers (WowTestKit #77): RegisterStateDriver /
-- RegisterAttributeDriver and the macro conditions they read
-- (SecureStateDriver.lua, wow-ui-source forever 70959).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

Kit.checkCore()   -- the driver globals and SecureCmdOptionParse are the build's

-- The conditions: clauses, groups, negation, targets.
eq(SecureCmdOptionParse("[combat] in; out"), "out", "out of combat the default clause")
WoW.combat = true
eq(SecureCmdOptionParse("[combat] in; out"), "in", "in combat the first")
eq(SecureCmdOptionParse("[nocombat] a; b"), "b", "no<name> negates")
eq(SecureCmdOptionParse("[nocombat][combat] a; b"), "a", "any group holding is enough")
WoW.combat = false
eq(SecureCmdOptionParse("[nocombat,combat] a; b"), "b", "every condition in a group must hold")
eq(SecureCmdOptionParse("[combat] a"), nil, "no clause holds: nil")
eq(SecureCmdOptionParse("[] a; b"), "a", "an empty group holds")
eq(SecureCmdOptionParse("[combat] a;  spaced out  "), "spaced out", "the value is trimmed")
eq(SecureCmdOptionParse("[nocombat]"), "", "a clause that holds with no value gives an empty string")
local value, target = SecureCmdOptionParse("[@focus,nocombat] heal; [target=pet] x")
check(value == "heal" and target == "focus", "@unit is the clause's target, not a condition")
value, target = SecureCmdOptionParse("[combat] a; [target=pet] x")
check(value == "x" and target == "pet", "and so is target=unit")
local okUnknown, errUnknown = pcall(SecureCmdOptionParse, "[mod:shift] a; b")
check(not okUnknown and tostring(errUnknown):find("WoW.CONDITIONS.mod", 1, true),
    "a condition the core doesn't model is an error naming where to add it")

-- A stub's own condition, with its arguments and target.
local seenArgs, seenTarget
WoW.CONDITIONS.mod = function(args, unit) seenArgs, seenTarget = args, unit; return args and args[2] == "ctrl" end
eq(SecureCmdOptionParse("[mod:shift/ctrl, @player] m; n"), "m", "a stub's condition decides")
check(seenArgs and seenArgs[1] == "shift" and seenArgs[2] == "ctrl" and seenTarget == "player",
    "with its ':a/b' arguments and the group's target")
eq(SecureCmdOptionParse("[nomod:alt] m; n"), "m", "a stub's condition negates too")
WoW.CONDITIONS.mod = nil

-- [group], [party], [raid] read false in combat (porting guide, measured).
WoW.CONDITIONS.group = function() return true end
eq(SecureCmdOptionParse("[group:raid] hide; show"), "hide", "out of combat the stub's group condition decides")
WoW.combat = true
eq(SecureCmdOptionParse("[group:raid] hide; show"), "show", "in combat [group] reads false")
eq(SecureCmdOptionParse("[party] p; q"), "q", "[party] too, stub or not")
eq(SecureCmdOptionParse("[noraid] p; q"), "p", "and its negation holds")
WoW.combat = false
WoW.CONDITIONS.group = nil

-- A visibility driver: resolved at registration, then by the manager.
local bar = CreateFrame("Frame", "KitBar", UIParent)
CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")   -- the bar is protected
local shows, hides = 0, 0
bar:SetScript("OnShow", function() shows = shows + 1 end)
bar:SetScript("OnHide", function() hides = hides + 1 end)
RegisterStateDriver(bar, "visibility", "[combat] show; hide")
check(not bar:IsShown(), "registration resolves at once: out of combat, hide")
eq(bar:GetAttribute("statehidden"), true, "and statehidden is set")
eq(WoW.stateDrivers[bar]["state-visibility"], "[combat] show; hide", "WoW.stateDrivers holds the values")

-- Entering combat: the event wakes the manager, the next frame resolves.
WoW.combat = true
WoW.step(0.02)   -- the first frame since registration (the manager's timer starts at 0)
check(bar:IsShown(), "the manager's first update resolves it")
WoW.combat = false
WoW.step(0.02)
check(bar:IsShown(), "then it waits out its 0.2 s")
WoW.step(0.2)
check(not bar:IsShown(), "and resolves again once 0.2 s have passed")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not bar:IsShown(), "the event alone resolves nothing")
WoW.tick(0.02)
check(bar:IsShown(), "PLAYER_REGEN_DISABLED brings the next frame's update forward (WoW.tick runs it too)")
eq(bar:GetAttribute("statehidden"), nil, "statehidden is cleared")
eq(#WoW.blocked, 0, "the driver shows a protected frame in combat: nothing blocked")
eq(shows, 2, "with its OnShow (each time it showed)")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.step()
check(not bar:IsShown(), "leaving combat: PLAYER_REGEN_ENABLED, then a frame, hides it")
eq(hides, 3, "with its OnHide (each time it hid)")

-- Registering is refused in combat (SecureStateDriverManager is protected).
WoW.combat = true
UnregisterStateDriver(bar, "visibility")
check(WoW.stateDrivers[bar]["state-visibility"] ~= nil, "unregistering in combat does nothing")
check(WoW.blocked[1] and WoW.blocked[1]:find("SecureStateDriverManager", 1, true), "and the refusal is recorded")
local late = CreateFrame("Frame", nil, UIParent)
RegisterStateDriver(late, "visibility", "hide")
check(late:IsShown() and WoW.stateDrivers[late] == nil, "nor does registering")
WoW.combat = false
WoW.blocked = {}
UnregisterStateDriver(bar, "visibility")
eq(WoW.stateDrivers[bar]["state-visibility"], nil, "out of combat it unregisters")
WoW.combat = true
WoW.step(0.2)
check(not bar:IsShown(), "and the bar no longer follows combat")
WoW.combat = false

-- Other attributes: the value, a number, "nil" clears; empty values unregister.
local header = CreateFrame("Frame", "KitStateHeader", UIParent, "SecureHandlerStateTemplate")
RegisterStateDriver(header, "page", "[combat] 2; nil")
eq(header:GetAttribute("state-page"), nil, "\"nil\" clears the attribute")
WoW.combat = true
WoW.step(0.2)
eq(header:GetAttribute("state-page"), 2, "a number string is set as a number")
check(header:IsShown(), "a state other than visibility doesn't show or hide")
RegisterAttributeDriver(header, "label", "[nocombat] calm; busy")
WoW.combat = false   -- the registration above was refused (combat): nothing set
eq(header:GetAttribute("label"), nil, "(registered in combat: refused)")
WoW.blocked = {}
RegisterAttributeDriver(header, "label", "[nocombat] calm; busy")
eq(header:GetAttribute("label"), "calm", "RegisterAttributeDriver sets the attribute itself")
RegisterAttributeDriver(header, "_private", "x")
eq(WoW.stateDrivers[header]._private, nil, "an attribute named _... isn't driven")
RegisterAttributeDriver(header, "label", "")
eq(WoW.stateDrivers[header].label, nil, "empty values unregister")
UnregisterAttributeDriver(header)
eq(WoW.stateDrivers[header], nil, "no attribute: every driver of the frame goes")

-- A reset forgets the drivers and hides the manager.
RegisterStateDriver(bar, "visibility", "show")
WoW.reset()
eq(next(WoW.stateDrivers), nil, "WoW.reset clears the drivers")
eq(WoW.stateDriverTimer, nil, "and the manager's timer")

done("test_state_drivers")
