--!strict
local Runner = require("./Runner")
local suite = require("./unit/R4")
local report = Runner.run("PureLuau", "cli-r4", 12345, function(check)
	suite({
		Protocol = require("../src/shared/Protocol"),
		ClientController = require("../src/client/Net/ClientController"),
		SnapshotBuffer = require("../src/client/Net/SnapshotBuffer"),
		ActionRouter = require("../src/client/Input/ActionRouter"),
		Text = require("../src/client/Presentation/Text"),
		HudLayout = require("../src/client/Presentation/HudLayout"),
		AutoAssist = require("../src/client/Input/AutoAssist"),
		PlazaState = require("../src/client/Presentation/PlazaState"),
		catalog = require("../src/shared/RemakeCatalog"),
	}, check)
end, "T-R4")
print(Runner.toJson(report))
assert(report.status == "PASS", "R4 suite failed")
