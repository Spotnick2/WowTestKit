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

## Resets, call hooks, masks and intrinsics

- **`WoW.reset()`** clears the client's state and discards every frame made so far (events and
  OnUpdate no longer reach them): for a suite that loads the addon again after each reset.
  **`WoW.reset({ keepFrames = true })`** keeps the frames (with their parents, children and state
  drivers), `WoW.widgets` and `WoW.methodsCalled`, and clears the rest (timers included): for a
  file that loads the addon once and resets between sections. Each `WoW.onReset` function gets the same opts.
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
