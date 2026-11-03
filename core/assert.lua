-- core/assert.lua: check / eq / done. One test file is one Lua process; done()
-- prints its counts and exits with them.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

-- Prints "<name>: N passed, M failed" (the runners and the migration
-- comparison read that line) and exits. Every line printed during the test
-- is checked for a stray "|" first (core/stubs.lua's print).
function done(name)
    local strays = WoW and WoW.strays or {}
    eq(#strays, 0, "no stray | in any printed line" .. (strays[1] and (": " .. strays[1]) or ""))
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- A test that can't run here says so on one line and exits cleanly. The
-- runners count SKIPPED lines, so a skip is visible, never silent.
function Kit.skip(name, why)
    io.write(string.format("%s: SKIPPED (%s)\n", name, why))
    os.exit(0)
end

function Kit.counts() return passed, failed end
