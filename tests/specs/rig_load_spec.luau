--!strict

local fixtures = require("../fixtures")

local function add_traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function protect(callback: () -> ()): (boolean, string)
	return xpcall(function(): string
		callback()
		return ""
	end, add_traceback)
end

local function with_destroy(instance: Instance, callback: () -> ())
	local ok, message = protect(callback)
	fixtures.destroy(instance)

	if not ok then
		error(message, 0)
	end
end

local function part(name: string, parent: Instance): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Parent = parent
	return result
end

local function motor(part0: BasePart?, part1: BasePart?, parent: Instance, name: string?): Motor6D
	local result = Instance.new("Motor6D")
	result.Name = name or "Joint"
	result.Part0 = part0
	result.Part1 = part1
	result.Parent = parent
	return result
end

local function animation_constraint(
	part0: BasePart?,
	part1: BasePart?,
	parent: Instance,
	name: string?,
	c0: CFrame?,
	c1: CFrame?,
	is_kinematic: boolean?
): AnimationConstraint
	local result = Instance.new("AnimationConstraint")
	result.Name = name or "Joint"
	result.IsKinematic = is_kinematic ~= false

	if part0 ~= nil then
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = result.Name .. "Attachment0"
		attachment0.CFrame = c0 or CFrame.identity
		attachment0.Parent = part0
		result.Attachment0 = attachment0
	end

	if part1 ~= nil then
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = result.Name .. "Attachment1"
		attachment1.CFrame = c1 or CFrame.identity
		attachment1.Parent = part1
		result.Attachment1 = attachment1
	end

	result.Parent = parent
	return result
end

local function constraint_model(
	root_c0: CFrame?,
	root_c1: CFrame?,
	child_c0: CFrame?,
	child_c1: CFrame?
): (Model, { root: Part, middle: Part, leaf: Part, root_joint: AnimationConstraint, child_joint: AnimationConstraint })
	local model = Instance.new("Model")
	model.Name = "ConstraintRig"

	local root = part("Root", model)
	local middle = part("Torso", model)
	local leaf = part("Arm", model)

	local child_joint = animation_constraint(middle, leaf, model, "Shoulder", child_c0, child_c1, true)
	local root_joint = animation_constraint(root, middle, model, "RootJoint", root_c0, root_c1, true)

	return model, {
		root = root,
		middle = middle,
		leaf = leaf,
		root_joint = root_joint,
		child_joint = child_joint,
	}
end

local function sibling_motor_model(reverse: boolean): (Model, { [string]: Motor6D })
	local model = Instance.new("Model")
	model.Name = "SiblingRig"

	local root = part("Root", model)
	local arm = part("Arm", model)
	local leg = part("Leg", model)
	local arm_motor = Instance.new("Motor6D")
	arm_motor.Name = "NotTheTargetNameA"
	arm_motor.Part0 = root
	arm_motor.Part1 = arm
	local leg_motor = Instance.new("Motor6D")
	leg_motor.Name = "NotTheTargetNameB"
	leg_motor.Part0 = root
	leg_motor.Part1 = leg

	if reverse then
		leg_motor.Parent = model
		arm_motor.Parent = model
	else
		arm_motor.Parent = model
		leg_motor.Parent = model
	end

	return model, {
		Arm = arm_motor,
		Leg = leg_motor,
	}
end

local function mixed_model(): (Model, Motor6D, Bone)
	local model = Instance.new("Model")
	model.Name = "MixedRig"
	local root = part("Root", model)
	local torso = part("Torso", model)
	local torso_motor = motor(root, torso, model, "RootJoint")

	local bone = Instance.new("Bone")
	bone.Name = "Spine"
	bone.CFrame = CFrame.new(0, 2, 0)
	bone.Parent = torso

	return model, torso_motor, bone
end

return function(t: any, reel: any)
	local test = t.test
	local rig_load = reel.rig

	test("rig_load builds an immutable parent-first Motor6D descriptor keyed by Part1 name", function()
		local root_c0 = CFrame.new(1, 0, 0) * CFrame.Angles(0, 0.2, 0)
		local root_c1 = CFrame.new(0, 1, 0) * CFrame.Angles(0.1, 0, 0)
		local child_c0 = CFrame.new(0, 2, 0)
		local child_c1 = CFrame.new(0, 0, 1)
		local model, handles = fixtures.motor_model({
			middle_name = "Torso",
			leaf_name = "Arm",
			root_c0 = root_c0,
			root_c1 = root_c1,
			child_c0 = child_c0,
			child_c1 = child_c1,
			reverse_motor_order = true,
		})

		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			local desc = rig.desc
			local torso_index = desc.name_to_index.Torso
			local arm_index = desc.name_to_index.Arm

			t.equal(desc.count, 2)
			t.non_nil(torso_index)
			t.non_nil(arm_index)
			t.equal(desc.parent[torso_index], 0)
			t.equal(desc.parent[arm_index], torso_index)
			t.equal(desc.is_bone[torso_index], false)
			t.equal(desc.is_bone[arm_index], false)
			t.same(rig.motors[torso_index], handles.root_motor)
			t.same(rig.motors[arm_index], handles.child_motor)
			t.cframe_near(desc.c0[torso_index], root_c0)
			t.cframe_near(desc.c1_inv[torso_index], root_c1:Inverse())
			t.cframe_near(desc.c0[arm_index], child_c0)
			t.cframe_near(desc.c1_inv[arm_index], child_c1:Inverse())
			t.cframe_near(rig.transforms[torso_index], CFrame.identity)
			t.cframe_near(rig.transforms[arm_index], CFrame.identity)
			t.is_nil(rig.world_transforms)
			t.is_nil(rig.blend_scratch)

			t.truthy(table.isfrozen(desc))
			t.truthy(table.isfrozen(desc.names))
			t.truthy(table.isfrozen(desc.parent))
			t.truthy(table.isfrozen(desc.is_bone))
			t.truthy(table.isfrozen(desc.name_to_index))
			t.truthy(table.isfrozen(desc.c0))
			t.truthy(table.isfrozen(desc.c1_inv))
			t.truthy(table.isfrozen(desc.bind))
		end)
	end)

	test("rig_load treats kinematic AnimationConstraints as parent-first animation joints", function()
		local root_c0 = CFrame.new(1, 0, 0) * CFrame.Angles(0, 0.2, 0)
		local root_c1 = CFrame.new(0, 1, 0) * CFrame.Angles(0.1, 0, 0)
		local child_c0 = CFrame.new(0, 2, 0)
		local child_c1 = CFrame.new(0, 0, 1)
		local model, handles = constraint_model(root_c0, root_c1, child_c0, child_c1)

		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			local torso_index = rig.desc.name_to_index.Torso
			local arm_index = rig.desc.name_to_index.Arm

			t.equal(rig.desc.count, 2)
			t.equal(rig.desc.parent[torso_index], 0)
			t.equal(rig.desc.parent[arm_index], torso_index)
			t.equal(rig.desc.is_bone[torso_index], false)
			t.equal(rig.desc.is_bone[arm_index], false)
			t.same(rig.motors[torso_index], handles.root_joint)
			t.same(rig.motors[arm_index], handles.child_joint)
			t.cframe_near(rig.desc.c0[torso_index], root_c0)
			t.cframe_near(rig.desc.c1_inv[torso_index], root_c1:Inverse())
			t.cframe_near(rig.desc.c0[arm_index], child_c0)
			t.cframe_near(rig.desc.c1_inv[arm_index], child_c1:Inverse())
		end)
	end)

	test("rig_load preserves a Motor6D-to-AnimationConstraint hierarchy", function()
		local model, handles = fixtures.motor_model()
		handles.child_motor:Destroy()
		local child_joint = animation_constraint(handles.middle, handles.leaf, model, "Shoulder", nil, nil, true)

		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			local torso_index = rig.desc.name_to_index.Torso
			local arm_index = rig.desc.name_to_index.Arm

			t.equal(rig.desc.parent[arm_index], torso_index)
			t.same(rig.motors[torso_index], handles.root_motor)
			t.same(rig.motors[arm_index], child_joint)
		end)
	end)

	test("rig_load builds Bone chains with their authored bind CFrames", function()
		local root_bind = CFrame.new(0, 1, 0) * CFrame.Angles(0.1, 0, 0)
		local child_bind = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0.2, 0)
		local model, handles = fixtures.bone_model({
			root_bind = root_bind,
			child_bind = child_bind,
		})

		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			local root_index = rig.desc.name_to_index.RootBone
			local child_index = rig.desc.name_to_index.ChildBone

			t.equal(rig.desc.count, 2)
			t.equal(rig.desc.parent[root_index], 0)
			t.equal(rig.desc.parent[child_index], root_index)
			t.equal(rig.desc.is_bone[root_index], true)
			t.equal(rig.desc.is_bone[child_index], true)
			t.same(rig.bones[root_index], handles.root)
			t.same(rig.bones[child_index], handles.child)
			t.cframe_near(rig.desc.bind[root_index], root_bind)
			t.cframe_near(rig.desc.bind[child_index], child_bind)
		end)
	end)

	test("rig_load preserves a mixed Motor6D-to-Bone hierarchy", function()
		local model, torso_motor, spine = mixed_model()

		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			local torso_index = rig.desc.name_to_index.Torso
			local spine_index = rig.desc.name_to_index.Spine

			t.equal(rig.desc.parent[torso_index], 0)
			t.equal(rig.desc.parent[spine_index], torso_index)
			t.equal(rig.desc.is_bone[torso_index], false)
			t.equal(rig.desc.is_bone[spine_index], true)
			t.same(rig.motors[torso_index], torso_motor)
			t.same(rig.bones[spine_index], spine)
		end)
	end)

	test("load_rig accepts an empty model", function()
		local model = Instance.new("Model")
		with_destroy(model, function()
			local rig = rig_load.load_rig(model)
			t.equal(rig.desc.count, 0)
			t.equal(#rig.transforms, 0)
		end)
	end)

	test("rig_load rejects Motor6Ds with a nil endpoint", function()
		local model = Instance.new("Model")
		local root = part("Root", model)
		motor(root, nil, model)

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "nil Part0/Part1")
		end)
	end)

	test("rig_load rejects AnimationConstraints with a nil endpoint", function()
		local model = Instance.new("Model")
		local root = part("Root", model)
		animation_constraint(root, nil, model, nil, nil, nil, true)

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "nil Part0/Part1")
		end)
	end)

	test("rig_load rejects non-kinematic AnimationConstraints", function()
		local model = Instance.new("Model")
		local root = part("Root", model)
		local child = part("Child", model)
		animation_constraint(root, child, model, nil, nil, nil, false)

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "IsKinematic")
		end)
	end)

	test("rig_load rejects two joints targeting the same Instance", function()
		local model, handles = fixtures.motor_model()
		motor(handles.root, handles.middle, model, "Duplicate")

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "duplicate rig target instance")
		end)
	end)

	test("rig_load rejects distinct targets with the same animation name", function()
		local model = Instance.new("Model")
		local root = part("Root", model)
		local first = part("Arm", model)
		local second = part("Arm", model)
		motor(root, first, model, "First")
		motor(root, second, model, "Second")

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "duplicate animation target name")
		end)
	end)

	test("rig_load rejects cycles in the target hierarchy", function()
		local model = Instance.new("Model")
		local first = part("First", model)
		local second = part("Second", model)
		motor(second, first, model, "FirstJoint")
		motor(first, second, model, "SecondJoint")

		with_destroy(model, function()
			t.errors(function()
				rig_load.load_rig(model)
			end, "cycle in rig hierarchy")
		end)
	end)

	test("bind_rig ignores unrelated Instance data and maps targets by name despite discovery order", function()
		local template = sibling_motor_model(false)
		local model, handles = sibling_motor_model(true)
		model.Name = "CompletelyDifferentModelName"
		handles.Arm.Name = "RenamedCloneMotor"
		handles.Leg.Name = "AnotherCloneMotorName"
		local clone_root = handles.Arm.Part0 :: BasePart
		clone_root.Name = "UntargetedRootMayDiffer"
		(handles.Arm.Part1 :: BasePart).Size = Vector3.new(3, 4, 5);
		(handles.Leg.Part1 :: BasePart).Color = Color3.new(0.2, 0.4, 0.6);

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			local first = rig_load.bind_rig(desc, model)
			local second = rig_load.bind_rig(desc, model)

			t.same(first.desc, desc)
			t.same(second.desc, desc)
			t.falsy(rawequal(first.transforms, second.transforms))

			for name, expected_motor in handles do
				local index = desc.name_to_index[name]
				t.same(first.motors[index], expected_motor)
			end
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig accepts equivalent Motor6D and AnimationConstraint layouts", function()
		local root_c0 = CFrame.new(1, 0, 0)
		local root_c1 = CFrame.new(0, 1, 0)
		local child_c0 = CFrame.new(0, 2, 0)
		local child_c1 = CFrame.new(0, 0, 1)
		local template = fixtures.motor_model({
			root_c0 = root_c0,
			root_c1 = root_c1,
			child_c0 = child_c0,
			child_c1 = child_c1,
		})
		local model, handles = constraint_model(root_c0, root_c1, child_c0, child_c1)

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			local bound = rig_load.bind_rig(desc, model)

			t.same(bound.desc, desc)
			t.same(bound.motors[desc.name_to_index.Torso], handles.root_joint)
			t.same(bound.motors[desc.name_to_index.Arm], handles.child_joint)
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig rejects a target-count mismatch", function()
		local template = fixtures.motor_model()
		local model, handles = fixtures.motor_model()
		handles.child_motor:Destroy()

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			t.errors(function()
				rig_load.bind_rig(desc, model)
			end, "target count mismatch")
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig rejects missing target names at the same target count", function()
		local template = fixtures.motor_model()
		local model, handles = fixtures.motor_model()
		handles.leaf.Name = "Other"

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			t.errors(function()
				rig_load.bind_rig(desc, model)
			end, "missing animation target")
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig rejects a Motor6D/Bone target type mismatch", function()
		local template, template_handles = fixtures.motor_model({ leaf_name = "Unused" })
		template_handles.child_motor:Destroy()
		local model, bone_handles = fixtures.bone_model({ root_name = "Torso" })
		bone_handles.child:Destroy()

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			t.equal(desc.count, 1)
			t.errors(function()
				rig_load.bind_rig(desc, model)
			end, "target type mismatch")
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig rejects a changed target parent", function()
		local template = fixtures.motor_model()
		local model = fixtures.motor_model({ child_uses_root = true })

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			t.errors(function()
				rig_load.bind_rig(desc, model)
			end, "parent mismatch")
		end)

		fixtures.destroy(template)
		fixtures.destroy(model)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig accepts tiny Motor6D offset variance and rejects meaningful C0 or C1 changes", function()
		local template = fixtures.motor_model()
		local fuzzy = fixtures.motor_model({
			root_c0 = CFrame.new(5e-6, 0, 0) * CFrame.Angles(5e-6, 0, 0),
			root_c1 = CFrame.new(0, 5e-6, 0) * CFrame.Angles(0, 5e-6, 0),
		})
		local bad_c0 = fixtures.motor_model({ root_c0 = CFrame.new(1e-3, 0, 0) })
		local bad_c1 = fixtures.motor_model({ root_c1 = CFrame.Angles(0, 1e-3, 0) })

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			local bound = rig_load.bind_rig(desc, fuzzy)
			t.same(bound.desc, desc)
			t.errors(function()
				rig_load.bind_rig(desc, bad_c0)
			end, "C0/C1 is outside tolerance")
			t.errors(function()
				rig_load.bind_rig(desc, bad_c1)
			end, "C0/C1 is outside tolerance")
		end)

		fixtures.destroy(template)
		fixtures.destroy(fuzzy)
		fixtures.destroy(bad_c0)
		fixtures.destroy(bad_c1)
		if not ok then
			error(message, 0)
		end
	end)

	test("bind_rig accepts tiny Bone bind variance and rejects meaningful changes", function()
		local template = fixtures.bone_model()
		local fuzzy = fixtures.bone_model({
			root_bind = CFrame.new(5e-6, 0, 0) * CFrame.Angles(0, 0, 5e-6),
		})
		local bad = fixtures.bone_model({ root_bind = CFrame.Angles(0, 0, 1e-3) })

		local ok, message = protect(function()
			local desc = rig_load.load_rig_desc(template)
			local bound = rig_load.bind_rig(desc, fuzzy)
			t.same(bound.desc, desc)
			t.errors(function()
				rig_load.bind_rig(desc, bad)
			end, "bind CFrame is outside tolerance")
		end)

		fixtures.destroy(template)
		fixtures.destroy(fuzzy)
		fixtures.destroy(bad)
		if not ok then
			error(message, 0)
		end
	end)

	test("create_rig_state allocates only local transforms", function()
		local desc = fixtures.desc({
			{ name = "First" },
			{ name = "Second", parent = 1 },
		})
		local motors = {} :: { (Motor6D | AnimationConstraint)? }
		local bones = {} :: { Bone? }
		local rig = rig_load.create_rig_state(desc, motors, bones)

		t.same(rig.desc, desc)
		t.same(rig.motors, motors)
		t.same(rig.bones, bones)
		t.equal(#rig.transforms, 2)
		t.cframe_near(rig.transforms[1], CFrame.identity)
		t.cframe_near(rig.transforms[2], CFrame.identity)
		t.is_nil(rig.world_transforms)
		t.is_nil(rig.blend_scratch)
	end)

	test("optional blend scratch is explicit, complete, and idempotent", function()
		local desc = fixtures.desc({
			{ name = "First" },
			{ name = "Second" },
		})
		local rig = rig_load.create_rig_state(desc)
		local first = rig_load.allocate_blend_scratch(rig)
		local second = rig_load.allocate_blend_scratch(rig)

		t.same(first, second)
		t.same(rig.blend_scratch, first)
		t.equal(#first.weight, 2)
		t.equal(#first.position, 2)
		t.equal(#first.quat_vector, 2)
		t.equal(#first.quat_scalar, 2)
		t.equal(#first.group_weight, 2)
		t.equal(#first.group_touched, 0)
		t.equal(first.weight[1], 0)
		t.vector_near(first.position[2], vector.zero)
	end)

	test("optional retained world output is lazy and idempotent", function()
		local desc = fixtures.desc({ { name = "Joint" } })
		local rig = rig_load.create_rig_state(desc)
		t.is_nil(rig.world_transforms)

		local first = rig_load.get_world_transforms(rig)
		local second = rig_load.get_world_transforms(rig)
		t.same(first, second)
		t.same(rig.world_transforms, first)
	end)
end