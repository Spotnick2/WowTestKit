-- A blocked operation on a secret that a pcall swallowed is counted, and
-- done() fails on one (WowTestKit #13). The failing case runs as its own Lua
-- process (check() counts toward the file it runs in).
dofile("kit.lua")
Kit.load({ build = "70532" })

local s = WoW.Secret("UnitHealth")
eq(WoW.secretBlocked, 0, "nothing counted at the start")

check(not pcall(function() return s + 1 end), "arithmetic on a secret throws")
eq(WoW.secretBlocked, 1, "a metamethod touch a pcall caught is counted")
check(WoW.secretBlockedFirst:find("UnitHealth", 1, true), "the first one's message is kept")
check(not pcall(function() return s > 0 end), "ordering a secret against a number throws")
eq(WoW.secretBlocked, 2, "Lua's own compare error (no metamethod) is counted too")
check(not pcall(function() return 0 < s end), "and the other way round")
check(not pcall(function() return s < "x" end), "and against a string")
eq(WoW.secretBlocked, 4, "both orders and a string count")
local handled
check(not xpcall(function() return s .. "" end, function(e) handled = e; return e end), "xpcall catches a touch")
eq(WoW.secretBlocked, 5, "xpcall counts it")
check(handled and handled:find("secret value touched", 1, true), "and still hands the error to its handler")

check(not pcall(string.format, "%s", s), "string.format on a secret throws")
eq(WoW.secretBlocked, 6, "and is counted (Lua's own argument check names no secret)")
check(not pcall(function() return ("%d"):format(s) end), "the method form too")
eq(WoW.secretBlocked, 7, "is counted")
eq(string.format("%s-%d", "a", 1), "a-1", "string.format still formats plain values")
WoW.secretBlocked = 5   -- the checks below count from here

-- Other errors aren't counted, and pcall's returns are unchanged.
check(not pcall(error, "plain"), "a plain error")
eq(WoW.secretBlocked, 5, "isn't counted")
local ok, a, b = pcall(function() return 1, 2 end)
check(ok and a == 1 and b == 2, "a successful pcall returns its values")
local ok2, err = pcall(error, { code = 7 })
check(not ok2 and type(err) == "table" and err.code == 7, "a table error passes through")
check(not WoW.rawpcall(function() return s + 1 end), "WoW.rawpcall catches")
eq(WoW.secretBlocked, 5, "without counting")

-- The core run again (a fresh client) wraps Lua's pcall, not its own.
dofile(Kit.ROOT .. "/core/stubs.lua")
local again = WoW.Secret("again")
pcall(function() return again + 1 end)
eq(WoW.secretBlocked, 1, "after the core runs again, one touch counts once")
eq(Kit.rawpcall, WoW.rawpcall, "and WoW.rawpcall is still Lua's own")

WoW.reset()
eq(WoW.secretBlocked, 0, "WoW.reset clears the count")
eq(WoW.secretBlockedFirst, nil, "and the message")

-- done() fails a file with a counted touch.
local lua = arg[-1] or "lua"
local windows = package.config:sub(1, 1) == "\\"
local case = os.tmpname()
if windows then case = (os.getenv("TEMP") or ".") .. "\\wowtestkit-" .. case:gsub("[\\/.]", "") .. ".lua" end
local f = assert(io.open(case, "w"))
f:write('dofile("kit.lua")\nKit.load({ build = "70532" })\n',
        'local s = WoW.Secret("UnitPower")\n',
        'pcall(string.format, "%s", s)\n',
        'done("secret_case")\n')
f:close()
local cmd = '"' .. lua .. '" "' .. case .. '" 2>&1'
if windows then cmd = '"' .. cmd .. '"' end
local p = assert(io.popen(cmd))
local out = p:read("*a")
p:close()
os.remove(case)
check(out:find("each is a taint.log line", 1, true) and out:find("UnitPower", 1, true),
    "done() names the swallowed touch\n" .. out)
check(out:find("secret_case: %d+ passed, 1 failed"), "and the file fails\n" .. out)

done("test_secret_pcall")
