-- Kit.checkToc's version line (WowTestKit #84): the packager's token by
-- default, or the version an addon that's never packaged names. Each call's
-- failures are collected here instead of counted, so a case that must fail
-- doesn't fail this file.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local DIR = "tests/fixtures/"
local function failures(toc, opts)
    local real, failed = check, {}
    check = function(ok, msg) if not ok then failed[#failed + 1] = msg end end
    local ok, err = pcall(Kit.checkToc, toc, opts)
    check = real
    assert(ok, err)
    return table.concat(failed, " | ")
end

eq(failures("Fixture.toc", { dir = DIR }), "", "the token passes by default")
eq(failures("Dev.toc", { dir = DIR }), "Dev.toc: packager version token kept",
    "a TOC without the token fails by default")
eq(failures("Dev.toc", { dir = DIR, version = "dev" }), "", "version = \"dev\" passes on ## Version: dev")
eq(failures("Fixture.toc", { dir = DIR, version = "dev" }), "Fixture.toc: version dev",
    "version = \"dev\" fails on the token")
eq(failures("Dev.toc", { dir = DIR, version = "de" }), "Dev.toc: version de", "the whole line, not a prefix")
eq(failures("Dev.toc", { dir = DIR, version = "d.v" }), "Dev.toc: version d.v", "as written, not a pattern")

done("test_toc")
