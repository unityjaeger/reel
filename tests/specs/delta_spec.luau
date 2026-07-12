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

local function constant_asset(name: string, transform: CFrame)
	return fixtures.asset({
		{
			name = name,
			keys = {
				{ time = 0, transform = transform },
			},
		},
	})
end

local function state(binding: any, weight: number, time_position: number?)
	return {
		binding = binding,
		time_position = time_position or 0,
		weight = weight,
	}
end

return function(t: any, reel: any)
	local test = t.test
	local solver = reel.solver
	
	test("an empty delta pass leaves the native result untouched", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(3, 4, 5) * CFrame.Angles(0.2, 0.3, 0.4)
		rig.transforms[1] = base

		solver.apply_delta_prepared(rig, solver.prepare_delta_tracks({}))

		t.cframe_near(rig.transforms[1], base)
	end)

	test("identity additive animation is neutral", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(3, 0, 1) * CFrame.Angles(0, 0.4, 0)
		rig.transforms[1] = base
		local asset = constant_asset("Joint", CFrame.identity)
		local prepared = solver.prepare_delta_tracks({
			{
				asset = asset,
				state = state(one_channel_binding(), 1),
				mode = "additive",
			},
		})

		solver.apply_delta_prepared(rig, prepared)

		t.cframe_near(rig.transforms[1], base)
	end)

	test("prepared delta tracks sample live time-varying translation and rotation", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(3, -2, 1) * CFrame.Angles(0.2, -0.1, 0.3)
		local full_delta = CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		local asset = fixtures.asset({
			{
				name = "Joint",
				keys = {
					{ time = 0, transform = CFrame.identity },
					{ time = 2, transform = full_delta },
				},
			},
		})
		local delta_state = state(one_channel_binding(), 1, 0)
		local prepared = solver.prepare_delta_tracks({
			{ asset = asset, state = delta_state, mode = "additive" },
		})

		rig.transforms[1] = base
		solver.apply_delta_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], base)

		delta_state.time_position = 1
		rig.transforms[1] = base
		solver.apply_delta_prepared(rig, prepared)
		t.cframe_near(
			rig.transforms[1],
			base * CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
		)

		delta_state.time_position = 2
		rig.transforms[1] = base
		solver.apply_delta_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], base * full_delta)
	end)

	test("additive deltas post-compose in local space and affect only bound targets", function()
		local rig = fixtures.rig_state(two_target_desc())
		local upper_base = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(30), 0)
		local lower_base = CFrame.new(-2, 0, 5) * CFrame.Angles(0.1, 0.2, 0.3)
		rig.transforms[1] = upper_base
		rig.transforms[2] = lower_base
		local delta = CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
		local asset = constant_asset("Upper", delta)
		local prepared = solver.prepare_delta_tracks({
			{
				asset = asset,
				state = state(one_channel_binding(), 1),
				mode = "additive",
			},
		})

		solver.apply_delta_prepared(rig, prepared)

		t.cframe_near(rig.transforms[1], upper_base * delta)
		t.cframe_near(rig.transforms[2], lower_base)
	end)

	test("delta weights blend from identity, cap at full, and ignore non-effective values", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(1, 2, 3) * CFrame.Angles(0.1, 0.2, 0.3)
		local delta = CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(60), 0)
		local weighted_delta = CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(30), 0)
		local asset = constant_asset("Joint", delta)
		local delta_state = state(one_channel_binding(), 0.5)
		local prepared = solver.prepare_delta_tracks({
			{ asset = asset, state = delta_state, mode = "additive" },
		})

		rig.transforms[1] = base
		solver.apply_delta_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], base * weighted_delta)

		delta_state.weight = 2
		rig.transforms[1] = base
		solver.apply_delta_prepared(rig, prepared)
		t.cframe_near(rig.transforms[1], base * delta)

		for _, ignored_weight in { 0, -1, 1e-5 } do
			delta_state.weight = ignored_weight
			rig.transforms[1] = base
			solver.apply_delta_prepared(rig, prepared)
			t.cframe_near(rig.transforms[1], base)
		end
	end)

	test("subtractive mode inverts the already-weighted delta", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(1, 2, 3) * CFrame.Angles(0.2, -0.3, 0.1)
		local delta = CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(60), 0)
		local weighted_delta = CFrame.new(2, 0, 0) * CFrame.Angles(0, math.rad(30), 0)
		local asset = constant_asset("Joint", delta)
		rig.transforms[1] = base
		local prepared = solver.prepare_delta_tracks({
			{
				asset = asset,
				state = state(one_channel_binding(), 0.5),
				mode = "subtractive",
			},
		})

		solver.apply_delta_prepared(rig, prepared)

		t.cframe_near(rig.transforms[1], base * weighted_delta:Inverse())
	end)

	test("matching adjacent additive and subtractive deltas cancel exactly", function()
		local rig = fixtures.rig_state(one_target_desc())
		local base = CFrame.new(-2, 5, 7) * CFrame.Angles(0.4, -0.2, 0.1)
		local delta = CFrame.new(4, 1, -2) * CFrame.Angles(0.2, math.rad(70), -0.1)
		local asset = constant_asset("Joint", delta)
		local shared_state = state(one_channel_binding(), 0.4)
		rig.transforms[1] = base
		local prepared = solver.prepare_delta_tracks({
			{ asset = asset, state = shared_state, mode = "additive" },
			{ asset = asset, state = shared_state, mode = "subtractive" },
		})

		solver.apply_delta_prepared(rig, prepared)

		t.cframe_near(rig.transforms[1], base, 1e-4)
	end)

	test("delta preparation preserves non-commutative application order", function()
		local rig = fixtures.rig_state(one_target_desc())
		local binding = one_channel_binding()
		local rotation = CFrame.Angles(0, math.rad(90), 0)
		local translation = CFrame.new(2, 0, 0)
		local rotation_asset = constant_asset("Joint", rotation)
		local translation_asset = constant_asset("Joint", translation)
		local base = CFrame.new(0, 1, 0)
		rig.transforms[1] = base

		solver.apply_delta_prepared(rig, solver.prepare_delta_tracks({
			{
				asset = rotation_asset,
				state = state(binding, 1),
				mode = "additive",
			},
			{
				asset = translation_asset,
				state = state(binding, 1),
				mode = "additive",
			},
		}))

		t.cframe_near(rig.transforms[1], base * rotation * translation)
		t.falsy(rig.transforms[1]:FuzzyEq(base * translation * rotation, 1e-4))
	end)

	test("multiple delta tracks require no native blend scratch", function()
		local rig = fixtures.rig_state(one_target_desc())
		local binding = one_channel_binding()
		local first = CFrame.new(1, 0, 0)
		local second = CFrame.Angles(0, 0.25, 0)
		local first_asset = constant_asset("Joint", first)
		local second_asset = constant_asset("Joint", second)

		solver.apply_delta_prepared(rig, solver.prepare_delta_tracks({
			{ asset = first_asset, state = state(binding, 1), mode = "additive" },
			{ asset = second_asset, state = state(binding, 1), mode = "additive" },
		}))

		t.is_nil(rig.blend_scratch)
		t.cframe_near(rig.transforms[1], first * second)
	end)

	test("repreparing delta tracks reuses storage, updates mode, and removes old tracks", function()
		local rig = fixtures.rig_state(one_target_desc())
		local binding = one_channel_binding()
		local first_delta = CFrame.new(2, 0, 0)
		local second_delta = CFrame.new(0, 3, 0)
		local first_asset = constant_asset("Joint", first_delta)
		local second_asset = constant_asset("Joint", second_delta)
		local first_track: any = {
			asset = first_asset,
			state = state(binding, 1),
			mode = "additive",
		}
		local prepared = solver.prepare_delta_tracks({
			first_track,
			{
				asset = second_asset,
				state = state(binding, 1),
				mode = "additive",
			},
		})

		first_track.mode = "subtractive"
		local reused = solver.prepare_delta_tracks({ first_track }, prepared)
		t.same(reused, prepared)
		t.equal(reused.count, 1)
		t.is_nil(reused.tracks[2])

		rig.transforms[1] = CFrame.identity
		solver.apply_delta_prepared(rig, reused)
		t.cframe_near(rig.transforms[1], first_delta:Inverse())
	end)

	test("prepare_delta_tracks rejects unknown modes", function()
		local bad_track: any = {
			asset = constant_asset("Joint", CFrame.identity),
			state = state(one_channel_binding(), 1),
			mode = "multiplicative",
		}

		t.errors(function()
			solver.prepare_delta_tracks({ bad_track })
		end, "unknown delta track mode")
	end)
end