--!strict
local Runner = require("./Runner")
local suite = require("./unit/P5")
local report = Runner.run("PureLuau", "cli-p5", 12345, function(check)
	suite({
		ActionRouter = require("../src/client/Input/ActionRouter"),
		SnapshotBuffer = require("../src/client/Net/SnapshotBuffer"),
		ClientController = require("../src/client/Net/ClientController"),
		Protocol = require("../src/shared/Protocol"),
		catalog = require("../src/shared/PublicCatalog"),
		Layout = require("../src/client/Presentation/Layout"),
		CameraMath = require("../src/client/Presentation/CameraMath"),
		ViewDefinitions = require("../src/client/Presentation/ViewDefinitions"),
	}, check)
end, "T-P5")
print(Runner.toJson(report))
assert(report.status == "PASS", "P5 suite failed")
