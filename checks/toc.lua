-- checks/toc.lua: what every addon TOC must get right. A repo's own test_toc
-- calls it, then checks what is its own (IDs, load order, libraries).
--
--   Kit.checkToc("GlassChat.toc", { interface = 16001, dir = "" })

function Kit.checkToc(toc, opts)
    opts = opts or {}
    local dir = opts.dir or ""
    local f = assert(io.open(dir .. toc, "rb"), "TOC not found: " .. dir .. toc)
    local text = f:read("*a")
    f:close()
    local interface = tostring(opts.interface or 16001)
    check(text:find("## Interface: " .. interface .. "\r?\n") or text:find("## Interface: " .. interface .. "$"),
        toc .. ": interface " .. interface .. (interface == "16001" and " (1.60.1; 11601 is the transposed-digit bug)" or ""))
    check(text:find("## Version: @project-version@", 1, true), toc .. ": packager version token kept")
    local seen = {}
    for _, line in ipairs(Kit.tocLines(dir .. toc)) do
        local path = dir .. line:gsub("\\", "/")
        if line:match("%.lua$") then
            local lf = io.open(path, "rb")
            check(lf ~= nil, toc .. ": listed file exists: " .. line)
            if lf then lf:close() end
        end
        check(not seen[line], toc .. ": lists each file once: " .. line)
        seen[line] = true
    end
end

-- The client globals the stub core defines are in the selected build (the
-- core must never define something Forever lacks), and the WoW test table
-- doesn't shadow a client name.
function Kit.checkCore()
    local globals = Kit.data("globals")
    for _, name in ipairs(Kit.CORE_GLOBALS) do
        check(globals[name], "the core's " .. name .. " is a client global in " .. Kit.BUILD)
        check(rawget(_G, name) ~= nil, "the core defines " .. name)
    end
    for name, source in pairs(Kit.CORE_FRAMEXML) do
        check(rawget(_G, name) ~= nil and source ~= "", "the core's FrameXML " .. name .. " (" .. source .. ")")
    end
    check(not globals.WoW and not globals.Kit, "WoW and Kit are not client globals")
end
