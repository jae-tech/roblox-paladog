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
local Plaza = require("./World/Plaza")
local PlazaBoard = require("./World/PlazaBoard")

local active: any = nil
local function start(): any
	if active then
		return active
	end
	local protocol = require(ReplicatedStorage.Shared.Protocol)
	local catalog = require(ReplicatedStorage.Shared.RemakeCatalog)
	local balanceHash = protocol.BALANCE_HASH
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
		spatial = true,
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
		balanceHash = balanceHash,
		send = function(userId, message)
			send(userId, "ServerMessage", message)
		end,
		maxMatches = protocol.LIMITS.maxMatches,
		ackCacheSize = protocol.LIMITS.ackCacheSize,
		moveTtlTicks = protocol.LIMITS.moveTtlTicks,
	})
	local core = RemoteGateway.newCore({
		protocol = protocol,
		publicCatalog = { version = balanceHash, size = #catalog.stages },
		profiles = profiles,
		match = match,
		clock = os.clock,
		tick = function()
			return tick
		end,
		balanceHash = balanceHash,
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
			if tick % 3 == 0 then -- 10 Hz owner snapshots at the 30 Hz battle tick
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
	-- Plaza (R8): shared square, Roblox leaderstats and the per-server board, refreshed every 2 s.
	local plaza = Plaza.new(workspace)
	local function leaderstats(player: Player): Folder
		local folder = player:FindFirstChild("leaderstats") :: Folder?
		if folder then
			return folder
		end
		local created = Instance.new("Folder")
		created.Name = "leaderstats"
		for _, name in { "스테이지", "서바이벌", "레벨" } do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = created
		end
		created.Parent = player
		return created
	end
	-- Everyone (re)spawns in the plaza, never at a place's own spawn near the client battlefield.
	local function toPlaza(player: Player)
		leaderstats(player)
		player.RespawnLocation = plaza.spawn
		local function place(character: Model)
			local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
			if root and (root.Position - plaza.spawn.Position).Magnitude > 150 then
				character:PivotTo(plaza.spawn.CFrame + Vector3.new(0, 4, 0))
			end
		end
		player.CharacterAdded:Connect(place)
		if player.Character then
			task.spawn(place, player.Character)
		end
	end
	Players.PlayerAdded:Connect(toPlaza)
	for _, player in Players:GetPlayers() do
		toPlaza(player)
	end
	task.spawn(function()
		while not stopping do
			local rows: { PlazaBoard.Row } = {}
			for _, player in Players:GetPlayers() do
				local stats = PlazaBoard.statsOf(profiles.profileOf(player.UserId))
				local folder = leaderstats(player);
				(folder:FindFirstChild("스테이지") :: IntValue).Value = stats.stage;
				(folder:FindFirstChild("서바이벌") :: IntValue).Value = stats.wave;
				(folder:FindFirstChild("레벨") :: IntValue).Value = stats.level
				table.insert(rows, {
					userId = player.UserId,
					name = player.DisplayName,
					level = stats.level,
					stage = stats.stage,
					wave = stats.wave,
				})
				local phase = match.phaseOf(player.UserId)
				plaza.setExpedition(
					player,
					phase == "Running" or phase == "Settling" or phase == "Settled"
				)
			end
			plaza.updateBoard(PlazaBoard.rank(rows))
			task.wait(2)
		end
	end)
	active = { match = match, profiles = profiles, plaza = plaza }
	return active
end

return table.freeze({ start = start })
