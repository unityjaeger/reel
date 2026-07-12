---
title: animation
description: Packed KeyframeSequence assets.
sidebar:
 order: 3
---

```luau
local animation = require(game.ReplicatedStorage.reel).animation
```

## `AnimationAsset`

An immutable, packed representation of a `KeyframeSequence`.

| Field | Meaning |
| --- | --- |
| `length` | Last keyframe time |
| `looped` | Source `KeyframeSequence.Loop` |
| `priority` | Source priority, with `Core` remapped to `-1` |
| `channels` | Per-target spans into the packed key arrays |
| `name_to_channel` | Target name to channel index lookup |
| packed key arrays | Times, inverse durations, positions, quaternions, and easing functions |

Assets and their internal arrays are frozen after loading. 
One asset can be shared by every compatible character.

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

A sequence with exactly two keyframes whose first keyframe is not at time zero is also rejected.

Supported pose easing styles/directions are all the easing styles that roblox natively supports for KeyframeSequences.

### `bind_animation(asset, rig_or_desc)`

```luau
bind_animation(asset: AnimationAsset, rig_or_desc: RigState | RigDesc): AnimationBinding
```

Builds the dense mapping from channels whose names match rig targets.
Passing a `RigDesc` makes binding sharing explicit, passing a `RigState` uses its `desc`.