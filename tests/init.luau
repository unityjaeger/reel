--!strict

local reel = require("@game/ReplicatedStorage/reel")

local framework = require("@self/framework")

local registrars: { (any, any) -> () } = {
	require("@self/specs/easings_spec"),
	require("@self/specs/animation_load_spec"),
	require("@self/specs/rig_load_spec"),
	require("@self/specs/solver_spec"),
	require("@self/specs/delta_spec"),
	require("@self/specs/world_transforms_spec"),
	require("@self/specs/workflow_spec"),
}

local function run(): number
	framework.reset()

	for _, register in registrars do
		register(framework, reel)
	end

	return framework.run()
end

return run