-- kit.lua: WowTestKit's entry point. A consumer's tests/kit.lua (the bootstrap,
-- bootstrap/kit.lua here) dofiles this, then calls Kit.load.
--
--   dofile(dir .. "/kit.lua")
--   Kit.load({ build = "70532", sha = "<pinned commit>" })
--
-- Kit.load defines, as globals: the assertions (check, eq, done), the WoW
-- table and the stub core (CreateFrame, UIParent, print, timers, events, ...).
-- The consumer's own stub then adds its client APIs and overrides any
-- WoW.Methods entry, and ends with Kit.strict(allowNil).
--
-- A FRESH CLIENT mid-test (a second login with other saved settings): load
-- the consumer's stub again. This file then keeps the kit already loaded, and
-- the second Kit.load (same build) is Kit.freshClient(): the stub core is
-- rebuilt and the assertions' counts carry on (WowTestKit #8).

-- Already loaded in this process: keep it, with its counts.
if rawget(_G, "Kit") and rawget(Kit, "BUILD") then return Kit end

Kit = {
    API = 2,   -- bumped on a breaking change; Kit.load refuses an older consumer's api
               -- (docs/MIGRATING.md: what each bump changes, and how to move)
    ROOT = (debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."):gsub("\\", "/"),
}

local loaded = false

-- opts.build: the client build whose API lists to test against (required).
-- opts.api: the Kit.API the consumer was written for (default 1).
-- A second call with the same build is Kit.freshClient().
function Kit.load(opts)
    opts = opts or {}
    if loaded then
        if opts.build and tostring(opts.build) ~= Kit.BUILD then
            error(("Kit.load: already loaded for build %s, now asked for %s: one build per test file")
                :format(Kit.BUILD, tostring(opts.build)), 2)
        end
        return Kit.freshClient()
    end
    loaded = true
    assert(opts.build, "Kit.load needs { build = \"<build>\" } (tests/kit.pin's build)")
    local api = tonumber(opts.api) or 1
    if api ~= Kit.API then
        error(("WowTestKit API %d, but this repo was written for API %d: pin a kit commit for API %d, "
            .. "or migrate (WowTestKit's docs/MIGRATING.md) and set api=%d in tests/kit.pin")
            :format(Kit.API, api, api, Kit.API), 0)
    end
    Kit.BUILD, Kit.SHA = tostring(opts.build), opts.sha
    for _, file in ipairs({ "core/assert.lua", "core/toc.lua", "core/data.lua", "core/stubs.lua",
                            "checks/methods.lua", "checks/toc.lua" }) do
        dofile(Kit.ROOT .. "/" .. file)
    end
    return Kit
end

-- A fresh client in the same test file: the stub core is built again (a new
-- WoW, UIParent, CreateFrame..., strict globals off until the consumer's stub
-- calls Kit.strict again). What carries over: the assertions and their
-- counts (check / eq / done are loaded once), the stray "|" lines printed so
-- far (done() still fails on one), the widget methods called so far
-- (Kit.checkMethods still checks them), and the count of secret touches a
-- pcall swallowed, when the core keeps one (done() still fails on it).
-- What doesn't: the old client's named widgets. Each global the core set for
-- one is removed while it still names that widget, so an addon's
-- `if not MyFrame then` makes it again (#45).
function Kit.freshClient()
    assert(loaded, "Kit.freshClient: call Kit.load first")
    local strays, called = WoW.strays, WoW.methodsCalled
    local secretBlocked, secretFirst = WoW.secretBlocked, WoW.secretBlockedFirst
    Kit.earlierMethodsCalled = Kit.earlierMethodsCalled or {}
    for pair in pairs(called) do Kit.earlierMethodsCalled[pair] = true end
    setmetatable(_G, nil)
    for name, w in pairs(WoW.published or {}) do
        if rawget(_G, name) == w then rawset(_G, name, nil) end
    end
    dofile(Kit.ROOT .. "/core/stubs.lua")
    for _, line in ipairs(strays) do table.insert(WoW.strays, line) end
    if secretBlocked then
        WoW.secretBlocked = (WoW.secretBlocked or 0) + secretBlocked
        WoW.secretBlockedFirst = WoW.secretBlockedFirst or secretFirst
    end
    return Kit
end
