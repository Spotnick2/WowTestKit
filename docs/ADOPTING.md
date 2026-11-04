# Moving an addon onto WowTestKit

The README says how to use the kit. This guide is for an addon that already has tests and its
own copy of the mock (`tests/wow_stubs.lua`, a harness with `check` / `eq` / `done`, maybe an
`events-<build>.txt` fixture). It is what GlassChat and GlassPearls did, with what they ran into.

The rule for the whole move: **the tests must say the same thing before and after.** A count may
change only for a reason you can name. Step 2 proves it.

Not for: an addon targeting another client than WoW: Forever (the kit only has Forever data).

## 1. Before you change anything: the baseline

On the repo's `main`, record two things. Keep them outside the repo.

1. **Every test file's result line**, in order (`test_x: N passed, M failed`): run the repo's own
   test runner and keep its output.
2. **A load snapshot**: what the addon does when it loads, recorded by the stub. A throwaway
   script, run from the repo root, never committed:

   ```lua
   dofile("tests/wow_stubs.lua")
   dofile("tests/harness.lua")
   loadAddon()                                  -- however the harness loads the addon
   WoW.fireAllRegistered()
   WoW.tick()
   -- SlashCmdList.MYADDON(cmd) for each of its commands, then WoW.tick()

   local function dump(title, list, keepOrder)
       if not keepOrder then table.sort(list) end
       io.write("## " .. title .. " (" .. #list .. ")\n")
       for _, l in ipairs(list) do io.write(l .. "\n") end
   end
   local regs, named, methods, chat = {}, {}, {}, {}
   for _, w in ipairs(WoW.frames) do
       for e in pairs(w._events) do regs[#regs + 1] = (w._name or ("<" .. w._type .. ">")) .. " " .. e end
       if w._name then named[#named + 1] = w._type .. " " .. w._name end
   end
   for k in pairs(WoW.methodsCalled) do methods[#methods + 1] = k end
   for i, l in ipairs(WoW.chat) do chat[#chat + 1] = string.format("%04d %s", i, l) end
   dump("registered events", regs); dump("methods called", methods)
   dump("named frames", named); dump("chat lines", chat, true)
   ```

   Adapt the field names to the old stub's if they differ; the point is the same four lists from
   both stubs.

## 2. The move

Branch off `main`, from the repo's issue.

**Pin.** Copy `bootstrap/kit.lua`, `bootstrap/kit.ps1` and `bootstrap/fetch_kit.sh` into
`tests/` unchanged, and write `tests/kit.pin`: `sha=` the kit's current `main` commit (40 hex),
`build=` the build the addon was last measured on if it records one (a `MEASURED_ON_BUILD`, say),
otherwise the newest `data/forever-<build>/` here, and `api=1`.

**The stub.** `tests/wow_stubs.lua` starts with `dofile("tests/kit.lua")`, then
`local Methods = WoW.Methods`, and ends with `Kit.strict({ ... })`. In between:

- **Delete what the core does**: assertions, `CreateFrame` and the widget metatable, the method
  recorder, secrets, the event-name check and its `events-<build>.txt` fixture (and any env var
  pointing at the API dump), protected frames in combat, timers and the clock, `print`,
  `hooksecurefunc`, `fire` / `fireAllRegistered` / `tick`, the strict-globals block. The core's
  file, `core/stubs.lua`, is short; read it before deleting.
- **Keep the addon's own client APIs** (`C_*` tables, unit, bag, map functions...): they're not
  the kit's business.
- **Templates** move into `WoW.templates.<Name> = function(w, name) ... end`.
- **State the tests reset** goes in a function added to `WoW.onReset`.
- **A region type the core lacks** (`CreateLine`, ...): build it with `WoW.addRegion`.
- **A method that behaves differently from the core's** stays as a `Methods.X = ...` override
  only if a test relies on it, with a comment saying why. Prefer the core's behaviour: every one
  in it was measured on the client or read in Blizzard's source. GlassPearls ended with no
  override; GlassChat kept six.
- **A method the core doesn't have** stays in the local stub as a `Methods` entry. If other addons
  would want it, open an issue here.
- Build everything before `Kit.strict`: it also forgets the method calls the stub made while
  building, so the methods check sees only the addon's.

**The harness** loses `check` / `eq` / `done` (the kit's are global). `tocLines()` /
`tocFiles()` become wrappers of `Kit.tocLines(TOC)` / `Kit.tocFiles(TOC)`.

**`test_toc`** calls `Kit.checkToc(TOC)` (interface, version token, every listed `.lua` file
exists, every entry is listed once) and keeps its own checks on top. The existence check covers
`.lua` entries only: an `.xml` or other listed file can be missing and still pass. So keep (or
add) the repo's own existence checks for those.

**`test_methods`**: exercise the addon as widely as is cheap (load it, `WoW.fireAllRegistered()`,
some `WoW.tick()` / `WoW.advance()`, open every window and options page, hover and click their
buttons, run every slash command), then:

```lua
local recorded = Kit.checkMethods({ allow = {
    ["Frame:GetMapID"] = "WorldMapFrame's MapCanvasMixin (Blizzard_MapCanvas/Blizzard_MapCanvas.lua)",
} })
check(recorded >= 120, "the exercise reached the windows (" .. recorded .. " recorded)")
```

Each recorded `Type:Method` must exist on that widget type in the pinned build. An `allow` entry
is only for a method a Blizzard mixin adds in Lua, which the dump's widget walk can't see; name
the file. The floor (`recorded >=`) is what loading plus the exercise records today, rounded
down: it keeps the exercise from quietly shrinking. If the repo already had a methods test that
accepted any documented name, this replaces it.

**`tests/run.ps1`** hands off to the kit (README, step 4), keeping whatever the repo did before
(library checkouts, ...). It gains `-KitDev`.

**CI**: the "Fetch WowTestKit at its pin" step (README, step 5) before the unit tests.

**The repo's CLAUDE.md**, in its testing section:

> The test scaffolding is WowTestKit (`C:\Projects\WoW\WowTestKit`; its README is the reference)
> at the commit and client build `tests\kit.pin` names. `tests\run.ps1` puts that commit in
> `%LOCALAPPDATA%\WowTestKit\<sha>` and hands off to the kit's runner; CI fetches it with
> `tests\fetch_kit.sh`. `tests\kit.lua`, `kit.ps1` and `fetch_kit.sh` are the kit's bootstrap
> copies: never edit them here. A kit need is an issue on the kit, worked around in
> `tests\wow_stubs.lua` with a `-- WowTestKit #N:` comment meanwhile. `tests\run.ps1 -KitDev`
> runs against the `..\WowTestKit` working copy instead of the pin.

## 3. Prove it: the comparison

Run the tests and the snapshot again on the branch, and compare with the baseline.

- **The snapshot must be identical.** A difference is a behaviour change: the old stub and the
  core disagree on something the addon does. Find out which is right (the core's comments say
  where each behaviour was measured) before going on.
- **Every result line must match, or differ for a reason you can name.** Expected ones:
  - +1 passed in every file, if the old `done()` had no stray-`|` check: the kit's checks every
    printed line;
  - `test_toc` gains a few: `Kit.checkToc` checks lines the old test may have skipped (the
    library XML lines, a second TOC);
  - a test that read the events fixture loses that check.
- **Mutation-test the methods check**: call a method that doesn't exist (`f:NoSuchMethod()`) in
  one window, and a real method on the wrong type (`FontString:SetTexCoord`); `test_methods`
  must fail on each. Empty the exercise; it must fail ("recorded 0"). Put everything back.
- **Run against the pin, not the working copy**: `tests\run.ps1` without `-KitDev`, so the
  pinned commit is fetched from GitHub; then CI.

Put the comparison in the PR: each changed count with its reason, "snapshot identical", the
mutations that went red.

## What the pilots ran into

- **A stray `|` in a printed line** (`[a | b]` in a help line) now fails `done()`: the client
  reads `|` as the start of an escape. Double it (`||`) in the addon, in its own issue. Until
  then the test may accept exactly that line, marked `-- FINDING:`, so any other stray still fails.
- **A method the addon calls on a Blizzard frame** (the world map's, a tooltip's) can come from a
  Blizzard mixin: confirm it in Blizzard's UI source, then `allow` that one pair.
- **Something the kit should do but doesn't**: open an issue here
  (`gh issue create -R Spotnick2/WowTestKit`), work around it in the local stub with a
  `-- WowTestKit #N:` comment, and move on. Never edit the bootstrap copies or the cache.
- **Trying a kit fix before it's merged**: `tests\run.ps1 -KitDev` runs against `..\WowTestKit`.
  Pin only commits on the kit's `main`.
