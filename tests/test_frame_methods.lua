-- Widget methods consumers had in their own stubs: GetSize (WowTestKit #78),
-- and scale, drag state, clicks, scroll frames, edit box focus, tooltip
-- lines, GetTexture, GetMinMaxValues and string metrics (WowTestKit #89).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- GetSize reads what SetSize, SetWidth and SetHeight set.
local f = CreateFrame("Frame", nil, UIParent)
local w, h = f:GetSize()
check(w == 0 and h == 0, "GetSize is 0, 0 before a size is set")
f:SetSize(120, 40)
w, h = f:GetSize()
check(w == 120 and h == 40, "GetSize returns the width and height SetSize set (" .. tostring(w) .. ", " .. tostring(h) .. ")")
f:SetWidth(75)
f:SetHeight(30)
w, h = f:GetSize()
check(w == 75 and h == 30, "and SetWidth / SetHeight's")
eq(select("#", f:GetSize()), 2, "two values")
local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fs:SetSize(50, 12)
w, h = fs:GetSize()
check(w == 50 and h == 12, "a region's too")
check(WoW.methodsCalled["Frame:GetSize"], "the call is recorded")

-- GetNumPoints counts the anchors GetPoint reads (#89).
local a = CreateFrame("Frame", nil, UIParent)
eq(a:GetNumPoints(), 0, "no anchors on a new frame")
a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 1, 2)
a:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -1, -2)
eq(a:GetNumPoints(), 2, "one per anchor set")
a:ClearAllPoints()
eq(a:GetNumPoints(), 0, "none after ClearAllPoints")

-- The scale: 1 until set, and the effective scale is the chain's product.
local top = CreateFrame("Frame", nil, UIParent)
local mid = CreateFrame("Frame", nil, top)
local leaf = CreateFrame("Frame", nil, mid)
local tex = mid:CreateTexture()
eq(top:GetScale(), 1, "GetScale is 1 until set")
eq(tex:GetScale(), 1, "a region's too")
top:SetScale(2)
eq(top:GetScale(), 2, "GetScale reads what SetScale set")
eq(mid:GetScale(), 1, "a child's own scale stays 1")
eq(leaf:GetEffectiveScale(), 2, "the effective scale takes the parent's")
mid:SetScale(1.5)
eq(leaf:GetEffectiveScale(), 3, "every scale up the chain multiplies in")
eq(tex:GetEffectiveScale(), 3, "a region's follows its parent's")
leaf:SetScale(0.5)
eq(leaf:GetEffectiveScale(), 1.5, "the widget's own included")
UIParent:SetScale(0.5)
eq(top:GetEffectiveScale(), 1, "UIParent's too")
UIParent._scale = nil
leaf._escale = 0.25
eq(leaf:GetEffectiveScale(), 0.25, "a test's _escale wins over the chain")
leaf._escale = nil
eq(CreateFrame("Frame", nil, UIParent):GetEffectiveScale(), 1, "1 while nothing is scaled")

-- The drag state.
local win = CreateFrame("Frame", "KitWindow", UIParent)
check(not win:IsMovable(), "a frame isn't movable until set")
win:SetMovable(true)
check(win:IsMovable(), "SetMovable(true) makes it movable")
win:StartMoving()
eq(win._moving, true, "StartMoving: moving")
win:StopMovingOrSizing()
eq(win._moving, false, "StopMovingOrSizing stops it")
win:StartSizing("BOTTOMRIGHT")
check(win._sizing == true and win._sizingPoint == "BOTTOMRIGHT", "StartSizing: sizing, from its point")
win:StopMovingOrSizing()
check(win._sizing == false and win._sizingPoint == nil, "StopMovingOrSizing stops that too")
win:SetResizeBounds(200, 100, 800, 600)
local rb = win._resizeBounds
check(rb[1] == 200 and rb[2] == 100 and rb[3] == 800 and rb[4] == 600, "SetResizeBounds is kept as given")
check(not win:IsClampedToScreen(), "a frame isn't clamped to the screen until set (#104)")
win:SetClampedToScreen(true)
check(win:IsClampedToScreen(), "SetClampedToScreen(true) clamps it")
eq(win._clamped, true, "kept in w._clamped")
win:SetClampedToScreen(false)
check(not win:IsClampedToScreen(), "SetClampedToScreen(false) unclamps it")

-- Clicks a button registered: as given, a later call replaces them.
local btn = CreateFrame("Button", nil, UIParent)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
local rc = btn._registeredClicks
check(#rc == 2 and rc[1] == "LeftButtonUp" and rc[2] == "RightButtonUp", "RegisterForClicks keeps the clicks")
btn:RegisterForClicks("AnyDown")
check(#btn._registeredClicks == 1 and btn._registeredClicks[1] == "AnyDown", "a later call replaces them")

-- In combat a protected frame refuses SetScale, StartMoving,
-- StopMovingOrSizing and RegisterForClicks (WoW.PROTECTED, test_protected):
-- nothing changes.
WoW.templates.KitSecureTemplate = function(w) w._protected = true end
local secure = CreateFrame("Button", "KitSecureDrag", UIParent, "KitSecureTemplate")
secure:StartMoving()
WoW.combat = true
secure:StopMovingOrSizing()
eq(secure._moving, true, "a refused StopMovingOrSizing leaves the drag on")
secure:SetScale(3)
eq(secure:GetScale(), 1, "a refused SetScale leaves the scale")
secure:RegisterForClicks("AnyUp")
eq(secure._registeredClicks, nil, "a refused RegisterForClicks registers nothing")
WoW.combat = false
WoW.blocked = {}

-- ScrollFrame: the child, the offset (OnVerticalScroll on a change), the range.
local sf = CreateFrame("ScrollFrame", nil, UIParent)
local child = CreateFrame("Frame", nil, sf)
eq(sf:GetScrollChild(), nil, "no scroll child until set")
sf:SetScrollChild(child)
eq(sf:GetScrollChild(), child, "GetScrollChild reads it")
eq(sf:GetVerticalScroll(), 0, "the vertical scroll is 0 until set")
local scrolled = {}
sf:SetScript("OnVerticalScroll", function(_, offset) scrolled[#scrolled + 1] = offset end)
sf:SetVerticalScroll(30)
eq(sf:GetVerticalScroll(), 30, "GetVerticalScroll reads it")
check(#scrolled == 1 and scrolled[1] == 30, "OnVerticalScroll fires with the offset")
sf:SetVerticalScroll(30)
eq(#scrolled, 1, "not without a change")
sf:SetVerticalScroll(0)
check(#scrolled == 2 and scrolled[2] == 0, "back to 0 is a change")
eq(sf:GetVerticalScrollRange(), 0, "the range is 0 unset")
sf._yrange = 120
eq(sf:GetVerticalScrollRange(), 120, "a test's _yrange")

-- EditBox focus: one at a time, scripts on a change.
local box1 = CreateFrame("EditBox", "KitBox1", UIParent)
local box2 = CreateFrame("EditBox", "KitBox2", UIParent)
local seen = {}
for _, e in ipairs({ box1, box2 }) do
    e:SetScript("OnEditFocusGained", function(self) seen[#seen + 1] = self:GetName() .. " gained" end)
    e:SetScript("OnEditFocusLost", function(self) seen[#seen + 1] = self:GetName() .. " lost" end)
end
check(not box1:HasFocus() and not box2:HasFocus(), "no focus until set")
box1:SetFocus()
check(box1:HasFocus(), "SetFocus gives it the focus")
eq(table.concat(seen, ", "), "KitBox1 gained", "and fires OnEditFocusGained")
box1:SetFocus()
eq(#seen, 1, "not again while it has it")
box2:SetFocus()
check(box2:HasFocus() and not box1:HasFocus(), "one edit box at a time")
eq(table.concat(seen, ", "), "KitBox1 gained, KitBox1 lost, KitBox2 gained", "the one that had it loses it first")
eq(WoW.focus, box2, "WoW.focus is the edit box with the focus")
box1:ClearFocus()
eq(#seen, 3, "ClearFocus on one without it fires nothing")
box2:ClearFocus()
check(not box2:HasFocus(), "ClearFocus takes it")
eq(seen[4], "KitBox2 lost", "and fires OnEditFocusLost")
box2:ClearFocus()
eq(#seen, 4, "only on a change")

-- GameTooltip's lines and owner.
local tt = CreateFrame("GameTooltip", "KitTooltip", UIParent)
eq(tt:NumLines(), 0, "a new tooltip has no lines")
eq(#tt._lines, 0, "and an empty _lines")
tt:SetOwner(btn, "ANCHOR_RIGHT", 4, 0)
eq(tt:GetOwner(), btn, "GetOwner reads SetOwner's owner")
eq(tt._ownerAnchor[1], "ANCHOR_RIGHT", "the anchor is kept")
tt:SetText("Title", 1, 1, 1)
tt:AddLine("first", 1, 0.8, 0)
tt:AddDoubleLine("left", "right")
eq(tt:NumLines(), 3, "SetText, AddLine and AddDoubleLine make three lines")
check(tt._lines[1] == "Title" and tt._lines[2] == "first" and tt._lines[3] == "left", "each line's left text, in order")
check(tt._linesRight[3] == "right" and tt._linesRight[2] == nil, "a double line's right text, none for a single line")
tt:SetText("Again")
eq(tt:NumLines(), 1, "SetText makes its text the only line")
eq(tt._lines[1], "Again", "its text")
eq(tt._linesRight[3], nil, "the right texts go too")
tt:AddLine("more")
tt:SetOwner(UIParent, "ANCHOR_CURSOR")
eq(tt:NumLines(), 0, "SetOwner clears the lines")
eq(tt:GetOwner(), UIParent, "and takes the new owner")
tt:AddLine("x")
tt:ClearLines()
eq(tt:NumLines(), 0, "ClearLines clears them")
local secretName = WoW.Secret("name")
tt:AddDoubleLine(secretName, "1")
check(tt._lines[1] == secretName, "a secret is kept as given, untouched")

-- GetTexture: the file SetTexture set.
local t = f:CreateTexture()
eq(t:GetTexture(), nil, "no file until set")
t:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
eq(t:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark", "GetTexture reads SetTexture's file")
t:SetTexture(134400)
eq(t:GetTexture(), 134400, "a file ID too")
t:SetAtlas("glass-rim")
eq(t:GetTexture(), nil, "nil once an atlas replaced the file")

-- GetMinMaxValues.
local slider = CreateFrame("Slider", nil, UIParent)
local lo, hi = slider:GetMinMaxValues()
check(lo == 0 and hi == 0, "a slider reads 0, 0 until set")
slider:SetMinMaxValues(0.5, 2)
lo, hi = slider:GetMinMaxValues()
check(lo == 0.5 and hi == 2, "then what SetMinMaxValues set")
lo, hi = CreateFrame("StatusBar", nil, UIParent):GetMinMaxValues()
check(lo == 0 and hi == 1, "a status bar starts at 0, 1")

-- String metrics: the core's approximation, 6 a character and 14 a line.
local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
eq(label:GetStringWidth(), 0, "no text: width 0")
eq(label:GetStringHeight(), 0, "and height 0")
label:SetText("")
eq(label:GetStringHeight(), 0, "an empty text is no line")
label:SetText("abcd")
eq(label:GetStringWidth(), 24, "6 a character")
eq(label:GetStringHeight(), 14, "one line with no width set")
label:SetText("ab\nabcde")
eq(label:GetStringWidth(), 30, "the widest line's width")
eq(label:GetStringHeight(), 28, "a newline is a line")
label:SetText(string.rep("x", 25))
label:SetWidth(60)
eq(label:GetStringHeight(), 42, "wrapped at the width: 10 characters a line, 25 make three")
eq(label:GetStringWidth(), 150, "the width isn't wrapped")
label:SetText(1234)
eq(label:GetStringWidth(), 24, "a number's characters")
label:SetFormattedText("%s", WoW.Secret("text"))
eq(label:GetStringWidth(), 0, "a secret text reads as none")
local coreWidth = WoW.Methods.GetStringWidth
WoW.Methods.GetStringWidth = function() return 99 end
eq(label:GetStringWidth(), 99, "a consumer replaces WoW.Methods.GetStringWidth")
WoW.Methods.GetStringWidth = coreWidth

-- The unbounded widths (WowTestKit #107): GetStringWidth's rule, ignoring
-- the width set; the ForText one measures its argument, not the text.
local wide = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
eq(wide:GetUnboundedStringWidth(), 0, "unbounded: no text, width 0")
wide:SetText("ab\nabcde")
eq(wide:GetUnboundedStringWidth(), 30, "unbounded: the widest line's width")
wide:SetText(string.rep("x", 25))
wide:SetWidth(60)
eq(wide:GetUnboundedStringWidth(), 150, "unbounded: the width set doesn't cap it")
eq(wide:GetUnboundedStringWidthForText("abc"), 18, "for text: its argument's width")
eq(wide:GetUnboundedStringWidthForText("abc\nab"), 18, "for text: the widest line's")
eq(wide:GetUnboundedStringWidthForText(12345), 30, "for text: a number's characters")
eq(wide:GetUnboundedStringWidthForText(""), 0, "for text: an empty text is 0")
local ok, err = pcall(wide.GetUnboundedStringWidthForText, wide, nil)
check(not ok and tostring(err):find("GetUnboundedStringWidthForText", 1, true), "for text: a missing text throws")
ok = pcall(wide.GetUnboundedStringWidthForText, wide, {})
check(not ok, "for text: a table isn't a text")
ok, err = pcall(function() wide:GetUnboundedStringWidthForText() end)
check(not ok and tostring(err):find("test_frame_methods.lua:241:", 1, true), "for text: the error names the caller's line: " .. tostring(err))
-- AllowedWhenUntainted: addon code is tainted, so a secret is refused, and a
-- pcall that swallows the refusal counts it.
WoW.secretBlocked = 0
ok, err = pcall(function() wide:GetUnboundedStringWidthForText(WoW.Secret("a label")) end)
check(not ok and tostring(err):find("secret value touched in Lua: a label", 1, true), "for text: a secret proxy is refused: " .. tostring(err))
check(tostring(err):find("test_frame_methods.lua:246:", 1, true), "for text: at the caller's line")
eq(WoW.secretBlocked, 1, "for text: the swallowed refusal is counted")
local typed = WoW.MarkSecret("a typed secret label (#107)")
ok = pcall(function() wide:GetUnboundedStringWidthForText(typed) end)
check(not ok, "for text: a typed secret string is refused too")
eq(WoW.secretBlocked, 2, "for text: and counted")
WoW.secrets[typed] = nil
WoW.secretBlocked = 0
eq(wide:GetText(), string.rep("x", 25), "for text: the string's own text is unchanged")

-- WoW.reset() clears the focus.
box1:SetFocus()
WoW.reset()
eq(WoW.focus, nil, "WoW.reset() clears the focus")

done("test_frame_methods")
