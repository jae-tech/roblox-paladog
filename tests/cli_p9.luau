--!strict
local Runner = require("./Runner")
local suite = require("./unit/P9")
local report = Runner.run("PureLuau", "cli-p9", 12345, function(check)
	suite({
		Protocol = require("../src/shared/Protocol"),
		Catalog = require("../src/shared/PublicCatalog"),
		RemoteGateway = require("../src/server/Net/RemoteGateway"),
		MatchService = require("../src/server/Services/MatchService"),
		ProfileService = require("../src/server/Services/ProfileService"),
		Schema = require("../src/server/Services/ProfileSchema"),
		World = require("../src/server/Simulation/World"),
		SessionStore = require("../src/server/Services/SessionStore"), -- the store Runtime ships
	}, check)
end, "T-P9")
print(Runner.toJson(report))
assert(report.status == "PASS", "P9 suite failed")
