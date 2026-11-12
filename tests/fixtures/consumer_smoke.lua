-- A consumer's first test, as CI's "Consumer bootstrap" step runs it: the kit
-- comes in through tests/kit.lua and tests/kit.pin only.
dofile("tests/kit.lua")
eq(Kit.BUILD, "70532", "the pin's build is selected")
check(Kit.SHA and #Kit.SHA == 40, "the pin's commit is recorded")
local f = CreateFrame("Frame", nil, UIParent)
f:RegisterEvent("PLAYER_LOGIN")
Kit.strict({})
f:Show()
-- A fresh client, the way a consumer's stub loads again (WowTestKit #8):
-- the bootstrap runs again, and the counts and recorded calls carry on.
local before = Kit.counts()
dofile("tests/kit.lua")
check(Kit.counts() == before and #WoW.frames == 0, "the bootstrap again gives a fresh client, counts kept")
Kit.strict({})
eq(Kit.checkMethods(), 1, "the first client's Frame:Show is still checked")
done("test_smoke")
