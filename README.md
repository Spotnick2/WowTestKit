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

An addon that already has its own stub: [docs/ADOPTING.md](docs/ADOPTING.md) is how to move it over.

## Resets, call hooks and masks

- **`WoW.reset()`** clears the client's state and discards every frame made so far (events and
  OnUpdate no longer reach them): for a suite that loads the addon again after each reset.
  **`WoW.reset({ keepFrames = true })`** keeps the frames (with their parents and children),
  `WoW.widgets` and `WoW.methodsCalled`, and clears the rest: for a file that loads the addon once
  and resets between sections. Each `WoW.onReset` function gets the same opts.
- **`WoW.onMethodCall`** is a list of functions run as `fn(widget, methodName, ...)` on every call
  made through a widget's methods, after the call is recorded and logged (`w._log`), before the
  combat refusal: a refused call is seen too, with `WoW.combat` and `WoW.isProtected(widget)` as
  they are at the call. `table.insert(WoW.onMethodCall, fn)` in the stub; `WoW.reset` keeps the
  list, a fresh client starts with an empty one.
- **`f._maskTextures`** lists the masks a frame made with `CreateMaskTexture`, in creation order
  (a texture's `t._masks` are the masks `AddMaskTexture` put on it). They aren't in `f._regions`,
  so `GetRegions()` doesn't return them: whether the client's does is unmeasured.

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
