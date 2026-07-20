---
title: rig
description: Static rig descriptions and per-rig states.
sidebar:
 order: 1
---

```luau
local rig_api = require(game.ReplicatedStorage.reel).rig
```

## `RigDesc`

`RigDesc` is immutable static layout data.
Its arrays use descriptor indices, which are ordered parent before child.

| Field | Meaning |
| --- | --- |
| `count` | Number of joint/Bone animation targets |
| `names` | Target name at each descriptor index |
| `parent` | Parent descriptor index, or `0` for a root |
| `is_bone` | Whether the target uses Bone world-transform math |
| `name_to_index` | Target-name lookup |
| `c0`, `c1_inv` | Motor6D or AnimationConstraint static offsets |
| `bind` | Bone `CFrame` |

Motor6D and AnimationConstraint targets use `Part1.Name`, Bone targets use `Bone.Name`.
Target names must be unique across the whole rig.
AnimationConstraints must have `IsKinematic` enabled.

## `RigState`

`RigState` is mutable and belongs to one character.

| Field | Meaning |
| --- | --- |
| `desc` | Shared static descriptor |
| `motors`, `bones` | Sparse Instance arrays aligned to descriptor indices, `motors` contains Motor6Ds or AnimationConstraints |
| `transforms` | Current local solver output |
| `world_transforms` | Optional retained world-output array |
| `blend_scratch` | Optional native multi-track scratch |

:::note
`motors` and `bones` are only sparse when both joints and Bones are present in the rig.
The `motors` name is retained for API compatibility.
:::

## Functions

### `load_rig(model)`

```luau
load_rig(model: Model): RigState
```

Scans a model once, creates a frozen descriptor, and returns the matching state.

### `load_rig_desc(model)`

```luau
load_rig_desc(model: Model): RigDesc
```

Builds only the frozen static layout. It retains no template Instances.

### `bind_rig(desc, model)`

```luau
bind_rig(desc: RigDesc, model: Model): RigState
```

Validates that `model` is animation-equivalent to `desc`, then returns fresh local state with its joint/Bone references reordered into descriptor-index order.

The validation rejects mismatched target count, names, joint/Bone types, animated parents, joint offsets, Bone bind transforms, non-kinematic AnimationConstraints, duplicate targets, and cycles.
Motor6D and kinematic AnimationConstraint targets are interchangeable when their target names, hierarchy, and offsets match.

### `create_rig_state(desc, motors?, bones?)`

```luau
create_rig_state(
	desc: RigDesc,
	motors: { (Motor6D | AnimationConstraint)? }?,
	bones: { Bone? }?
): RigState
```

Creates a state without scanning or validating a model.
Supplied arrays must already be descriptor-indexed.

### `allocate_blend_scratch(rig)`

```luau
allocate_blend_scratch(rig: RigState): BlendScratch
```

Idempotently allocates the buffers required by a native solve with two or more effective tracks.
Call this during setup for any rig that can blend native tracks.

### `get_world_transforms(rig)`

```luau
get_world_transforms(rig: RigState): { CFrame }
```

Idempotently allocates the retained output used by
[`compute_world_transforms()`](/reference/solver/#compute_world_transforms).
It does not compute any transforms itself.