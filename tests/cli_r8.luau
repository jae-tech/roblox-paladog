--!strict
local Runner = require("./Runner")
local suite = require("./unit/R8")
local report = Runner.run("PureLuau", "cli-r8", 12345, function(check)
	suite({
		PlazaBoard = require("../src/server/World/PlazaBoard"),
		Schema = require("../src/server/Services/ProfileSchema"),
		ArenaSpace = require("../src/shared/ArenaSpace"),
		GearLook = require("../src/shared/GearLook"),
		FigureLook = require("../src/shared/FigureLook"),
		Protocol = require("../src/shared/Protocol"),
		Battle = require("../src/server/Battle/Battle"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		RemoteGateway = require("../src/server/Net/RemoteGateway"),
		SessionStore = require("../src/server/Services/SessionStore"),
	}, check)
end, "T-R8")
print(Runner.toJson(report))
assert(report.status == "PASS", "R8 suite failed")
