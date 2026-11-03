-- core/toc.lua: reading a TOC the way the client does.

-- Every file line of a TOC, in load order: no blank lines, no "#" lines, as
-- written (backslashes kept: a library's XML line is compared as written).
function Kit.tocLines(toc)
    local lines = {}
    for line in io.lines(toc) do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- The Lua files of a TOC, in load order, as paths ("/" separators, so they
-- open on Linux too). dir: the folder the TOC is in, prefixed to each file
-- ("" or nil for the repo root).
function Kit.tocFiles(toc, dir)
    dir = dir or ""
    local files = {}
    for _, line in ipairs(Kit.tocLines(dir .. toc)) do
        if line:match("%.lua$") then files[#files + 1] = dir .. line:gsub("\\", "/") end
    end
    return files
end
