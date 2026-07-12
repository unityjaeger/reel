--!strict

local fixtures = require("../fixtures")

local function add_traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function destroy_all(instances: { Instance }, callback: () -> ())
	local ok, message = xpcall(function(): string
		callback()
		return ""
	end, add_traceback)

	for _, instance in instances do
		fixtures.destroy(instance)
	end

	if not ok then
		error(message, 0)
	end
end

return function(t: any, reel: any)
	local test = t.test
	local rig_load = reel.rig
	local animation_load = reel.animation
	local solver = reel.solver

	test("workflow loads, binds, solves, reconstructs, and commits one native track", function()
		local model, handles = fixtures.motor_model({
			root_c0 = CFrame.new(0, 1, 0),
			child_c0 = CFrame.new(0, 2, 0),
		})
		local sequence = fixtures.sequence({
			fixtures.keyframe(0, { fixtures.pose("Arm", CFrame.identity) }),
			fixtures.keyframe(1, {
				fixtures.pose(
					"Arm",
					CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
				),
			}),
		})

		destroy_all({ model, sequence }, function()
			local rig = rig_load.load_rig(model)
			local asset = animation_load.load_keyframe_sequence(sequence)
			local binding = animation_load.bind_animation(asset, rig.desc)
			local state = {
				binding = binding,
				time_position = 0.5,
				weight = 1,
				priority = nil,
			}
			local prepared = solver.prepare_tracks({
				{ asset = asset, state = state },
			})

			solver.solve_prepared(rig, prepared)

			local torso_index = rig.desc.name_to_index.Torso
			local arm_index = rig.desc.name_to_index.Arm
			local expected_arm = CFrame.new(1, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
			t.cframe_near(rig.transforms[torso_index], CFrame.identity)
			t.cframe_near(rig.transforms[arm_index], expected_arm)

			local root = CFrame.new(10, 20, 30) * CFrame.Angles(0.1, 0.2, 0.3)
			local world = solver.compute_world_transforms(rig, root, {})
			local torso_world = root
				* rig.desc.c0[torso_index]
				* rig.transforms[torso_index]
				* rig.desc.c1_inv[torso_index]
			local arm_world = torso_world
				* rig.desc.c0[arm_index]
				* expected_arm
				* rig.desc.c1_inv[arm_index]
			t.cframe_near(world[torso_index], torso_world)
			t.cframe_near(world[arm_index], arm_world)

			handles.child_motor.Transform = rig.transforms[arm_index]
			t.cframe_near(handles.child_motor.Transform, expected_arm)
		end)
	end)

	test("workflow applies a loaded identity-relative delta after the native solve", function()
		local model = fixtures.motor_model()
		local base_transform = CFrame.new(1, 2, 0) * CFrame.Angles(0.1, 0.2, 0)
		local delta_transform = CFrame.new(0, 0, -1) * CFrame.Angles(0, 0, 0.4)
		local base_sequence = fixtures.sequence({
			fixtures.keyframe(0, { fixtures.pose("Arm", base_transform) }),
		})
		local delta_sequence = fixtures.sequence({
			fixtures.keyframe(0, { fixtures.pose("Arm", delta_transform) }),
		})

		destroy_all({ model, base_sequence, delta_sequence }, function()
			local rig = rig_load.load_rig(model)
			local arm_index = rig.desc.name_to_index.Arm
			local base_asset = animation_load.load_keyframe_sequence(base_sequence)
			local delta_asset = animation_load.load_keyframe_sequence(delta_sequence)
			local base_state = {
				binding = animation_load.bind_animation(base_asset, rig.desc),
				time_position = 0,
				weight = 1,
				priority = nil,
			}
			local delta_state = {
				binding = animation_load.bind_animation(delta_asset, rig.desc),
				time_position = 0,
				weight = 1,
			}

			solver.solve_prepared(rig, solver.prepare_tracks({
				{ asset = base_asset, state = base_state },
			}))
			solver.apply_delta_prepared(rig, solver.prepare_delta_tracks({
				{
					asset = delta_asset,
					state = delta_state,
					mode = "additive",
				},
			}))

			t.cframe_near(rig.transforms[arm_index], base_transform * delta_transform)
			t.is_nil(rig.blend_scratch)
		end)
	end)
end