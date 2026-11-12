-- C_Timer.NewTicker repeats, honours iterations, and hands its callback the
-- ticker (WowTestKit #18; UITimerDocumentation, dump 70450:
-- NewTicker(seconds, callback, optional iterations) -> cbObject).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

WoW.now = 0

-- Under advance: once per period, and the callback gets the handle.
local fired, got = 0, nil
local ticker = C_Timer.NewTicker(1, function(t) fired = fired + 1; got = t end)
check(type(ticker.Cancel) == "function" and type(ticker.IsCancelled) == "function", "the handle has Cancel and IsCancelled")
eq(ticker:IsCancelled(), false, "a new ticker isn't cancelled")
WoW.advance(1)
eq(fired, 1, "it fires when due")
eq(got, ticker, "and passes the ticker to its callback")
WoW.advance(1)
eq(fired, 2, "it fires again a period later")
WoW.advance(3)
eq(fired, 5, "an advance spanning three periods fires it three times")
WoW.advance(0.5)
eq(fired, 5, "not before the next period")
ticker:Cancel()
eq(ticker:IsCancelled(), true, "Cancel makes IsCancelled true")
WoW.advance(10)
eq(fired, 5, "a cancelled ticker stops")
eq(#WoW.timers, 0, "and leaves WoW.timers")

-- Under flushTimers: run once and kept.
WoW.reset()
WoW.now = 0
local n = 0
C_Timer.NewTicker(1, function() n = n + 1 end)
WoW.flushTimers()
eq(n, 1, "flushTimers runs a ticker once")
eq(#WoW.timers, 1, "and keeps it")
WoW.flushTimers()
eq(n, 2, "a later flush runs it again (the client never drops a live ticker)")
WoW.advance(0.5)
eq(n, 2, "flushTimers re-armed it from now: not due half a period later")
WoW.advance(0.5)
eq(n, 3, "due a period after the flush")

-- Iterations.
WoW.reset()
WoW.now = 0
local k = 0
C_Timer.NewTicker(1, function() k = k + 1 end, 3)
WoW.advance(10)
eq(k, 3, "iterations = 3 fires it three times")
eq(#WoW.timers, 0, "then it's gone")
local f2 = 0
C_Timer.NewTicker(1, function() f2 = f2 + 1 end, 2)
WoW.flushTimers(); WoW.flushTimers(); WoW.flushTimers()
eq(f2, 2, "flushTimers honours iterations too")

-- A ticker cancelled from its own callback.
WoW.reset()
WoW.now = 0
local c = 0
C_Timer.NewTicker(1, function(t) c = c + 1; if c == 2 then t:Cancel() end end)
WoW.advance(10)
eq(c, 2, "a Cancel from inside the callback holds")

-- A cancelled ticker leaves WoW.timers at the next flush, due or not.
WoW.reset()
C_Timer.NewTicker(60, function() end):Cancel()
WoW.flushTimers(1)
eq(#WoW.timers, 0, "flushTimers drops a cancelled ticker that isn't due")

-- A 0-second ticker fires once per advance, never forever. (Without the
-- guard, advance loops forever: the mutation test hangs.)
WoW.reset()
WoW.now = 0
local z = 0
C_Timer.NewTicker(0, function() z = z + 1 end)
WoW.advance(1)
WoW.advance(1)
eq(z, 2, "a 0-second ticker fires once per advance")

-- Timers are unchanged: run once and dropped, with no argument.
WoW.reset()
WoW.now = 0
local args
C_Timer.After(1, function(...) args = select("#", ...) end)
WoW.advance(1)
eq(args, 0, "a C_Timer.After callback gets no argument")
eq(#WoW.timers, 0, "and is dropped")

-- A ticker-shaped record a stub made itself (GlassChat's own NewTicker:
-- { s, fn, every }, no at or handle) runs once and is dropped (#34).
WoW.reset()
WoW.now = 0
local own = 0
table.insert(WoW.timers, { s = 1, fn = function() own = own + 1 end, every = 1 })
WoW.flushTimers()
eq(own, 1, "a stub's own ticker record runs under flushTimers")
eq(#WoW.timers, 0, "once, and is dropped")
table.insert(WoW.timers, { s = 1, fn = function() own = own + 1 end, every = 1 })
WoW.advance(5)
eq(own, 2, "under advance too, once")

done("test_ticker")
