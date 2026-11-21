-- The calendar clock (WowTestKit #103): time() reads WoW.epoch, which moves
-- with WoW.now wherever the core moves it. GuildSpy's scanner stamps its
-- observations with time() inside a debounce timer.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local listed = false
for _, name in ipairs(Kit.CORE_GLOBALS) do listed = listed or name == "time" end
check(listed, "time is in Kit.CORE_GLOBALS, so checkCore checks it against the build")
Kit.checkCore()

eq(WoW.epoch, 1790000000, "the calendar clock starts at 1790000000")
eq(time(), 1790000000, "and time() reads it")
local t = { year = 2026, month = 11, day = 20, hour = 12 }
eq(time(t), os.time(t), "time(t) is os.time(t)")

-- A test sets it directly, and reads it outside an advance.
WoW.epoch = WoW.epoch + 3600
eq(time(), 1790003600, "a test moves it (a login an hour later)")
WoW.now = 0
eq(time(), 1790003600, "setting WoW.now leaves it alone")

-- WoW.advance: each timer reads its due time from both clocks.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
eq(WoW.epoch, 1000, "WoW.reset leaves it alone, as it does WoW.now")
local seen = {}
C_Timer.After(2, function() seen[#seen + 1] = GetTime() .. "/" .. time() end)
C_Timer.After(3, function()
    seen[#seen + 1] = GetTime() .. "/" .. time()
    C_Timer.After(1, function() seen[#seen + 1] = GetTime() .. "/" .. time() end)
end)
WoW.advance(5)
eq(table.concat(seen, " "), "2/1002 3/1003 4/1004", "a timer inside advance(5) reads its due time from time() too")
eq(time(), 1005, "then time() is at the advance's end")
eq(WoW.epoch - WoW.now, 1000, "the two clocks moved together")

-- An advance inside a timer moves both, and the outer one doesn't move them twice.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
C_Timer.After(1, function() WoW.advance(10) end)
WoW.advance(2)
eq(GetTime(), 11, "an advance inside a timer goes past the outer one's end")
eq(time(), 1011, "and time() with it")

-- An overdue timer runs at the current time: neither clock goes back.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
C_Timer.After(1, function() end)
WoW.now = 5   -- moves GetTime() only
WoW.advance(1)
eq(time(), 1001, "an overdue timer doesn't move the calendar clock back")

-- It stays whole seconds: the core carries the fraction.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
local stamped
C_Timer.After(2.5, function() stamped = time() end)
WoW.advance(3.5)
eq(stamped, 1002, "a timer due at 2.5 s reads 1002")
eq(WoW.epoch, 1003, "WoW.epoch stays whole: 3.5 s in, it reads 1003")
WoW.advance(0.5)
eq(time(), 1004, "and the half second carried makes 1004 with the next half")
eq(WoW.epoch, time(), "time() is WoW.epoch")

-- WoW.tick and WoW.step move it by their elapsed.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
WoW.tick(0.5)
eq(WoW.epoch, 1000, "half a second's tick: still 1000")
for _ = 1, 25 do WoW.tick() end
eq(WoW.epoch, 1001, "half a second and 25 ticks of 0.02 s make 1001")
local f = CreateFrame("Frame", nil, UIParent)
local inUpdate
f:SetScript("OnUpdate", function() inUpdate = time() end)
WoW.step(2)
eq(time(), 1003, "a step moves it once")
eq(inUpdate, 1003, "and OnUpdate reads it moved")

-- A test that sets it starts from that second: the fraction carried goes.
WoW.reset()
WoW.now, WoW.epoch = 0, 1000
WoW.tick(0.75)
WoW.epoch = 2000
WoW.tick(0.5)
eq(time(), 2000, "set by a test, it doesn't carry the 0.75 s from before")
WoW.tick(0.5)
eq(time(), 2001, "and counts from there")

-- Float drift: ten 0.1 s add up to 0.9999999999999999, and still make a second.
WoW.now, WoW.epoch = 0, 3000
for _ = 1, 10 do WoW.tick(0.1) end
eq(time(), 3001, "ten 0.1 s ticks are a second, past the float drift")

done("test_clock")
