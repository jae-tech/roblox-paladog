--!strict
local Runner = require("./Runner")
local suite = require("./unit/R8")
local report = Runner.run("PureLuau", "cli-r8", 12345, function(check)
	suite({
		PlazaBoard = require("../src/server/World/PlazaBoard"),
		Schema = require("../src/server/Services/ProfileSchema"),
	}, check)
end, "T-R8")
print(Runner.toJson(report))
assert(report.status == "PASS", "R8 suite failed")
