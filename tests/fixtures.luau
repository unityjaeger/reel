--!strict

type PoseOptions = {
	weight: number?,
	easing_style: EnumItem?,
	easing_direction: EnumItem?,
	subposes: { Pose }?,
}

type SequenceOptions = {
	looped: boolean?,
	priority: EnumItem?,
}

export type AssetKey = {
	time: number,
	transform: CFrame,
	easing: ((number) -> number)?,
}

export type AssetChannel = {
	name: string,
	keys: { AssetKey },
}

export type AssetMarker = {
	read time: number,
	read name: string,
	read value: string,
}

export type BindingPair = {
	rig_index: number,
	channel_index: number,
}

export type DescNode = {
	name: string,
	parent: number?,
	is_bone: boolean?,
	c0: CFrame?,
	c1_inv: CFrame?,
	bind: CFrame?,
}

type MotorModelOptions = {
	model_name: string?,
	root_name: string?,
	middle_name: string?,
	leaf_name: string?,
	root_c0: CFrame?,
	root_c1: CFrame?,
	child_c0: CFrame?,
	child_c1: CFrame?,
	child_uses_root: boolean?,
	reverse_motor_order: boolean?,
}

export type MotorModelHandles = {
	root: Part,
	middle: Part,
	leaf: Part,
	root_motor: Motor6D,
	child_motor: Motor6D,
}

type BoneModelOptions = {
	model_name: string?,
	part_name: string?,
	root_name: string?,
	child_name: string?,
	root_bind: CFrame?,
	child_bind: CFrame?,
}

export type BoneModelHandles = {
	part: Part,
	root: Bone,
	child: Bone,
}

local IDENTITY = CFrame.identity

local function linear(alpha: number): number
	return alpha
end

local function pose(name: string, cframe: CFrame?, options: PoseOptions?): Pose
	local config: PoseOptions = options or {}
	local result = Instance.new("Pose")
	result.Name = name
	result.CFrame = cframe or IDENTITY
	result.Weight = if config.weight == nil then 1 else config.weight
	result.EasingStyle = (config.easing_style or Enum.PoseEasingStyle.Linear) :: any
	result.EasingDirection = (config.easing_direction or Enum.PoseEasingDirection.In) :: any

	local subposes = config.subposes
	if subposes ~= nil then
		for _, subpose in subposes do
			result:AddSubPose(subpose)
		end
	end

	return result
end

local function keyframe(time: number, poses: { Pose }): Keyframe
	local result = Instance.new("Keyframe")
	result.Time = time

	for _, root_pose in poses do
		result:AddPose(root_pose)
	end

	return result
end

local function sequence(keyframes: { Keyframe }, options: SequenceOptions?): KeyframeSequence
	local config: SequenceOptions = options or {}
	local result = Instance.new("KeyframeSequence")
	result.Loop = config.looped == true
	result.Priority = (config.priority or Enum.AnimationPriority.Action) :: any

	for _, frame in keyframes do
		result:AddKeyframe(frame)
	end

	return result
end

--builds the same frozen packed shape returned by animation_load
--this intentionally bypasses the loader so solver tests isolate solver behavior
local function asset(
	channels_in: { AssetChannel },
	priority: number?,
	looped: boolean?,
	markers_in: { AssetMarker }?
): any
	local channels = table.create(#channels_in)
	local name_to_channel: { [string]: number } = {}
	local markers: { AssetMarker } = {}
	local key_times: { number } = {}
	local key_inv_durations: { number } = {}
	local key_positions: { vector } = {}
	local key_quat_vectors: { vector } = {}
	local key_quat_scalars: { number } = {}
	local key_easing_functions: { (number) -> number } = {}
	local length = 0

	for channel_index, channel_in in channels_in do
		local keys = table.clone(channel_in.keys)
		table.sort(keys, function(a: AssetKey, b)
			return a.time < b.time
		end)

		local key_start = #key_times + 1
		local key_count = #keys
		channels[channel_index] = table.freeze({
			count = key_count,
			key_start = key_start,
		})
		name_to_channel[channel_in.name] = channel_index

		for key_offset, key in keys do
			local transform = key.transform
			local axis, angle = transform:ToAxisAngle()
			local half_angle = angle * 0.5
			local key_index = key_start + key_offset - 1

			key_times[key_index] = key.time
			key_positions[key_index] = transform.Position :: any
			key_quat_vectors[key_index] = axis * math.sin(half_angle) :: any
			key_quat_scalars[key_index] = math.cos(half_angle)
			key_easing_functions[key_index] = key.easing or linear

			if key.time > length then
				length = key.time
			end
		end

		for key_offset = 1, key_count - 1 do
			local key_index = key_start + key_offset - 1
			local duration = key_times[key_index + 1] - key_times[key_index]
			key_inv_durations[key_index] = 1 / duration
		end
	end

	local pose_length = length
	for _, marker_in in markers_in or {} do
		table.insert(markers, table.freeze({
			time = marker_in.time,
			name = marker_in.name,
			value = marker_in.value,
		}))

		if marker_in.time > length then
			length = marker_in.time
		end
	end

	table.sort(markers, function(a: AssetMarker, b)
		return a.time < b.time
	end)

	table.freeze(channels)
	table.freeze(name_to_channel)
	table.freeze(markers)
	table.freeze(key_times)
	table.freeze(key_inv_durations)
	table.freeze(key_positions)
	table.freeze(key_quat_vectors)
	table.freeze(key_quat_scalars)
	table.freeze(key_easing_functions)

	return table.freeze({
		length = length,
		pose_length = pose_length,
		looped = looped == true,
		priority = priority or 0,
		channels = channels,
		name_to_channel = name_to_channel,
		markers = markers,
		key_times = key_times,
		key_inv_durations = key_inv_durations,
		key_positions = key_positions,
		key_quat_vectors = key_quat_vectors,
		key_quat_scalars = key_quat_scalars,
		key_easing_functions = key_easing_functions,
	})
end

local function binding(pairs: { BindingPair }): any
	local count = #pairs
	local active_rig_indices = table.create(count)
	local active_channel_indices = table.create(count)

	for index, pair in pairs do
		active_rig_indices[index] = pair.rig_index
		active_channel_indices[index] = pair.channel_index
	end

	return {
		active_count = count,
		active_rig_indices = active_rig_indices,
		active_channel_indices = active_channel_indices,
	}
end

local function desc(nodes: { DescNode }): any
	local count = #nodes
	local names = table.create(count)
	local parent = table.create(count)
	local is_bone = table.create(count)
	local name_to_index: { [string]: number } = {}
	local c0 = table.create(count)
	local c1_inv = table.create(count)
	local bind = table.create(count)

	for index, node in nodes do
		names[index] = node.name
		parent[index] = node.parent or 0
		is_bone[index] = node.is_bone == true
		name_to_index[node.name] = index
		c0[index] = node.c0 or IDENTITY
		c1_inv[index] = node.c1_inv or IDENTITY
		bind[index] = node.bind or IDENTITY
	end

	return {
		count = count,
		names = names,
		parent = parent,
		is_bone = is_bone,
		name_to_index = name_to_index,
		c0 = c0,
		c1_inv = c1_inv,
		bind = bind,
	}
end

local function rig_state(rig_desc: any): any
	return {
		desc = rig_desc,
		motors = {},
		bones = {},
		transforms = table.create(rig_desc.count, IDENTITY),
		world_transforms = nil,
		blend_scratch = nil,
	}
end

local function part(name: string, parent: Instance): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Parent = parent
	return result
end

local function motor_model(options: MotorModelOptions?): (Model, MotorModelHandles)
	local config: MotorModelOptions = options or {}
	local model = Instance.new("Model")
	model.Name = config.model_name or "MotorRig"

	local root = part(config.root_name or "Root", model)
	local middle = part(config.middle_name or "Torso", model)
	local leaf = part(config.leaf_name or "Arm", model)

	local root_motor = Instance.new("Motor6D")
	root_motor.Name = "RootJoint"
	root_motor.Part0 = root
	root_motor.Part1 = middle
	root_motor.C0 = config.root_c0 or IDENTITY
	root_motor.C1 = config.root_c1 or IDENTITY

	local child_motor = Instance.new("Motor6D")
	child_motor.Name = "Shoulder"
	child_motor.Part0 = if config.child_uses_root == true then root else middle
	child_motor.Part1 = leaf
	child_motor.C0 = config.child_c0 or IDENTITY
	child_motor.C1 = config.child_c1 or IDENTITY

	if config.reverse_motor_order == true then
		child_motor.Parent = model
		root_motor.Parent = model
	else
		root_motor.Parent = model
		child_motor.Parent = model
	end

	return model, {
		root = root,
		middle = middle,
		leaf = leaf,
		root_motor = root_motor,
		child_motor = child_motor,
	}
end

local function bone_model(options: BoneModelOptions?): (Model, BoneModelHandles)
	local config: BoneModelOptions = options or {}
	local model = Instance.new("Model")
	model.Name = config.model_name or "BoneRig"

	local host = part(config.part_name or "Mesh", model)

	local root = Instance.new("Bone")
	root.Name = config.root_name or "RootBone"
	root.CFrame = config.root_bind or IDENTITY
	root.Parent = host

	local child = Instance.new("Bone")
	child.Name = config.child_name or "ChildBone"
	child.CFrame = config.child_bind or IDENTITY
	child.Parent = root

	return model, {
		part = host,
		root = root,
		child = child,
	}
end

local function destroy(instance: Instance)
	instance:Destroy()
end

return {
	pose = pose,
	keyframe = keyframe,
	sequence = sequence,

	asset = asset,
	direct_asset = asset,
	binding = binding,
	desc = desc,
	rig_state = rig_state,

	motor_model = motor_model,
	bone_model = bone_model,
	destroy = destroy,
}