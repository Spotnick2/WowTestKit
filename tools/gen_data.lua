-- gen_data.lua: the kit's four API lists for one client build, from that
-- build's API dump (References\Forever\api\forever-api-<version>.<build>.md).
--
--   lua tools/gen_data.lua <dump.md> [outroot]      (outroot defaults to data)
--
-- Writes <outroot>/forever-<build>/:
--   widget-methods.txt  every Type:Method pair the client's widget metatables have
--   functions.txt       every callable: documented functions (not script-object
--                       methods), the _G walk's functions, every namespace's members
--   globals.txt         top-level names: the _G walk's functions and each
--                       namespace's root table (C_Timer, ...)
--   events.txt          every documented event name
--
-- Never the dump's "Namespace candidates": loaded addons show up there.
-- Each file starts with "#" lines naming the build and this generator.

local dump, outroot = arg[1], arg[2] or "data"
assert(dump, "usage: lua tools/gen_data.lua <dump.md> [outroot]")
local build = dump:match("forever%-api%-[%d.]-%.(%d+)%.md$")
assert(build, "the dump's file name must end forever-api-<version>.<build>.md: " .. dump)
local dumpName = dump:match("[^/\\]+$")

local SECTIONS = {
    ["Documented functions"] = "documented",
    ["Documented events"] = "events",
    ["Widget methods"] = "widgets",
    ["Global functions"] = "globals",
    ["Namespace functions"] = "namespaces",
}

local sets = { documented = {}, events = {}, widgets = {}, globals = {}, namespaces = {} }
local section
local f = assert(io.open(dump, "r"))
for line in f:lines() do
    line = line:gsub("\r$", "")
    local title = line:match("^## (.-) %(%d+%)%s*$")
    if title then
        section = SECTIONS[title]   -- nil for every section we don't read
    elseif line:match("^## ") then
        section = nil
    elseif section == "documented" then
        -- "Name(args) -> ret  [System]": a trailing [System] is a script
        -- object's method (a widget's), never callable as a global.
        local name = line:match("^([%a_][%w_.]*)%(")
        if name and not line:match("%[[%w_]+%]%s*$") then sets.documented[name] = true end
    elseif section == "events" then
        local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
        if name then sets.events[name] = true end
    elseif section == "widgets" then
        local pair = line:match("^(%a+:[%w_]+)%s*$")
        if pair then sets.widgets[pair] = true end
    elseif section == "globals" then
        local name = line:match("^([%a_][%w_]*)%s*$")
        if name then sets.globals[name] = true end
    elseif section == "namespaces" then
        local name = line:match("^([%a_][%w_]*%.[%w_]+)%s*$")
        if name then sets.namespaces[name] = true end
    end
end
f:close()

for k, s in pairs(sets) do
    assert(next(s), "no entries read from the dump's section for " .. k .. ": has its format changed?")
end

local functions, globals = {}, {}
for name in pairs(sets.documented) do functions[name] = true end
for name in pairs(sets.globals) do functions[name] = true; globals[name] = true end
for name in pairs(sets.namespaces) do
    functions[name] = true
    globals[name:match("^[^.]+")] = true
end
-- A documented global function with no namespace is a global too.
for name in pairs(sets.documented) do
    if not name:find(".", 1, true) then globals[name] = true end
end

local dir = outroot .. "/forever-" .. build
local function write(file, set, what)
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    local out = assert(io.open(dir .. "/" .. file, "wb"))
    out:write("# ", what, "\n")
    out:write("# build ", build, ", from ", dumpName, " by tools/gen_data.lua (never edit by hand)\n")
    for _, k in ipairs(list) do out:write(k, "\n") end
    out:close()
    io.write(string.format("%-20s %5d\n", file, #list))
end

-- os.execute's mkdir differs by OS; both forms tolerate an existing folder.
if package.config:sub(1, 1) == "\\" then
    os.execute('if not exist "' .. dir:gsub("/", "\\") .. '" mkdir "' .. dir:gsub("/", "\\") .. '"')
else
    os.execute("mkdir -p '" .. dir .. "'")
end
write("widget-methods.txt", sets.widgets, "Type:Method pairs off each widget type's metatable")
write("functions.txt", functions, "callable names: documented, the _G walk's, namespace members")
write("globals.txt", globals, "top-level names: the _G walk's functions and each namespace's root")
write("events.txt", sets.events, "documented event names")
