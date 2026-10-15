--!strict
local Runner = require("./Runner")
local suite = require("./unit/P0")
local fixtures = {
	clock = require("./fixtures/FakeClock"),
	rng = require("./fixtures/FakeRng"),
	store = require("./fixtures/InMemoryProfileStore"),
}
local guard = require("../test-support/Guard")
local report = Runner.run("PureLuau", "cli-p0", 12345, function(check)
	suite(fixtures, check)
	local empty = Runner.run("PureLuau", "empty", 12345, function() end)
	check("runner-rejects-empty-suite", "FAIL", empty.status, 0)
	local exception = Runner.run("PureLuau", "exception", 12345, function()
		error('escaped "quote"\n\t\\ control')
	end)
	check("runner-captures-exception", "FAIL", exception.status, 0)
	local sentinel = Runner.run("PureLuau", "sentinel-exception", 12345, function()
		error("no exception", 0)
	end)
	check("runner-rejects-sentinel-exception", "FAIL", sentinel.status, 0)
	check(
		"runner-exception-json-escaped",
		false,
		string.find(Runner.toJson(exception), "\n", 1, true) ~= nil,
		0
	)
	for _, studio in { false, true } do
		for _, marker in { false, true } do
			for _, universe in { 10, 11 } do
				check(
					"guard-" .. tostring(studio) .. "-" .. tostring(marker) .. "-" .. universe,
					studio and marker and universe == 10,
					guard(studio, marker, universe, { 10 }),
					0
				)
			end
		end
	end
	check("guard-empty-policy-denied", false, guard(true, true, 0, {}), 0)
end)
print(Runner.toJson(report))
assert(report.status == "PASS", "P0 suite failed")
