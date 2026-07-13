---
title: shared rigs
description: Explains how to reuse rigs.
---

`RigDesc`, `AnimationAsset`, and `AnimationBinding` are immutable setup data.
A `RigState` is per character and owns its current transforms, Instance references and optional buffers.

For a set of identical characters, load one description and bind every clone to it:
```luau
local desc = rig_api.load_rig_desc(models[1])
local asset = animation.load_keyframe_sequence(sequence)
local binding = animation.bind_animation(asset, desc)

local rigs = table.create(#models)
for index, model in models do
	rigs[index] = rig_api.bind_rig(desc, model)
end
```

Every `RigState` gets independent `transforms`, `motors`, `bones`, world output, and blend scratch.
The descriptor and binding are safe to share with every state that has the same layout.

## What `bind_rig()` validates
Binding is intentionally strict about animation-relevant structure. It checks:
- the total target count
- globally unique animation target names
- target presence and target type (`Motor6D` or `Bone`)
- the animated parent target of every target
- Motor6D `C0` and `C1`
- Bone bind `CFrame` values

The traversal order does not need to match the template. 
Reel maps actual Motor6D/Bone Instances into descriptor-index order after validation.

Offsets are compared with `CFrame:FuzzyEq`, so harmless floating-point variation is accepted.
Unrelated data such as a model name, part size, Motor6D Instance name, or an untargeted root `Part0` name does not participate in binding.

## Offline or custom states
Use `rig_api.create_rig_state(desc, motors, bones)` only when another system has already produced Instance arrays in descriptor-index order, or when no Instances are needed.
It does not scan or validate a model.

See the [rig reference](/reel/reference/rig/) for the descriptor layout and all binding
errors.