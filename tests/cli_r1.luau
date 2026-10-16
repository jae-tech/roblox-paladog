--!strict
local Runner = require("./Runner")
local suite = require("./unit/R1")
local report = Runner.run("PureLuau", "cli-r1", 12345, function(check)
	suite({
		Battle = require("../src/server/Battle/Battle"),
		Rules = require("../src/server/Battle/Rules"),
	}, check)
end, "T-R1")
print(Runner.toJson(report))
assert(report.status == "PASS", "R1 suite failed")
