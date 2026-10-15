--!strict
local Runner = require("./Runner")
local suite = require("./unit/P5Net")
local report = Runner.run("PureLuau", "cli-p5-net", 12345, function(check)
	suite({
		SnapshotBuffer = require("../src/client/Net/SnapshotBuffer"),
		ClientController = require("../src/client/Net/ClientController"),
		Protocol = require("../src/shared/Protocol"),
		catalog = require("../src/shared/PublicCatalog"),
	}, check)
end, "T-P5-NET")
print(Runner.toJson(report))
assert(report.status == "PASS", "P5 network suite failed")
