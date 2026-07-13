---
title: solver
description: Solve a list of animations.
sidebar:
 order: 1
---

```luau
local solver = require(game.ReplicatedStorage.reel).solver
```

## Native tracks

```luau
type AnimationState = {
	binding: AnimationBinding,
	time_position: number,
	weight: number,
	priority: number?,
}

type PlayingTrack = {
	asset: AnimationAsset,
	state: AnimationState,
}

type PreparedTrack = {
	asset: AnimationAsset,
	state: AnimationState,
	priority: number,
}

type PriorityGroup = {
	start: number,
	stop: number,
}

type PreparedPlaying = {
	count: number,
	tracks: { PreparedTrack },

	group_count: number,
	groups: { PriorityGroup },
}
```

`time_position` and `weight` are live inputs.
`priority` overrides the asset priority when not `nil`.

`PreparedPlaying` is the reusable result of native preparation. 
Its tracks and priority groups are solver-owned cache data, callers should retain and pass it back as `out`, not edit its internals.

### `prepare_tracks(tracks, out?)`

```luau
prepare_tracks(
	tracks: { PlayingTrack },
	out: PreparedPlaying?
): PreparedPlaying
```

Builds or reuses a dense, priority-sorted native track list.
It caches priority groups, so call it when membership, assets, state objects, or priorities change.

### `solve_prepared(rig, prepared)`

```luau
solve_prepared(rig: RigState, prepared: PreparedPlaying): ()
```

Samples and blends into `rig.transforms`.
It neither advances time nor commits Instance properties.
Allocate blend scratch first when two or more effective native tracks may run together.

## Delta tracks

```luau
type DeltaMode = "additive" | "subtractive"

type DeltaState = {
	binding: AnimationBinding,
	time_position: number,
	weight: number,
}

type DeltaTrack = {
	asset: AnimationAsset,
	state: DeltaState,
	mode: DeltaMode,
}

export type PreparedDeltaTrack = {
	asset: AnimationAsset,
	state: DeltaState,
	inverse: boolean,
}

export type PreparedDelta = {
	count: number,
	tracks: { PreparedDeltaTrack },
}
```

`PreparedDelta` is the reusable ordered result of delta preparation.
Its cached mode data is refreshed whenever you prepare again.

### `prepare_delta_tracks(tracks, out?)`

```luau
prepare_delta_tracks(
	tracks: { DeltaTrack },
	out: PreparedDelta?
): PreparedDelta
```

Builds or reuses a delta list in supplied array order.
It validates the mode and caches whether a track is subtractive.

### `apply_delta_prepared(rig, prepared)`

```luau
apply_delta_prepared(rig: RigState, prepared: PreparedDelta): ()
```

Composes weighted identity-relative delta transforms into the current local result.
Call it after `solve_prepared()` and before committing or reconstructing world transforms.

## World output

### `compute_world_transforms(rig, root_cframe, out?)`

```luau
compute_world_transforms(
	rig: RigState,
	root_cframe: CFrame,
	out: { CFrame }?
): { CFrame }
```

Writes each target's world transform to `out`, or lazily allocates and reuses `rig.world_transforms` when `out` is omitted.
It uses the latest `rig.transforms`, it does not solve first.