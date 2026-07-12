--!strict

local fixtures = require("../fixtures")

return function(t: any, reel: any)
	local test = t.test
	local solver = reel.solver
	
	test("world reconstruction uses the Motor6D C0/local/inverse-C1 formula", function()
		local c0 = CFrame.new(1, 2, 3) * CFrame.Angles(0.1, 0.2, 0.3)
		local c1_inv = (CFrame.new(-2, 1, 0) * CFrame.Angles(-0.2, 0.1, 0.4)):Inverse()
		local desc = fixtures.desc({
			{
				name = "Joint",
				c0 = c0,
				c1_inv = c1_inv,
			},
		})
		local rig = fixtures.rig_state(desc)
		local root = CFrame.new(10, -3, 5) * CFrame.Angles(0.3, -0.1, 0.2)
		local local_transform = CFrame.new(0.5, 1, -2) * CFrame.Angles(-0.1, 0.4, 0.2)
		rig.transforms[1] = local_transform
		local out = table.create(1) :: { CFrame }

		local result = solver.compute_world_transforms(rig, root, out)

		t.same(result, out)
		t.cframe_near(result[1], root * c0 * local_transform * c1_inv)
	end)

	test("world reconstruction feeds each solved Motor6D world transform into its child", function()
		local first_c0 = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0.2, 0)
		local first_c1_inv = CFrame.new(0, -0.5, 0)
		local second_c0 = CFrame.new(1, 0, 0) * CFrame.Angles(0.1, 0, 0)
		local second_c1_inv = CFrame.new(-0.25, 0, 0) * CFrame.Angles(0, 0, -0.1)
		local desc = fixtures.desc({
			{
				name = "Upper",
				c0 = first_c0,
				c1_inv = first_c1_inv,
			},
			{
				name = "Lower",
				parent = 1,
				c0 = second_c0,
				c1_inv = second_c1_inv,
			},
		})
		local rig = fixtures.rig_state(desc)
		local root = CFrame.new(20, 4, -7) * CFrame.Angles(0, -0.4, 0)
		local first_local = CFrame.Angles(0, 0, 0.5)
		local second_local = CFrame.new(0, 0.2, 0) * CFrame.Angles(-0.3, 0.1, 0)
		rig.transforms[1] = first_local
		rig.transforms[2] = second_local
		local first_world = root * first_c0 * first_local * first_c1_inv
		local second_world = first_world * second_c0 * second_local * second_c1_inv

		local result = solver.compute_world_transforms(rig, root, {})

		t.cframe_near(result[1], first_world)
		t.cframe_near(result[2], second_world)
	end)

	test("Bone world reconstruction uses bind CFrames and supports Bone chains", function()
		local first_bind = CFrame.new(0, 1, 0) * CFrame.Angles(0.1, 0, 0)
		local second_bind = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, 0.2)
		local desc = fixtures.desc({
			{
				name = "Spine",
				is_bone = true,
				bind = first_bind,
			},
			{
				name = "Chest",
				parent = 1,
				is_bone = true,
				bind = second_bind,
			},
		})
		local rig = fixtures.rig_state(desc)
		local root = CFrame.new(-3, 8, 1) * CFrame.Angles(0, 0.4, 0)
		local first_local = CFrame.Angles(0, -0.2, 0.1)
		local second_local = CFrame.new(0.1, 0, 0) * CFrame.Angles(0.3, 0, 0)
		rig.transforms[1] = first_local
		rig.transforms[2] = second_local
		local first_world = root * first_bind * first_local
		local second_world = first_world * second_bind * second_local

		local result = solver.compute_world_transforms(rig, root, {})

		t.cframe_near(result[1], first_world)
		t.cframe_near(result[2], second_world)
	end)

	test("mixed descriptors select Motor6D and Bone formulas independently", function()
		local motor_c0 = CFrame.new(1, 0, 0)
		local motor_c1_inv = CFrame.new(0, 0, -1)
		local bone_bind = CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.2, 0)
		local child_bind = CFrame.new(0, 1, 0)
		local desc = fixtures.desc({
			{
				name = "MotorRoot",
				c0 = motor_c0,
				c1_inv = motor_c1_inv,
			},
			{
				name = "BoneRoot",
				parent = 1,
				is_bone = true,
				bind = bone_bind,
			},
			{
				name = "BoneChild",
				parent = 2,
				is_bone = true,
				bind = child_bind,
			},
		})
		local rig = fixtures.rig_state(desc)
		local root = CFrame.new(5, 6, 7) * CFrame.Angles(0.1, -0.2, 0.3)
		local motor_local = CFrame.Angles(0, 0.4, 0)
		local bone_local = CFrame.Angles(-0.1, 0, 0)
		local child_local = CFrame.new(0.2, 0, 0)
		rig.transforms[1] = motor_local
		rig.transforms[2] = bone_local
		rig.transforms[3] = child_local

		local result = solver.compute_world_transforms(rig, root, {})

		local motor_world = root * motor_c0 * motor_local * motor_c1_inv
		t.cframe_near(result[1], motor_world)
		local bone_world = motor_world * bone_bind * bone_local
		t.cframe_near(result[2], bone_world)
		t.cframe_near(result[3], bone_world * child_bind * child_local)
	end)

	test("caller-owned world output avoids and does not populate retained rig storage", function()
		local desc = fixtures.desc({
			{ name = "First", c0 = CFrame.new(1, 0, 0) },
			{ name = "Second", c0 = CFrame.new(0, 2, 0) },
		})
		local rig = fixtures.rig_state(desc)
		rig.transforms[1] = CFrame.new(0, 0, 3)
		rig.transforms[2] = CFrame.new(4, 0, 0)
		local root = CFrame.new(10, 20, 30)
		local out = { CFrame.new(999, 999, 999), CFrame.new(999, 999, 999) }

		local first_result = solver.compute_world_transforms(rig, root, out)
		local second_result = solver.compute_world_transforms(rig, root, out)

		t.same(first_result, out)
		t.same(second_result, out)
		t.is_nil(rig.world_transforms)
		t.cframe_near(out[1], root * CFrame.new(1, 0, 0) * rig.transforms[1])
		t.cframe_near(out[2], root * CFrame.new(0, 2, 0) * rig.transforms[2])
	end)

	test("omitted world output allocates once and reuses the retained array", function()
		local desc = fixtures.desc({
			{ name = "Joint", c0 = CFrame.new(0, 1, 0) },
		})
		local rig = fixtures.rig_state(desc)
		local root = CFrame.new(10, 0, 0)
		t.is_nil(rig.world_transforms)

		rig.transforms[1] = CFrame.new(1, 0, 0)
		local first = solver.compute_world_transforms(rig, root)
		t.same(first, rig.world_transforms)
		t.cframe_near(first[1], root * CFrame.new(0, 1, 0) * rig.transforms[1])

		rig.transforms[1] = CFrame.new(2, 0, 0)
		local second = solver.compute_world_transforms(rig, root)
		t.same(second, first)
		t.cframe_near(second[1], root * CFrame.new(0, 1, 0) * rig.transforms[1])
	end)

	test("world reconstruction does not mutate local solver output", function()
		local desc = fixtures.desc({
			{ name = "Joint", c0 = CFrame.new(1, 2, 3) },
		})
		local rig = fixtures.rig_state(desc)
		local local_transform = CFrame.new(-4, 5, 6) * CFrame.Angles(0.2, 0.3, 0.4)
		rig.transforms[1] = local_transform

		solver.compute_world_transforms(rig, CFrame.new(7, 8, 9), {})

		t.cframe_near(rig.transforms[1], local_transform)
	end)
end