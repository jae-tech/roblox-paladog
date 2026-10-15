--!strict
local Runner = require("./Runner")
local suite = require("./unit/P7")
local report = Runner.run("PureLuau", "cli-p7", 12345, function(check)
	suite({
		Growth = require("../src/server/Services/ProgressionService"),
		ResultReducer = require("../src/server/Simulation/ResultReducer"),
		Schema = require("../src/server/Services/ProfileSchema"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		World = require("../src/server/Simulation/World"),
		Config = require("../src/server/Config/Generated/Progression"),
		Catalog = require("../src/shared/PublicCatalog"),
		Protocol = require("../src/shared/Protocol"),
		ClientController = require("../src/client/Net/ClientController"),
		newStore = require("./fixtures/InMemoryStoreAdapter"),
	}, check)
end, "T-P7")
print(Runner.toJson(report))
assert(report.status == "PASS", "P7 suite failed")
