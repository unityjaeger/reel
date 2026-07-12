--!strict

export type RigDesc = {
	read count: number,

	read names: { string },
	read parent: { number },

	read is_bone: { boolean },

	read name_to_index: { [string]: number },

	read c0: { CFrame },
	read c1_inv: { CFrame },
	read bind: { CFrame },
}

export type BlendScratch = {
	weight: { number },
	position: { vector },
	quat_vector: { vector },
	quat_scalar: { number },

	group_weight: { number },
	group_touched: { number },
}

export type RigState = {
	desc: RigDesc,

	motors: { Motor6D? },
	bones: { Bone? },

	transforms: { CFrame },
	world_transforms: { CFrame }?, -- allocated by get_world_transforms when needed

	blend_scratch: BlendScratch?, -- allocated explicitly through allocate_blend_scratch
}

export type Rig = RigState

type RawNode = {
	order: number,
	key: Instance,
	parent_key: Instance?,
	name: string,

	is_bone: boolean,
	motor: Motor6D?,
	bone: Bone?,

	c0: CFrame,
	c1: CFrame,
	bind: CFrame,

	depth: number?,
}

const IDENTITY = CFrame.identity

const function freeze_rig_desc(desc: RigDesc): RigDesc
	table.freeze(desc.names)
	table.freeze(desc.parent)
	table.freeze(desc.is_bone)
	table.freeze(desc.name_to_index)
	table.freeze(desc.c0)
	table.freeze(desc.c1_inv)
	table.freeze(desc.bind)

	return table.freeze(desc)
end

const function create_rig_state(desc: RigDesc, motors: { Motor6D? }?, bones: { Bone? }?): RigState
	local result: RigState = {
		desc = desc,

		motors = motors or {},
		bones = bones or {},

		transforms = table.create(desc.count, IDENTITY),
		world_transforms = nil,
		blend_scratch = nil,
	}

	return result
end

const function create_blend_scratch(desc: RigDesc): BlendScratch
	local count = desc.count
	return {
		weight = table.create(count, 0),
		position = table.create(count, vector.zero),
		quat_vector = table.create(count, vector.zero),
		quat_scalar = table.create(count, 0),
		group_weight = table.create(count, 0),
		group_touched = {},
	}
end

const function allocate_blend_scratch(rig: RigState): BlendScratch
	local scratch = rig.blend_scratch
	if scratch == nil then
		scratch = create_blend_scratch(rig.desc)
		rig.blend_scratch = scratch
	end

	return scratch :: BlendScratch
end

const function get_world_transforms(rig: RigState): { CFrame }
	local world_transforms = rig.world_transforms
	if world_transforms == nil then
		world_transforms = table.create(rig.desc.count) :: { CFrame }
		rig.world_transforms = world_transforms
	end

	return world_transforms :: { CFrame }
end

const function add_node(raw_nodes: { RawNode }, key_to_raw: { [Instance]: number }, node: RawNode)
	if key_to_raw[node.key] ~= nil then
		error(`duplicate rig target instance: {node.key:GetFullName()}`)
	end

	table.insert(raw_nodes, node)
	key_to_raw[node.key] = #raw_nodes
end

const function depth(raw_nodes: { RawNode }, visiting: { [number]: boolean }, key_to_raw: { [Instance]: number }, raw_index: number): number
	local cached = raw_nodes[raw_index].depth
	if cached ~= nil then
		return cached
	end

	if visiting[raw_index] then
		error("cycle in rig hierarchy")
	end

	visiting[raw_index] = true

	local parent_key = raw_nodes[raw_index].parent_key
	local parent_raw = if parent_key ~= nil then key_to_raw[parent_key] else nil

	local result = if parent_raw ~= nil then depth(raw_nodes, visiting, key_to_raw, parent_raw) + 1 else 0

	visiting[raw_index] = nil
	raw_nodes[raw_index].depth = result

	return result
end

const function read_raw_nodes(rig: Model): { RawNode }
	local raw_nodes: { RawNode } = {}
	local key_to_raw: { [Instance]: number } = {}

	for order, motor: Motor6D in rig:QueryDescendants("Motor6D") do
		local part0 = motor.Part0
		local part1 = motor.Part1

		if part0 == nil or part1 == nil then
			error(`Motor6D has nil Part0/Part1: {motor:GetFullName()}`)
		end

		add_node(raw_nodes, key_to_raw, {
			order = order,
			key = part1,
			parent_key = part0,
			name = part1.Name,

			is_bone = false,
			motor = motor,
			bone = nil,

			c0 = motor.C0,
			c1 = motor.C1,
			bind = IDENTITY,
		})
	end

	for order, bone: Bone in rig:QueryDescendants("Bone") do
		local parent = bone.Parent
		local parent_key =
			if parent ~= nil and (parent:IsA("Bone") or parent:IsA("BasePart"))
			then parent
			else nil

		add_node(raw_nodes, key_to_raw, {
			order = order,
			key = bone,
			parent_key = parent_key,
			name = bone.Name,

			is_bone = true,
			motor = nil,
			bone = bone,

			c0 = IDENTITY,
			c1 = IDENTITY,
			bind = bone.CFrame,
		})
	end

	local visiting: { [number]: boolean } = {}

	for index in raw_nodes do
		depth(raw_nodes, visiting, key_to_raw, index)
	end

	table.sort(raw_nodes, function(a, b)
		if a.depth ~= b.depth then
			return (a.depth :: number) < (b.depth :: number)
		end

		return (a.order :: number) < (b.order :: number)
	end)

	return raw_nodes
end

const function build_rig(raw_nodes: { RawNode }): (RigDesc, { Motor6D? }, { Bone? })
	local count = #raw_nodes
	local desc: RigDesc = {
		count = count,
		names = table.create(count) :: { string },
		parent = table.create(count) :: { number },
		is_bone = table.create(count) :: { boolean },
		name_to_index = {},
		c0 = table.create(count) :: { CFrame },
		c1_inv = table.create(count) :: { CFrame },
		bind = table.create(count) :: { CFrame },
	}

	local motors: { Motor6D? } = {}
	local bones: { Bone? } = {}

	local key_to_index: { [Instance]: number } = {}

	for index, node in raw_nodes do
		key_to_index[node.key] = index
	end

	for index, node in raw_nodes do
		if desc.name_to_index[node.name] ~= nil then
			error(`duplicate animation target name: {node.name}`)
		end

		desc.names[index] = node.name
		desc.name_to_index[node.name] = index

		desc.parent[index] = if node.parent_key ~= nil then key_to_index[node.parent_key] or 0 else 0
		desc.is_bone[index] = node.is_bone
		motors[index] = node.motor
		bones[index] = node.bone

		desc.c0[index] = node.c0
		desc.c1_inv[index] = node.c1:Inverse()
		desc.bind[index] = node.bind
	end

	return freeze_rig_desc(desc), motors, bones
end

const function read_rig(rig: Model): (RigDesc, { Motor6D? }, { Bone? })
	return build_rig(read_raw_nodes(rig))
end

const function load_rig_desc(rig: Model): RigDesc
	local desc = read_rig(rig)
	return desc
end

local function bind_raw_nodes(desc: RigDesc, raw_nodes: { RawNode }): ({ Motor6D? }, { Bone? })
	if #raw_nodes ~= desc.count then
		error(`rig target count mismatch: expected {desc.count}, got {#raw_nodes}`)
	end

	local name_to_raw: { [string]: RawNode } = {}
	local key_to_raw: { [Instance]: RawNode } = {}

	for _, node in raw_nodes do
		if name_to_raw[node.name] ~= nil then
			error(`duplicate animation target name: {node.name}`)
		end

		name_to_raw[node.name] = node
		key_to_raw[node.key] = node
	end

	local motors: { Motor6D? } = {}
	local bones: { Bone? } = {}

	for index = 1, desc.count do
		local name = desc.names[index]
		local node = name_to_raw[name]
		if node == nil then
			error(`rig is missing animation target "{name}"`)
		end

		if node.is_bone ~= desc.is_bone[index] then
			error(`rig target type mismatch for "{name}"`)
		end

		local expected_parent_index = desc.parent[index]
		local expected_parent_name = if expected_parent_index == 0 then nil else desc.names[expected_parent_index]
		local actual_parent = if node.parent_key == nil then nil else key_to_raw[node.parent_key]
		local actual_parent_name = if actual_parent == nil then nil else actual_parent.name

		if actual_parent_name ~= expected_parent_name then
			error(`rig parent mismatch for "{name}": expected "{expected_parent_name}", got "{actual_parent_name}"`)
		end

		if desc.is_bone[index] then
			if not node.bind:FuzzyEq(desc.bind[index]) then
				error(`rig bind CFrame is outside tolerance for Bone "{name}"`)
			end
		elseif not node.c0:FuzzyEq(desc.c0[index])
			or not node.c1:Inverse():FuzzyEq(desc.c1_inv[index])
		then
			error(`rig C0/C1 is outside tolerance for Motor6D target "{name}"`)
		end

		motors[index] = node.motor
		bones[index] = node.bone
	end

	return motors, bones
end

const function bind_rig(desc: RigDesc, rig: Model): RigState
	local motors, bones = bind_raw_nodes(desc, read_raw_nodes(rig))
	return create_rig_state(desc, motors, bones)
end

const function load_rig(rig: Model): RigState
	local desc, motors, bones = read_rig(rig)
	return create_rig_state(desc, motors, bones)
end

return {
	create_rig_state = create_rig_state,
	allocate_blend_scratch = allocate_blend_scratch,
	get_world_transforms = get_world_transforms,
	load_rig_desc = load_rig_desc,
	bind_rig = bind_rig,
	load_rig = load_rig
}