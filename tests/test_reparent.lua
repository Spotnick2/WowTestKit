-- SetParent, as measured on 70959 (WowTestKitProbe, /fp steps tk reparent,
-- 2026-11-18; WowTestKit #99): OnShow / OnHide on a visibility change,
-- children first, during the call, with the new parent already set; the
-- frame level one above the new parent's, and the children one above it.
-- Each case is one of the probe's, with the client's result.
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

local names, fired = {}, {}
local function nameOf(f)
    if f == nil then return "nil" end
    if f == UIParent then return "UIParent" end
    return names[f] or "?"
end
local function frame(name, parent)
    local f = CreateFrame("Frame", nil, parent)
    names[f] = name
    for _, script in ipairs({ "OnShow", "OnHide" }) do
        f:SetScript(script, function(self)
            fired[#fired + 1] = name .. ":" .. script .. "(" .. nameOf(self:GetParent()) .. ")"
        end)
    end
    return f
end
local function run(act) fired = {}; act(); return table.concat(fired, " ") end

-- Scripts (the probe's v1-v9).
local S = frame("S", UIParent)
local H = frame("H", UIParent); H:Hide()
local C = frame("C", S)
local G = frame("G", C)
eq(run(function() C:SetParent(H) end), "G:OnHide(C) C:OnHide(H)", "v1 visible -> hidden: OnHide, children first, new parent set")
check(C:IsShown() and not C:IsVisible() and not G:IsVisible(), "v1 shown, invisible")
eq(run(function() C:SetParent(S) end), "G:OnShow(C) C:OnShow(S)", "v2 hidden -> visible: OnShow")
eq(run(function() C:SetParent(nil) end), "", "v3 visible -> visible (no parent): nothing")
eq(run(function() C:SetParent(H) end), "G:OnHide(C) C:OnHide(H)", "v4 from no parent to a hidden one")
eq(run(function() C:SetParent(nil) end), "G:OnShow(C) C:OnShow(nil)", "v5 from a hidden parent to none")
eq(run(function() C:Hide() end), "G:OnHide(C) C:OnHide(nil)", "v6 Hide: children first too")
eq(run(function() C:SetParent(H) end), "", "v7 a hidden frame moved: nothing")
eq(run(function() C:SetParent(S) end), "", "v8 nor back under a shown parent")
eq(run(function() C:Show() end), "G:OnShow(C) C:OnShow(S)", "v9 Show: children first")
eq((S:GetChildren()), C, "the new parent lists it")
local listed
C:SetScript("OnHide", function(self)
    listed = (H:GetChildren()) == self and select("#", S:GetChildren()) == 0
end)
C:SetParent(H)
check(listed, "when its OnHide runs, the new parent lists it and the old one doesn't")
C:SetParent(S)

-- Under a UIParent hidden by Alt+Z (the probe's u1-u2: LibShowcase's drop).
local U = frame("U", nil)
local UG = frame("UG", U)
UIParent:Hide()
eq(run(function() U:SetParent(UIParent) end), "UG:OnHide(U) U:OnHide(UIParent)", "u1 under a hidden UIParent: OnHide")
eq(run(function() U:SetParent(nil) end), "UG:OnShow(U) U:OnShow(nil)", "u2 and out again: OnShow")
UIParent:Show()

-- A script that reparents during the walk: the drop re-entering itself. Not
-- measured: this pins the kit's walk, one script per real change.
local A = frame("A", S)
local AB = frame("AB", A)
local reentered = 0
A:SetScript("OnHide", function(self)
    fired[#fired + 1] = "A:OnHide(" .. nameOf(self:GetParent()) .. ")"
    reentered = reentered + 1
    if reentered == 1 then self:SetParent(S) end   -- put it back from its own OnHide
end)
eq(run(function() A:SetParent(H) end), "AB:OnHide(A) A:OnHide(H) AB:OnShow(A) A:OnShow(S)",
    "an OnHide that reparents again: each change gets its scripts once")
check(A:IsVisible() and AB:IsVisible() and A:GetParent() == S, "and the last move holds")

-- Levels (the probe's l0-l5).
local P10 = frame("P10", UIParent); P10:SetFrameLevel(10)
local P3 = frame("P3", UIParent); P3:SetFrameLevel(3)
local L = frame("L", UIParent)
eq(L:GetFrameLevel(), 1, "l0 made under UIParent (0): 1")
L:SetFrameLevel(7)
local LG = frame("LG", L)
eq(LG:GetFrameLevel(), 8, "l0 a child made under it: one above")
local function levels() return L:GetFrameLevel() .. "," .. LG:GetFrameLevel() end
L:SetParent(P10)
eq(levels(), "11,12", "l1 under a 10: 11, its child 12")
L:SetParent(nil)
eq(levels(), "0,1", "l2 no parent: 0")
L:SetParent(UIParent)
eq(levels(), "1,2", "l3 under UIParent: 1")
L:SetFrameLevel(50)
L:SetParent(P3)
eq(levels(), "4,5", "l4 a 50 under a 3: lowered to 4, its child one above")
L:SetFrameLevel(2)
L:SetParent(P10)
eq(levels(), "11,12", "l5 a 2 under a 10: raised to 11")

-- A region reparented: no scripts to run, its visibility follows.
local tex = S:CreateTexture()
tex:SetParent(H)
check(not tex:IsVisible(), "a texture moved under a hidden frame is invisible")

done("test_reparent")
