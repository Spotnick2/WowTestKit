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

-- The dump's _G walk ran with addons loaded, so their globals are in it.
-- Dropped: <Addon>_... for each addon listed in tools/loaded-addons.txt, and
-- any *_OnAddonCompartment* handler (a TOC's AddonCompartmentFunc, never
-- Blizzard's).
local addons = {}
local here = (arg[0]:match("^(.*)[/\\][^/\\]*$") or ".")
for l in io.lines(here .. "/loaded-addons.txt") do
    l = l:gsub("\r$", ""):gsub("%s+$", "")
    if l ~= "" and not l:match("^#") then addons[#addons + 1] = l end
end
-- Other loaded addons' globals are listed beside the dumps, outside this repo,
-- in addon-globals.txt: an exact name or a Prefix* on each line. Third-party
-- addons are never named here; without that file, nothing more is dropped.
local exact, prefixes, listFile = {}, {}, nil
do
    local dumpDir = dump:match("^(.*)[/\\][^/\\]*$") or "."
    local path = dumpDir .. "/addon-globals.txt"
    local lf = io.open(path, "r")
    if lf then
        listFile = path
        for l in lf:lines() do
            l = l:gsub("\r$", ""):gsub("%s+$", ""):gsub("^%s+", "")
            if l ~= "" and not l:match("^#") then
                local p = l:match("^(.-)%*$")
                if p then prefixes[#prefixes + 1] = p else exact[l] = true end
            end
        end
        lf:close()
    end
end

local function addonOwned(name)
    if name:find("_OnAddonCompartment", 1, true) then return true end
    for _, a in ipairs(addons) do
        if name:sub(1, #a + 1) == a .. "_" then return true end
    end
    if exact[name] then return true end
    for _, p in ipairs(prefixes) do
        if name:sub(1, #p) == p then return true end
    end
end
local dropped = 0

local sets = { documented = {}, events = {}, widgets = {}, globals = {}, namespaces = {}, subtypes = {} }
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
        -- "Name(args) -> ret  [System]". A Simple*API system is a script
        -- object's (a widget's): its functions are methods, never globals.
        -- The animation subtypes' own methods are only here (the widget walk
        -- lists Animation alone): [SimpleAnimAlphaAPI] SetFromAlpha is
        -- Alpha:SetFromAlpha.
        local name = line:match("^([%a_][%w_.]*)%(")
        local system = line:match("%[([%w_]+)%]%s*$")
        if name and system and system:match("^Simple%w*API$") then
            local sub = system:match("^SimpleAnim(%w+)API$")
            if sub and sub ~= "Group" and sub ~= "atableObject" then sets.subtypes[sub .. ":" .. name] = true end
        elseif name then
            sets.documented[name] = true
        end
    elseif section == "events" then
        local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
        if name then sets.events[name] = true end
    elseif section == "widgets" then
        local pair = line:match("^(%a+:[%w_]+)%s*$")
        if pair then sets.widgets[pair] = true end
    elseif section == "globals" then
        local name = line:match("^([%a_][%w_]*)%s*$")
        if name then
            if addonOwned(name) then dropped = dropped + 1 else sets.globals[name] = true end
        end
    elseif section == "namespaces" then
        local name = line:match("^([%a_][%w_]*%.[%w_]+)%s*$")
        if name then sets.namespaces[name] = true end
    end
end
f:close()

for k, s in pairs(sets) do
    assert(next(s), "no entries read from the dump's section for " .. k .. ": has its format changed?")
end

for pair in pairs(sets.subtypes) do sets.widgets[pair] = true end

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
io.write(string.format("dropped %d addon globals from the _G walk (tools/loaded-addons.txt%s)\n",
    dropped, listFile and (", " .. listFile) or "; no addon-globals.txt beside the dump"))
