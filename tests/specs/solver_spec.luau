--!strict

local fixtures = require("../fixtures")

local function one_target_desc()
	return fixtures.desc({
		{ name = "Joint" },
	})
end

local function two_target_desc()
	return fixtures.desc({
		{ name = "Upper" },
		{ name = "Lower", parent = 1 },
	})
end

local function one_channel_binding()
	return fixtures.binding({
		{ rig_index = 1, channel_index = 1 },
	})
end

local function empty_binding()
	return fixtures.binding({})
end

local function constant_asset(name: string, transform: CFrame, priority: number?)
	return fixtures.asset({
		{
			name = name,
			keys = {
				{ time = 0, transform = transform },
			},
		},
	}, priority or 0)
end

local function state(binding: any, weight: number, priority: number?, time_position: number?)
	return {
		binding = binding,
		time_position = time_position or 0,
		weight = weight,
		priority = priority,
	}
end

return function(t: any, reel: any)
	local test = t.test
	local solver = reel.solver
	local rig_load = reel.rig
	
	test("native solve clears stale transforms when no track or no bound channel is effective", function()
		local rig = fixtures.rig_state(two_target_desc())
		rig.transforms[1] = CFrame.new(10, 20, 30)
		rig.transforms[2] = CFrame.Angles(1, 2, 3)

		solver.solve_prepared(rig, solver.prepare_tracks({}))

		t.cframe_near(rig.transforms[1], CFrame.identity)
		t.cframe_near(rig.transforms[2], CFrame.identity)

		rig.transforms[1] = CFrame.new(10, 20, 30)
		rig.transforms[2] = CFrame.Angles(1, 2, 3)
		local unbound_asset = constant_asset("Upper", CFrame.new(50, 0, 0))
		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = unbound_asset, state = state(empty_binding(), 1) },
		}))

		t.cframe_near(rig.transforms[1], CFrame.identity)
		t.cframe_near(rig.transforms[2], CFrame.identity)
	end)

	test("single-track sampling clamps endpoints and eases interior time", function()
		local rig = fixtures.rig_state(one_target_desc())
		local easing_input: number? = nil
		local asset = fixtures.asset({
			{
				name = "Joint",
				keys = {
					{
						time = 0,
						transform = CFrame.identity,
						easing = function(alpha: number): number
							easing_input = alpha
							return 0.5
						end,
					},
					{
						time = 2,
						transform = CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
					},
				},
			},
		})
		local playback = state(one_channel_binding(), 1, nil, -1)
		local prepared = solver.prepare_tracks({
			{ asset = asset, state = playback },
		})

		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.identity)

		playback.time_position = 0.5
		solver.solve_prepared(rig, prepared)
		t.near(easing_input :: number, 0.25)
		t.cframe_near(
			rig.transforms[1],
			CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
		)

		playback.time_position = 3
		solver.solve_prepared(rig, prepared)
		t.cframe_near(
			rig.transforms[1],
			CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		)
	end)

	test("sampling an exact interior key does not evaluate the preceding easing", function()
		local rig = fixtures.rig_state(one_target_desc())
		local asset = fixtures.asset({
			{
				name = "Joint",
				keys = {
					{
						time = 0,
						transform = CFrame.new(1, 0, 0),
						easing = function(_alpha: number): number
							error("exact keys must bypass easing")
						end,
					},
					{ time = 1, transform = CFrame.new(2, 0, 0) },
					{ time = 2, transform = CFrame.new(3, 0, 0) },
				},
			},
		})
		local playback = state(one_channel_binding(), 1, nil, 1)

		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = asset, state = playback },
		}))

		t.cframe_near(rig.transforms[1], CFrame.new(2, 0, 0))
	end)

	test("binary-search sampling selects every non-exact key interval", function()
		local rig = fixtures.rig_state(one_target_desc())
		local asset = fixtures.asset({
			{
				name = "Joint",
				keys = {
					{ time = 0, transform = CFrame.new(0, 0, 0) },
					{ time = 1, transform = CFrame.new(10, 0, 0) },
					{ time = 2, transform = CFrame.new(20, 0, 0) },
					{ time = 4, transform = CFrame.new(40, 0, 0) },
				},
			},
		})
		local playback = state(one_channel_binding(), 1, nil, 0.5)
		local prepared = solver.prepare_tracks({
			{ asset = asset, state = playback },
		})

		for _, sample in {
			{ time = 0.5, expected = 5 },
			{ time = 1.5, expected = 15 },
			{ time = 3, expected = 30 },
			} do
			playback.time_position = sample.time
			solver.solve_prepared(rig, prepared)
			t.cframe_near(rig.transforms[1], CFrame.new(sample.expected, 0, 0))
		end
	end)

	test("single-track interpolation takes the shortest quaternion hemisphere", function()
		local rig = fixtures.rig_state(one_target_desc())
		local asset = fixtures.asset({
			{
				name = "Joint",
				keys = {
					{ time = 0, transform = CFrame.Angles(0, math.rad(170), 0) },
					{ time = 1, transform = CFrame.Angles(0, math.rad(-170), 0) },
				},
			},
		})
		local playback = state(one_channel_binding(), 1, nil, 0.5)

		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = asset, state = playback },
		}))

		t.cframe_near(rig.transforms[1], CFrame.Angles(0, math.pi, 0), 1e-4)
	end)

	test("single-track weight blends from identity and caps at full influence", function()
		local rig = fixtures.rig_state(one_target_desc())
		local full = CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(60), 0)
		local asset = constant_asset("Joint", full)
		local playback = state(one_channel_binding(), 0.5)
		local prepared = solver.prepare_tracks({
			{ asset = asset, state = playback },
		})

		solver.solve_prepared(rig, prepared)
		t.cframe_near(
			rig.transforms[1],
			CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(30), 0)
		)

		playback.weight = 2
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], full)

		for _, ignored_weight in { 0, -1, 1e-5 } do
			playback.weight = ignored_weight
			solver.solve_prepared(rig, prepared)
			t.cframe_near(rig.transforms[1], CFrame.identity)
		end
	end)

	test("single-track partial bindings clear every unanimated target", function()
		local rig = fixtures.rig_state(two_target_desc())
		rig.transforms[2] = CFrame.new(99, 0, 0)
		local asset = constant_asset("Upper", CFrame.new(3, 0, 0))
		local playback = state(one_channel_binding(), 1)

		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = asset, state = playback },
		}))

		t.cframe_near(rig.transforms[1], CFrame.new(3, 0, 0))
		t.cframe_near(rig.transforms[2], CFrame.identity)
	end)

	test("single-effective-track selection ignores dormant and unbound tracks", function()
		local rig = fixtures.rig_state(two_target_desc())
		local dormant_asset = constant_asset("Upper", CFrame.new(100, 0, 0), 100)
		local unbound_asset = constant_asset("Upper", CFrame.new(200, 0, 0), 200)
		local active_asset = constant_asset("Upper", CFrame.new(7, 0, 0), -10)
		local prepared = solver.prepare_tracks({
			{
				asset = dormant_asset,
				state = state(one_channel_binding(), 1e-5),
			},
			{
				asset = unbound_asset,
				state = state(empty_binding(), 1),
			},
			{
				asset = active_asset,
				state = state(one_channel_binding(), 1),
			},
		})

		--no blend scratch is allocated: this must remain on the single-track path
		solver.solve_prepared(rig, prepared)

		t.is_nil(rig.blend_scratch)
		t.cframe_near(rig.transforms[1], CFrame.new(7, 0, 0))
		t.cframe_near(rig.transforms[2], CFrame.identity)
	end)

	test("two effective native tracks require explicitly allocated scratch", function()
		local rig = fixtures.rig_state(one_target_desc())
		local binding = one_channel_binding()
		local first = constant_asset("Joint", CFrame.new(1, 0, 0))
		local second = constant_asset("Joint", CFrame.new(3, 0, 0))
		local prepared = solver.prepare_tracks({
			{ asset = first, state = state(binding, 1) },
			{ asset = second, state = state(binding, 1) },
		})

		t.errors(function()
			solver.solve_prepared(rig, prepared)
		end)

		rig_load.allocate_blend_scratch(rig)
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(2, 0, 0))
	end)

	test("three effective native tracks all contribute to one solve", function()
		local rig = fixtures.rig_state(one_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local binding = one_channel_binding()
		local first = constant_asset("Joint", CFrame.new(0, 0, 0), 1)
		local second = constant_asset("Joint", CFrame.new(3, 0, 0), 1)
		local third = constant_asset("Joint", CFrame.new(9, 0, 0), 1)
		local prepared = solver.prepare_tracks({
			{ asset = first, state = state(binding, 1) },
			{ asset = second, state = state(binding, 1) },
			{ asset = third, state = state(binding, 1) },
		})

		t.equal(prepared.count, 3)
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(4, 0, 0))
	end)

	test("same-priority tracks share capacity and use shortest-hemisphere rotation", function()
		local rig = fixtures.rig_state(one_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local binding = one_channel_binding()
		local first = constant_asset(
			"Joint",
			CFrame.Angles(0, math.rad(170), 0),
			1
		)
		local second = constant_asset(
			"Joint",
			CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(-170), 0),
			1
		)

		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = first, state = state(binding, 1) },
			{ asset = second, state = state(binding, 1) },
		}))

		t.cframe_near(
			rig.transforms[1],
			CFrame.new(1, 0, 0) * CFrame.Angles(0, math.pi, 0),
			1e-4
		)
	end)

	test("sparse multi-track solves match isolated tracks and do not retain scratch state", function()
		local rig = fixtures.rig_state(two_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local first_asset = constant_asset("Upper", CFrame.new(2, 0, 0), 1)
		local second_asset = constant_asset("Lower", CFrame.new(4, 0, 0), 1)
		local first_state = state(fixtures.binding({
			{ rig_index = 1, channel_index = 1 },
		}), 2)
		local second_state = state(fixtures.binding({
			{ rig_index = 2, channel_index = 1 },
		}), 2)
		local prepared = solver.prepare_tracks({
			{ asset = first_asset, state = first_state },
			{ asset = second_asset, state = second_state },
		})

		--two globally effective tracks force the multi-track path even though their target sets are disjoint
		--each result must still equal its full single-track result, including for weights above one
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(2, 0, 0))
		t.cframe_near(rig.transforms[2], CFrame.new(4, 0, 0))

		first_state.binding = fixtures.binding({
			{ rig_index = 2, channel_index = 1 },
		})
		second_state.binding = fixtures.binding({
			{ rig_index = 1, channel_index = 1 },
		})
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(4, 0, 0))
		t.cframe_near(rig.transforms[2], CFrame.new(2, 0, 0))
	end)

	test("an underfilled priority group leaves the remaining identity influence", function()
		local rig = fixtures.rig_state(one_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local binding = one_channel_binding()
		local first = constant_asset("Joint", CFrame.new(4, 0, 0), 1)
		local second = constant_asset("Joint", CFrame.identity, 1)
		local first_state = state(binding, 0.25)
		local second_state = state(binding, 0.25)
		local prepared = solver.prepare_tracks({
			{ asset = first, state = first_state },
			{ asset = second, state = second_state },
		})

		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(1, 0, 0))

		first_state.weight = 0.5
		second_state.weight = 0.5
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(2, 0, 0))

		first_state.weight = 1
		second_state.weight = 1
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(2, 0, 0))
	end)

	test("an underfilled multi-track rotation blends the unused capacity from identity", function()
		local rig = fixtures.rig_state(one_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local binding = one_channel_binding()
		local quarter_turn = CFrame.Angles(0, math.rad(90), 0)
		local first = constant_asset("Joint", quarter_turn, 1)
		local second = constant_asset("Joint", quarter_turn, 1)

		solver.solve_prepared(rig, solver.prepare_tracks({
			{ asset = first, state = state(binding, 0.25) },
			{ asset = second, state = state(binding, 0.25) },
		}))

		t.cframe_near(rig.transforms[1], CFrame.Angles(0, math.rad(45), 0))
	end)

	test("higher priorities consume capacity per target and lower priorities fill the rest", function()
		local rig = fixtures.rig_state(two_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local high_asset = constant_asset("Upper", CFrame.new(-1, 0, 0), 2)
		local low_asset = fixtures.asset({
			{
				name = "Upper",
				keys = { { time = 0, transform = CFrame.new(1, 0, 0) } },
			},
			{
				name = "Lower",
				keys = { { time = 0, transform = CFrame.new(3, 0, 0) } },
			},
		}, 1)
		local high_binding = fixtures.binding({
			{ rig_index = 1, channel_index = 1 },
		})
		local low_binding = fixtures.binding({
			{ rig_index = 1, channel_index = 1 },
			{ rig_index = 2, channel_index = 2 },
		})
		local high_state = state(high_binding, 0.5)
		local prepared = solver.prepare_tracks({
			{ asset = low_asset, state = state(low_binding, 1) },
			{ asset = high_asset, state = high_state },
		})

		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.identity)
		t.cframe_near(rig.transforms[2], CFrame.new(3, 0, 0))

		high_state.weight = 1
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(-1, 0, 0))
		t.cframe_near(rig.transforms[2], CFrame.new(3, 0, 0))
	end)

	test("priority changes take effect only after preparation and prepared storage is reusable", function()
		local rig = fixtures.rig_state(one_target_desc())
		rig_load.allocate_blend_scratch(rig)
		local binding = one_channel_binding()
		local first = constant_asset("Joint", CFrame.new(10, 0, 0))
		local second = constant_asset("Joint", CFrame.new(20, 0, 0))
		local first_state = state(binding, 1, 2)
		local second_state = state(binding, 1, 1)
		local playing = {
			{ asset = first, state = first_state },
			{ asset = second, state = second_state },
		}
		local prepared = solver.prepare_tracks(playing)

		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(10, 0, 0))

		first_state.priority = 0
		solver.solve_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], CFrame.new(10, 0, 0))

		local reused = solver.prepare_tracks(playing, prepared)
		t.same(reused, prepared)
		solver.solve_prepared(rig, reused)
		t.cframe_near(rig.transforms[1], CFrame.new(20, 0, 0))
	end)

	test("repreparing a shorter native list removes stale tracks and priority groups", function()
		local binding = one_channel_binding()
		local first = constant_asset("Joint", CFrame.new(1, 0, 0), 3)
		local second = constant_asset("Joint", CFrame.new(2, 0, 0), 2)
		local third = constant_asset("Joint", CFrame.new(3, 0, 0), 1)
		local first_playing = { asset = first, state = state(binding, 1) }
		local prepared = solver.prepare_tracks({
			first_playing,
			{ asset = second, state = state(binding, 1) },
			{ asset = third, state = state(binding, 1) },
		})

		t.equal(prepared.count, 3)
		t.equal(prepared.group_count, 3)

		local reused = solver.prepare_tracks({ first_playing }, prepared)
		t.same(reused, prepared)
		t.equal(reused.count, 1)
		t.equal(reused.group_count, 1)
		t.is_nil(reused.tracks[2])
		t.is_nil(reused.tracks[3])
		t.is_nil(reused.groups[2])
		t.is_nil(reused.groups[3])

		solver.prepare_tracks({}, reused)
		t.equal(reused.count, 0)
		t.equal(reused.group_count, 0)
		t.is_nil(reused.tracks[1])
		t.is_nil(reused.groups[1])
	end)
end