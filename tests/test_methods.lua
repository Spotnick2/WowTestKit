-- Kit.checkMethods: passes on real pairs, fails closed on everything else.
-- The failing cases run as their own Lua process (check() counts toward the
-- file it runs in), from tests/fixtures/methods_case.lua.
dofile("kit.lua")
Kit.load({ build = "70532" })

local f = CreateFrame("Frame", nil, UIParent)
f:SetPoint("CENTER")
f:Show()
f:CreateTexture():SetAtlas("x")
f:CreateAnimationGroup():CreateAnimation("Alpha"):SetDuration(1)
-- Frame:SetPoint, Frame:Show, Frame:CreateTexture, Texture:SetAtlas,
-- Frame:CreateAnimationGroup, AnimationGroup:CreateAnimation, and Alpha:SetDuration
-- (checked as Animation's).
eq(Kit.checkMethods(), 7, "real pairs pass (7 recorded)")

-- Each case: (name, expected exit, a pattern its output must hold).
local lua = arg[-1] or "lua"
local windows = package.config:sub(1, 1) == "\\"
local function run(case)
    local cmd = '"' .. lua .. '" tests/fixtures/methods_case.lua ' .. case .. " 2>&1"
    if windows then cmd = '"' .. cmd .. '"' end   -- cmd.exe strips the outer pair
    local p = assert(io.popen(cmd))
    local out = p:read("*a")
    p:close()
    return out
end
for _, c in ipairs({
    { "nothing", "recorded the addon's widget method calls %(0%)" },
    { "missing", "method exists on Forever 70532: Frame:NotARealMethod" },
    { "wrongtype", "method exists on Forever 70532: Texture:RegisterEvent" },
    { "unknowntype", "widget type exists on Forever 70532: Gizmo:Show" },
    { "subtype", "Alpha:SetFromAlpha %(as Animation's; else allow it%)" },
    { "noreason", "allowed with a reason: Alpha:SetFromAlpha" },
}) do
    local out = run(c[1])
    check(out:find(c[2]), c[1] .. ": fails with " .. c[2] .. "\n" .. out)
    check(out:find("[1-9]%d* failed"), c[1] .. ": the case's file fails")
end
local ok = run("allowed")
check(ok:find("0 failed"), "an allowed subtype method with a reason passes\n" .. ok)

done("test_methods")
