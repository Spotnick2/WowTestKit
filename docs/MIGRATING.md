# Moving to a new Kit.API

`Kit.API` (in `kit.lua`) goes up when a kit change would otherwise change what a consumer's tests
mean without telling it. A consumer says which API it was written for in `tests/kit.pin`
(`api=`). When the pinned kit's API is another one, `Kit.load` stops with the kit's "migrate"
error instead of running the tests under a meaning they weren't written for.

To move: bump `sha=` in `tests/kit.pin`, follow each step of the new API below, set `api=` to it,
and run the tests. Compare the counts with the run before the bump. A count may change only for a
reason the steps name.

## API 1 → 2

### `WoW.tick(elapsed)` moves the clock (WowTestKit #9)

One rendered frame now moves `WoW.now`, so `GetTime()`, by `elapsed` before OnUpdate runs, as on
the client. Before, only `WoW.advance` moved the clock. Timers are still run by `WoW.advance` and
`WoW.flushTimers` only.

- **A wrapper that moved the clock itself goes.** GlassActionBars' `-- WowTestKit #9:` wrapper
  around `WoW.tick` would now move it twice per tick.
- **A step helper that advances, then ticks, ticks with 0.** Apotheca's
  `WoW.step(elapsed)` (`WoW.advance(elapsed); WoW.tick(elapsed)`) becomes
  `WoW.advance(elapsed); WoW.tick(0)`. Kept, it moves the clock by twice `elapsed`.
- **A test helper that moved `WoW.now` and ticked** (GlassMail's `test_openall` and `test_inbox`
  `step`: `WoW.now = WoW.now + dt; WoW.tick(dt)`) drops its own line.
- **Code timed by `GetTime()` inside OnUpdate now sees time pass under ticks.** A test that
  relied on it standing still (GlassChat's `test_idle`, Apotheca's `test_xpfood`, measured in
  the run against the kit) needs its expectations moved to the client's behaviour.

### A method the build lacks reads as `nil` (WowTestKit #22)

A widget's capitalised key used to answer every name with a recording function. Now it answers
only when the widget's type has that method on the pinned build, when the stub has a `Methods`
implementation for it, or when it's allowed with `Kit.allowMethods`. Anything else reads as `nil`,
as on the client, so `if type(f.GetModel) == "function"` takes the client's branch and a call
fails where it's made ("attempt to call method 'X' (a nil value)").

- **A Blizzard mixin method allowed only at the check moves to `Kit.allowMethods`, before the
  addon loads.** `Kit.checkMethods({ allow = { ["GameTooltip:SetItemByID"] = "…" } })` with no
  `Methods.SetItemByID` in the stub let the call through before; now the call fails first. Put
  the pair in `Kit.allowMethods({ ["GameTooltip:SetItemByID"] = "<the Blizzard file>" })` in the
  stub (`Kit.checkMethods` accepts those too), or give the stub an implementation. Measured in the
  run against the kit: Apotheca (`GameTooltip:SetItemByID`, test_frames and test_methods) and
  GlassActionBars (`GameTooltip:SetSpellByID`, test_feedpet). GlassPearls' test_books_compass
  loses one check ("its tooltip follows"), not yet traced to its method. AltStable, GlassMail
  and NodeRadar allow pairs the same way: check each.
- **A workaround that faked an absent method goes.** AltStable's `-- WowTestKit #22:`
  `rawset(f, "GetModel", false)` is now the kit's own behaviour.
