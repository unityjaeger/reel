---
title: delta layers
description: Explains how to use additive/subtractive blending.
---

Delta clips are authored relative to 'CFrame.identity'.
Identity means no effect, translation and rotation are the offset applied to the current local transform.

```luau
local delta_state = {
	binding = animation.bind_animation(recoil_asset, rig.desc),
	time_position = 0,
	weight = 1,
}

local prepared_deltas = solver.prepare_delta_tracks({
	{
		asset = recoil_asset,
		state = delta_state,
		mode = "additive",
	},
})
```

The frame order is always:

```luau
solver.solve_prepared(rig, native_prepared)
solver.apply_delta_prepared(rig, prepared_deltas)
```

:::danger
`apply_delta_prepared()` edits `rig.transforms` in place.
Calling it again without a fresh native solve compounds the previous delta result.
:::

## Modes and order

For each bound target, Reel first applies the delta weight from identity.
It then chooses the operation:

```
additive:    base * weightedDelta
subtractive: base * inverse(weightedDelta)
```

Delta preparation preserves the array order you supply.
It does not sort by priority.
Rotation composition is not commutative, so layer order is observable:

```
base * aim * inverse(correction) * recoil
```

An immediately adjacent additive and subtractive use of the same weighted delta cancels exactly.

## Authoring notes

- Author a neutral channel as `CFrame.identity`
- Add an identity key at time zero when the layer should begin neutral
- Missing channels leave that rig target unchanged, allowing partial-body overlays
- Keep the binding paired with the same asset that created it

The animation loader duplicates a channel's first key at time zero when that key starts later.
For delta clips, an omitted identity key can therefore make a non-identity offset active immediately.

Delta tracks do not use native blend scratch.
Their cost is proportional to their bound channels.