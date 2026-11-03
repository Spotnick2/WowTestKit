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

Kit = {
    API = 1,   -- bumped on a breaking change; Kit.load refuses an older consumer's api
    ROOT = (debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."):gsub("\\", "/"),
}

local loaded = false

-- opts.build: the client build whose API lists to test against (required).
-- opts.api: the Kit.API the consumer was written for (default 1).
function Kit.load(opts)
    assert(not loaded, "Kit.load called twice")
    loaded = true
    opts = opts or {}
    assert(opts.build, "Kit.load needs { build = \"<build>\" } (tests/kit.pin's build)")
    local api = tonumber(opts.api) or 1
    if api ~= Kit.API then
        error(("WowTestKit API %d, but this repo was written for API %d: bump tests/kit.pin "
            .. "to a kit release for API %d, or migrate"):format(Kit.API, api, api), 0)
    end
    Kit.BUILD, Kit.SHA = tostring(opts.build), opts.sha
    for _, file in ipairs({ "core/assert.lua", "core/toc.lua", "core/data.lua", "core/stubs.lua",
                            "checks/methods.lua", "checks/toc.lua" }) do
        dofile(Kit.ROOT .. "/" .. file)
    end
    return Kit
end
