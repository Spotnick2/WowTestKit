-- A frame's ID: 0 until set, on frames and on secure handles (WowTestKit #41).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

-- A bag window and its item button, as Blizzard's ContainerFrame keeps them.
local bag = CreateFrame("Frame", "KitBag", UIParent)
local slot = CreateFrame("Button", nil, bag)
eq(bag:GetID(), 0, "a frame's ID is 0 until set")
eq(slot:GetID(), 0, "a button's too")
bag:SetID(3)
slot:SetID(12)
eq(slot:GetParent():GetID(), 3, "SetID keeps the bag")
eq(slot:GetID(), 12, "and the slot")
check(WoW.methodsCalled["Button:SetID"] and WoW.methodsCalled["Frame:GetID"], "both recorded")

-- Through a handle (RestrictedFrames.lua:108, :410).
local header = CreateFrame("Frame", "KitIdHeader", UIParent, "SecureHandlerBaseTemplate")
SecureHandlerExecute(header, [[ before = self:GetID(); self:SetID("7"); after = self:GetID() ]])
local env = WoW.secureEnvironment(header)
eq(env.before, 0, "a handle's GetID is the frame's")
eq(env.after, 7, "SetID takes a numeric string")
eq(header:GetID(), 7, "and sets the frame's ID")
SecureHandlerExecute(header, [[ self:SetID("seven") ]])
eq(header:GetID(), 0, "a non-number sets 0")
local button = CreateFrame("Button", "KitIdButton", UIParent, "SecureActionButtonTemplate")
SecureHandlerWrapScript(button, "OnClick", header, [[ self:SetID(owner:GetID() + 4) ]])
WoW.combat = true
WoW.click(button, "LeftButton", true)
eq(button:GetID(), 4, "a snippet sets a protected frame's ID in combat")
eq(#WoW.blocked, 0, "with nothing blocked")
WoW.combat = false

done("test_frame_id")
