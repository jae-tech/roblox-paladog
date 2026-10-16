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
		suiteId == "T-TOOL"
			or suiteId == "T-TOOL-INTENTIONAL-FAIL"
			or suiteId == "T-P2"
			or suiteId == "T-P3"
			or suiteId == "T-P4"
			or suiteId == "T-P5"
			or suiteId == "T-P6"
			or suiteId == "T-P7"
			or suiteId == "T-P8"
			or suiteId == "T-P9",
		"unsupported P0 suite"
	)
	return Runner.run("StudioServer", HttpService:GenerateGUID(false), seed, function(check)
		if suiteId == "T-P9" then
			local p9: any = p2Env()
			p9.Schema = p9.ProfileSchema
			p9.World = require(GameServer.Simulation.World)
			p9.SessionStore = require(GameServer.Services.SessionStore)
			require(tests.unit.P9)(p9, check)
			return
		end
		if suiteId == "T-P8" then
			local client = game:GetService("StarterPlayer").StarterPlayerScripts.GameClient
			require(tests.unit.P8)({
				Adapter = require(GameServer.Persistence.DataStoreAdapter),
				Policy = require(GameServer.Persistence.PersistencePolicy),
				Validator = require(GameServer.Persistence.ProfileValidator),
				Schema = require(GameServer.Services.ProfileSchema),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				Catalog = require(ReplicatedStorage.Shared.PublicCatalog),
				ClientController = require(client.Net.ClientController),
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				newBackend = require(tests.fixtures.FakeDataStore),
			}, check)
			return
		end
		if suiteId == "T-P7" then
			local client = game:GetService("StarterPlayer").StarterPlayerScripts.GameClient
			require(tests.unit.P7)({
				Growth = require(GameServer.Services.ProgressionService),
				ResultReducer = require(GameServer.Simulation.ResultReducer),
				Schema = require(GameServer.Services.ProfileSchema),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				World = require(GameServer.Simulation.World),
				Config = require(GameServer.Config.Generated.Progression),
				Catalog = require(ReplicatedStorage.Shared.PublicCatalog),
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				ClientController = require(client.Net.ClientController),
				newStore = require(tests.fixtures.InMemoryStoreAdapter),
			}, check)
			return
		end
		if suiteId == "T-P6" then
			require(tests.unit.P6)({
				World = require(GameServer.Simulation.World),
				StageSystem = require(GameServer.Simulation.StageSystem),
				Stages = require(GameServer.Config.Generated.Stages),
				ProjectileSystem = require(GameServer.Simulation.ProjectileSystem),
				SessionStore = require(GameServer.Services.SessionStore),
				Schema = require(GameServer.Services.ProfileSchema),
				ProfileService = require(GameServer.Services.ProfileService),
				MatchService = require(GameServer.Services.MatchService),
				Catalog = require(ReplicatedStorage.Shared.PublicCatalog),
			}, check)
			return
		end
		if suiteId == "T-P5" then
			local client = game:GetService("StarterPlayer").StarterPlayerScripts.GameClient
			require(tests.unit.P5)({
				ActionRouter = require(client.Input.ActionRouter),
				SnapshotBuffer = require(client.Net.SnapshotBuffer),
				ClientController = require(client.Net.ClientController),
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				catalog = require(ReplicatedStorage.Shared.PublicCatalog),
				Layout = require(client.Presentation.Layout),
				CameraMath = require(client.Presentation.CameraMath),
				ViewDefinitions = require(client.Presentation.ViewDefinitions),
			}, check)
			return
		end
		if suiteId == "T-P2" then
			require(tests.unit.P2)(p2Env(), check)
			return
		elseif suiteId == "T-P3" or suiteId == "T-P4" then
			local simulation = GameServer.Simulation
			local env = {
				World = require(simulation.World),
				FixedStep = require(simulation.FixedStep),
				Targeting = require(simulation.Targeting),
				Damage = require(simulation.Damage),
				ProjectileSystem = require(simulation.ProjectileSystem),
				HeroActionSystem = require(simulation.HeroActionSystem),
				Protocol = require(ReplicatedStorage.Shared.Protocol),
				MatchService = require(GameServer.Services.MatchService),
				ProfileService = require(GameServer.Services.ProfileService),
				newStore = require(tests.fixtures.InMemoryStoreAdapter),
			}
			if suiteId == "T-P3" then
				require(tests.unit.P3)(env, check)
			else
				require(tests.unit.P4)(env, check)
			end
			return
		end
		suite(fixtures, check)
		if suiteId == "T-TOOL-INTENTIONAL-FAIL" then
			check("intentional-failure", 1, 2, 0)
		end
	end, suiteId)
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
	local state = { tick = 0 }
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
	local FixedStep = require(GameServer.Simulation.FixedStep)
	local driver = FixedStep.new()
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		FixedStep.advance(driver, dt, function()
			state.tick += 1
			core.drain()
			match.stepAll()
			if state.tick % 2 == 0 then
				core.publishSnapshots() -- 10 Hz full snapshots
			end
		end)
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
