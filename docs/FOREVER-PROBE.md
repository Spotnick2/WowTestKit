# What WowTestKitProbe measured

The kit's probe, `tools/WowTestKitProbe` (`/fp tk`), measures client behaviour a core model
needs, so the model follows the client rather than a guess. Each section names the build, the
date, the procedure and the core code that follows it. Addon-agnostic findings also belong in
`References\Docs\PORTING-TBC-TO-FOREVER.md`.

## SetParent: scripts and frame level (WowTestKit #99)

1.60.1 build 70959, 2026-11-18, out of combat, `/fp steps tk reparent` (run #392). Plain,
empty frames of the probe's own: S shown and H hidden under UIParent, C under S with a child G.
Raw lines: `WowTestKitProbeDB.log` (`REPARENT ...`).

**Scripts**
| Case | Scripts during the call |
|---|---|
| C: S → H (visible → hidden) | `G:OnHide`, then `C:OnHide`; C's `GetParent()` is already H |
| C: H → S (hidden → visible) | `G:OnShow`, then `C:OnShow` |
| C: S → nil (visible → visible) | none |
| C: nil → H, then H → nil | OnHide on both, then OnShow on both, children first |
| a hidden C: nil → H, then H → S | none |
| `C:Hide()`, then `C:Show()` (controls) | children first too: `G` before `C` |
| U (no parent) → UIParent hidden by Alt+Z, then back to nil | OnHide, then OnShow, children first |

Every script ran during the call: nothing fired late (the step a second later saw only the
probe's own clean-up, run outside any case).

**Frame level**
| Case | Level after |
|---|---|
| made under UIParent (0) | 1; a child made under a 7 is 8 |
| a 7 → under a 10 | 11, its child 12 |
| → no parent | 0, its child 1 |
| → UIParent | 1, its child 2 |
| a 50 → under a 3 | 4 (lowered), its child 5 |
| a 2 → under a 10 | 11 (raised), its child 12 |
| with `SetFixedFrameLevel(true)`, `SetFrameLevel(7)`, → under a 3 | 11, unchanged (`HasFixedFrameLevel` true) |
| a MEDIUM frame → under a HIGH one | its strata becomes HIGH |

**In the core** (`Methods.SetParent`, `settle`): a reparent that changes visibility runs the
OnShow / OnHide walk after the parent's lists move, and every walk (Show, Hide, SetParent) runs
children before their parent. The level becomes the new parent's + 1 (0 with no parent), each
descendant one above its parent. Not modelled: a fixed frame level (the core has no
`SetFixedFrameLevel`; and whether its `SetFrameLevel(7)` was ignored or undone isn't told apart
here) and the strata following the parent. Not measured: siblings' order in a walk, a deeper
tree, a descendant given a level of its own, a script that reparents during the walk.
