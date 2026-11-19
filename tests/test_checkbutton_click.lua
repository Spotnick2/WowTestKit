-- A click on a CheckButton toggles its checked state before its handlers
-- run, so OnClick reads the new state (WowTestKit #87).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local log = {}
local box = CreateFrame("CheckButton", nil, UIParent)
box:SetScript("PreClick", function(self) log[#log + 1] = "pre:" .. tostring(self:GetChecked()) end)
box:SetScript("OnClick", function(self) log[#log + 1] = "click:" .. tostring(self:GetChecked()) end)
box:SetScript("PostClick", function(self) log[#log + 1] = "post:" .. tostring(self:GetChecked()) end)
local function seen() local s = table.concat(log, " "); log = {}; return s end

eq(box:GetChecked(), false, "a new check box is unchecked")
WoW.click(box)
eq(seen(), "pre:true click:true post:true", "a click checks it before PreClick and OnClick run")
eq(box:GetChecked(), true, "and it stays checked")
box:Click()
eq(seen(), "pre:false click:false post:false", "Button:Click() unchecks it again")
box:SetChecked(true)
WoW.click(box, "LeftButton", true)
eq(seen(), "pre:false click:false post:false", "a click toggles from a SetChecked state")

box:Disable()
WoW.click(box)
eq(seen(), "", "a disabled check box doesn't click")
eq(box:GetChecked(), false, "and keeps its state")
box:Enable()

local plain = CreateFrame("Button", nil, UIParent)
WoW.click(plain)
eq(plain._checked, nil, "a plain Button has no checked state to toggle")

done("test_checkbutton_click")
