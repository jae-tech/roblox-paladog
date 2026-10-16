--!strict
local Runner = require("./Runner")
local suite = require("./unit/P8")
local report = Runner.run("PureLuau", "cli-p8", 12345, function(check)
	suite({
		Adapter = require("../src/server/Persistence/DataStoreAdapter"),
		Policy = require("../src/server/Persistence/PersistencePolicy"),
		Validator = require("../src/server/Persistence/ProfileValidator"),
		Schema = require("../src/server/Services/ProfileSchema"),
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		Economy = require("../src/server/Services/Economy"),
		Db = require("../src/server/Config/Remake/Db"),
		newBackend = require("./fixtures/FakeDataStore"),
	}, check)
end, "T-P8")
print(Runner.toJson(report))
assert(report.status == "PASS", "P8 suite failed")
