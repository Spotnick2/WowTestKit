# WowTestKit

The shared unit-test scaffolding for the WoW: Forever addons: plain Lua 5.1, no dependencies.

- **`core/`**: the assertions (`check`, `eq`, `done`), TOC readers, and the **mechanics** of a
  WoW API mock: strict globals, secrets, events checked against the build, widgets that record
  every method called (and log each call with its arguments: `w._log`, `WoW.widgets`), timers,
  `print` with the stray-`|` check, `hooksecurefunc`.
- **`checks/`**: `Kit.checkMethods` (every `Type:Method` the addon called exists on that widget
  type), `Kit.checkToc`, `Kit.checkCore`.
- **`data/forever-<build>/`**: four lists per client build (widget methods, a model scene
  actor's among them, functions, globals, events), generated from that build's API dump by `tools/gen_data.lua`. Never edited by hand.
- **`scripts/`**: the runners (`run.ps1` locally, `run.sh` in CI).
- **`bootstrap/`**: the three small files a consumer copies into its `tests/`.

What it deliberately doesn't hold: client APIs beyond those mechanics, an addon's loader, and
packaging or release scripts. Those stay in each addon.

## Using it from an addon

1. Copy `bootstrap/kit.lua`, `bootstrap/kit.ps1` and `bootstrap/fetch_kit.sh` into `tests/`.
2. Write `tests/kit.pin`:
   ```
   # WowTestKit for these tests: the commit, and the client build to test against.
   sha=<a WowTestKit commit, 40 hex>
   build=70532
   api=2
   ```
3. `tests/wow_stubs.lua` starts with `dofile("tests/kit.lua")`, takes `local Methods = WoW.Methods`,
   adds the addon's own client APIs (and may replace any `Methods` entry), and ends with
   `Kit.strict({ <the addon's globals that may read nil> })`.
4. `tests/run.ps1`:
   ```powershell
   param([string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe", [switch]$KitDev)
   $RepoRoot = Split-Path -Parent $PSScriptRoot
   . (Join-Path $PSScriptRoot "kit.ps1")
   $kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
   & (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "MyAddon.toc" -Lua $Lua
   exit $LASTEXITCODE
   ```
5. CI, before the tests:
   ```yaml
   - name: Fetch WowTestKit at its pin
     run: |
       bash tests/fetch_kit.sh "$RUNNER_TEMP/WowTestKit"
       echo "WOWTESTKIT=$RUNNER_TEMP/WowTestKit" >> "$GITHUB_ENV"
   ```

Local runs and CI use the same pinned commit. The local copy is cached in
`%LOCALAPPDATA%\WowTestKit\<sha>`, outside the repo, and works offline once fetched.
`tests\run.ps1 -KitDev` runs against the `..\WowTestKit` working copy instead, to try a kit change.

Each `tests/test_*.lua` ends with `done(name)` or `Kit.skip(name, why)`. The runners pass a file
only if it exits 0 and its last non-blank line is `<name>: N passed, 0 failed`,
`<name>: SKIPPED (why)` or `SKIPPED: why` (blank lines after it don't count). A file that stops
without one of them fails, and so does an empty suite.
`Kit.skip` after a failed assertion reports the failure, so skip before the first assertion.

An addon that already has its own stub: [docs/ADOPTING.md](docs/ADOPTING.md) is how to move it over.

## Comparing two pins

A pin bump must leave the tests saying the same thing, or change them for a reason you can name
([docs/MIGRATING.md](docs/MIGRATING.md)). `tests/kit.ps1`, run directly, checks it:

```powershell
pwsh tests/kit.ps1 -Compare HEAD                              # the pin HEAD committed vs tests/kit.pin now
pwsh tests/kit.ps1 -Compare <old kit sha>                     # the same pin with another sha=
pwsh tests/kit.ps1 -Compare main -Snapshot <script.lua> [-Lua <lua.exe>]
```

It runs `tests/run.ps1` with the old pin, then with `tests/kit.pin` as it is, and prints only the
test files whose result line differs (a file Lua stopped shows its error), the summary if it
differs, and, with `-Snapshot`, whether the load snapshot ([docs/ADOPTING.md](docs/ADOPTING.md),
section 1) is identical. A commit of the repo gives its whole `tests/kit.pin` (sha, build and
api), so use one when the bump changes the build: a kit sha replaces `sha=` only. The old pin is
written into `tests/kit.pin` for its run and the file is put back byte for byte;
`tests/kit.pin.compare-backup` holds it meanwhile, and exists only once it is complete.
`tests/kit.pin.compare-lock`, created whole with the process that made it and kept until both
runs are done, makes a second `-Compare` refuse to start. It says whether the first is still
running (wait for it) or stopped, and then what to do with what it left. For a lock that names
no process, you check yourself that no `-Compare` is running. Exit 0 means nothing differs and both runs
passed. 1 means something differs, a run failed, or a run's results couldn't all be read. 2 means
it couldn't run. Copy the new `kit.ps1` into
`tests/` first: it's part of the bump.

## Resets, call hooks, masks and intrinsics

- **`WoW.reset()`** clears the client's state and discards every frame made so far (events and
  OnUpdate no longer reach them): for a suite that loads the addon again after each reset.
  **`WoW.reset({ keepFrames = true })`** keeps the frames (with their parents, children and state
  drivers), `WoW.widgets` and `WoW.methodsCalled`, and clears the rest (timers included): for a
  file that loads the addon once and resets between sections. A discarded frame's name still
  points at it. **`WoW.reset({ releaseNames = true })`** also takes those names off `_G`, unless
  a test replaced them, as a /reload would. Use it for an addon that guards creation by name
  (`if not MyFrame then CreateFrame("Frame", "MyFrame") end`). It can't go with `keepFrames`.
  Each `WoW.onReset` function gets the same opts.
- **`WoW.onMethodCall`** is a list of functions run as `fn(widget, methodName, ...)` on every call
  made through a widget's methods, after the call is recorded and logged (`w._log`), before the
  combat refusal: a refused call is seen too, with `WoW.combat` and `WoW.isProtected(widget)` as
  they are at the call. `table.insert(WoW.onMethodCall, fn)` in the stub; `WoW.reset` keeps the
  list, a fresh client starts with an empty one.
- **`f._maskTextures`** lists the masks a frame made with `CreateMaskTexture`, in creation order
  (a texture's `t._masks` are the masks `AddMaskTexture` put on it). They aren't in `f._regions`,
  so `GetRegions()` doesn't return them: whether the client's does is unmeasured.
- **`WoW.INTRINSIC`** maps each XML intrinsic Blizzard's source declares (`EventFrame`,
  `DropdownButton`, `ItemButton`, …) to its base type: `CreateFrame("DropdownButton")` makes a
  `Button` (`w._type`), keeps the name asked for in `w._intrinsic`, and its calls are recorded on
  `Button`, so the mixin's methods are `Kit.allowMethods` entries on the base type
  (`["Button:SetupMenu"]`). A consumer adds its own: `WoW.INTRINSIC.MyIntrinsic = "Frame"`.

## A new client build

After the forever-api-dump skill has made the new dump:

```
lua tools/gen_data.lua ../References/Forever/api/forever-api-<version>.<build>.md
```

The dump's `_G` walk ran with addons loaded. The generator drops the owner's addons (`tools/loaded-addons.txt`)
and the names in an `addon-globals.txt` beside the dump, if there is one (an exact name or a `Prefix*`
on each line). That list stays with the dumps, so other addons' names never land in this repo.

Commit the new `data/forever-<build>/` with a release. A consumer moves to it by changing
`build=` in its `tests/kit.pin`.

MIT licensed.
