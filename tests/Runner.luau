--!strict
export type Case = { id: string, expected: string, actual: string, tick: number, status: string }
export type Report = {
	runId: string,
	suite: string,
	environment: string,
	seed: number,
	status: string,
	cases: { Case },
	failures: { string },
	evidencePaths: { string },
}

local Runner = {}

function Runner.run(
	environment: string,
	runId: string,
	seed: number,
	suite: (check: (string, unknown, unknown, number) -> ()) -> ()
): Report
	local report: Report = {
		runId = runId,
		suite = "T-TOOL-P0",
		environment = environment,
		seed = seed,
		status = "PASS",
		cases = {},
		failures = {},
		evidencePaths = {},
	}
	local function check(id: string, expected: unknown, actual: unknown, tick: number)
		local passed = expected == actual
		table.insert(report.cases, {
			id = id,
			expected = tostring(expected),
			actual = tostring(actual),
			tick = tick,
			status = if passed then "PASS" else "FAIL",
		})
		if not passed then
			table.insert(report.failures, id)
		end
	end
	local ok, problem = pcall(function()
		suite(check)
		return true
	end)
	if not ok then
		table.insert(report.cases, {
			id = "suite-exception",
			expected = "suite returns normally",
			actual = tostring(problem),
			tick = 0,
			status = "FAIL",
		})
		table.insert(report.failures, "suite-exception")
	end
	if #report.cases == 0 then
		check("nonempty-suite", "at least one assertion", "zero assertions", 0)
	end
	if #report.failures > 0 then
		report.status = "FAIL"
	end
	return report
end

-- CLI has no HttpService. Encode this closed report schema, not arbitrary tables.
function Runner.toJson(report: Report): string
	local function quote(value: string): string
		return '"'
			.. string.gsub(value, '[%z\1-\31\\"]', function(character)
				return string.format("\\u%04x", string.byte(character))
			end)
			.. '"'
	end
	local cases: { string } = {}
	for _, case in report.cases do
		table.insert(
			cases,
			string.format(
				'{"id":%s,"expected":%s,"actual":%s,"tick":%d,"status":%s}',
				quote(case.id),
				quote(case.expected),
				quote(case.actual),
				case.tick,
				quote(case.status)
			)
		)
	end
	local failures: { string } = {}
	for _, failure in report.failures do
		table.insert(failures, quote(failure))
	end
	return string.format(
		'{"runId":%s,"suite":%s,"environment":%s,"seed":%d,"status":%s,"cases":[%s],"failures":[%s],"evidencePaths":[]}',
		quote(report.runId),
		quote(report.suite),
		quote(report.environment),
		report.seed,
		quote(report.status),
		table.concat(cases, ","),
		table.concat(failures, ",")
	)
end

return Runner
