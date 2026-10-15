--!strict
local Runner = require("./Runner")
local suite = require("./unit/Mvp")
local report = Runner.run("PureLuau", "cli-mvp", 12345, function(check)
	suite({
		World = require("../src/server/Simulation/World"),
		SessionStore = require("../src/server/Services/SessionStore"),
		Schema = require("../src/server/Services/ProfileSchema"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		RemoteGateway = require("../src/server/Net/RemoteGateway"),
		ClientController = require("../src/client/Net/ClientController"),
		Protocol = require("../src/shared/Protocol"),
		Catalog = require("../src/shared/PublicCatalog"),
	}, check)
end, "T-MVP")
print(Runner.toJson(report))
assert(report.status == "PASS", "MVP suite failed")
