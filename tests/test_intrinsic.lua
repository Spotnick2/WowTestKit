-- CreateFrame of an XML intrinsic makes a widget of its base type
-- (WowTestKit #85).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- Every intrinsic maps to a widget type the build has, and none is a type of its own.
local types = {}
for pair in pairs(Kit.data("widgetMethods")) do types[pair:match("^([%w_]+):")] = true end
for name, base in pairs(WoW.INTRINSIC) do
    check(types[base] and not types[name], name .. " -> " .. base .. ": a build type, and not one itself")
end
eq(WoW.INTRINSIC.EventFrame, "Frame", "EventFrame is a Frame (EventFrame.xml:3)")
eq(WoW.INTRINSIC.DropdownButton, "Button", "DropdownButton is a Button (DropdownButton.xml:3)")

-- The base type, the name asked for, and the template.
local built
WoW.templates.KitDropTemplate = function(w) built = w end
local d = CreateFrame("DropdownButton", "KitDrop", UIParent, "KitDropTemplate")
eq(d._type, "Button", "a DropdownButton is a Button")
eq(d._intrinsic, "DropdownButton", "which keeps the name asked for")
eq(built, d, "a template given to CreateFrame still applies")
eq(rawget(_G, "KitDrop"), d, "a named one is a global")
eq(UIParent._children[#UIParent._children], d, "and its parent's child")
eq(d:GetObjectType(), "Button", "GetObjectType returns the base type (unmeasured on the client)")
check(d:IsObjectType("Button") and d:IsObjectType("Frame"), "IsObjectType follows the base type")

-- Its methods are the base type's.
d:SetPoint("CENTER")
d:SetSize(10, 10)
check(WoW.methodsCalled["Button:SetPoint"] and WoW.methodsCalled["Button:SetSize"], "the calls are recorded on Button")
check(not WoW.methodsCalled["DropdownButton:SetPoint"], "not on the intrinsic's name")
eq(d.SetupMenu, nil, "a mixin method reads nil until allowed")
Kit.allowMethods({ ["Button:SetupMenu"] = "DropdownButtonMixin (Blizzard_Menu/DropdownButton.lua:237)" })
eq(type(d.SetupMenu), "function", "allowed on the base type, it reads as a method")
d:SetupMenu(function() end)
local ev = CreateFrame("EventFrame", nil, UIParent)
eq(ev._type, "Frame", "an EventFrame is a Frame")
eq(ev.SetNormalFontObject, nil, "with a Frame's methods only (feature detection as on the client)")
ev:SetPoint("TOP")
check(Kit.checkMethods() > 0, "Kit.checkMethods passes every call made on them")

-- A plain type, and a type that is one on the build, are unchanged.
local b = CreateFrame("Button")
check(b._type == "Button" and b._intrinsic == nil, "a plain Button has no _intrinsic")
eq(CreateFrame("ScrollingMessageFrame")._type, "ScrollingMessageFrame",
    "ScrollingMessageFrame stays a type of its own (the build lists it)")

-- A consumer adds its own; the base type's set-up applies.
WoW.INTRINSIC.KitBar = "StatusBar"
local bar = CreateFrame("KitBar")
check(bar._type == "StatusBar" and bar._intrinsic == "KitBar", "a consumer's intrinsic maps too")
eq(bar:GetValue(), 0, "with the base type's set-up (a status bar's value)")

done("test_intrinsic")
