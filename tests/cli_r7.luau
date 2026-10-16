--!strict
local Runner = require("./Runner")
local suite = require("./unit/R7")
local env: any = {}
local report = Runner.run("PureLuau", "cli-r7", 12345, function(check)
	for key, value in
		{
			Protocol = require("../src/shared/Protocol"),
			Schema = require("../src/server/Services/ProfileSchema"),
			Settlement = require("../src/server/Services/Settlement"),
			Battle = require("../src/server/Battle/Battle"),
			Db = require("../src/server/Config/Remake/Db"),
			ProfileService = require("../src/server/Services/ProfileService"),
			MatchService = require("../src/server/Services/MatchService"),
			RemoteGateway = require("../src/server/Net/RemoteGateway"),
			SessionStore = require("../src/server/Services/SessionStore"),
			Rules = require("../src/server/Battle/Rules"),
		} :: { [string]: any }
	do
		env[key] = value
	end
	suite(env, check)
end, "T-R7")
print(Runner.toJson(report))
local m = env.metrics
if m then
	print(
		string.format(
			"load ticks=%d windows=%d p50=%.2f p95=%.2f p99=%.2f max=%.2f ms objects=%d",
			m.ticks,
			m.windows,
			m.p50,
			m.p95,
			m.p99,
			m.max,
			m.maxObjects
		)
	)
end
assert(report.status == "PASS", "R7 suite failed")
