---
title: animation
description: Packed KeyframeSequence assets.
sidebar:
 order: 2
---

```luau
local animation = require(game.ReplicatedStorage.reel).animation
```

## `AnimationAsset`

An immutable, packed representation of a `KeyframeSequence`.

| Field | Meaning |
| --- | --- |
| `length` | Last source keyframe time, including marker-only keyframes |
| `pose_length` | Last keyframe time that contains poses, `0` when the sequence has no poses |
| `looped` | Source `KeyframeSequence.Loop` |
| `priority` | Source priority, with `Core` remapped to `-1` |
| `channels` | Per-target spans into the packed key arrays |
| `name_to_channel` | Target name to channel index lookup |
| `markers` | Dense, time-ordered `Marker` records from source keyframes |
| packed key arrays | Times, inverse durations, positions, quaternions, and easing functions |

Assets and their internal arrays are frozen after loading. 
One asset can be shared by every compatible character.

### `Marker`

```luau
type Marker = {
	time: number,
	name: string,
	value: string,
}
```

Each `KeyframeMarker` becomes one immutable record in `asset.markers`.
Markers are separate from pose channels: they never create packed solver keys or an animation binding entry.

A marker-only sequence therefore has an empty `channels` array and no packed pose data, while its `markers` and `length` are still available.
In a mixed sequence, marker-only keyframes likewise do not affect solver keys.
A marker after the final pose extends `length`, sampling continues to hold the last pose until that time.

The solver does not dispatch marker events or retain playback history.
A player should consume `asset.markers` as its time position advances, typically using the interval `previous_time < marker.time <= current_time`.
When looping across the end, query the tail of the clip and then its beginning as two intervals.
This keeps repeated, out-of-order, and parallel solver samples side-effect free.

### `MarkerAsset`

```luau
type MarkerAsset = {
	length: number,
	markers: { Marker },
}
```

This is the immutable marker-only representation returned by `extract_markers()`.
Its `length` still uses the last source keyframe, even when that keyframe has no marker.

## `AnimationBinding`

An immutable mapping between one asset and one rig layout:

| Field | Meaning |
| --- | --- |
| `active_count` | Number of matching targets |
| `active_rig_indices` | Descriptor index for each match |
| `active_channel_indices` | Asset channel index for the same match |

A binding does not retain an asset or descriptor reference. 
Always use it with the same asset and compatible descriptor that created it.

## Functions

### `load_keyframe_sequence(sequence)`

```luau
load_keyframe_sequence(sequence: KeyframeSequence): AnimationAsset
```

Reads the pose tree into packed channels.
It traverses children even if a parent pose has zero weight.
A pose with `Weight == 0` contributes no key for its own target, any non-zero weight contributes the full pose transform.

If a channel begins after time zero, its first key is duplicated at zero.

Duplicate target names at one timestamp, ambiguous target paths across timestamps, and duplicate or descending channel times are rejected.

A sequence with exactly two source keyframes whose first keyframe is not at time zero is also rejected. Markers and poses both count because this preserves the source shape that avoids the unsupported two-keyframe behavior.

Supported pose easing styles/directions are all the easing styles that roblox natively supports for KeyframeSequences.

### `extract_markers(sequence)`

```luau
extract_markers(sequence: KeyframeSequence): MarkerAsset
```

Reads only the sequence length and marker records.
Use it when marker playback metadata is needed without packing pose channels.
It applies the same source-keyframe sorting and unsupported two-keyframe-shape validation as `load_keyframe_sequence()`.

### `bind_animation(asset, rig_or_desc)`

```luau
bind_animation(asset: AnimationAsset, rig_or_desc: RigState | RigDesc): AnimationBinding
```

Builds the dense mapping from channels whose names match rig targets.
Passing a `RigDesc` makes binding sharing explicit, passing a `RigState` uses its `desc`.