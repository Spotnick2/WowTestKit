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
"passed" count goes up by one. A file that ends with its own report instead (AltStable's
`WoW.finish`) gains nothing, and has no swallowed-secret check: call `done()`, or check
`WoW.secretBlocked` in that report. `Kit.checkCore()` checks the core's new globals too (`pcall`,
`xpcall`, `GetCursorPosition`, the four `SecureHandler*`), so a file that calls it gains those
checks.

### `WoW.tick(elapsed)` moves the clock (WowTestKit #9)

One rendered frame now moves `WoW.now`, so `GetTime()`, by `elapsed` before OnUpdate runs, as on
the client. Before, only `WoW.advance` moved the clock. Timers are still run by `WoW.advance` and
`WoW.flushTimers` only.

- **A wrapper that moved the clock itself goes.** GlassActionBars' `-- WowTestKit #9:` wrapper
  around `WoW.tick` would now move it twice per tick.
- **A step helper that advances, then ticks, goes: the core's `WoW.step(dt)` is one.** Apotheca's
  `WoW.step(elapsed)` (`WoW.advance(elapsed); WoW.tick(elapsed)`) would now move the clock by twice
  `elapsed`. The core's `WoW.step(dt)` (WowTestKit #66) moves it once: the clock moves on by `dt`,
  the timers due by then run, then OnUpdate runs with `dt`. Don't replace the helper with
  `WoW.advance(dt); WoW.tick(0)`: that hands every OnUpdate `elapsed = 0`, so one that throttles by
  adding up `elapsed` (`self.t = self.t + elapsed; if self.t < 0.1 then return end`) never runs.
  Measured on Apotheca's move (Apotheca#99): with `tick(0)`, 14 of 26 test files failed.
  On a kit older than `WoW.step`, the same frame is
  `WoW.advance(dt); WoW.now = WoW.now - dt; WoW.tick(dt)`.
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
  GlassActionBars (`GameTooltip:SetSpellByID`, test_feedpet). AltStable, GlassMail, GlassPearls
  and NodeRadar allow pairs the same way: check each.
- **GameTooltip's setters are Lua methods**: `SetHyperlink`, `SetItemByID`, `SetSpellByID`,
  `SetBagItem`, `SetLootItem`, `SetInventoryItem` and the rest come from
  `TooltipDataHandlerMixin` (`Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua`), which the
  dump's widget walk doesn't see. Allow each one the addon calls. **A call inside a `pcall` fails
  silently**: no test fails, the tooltip code just stops running. Measured: AltStable
  (`SetHyperlink`, `SetInventoryItem`; `test_methods` records them no more) and GlassPearls
  (`SetBagItem`, `SetLootItem`; `SetItemByID` is the method `test_books_compass` loses).
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

### Timers run at their due time (WowTestKit #86, #76)

Not a `Kit.API` change: a pin bumped past it sees it with `api=` unchanged. `WoW.advance(dt)` runs
each due timer in due order with `GetTime()` at its due time (or now, if it was already overdue),
and a timer scheduled inside one counts from that time; then the clock is at `now + dt`. Before,
every timer in the advance read its end. `WoW.step` follows: its timers run at their due times,
then OnUpdate at the step's end.

- **A timer that reads `GetTime()` inside a multi-second advance** now reads its due time: a
  `C_Timer.After(2, fn)` in `WoW.advance(4)` reads 2, not 4, as on the client. A test that
  expected the end of the advance moves to the due time. GuildSpy's `test_scanner` needed it
  (GuildSpy#68).
- **A chain of timers** (one scheduled inside another) now runs within one long advance:
  `After(1)` scheduling `After(1)` runs both in `WoW.advance(5)`, at 1 and 2. Before, the second
  counted from 5 and waited for a later advance, so a test that counted runs after a long advance
  may now see more. A loop or stub wrapper that stepped the clock from one due time to the next
  for this can go (GuildSpy's `WoW.advance` in `tests/wow_stubs.lua`).
- **A 0-second ticker fires once per advance, `WoW.advance(0)` included** (#76), first thing,
  with the clock where the advance started. Before, `advance(0)` fired it only the first time. A
  stub's `advance(0)` that moved the clock by `1e-9` to work around it can go (PortalRoulette's
  `tests/wow_stubs.lua`).

### OnShow / OnHide fire on a visibility change, down the tree (WowTestKit #21, #46, #99)

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
- **Children first, and on a reparent too** (#99, measured on 70959 by WowTestKitProbe; see
  `docs/FOREVER-PROBE.md`). The scripts of one walk run on a frame's descendants before the frame
  itself (#21 had them parents first, unmeasured). A test asserting the order of a walk's
  scripts reads it reversed. `SetParent` that changes a frame's visibility now runs the walk, so
  its OnShow / OnHide fire during the call (with `GetParent()` the new parent); one that leaves it
  visible, or hidden, fires nothing. LibShowcase's `-- WowTestKit #99:` `SetParent` goes.
- **`SetParent` sets the frame level** (#99, measured): the new parent's + 1, raised or lowered,
  0 with no parent, and each descendant one above its parent. A test reading a level after a
  reparent reads the new one; one that relied on a level surviving it (LibShowcase's "level not
  restored" mutant) now sees it change.

### Protected frames: one list, and parents of protected frames (WowTestKit #12, #42)

In combat a protected frame refuses every method in `WoW.PROTECTED` (Show, Hide, SetShown,
SetPoint, ClearAllPoints, SetAllPoints, SetAttribute, RegisterForClicks, SetSize, SetWidth,
SetHeight, SetScale, SetFrameStrata, SetFrameLevel, EnableMouse, StartMoving, StopMovingOrSizing,
SetClampedToScreen, ClearPoint, StartSizing) and records `name:Method` in
`WoW.blocked`. A frame that parents a protected one, at any depth, is protected too (measured);
`IsProtected()` returns `protected, explicitly`.

- **Tests asserting `WoW.blocked` stays empty now also catch** `SetAttribute`, resizing, moving,
  clamping and `RegisterForClicks` in combat, and any of these on a frame above a secure one,
  `UIParent` included.
- **A refused `SetShown` is recorded as `name:SetShown`**, no longer `name:Show` / `name:Hide`.
- **A stub's own guards go** (Apotheca's and GlassUnitFrames' `-- WowTestKit #12:`). Add the
  methods you rely on beyond the list: `WoW.PROTECTED.SetParent = true`.
- **SetScale, SetFrameStrata, SetFrameLevel and EnableMouse joined the list** (measured on 70959,
  WowTestKit #83). A stub that added one itself (LibGroupBuffs' `SetScale`) drops its line. SetAlpha,
  and every write to a protected frame's regions, stay out: the client allows them.
- **Clearing `f._protected` no longer frees a frame that parents protected ones.** A helper that
  acts as Blizzard that way (GlassActionBars' `WoW.blizzard`, `test_edges`: MultiBar5 is
  protected through its buttons) clears `WoW.combat` for the call instead, which both the
  dispatch and the core's methods check. `InCombatLockdown()` then reads false inside the call,
  so a helper whose code asks it shows or hides with `WoW.setShown(frame, shown)` instead (no
  refusal at all). A stub's guard that checks `w._protected` checks `WoW.isProtected(w)`.
- **Replacing `WoW.refused` changes only the dispatch's check.** The core's `Show`, `Hide`,
  `SetPoint`, `ClearAllPoints`, `SetAllPoints` and `SetAttribute` check again with their own copy,
  so a replacement that returns false doesn't let the call through: the core still refuses it.
  A replacement that raises an error works, since the dispatch checks first: Apotheca's
  `WoW.strictLockdown` (an error at the call) moves there, as the dispatch refuses before a
  `Methods` wrapper runs.

### Unit events (WowTestKit #17, #94)

`Frame:RegisterUnitEvent(event, unit1, unit2, …)` delivers the event only for those units;
`IsEventRegistered` returns them; `WoW.fireAllRegistered()` fires a unit event once per registered
unit, with it as the payload.

- **A stub's shim that registered the plain event goes** (Apotheca's `RegisterUnitEvent`): kept,
  it hides the unit filter.
- **`w._unitEvents[event]` is a set** (`{ target = true }`), not the unit string GlassUnitFrames'
  stub kept.
- **`WoW.fireAllRegistered(units)` takes an optional list of units** (#94): every event a frame
  registered plainly fires once per unit in it (sorted, each once, together with its
  `RegisterUnitEvent` units), instead of once with no payload. Without the list, or with an
  empty one, nothing changes. GlassRaidFrames' `-- WowTestKit #94:` `fireAllRegistered` goes:
  pass it the units it modelled (`WoW.units` and `"player"`).

### Refused events (WowTestKit #79)

- **`RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` returns `false` and registers nothing**, as on
  Forever (measured; the client raises `ADDON_ACTION_FORBIDDEN`). Each refusal is recorded in
  `WoW.forbidden` (`"name:RegisterEvent:EVENT"`, cleared by `WoW.reset()`), not in `WoW.blocked`.
  The set is `WoW.REFUSED_EVENTS`; a stub adds one it measured. A test that registered the
  combat log and fired it now sees nothing arrive. Stakeout's `-- WowTestKit #79:` override
  (`WoW.refusedEvents`) goes.

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
- **State drivers** (#77): the core defines `RegisterStateDriver`, `UnregisterStateDriver`,
  `RegisterAttributeDriver`, `UnregisterAttributeDriver` and `SecureCmdOptionParse`, so
  `Kit.checkCore()` gains ten checks. A stub's own (Apotheca's `-- WowTestKit #77:`) goes. A
  driver resolves at registration, then every 0.2 s of `WoW.tick` / `WoW.step`, and on the next
  frame after `WoW.fire("PLAYER_REGEN_DISABLED")` (or `_ENABLED`, and the client's other wake
  events): flipping `WoW.combat` alone waits out the 0.2 s. Registering in combat is refused (in
  `WoW.blocked`). The core's conditions are `[combat]` and `no...`; any other is an error until
  the stub adds it to `WoW.CONDITIONS`. `[group]`, `[party]` and `[raid]` read false in combat, as
  measured. `_onstate-<s>` snippets don't run (OnAttributeChanged isn't modelled).
- **The secure action resolves modified attributes** (#88): `*type1`, `shift-type*`, `type`...
  for the mouse button and the modifiers the stub's `IsShiftKeyDown` / `IsControlKeyDown` /
  `IsAltKeyDown` report (none held when it has none), and `WoW.secureActions` records the
  resolved values. A stub's own `SecureActionButtonTemplate` for this (Shatter's) goes. **An edge
  whose type resolves to nothing records nothing now**: a test that counted an entry for a button
  with no `type` (or for a right click on a `*type1` button) counts one less. With
  `WoW.useKeyHeldSpell` (the `ActionButtonUseKeyHeldSpell` CVar, off by default) or a
  `pressAndHoldAction` attribute, the up edge acts on `typerelease` (`release = true`).
- **`SecureHandlerWrapScript` wraps `OnEnter`, `OnLeave`, `OnShow` and `OnHide` too** (#93), as
  the client does; other scripts but `OnClick` are still refused. GlassRaidFrames'
  `-- WowTestKit #93:` wrap, execute and frame-ref stubs go, and its tests drive the snippets
  through the kit: `WoW.enter(frame)` / `WoW.leave(frame)` run `OnEnter` / `OnLeave` with
  `motion` (true unless given). The enter and leave pre snippets get `self` only (no `motion`),
  run only on a motion, and a leave's only after an enter (`_wrapentered`). Handles have
  `control:RunFor(otherHandle, body, ...)`.

### A fresh client (WowTestKit #8, #45, #48)

Loading the stub again in the same test file is a fresh client: the counts, strays, methods called
and swallowed-secret count carry over; the old client's named widgets leave `_G`; the API is
checked again. GlassActionBars' and GlassUnitFrames' `-- WowTestKit #8:` blocks go.

- **A reload that replays the counts goes.** NodeRadar's `fresh()` reads `Kit.counts()`, reloads
  and then calls `check(true)` once per earlier pass: the kit already carried them, so each
  reload doubles the count (`test_locate`: 55 checks became 14,980,609; `test_locate2` was still
  running when the machine ran low on memory).

### Widget methods the stubs had (WowTestKit #78, #89, #92, #97)

The core now implements methods most consumers had in their own stub. Each read as a method
before (it's in the build's lists) and returned nil. A stub's own copy still wins; drop it, unless
its model is one the tests rely on.

- **`GetSize()` returns the width and height** (#78), as `GetWidth` / `GetHeight` read them. The
  `-- WowTestKit #78:` one-liners go (Apotheca, GlassMiniMap, GlassMiniMapBar, GlassQuestTracker,
  GlassUI, NodeRadar, PortalRoulette, Shatter, Stakeout).
- **The `-- WowTestKit #89:` methods** (Shatter, GlassRaidFrames, Gnomesweeper, TimeIsMoney):
  `GetNumPoints`, `SetScale` / `GetScale` (1 until set), `SetMovable` / `IsMovable`,
  `StartMoving` / `StartSizing` / `StopMovingOrSizing` (`_moving`, `_sizing`),
  `SetResizeBounds` (`_resizeBounds`), `RegisterForClicks`, the ScrollFrame's scroll child and
  vertical scroll, EditBox focus, GameTooltip's lines and owner, `GetTexture`, `GetMinMaxValues`
  (0, 0 until set), and `GetStringWidth` / `GetStringHeight`. Where a stub's names differ, its
  tests move to the core's:
  - `RegisterForClicks` keeps the clicks in `_registeredClicks` (`_clicks` is
    `SetMouseClickEnabled`'s already): TimeIsMoney and GlassRaidFrames read `_clicks`.
  - `GetVerticalScrollRange` reads a test's `_yrange` (Shatter's `_vscrollRange`, Apotheca's
    `_vrange`), and `SetVerticalScroll` fires `OnVerticalScroll` on a change.
  - A tooltip's lines are `_lines` (left texts) and `_linesRight` (an `AddDoubleLine`'s right
    text): a test that read a double line as one `"left|right"` or `"left\tright"` string reads
    the two. `SetOwner` clears the lines and `SetText` makes its text the only line (Shatter's
    model); TimeIsMoney's, whose `SetOwner` kept them and which kept them in `lines`, differs.
  - **One edit box has the focus at a time** (`WoW.focus`): `SetFocus` on another fires the first
    one's `OnEditFocusLost`.
  - **The string metrics are an approximation** (6 units a character, 14 a line, wrapped at the
    width set): a test that asserted a stub's own numbers keeps its stub's method.
- **`GetEffectiveScale` follows `SetScale`** (#89): unset, it's the product of the scales up the
  parents (porting guide, "GetCenter is in the frame's OWN space"), so 1 only while nothing is
  scaled. A test's `_escale` still wins. A test that scaled a frame and expected 1 sets `_escale`;
  Gnomesweeper's chain goes.
- **`SetPoint` replaces the anchor a frame already has for that point** (#92), as the client keeps
  one anchor per point; a secure handle's `SetPoint` too, and a second `SetAllPoints` replaces the
  first. `ClearPoint(point)` removes one. A frame re-anchored without `ClearAllPoints` now counts
  each point once in `#f._points` and `GetNumPoints()`, and a replaced anchor moves to the end of
  the list, so `GetPoint(i)` / `f._points[i]` may read another anchor than before. GlassRaidFrames'
  `-- WowTestKit #92:` `SetPoint` and its `ClearPoint` go.
- **`GetVertexColor()` and `GetNumMaskTextures()`** (#97) read back what `SetVertexColor` and
  `AddMaskTexture` / `RemoveMaskTexture` set: white and 0 until set, and an alpha left out reads 1
  (both defaults unmeasured). GlassNameplates' `-- WowTestKit #97:` pair goes.

### Smaller ones (WowTestKit #7, #38, #41, #62, #84, #87, #90, #91)

- **The widget metatable's `__index` is a method table per type** (#7): GlassMiniMapBar's
  `-- WowTestKit #7:` block goes.
- **Every widget starts with empty `_children` and `_regions`** (#38): Glass UI's `CreateFrame`
  wrapper goes. A test checking `f._children == nil` for "no children" checks `#f._children == 0`.
- **`SetID` keeps a frame's ID and `GetID` returns it, 0 until set** (#41), on handles too: Glass
  UI's `-- WowTestKit #41:` `SetID` / `GetID` go. A test that read `nil` from `GetID` reads 0.
- **The core defines `GetLocale`** (#62): `WoW.locale`, `"enUS"` until a test sets it, cleared by
  `WoW.reset()`. AltStable's, LibGroupBuffs' and Gnomesweeper's own `GetLocale` stubs can go (one
  kept after the kit's still wins). `Kit.checkCore()` checks it too, so a file that calls it
  gains two checks.
- **A click on a CheckButton toggles its checked state before PreClick and OnClick** (#87), as
  Blizzard's check box handlers expect: `WoW.click(b)` / `b:Click()` on an enabled CheckButton,
  each call once. GlassGear's `-- WowTestKit #87:` override of `Methods.Click` goes. A test that
  clicked a check box and asserted the old state, or clicked both edges (`down` true, then
  false) of one click, now sees it toggled (twice for the two edges).
- **`xpcall(f, handler, ...)` passes `...` to `f`** (#91), as the client's does, and still counts a
  swallowed secret touch. Gnomesweeper's and AltStable's `xpcall` overrides go (Gnomesweeper's is
  `-- WowTestKit #91:`).
- **`Kit.checkToc` takes `{ version = "dev" }`** (#84) for an addon that's never packaged: it
  checks that whole `## Version:` line instead of the packager's token (the default, unchanged).
  ForeverProbe's `-- WowTestKit #84:` checks go.
- **A model scene actor is a `ModelSceneActor` widget** (#90): each build's widget methods have
  that type (the dump's `FrameAPIModelSceneFrameActor` and `...ActorBase` functions), and the
  core's `ModelScene:CreateActor()` makes one, kept in `scene._actors`. `Kit.checkMethods` checks
  an actor's calls like any widget's: Gnomesweeper's `-- WowTestKit #90:` `allow` entries go, and
  its and AltStable's own `CreateActor` can go (one kept still wins). An actor method the build
  lacks now reads `nil`, as on any widget (#22): a mixin's (`ModelSceneActorMixin`'s
  `SetOnModelLoadedCallback`...) needs `Kit.allowMethods`.

### A state-only reset, a hook on every call, a frame's masks, intrinsics (WowTestKit #80, #81, #82, #85)

- **A state-only reset** (#80): `WoW.reset({ keepFrames = true })` keeps the frames made so far
  (with their state drivers, #77), `WoW.widgets` and `WoW.methodsCalled`. LibGroupBuffs' `-- WowTestKit #80:` `WoW.reset` (it
  emptied `WoW.frames` before the kit's reset, then put the three back) goes: call the kit's with
  `{ keepFrames = true }`. `WoW.reset()` with no opts is unchanged.
- **A hook on every widget call** (#81): each function in `WoW.onMethodCall` runs as
  `fn(widget, methodName, ...)`, before the combat refusal. LibGroupBuffs' `-- WowTestKit #81:`
  workaround (a metatable on `WoW.PROTECTED` answering truthy for every state write, and a wrapped
  `WoW.refused` that recorded the touch, then refused only what `rawget(WoW.PROTECTED, method)`
  names) goes: `WoW.PROTECTED` and `WoW.refused` stay the kit's, and `WoW.combatTouches` is filled
  by a hook that returns unless `WoW.combat` and `WoW.isProtected(widget)`, skips `SetScript` /
  `HookScript`, and records `name:Method` for a state write (`Show`, `Hide`, `EnableMouse`,
  `Raise`, `Lower`, `Set*`, `Start*`, `Stop*`, `Clear*`). The stub clears `WoW.combatTouches` in a
  `WoW.onReset` function; the hook itself survives `WoW.reset`.
- **A frame's masks are in `f._maskTextures`** (#82), in creation order, and move with `SetParent`.
  `GetRegions()` still doesn't return them: whether the client's does is unmeasured, and
  Blizzard's source doesn't settle it. A test that walks a frame's masks walks `f._maskTextures`.
  LibGroupBuffs' `-- WowTestKit #82:` `CreateMaskTexture` (which added each mask to the regions,
  as its pre-kit stub did) goes; kept, its tests also rely on `GetRegions()` listing masks, which
  nobody has measured.
- **An XML intrinsic is a widget of its base type** (#85): `CreateFrame("EventFrame")` makes a
  `Frame`, `CreateFrame("DropdownButton")` a `Button` (`WoW.INTRINSIC`, every intrinsic in
  Blizzard's source but `ScrollingMessageFrame`, which the build lists as a type). Before, the
  widget's type was the intrinsic's name: every name read as a method on it, and
  `Kit.checkMethods` failed each call ("widget type exists on Forever …: EventFrame:SetPoint").
  Now `w._type` and `GetObjectType()` are the base type (the client's `GetObjectType` for an
  intrinsic is unmeasured), `w._intrinsic` keeps the name, and the calls are recorded on the base
  type. **A method the base type lacks now reads `nil`**: the intrinsic's mixin methods
  (`DropdownButtonMixin:SetupMenu`) are allowed on the base type,
  `Kit.allowMethods({ ["Button:SetupMenu"] = "…" })`, and a pair allowed under the intrinsic's
  name (`DropdownButton:SetupMenu`) moves there. GuildSpy's `-- WowTestKit #85:` `CreateFrame`
  wrapper goes. A stub's `if w._type == "DropdownButton"` reads `w._intrinsic`.
