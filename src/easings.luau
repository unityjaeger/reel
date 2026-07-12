--!strict
--!optimize 2
--!native

const function linear(t: number): number
	return t
end

const function in_cubicv2(t: number): number
	return t * t * t
end

const function out_cubicv2(t: number): number
	local t1 = t - 1
	return t1 * t1 * t1 + 1
end

const function in_out_cubicv2(t: number): number
	return if t < .5 then 4 * t * t * t else (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
end

const in_cubic = out_cubicv2
const out_cubic = in_cubicv2
const in_out_cubic = in_out_cubicv2

const c4 = math.tau / 3
const c5 = math.tau / 4.5

const function in_elastic(t: number): number
	if t == 0 or t == 1 then
		return t
	end

	return -(2 ^ (10 * t - 10)) * math.sin((10 * t - 10.75) * c4)
end

const function out_elastic(t: number): number
	if t == 0 or t == 1 then
		return t
	end

	return (2 ^ (-10 * t)) * math.sin((10 * t - 0.75) * c4) + 1
end

const function in_out_elastic(t: number): number
	if t == 0 or t == 1 then
		return t
	end

	if t < 0.5 then
		return -((2 ^ (20 * t - 10)) * math.sin((20 * t - 11.125) * c5)) / 2
	end

	return ((2 ^ (-20 * t + 10)) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
end

const function out_bounce(t: number): number
	const n1 = 7.5625
	const d1 = 2.75

	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + .75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + .9375
	else
		t -= 2.625 / d1
		return n1 * t * t + .984375
	end
end

const function in_bounce(t: number): number
	return 1 - out_bounce(1 - t)
end

const function in_out_bounce(t: number): number
	if t < .5 then
		return in_bounce(t * 2) * .5
	end
	
	return (out_bounce((t * 2) - 1) * .5) + .5
end

const function in_constant(t: number): number
	return math.ceil(t)
end

const function out_constant(t: number): number
	return math.floor(t)
end

const function in_out_constant(t: number): number
	return math.round(t)
end

return {
	linear = linear,
	
	in_cubic = in_cubic,
	out_cubic = out_cubic,
	in_out_cubic = in_out_cubic,
	
	in_cubicv2 = in_cubicv2,
	out_cubicv2 = out_cubicv2,
	in_out_cubicv2 = in_out_cubicv2,
	
	in_bounce = in_bounce,
	out_bounce = out_bounce,
	in_out_bounce = in_out_bounce,
	
	in_elastic = in_elastic,
	out_elastic = out_elastic,
	in_out_elastic = in_out_elastic,
	
	in_constant = in_constant,
	out_constant = out_constant,
	in_out_constant = in_out_constant
}