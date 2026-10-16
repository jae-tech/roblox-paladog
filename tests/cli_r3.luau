--!strict
local Runner = require("./Runner")
local suite = require("./unit/R3")
local report = Runner.run("PureLuau", "cli-r3", 12345, function(check)
	suite({
		Protocol = require("../src/shared/Protocol"),
		Schema = require("../src/server/Services/ProfileSchema"),
		Economy = require("../src/server/Services/Economy"),
		Settlement = require("../src/server/Services/Settlement"),
		Battle = require("../src/server/Battle/Battle"),
		Db = require("../src/server/Config/Remake/Db"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		RemoteGateway = require("../src/server/Net/RemoteGateway"),
		SessionStore = require("../src/server/Services/SessionStore"),
	}, check)
end, "T-R3")
print(Runner.toJson(report))
assert(report.status == "PASS", "R3 suite failed")
