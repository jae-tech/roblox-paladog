--!strict
local Runner = require("./Runner")
local suite = require("./unit/R2")
local report = Runner.run("PureLuau", "cli-r2", 12345, function(check)
	suite({
		Battle = require("../src/server/Battle/Battle"),
		Rules = require("../src/server/Battle/Rules"),
	}, check)
end, "T-R2")
print(Runner.toJson(report))
assert(report.status == "PASS", "R2 suite failed")
