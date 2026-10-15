--!strict
local Runner = require("./Runner")
local suite = require("./unit/P5Input")
local report = Runner.run("PureLuau", "cli-p5-input", 12345, function(check)
	suite({ ActionRouter = require("../src/client/Input/ActionRouter") }, check)
end, "T-P5-INPUT")
print(Runner.toJson(report))
assert(report.status == "PASS", "P5 input suite failed")
