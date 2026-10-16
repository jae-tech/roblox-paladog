--!strict
local Runner = require("./Runner")
local report = Runner.run("PureLuau", "cli-3d", 12345, function(check)
	require("./unit/Spatial3D")({
		ProfileService = require("../src/server/Services/ProfileService"),
		MatchService = require("../src/server/Services/MatchService"),
		SessionStore = require("../src/server/Services/SessionStore"),
		Battle = require("../src/server/Battle/Battle"),
		Protocol = require("../src/shared/Protocol"),
		ActionRouter = require("../src/client/Input/ActionRouter"),
		ClientController = require("../src/client/Net/ClientController"),
		SnapshotBuffer = require("../src/client/Net/SnapshotBuffer"),
	}, check)
end, "T-3D")
print(Runner.toJson(report))
assert(report.status == "PASS", "3D suite failed")
