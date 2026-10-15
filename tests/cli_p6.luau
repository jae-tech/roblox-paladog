--!strict
local Runner = require("./Runner")
local suite = require("./unit/P6")
local report = Runner.run("PureLuau", "cli-p6", 12345, function(check)
	suite({
		World = require("../src/server/Simulation/World"),
		StageSystem = require("../src/server/Simulation/StageSystem"),
		Stages = require("../src/server/Config/Generated/Stages"),
		ProjectileSystem = require("../src/server/Simulation/ProjectileSystem"),
		SessionStore = require("../src/server/Services/SessionStore"),
		Schema = require("../src/server/Services/ProfileSchema"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		Catalog = require("../src/shared/PublicCatalog"),
	}, check)
end, "T-P6")
print(Runner.toJson(report))
assert(report.status == "PASS", "P6 suite failed")
