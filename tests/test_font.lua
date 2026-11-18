-- A FontString with no font refuses SetText (WowTestKit #69).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local f = CreateFrame("Button", nil, UIParent)

-- The probe's board: a hotkey made with no template, no font.
local hotkey = f:CreateFontString(nil, "OVERLAY")
local ok, err = pcall(function() hotkey:SetText("1") end)
check(not ok, "SetText on a font string with no font throws")
check(tostring(err):find("FontString:SetText(): Font not set", 1, true), "with the client's message: " .. tostring(err))
check(tostring(err):find("test_font.lua:9:", 1, true), "at the caller's line: " .. tostring(err))
eq(hotkey:GetText(), nil, "and sets no text")
check(not pcall(function() hotkey:SetText("") end), "an empty text throws too")
check(not pcall(function() hotkey:SetText(nil) end), "and nil")
eq(WoW.secretBlocked, 0, "the error isn't counted as a secret touch")

-- Each source of a font is enough.
local a = f:CreateFontString(nil, "OVERLAY")
a:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
check(pcall(function() a:SetText("x") end), "SetFont gives a font")
eq(a:GetText(), "x", "and the text is set")
local b = f:CreateFontString(nil, "OVERLAY")
b:SetFontObject({})
check(pcall(function() b:SetText("x") end), "SetFontObject gives one")
local c = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
eq(c._fontTemplate, "GameFontNormal", "CreateFontString keeps the template")
check(pcall(function() c:SetText("x") end), "and a template gives one")
local named = f:CreateFontString("KitFontNamed", "ARTWORK", "GameFontHighlight")
eq(rawget(_G, "KitFontNamed"), named, "a named one is still a global")
named:SetText("y")
eq(named:GetText(), "y", "and takes its text")

-- SetFormattedText isn't measured: it doesn't throw.
local d = f:CreateFontString(nil, "OVERLAY")
check(pcall(function() d:SetFormattedText("%d", 3) end), "SetFormattedText doesn't throw (unmeasured)")

-- Not font strings: an EditBox (OnTextChanged still runs) and a Button.
local edit = CreateFrame("EditBox", nil, UIParent)
local changed = 0
edit:SetScript("OnTextChanged", function() changed = changed + 1 end)
edit:SetText("abc")
eq(edit:GetText(), "abc", "an EditBox takes text with no font")
eq(changed, 1, "and runs OnTextChanged")
f:SetText("label")
eq(f:GetText(), "label", "a Button's SetText isn't affected")

-- A stub's own font string (WoW.newWidget) is checked the same.
local own = WoW.newWidget("FontString", f)
check(not pcall(function() own:SetText("x") end), "a stub's own font string with no font throws")

done("test_font")
