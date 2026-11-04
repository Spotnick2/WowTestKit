# CLAUDE.md

WowTestKit: the unit-test scaffolding shared by the WoW: Forever addons under `C:\Projects\WoW`.
The README is the contract; this file is how to work on it. The plan behind it is
Spotnick2/wow-dev-tools#11.

## The model (ForeverProbe's)

- **Consumers use the kit; they never edit it.** An addon's session that needs something from
  the kit opens an issue here (`gh issue create -R Spotnick2/WowTestKit`), works around it in its
  own stub meanwhile, and notes the issue number beside the workaround.
- **Consumers pin a commit** (`tests/kit.pin`), locally and in CI. A kit change reaches an addon
  only when its pin is bumped (the wow-propagate skill: one issue per repo, applied when the repo
  is next touched).
- **Backward compatible**, or bump `Kit.API` in `kit.lua`: an older consumer then fails loudly
  with a message, never silently changes meaning.

## What belongs here

- **Mechanics only** in `core/stubs.lua`. A client API (a `C_*` table, a unit or bag function)
  belongs in the consumer's stub, verified in the dump. Every client global the core defines is
  in `Kit.CORE_GLOBALS` and checked against the build's data (`Kit.checkCore`).
- **A behaviour change to a core method changes every consumer's tests** at their next pin bump.
  Model only what was measured on the client or read in Blizzard's source, and say which in a
  comment. Never add a method no consumer had.
- `data/` is generated: `tools/gen_data.lua <dump>`. Never edit it. `tests/test_data.lua` checks it
  matches the dumps on this machine.
- Not here: an addon's loader, its client APIs, packaging and release scripts.

## Commands

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_core.lua           # one test, from the repo root
& .\scripts\run.ps1 -RepoRoot . -Extra kit.lua,core\stubs.lua,checks\methods.lua   # all of them (from a pwsh prompt: -File would pass the list as one string)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tools\gen_data.lua ..\References\Forever\api\forever-api-1.60.1.<build>.md
```

Mutation-test every new assertion: break the behaviour, confirm it goes red.

## Workflow

Issue → branch off `main` → PR with `Closes #N`. The owner merges. Never commit to `main`.
