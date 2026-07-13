---
title: performance
description: Notes about performance.
---

Reel separates immutable setup data from mutable runtime data so a large group of matching characters can avoid repeated loading and binding work.

## Data ownership

| Data | Recommended ownership |
| --- | --- |
| `AnimationAsset` | Shared per animation |
| `RigDesc` | Shared per matching skeleton |
| `AnimationBinding` | Shared per asset/descriptor pair |
| `RigState` | One per character and worker |
| `AnimationState` / `DeltaState` | One per playing track and character |
| Prepared native/delta lists | Owned by the character or worker that mutates them |

Assets, descriptors, and bindings are frozen.
Do not share mutable rig state, track state, or prepared lists across Actors.

## Parallel Luau shape

Partition characters by Actor or small batches of characters.

Within each worker:
1. Update local track states
2. Call `solve_prepared()`
3. Optionally apply delta layers and reconstruct world transforms
4. Call `task.synchronize()` before assigning `Motor6D.Transform` or `Bone.Transform`

Keep one descriptor and one binding per compatible asset/rig layout in that worker.
Avoid splitting the solve for a single small rig across workers, the coordination cost usually dominates.

## Allocation rules

- Load `KeyframeSequence` assets and rigs during setup, never per frame
- Reuse prepared lists while track membership and priority are stable
- Allocate native blend scratch once for rigs that can blend two effective tracks
- Pass a preallocated world output array in hot loops
- Skip delta processing and world reconstruction when the caller does not need them

Profile solving, world reconstruction, and Instance commits separately for parallel luau.