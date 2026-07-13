---
title: introduction
description: Introduction to the library.
---

# Reel
Reel is a custom animation solver that aims to have 1:1 roblox animation solver behavior.
It also implements additive and subtractive animation blending.

# Installation
Either grab the .rbxm from the [latest release](https://github.com/unityjaeger/reel/releases/latest)

or get it through wally:
```
reel = "unityjaeger/reel@0.1.0"
```

:::note
Read the [reference](/reel/reference/rig/) first to familiarize yourself with the library.
:::

# Use Cases
- no instances needed, enabling things like ping compensation for hit detection
- additive and subtractive animation blending
- full control, if you want specific behavior then you can implement that into a custom player

# Usage Example
Minimal playback example.

```luau
local reel = require(game.ReplicatedStorage.reel)

local animation = reel.animation
local rig_api = reel.rig
local solver = reel.solver

local RunService = game:GetService("RunService")

local sequence = game.ServerStorage.Walk
local character = workspace.Character

local asset = animation.load_keyframe_sequence(sequence)
local rig = rig_api.load_rig(character)
local binding = animation.bind_animation(asset, rig.desc)

local state = {
	binding = binding,
	time_position = 0,
	weight = 1,
	priority = nil, -- use asset.priority
}

local prepared = solver.prepare_tracks({
	{ asset = asset, state = state },
})

local started_at = os.clock()

RunService.PreAnimation:Connect(function()
	local elapsed = os.clock() - started_at
	if asset.looped and asset.length > 0 then
		state.time_position = elapsed % asset.length
	else
		state.time_position = math.min(elapsed, asset.length)
	end

	solver.solve_prepared(rig, prepared)

	for index, motor in rig.motors do
		motor.Transform = rig.transforms[index]
	end

	for index, bone in rig.bones do
		bone.Transform = rig.transforms[index]
	end
end)
```

The one-track path does not need blend scratch.
`solve_prepared()` writes only to `rig.transforms`, committing `Motor6D.Transform` and `Bone.Transform` remains the caller's responsibility.

# Frame responsibilities

Before solving, update each active track's `time_position` and `weight`. 
Reel does not manage speed, loops, fades, stopping, events, or replication.

Prepare the dense track list when its membership or priority structure changes:

```luau
prepared = solver.prepare_tracks(current_tracks, prepared)
```

You may update `time_position` and `weight` without preparing again.
Re-prepare when a track is added, removed, replaced, or receives a different priority.