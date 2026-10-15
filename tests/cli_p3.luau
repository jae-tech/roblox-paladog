--!strict
-- Luau CLI entry for the P3 suite; Studio runs the same suite with Instance-path modules.
local Runner = require("./Runner")
local suite = require("./unit/P3")
local env = {
	World = require("../src/server/Simulation/World"),
	FixedStep = require("../src/server/Simulation/FixedStep"),
	Targeting = require("../src/server/Simulation/Targeting"),
	Damage = require("../src/server/Simulation/Damage"),
	Protocol = require("../src/shared/Protocol"),
	MatchService = require("../src/server/Services/MatchService"),
	ProfileService = require("../src/server/Services/ProfileService"),
	newStore = require("./fixtures/InMemoryStoreAdapter"),
}
local report = Runner.run("PureLuau", "cli-p3", 12345, function(check)
	suite(env, check)
end, "T-P3")
print(Runner.toJson(report))
assert(report.status == "PASS", "P3 suite failed")
