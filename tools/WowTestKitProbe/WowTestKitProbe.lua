-- WowTestKitProbe: WowTestKit's developer probe, a ForeverProbe module
-- (/fp tk). It measures client behaviour the kit's core models, so a core
-- method follows a measurement rather than a guess. Its lines go to the
-- ForeverProbe console and WowTestKitProbeDB.log, never to chat. It is never
-- packaged.
--   /fp steps tk reparent   SetParent: OnShow / OnHide on a visibility change,
--                           and the frame level after it (WowTestKit #99)
--   /fp tk reparent         the same measurement at once, without the steps
--
-- Every frame it makes is its own, plain (no template, nothing protected) and
-- empty (nothing drawn), so it runs in or out of combat and shows nothing.

local ADDON, NS = ...
local MAX_LOG = 3000
local Probe = ForeverProbe:Module("WowTestKitProbe", { api = 1, cmd = "tk" })
local function say(msg) Probe:Say(msg) end
local Show = Probe.Show

-- ─── reparent (#99) ─────────────────────────────────────────────────────────
--
-- Each case runs one call between a begin and an end mark. The frames' OnShow
-- and OnHide append to `fired` with the parent and visibility they read inside
-- the script, so the record says whether a script ran during the call, in
-- which order (parents first?), and whether the frame was already under its
-- new parent when it ran. Anything that fires after a case's end mark is late:
-- the next step collects it a second later.

local names = {}          -- frame -> its name in the record
local fired = {}          -- the scripts of the case being run
local late = {}           -- scripts that ran outside any case
local inCase = false
local results = {}        -- case label -> what it recorded

local function nameOf(f)
    if f == nil then return "nil" end
    if f == UIParent then return "UIParent" end
    return names[f] or "?"
end

local function watch(f, name)
    names[f] = name
    for _, script in ipairs({ "OnShow", "OnHide" }) do
        f:SetScript(script, function(self)
            local line = name .. ":" .. script .. "(parent=" .. nameOf(self:GetParent())
                .. ",visible=" .. Show(self:IsVisible()) .. ")"
            if inCase then fired[#fired + 1] = line else late[#late + 1] = line end
        end)
    end
    return f
end

local function frame(name, parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 1)
    f:SetPoint("CENTER")
    return watch(f, name)
end

-- One case: run act, record the scripts it fired and what read() says after.
local function case(label, act, read)
    fired = {}
    inCase = true
    local ok, err = pcall(act)
    inCase = false
    local after = ""
    if read then
        local okR, v = pcall(read)
        after = okR and tostring(v) or ("read threw: " .. tostring(v))
    end
    local line = (ok and "" or ("THREW " .. tostring(err) .. " ")) .. "scripts=["
        .. table.concat(fired, " ") .. "]" .. (after ~= "" and (" " .. after) or "")
    results[label] = line
    say("REPARENT " .. label .. ": " .. line)
    return line
end

local function levels(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        parts[#parts + 1] = nameOf(f) .. "=" .. Show(f:GetFrameLevel())
    end
    return "levels " .. table.concat(parts, " ")
end

local function vis(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        parts[#parts + 1] = nameOf(f) .. ":" .. (f:IsShown() and "shown" or "hidden")
            .. "/" .. (f:IsVisible() and "visible" or "invisible")
    end
    return table.concat(parts, " ")
end

local caseStarted = 0

local function measureVisibility()
    -- S shown, H hidden, both under UIParent; C (with its child G) starts under S.
    local S = frame("S", UIParent)
    local H = frame("H", UIParent); H:Hide()
    local C = frame("C", S)
    local G = frame("G", C)
    case("v1 C: S -> H (visible -> hidden)", function() C:SetParent(H) end, function() return vis(C, G) end)
    case("v2 C: H -> S (hidden -> visible)", function() C:SetParent(S) end, function() return vis(C, G) end)
    case("v3 C: S -> nil (visible -> visible)", function() C:SetParent(nil) end, function() return vis(C, G) end)
    case("v4 C: nil -> H (visible -> hidden)", function() C:SetParent(H) end, function() return vis(C, G) end)
    case("v5 C: H -> nil (hidden -> visible)", function() C:SetParent(nil) end, function() return vis(C, G) end)
    case("v6 C:Hide() under nil (control)", function() C:Hide() end, function() return vis(C, G) end)
    case("v7 hidden C: nil -> H", function() C:SetParent(H) end, function() return vis(C, G) end)
    case("v8 hidden C: H -> S", function() C:SetParent(S) end, function() return vis(C, G) end)
    case("v9 C:Show() under S (control)", function() C:Show() end, function() return vis(C, G) end)
    C:SetParent(H)   -- put away, outside any case
end

local function measureLevels()
    local P10 = frame("P10", UIParent); P10:SetFrameLevel(10)
    local P3 = frame("P3", UIParent); P3:SetFrameLevel(3)
    local L = frame("L", UIParent)
    local fresh = levels(UIParent, L)
    L:SetFrameLevel(7)
    local LG = frame("LG", L)
    results["l0 made"] = fresh .. "; after L:SetFrameLevel(7) and LG made under it: " .. levels(L, LG)
    say("REPARENT l0 made: " .. results["l0 made"])
    case("l1 L(7): UIParent -> P10(10)", function() L:SetParent(P10) end, function() return levels(L, LG) end)
    case("l2 L: P10 -> nil", function() L:SetParent(nil) end, function() return levels(L, LG) end)
    case("l3 L: nil -> UIParent", function() L:SetParent(UIParent) end, function() return levels(L, LG) end)
    case("l4 L(50): UIParent -> P3(3)", function() L:SetFrameLevel(50); L:SetParent(P3) end,
        function() return levels(L, LG) end)
    case("l5 L(2): P3 -> P10(10)", function() L:SetFrameLevel(2); L:SetParent(P10) end,
        function() return levels(L, LG) end)
    local okFixed = Probe:Try("SetFixedFrameLevel", L.SetFixedFrameLevel, L, true)
    if okFixed then
        case("l6 fixed L(7): P10 -> P3(3)", function() L:SetFrameLevel(7); L:SetParent(P3) end,
            function() return levels(L, LG) .. " fixed=" .. Show(L:HasFixedFrameLevel()) end)
        L:SetFixedFrameLevel(false)
    end
    local PH = frame("PH", UIParent); PH:SetFrameStrata("HIGH")
    case("l7 L (MEDIUM): P3 -> PH (HIGH strata)", function() L:SetFrameStrata("MEDIUM"); L:SetParent(PH) end,
        function() return "strata L=" .. Show(L:GetFrameStrata()) .. " PH=" .. Show(PH:GetFrameStrata())
            .. " " .. levels(PH, L) end)
    for _, f in ipairs({ P10, P3, L, PH }) do f:Hide() end
end

local function reparent()
    results = {}
    late = {}
    say("REPARENT client " .. table.concat({ GetBuildInfo() }, " ", 1, 2) .. ", UIParent level "
        .. Show(UIParent:GetFrameLevel()) .. ", combat " .. Show(InCombatLockdown()))
    measureVisibility()
    measureLevels()
    caseStarted = GetTime()
    WowTestKitProbeDB.reparent = results
    say("REPARENT done: " .. (function() local n = 0; for _ in pairs(results) do n = n + 1 end; return n end)()
        .. " cases; the next step collects late scripts")
    return "done"
end

-- The Alt+Z case (LibShowcase's drop): with UIParent hidden, a parentless
-- shown frame moved under UIParent, then back out.
local function hiddenUI()
    local U = frame("U", nil)
    local UG = frame("UG", U)
    local before = "UIParent shown=" .. Show(UIParent:IsShown()) .. " " .. vis(U, UG)
    say("REPARENT u0 " .. before)
    case("u1 U: nil -> UIParent (hidden by Alt+Z)", function() U:SetParent(UIParent) end,
        function() return vis(U, UG) end)
    case("u2 U: UIParent (hidden) -> nil", function() U:SetParent(nil) end, function() return vis(U, UG) end)
    U:Hide()
    WowTestKitProbeDB.reparent = results
    return before
end

Probe:Steps("reparent", {
    title = "SetParent: scripts and frame level (WowTestKit #99)",
    rev = 1,
    { text = "Press Run. It reparents a few invisible test frames and records what fires. Works in or out of combat.",
      button = "Run", run = reparent },
    { text = "Waiting a second for any script that runs late.",
      wait = function()
          if GetTime() - caseStarted < 1 then return false, "waiting" end
          local list = table.concat(late, " ")
          results["late"] = "[" .. list .. "]"
          WowTestKitProbeDB.reparent = results
          say("REPARENT late: [" .. list .. "]")
          return true, results["late"]
      end, timeout = 30 },
    { text = "Press Alt+Z to hide the interface. This panel stays up.",
      wait = function() return not UIParent:IsShown() end, timeout = 120 },
    { text = "Reparenting under the hidden interface.", auto = true, run = hiddenUI },
    { text = "Press Alt+Z again to bring the interface back.",
      wait = function() return UIParent:IsShown() end, timeout = 120 },
    { text = "Type /reload, or press Reload now, to save the results.", reload = true },
})

Probe:Command("reparent", function() reparent() end, "SetParent's scripts and levels at once (#99)")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(WowTestKitProbeDB) ~= "table" then WowTestKitProbeDB = {} end
    if type(WowTestKitProbeDB.log) ~= "table" then WowTestKitProbeDB.log = {} end
    Probe:UseLog(WowTestKitProbeDB.log, MAX_LOG)
    WowTestKitProbeDB.loads = (WowTestKitProbeDB.loads or 0) + 1
    say("loaded (" .. WowTestKitProbeDB.loads .. " loads). /fp steps tk reparent")
end)

NS._test = { Probe = Probe, results = function() return results end, hiddenUI = hiddenUI }   -- the test seam, never on _G
