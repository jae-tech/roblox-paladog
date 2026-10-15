--!strict
local input = require("./P5Input")
local net = require("./P5Net")
local view = require("./P5View")
return function(env: any, check: (string, unknown, unknown, number) -> ())
	input(env, check)
	net(env, check)
	view(env, check)
end
