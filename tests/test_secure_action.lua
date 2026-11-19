-- The secure action's modified attributes and press-and-hold release
-- (WowTestKit #88; SecureTemplates.lua, wow-ui-source forever 70959).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local function last() return WoW.secureActions[#WoW.secureActions] end
local function count() return #WoW.secureActions end

-- Shatter's pattern: armed in PreClick for a left click, cleared in PostClick.
local nextBtn = CreateFrame("Button", "KitNext", UIParent, "SecureActionButtonTemplate")
nextBtn:SetScript("PreClick", function(self)
    self:SetAttribute("*type1", "spell")
    self:SetAttribute("*spell1", 13262)
    self:SetAttribute("*target-bag1", 0)
    self:SetAttribute("*target-slot1", 3)
end)
nextBtn:SetScript("PostClick", function(self)
    for _, k in ipairs({ "*type1", "*spell1", "*target-bag1", "*target-slot1" }) do self:SetAttribute(k, nil) end
end)
WoW.click(nextBtn, "LeftButton", true)
eq(count(), 1, "a left click acts on *type1")
local a = last()
check(a.type == "spell" and a.spell == 13262 and a.targetBag == 0 and a.targetSlot == 3 and a.mouse == "LeftButton",
    "and records the resolved *spell1, *target-bag1, *target-slot1")
WoW.click(nextBtn, "LeftButton", false)
WoW.click(nextBtn, "RightButton", true)
WoW.click(nextBtn, "MiddleButton", true)
eq(count(), 1, "the up edge, a right and a middle click do nothing (no type for buttons 2 and 3)")

-- The lookup order: prefix..name..suffix, *name..suffix, prefix..name*, *name*, name.
local b = CreateFrame("Button", "KitMods", UIParent, "SecureActionButtonTemplate")
b:SetAttribute("type", "macro")
b:SetAttribute("*type*", "item")
b:SetAttribute("type*", "toy")
b:SetAttribute("*type1", "spell")
b:SetAttribute("type1", "target")
WoW.click(b, "LeftButton", true)
eq(last().type, "target", "no modifier: type1 before *type1")
b:SetAttribute("type1", nil)
WoW.click(b, "LeftButton", true)
eq(last().type, "spell", "then *type1")
WoW.click(b, "RightButton", true)
eq(last().type, "toy", "then type* (any button)")
b:SetAttribute("type*", nil)
WoW.click(b, "RightButton", true)
eq(last().type, "item", "then *type*")
b:SetAttribute("*type*", nil)
WoW.click(b, "RightButton", true)
eq(last().type, "macro", "then the plain attribute")

-- Modifiers, from the stub's own IsShiftKeyDown...
local held = {}
IsShiftKeyDown = function() return held.shift end
IsControlKeyDown = function() return held.ctrl end
IsAltKeyDown = function() return held.alt end
b:SetAttribute("shift-type1", "focus")
b:SetAttribute("alt-ctrl-shift-type2", "assist")
held.shift = true
WoW.click(b, "LeftButton", true)
eq(last().type, "focus", "shift held: shift-type1 before *type1")
held.alt, held.ctrl = true, true
WoW.click(b, "RightButton", true)
eq(last().type, "assist", "the prefix is alt-ctrl-shift-, in that order")
WoW.click(b, "LeftButton", true)
eq(last().type, "spell", "another modifier set falls back to *type1")
held = {}
b:SetAttribute("shift-type1", "")
held.shift = true
local n = count()
WoW.click(b, "LeftButton", true)
eq(count(), n, "ATTRIBUTE_NOOP (\"\") excludes a combination: nothing happens")
held = {}
IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown = nil, nil, nil
WoW.click(b, "LeftButton", true)
eq(last().type, "spell", "without the stub's modifier functions, nothing is held")
b:SetAttribute("modifiers", "SELFCAST:self")
check(not pcall(WoW.click, b, "LeftButton", true), "the modifiers attribute isn't modelled, and says so")
b:SetAttribute("modifiers", nil)

-- Other buttons' suffixes, the parent, downbutton.
local c = CreateFrame("Button", "KitButtons", UIParent, "SecureActionButtonTemplate")
c:SetAttribute("type4", "spell")
c:SetAttribute("spell4", "Renew")
c:SetAttribute("type-Wheel", "macro")
WoW.click(c, "Button4", true)
check(last().type == "spell" and last().spell == "Renew", "Button4's suffix is 4")
WoW.click(c, "Wheel", true)
eq(last().type, "macro", "another button's suffix is -<button>")
local bar = CreateFrame("Frame", "KitParentBar", UIParent)
bar:SetAttribute("*type1", "item")
bar:SetAttribute("*item1", "Hearthstone")
local child = CreateFrame("Button", "KitChild", bar, "SecureActionButtonTemplate")
n = count()
WoW.click(child, "LeftButton", true)
eq(count(), n, "a button reads its own attributes")
child:SetAttribute("useparent*", true)
WoW.click(child, "LeftButton", true)
check(last().type == "item" and last().item == "Hearthstone", "useparent* reads the parent's")
child:SetAttribute("useparent*", nil)
child:SetAttribute("useparent-type", true)
WoW.click(child, "LeftButton", true)
check(last().type == "item" and last().item == nil, "useparent-type reads only the type there")
local d = CreateFrame("Button", "KitDown", UIParent, "SecureActionButtonTemplate")
d:SetAttribute("type1", "spell")
d:SetAttribute("type-heal", "macro")
d:SetAttribute("downbutton1", "heal")
WoW.click(d, "LeftButton", true)
eq(last().type, "macro", "on the down edge, downbutton remaps the button")
check(last().mouse == "LeftButton", "mouse is still the button clicked")
WoW.useKeyDown = false
WoW.click(d, "LeftButton", false)
eq(last().type, "spell", "not on the up edge")
WoW.useKeyDown = true

-- Press and hold: typerelease on the up edge, under ActionButtonUseKeyHeldSpell.
local h = CreateFrame("Button", "KitHold", UIParent, "SecureActionButtonTemplate")
h:SetAttribute("type", "spell")
h:SetAttribute("spell", "Fireball")
eq(WoW.useKeyHeldSpell, false, "the CVar is off by default")
WoW.useKeyHeldSpell = true
n = count()
WoW.click(h, "LeftButton", true)
eq(h:GetScript("OnClick")(h, "LeftButton", false), true, "under the CVar the up edge is the release: taken")
eq(count(), n + 1, "press and hold with no typerelease casts once")
h:SetAttribute("*typerelease1", "spell")
WoW.click(h, "LeftButton", false)
eq(count(), n + 2, "a typerelease (modified too) acts on the up edge")
check(last().release == true and last().type == "spell", "recorded as a release")
WoW.useKeyHeldSpell = false
WoW.click(h, "LeftButton", false)
eq(count(), n + 2, "without the CVar the up edge does nothing")
WoW.useKeyDown, WoW.useKeyHeldSpell = false, true
WoW.click(h, "LeftButton", false)
check(count() == n + 3 and not last().release, "acting on the up edge, it's a click there, not a release")
WoW.useKeyHeldSpell = false
h:SetAttribute("pressAndHoldAction", true)
WoW.click(h, "LeftButton", true)
eq(count(), n + 4, "pressAndHoldAction: the down edge acts, whatever ActionButtonUseKeyDown says")
WoW.click(h, "LeftButton", false)
check(count() == n + 5 and last().release, "and the up edge releases without the CVar")
WoW.useKeyDown = true

WoW.useKeyHeldSpell = true
WoW.reset()
eq(WoW.useKeyHeldSpell, false, "WoW.reset turns the CVar off")

done("test_secure_action")
