--!strict

const rig_load = require("./rig")
const easing_map = require("./easing_map")

export type PoseKey = {
	read time: number,

	read position: vector,
	read quat_vector: vector,
	read quat_scalar: number,

	read easing_function: (number) -> number,
}

export type Channel = {
	read count: number,
	read key_start: number,
}

export type Marker = {
	read time: number,
	read name: string,
	read value: string,
}

export type AnimationAsset = {
	read length: number,
	read pose_length: number,
	read looped: boolean,
	read priority: number,

	read channels: { Channel },
	read name_to_channel: { [string]: number },

	read markers: { Marker },

	read key_times: { number },
	read key_inv_durations: { number },
	read key_positions: { vector },
	read key_quat_vectors: { vector },
	read key_quat_scalars: { number },
	read key_easing_functions: { (number) -> number },
}

export type MarkerAsset = {
	read length: number,
	read markers: { Marker },
}

export type AnimationBinding = {
	read active_count: number,
	read active_rig_indices: { number },
	read active_channel_indices: { number },
}

const function quat_normalize(v: vector, s: number): (vector, number)
	local length = math.sqrt(vector.dot(v, v) + s * s)

	if length == 0 then
		return vector.zero, 1
	end

	local inv = 1 / length
	return v * inv, s * inv
end

const function clone_pose_key_at_time(key: PoseKey, time: number): PoseKey
	return table.freeze({
		time = time,

		position = key.position,
		quat_vector = key.quat_vector,
		quat_scalar = key.quat_scalar,

		easing_function = key.easing_function,
	})
end

const function pack_channel(
	keys: { PoseKey },
	key_times: { number },
	key_inv_durations: { number },
	key_positions: { vector },
	key_quat_vectors: { vector },
	key_quat_scalars: { number },
	key_easing_functions: { (number) -> number }
): Channel
	table.sort(keys, function(a: PoseKey, b: PoseKey)
		return a.time < b.time
	end)

	if keys[1] ~= nil and keys[1].time > 0 then
		table.insert(keys, 1, clone_pose_key_at_time(keys[1], 0))
	end

	local count = #keys
	local key_start = #key_times + 1

	local channel: Channel = {
		count = count,
		key_start = key_start,
	}

	for index, key in keys do
		local quat_vector, quat_scalar = quat_normalize(key.quat_vector, key.quat_scalar)
		local key_index = key_start + index - 1

		key_times[key_index] = key.time
		key_positions[key_index] = key.position
		key_quat_vectors[key_index] = quat_vector
		key_quat_scalars[key_index] = quat_scalar
		key_easing_functions[key_index] = key.easing_function
	end

	for index = 1, count - 1 do
		local key_index = key_start + index - 1
		local duration = key_times[key_index + 1] - key_times[key_index]

		if duration <= 0 then
			error("channel has duplicate or descending keyframe times")
		end

		key_inv_durations[key_index] = 1 / duration
	end

	return table.freeze(channel)
end

type PoseKeyBuckets = { [string]: { PoseKey } }

const function get_sequence_keyframes(sequence: KeyframeSequence): { Keyframe }
	local keyframes = sequence:GetKeyframes() :: { Keyframe }

	table.sort(keyframes, function(a: Keyframe, b: Keyframe)
		return a.Time < b.Time
	end)

	if #keyframes == 2 and keyframes[1].Time ~= 0 then
		error("unsupported KeyframeSequence, only 2 keyframes exist and neither of them are at Time = 0")
	end

	return keyframes
end

const function read_markers(keyframes: { Keyframe }): (number, { Marker })
	local markers: { Marker } = {}
	local length = 0

	for _, keyframe in keyframes do
		for _, marker: KeyframeMarker in keyframe:GetMarkers() do
			table.insert(markers, table.freeze({
				time = keyframe.Time,
				name = marker.Name,
				value = marker.Value,
			}))
		end

		length = keyframe.Time
	end

	table.freeze(markers)

	return length, markers
end

const function add_pose_key(out: PoseKeyBuckets, name: string, key: PoseKey)
	local keys = out[name]
	if keys == nil then
		keys = {}
		out[name] = keys
	end

	table.insert(keys, key)
end

const function read_pose_tree(
	pose: Pose,
	time: number,
	out: PoseKeyBuckets,
	seen_at_time: { [string]: string },
	first_path_by_name: { [string]: string },
	parent_path: string
)
	local name = pose.Name
	local path = if parent_path == "" then name else parent_path .. "/" .. name

	for _, child in pose:GetSubPoses() :: { Pose } do
		read_pose_tree(child, time, out, seen_at_time, first_path_by_name, path)
	end

	if pose.Weight == 0 then
		return
	end

	local duplicate_path = seen_at_time[name]
	if duplicate_path ~= nil then
		error(`duplicate animation target "{name}" at time {time}: "{duplicate_path}" and "{path}"`)
	end
	seen_at_time[name] = path

	local first_path = first_path_by_name[name]
	if first_path == nil then
		first_path_by_name[name] = path
	elseif first_path ~= path then
		error(`ambiguous animation target "{name}" appears at both "{first_path}" and "{path}"`)
	end

	local cframe = pose.CFrame
	local axis, angle = cframe:ToAxisAngle()
	local half_angle = angle * 0.5

	add_pose_key(out, name, table.freeze({
		time = time,
		position = cframe.Position :: any,
		quat_vector = math.sin(half_angle) * axis :: any,
		quat_scalar = math.cos(half_angle),
		easing_function = easing_map[pose.EasingStyle][pose.EasingDirection],
	}))
end

const function load_keyframe_sequence(sequence: KeyframeSequence): AnimationAsset
	local keyframes = get_sequence_keyframes(sequence)
	local length, markers = read_markers(keyframes)

	local pose_keys_by_name: PoseKeyBuckets = {}
	local first_path_by_name: { [string]: string } = {}

	local pose_length = 0

	for _, keyframe in keyframes do
		local poses = keyframe:GetPoses()
		if #poses == 0 then
			continue
		end

		pose_length = keyframe.Time

		local seen_at_time: { [string]: string } = {}

		for _, root_pose: Pose in poses do
			read_pose_tree(root_pose, keyframe.Time, pose_keys_by_name, seen_at_time, first_path_by_name, "")
		end
	end

	local sorted_names = {}
	for name in pose_keys_by_name do
		table.insert(sorted_names, name)
	end
	table.sort(sorted_names)

	local channels: { Channel } = table.create(#sorted_names) :: { Channel }
	local name_to_channel: { [string]: number } = {}
	local key_times: { number } = {}
	local key_inv_durations: { number } = {}
	local key_positions: { vector } = {}
	local key_quat_vectors: { vector } = {}
	local key_quat_scalars: { number } = {}
	local key_easing_functions: { (t: number) -> number } = {}

	for channel_index, name in sorted_names do
		channels[channel_index] = pack_channel(
			pose_keys_by_name[name],
			key_times,
			key_inv_durations,
			key_positions,
			key_quat_vectors,
			key_quat_scalars,
			key_easing_functions
		)
		name_to_channel[name] = channel_index
	end

	local priority = sequence.Priority
	local priority_value = priority.Value
	if priority == Enum.AnimationPriority.Core then
		--Core has a value of 1000, which would make it the highest priority so we have to do something like this
		priority_value = -1
	end

	table.freeze(channels)
	table.freeze(name_to_channel)
	table.freeze(key_times)
	table.freeze(key_inv_durations)
	table.freeze(key_positions)
	table.freeze(key_quat_vectors)
	table.freeze(key_quat_scalars)
	table.freeze(key_easing_functions)

	return table.freeze({
		length = length,
		pose_length = pose_length,
		looped = sequence.Loop,
		priority = priority_value,

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

const function bind_animation(asset: AnimationAsset, rig_or_desc: rig_load.Rig | rig_load.RigDesc): AnimationBinding
	local value = rig_or_desc :: any
	local desc: rig_load.RigDesc = value.desc or value

	local active_rig_indices = {}
	local active_channel_indices = {}
	local active_count = 0

	for rig_index = 1, desc.count do
		local channel_index = asset.name_to_channel[desc.names[rig_index]]

		if channel_index ~= nil then
			active_count += 1
			active_rig_indices[active_count] = rig_index
			active_channel_indices[active_count] = channel_index
		end
	end

	table.freeze(active_rig_indices)
	table.freeze(active_channel_indices)

	return table.freeze({
		active_count = active_count,
		active_rig_indices = active_rig_indices,
		active_channel_indices = active_channel_indices,
	})
end

const function extract_markers(sequence: KeyframeSequence): MarkerAsset
	local length, markers = read_markers(get_sequence_keyframes(sequence))

	return table.freeze({
		length = length,
		markers = markers,
	})
end

return {
	load_keyframe_sequence = load_keyframe_sequence,
	extract_markers = extract_markers,
	bind_animation = bind_animation,
}