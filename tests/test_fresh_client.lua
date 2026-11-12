-- A fresh client mid-test keeps the assertions' counts, the strays and the
-- methods called (WowTestKit #8). The failing cases run as their own Lua
-- process, from tests/fixtures/fresh_case.lua.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local firstWoW, firstUI = WoW, UIParent
local firstTex = UIParent:CreateTexture("KitFirstTexture")
rawset(_G, "KitAddonOwn", firstTex)   -- a global the addon set itself, to the same widget
WoW.secretBlocked = 2   -- as the core counts them once it does (#13)
local f = CreateFrame("Frame", "KitFirstLogin", UIParent)
Kit.strict({})
f:SetPoint("CENTER")   -- the addon's call, after Kit.strict
check(true, "a check before the reload")
local p0 = Kit.counts()

-- The consumer's stub loaded again: kit.lua again, then Kit.load again.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })
check(WoW ~= firstWoW, "a new WoW table")
check(UIParent ~= firstUI, "a new UIParent")
eq(rawget(_G, "KitFirstLogin"), nil, "the old client's named frame is no longer a global (#45)")
eq(rawget(_G, "KitFirstTexture"), nil, "nor its named texture")
eq(rawget(_G, "KitAddonOwn"), firstTex, "a global the core didn't set is left alone")
eq(#WoW.frames, 0, "no frames from the first client")
eq(rawget(_G, "KitNotDefinedYet"), nil, "strict globals are off until the stub calls Kit.strict")
local ok = pcall(function() return KitNotDefinedYet end)
check(ok, "so a read of an undefined global doesn't throw yet")
eq(WoW.secretBlocked, 2, "a count of swallowed secret touches carries over")
WoW.secretBlocked = 0   -- (set by hand above; nothing was touched)
local p1 = Kit.counts()
check(p1 >= p0 + 4, "the counts carried on (" .. p0 .. " before, " .. p1 .. " now)")
check(not pcall(Kit.load, { build = "70790" }), "a second Kit.load for another build throws")

local g = CreateFrame("Frame")
g:SetSize(1, 1)        -- the stub building this client: forgotten by Kit.strict
Kit.strict({})
g:Show()
eq(Kit.checkMethods(), 2, "checkMethods sees the first client's call (Frame:SetPoint) and this one's (Frame:Show)")

-- The failing cases.
local lua = arg[-1] or "lua"
local windows = package.config:sub(1, 1) == "\\"
local function run(case)
    local cmd = '"' .. lua .. '" tests/fixtures/fresh_case.lua ' .. case .. " 2>&1"
    if windows then cmd = '"' .. cmd .. '"' end
    local p = assert(io.popen(cmd))
    local out = p:read("*a")
    p:close()
    return out
end
local out = run("failbefore")
check(out:find("FAIL: before the reload", 1, true) and out:find("fresh_case failbefore: %d+ passed, 1 failed"),
    "a failure before the reload still fails the file\n" .. out)
out = run("straybefore")
check(out:find("no stray | in any printed line: off|watch", 1, true), "a stray printed before the reload still fails done()\n" .. out)
out = run("methodbefore")
check(out:find("method exists on Forever 70532: Frame:NotARealMethod", 1, true),
    "a bad method called before the reload still fails checkMethods\n" .. out)

done("test_fresh_client")
