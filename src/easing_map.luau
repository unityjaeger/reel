--!strict

const easings = require("./easings")

const IN = Enum.PoseEasingDirection.In
const OUT = Enum.PoseEasingDirection.Out
const IN_OUT = Enum.PoseEasingDirection.InOut

const LINEAR = Enum.PoseEasingStyle.Linear
const CUBIC = Enum.PoseEasingStyle.Cubic
const CUBICV2 = Enum.PoseEasingStyle.CubicV2
const ELASTIC = Enum.PoseEasingStyle.Elastic
const BOUNCE = Enum.PoseEasingStyle.Bounce
const CONSTANT = Enum.PoseEasingStyle.Constant

return {
	[LINEAR] = {
		[IN] = easings.linear,
		[OUT] = easings.linear,
		[IN_OUT] = easings.linear,
	},
	[CUBIC] = {
		[IN] = easings.in_cubic,
		[OUT] = easings.out_cubic,
		[IN_OUT] = easings.in_out_cubic,
	},
	[CUBICV2] = {
		[IN] = easings.in_cubicv2,
		[OUT] = easings.out_cubicv2,
		[IN_OUT] = easings.in_out_cubicv2,
	},
	[BOUNCE] = {
		[IN] = easings.in_bounce,
		[OUT] = easings.out_bounce,
		[IN_OUT] = easings.in_out_bounce,
	},
	[ELASTIC] = {
		[IN] = easings.in_elastic,
		[OUT] = easings.out_elastic,
		[IN_OUT] = easings.in_out_elastic,
	},
	[CONSTANT] = {
		[IN] = easings.in_constant,
		[OUT] = easings.out_constant,
		[IN_OUT] = easings.in_out_constant,
	}
}