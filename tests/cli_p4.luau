--!strict
-- CLI and Studio execute the same injected P4 behaviour suite.
local Runner = require("./Runner")
local suite = require("./unit/P4")
local env = {
	World = require("../src/server/Simulation/World"),
	ProjectileSystem = require("../src/server/Simulation/ProjectileSystem"),
	HeroActionSystem = require("../src/server/Simulation/HeroActionSystem"),
	Protocol = require("../src/shared/Protocol"),
	MatchService = require("../src/server/Services/MatchService"),
	ProfileService = require("../src/server/Services/ProfileService"),
	newStore = require("./fixtures/InMemoryStoreAdapter"),
}
local report = Runner.run("PureLuau", "cli-p4", 12345, function(check)
	suite(env, check)
end, "T-P4")
print(Runner.toJson(report))
assert(report.status == "PASS", "P4 suite failed")
