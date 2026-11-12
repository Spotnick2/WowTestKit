-- One fresh-client case, run by tests/test_fresh_client.lua as its own process:
-- something goes wrong before the reload, and the file must still fail.
dofile("kit.lua")
Kit.load({ build = "70532" })
Kit.strict({})

local case = arg[1]
if case == "failbefore" then
    check(false, "before the reload")
elseif case == "straybefore" then
    print("off|watch")
elseif case == "methodbefore" then
    CreateFrame("Frame"):NotARealMethod()
end

dofile("kit.lua")
Kit.load({ build = "70532" })
Kit.strict({})
CreateFrame("Frame"):Show()
check(true, "after the reload")
if case == "methodbefore" then Kit.checkMethods() end
done("fresh_case " .. tostring(case))
