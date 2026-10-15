--!strict
return function(env: any, check: any)
	local store, schema = env.SessionStore.new(), env.Schema
	local first = store.loadAndLock(
		1,
		{ sessionId = "a", jobId = "job" },
		0,
		schema.newProfile,
		schema.validate
	)
	local lease = { sessionId = "a", jobId = "job", fenceEpoch = first.profile.fenceEpoch }
	first.profile.gold = 999 -- returned data must not mutate the record
	local read = store.update(1, lease, 1000000, function(p: any)
		return p
	end)
	check("memory-copy-isolation", 0, read.profile.gold, 0)
	check("memory-no-distributed-lease-expiry", "ok", read.kind, 0)
	local invalid = store.update(1, lease, 0, function(p: any)
		p.gold = -1
		return p
	end)
	check("memory-invalid-document-rejected", "error", invalid.kind, 0)
	check("memory-release", true, store.release(1, lease), 0)
	local second = store.loadAndLock(
		1,
		{ sessionId = "a", jobId = "job" },
		0,
		schema.newProfile,
		schema.validate
	)
	check("memory-fence-increases", 2, second.profile.fenceEpoch, 0)
	check("memory-stale-release", false, store.release(1, lease), 0)
	check(
		"memory-stale-write",
		"stale",
		store.update(1, lease, 0, function(p: any)
			return p
		end).kind,
		0
	)
	check("memory-invalid-write-not-committed", 0, second.profile.gold, 0)

	local tick, serial = 0, 0
	local clients: { [number]: any } = {}
	local sent: { any } = {}
	local profiles = env.ProfileService.new({
		store = env.SessionStore.new(),
		clock = function()
			return tick / 20
		end,
		spawn = function(fn: () -> ())
			fn()
		end,
		sessionId = "mvp",
		jobId = "cli",
		receiptCap = 64,
		queueCap = 16,
		log = function(_s: string) end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return tick
		end,
		newMatchId = function()
			serial += 1
			return "match-" .. serial
		end,
		balanceHash = env.Catalog.balanceHash,
		maxMatches = 4,
		ackCacheSize = 128,
		moveTtlTicks = 10,
		playableMvp = true,
		send = function(userId: number, message: any)
			table.insert(sent, message)
			if clients[userId] then
				clients[userId].receiveMessage(message, tick / 20)
			end
		end,
	})
	local core = env.RemoteGateway.newCore({
		protocol = env.Protocol,
		publicCatalog = env.Catalog,
		profiles = profiles,
		match = match,
		clock = function()
			return tick / 20
		end,
		tick = function()
			return tick
		end,
		balanceHash = env.Catalog.balanceHash,
		send = function(userId: number, channel: string, payload: any)
			if clients[userId] and channel == "MatchSnapshot" then
				clients[userId].receiveSnapshot(payload, tick / 20)
			end
		end,
	})
	for userId = 1, 2 do
		core.playerAdded(userId)
	end
	local lastCommand: any = nil
	clients[1] = env.ClientController.new({
		protocol = env.Protocol,
		catalog = env.Catalog,
		playableMvp = true,
		requestId = function()
			serial += 1
			return string.format("request-%016d", serial)
		end,
		send = function(channel: string, payload: any)
			if channel == "ClientCommand" then
				lastCommand = payload
				core.clientCommand(1, payload)
			else
				core.moveIntent(1, payload)
			end
		end,
	})
	local client = clients[1]
	client.finishBootstrap(
		client.beginBootstrap(0),
		core.getBootstrap(1, { protocolVersion = 1 }),
		0
	)
	check("boot-lobby", "LobbyReady", client.model(0).phase, 0)
	check("client-one-stage", false, client.action("Start_s02", 0), 0)
	check("client-start", true, client.action("Start_s01", 0), 0)
	core.drain()
	check("server-running", "Running", match.phaseOf(1), 0)
	local world = match.worldOf(1)
	check("start-profile-before-world", true, profiles.profileOf(1).activeRun ~= nil, 0)
	check("other-owner-no-snapshot", nil, match.snapshot(2), 0)
	core.publishSnapshots()
	check("client-running", "Running", client.model(0).phase, 0)
	for _, kind in { "Cast", "UpgradeUnit", "AllocatePoint" } do
		match.handleCommand(1, { kind = kind, requestId = kind })
		check("server-mvp-reject-" .. kind, "WrongPhase", sent[#sent].reason, 0)
	end
	match.handleCommand(1, { kind = "Summon", slot = 2, requestId = "slot2" })
	check("server-one-unit", "WrongPhase", sent[#sent].reason, 0)
	match.handleCommand(2, { kind = "StartStage", stageId = "s02", requestId = "locked" })
	check("server-one-stage", "LockedStage", sent[#sent].reason, 0)
	check("client-one-unit", false, client.action("Summon2", 0), 0)
	check("client-no-skill", false, client.action("Cast", 0), 0)
	check("early-return-rejected", false, client.action("ReturnToLobby", 0), 0)
	match.handleCommand(2, {
		kind = "Summon",
		slot = 1,
		matchId = match.snapshot(1).matchId,
		requestId = "foreign",
		commandSeq = 1,
	})
	check("foreign-command-no-effect", 0, #match.takePending(1), 0)
	check(
		"foreign-move-rejected",
		false,
		match.handleMove(2, { matchId = match.snapshot(1).matchId, seq = 1, axis = 1 }),
		0
	)
	client.move(1, 0)
	core.drain()
	tick += 1
	match.stepAll()
	core.publishSnapshots()
	check("server-authoritative-move", true, world.entities[world.heroId].x > 10, tick)
	check("food-production", 100, world.resources.foodMilli, tick)
	check("first-enemy-spawn", 1, env.World.aliveCount(world, "Enemy"), tick)
	client.move(0, tick / 20)
	core.drain()
	local duplicateChecked = false
	while match.phaseOf(1) == "Running" and tick < 12000 do
		tick += 1
		local duplicateAt = false
		if tick % 100 == 1 then
			client.action("Summon1", (tick - 1) / 20)
			core.drain()
			if not duplicateChecked then
				core.clientCommand(1, lastCommand)
				core.drain()
				duplicateAt = true
				duplicateChecked = true
			end
		end
		match.stepAll()
		if duplicateAt then
			check("duplicate-spawn-once", 1, env.World.aliveCount(world, "Ally"), tick)
			check("duplicate-charge-once", 100, world.resources.foodMilli, tick)
		end
		core.publishSnapshots()
	end
	check("natural-melee-victory", "Victory", world.outcome, tick)
	check("finite-encounter-completed", 0, world.spawnsRemaining, tick)
	check("melee-enemy-kills", 3, world.killCounts.scrapper or 0, tick)
	check("result-delivered", "Victory", client.model(tick / 20).outcome, tick)
	check("result-settled", "Settled", client.model(tick / 20).phase, tick)
	local profile = profiles.profileOf(1)
	check("run-closed", nil, profile.activeRun, tick)
	check("no-permanent-reward", 0, profile.gold + profile.totalXp, tick)
	local endTick, food, revision = world.tick, world.resources.foodMilli, profile.revision
	for _ = 1, 20 do
		match.stepAll()
	end
	check("terminal-tick-frozen", endTick, world.tick, tick)
	check("terminal-food-frozen", food, world.resources.foodMilli, tick)
	check("result-closed-once", revision, profiles.profileOf(1).revision, tick)
	check("return-action", true, client.action("ReturnToLobby", tick / 20), tick)
	core.drain()
	check("return-lobby", "LobbyReady", client.model(tick / 20).phase, tick)
	check("return-clears-result", nil, client.model(tick / 20).outcome, tick)
	client.action("Start_s01", tick / 20)
	core.drain()
	check("restart-running", "Running", match.phaseOf(1), tick)
	check("restart-fresh-food", 0, match.worldOf(1).resources.foodMilli, tick)
	check("restart-ordinal", 2, profiles.profileOf(1).activeRun.ordinal, tick)
	local staleResult: string? = nil
	profiles.finishRun(
		1,
		profile.lastRunResult.matchId,
		"Victory",
		function(_p: any, reason: string?)
			staleResult = reason
		end
	)
	check("old-result-cannot-close-restart", "WrongPhase", staleResult, tick)
	check("new-run-still-open", 2, profiles.profileOf(1).activeRun.ordinal, tick)

	local idle = env.World.new({ stageId = "s01", spawnEncounter = true })
	while not idle.outcome and idle.tick < 12000 do
		env.World.step(idle)
	end
	check("natural-idle-defeat", "Defeat", idle.outcome, idle.tick)
	local capped = env.World.new({ stageId = "s01", spawnEncounter = true })
	capped.limits.enemyCap = 0
	for _ = 1, 5 do
		env.World.step(capped)
	end
	check("cap-no-spawn-loss", 3, capped.spawnsRemaining, capped.tick)
	capped.limits.enemyCap = 1
	env.World.step(capped)
	check("cap-resumes-single-spawn", 2, capped.spawnsRemaining, capped.tick)
	local replay = env.World.new({ stageId = "s01", spawnEncounter = true })
	local replay2 = env.World.new({ stageId = "s01", spawnEncounter = true })
	for _ = 1, 400 do
		env.World.step(replay)
		env.World.step(replay2)
	end
	check("encounter-deterministic", env.World.digest(replay), env.World.digest(replay2), 400)
end
