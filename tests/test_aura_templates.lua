-- Blizzard_AuraContainer's custom aura templates and ActionButtonSpellAlertTemplate
-- (WowTestKit #113), as Blizzard's source has them (wow-ui-source forever 71037).
dofile("kit.lua")
Kit.load({ build = "71139", api = Kit.API })

-- fn fails, with a message holding want.
local function fails(fn, want, what)
    local ok, err = pcall(fn)
    check(not ok, what .. ": fails")
    check(not ok and tostring(err):find(want, 1, true) ~= nil, what .. ": says '" .. want .. "' (got: " .. tostring(err) .. ")")
end

-- The container: an AuraContainer (a Frame), with the intrinsic's KeyValues
-- (Blizzard_AuraContainer.xml:7-8), nothing asked yet.
local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
eq(c:GetObjectType(), "Frame", "an AuraContainer is a Frame")
eq(c._enabled, true, "a container starts enabled")
eq(c._unit, "none", "on the unit \"none\"")
eq(c._refreshes, 0, "and has refreshed nothing")

-- SetUnit / SetEnabled refresh only when the value changes.
c:SetUnit("none")
eq(c._refreshes, 0, "SetUnit(\"none\") at first: no refresh")
c:SetEnabled(true)
eq(c._refreshes, 0, "SetEnabled(true) at first: no refresh")
c:SetUnit("player")
eq(c._unit, "player", "SetUnit keeps the unit")
eq(c._refreshes, 1, "and refreshes")
c:SetUnit("player")
eq(c._refreshes, 1, "the same unit again: no refresh")
fails(function() c:SetUnit(nil) end, "assertion failed", "SetUnit(nil)")
c:SetEnabled(false)
eq(c._enabled, false, "SetEnabled(false) disables it")
eq(c._refreshes, 2, "and refreshes")
c:SetEnabled(false)
eq(c._refreshes, 2, "disabled again: no refresh")
c:UpdateAllAuras()
eq(c._refreshes, 3, "UpdateAllAuras is a refresh")

-- AddAuraSlot: an AuraButton with the template, initializeFrame called with it
-- while it's still shown, hidden after, the filters copied, a refresh.
local order = {}
WoW.templates.KitExtraTemplate = function(f) order[#order + 1] = f.SetApplicationBar ~= nil end
local ids = { [101] = true }
local seen, shownAtInit
local f = c:AddAuraSlot("glow", "HELPFUL|PLAYER", {
    templateNames = { "KitExtraTemplate" },
    candidateFilters = { includeSpellIDs = ids },
    initializeFrame = function(frame) seen, shownAtInit = frame, frame:IsShown() end,
})
eq(f:GetObjectType(), "Button", "the slot frame is an AuraButton (a Button)")
eq(f._intrinsic, "AuraButton", "made as an AuraButton")
eq(f:GetParent(), c, "parented to the container")
eq(f._template, "CustomAuraButtonTemplate, KitExtraTemplate", "CustomAuraButtonTemplate, then templateNames")
eq(#order, 1, "templateNames' templates are applied")
eq(order[1], true, "after CustomAuraButtonTemplate")
eq(seen, f, "initializeFrame gets the slot frame")
eq(shownAtInit, true, "still shown when initializeFrame runs")
eq(f:IsShown(), false, "hidden after: no aura (CustomAuraButton.lua:694)")
eq(c:GetAuraSlotFrame("glow"), f, "GetAuraSlotFrame returns it")
eq(c:GetAuraSlotFrame("nope"), nil, "and nil for a key with no slot")
eq(c:IsAuraSlotEnabled("glow"), true, "a new slot is enabled")
eq(c._slots.glow.filter, "HELPFUL|PLAYER", "the slot keeps its filter")
eq(c._refreshes, 4, "AddAuraSlot refreshes")
ids[102] = true
eq(c._slots.glow.candidateFilters.includeSpellIDs[102], nil, "the candidate filters are a copy")
eq(c._slots.glow.candidateFilters.includeSpellIDs[101], true, "of what was passed")

-- What AddAuraSlot refuses.
fails(function() c:AddAuraSlot("glow", "HELPFUL") end, "aura slot 'glow' already exists with this key.", "a key in use")
fails(function() c:AddAuraSlot("", "HELPFUL") end, "slotKey must be a non-empty string.", "an empty key")
fails(function() c:AddAuraSlot("x", "HELPFUL|BOGUS") end, "Unknown aura filter component: 'BOGUS'", "an unknown filter")
fails(function() c:AddAuraSlot("x", "HELPFUL !") end, "A negation prefix ('!') must be followed", "a bare '!'")
fails(function() c:AddAuraSlot("x", nil) end, "bad argument #2 to 'split'", "no filter string")
fails(function() c:AddAuraSlot("x", "HELPFUL", { initializeFrame = 1 }) end, "initializeFrame must be a function or nil.", "initializeFrame not a function")
fails(function() c:AddAuraSlot("x", "HELPFUL", { templateNames = "T" }) end, "templateNames must be a table or nil.", "templateNames not a table")
fails(function() c:AddAuraSlot("x", "HELPFUL", { candidateFilters = { includeSpellIDs = 5 } }) end, "includeSpellIDs must be a table or nil", "includeSpellIDs not a table")
fails(function() c:AddAuraSlot("x", "HELPFUL", { candidateFilters = { maxDuration = -1 } }) end, "maxDuration must be a non-negative number or nil.", "a negative maxDuration")
fails(function() c:AddAuraSlot("x", "HELPFUL", { candidateFilters = { isStealable = 1 } }) end, "isStealable must be a boolean or nil.", "a boolean filter that isn't")
fails(function() c:AddAuraSlot("x", "HELPFUL", false) end, "bad argument #1 to 'pairs' (table expected, got boolean)", "options false (MergeTable)")
eq(c._slots.x, nil, "a refused slot isn't added")
eq(c._refreshes, 4, "nor refreshes")
check(c:AddAuraSlot("neg", "!PLAYER | HARMFUL") ~= nil, "a negated component, spaces and no options are fine")
eq(c._refreshes, 5, "that slot refreshes too")

-- SetAuraSlotEnabled refreshes every time; SetAuraSlotCandidateFilters copies.
c:SetAuraSlotEnabled("glow", false)
eq(c:IsAuraSlotEnabled("glow"), false, "SetAuraSlotEnabled(false) disables the slot")
eq(c._refreshes, 6, "and refreshes")
c:SetAuraSlotEnabled("glow", false)
eq(c._refreshes, 7, "the same value again: still a refresh (ManagedAuraContainer.lua:250)")
fails(function() c:SetAuraSlotEnabled("glow", 1) end, "enabled must be a boolean.", "a non-boolean")
fails(function() c:SetAuraSlotEnabled("nope", true) end, "aura slot 'nope' was not found with this key.", "SetAuraSlotEnabled on no slot")
fails(function() c:IsAuraSlotEnabled("nope") end, "aura slot 'nope' was not found with this key.", "IsAuraSlotEnabled on no slot")
local want = { includeSpellIDs = { [7] = true } }
c:SetAuraSlotCandidateFilters("glow", want)
want.includeSpellIDs[8] = true
eq(c._slots.glow.candidateFilters.includeSpellIDs[7], true, "SetAuraSlotCandidateFilters keeps the new filters")
eq(c._slots.glow.candidateFilters.includeSpellIDs[8], nil, "as a copy")
eq(c._refreshes, 8, "and refreshes")
c:SetAuraSlotCandidateFilters("glow", nil)
eq(next(c._slots.glow.candidateFilters), nil, "nil clears them")
fails(function() c:SetAuraSlotCandidateFilters("nope", {}) end, "aura slot 'nope' was not found with this key.", "SetAuraSlotCandidateFilters on no slot")
fails(function() c:SetAuraSlotCandidateFilters("glow", { excludeSpellIDs = "x" }) end, "excludeSpellIDs must be a table or nil", "bad candidate filters")
local refreshes = c._refreshes
fails(function() c:SetAuraSlotCandidateFilters("glow", false) end, "bad argument #1 to 'pairs' (table expected, got boolean)", "candidate filters false (MergeTable)")
eq(c._refreshes, refreshes, "a refused update doesn't refresh")
eq(next(c._slots.glow.candidateFilters), nil, "nor changes the filters")

-- The slot frame's application bar (ValidateInboundScriptObject's checks, then
-- the options' structure).
local bar = CreateFrame("StatusBar", nil, f)
local opts = { minApplications = 3, maxApplications = 3 }
f:SetApplicationBar(bar, opts)
opts.minApplications = 9
eq(f._applicationBar.bar, bar, "SetApplicationBar keeps the bar")
eq(f._applicationBar.options.minApplications, 3, "and a copy of its options")
f:SetApplicationBar(bar, { maxApplications = 2 })
eq(f._applicationBar.options.minApplications, 0, "minApplications defaults to 0")
eq(f._applicationBar.options.maxApplications, 2, "maxApplications kept")
local deep = CreateFrame("StatusBar", nil, CreateFrame("Frame", nil, f))
f:SetApplicationBar(deep, { maxApplications = 1 })
eq(f._applicationBar.bar, deep, "an indirect descendant is fine")
local parentOfSecure = CreateFrame("StatusBar", nil, f)
CreateFrame("Frame", nil, parentOfSecure, "SecureFrameTemplate")
f:SetApplicationBar(parentOfSecure, { maxApplications = 1 })
eq(f._applicationBar.bar, parentOfSecure, "protected only through a child (not explicitly) is fine")
local bad = "bad object '<StatusBar>' in function call ("
fails(function() f:SetApplicationBar(CreateFrame("StatusBar", nil, f, "SecureFrameTemplate"), { maxApplications = 1 }) end,
      bad .. "must not be an explicitly protected object)", "an explicitly protected bar")
fails(function() f:SetApplicationBar(CreateFrame("StatusBar", nil, c), { maxApplications = 1 }) end,
      bad .. "must be the owner or a direct or indirect descendant of owner)", "a bar on the container")
fails(function() f:SetApplicationBar(CreateFrame("StatusBar", nil, c:GetAuraSlotFrame("neg")), { maxApplications = 1 }) end,
      bad .. "must be the owner or a direct or indirect descendant of owner)", "a bar on another slot")
fails(function() f:SetApplicationBar(f, { maxApplications = 1 }) end,
      "bad object '<Button>' in function call (must be the owner or a direct or indirect descendant of owner)", "the slot frame itself")
fails(function() f:SetApplicationBar(CreateFrame("StatusBar"), { maxApplications = 1 }) end,
      bad .. "must be the owner or a direct or indirect descendant of owner)", "a bar with no parent")
fails(function() f:SetApplicationBar(f:CreateTexture(), { maxApplications = 1 }) end,
      "expected object type 'StatusBar', got 'Texture'", "a bar that isn't a StatusBar")
fails(function() f:SetApplicationBar(c:CreateTexture()) end,
      "bad object '<Texture>' in function call (must be the owner", "not a descendant: refused before the type")
fails(function() f:SetApplicationBar(bar, {}) end, "options.maxApplications must be a number, got nil", "no maxApplications")
fails(function() f:SetApplicationBar(bar) end, "options.maxApplications must be a number, got nil", "no options")
fails(function() f:SetApplicationBar(bar, { maxApplications = "3" }) end, "options.maxApplications must be a number, got string", "maxApplications not a number")
fails(function() f:SetApplicationBar(bar, { maxApplications = 3, minApplications = "1" }) end, "options.minApplications must be a number, got string", "minApplications not a number")
fails(function() f:SetApplicationBar(bar, "x") end, "options must be a table, got string", "options not a table")
eq(f._applicationBar.bar, parentOfSecure, "a refused bar isn't kept")

-- The slot frame's icon.
eq(f:GetIcon(), nil, "GetIcon: no icon before SetIcon")
local icon = f:CreateTexture(nil, "ARTWORK")
f:SetIcon(icon)
eq(f:GetIcon(), icon, "SetIcon's texture is GetIcon's")
fails(function() f:SetIcon(bar) end, "bad object '<StatusBar>' in function call (expected object type 'Texture', got 'StatusBar')", "an icon that isn't a Texture")
fails(function() f:SetIcon(c:CreateTexture()) end, "must be the owner or a direct or indirect descendant of owner", "an icon on the container")
eq(f:GetIcon(), icon, "a refused icon isn't kept")

-- The mixins' methods aren't widget calls: nothing logged, nothing for the methods check.
local before = #c._log
local quiet = c:AddAuraSlot("quiet", "HELPFUL")
c:SetAuraSlotEnabled("quiet", false)
c:SetUnit("target")
eq(#c._log, before, "the container's mixin calls aren't in its log")
eq(#quiet._log, 0, "a new slot frame has logged nothing (its Hide is the kit's)")
local barLog, fLog, cLog, iconLog = #bar._log, #f._log, #c._log, #icon._log
f:SetApplicationBar(bar, { maxApplications = 1 })
f:SetIcon(icon)
eq(#bar._log, barLog, "SetApplicationBar's checks log nothing on the bar")
eq(#icon._log, iconLog, "SetIcon's checks log nothing on the icon")
eq(#f._log + #c._log, fLog + cLog, "nor on the frames the parent walk passes")
check(not WoW.methodsCalled["Frame:AddAuraSlot"] and not WoW.methodsCalled["Button:SetApplicationBar"]
      and not WoW.methodsCalled["Button:SetIcon"],
      "no mixin method recorded as a widget method")
check(Kit.checkMethods() > 0, "Kit.checkMethods passes")

-- ActionButtonSpellAlertTemplate (ActionButtonSpellAlerts.xml:4).
local g = CreateFrame("Frame", nil, UIParent, "ActionButtonSpellAlertTemplate")
eq(#g._log, 0, "the template logs no call on the alert")
eq(g:IsShown(), false, "the spell alert starts hidden")
for _, k in ipairs({ "ProcStartFlipbook", "ProcLoopFlipbook", "ProcAltGlow" }) do
    eq(g[k]:GetObjectType(), "Texture", k .. " is a Texture")
    eq(g[k]._layer, "ARTWORK", k .. " on ARTWORK")
    eq(g[k]:GetParent(), g, k .. " is the alert's")
end
eq(g.ProcStartFlipbook:IsShown(), true, "ProcStartFlipbook is shown")
eq(g.ProcAltGlow:IsShown(), false, "ProcAltGlow is hidden")
eq(g.ProcLoop:GetObjectType(), "AnimationGroup", "ProcLoop is an AnimationGroup")
eq(g.ProcStartAnim:GetObjectType(), "AnimationGroup", "and so is ProcStartAnim")
check(g.ProcLoop ~= g.ProcStartAnim, "two of them")
g.ProcLoop:Play()
eq(g.ProcLoop:IsPlaying(), true, "ProcLoop plays")

done("test_aura_templates")
