---
title: world transforms
description: Explains how to generate world transforms.
---

World reconstruction is separate from local solving.
Skip it when you only need to commit `Motor6D.Transform` or `Bone.Transform` for playback.

```luau
solver.solve_prepared(rig, prepared)
local world = solver.compute_world_transforms(rig, character:GetPivot())
```

For optimal performance, manage the output array yourself:

```luau
local world = table.create(rig.desc.count)

solver.solve_prepared(rig, prepared)
solver.apply_delta_prepared(rig, deltas)
solver.compute_world_transforms(rig, character:GetPivot(), world)
```

When `out` is omitted, the first call allocates `rig.world_transforms` and later calls reuse it.
Pass a preallocated array when you want that ownership explicit.

## Formulas

Descriptor indices are parent before child, so reconstruction is one iterative pass with no Instance hierarchy traversal:

```
Motor6D: parentWorld * C0 * localTransform * inverse(C1)
Bone:    parentWorld * bindCFrame * localTransform
```

The supplied root `CFrame` is used for every descriptor target whose parent index is zero.
Use the root transform from the same moment you are evaluating.

One call accepts one root transform.
Descriptors with unrelated root hierarchies cannot use distinct root transforms in the same reconstruction pass.