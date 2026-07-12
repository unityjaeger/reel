--!strict

return function(t: any, reel: any)
	local test = t.test
	local easings = reel.easings
	local easing_map = reel.easing_map

	test("easings preserve the interpolation endpoints", function()
		local functions = {
			easings.linear,
			easings.in_cubic,
			easings.out_cubic,
			easings.in_out_cubic,
			easings.in_cubicv2,
			easings.out_cubicv2,
			easings.in_out_cubicv2,
			easings.in_bounce,
			easings.out_bounce,
			easings.in_out_bounce,
			easings.in_elastic,
			easings.out_elastic,
			easings.in_out_elastic,
			easings.in_constant,
			easings.out_constant,
			easings.in_out_constant,
		}

		for index, easing: (t: number) -> number in functions do
			t.near(easing(0), 0, 1e-12, `easing {index} at zero`)
			t.near(easing(1), 1, 1e-12, `easing {index} at one`)
		end
	end)

	test("linear and constant easings keep their exact step semantics", function()
		t.equal(easings.linear(0.25), 0.25)
		t.equal(easings.in_constant(0.25), 1)
		t.equal(easings.out_constant(0.25), 0)
		t.equal(easings.in_out_constant(0.49), 0)
		t.equal(easings.in_out_constant(0.51), 1)
	end)

	test("cubic easing families keep their direction and midpoint formulas", function()
		t.near(easings.in_cubic(0.25), 0.578125, 1e-12)
		t.near(easings.out_cubic(0.25), 0.015625, 1e-12)
		t.near(easings.in_out_cubic(0.25), 0.0625, 1e-12)
		t.near(easings.in_out_cubic(0.75), 0.9375, 1e-12)

		t.near(easings.in_cubicv2(0.25), 0.015625, 1e-12)
		t.near(easings.out_cubicv2(0.25), 0.578125, 1e-12)
		t.near(easings.in_out_cubicv2(0.25), 0.0625, 1e-12)
		t.near(easings.in_out_cubicv2(0.75), 0.9375, 1e-12)
	end)

	test("bounce and elastic easings keep representative interior values", function()
		--one sample from each piece of out_bounce
		t.near(easings.out_bounce(0.25), 0.47265625, 1e-12)
		t.near(easings.out_bounce(0.5), 0.765625, 1e-12)
		t.near(easings.out_bounce(0.8), 0.94, 1e-12)
		t.near(easings.out_bounce(0.95), 0.98453125, 1e-12)

		t.near(easings.in_bounce(0.25), 0.02734375, 1e-12)
		t.near(easings.in_out_bounce(0.25), 0.1171875, 1e-12)
		t.near(easings.in_out_bounce(0.75), 0.8828125, 1e-12)

		t.near(easings.in_elastic(0.5), -0.015625, 1e-12)
		t.near(easings.out_elastic(0.5), 1.015625, 1e-12)
		t.near(easings.in_out_elastic(0.25), 0.011969444423734044, 1e-12)
		t.near(easings.in_out_elastic(0.5), 0.5, 1e-12)
		t.near(easings.in_out_elastic(0.75), 0.988030555576266, 1e-12)
	end)

	test("easing_map maps every style and direction to the exact easing", function()
		local IN = Enum.PoseEasingDirection.In
		local OUT = Enum.PoseEasingDirection.Out
		local IN_OUT = Enum.PoseEasingDirection.InOut
		local expected = {
			[Enum.PoseEasingStyle.Linear] = {
				[IN] = easings.linear,
				[OUT] = easings.linear,
				[IN_OUT] = easings.linear,
			},
			[Enum.PoseEasingStyle.Cubic] = {
				[IN] = easings.in_cubic,
				[OUT] = easings.out_cubic,
				[IN_OUT] = easings.in_out_cubic,
			},
			[Enum.PoseEasingStyle.CubicV2] = {
				[IN] = easings.in_cubicv2,
				[OUT] = easings.out_cubicv2,
				[IN_OUT] = easings.in_out_cubicv2,
			},
			[Enum.PoseEasingStyle.Elastic] = {
				[IN] = easings.in_elastic,
				[OUT] = easings.out_elastic,
				[IN_OUT] = easings.in_out_elastic,
			},
			[Enum.PoseEasingStyle.Bounce] = {
				[IN] = easings.in_bounce,
				[OUT] = easings.out_bounce,
				[IN_OUT] = easings.in_out_bounce,
			},
			[Enum.PoseEasingStyle.Constant] = {
				[IN] = easings.in_constant,
				[OUT] = easings.out_constant,
				[IN_OUT] = easings.in_out_constant,
			},
		}

		for style, expected_by_direction in expected do
			local by_direction = (easing_map :: any)[style]
			t.non_nil(by_direction, `missing style {style.Name}`)

			for direction, expected_easing in expected_by_direction do
				local easing = by_direction[direction]
				t.same(easing, expected_easing, `wrong {style.Name}/{direction.Name}`)
			end
		end
	end)
end