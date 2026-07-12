--!strict

type TestCallback = () -> ()

type TestCase = {
	name: string,
	callback: TestCallback,
}

local tests: { TestCase } = {}
local names: { [string]: boolean } = {}

local function describe(value: any): string
	if typeof(value) == "string" then
		return string.format("%q", value)
	end

	return tostring(value)
end

local function failure(message: string?, fallback: string)
	error(message or fallback, 3)
end

local function test(name: string, callback: TestCallback)
	if names[name] then
		error(`duplicate test name: {name}`, 2)
	end

	names[name] = true
	table.insert(tests, {
		name = name,
		callback = callback,
	})
end

local function reset()
	table.clear(tests)
	table.clear(names)
end

local function equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		failure(message, `expected {describe(expected)}, got {describe(actual)}`)
	end
end

local function same(actual: any, expected: any, message: string?)
	if not rawequal(actual, expected) then
		failure(message, `expected the same value as {describe(expected)}, got {describe(actual)}`)
	end
end

local function truthy(actual: any, message: string?)
	if not actual then
		failure(message, `expected a truthy value, got {describe(actual)}`)
	end
end

local function falsy(actual: any, message: string?)
	if actual then
		failure(message, `expected a falsy value, got {describe(actual)}`)
	end
end

local function is_nil(actual: any, message: string?)
	if actual ~= nil then
		failure(message, `expected nil, got {describe(actual)}`)
	end
end

local function non_nil<T>(actual: T?, message: string?): T
	if actual == nil then
		failure(message, "expected a non-nil value")
	end

	return actual :: T
end

local function near(actual: number, expected: number, epsilon: number?, message: string?)
	local tolerance = epsilon or 1e-5
	local difference = math.abs(actual - expected)

	if difference > tolerance or difference ~= difference then
		failure(
			message,
			`expected {actual} to be within {tolerance} of {expected}; difference was {difference}`
		)
	end
end

local function vector_near(actual: vector, expected: vector, epsilon: number?, message: string?)
	local tolerance = epsilon or 1e-5
	local delta = actual - expected
	local difference = math.sqrt(vector.dot(delta, delta))

	if difference > tolerance or difference ~= difference then
		failure(
			message,
			`expected {describe(actual)} to be within {tolerance} of {describe(expected)}; difference was {difference}`
		)
	end
end

local function cframe_near(actual: CFrame, expected: CFrame, epsilon: number?, message: string?)
	local tolerance = epsilon or 1e-5

	if not actual:FuzzyEq(expected, tolerance) then
		failure(
			message,
			`expected {describe(actual)} to be within {tolerance} of {describe(expected)}`
		)
	end
end

local function errors(callback: () -> any, expected_message: string?, message: string?): any
	local ok, result = pcall(callback)

	if ok then
		failure(message, "expected callback to throw an error")
	end

	if expected_message ~= nil and string.find(tostring(result), expected_message, 1, true) == nil then
		failure(
			message,
			`expected error containing {describe(expected_message)}, got {describe(result)}`
		)
	end

	return result
end

local function add_traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

local function run(): number
	if #tests == 0 then
		error("no tests registered", 2)
	end

	local passed = 0
	local failures: { string } = {}

	for _, case in tests do
		local ok, result = xpcall(function(): string
			case.callback()
			return ""
		end, add_traceback)

		if ok then
			passed += 1
			print(`PASS  {case.name}`)
		else
			local formatted = `FAIL  {case.name}\n{result}`
			table.insert(failures, formatted)
			warn(formatted)
		end
	end

	local total = #tests
	print(`\n{passed}/{total} tests passed`)

	if #failures > 0 then
		error(`{#failures} test(s) failed:\n\n{table.concat(failures, "\n\n")}`, 2)
	end

	return passed
end

return {
	test = test,
	reset = reset,
	run = run,

	equal = equal,
	same = same,
	truthy = truthy,
	falsy = falsy,
	is_nil = is_nil,
	["nil"] = is_nil,
	non_nil = non_nil,
	near = near,
	vector_near = vector_near,
	cframe_near = cframe_near,
	errors = errors,
}