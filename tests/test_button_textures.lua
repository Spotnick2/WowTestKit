-- A button's state textures: Set/Get Normal, Pushed, Highlight, Disabled,
-- and a CheckButton's Checked (WowTestKit #70).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local b = CreateFrame("Button", nil, UIParent)
eq(b:GetPushedTexture(), nil, "no pushed texture until one is set")
eq(b:GetHighlightTexture(), nil, "nor a highlight")

-- A file: set on the button's own texture, made on first use.
b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
local pushed = b:GetPushedTexture()
check(pushed ~= nil, "SetPushedTexture(file) makes the pushed texture")
eq(pushed:GetObjectType(), "Texture", "a Texture")
eq(pushed:GetParent(), b, "the button's")
eq(pushed._file, "Interface\\Buttons\\UI-Quickslot-Depress", "with the file on it")
b:SetPushedTexture(130838)
eq(b:GetPushedTexture(), pushed, "a second file goes on the same texture")
eq(pushed._file, 130838, "a file ID too")

-- Apotheca's case: the skin sets its rim, turning it off restores the file.
local rim = b:CreateTexture(nil, "OVERLAY")
rim:SetAtlas("glass-rim")
b:SetPushedTexture(rim)
eq(b:GetPushedTexture(), rim, "given a Texture, the button takes that texture")
eq(rim._atlas, "glass-rim", "and leaves it as it was")
b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
eq(b:GetPushedTexture(), rim, "a file afterwards goes on the texture it has")
eq(rim._file, "Interface\\Buttons\\UI-Quickslot-Depress", "as SetTexture would set it")
eq(rim._atlas, nil, "one source at a time")

-- The highlight takes a blend mode.
b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
local hl = b:GetHighlightTexture()
eq(hl._file, "Interface\\Buttons\\ButtonHilight-Square", "SetHighlightTexture sets the file")
eq(hl._blend, "ADD", "and the blend mode")
b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
eq(hl._blend, "ADD", "a later call without a blend leaves it")
local soft = b:CreateTexture()
b:SetHighlightTexture(soft, "BLEND")
eq(b:GetHighlightTexture(), soft, "a Texture is taken as the highlight")
eq(soft._blend, "BLEND", "with the blend given")
b:SetPushedTexture("x", "ADD")
eq(b:GetPushedTexture()._blend, nil, "only the highlight takes a blend")

-- nil: no texture made; an existing one loses its file.
local c = CreateFrame("Button", nil, UIParent)
c:SetNormalTexture(nil)
eq(c:GetNormalTexture(), nil, "a nil asset makes no texture")
c:SetNormalTexture("n")
c:SetNormalTexture(nil)
check(c:GetNormalTexture() ~= nil and c:GetNormalTexture()._file == nil, "and clears the file on one it has")
c:SetDisabledTexture("d")
eq(c:GetDisabledTexture()._file, "d", "the disabled texture")
check(c:GetNormalTexture() ~= c:GetDisabledTexture(), "each state has its own texture")

-- A CheckButton's checked texture; a Button has none on the build.
local cb = CreateFrame("CheckButton", nil, UIParent)
cb:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
eq(cb:GetCheckedTexture()._file, "Interface\\Buttons\\CheckButtonHilight", "a CheckButton's checked texture")
cb:SetPushedTexture("p")
eq(cb:GetPushedTexture()._file, "p", "and its Button states")
check(WoW.methodsCalled["Button:SetPushedTexture"] and WoW.methodsCalled["CheckButton:SetCheckedTexture"],
    "the calls are recorded")
Kit.checkMethods({ label = "state textures" })

done("test_button_textures")
