--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
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
local GameServer = ServerScriptService.GameServer
local function p2Env()
	return {
		Protocol = require(ReplicatedStorage.Shared.Protocol),
		Catalog = require(ReplicatedStorage.Shared.PublicCatalog),
		RemoteGateway = require(GameServer.Net.RemoteGateway),
		MatchService = require(GameServer.Services.MatchService),
		ProfileService = require(GameServer.Services.ProfileService),
		ProfileSchema = require(GameServer.Services.ProfileSchema),
		newStore = require(tests.fixtures.InMemoryStoreAdapter),
	}
end

local Harness = {}
function Harness.runSuite(suiteId: string, seed: number)
	guard()
	assert(
		suiteId == "T-TOOL" or suiteId == "T-TOOL-INTENTIONAL-FAIL" or suiteId == "T-P2",
		"unsupported P0 suite"
	)
	return Runner.run("StudioServer", HttpService:GenerateGUID(false), seed, function(check)
		if suiteId == "T-P2" then
			require(tests.unit.P2)(p2Env(), check)
			return
		end
		suite(fixtures, check)
		if suiteId == "T-TOOL-INTENTIONAL-FAIL" then
			check("intentional-failure", 1, 2, 0)
		end
	end)
end

-- T-ISOLATION rig: production gateway/services + Mock/InMemory store + real Remotes, test build only.
local rig: { [string]: any }? = nil

function Harness.startNetRig()
	guard()
	if rig then
		return "already running"
	end
	local env = p2Env()
	local Protocol = env.Protocol
	local Progression = require(GameServer.Config.Generated.Progression)
	local RemoteBinding = require(GameServer.Net.RemoteBinding)
	local store = env.newStore()
	local state = { tick = 0, accumulator = 0 }
	local forward: ((number, string, any) -> ())? = nil
	local profiles = env.ProfileService.new({
		store = store,
		clock = os.time,
		spawn = function(fn)
			task.spawn(fn)
		end,
		sessionId = HttpService:GenerateGUID(false),
		jobId = game.JobId,
		receiptCap = Protocol.LIMITS.receiptCap,
		queueCap = Protocol.LIMITS.profileQueueCap,
		log = function(message)
			warn(message)
		end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return state.tick
		end,
		newMatchId = function()
			return HttpService:GenerateGUID(false)
		end,
		balanceHash = Progression.balanceHash,
		send = function(userId, message)
			if forward then
				forward(userId, "ServerMessage", message)
			end
		end,
		maxMatches = Protocol.LIMITS.maxMatches,
		ackCacheSize = Protocol.LIMITS.ackCacheSize,
		moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
	})
	local core = env.RemoteGateway.newCore({
		protocol = Protocol,
		publicCatalog = env.Catalog,
		match = match,
		profiles = profiles,
		clock = os.clock,
		tick = function()
			return state.tick
		end,
		balanceHash = Progression.balanceHash,
		send = function(userId, channel, payload)
			if forward then
				forward(userId, channel, payload)
			end
		end,
	})
	local _, send, disconnect = RemoteBinding.bind(core, ReplicatedStorage, Players)
	forward = send
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		state.accumulator = math.min(state.accumulator + dt, 0.25)
		while state.accumulator >= 0.05 do
			state.accumulator -= 0.05
			state.tick += 1
			core.drain()
			if state.tick % 2 == 0 then
				core.publishSnapshots()
			end
		end
	end)
	rig = {
		core = core,
		match = match,
		profiles = profiles,
		store = store,
		disconnect = disconnect,
		heartbeat = heartbeat,
	}
	return "started"
end

function Harness.netRig()
	guard()
	return rig
end

function Harness.stopNetRig()
	guard()
	if rig then
		rig.heartbeat:Disconnect()
		rig.disconnect()
		rig = nil
	end
end

return Harness
