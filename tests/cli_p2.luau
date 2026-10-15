--!strict
-- Luau CLI entry for the P2 suite; Studio runs the same suite with Instance-path modules.
local Runner = require("./Runner")
local suite = require("./unit/P2")
local env = {
	Protocol = require("../src/shared/Protocol"),
	Catalog = require("../src/shared/PublicCatalog"),
	RemoteGateway = require("../src/server/Net/RemoteGateway"),
	MatchService = require("../src/server/Services/MatchService"),
	ProfileService = require("../src/server/Services/ProfileService"),
	ProfileSchema = require("../src/server/Services/ProfileSchema"),
	newStore = require("./fixtures/InMemoryStoreAdapter"),
}
local report = Runner.run("PureLuau", "cli-p2", 12345, function(check)
	suite(env, check)
end, "T-P2")
print(Runner.toJson(report))
assert(report.status == "PASS", "P2 suite failed")
