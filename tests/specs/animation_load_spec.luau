--!strict

local fixtures = require("../fixtures")

local function add_traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function with_destroy(instance: Instance, callback: () -> ())
	local ok, message = xpcall(function(): string
		callback()
		return ""
	end, add_traceback)
	
	fixtures.destroy(instance)

	if not ok then
		error(message, 0)
	end
end

local function channel_key_index(asset: any, name: string, offset: number): number
	local channel_index = asset.name_to_channel[name]
	local channel = asset.channels[channel_index]
	return channel.key_start + offset
end

local function marker_keyframe(time: number, name: string, value: string): Keyframe
	local keyframe = fixtures.keyframe(time, {})
	local marker = Instance.new("KeyframeMarker")
	marker.Name = name
	marker.Value = value
	keyframe:AddMarker(marker)
	return keyframe
end

local function add_marker(keyframe: Keyframe, name: string, value: string): Keyframe
	local marker = Instance.new("KeyframeMarker")
	marker.Name = name
	marker.Value = value
	keyframe:AddMarker(marker)
	return keyframe
end

return function(t: any, reel: any)
	local test = t.test
	local animation_load = reel.animation

	test("animation_load packs sorted channels and key times with immutable metadata", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(2, {
				fixtures.pose("Zed", CFrame.new(0, 0, 20)),
				fixtures.pose("Arm", CFrame.new(2, 0, 0)),
			}),
			fixtures.keyframe(0, {
				fixtures.pose("Zed", CFrame.identity),
				fixtures.pose("Arm", CFrame.identity),
			}),
			fixtures.keyframe(1, {
				fixtures.pose("Zed", CFrame.new(0, 0, 10)),
				fixtures.pose("Arm", CFrame.new(1, 0, 0)),
			}),
		}, {
			looped = true,
			priority = Enum.AnimationPriority.Action,
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)

			t.equal(asset.length, 2)
			t.equal(asset.looped, true)
			t.equal(asset.priority, Enum.AnimationPriority.Action.Value)
			t.equal(asset.name_to_channel.Arm, 1)
			t.equal(asset.name_to_channel.Zed, 2)
			t.equal(asset.channels[1].count, 3)
			t.equal(asset.channels[2].count, 3)

			local arm_start = asset.channels[1].key_start
			t.equal(asset.key_times[arm_start], 0)
			t.equal(asset.key_times[arm_start + 1], 1)
			t.equal(asset.key_times[arm_start + 2], 2)
			t.vector_near(asset.key_positions[arm_start + 1], vector.create(1, 0, 0))

			t.truthy(table.isfrozen(asset))
			t.truthy(table.isfrozen(asset.channels))
			t.truthy(table.isfrozen(asset.channels[1]))
			t.truthy(table.isfrozen(asset.name_to_channel))
			t.truthy(table.isfrozen(asset.key_times))
			t.truthy(table.isfrozen(asset.key_inv_durations))
			t.truthy(table.isfrozen(asset.key_positions))
			t.truthy(table.isfrozen(asset.key_quat_vectors))
			t.truthy(table.isfrozen(asset.key_quat_scalars))
			t.truthy(table.isfrozen(asset.key_easing_functions))
		end)
	end)

	test("animation_load maps Core priority to the lowest solver priority", function()
		local sequence = fixtures.sequence({}, {
			looped = false,
			priority = Enum.AnimationPriority.Core,
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			t.equal(asset.length, 0)
			t.equal(asset.looped, false)
			t.equal(asset.priority, -1)
			t.equal(#asset.channels, 0)
		end)
	end)

	test("animation_load traverses zero-weight structural poses and treats any nonzero weight as channel presence", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("StructuralRoot", CFrame.new(100, 0, 0), {
					weight = 0,
					subposes = {
						fixtures.pose("Arm", CFrame.new(3, 4, 5), {
							weight = 0.25,
						}),
					},
				}),
			}),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			t.is_nil(asset.name_to_channel.StructuralRoot)
			t.non_nil(asset.name_to_channel.Arm)
			t.equal(#asset.channels, 1)
			t.vector_near(asset.key_positions[1], vector.create(3, 4, 5))
		end)
	end)

	test("animation_load extends a late-starting channel back to time zero", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("Anchor", CFrame.identity),
			}),
			fixtures.keyframe(1, {
				fixtures.pose("Arm", CFrame.new(4, 0, 0)),
			}),
			fixtures.keyframe(2, {
				fixtures.pose("Arm", CFrame.new(8, 0, 0)),
			}),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			local channel = asset.channels[asset.name_to_channel.Arm]
			local start = channel.key_start

			t.equal(channel.count, 3)
			t.equal(asset.key_times[start], 0)
			t.equal(asset.key_times[start + 1], 1)
			t.equal(asset.key_times[start + 2], 2)
			t.vector_near(asset.key_positions[start], vector.create(4, 0, 0))
			t.vector_near(asset.key_positions[start + 1], vector.create(4, 0, 0))
			t.vector_near(asset.key_positions[start + 2], vector.create(8, 0, 0))
		end)
	end)

	test("animation_load rejects the ambiguous two-keyframe late-start shape", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(1, { fixtures.pose("Arm", CFrame.new(1, 0, 0)) }),
			fixtures.keyframe(2, { fixtures.pose("Arm", CFrame.new(2, 0, 0)) }),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.load_keyframe_sequence(sequence)
			end, "only 2 keyframes")
		end)
	end)

	test("animation_load retains marker-only keyframes without creating solver keys", function()
		local sequence = fixtures.sequence({
			marker_keyframe(1, "Footstep", "Left"),
			marker_keyframe(2, "Footstep", "Right"),
			marker_keyframe(3, "Finished", ""),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)

			t.equal(asset.length, 3)
			t.equal(asset.pose_length, 0)
			t.equal(#asset.channels, 0)
			t.equal(#asset.key_times, 0)
			t.equal(#asset.markers, 3)
			t.equal(asset.markers[1].time, 1)
			t.equal(asset.markers[1].name, "Footstep")
			t.equal(asset.markers[1].value, "Left")
			t.equal(asset.markers[2].time, 2)
			t.equal(asset.markers[2].value, "Right")
			t.equal(asset.markers[3].time, 3)
			t.equal(asset.markers[3].name, "Finished")
			t.truthy(table.isfrozen(asset.markers))
			t.truthy(table.isfrozen(asset.markers[1]))
		end)
	end)

	test("animation_load rejects exactly two late marker-only keyframes", function()
		local sequence = fixtures.sequence({
			marker_keyframe(1, "Footstep", "Left"),
			marker_keyframe(2, "Footstep", "Right"),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.load_keyframe_sequence(sequence)
			end, "only 2 keyframes")
		end)
	end)

	test("animation_load accepts two late pose keyframes with a third marker-only keyframe", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(1, { fixtures.pose("Arm", CFrame.new(1, 0, 0)) }),
			fixtures.keyframe(2, { fixtures.pose("Arm", CFrame.new(2, 0, 0)) }),
			marker_keyframe(3, "Finished", ""),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			local arm = asset.channels[asset.name_to_channel.Arm]

			t.equal(asset.length, 3)
			t.equal(asset.pose_length, 2)
			t.equal(arm.count, 3)
			t.equal(#asset.markers, 1)
			t.equal(asset.markers[1].time, 3)
		end)
	end)

	test("extract_markers returns sorted immutable marker metadata and the full sequence length", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(4, {}),
			add_marker(
				fixtures.keyframe(2, {
					fixtures.pose("Arm", CFrame.new(2, 0, 0)),
				}),
				"Footstep",
				"Right"
			),
			marker_keyframe(0, "Started", ""),
		})

		with_destroy(sequence, function()
			local marker_asset = animation_load.extract_markers(sequence)
			local full_asset = animation_load.load_keyframe_sequence(sequence)

			t.equal(marker_asset.length, 4)
			t.equal(#marker_asset.markers, 2)
			t.equal(marker_asset.markers[1].time, 0)
			t.equal(marker_asset.markers[1].name, "Started")
			t.equal(marker_asset.markers[1].value, "")
			t.equal(marker_asset.markers[2].time, 2)
			t.equal(marker_asset.markers[2].name, "Footstep")
			t.equal(marker_asset.markers[2].value, "Right")

			for index, marker in marker_asset.markers do
				local full_marker = full_asset.markers[index]
				t.equal(marker.time, full_marker.time)
				t.equal(marker.name, full_marker.name)
				t.equal(marker.value, full_marker.value)
				t.truthy(table.isfrozen(marker))
			end

			t.truthy(table.isfrozen(marker_asset))
			t.truthy(table.isfrozen(marker_asset.markers))
		end)
	end)

	test("extract_markers returns an empty frozen asset for an empty sequence", function()
		local sequence = fixtures.sequence({})

		with_destroy(sequence, function()
			local asset = animation_load.extract_markers(sequence)
			t.equal(asset.length, 0)
			t.equal(#asset.markers, 0)
			t.truthy(table.isfrozen(asset))
			t.truthy(table.isfrozen(asset.markers))
		end)
	end)

	test("extract_markers enforces the same unsupported two-keyframe shape as the full loader", function()
		local sequence = fixtures.sequence({
			marker_keyframe(1, "Footstep", "Left"),
			marker_keyframe(2, "Footstep", "Right"),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.extract_markers(sequence)
			end, "only 2 keyframes")
		end)
	end)

	test("animation_load rejects duplicate targets at one timestamp", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("Arm", CFrame.identity),
				fixtures.pose("Arm", CFrame.new(1, 0, 0)),
			}),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.load_keyframe_sequence(sequence)
			end, "duplicate animation target")
		end)
	end)

	test("animation_load rejects one target name moving between pose-tree paths", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("RootA", CFrame.identity, {
					weight = 0,
					subposes = { fixtures.pose("Arm", CFrame.identity) },
				}),
			}),
			fixtures.keyframe(1, {
				fixtures.pose("RootB", CFrame.identity, {
					weight = 0,
					subposes = { fixtures.pose("Arm", CFrame.identity) },
				}),
			}),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.load_keyframe_sequence(sequence)
			end, "ambiguous animation target")
		end)
	end)

	test("animation_load rejects duplicate per-channel key times", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, { fixtures.pose("Arm", CFrame.identity) }),
			fixtures.keyframe(0, { fixtures.pose("Arm", CFrame.new(1, 0, 0)) }),
		})

		with_destroy(sequence, function()
			t.errors(function()
				animation_load.load_keyframe_sequence(sequence)
			end, "duplicate or descending keyframe times")
		end)
	end)

	test("animation_load stores the left key's easing function", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("Arm", CFrame.identity, {
					easing_style = Enum.PoseEasingStyle.Constant,
					easing_direction = Enum.PoseEasingDirection.Out,
				}),
			}),
			fixtures.keyframe(1, {
				fixtures.pose("Arm", CFrame.new(1, 0, 0)),
			}),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			local key_index = channel_key_index(asset, "Arm", 0)
			t.equal(asset.key_easing_functions[key_index](0.75), 0)
		end)
	end)

	test("bind_animation aligns matched channels in descriptor order", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, {
				fixtures.pose("Head", CFrame.new(0, 1, 0)),
				fixtures.pose("Arm", CFrame.new(1, 0, 0)),
			}),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			local desc = fixtures.desc({
				{ name = "Root" },
				{ name = "Head" },
				{ name = "Leg" },
				{ name = "Arm" },
			})
			local rig = fixtures.rig_state(desc)
			local from_desc = animation_load.bind_animation(asset, desc)
			local from_state = animation_load.bind_animation(asset, rig)

			t.equal(from_desc.active_count, 2)
			t.equal(from_desc.active_rig_indices[1], 2)
			t.equal(from_desc.active_channel_indices[1], asset.name_to_channel.Head)
			t.equal(from_desc.active_rig_indices[2], 4)
			t.equal(from_desc.active_channel_indices[2], asset.name_to_channel.Arm)

			t.equal(from_state.active_count, from_desc.active_count)
			t.equal(from_state.active_rig_indices[1], from_desc.active_rig_indices[1])
			t.equal(from_state.active_channel_indices[2], from_desc.active_channel_indices[2])
			t.truthy(table.isfrozen(from_desc))
			t.truthy(table.isfrozen(from_desc.active_rig_indices))
			t.truthy(table.isfrozen(from_desc.active_channel_indices))
		end)
	end)

	test("bind_animation produces an empty frozen binding when nothing matches", function()
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, { fixtures.pose("Arm", CFrame.identity) }),
		})

		with_destroy(sequence, function()
			local asset = animation_load.load_keyframe_sequence(sequence)
			local desc = fixtures.desc({ { name = "Leg" } })
			local binding = animation_load.bind_animation(asset, desc)

			t.equal(binding.active_count, 0)
			t.equal(#binding.active_rig_indices, 0)
			t.equal(#binding.active_channel_indices, 0)
			t.truthy(table.isfrozen(binding))
		end)
	end)
end