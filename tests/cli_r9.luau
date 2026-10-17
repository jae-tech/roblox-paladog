--!strict
local Runner = require("./Runner")
local suite = require("./unit/R9")
local report = Runner.run("PureLuau", "cli-r9", 12345, function(check)
	suite({
		Store = require("../src/server/Services/Store"),
		Schema = require("../src/server/Services/ProfileSchema"),
		Protocol = require("../src/shared/Protocol"),
		Battle = require("../src/server/Battle/Battle"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		RemoteGateway = require("../src/server/Net/RemoteGateway"),
		SessionStore = require("../src/server/Services/SessionStore"),
	}, check)
end, "T-R9")
print(Runner.toJson(report))
assert(report.status == "PASS", "R9 suite failed")
