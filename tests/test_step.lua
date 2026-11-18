-- WoW.step: one rendered frame with its timers (WowTestKit #66), and
-- UIPanelScrollFrameTemplate's ScrollBar.
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

WoW.now = 100

-- An OnUpdate throttled by adding up elapsed, the common pattern.
local poll = CreateFrame("Frame", nil, UIParent)
poll.t, poll.runs = 0, 0
poll:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 then return end
    self.t, self.runs = 0, self.runs + 1
end)
local seen = {}
local probe = CreateFrame("Frame", nil, UIParent)
probe:SetScript("OnUpdate", function(_, elapsed) seen[#seen + 1] = { elapsed, GetTime() } end)

WoW.step(0.05)
eq(#seen, 1, "a step runs OnUpdate once")
eq(seen[1][1], 0.05, "with the step's dt")
eq(seen[1][2], 100.05, "after the clock moved by it")
eq(GetTime(), 100.05, "the clock moves once, not twice")
WoW.step(0.05)
eq(poll.runs, 1, "an elapsed-throttled OnUpdate runs once its elapsed adds up")
for _ = 1, 8 do WoW.step(0.05) end
eq(poll.runs, 5, "and every 0.1 s of steps after that")

-- What step replaces: advance, then tick(0), starves that OnUpdate.
local starved = poll.runs
for _ = 1, 10 do WoW.advance(0.05); WoW.tick(0) end
eq(poll.runs, starved, "advance + tick(0) hands OnUpdate elapsed = 0, so the throttled one never runs")

-- Timers due by the new time run, before OnUpdate.
local order = {}
local t0 = GetTime()
C_Timer.After(0.5, function() order[#order + 1] = { "timer", GetTime() } end)
local fired = CreateFrame("Frame", nil, UIParent)
fired:SetScript("OnUpdate", function() if order[1] and not order[2] then order[2] = { "update" } end end)
WoW.step(0.25)
eq(#order, 0, "a timer not yet due doesn't run")
WoW.step(0.25)
eq(order[1] and order[1][1], "timer", "the timer due by the step's end runs")
eq(order[1] and order[1][2], t0 + 0.5, "with the clock at the step's end")
eq(order[2] and order[2][1], "update", "and OnUpdate runs after it, in the same step")
fired:SetScript("OnUpdate", nil)

-- A ticker fires once per period the step spans, as under advance.
local ticks = 0
local ticker = C_Timer.NewTicker(0.1, function() ticks = ticks + 1 end)
WoW.step(0.35)
eq(ticks, 3, "a 0.1 s ticker fires three times in a 0.35 s step")
ticker:Cancel()

-- A hidden frame's OnUpdate doesn't run; the default dt is tick's.
probe:Hide()
local before, t1 = #seen, GetTime()
WoW.step()
eq(#seen, before, "a hidden frame's OnUpdate doesn't run")
check(math.abs(GetTime() - (t1 + 0.02)) < 1e-9, "the default dt is 0.02, as tick's")

-- tick is unchanged: it runs no timer.
local late = false
C_Timer.After(0.01, function() late = true end)
WoW.tick(1)
check(not late, "a tick still runs no timer")

-- UIPanelScrollFrameTemplate (SecureScrollTemplates.xml:44).
local sf = CreateFrame("ScrollFrame", "KitScroll", UIParent, "UIPanelScrollFrameTemplate")
check(sf.ScrollBar ~= nil, "the template gives the scroll frame its ScrollBar")
eq(sf.ScrollBar:GetObjectType(), "Slider", "a Slider")
eq(sf.ScrollBar:GetParent(), sf, "parented to the scroll frame")
eq(sf.ScrollBar:GetName(), "KitScrollScrollBar", "named $parentScrollBar")
eq(rawget(_G, "KitScrollScrollBar"), sf.ScrollBar, "which is a global")
eq(sf.ScrollBar.ScrollUpButton:GetObjectType(), "Button", "the bar's ScrollUpButton is a Button")
eq(sf.ScrollBar.ScrollUpButton:GetName(), "KitScrollScrollBarScrollUpButton", "named $parentScrollUpButton")
eq(sf.ScrollBar.ScrollDownButton:GetName(), "KitScrollScrollBarScrollDownButton", "and ScrollDownButton")
eq(select("#", sf:GetChildren()), 1, "the bar is the scroll frame's one child")
local anon = CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate")
eq(anon.ScrollBar:GetName(), nil, "an unnamed scroll frame's bar has no name")
check(anon.ScrollBar.ScrollDownButton ~= nil, "but has its buttons")

done("test_step")
