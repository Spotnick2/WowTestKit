-- GetLocale: the client's locale code, driven by WoW.locale (WowTestKit #62).
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

eq(GetLocale(), "enUS", "GetLocale reads enUS until a test sets one")
WoW.locale = "deDE"
eq(GetLocale(), "deDE", "and the test's locale once set")
WoW.reset()
eq(GetLocale(), "enUS", "WoW.reset clears it")
local listed = false
for _, name in ipairs(Kit.CORE_GLOBALS) do listed = listed or name == "GetLocale" end
check(listed, "GetLocale is in Kit.CORE_GLOBALS, so checkCore checks it against the build")

done("test_locale")
