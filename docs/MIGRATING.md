# Moving to a new Kit.API

`Kit.API` (in `kit.lua`) goes up when a kit change would otherwise change what a consumer's tests
mean without telling it. A consumer says which API it was written for in `tests/kit.pin`
(`api=`). When the pinned kit's API is another one, `Kit.load` stops with the kit's "migrate"
error instead of running the tests under a meaning they weren't written for.

To move: bump `sha=` in `tests/kit.pin`, follow each step of the new API below, set `api=` to it,
and run the tests. Compare the counts with the run before the bump. A count may change only for a
reason the steps name.

## API 1 → 2

API 2 is every kit change after `134d55a`, the last API-1 commit (every API-1 pin is at or
before it). The first three sections below need a code change in most consumers; the rest change
what a test sees, and name the consumers the run against the kit showed affected. Check each
against your stub and tests.

**`done()` adds a check to every test file** (no swallowed secret touch, below), so each file's
"passed" count goes up by one. `Kit.checkCore()` checks the core's new globals too (`pcall`,
`xpcall`, `GetCursorPosition`, the four `SecureHandler*`), so a file that calls it gains those
checks.

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

### `SetGradient` drops an alpha set before it, and takes colour objects (WowTestKit #37)

Measured on 70374 (porting guide section 3): a texture with a gradient reads `GetAlpha()` 1 and
ignores `SetAlpha`, whichever comes first. The core used to keep an alpha set before
`SetGradient`. It now drops it, and `SetGradient` throws on colours that aren't colour objects
(the dump's `colorRGBA`, from `CreateColor`).

- **A stub override that did this goes.** Glass UI's `SetGradient` override (`_alpha = 1`, table
  colours) is now the kit's own behaviour.
- **A test that read the earlier alpha back from a gradient texture** now reads 1, as on the client.
- **A test passing numbers as the colours** passes colour objects (a table with `r`, `g`, `b`, `a`
  is enough for the stub).

### A swallowed secret touch fails the file (WowTestKit #13, #47)

The core's `pcall` and `xpcall` count every blocked operation on a secret they catch
(`WoW.secretBlocked`), as the client writes each to taint.log caught or not, and `done()` fails
on one, naming the first. `string.format` on a secret counts too. Lua's "attempt to compare …
userdata" counts while a secret proxy is alive in the test.

- **A stub that touches its own secrets fails the files that reach it.** GlassPearls' stub
  concatenated a secret faction in `UnitFactionGroup` (`test_books`, `test_restock_plan`): the
  client returns the secret without an error, so the stub must too.
- **A test that touches a secret on purpose** uses `WoW.rawpcall`, or reads the count and sets it
  back to 0.
- **A stub's own counted `pcall` goes** (Apotheca's `-- WowTestKit #13:`): kept, each touch counts
  twice.

### Tickers repeat (WowTestKit #18, #34)

`C_Timer.NewTicker` repeats until cancelled or its `iterations` are used up; its handle has
`Cancel` and `IsCancelled`, and the callback gets the handle. `WoW.advance` fires it once per
period; `WoW.flushTimers` runs it once and keeps it.

- **A loop that flushes until `WoW.timers` is empty never ends while a ticker lives.** Cancel it
  first, or flush a fixed number of times.
- **A test that counted one run** after several flushes or a long `advance` now sees one per
  flush or period.
- A record a stub put in `WoW.timers` itself still runs once (GlassChat's own `NewTicker`).

### OnShow / OnHide fire on a visibility change, down the tree (WowTestKit #21, #46)

`Show` / `Hide` fire the frame's and its descendants' scripts only where visibility changed:
`Show` on a shown frame fires nothing, a frame under a hidden parent gets nothing until the parent
shows, and showing or hiding a parent reaches its shown children. `WoW.reset()` takes the old
frames out of the parents that survive it.

- **A frame the stub never shows keeps its children invisible.** GlassMail's `test_openall` and
  `test_inbox` expected `OpenAllMail`'s OnShow while its mail frame was hidden in the stub: the
  stub shows the mail frame at `MAIL_SHOW`, as the client does.
- **A stub's own propagation goes** (Apotheca's `-- WowTestKit #21:`): kept, children get their
  scripts twice.
- **A stub that writes `_shown` directly** bypasses the scripts; use `Show` / `Hide`, or
  `WoW.setShown(frame, shown)` for secure code's path (no combat refusal).

### Protected frames: one list, and parents of protected frames (WowTestKit #12, #42)

In combat a protected frame refuses every method in `WoW.PROTECTED` (Show, Hide, SetShown,
SetPoint, ClearAllPoints, SetAllPoints, SetAttribute, RegisterForClicks, SetSize, SetWidth,
SetHeight, StartMoving, StopMovingOrSizing, SetClampedToScreen) and records `name:Method` in
`WoW.blocked`. A frame that parents a protected one, at any depth, is protected too (measured);
`IsProtected()` returns `protected, explicitly`.

- **Tests asserting `WoW.blocked` stays empty now also catch** `SetAttribute`, resizing, moving,
  clamping and `RegisterForClicks` in combat, and any of these on a frame above a secure one,
  `UIParent` included.
- **A refused `SetShown` is recorded as `name:SetShown`**, no longer `name:Show` / `name:Hide`.
- **A stub's own guards go** (Apotheca's and GlassUnitFrames' `-- WowTestKit #12:`). Add the
  methods you rely on beyond the list: `WoW.PROTECTED.SetScale = true`.
- **Apotheca's `WoW.strictLockdown`** (an error at the call) moves to a replacement of
  `WoW.refused`: the dispatch refuses before a `Methods` wrapper runs.

### Unit events (WowTestKit #17)

`Frame:RegisterUnitEvent(event, unit1, unit2, …)` delivers the event only for those units;
`IsEventRegistered` returns them; `WoW.fireAllRegistered()` fires a unit event once per registered
unit, with it as the payload.

- **A stub's shim that registered the plain event goes** (Apotheca's `RegisterUnitEvent`): kept,
  it hides the unit filter.
- **`w._unitEvents[event]` is a set** (`{ target = true }`), not the unit string GlassUnitFrames'
  stub kept.

### The status bar colour (WowTestKit #19)

`SetStatusBarColor` sets the fill's vertex colour and drops a gradient painted on it (measured,
LibGlass#64). GlassUnitFrames' `-- WowTestKit #19:` override goes.

### Secure handlers (WowTestKit #20, #43, #44)

The core now defines `SecureHandlerWrapScript`, `SecureHandlerUnwrapScript`,
`SecureHandlerSetFrameRef`, `SecureHandlerExecute` and `GetCursorPosition`, and the secure
templates (`SecureActionButtonTemplate`'s OnClick is the secure action, `WoW.secureActionClick`).

- **A stub's own model goes** (Apotheca's `-- WowTestKit #20:`). `WoW.overrideBindings[key]` is
  `{ owner, name, button, priority }`; `owner` is an environment global in a snippet.
- **A stub that defines `SecureActionButtonTemplate` itself replaces the kit's**: its buttons set
  `OnClick` to `WoW.secureActionClick`, or keep their own.
- **A secure button has an OnClick**, as on the client. AltStable's `test_sheetui` asserted it had
  none.
- **Snippets follow the client's rules:** no `function` keyword or table literals; `SetAttribute`
  refuses `_` names and table values; `SetPoint` needs a protected relative frame; in combat a
  handle reaches only protected frames.

### A fresh client (WowTestKit #8, #45, #48)

Loading the stub again in the same test file is a fresh client: the counts, strays, methods called
and swallowed-secret count carry over; the old client's named widgets leave `_G`; the API is
checked again. GlassActionBars' and GlassUnitFrames' `-- WowTestKit #8:` blocks go.

### Smaller ones (WowTestKit #7, #38, #41)

- **The widget metatable's `__index` is a method table per type** (#7): GlassMiniMapBar's
  `-- WowTestKit #7:` block goes.
- **Every widget starts with empty `_children` and `_regions`** (#38): Glass UI's `CreateFrame`
  wrapper goes. A test checking `f._children == nil` for "no children" checks `#f._children == 0`.
- **`SetID` keeps a frame's ID and `GetID` returns it, 0 until set** (#41), on handles too: Glass
  UI's `-- WowTestKit #41:` `SetID` / `GetID` go. A test that read `nil` from `GetID` reads 0.
