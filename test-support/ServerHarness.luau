--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local policy = require(script.Parent.TestPolicy)
local isAllowed = require(script.Parent.Guard)

local function guard()
	assert(
		isAllowed(
			RunService:IsStudio(),
			ReplicatedStorage:GetAttribute("P0TestBuild") == true,
			game.GameId,
			policy.allowedUniverseIds
		),
		"test harness requires Studio, test build marker, and approved universe"
	)
end

guard()
ReplicatedStorage:SetAttribute("P0AuthorizedTestUniverse", game.GameId)
local tests = script.Parent.Tests
local Runner = require(tests.Runner)
local suite = require(tests.unit.P0)
local fixtures = {
	clock = require(tests.fixtures.FakeClock),
	rng = require(tests.fixtures.FakeRng),
	store = require(tests.fixtures.InMemoryProfileStore),
}
local Harness = {}
function Harness.runSuite(suiteId: string, seed: number)
	guard()
	assert(suiteId == "T-TOOL" or suiteId == "T-TOOL-INTENTIONAL-FAIL", "unsupported P0 suite")
	return Runner.run(
		"StudioServer",
		game:GetService("HttpService"):GenerateGUID(false),
		seed,
		function(check)
			suite(fixtures, check)
			if suiteId == "T-TOOL-INTENTIONAL-FAIL" then
				check("intentional-failure", 1, 2, 0)
			end
		end
	)
end
return Harness
