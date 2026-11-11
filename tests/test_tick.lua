-- WoW.tick: one rendered frame moves GetTime() by its elapsed (WowTestKit #9).
dofile("kit.lua")
Kit.load({ build = "70532" })

WoW.now = 100
local f = CreateFrame("Frame", nil, UIParent)
local seen = {}
f:SetScript("OnUpdate", function(_, elapsed) seen[#seen + 1] = { elapsed, GetTime() } end)

WoW.tick(0.5)
eq(#seen, 1, "OnUpdate runs once per tick")
eq(seen[1][1], 0.5, "with the tick's elapsed")
eq(seen[1][2], 100.5, "and GetTime() has already moved by it")
WoW.tick(0.25)
eq(seen[2][2], 100.75, "every tick moves the clock")
WoW.tick()
check(math.abs(GetTime() - 100.77) < 1e-9, "the default elapsed (0.02) moves it too (" .. GetTime() .. ")")

-- A fade timed by GetTime() inside OnUpdate (GlassActionBars' Fade.lua).
local fade = CreateFrame("Frame", nil, UIParent)
local startAt = GetTime()
fade:SetScript("OnUpdate", function(self)
    local a = 1 - (GetTime() - startAt)
    self:SetAlpha(a < 0 and 0 or a)
end)
for _ = 1, 10 do WoW.tick(0.1) end
check(fade:GetAlpha() < 0.01, "a fade timed by GetTime() reaches 0 under ticks (alpha " .. fade:GetAlpha() .. ")")

-- Timers are still WoW.advance's: a tick runs none.
local fired = false
C_Timer.After(0.1, function() fired = true end)
WoW.tick(1)
check(not fired, "a tick runs no timer")
WoW.advance(0)
check(fired, "advance runs the timer the tick's clock made due")

-- A hidden frame's OnUpdate doesn't run, but the clock still moves.
f:Hide()
local before, t0 = #seen, GetTime()
WoW.tick(1)
eq(#seen, before, "a hidden frame's OnUpdate doesn't run")
eq(GetTime(), t0 + 1, "the clock moves anyway")

done("test_tick")
