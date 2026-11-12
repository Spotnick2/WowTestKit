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
