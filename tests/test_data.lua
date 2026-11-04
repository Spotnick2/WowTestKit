-- The data lists: every build has its four, with provenance; and where the
-- dump is on this disk (the owner's machine, not CI), they are exactly what
-- tools/gen_data.lua makes from it.
dofile("kit.lua")
Kit.load({ build = "70532" })

local FILES = { "widget-methods.txt", "functions.txt", "globals.txt", "events.txt" }
local builds = Kit.builds()
check(#builds >= 1, "the kit has data for at least one build")

local function lines(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local all = {}
    for l in f:lines() do all[#all + 1] = (l:gsub("\r$", "")) end
    f:close()
    return all
end

local DUMPS = os.getenv("WOWTESTKIT_DUMPS") or "C:/Projects/WoW/References/Forever/api"
local compared = 0
for _, build in ipairs(builds) do
    for _, file in ipairs(FILES) do
        local path = "data/forever-" .. build .. "/" .. file
        local l = lines(path)
        check(l and #l > 100, path .. " exists and has entries")
        if l then
            check(l[2] and l[2]:find("^# build " .. build .. ", from forever%-api%-[%d.]+%." .. build .. "%.md by tools/gen_data.lua"),
                path .. " names its build and generator")
        end
    end
    -- No loaded addon's globals; the animation subtypes' own methods are in.
    local globals = lines("data/forever-" .. build .. "/globals.txt") or {}
    local suspects = {}
    for _, g in ipairs(globals) do
        if g:find("_OnAddonCompartment", 1, true) or g:match("^Glass") then suspects[#suspects + 1] = g end
    end
    eq(#suspects, 0, build .. ": no addon globals in globals.txt (add the addon to tools/loaded-addons.txt): "
        .. table.concat(suspects, " "):sub(1, 200))
    local methods = table.concat(lines("data/forever-" .. build .. "/widget-methods.txt") or {}, "\n")
    check(methods:find("\nAlpha:SetFromAlpha\n", 1, true), build .. ": Alpha:SetFromAlpha (SimpleAnimAlphaAPI)")
    check(methods:find("\nScale:SetScaleFrom\n", 1, true), build .. ": Scale:SetScaleFrom (SimpleAnimScaleAPI)")
    -- Regenerate from the dump when it's here, and compare.
    local dump
    local p = io.popen(package.config:sub(1, 1) == "\\"
        and ('dir /b "' .. DUMPS:gsub("/", "\\") .. '\\forever-api-*.' .. build .. '.md" 2>nul')
        or ("ls '" .. DUMPS .. "' 2>/dev/null | grep '\\." .. build .. "\\.md$'"))
    if p then dump = p:read("*l"); p:close() end
    if dump and dump ~= "" then
        local tmp = os.tmpname():gsub("\\", "/")
        os.remove(tmp)
        local lua = arg[-1] or "lua"
        local cmd = '"' .. lua .. '" tools/gen_data.lua "' .. DUMPS .. "/" .. dump .. '" "' .. tmp .. '"'
        if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. ' >nul"' else cmd = cmd .. " >/dev/null" end
        os.execute(cmd)
        for _, file in ipairs(FILES) do
            local a, b = lines("data/forever-" .. build .. "/" .. file), lines(tmp .. "/forever-" .. build .. "/" .. file)
            check(b and #a == #b and table.concat(a, "\n") == table.concat(b, "\n"),
                "data/forever-" .. build .. "/" .. file .. " is what the generator makes from " .. dump)
        end
        compared = compared + 1
    end
end
io.write(("test_data: compared %d of %d builds with their dump%s\n"):format(compared, #builds,
    compared == 0 and " (no dumps on this machine: CI)" or ""))
done("test_data")
