-- WowTestKitProbe on the kit (local only: ForeverProbe is private, so CI,
-- which runs tests\test_*.lua, never sees this folder). From the repo root:
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\probe\test_probe.lua
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- loadForeverProbe(), as GlassChat/tests/harness.lua does it (ForeverProbe's guide, section 8).
local function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only)\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
end

-- Client globals the kit leaves to the consumer's stub.
SlashCmdList = {}
function GetBuildInfo() return "1.60.1", "70959", "Nov 18 2026", 16001 end
loadForeverProbe()
local ns = {}
assert(loadfile("tools/WowTestKitProbe/WowTestKitProbe.lua"))("WowTestKitProbe", ns)
WoW.fire("ADDON_LOADED", "WowTestKitProbe")
check(type(WowTestKitProbeDB) == "table" and type(WowTestKitProbeDB.log) == "table", "the module binds its saved log")

SlashCmdList.FOREVERPROBE("tk reparent")
local results = ns._test.results()
local n = 0
for label, line in pairs(results) do
    n = n + 1
    check(not line:find("THREW", 1, true) and not line:find("read threw", 1, true), label .. " ran: " .. line)
end
check(n == 17, "every case recorded (" .. n .. ")")
eq(WowTestKitProbeDB.reparent, results, "the results are saved")
eq(#WoW.chat, 0, "nothing goes to chat")

-- The procedure starts, and its Alt+Z case runs with UIParent hidden.
SlashCmdList.FOREVERPROBE("steps tk reparent")
UIParent:Hide()
check(ns._test.hiddenUI():find("UIParent shown=false", 1, true), "the Alt+Z case sees UIParent hidden")
UIParent:Show()
for _, label in ipairs({ "u1 U: nil -> UIParent (hidden by Alt+Z)", "u2 U: UIParent (hidden) -> nil" }) do
    check(results[label] and not results[label]:find("THREW", 1, true), label .. " ran")
end

if os.getenv("PROBE_VERBOSE") then
    for label, line in pairs(results) do io.write(label, ": ", line, "\n") end
end
done("test_probe")
