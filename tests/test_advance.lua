-- WoW.advance runs each due timer with the clock at its due time, in due
-- order, then moves the clock to the end of the advance (WowTestKit #86). On
-- the client a C_Timer.After(2, fn) runs at about 2 s, and GetTime() inside it
-- reads that. GuildSpy#68: a scan stamped inside a debounce timer.
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- A timer reads its due time, not the advance's end.
WoW.now = 0
local seen
C_Timer.After(2, function() seen = GetTime() end)
WoW.advance(4)
eq(seen, 2, "a 2 s timer inside advance(4) reads 2 from GetTime()")
eq(GetTime(), 4, "then the clock is at the advance's end")

-- In due order, each at its own time, whatever order they were made in.
WoW.reset()
WoW.now = 10
local log = {}
C_Timer.After(3, function() log[#log + 1] = "b@" .. GetTime() end)
C_Timer.After(1, function() log[#log + 1] = "a@" .. GetTime() end)
WoW.advance(5)
eq(table.concat(log, " "), "a@11 b@13", "two timers run in due order, each at its due time")

-- A chain: a timer made inside one counts from that one's due time.
WoW.reset()
WoW.now = 0
local chain = {}
C_Timer.After(1, function()
    chain[#chain + 1] = GetTime()
    C_Timer.After(1, function()
        chain[#chain + 1] = GetTime()
        C_Timer.After(1, function() chain[#chain + 1] = GetTime() end)
    end)
end)
WoW.advance(5)
eq(table.concat(chain, ","), "1,2,3", "a chain of 1 s timers runs at 1, 2 and 3 in one advance(5)")

-- One that doesn't fall due inside the advance waits for its own time.
WoW.reset()
WoW.now = 0
local late
C_Timer.After(3, function() C_Timer.After(3, function() late = GetTime() end) end)
WoW.advance(4)
eq(late, nil, "a timer made at 3 for 3 s isn't due at 4")
WoW.advance(1.5)
eq(late, nil, "nor at 5.5")
WoW.advance(0.5)
eq(late, 6, "it runs at 6, three seconds after the timer that made it")

-- A ticker reads each period's time.
WoW.reset()
WoW.now = 0
local ticks = {}
local ticker = C_Timer.NewTicker(1, function() ticks[#ticks + 1] = GetTime() end)
WoW.advance(3.5)
eq(table.concat(ticks, ","), "1,2,3", "a 1 s ticker in advance(3.5) reads 1, 2 and 3")
ticker:Cancel()

-- A 0-second ticker fires once per advance (#76), first thing, with the clock
-- where the advance started: it is due from the time it last fired.
WoW.reset()
WoW.now = 0
local zero = {}
local z = C_Timer.NewTicker(0, function() zero[#zero + 1] = GetTime() end)
WoW.advance(1)
WoW.advance(1)
WoW.advance(0)
eq(table.concat(zero, ","), "0,1,2", "a 0-second ticker reads each advance's start")
z:Cancel()

-- An overdue timer runs at now: the clock never goes back.
WoW.reset()
WoW.now = 0
local overdue
C_Timer.After(1, function() overdue = GetTime() end)
WoW.tick(5)   -- a tick runs no timer
WoW.advance(0)
eq(overdue, 5, "a timer the clock passed runs at now, not back at its due time")

-- A callback that advances the clock itself: it never goes back.
WoW.reset()
WoW.now = 0
C_Timer.After(1, function() WoW.advance(10) end)
WoW.advance(2)
eq(GetTime(), 11, "the outer advance doesn't move the clock back from a nested one")

-- WoW.step follows: the timer at its due time, OnUpdate at the step's end.
WoW.reset()
WoW.now = 0
local order = {}
C_Timer.After(0.1, function() order[#order + 1] = "timer@" .. GetTime() end)
local f = CreateFrame("Frame", nil, UIParent)
f:SetScript("OnUpdate", function(_, elapsed) order[#order + 1] = "update@" .. GetTime() .. "+" .. elapsed end)
WoW.step(0.25)
eq(table.concat(order, " "), "timer@0.1 update@0.25+0.25", "step runs the timer at its due time, then OnUpdate at the step's end")

done("test_advance")
