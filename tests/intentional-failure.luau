--!strict
local Runner = require("./Runner")
local report = Runner.run("PureLuau", "cli-intentional-failure", 12345, function(check)
	check("intentional-failure", 1, 2, 0)
end)
print(Runner.toJson(report))
assert(report.status == "PASS", "intentional failure: expected nonzero process exit")
