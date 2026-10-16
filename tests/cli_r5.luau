--!strict
local Runner = require("./Runner")
local suite = require("./unit/R5")
local report = Runner.run("PureLuau", "cli-r5", 12345, function(check)
	suite({
		Battle = require("../src/server/Battle/Battle"),
		Rules = require("../src/server/Battle/Rules"),
		Db = require("../src/server/Config/Remake/Db"),
		Protocol = require("../src/shared/Protocol"),
		Schema = require("../src/server/Services/ProfileSchema"),
		Quests = require("../src/server/Services/Quests"),
		Settlement = require("../src/server/Services/Settlement"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		SessionStore = require("../src/server/Services/SessionStore"),
		Text = require("../src/client/Presentation/Text"),
		catalog = require("../src/shared/RemakeCatalog"),
		ActionRouter = require("../src/client/Input/ActionRouter"),
		SnapshotBuffer = require("../src/client/Net/SnapshotBuffer"),
	}, check)
end, "T-R5")
print(Runner.toJson(report))
assert(report.status == "PASS", "R5 suite failed")
