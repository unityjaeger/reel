---
title: multiple tracks
description: Explains how to work with multiple tracks.
---

Use `prepare_tracks()` with a dense array of active native tracks:

```luau
local prepared = solver.prepare_tracks({
	{ asset = walk_asset, state = walk_state },
	{ asset = aim_asset, state = aim_state },
})
```

If a rig may ever solve two or more effective native tracks, allocate its scratch once during setup:

```luau
rig_api.allocate_blend_scratch(rig)
```

This is deliberate.
Single-track and static NPCs do not pay for unused blend buffers.
The call is idempotent.

A track is effective when its weight is greater than `1e-5` and its binding has at least one active channel.
Solves with zero or one effective track do not use scratch.
A multi-track solve without preallocated scratch fails.

## Priorities and weights

`AnimationState.priority` overrides `AnimationAsset.priority` when not `nil`.
Higher-priority tracks consume a target's available weight first.
Lower-priority tracks fill only what remains for that target.
Tracks in one priority group share that group's capacity.

(identical to how roblox does it)

This is evaluated per target.
A high-priority arm overlay does not suppress a lower-priority leg animation when the overlay has no leg channel.

Use weights in the normal `0` to `1` range.
Values at or below `1e-5` are ignored.
For one track, a value at or above one is full influence.
In a multi-track group, the solver scales competing tracks to the available capacity.

## Reusing preparation

Preparation sorts dense tracks and caches priority groups.
Keep the object and reuse it when the list changes:

```luau
prepared = solver.prepare_tracks(current_tracks, prepared)
```

Changing only `time_position` or `weight` is live, changing a track's asset, state, membership, or priority requires re-preparation.

Native tracks produce the base pose.
Apply any [delta layers](/reel/guides/delta_layers/) after this solve.