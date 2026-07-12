--!strict
--!optimize 2

const rig_load = require("./rig")
const animation_load = require("./animation")

type Channel = animation_load.Channel
type AnimationAsset = animation_load.AnimationAsset
type AnimationBinding = animation_load.AnimationBinding
type BlendScratch = rig_load.BlendScratch
type Rig = rig_load.Rig

const IDENTITY = CFrame.identity
const VEC_ZERO = vector.zero
const EPS = 1e-5
const FLT_EPS = 1e-7

export type AnimationState = {
	binding: AnimationBinding,

	time_position: number,

	weight: number,

	priority: number?,
}

export type PlayingTrack = {
	asset: AnimationAsset,
	state: AnimationState,
}

export type DeltaMode = "additive" | "subtractive"

export type DeltaState = {
	binding: AnimationBinding,
	time_position: number,
	weight: number,
}

export type DeltaTrack = {
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

export type PreparedTrack = {
	asset: AnimationAsset,
	state: AnimationState,
	priority: number,
}

export type PriorityGroup = {
	start: number,
	stop: number,
}

export type PreparedPlaying = {
	count: number,
	tracks: { PreparedTrack },

	group_count: number,
	groups: { PriorityGroup },
}

const function quat_normalize(v: vector, w: number): (vector, number)
	local len = math.sqrt(vector.dot(v, v) + w * w)
	if len < FLT_EPS then
		return vector.zero, 1
	end

	local inv = 1 / len
	return v * inv, w * inv
end

local function quat_nlerp(v0: vector, w0: number, v1: vector, w1: number, t: number): (vector, number)
	if vector.dot(v0, v1) + w0 * w1 < 0 then
		v1 = -v1
		w1 = -w1
	end

	local out_v, out_w = quat_normalize(
		vector.lerp(v0, v1, t),
		math.lerp(w0, w1, t)
	)

	return out_v, out_w
end

const function sample_channel(asset: AnimationAsset, channel: Channel, target_time: number): (vector, vector, number)
	local count = channel.count
	local key_start = channel.key_start
	local times = asset.key_times

	local positions = asset.key_positions
	local quat_vectors = asset.key_quat_vectors
	local quat_scalars = asset.key_quat_scalars

	if count == 0 then
		return VEC_ZERO, VEC_ZERO, 1
	end

	local key_stop = key_start + count - 1

	if count == 1 or target_time <= times[key_start] then
		return positions[key_start], quat_vectors[key_start], quat_scalars[key_start]
	end

	if target_time >= times[key_stop] then
		return positions[key_stop], quat_vectors[key_stop], quat_scalars[key_stop]
	end

	local left = key_start

	if count > 2 then
		local low = key_start
		local high = key_stop

		while low <= high do
			local mid = (low + high) // 2
			if times[mid] == target_time then
				return positions[mid], quat_vectors[mid], quat_scalars[mid]
			elseif times[mid] < target_time then
				left = mid
				low = mid + 1
			else
				high = mid - 1
			end
		end
	end

	local right = left + 1

	local alpha = (target_time - times[left]) * asset.key_inv_durations[left]
	alpha = asset.key_easing_functions[left](alpha)

	local position = vector.lerp(positions[left], positions[right], alpha)

	local qv, qs = quat_nlerp(
		quat_vectors[left],
		quat_scalars[left],
		quat_vectors[right],
		quat_scalars[right],
		alpha
	)

	return position, qv, qs
end

const function get_priority(asset: AnimationAsset, state: AnimationState): number
	local state_priority = state.priority
	if state_priority ~= nil then
		return state_priority
	end

	return asset.priority
end

const function sort_tracks_by_priority(a: PreparedTrack, b: PreparedTrack): boolean
	return a.priority > b.priority
end

const function create_prepared_playing(): PreparedPlaying
	return {
		count = 0,
		tracks = {},

		group_count = 0,
		groups = {},
	}
end

const function write_prepared_track(tracks: { PreparedTrack }, index: number, asset: AnimationAsset, state: AnimationState)
	local priority = get_priority(asset, state)
	local track = tracks[index]

	if track == nil then
		tracks[index] = {
			asset = asset,
			state = state,
			priority = priority,
		}
	else
		track.asset = asset
		track.state = state
		track.priority = priority
	end
end

const function rebuild_priority_groups(prepared: PreparedPlaying)
	local tracks = prepared.tracks
	local groups = prepared.groups
	local old_group_count = prepared.group_count
	local track_count = prepared.count

	local group_count = 0
	local group_start = 1

	while group_start <= track_count do
		local group_priority = tracks[group_start].priority
		local group_stop = group_start + 1

		while group_stop <= track_count and tracks[group_stop].priority == group_priority do
			group_stop += 1
		end

		group_count += 1

		local group = groups[group_count]
		if group == nil then
			groups[group_count] = {
				start = group_start,
				stop = group_stop,
			}
		else
			group.start = group_start
			group.stop = group_stop
		end

		group_start = group_stop
	end

	for index = group_count + 1, old_group_count do
		groups[index] = nil
	end

	prepared.group_count = group_count
end

const function finish_prepared(prepared: PreparedPlaying, count: number, old_count: number): PreparedPlaying
	local tracks = prepared.tracks

	for index = count + 1, old_count do
		tracks[index] = nil
	end

	prepared.count = count

	if count > 1 then
		table.sort(tracks, sort_tracks_by_priority)
	end

	rebuild_priority_groups(prepared)

	return prepared
end

const function prepare_tracks(playing_tracks: { PlayingTrack }, out: PreparedPlaying?): PreparedPlaying
	local prepared = out or create_prepared_playing()
	local tracks = prepared.tracks
	local old_count = prepared.count
	local count = #playing_tracks

	for index = 1, count do
		local playing_track = playing_tracks[index]
		write_prepared_track(tracks, index, playing_track.asset, playing_track.state)
	end

	return finish_prepared(prepared, count, old_count)
end

const function create_prepared_delta(): PreparedDelta
	return {
		count = 0,
		tracks = {},
	}
end

const function prepare_delta_tracks(
	delta_tracks: { DeltaTrack },
	out: PreparedDelta?
): PreparedDelta
	local prepared = out or create_prepared_delta()
	local tracks = prepared.tracks
	local old_count = prepared.count
	local count = #delta_tracks

	for index = 1, count do
		local delta_track = delta_tracks[index]
		local mode = delta_track.mode
		local inverse: boolean

		if mode == "additive" then
			inverse = false
		elseif mode == "subtractive" then
			inverse = true
		else
			error(`unknown delta track mode: {mode}`)
		end

		local track = tracks[index]

		if track == nil then
			tracks[index] = {
				asset = delta_track.asset,
				state = delta_track.state,
				inverse = inverse,
			}
		else
			track.asset = delta_track.asset
			track.state = delta_track.state
			track.inverse = inverse
		end
	end

	for index = count + 1, old_count do
		tracks[index] = nil
	end

	prepared.count = count
	return prepared
end

const function solve_single_track(rig: Rig, track: PreparedTrack)
	local desc = rig.desc
	local transforms = rig.transforms
	local rig_count = desc.count
	local state = track.state
	local track_weight = state.weight
	local binding = state.binding
	local active_count = binding.active_count

	if track_weight <= EPS then
		for rig_index = 1, rig_count do
			transforms[rig_index] = IDENTITY
		end
		return
	end

	if active_count < rig_count then
		for rig_index = 1, rig_count do
			transforms[rig_index] = IDENTITY
		end
	end

	local real_time = state.time_position
	local asset = track.asset
	local channels = asset.channels
	local active_rig_indices = binding.active_rig_indices
	local active_channel_indices = binding.active_channel_indices

	for active_index = 1, active_count do
		local rig_index = active_rig_indices[active_index]
		local channel_index = active_channel_indices[active_index]
		local pos, qv, qs = sample_channel(asset, channels[channel_index], real_time)

		if track_weight < 1 then
			pos *= track_weight

			if qs < 0 then
				qv = -qv
				qs = -qs
			end

			qv *= track_weight
			qs = qs * track_weight + 1 - track_weight
			qv, qs = quat_normalize(qv, qs)
		end

		transforms[rig_index] = CFrame.new(pos.x, pos.y, pos.z, qv.x, qv.y, qv.z, qs)
	end
end

const function solve_prepared(rig: Rig, prepared: PreparedPlaying)
	local desc = rig.desc
	local rig_count = desc.count
	local transforms = rig.transforms

	local tracks = prepared.tracks
	local groups = prepared.groups
	local group_count = prepared.group_count

	local effective_count = 0
	local single_track: PreparedTrack? = nil

	for track_index = 1, prepared.count do
		local track = tracks[track_index]
		if track.state.weight > EPS and track.state.binding.active_count > 0 then
			effective_count += 1
			single_track = track

			if effective_count == 2 then
				break
			end
		end
	end

	if effective_count == 0 then
		for rig_index = 1, rig_count do
			transforms[rig_index] = IDENTITY
		end
		return
	elseif effective_count == 1 then
		solve_single_track(rig, single_track :: PreparedTrack)
		return
	end

	local scratch = rig.blend_scratch :: BlendScratch
	local blend_weight = scratch.weight
	local blend_position = scratch.position
	local blend_qv = scratch.quat_vector
	local blend_qs = scratch.quat_scalar
	local group_weight = scratch.group_weight
	local group_touched = scratch.group_touched

	for i = 1, rig_count do
		blend_weight[i] = 0
		blend_position[i] = VEC_ZERO
		blend_qv[i] = VEC_ZERO
		blend_qs[i] = 0
	end

	for group_index = 1, group_count do
		local group = groups[group_index]
		local group_start = group.start
		local group_stop = group.stop

		local touched_count = 0

		for track_index = group_start, group_stop - 1 do
			local track = tracks[track_index]
			local track_weight = track.state.weight

			if track_weight <= EPS then
				continue
			end

			local binding = track.state.binding
			local active_rig_indices = binding.active_rig_indices

			for active_index = 1, binding.active_count do
				local rig_index = active_rig_indices[active_index]

				if blend_weight[rig_index] >= 1 - EPS then
					continue
				end

				if group_weight[rig_index] <= 0 then
					touched_count += 1
					group_touched[touched_count] = rig_index
				end

				group_weight[rig_index] += track_weight
			end
		end

		for touched_index = 1, touched_count do
			local rig_index = group_touched[touched_index]
			local total_weight = group_weight[rig_index]
			local remaining = 1 - blend_weight[rig_index]

			if remaining <= EPS then
				group_weight[rig_index] = 0
			elseif total_weight > remaining then
				group_weight[rig_index] = remaining / total_weight
			else
				group_weight[rig_index] = 1
			end
		end

		for track_index = group_start, group_stop - 1 do
			local track = tracks[track_index]
			local state = track.state
			local track_weight = state.weight

			if track_weight <= EPS then
				continue
			end

			local real_time = state.time_position
			local binding = state.binding
			local asset = track.asset
			local channels = asset.channels
			local active_rig_indices = binding.active_rig_indices
			local active_channel_indices = binding.active_channel_indices

			for active_index = 1, binding.active_count do
				local rig_index = active_rig_indices[active_index]
				local scale = group_weight[rig_index]

				if scale <= EPS then
					continue
				end

				local effective_weight = track_weight * scale
				local channel_index = active_channel_indices[active_index]
				local pos, qv, qs = sample_channel(asset, channels[channel_index], real_time)

				local current_weight = blend_weight[rig_index]
				local acc_qv = blend_qv[rig_index]
				local acc_qs = blend_qs[rig_index]

				if current_weight > 0 and vector.dot(acc_qv, qv) + acc_qs * qs < 0 then
					qv = -qv
					qs = -qs
				end

				blend_position[rig_index] += pos * effective_weight
				blend_qv[rig_index] += qv * effective_weight
				blend_qs[rig_index] += qs * effective_weight
				blend_weight[rig_index] = current_weight + effective_weight
			end
		end

		for touched_index = 1, touched_count do
			group_weight[group_touched[touched_index]] = 0
		end
	end

	for rig_index = 1, rig_count do
		local weight = blend_weight[rig_index]

		if weight <= EPS then
			transforms[rig_index] = IDENTITY
		else
			local pos = blend_position[rig_index]
			local qv = blend_qv[rig_index]
			local qs = blend_qs[rig_index]

			if weight < 1 then
				if qs < 0 then
					qv = -qv
					qs = -qs
				end

				qs += 1 - weight
			else
				local inv = 1 / weight
				pos *= inv
				qv *= inv
				qs *= inv
			end

			qv, qs = quat_normalize(qv, qs)
			transforms[rig_index] = CFrame.new(pos.x, pos.y, pos.z, qv.x, qv.y, qv.z, qs)
		end
	end
end

const function apply_delta_prepared(rig: Rig, prepared: PreparedDelta)
	local transforms = rig.transforms
	local tracks = prepared.tracks

	for track_index = 1, prepared.count do
		local track = tracks[track_index]
		local state = track.state
		local weight = state.weight

		if weight <= EPS then
			continue
		end

		local binding = state.binding
		local asset = track.asset
		local inverse = track.inverse
		local channels = asset.channels
		local active_rig_indices = binding.active_rig_indices
		local active_channel_indices = binding.active_channel_indices
		local real_time = state.time_position

		for active_index = 1, binding.active_count do
			local rig_index = active_rig_indices[active_index]
			local channel_index = active_channel_indices[active_index]
			local pos, qv, qs = sample_channel(asset, channels[channel_index], real_time)

			if weight < 1 then
				pos *= weight

				if qs < 0 then
					qv = -qv
					qs = -qs
				end

				qv *= weight
				qs = qs * weight + 1 - weight
				qv, qs = quat_normalize(qv, qs)
			end

			local delta = CFrame.new(pos.x, pos.y, pos.z, qv.x, qv.y, qv.z, qs)
			if inverse then
				delta = delta:Inverse()
			end

			transforms[rig_index] = transforms[rig_index] * delta
		end
	end
end

const function compute_world_transforms(rig: Rig, root_cframe: CFrame, out: { CFrame }?): { CFrame }
	local desc = rig.desc
	local world_transforms = out or rig_load.get_world_transforms(rig)
	local local_transforms = rig.transforms
	local parent = desc.parent
	local is_bone = desc.is_bone
	local c0 = desc.c0
	local c1_inv = desc.c1_inv
	local bind = desc.bind

	for rig_index = 1, desc.count do
		local parent_index = parent[rig_index]
		local parent_world = if parent_index == 0 then root_cframe else world_transforms[parent_index]
		local local_transform = local_transforms[rig_index]

		if is_bone[rig_index] then
			world_transforms[rig_index] = parent_world * (bind[rig_index] :: CFrame) * local_transform
		else
			world_transforms[rig_index] = parent_world * (c0[rig_index] :: CFrame) * local_transform * (c1_inv[rig_index] :: CFrame)
		end
	end

	return world_transforms
end

return {
	prepare_tracks = prepare_tracks,
	prepare_delta_tracks = prepare_delta_tracks,
	solve_prepared = solve_prepared,
	apply_delta_prepared = apply_delta_prepared,
	compute_world_transforms = compute_world_transforms
}