--!strict
-- Stage gameplay. Persistence stays memory-only unless the server policy is explicitly changed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ProfileService = require("./Services/ProfileService")
local SessionStore = require("./Services/SessionStore")
local MatchService = require("./Services/MatchService")
local RemoteGateway = require("./Net/RemoteGateway")
local RemoteBinding = require("./Net/RemoteBinding")
local FixedStep = require("./Simulation/FixedStep")
local PersistencePolicy = require("./Persistence/PersistencePolicy")

local active: any = nil
local function start(): any
	if active then
		return active
	end
	local protocol = require(ReplicatedStorage.Shared.Protocol)
	local catalog = require(ReplicatedStorage.Shared.PublicCatalog)
	local tick = 0
	local stopping = false
	local forward: ((number, string, any) -> ())? = nil
	local function send(userId: number, channel: string, payload: any)
		if forward then
			forward(userId, channel, payload)
		end
	end
	local profiles = ProfileService.new({
		store = if PersistencePolicy.config.enabled
			then require("./Persistence/RobloxStoreBinding").new()
			else SessionStore.new(),
		clock = os.time,
		spawn = function(fn)
			task.spawn(fn)
		end,
		sessionId = HttpService:GenerateGUID(false),
		jobId = game.JobId,
		receiptCap = protocol.LIMITS.receiptCap,
		queueCap = protocol.LIMITS.profileQueueCap,
		log = warn,
	})
	local match = MatchService.new({
		profiles = profiles,
		tick = function()
			return tick
		end,
		newMatchId = function()
			return HttpService:GenerateGUID(false)
		end,
		newSeed = function()
			return math.max(1, tonumber(string.sub(HttpService:GenerateGUID(false), 1, 8), 16) or 1)
		end,
		balanceHash = catalog.balanceHash,
		send = function(userId, message)
			send(userId, "ServerMessage", message)
		end,
		maxMatches = protocol.LIMITS.maxMatches,
		ackCacheSize = protocol.LIMITS.ackCacheSize,
		moveTtlTicks = protocol.LIMITS.moveTtlTicks,
		stageFlow = true,
	})
	local core = RemoteGateway.newCore({
		protocol = protocol,
		publicCatalog = catalog,
		profiles = profiles,
		match = match,
		clock = os.clock,
		tick = function()
			return tick
		end,
		balanceHash = catalog.balanceHash,
		send = send,
	})
	local _, sender = RemoteBinding.bind(core, ReplicatedStorage, Players)
	forward = sender
	local driver = FixedStep.new()
	RunService.Heartbeat:Connect(function(dt)
		if stopping then
			return
		end
		profiles.poll() -- memory check; due lease I/O shares the asynchronous profile writer
		FixedStep.advance(driver, dt, function()
			tick += 1
			core.drain()
			match.stepAll()
			if tick % 2 == 0 then
				core.publishSnapshots()
			end
		end)
	end)
	game:BindToClose(function()
		stopping = true
		for _, player in Players:GetPlayers() do
			core.playerRemoving(player.UserId)
		end
		profiles.shutdown()
		local deadline = os.clock() + 25
		while not profiles.isIdle() and os.clock() < deadline do
			task.wait(0.1)
		end
		if not profiles.isIdle() then
			warn("Profile close deadline reached; unconfirmed data may be lost")
		end
	end)
	active = { match = match, profiles = profiles }
	return active
end

return table.freeze({ start = start })
