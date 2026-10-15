--!strict
local Runner = require("./Runner")
local suite = require("./unit/P5View")
local env = {
	Layout = require("../src/client/Presentation/Layout"),
	CameraMath = require("../src/client/Presentation/CameraMath"),
	ViewDefinitions = require("../src/client/Presentation/ViewDefinitions"),
}
local report = Runner.run("PureLuau", "cli-p5-view", 12345, function(check)
	suite(env, check)
end, "T-P5-VIEW")
print(Runner.toJson(report))
assert(report.status == "PASS", "P5 presentation suite failed")
