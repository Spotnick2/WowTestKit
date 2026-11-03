-- A consumer's first test, as CI's "Consumer bootstrap" step runs it: the kit
-- comes in through tests/kit.lua and tests/kit.pin only.
dofile("tests/kit.lua")
eq(Kit.BUILD, "70532", "the pin's build is selected")
check(Kit.SHA and #Kit.SHA == 40, "the pin's commit is recorded")
local f = CreateFrame("Frame", nil, UIParent)
f:RegisterEvent("PLAYER_LOGIN")
Kit.checkMethods()
Kit.strict({})
done("test_smoke")
