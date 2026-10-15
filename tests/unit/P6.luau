--!strict
-- P6 contracts. Prepared for CLI + Studio; execution deliberately deferred at the user's request.
return function(env: any, check: any)
	local Stage, World = env.StageSystem, env.World
	for _, id in { "s01", "s02", "s03" } do
		local config = env.Stages[id]
		local state = Stage.new(config, 12345)
		for count = 0, config.blockCount * 2 do
			local slow = count % (config.blockCount * 2) < config.blockCount
			local low = if slow then config.slowMinTicks else config.fastMinTicks
			local high = if slow then config.slowMaxTicks else config.fastMaxTicks
			local delay = state.nextSpawnTicks
			check(id .. "-interval-" .. count, true, delay >= low and delay <= high, count)
			for _ = 1, delay - 1 do
				assert(Stage.step(state, config, false) == nil, "spawned before the interval")
			end
			check(id .. "-spawn-" .. count, true, Stage.step(state, config, false) ~= nil, count)
			check(id .. "-count-" .. count, count + 1, state.successfulSpawnCount, count)
		end
		local remaining, rng = state.nextSpawnTicks, state.rngState
		for _ = 1, 100 do
			assert(Stage.step(state, config, true) == nil, "cap must freeze spawning")
		end
		check(id .. "-cap-freezes-timer", remaining, state.nextSpawnTicks, 100)
		check(id .. "-cap-freezes-rng", rng, state.rngState, 100)
		Stage.step(state, config, false)
		check(id .. "-cap-resumes-not-burst", remaining - 1, state.nextSpawnTicks, 101)
		local weights: { [string]: number } = {}
		for roll = 0, 99 do
			local choice = Stage.chooseEnemy(config, roll)
			weights[choice] = (weights[choice] or 0) + 1
		end
		for _, choice in config.choices do
			check(id .. "-weight-" .. choice.enemyId, choice.weight, weights[choice.enemyId], 0)
		end
	end
	local a = World.new({ stageId = "s02", stageSpawns = true, seed = 12345 })
	local b = World.new({ stageId = "s02", stageSpawns = true, seed = 12345 })
	local c = World.new({ stageId = "s02", stageSpawns = true, seed = 54321 })
	for _ = 1, 600 do
		World.step(a)
		World.step(b)
		World.step(c)
	end
	check("seed-replay", World.digest(a), World.digest(b), 600)
	check("seed-affects-digest", true, World.digest(a) ~= World.digest(c), 600)
	for _, case in { "Defeat", "Victory", "Timeout" } do
		local w = World.new({ stageId = "s01", stageSpawns = true })
		if case == "Defeat" then
			w.entities[w.heroId].hp = 0
			w.entities[w.coreId].hp = 0
		elseif case == "Victory" then
			w.entities[w.coreId].hp = 0
		else
			w.tick = 11999
		end
		World.step(w)
		check("outcome-priority-" .. case, case, w.outcome, w.tick)
		local digest = World.digest(w)
		World.step(w, { commands = { { kind = "Summon", slot = 1 } } })
		check("terminal-frozen-" .. case, digest, World.digest(w), w.tick)
	end

	local store, schema = env.SessionStore.new(), env.Schema
	local loaded = store.loadAndLock(
		9,
		{ sessionId = "a", jobId = "job" },
		0,
		schema.newProfile,
		schema.validate
	)
	local fence = { sessionId = "a", jobId = "job", fenceEpoch = loaded.profile.fenceEpoch }
	loaded.profile.gold = 999
	local saved = store.update(9, fence, 1000000, function(p: any)
		return p
	end)
	check("memory-copy-isolation", 0, saved.profile.gold, 0)
	local invalid = store.update(9, fence, 0, function(p: any)
		p.gold = -1
		return p
	end)
	check("invalid-memory-write-rejected", "error", invalid.kind, 0)
	store.release(9, fence)
	loaded = store.loadAndLock(
		9,
		{ sessionId = "a", jobId = "job" },
		0,
		schema.newProfile,
		schema.validate
	)
	check("memory-fence-monotonic", 2, loaded.profile.fenceEpoch, 0)
	check("stale-release-rejected", false, store.release(9, fence), 0)
	check(
		"stale-write-rejected",
		"stale",
		store.update(9, fence, 0, function(p: any)
			return p
		end).kind,
		0
	)
	check("invalid-memory-write-atomic", 0, loaded.profile.gold, 0)

	local tick, serial = 0, 0
	local scheduled: { () -> () } = {}
	local function flush()
		local count = 0
		while #scheduled > 0 do
			count += 1
			assert(count <= 100, "unbounded profile work")
			local nextJob = table.remove(scheduled, 1) :: () -> ()
			nextJob()
		end
	end
	local profiles = env.ProfileService.new({
		store = env.SessionStore.new(),
		clock = function()
			return tick / 20
		end,
		spawn = function(fn: () -> ())
			table.insert(scheduled, fn)
		end,
		sessionId = "p6",
		jobId = "cli",
		receiptCap = 64,
		queueCap = 4,
		log = function(_s: string) end,
	})
	local messages: { any } = {}
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return tick
		end,
		newMatchId = function()
			serial += 1
			return "match-" .. serial
		end,
		newSeed = function()
			return 12345
		end,
		balanceHash = env.Catalog.balanceHash,
		maxMatches = 4,
		ackCacheSize = 128,
		moveTtlTicks = 10,
		stageFlow = true,
		send = function(_userId: number, message: any)
			table.insert(messages, message)
		end,
	})
	match.playerJoined(1)
	match.playerJoined(2)
	flush()
	local function command(kind: string, stage: string?)
		serial += 1
		match.handleCommand(1, {
			kind = kind,
			stageId = stage,
			expectedRevision = profiles.profileOf(1).revision,
			requestId = string.format("operation-%016d", serial),
			matchId = if match.snapshot(1) then match.snapshot(1).matchId else nil,
		})
	end
	command("StartStage", "s03")
	flush()
	check("skip-stage-rejected", "LockedStage", messages[#messages].reason, tick)
	command("StartStage", "s01")
	check("preparing-before-write", "Preparing", match.phaseOf(1), tick)
	check("no-world-before-write", nil, match.worldOf(1), tick)
	flush()
	check("running-after-commit", "Running", match.phaseOf(1), tick)
	local world = match.worldOf(1)
	for _ = 1, 100 do
		tick += 1
		match.stepAll()
	end
	check("server-food-regen", 10000, world.resources.foodMilli, tick)
	local matchId = match.snapshot(1).matchId
	local summon = {
		kind = "Summon",
		slot = 1,
		matchId = matchId,
		requestId = "summon-operation-0001",
		commandSeq = 1,
	}
	match.handleCommand(1, summon)
	match.handleCommand(1, summon)
	match.handleCommand(2, {
		kind = "Summon",
		slot = 1,
		matchId = matchId,
		requestId = "foreign-operation-01",
		commandSeq = 1,
	})
	check(
		"foreign-move-rejected",
		false,
		match.handleMove(2, { matchId = matchId, seq = 1, axis = 1 }),
		tick
	)
	tick += 1
	match.stepAll()
	check("duplicate-summon-once", 1, World.aliveCount(world, "Ally"), tick)
	check("duplicate-charge-once", 100, world.resources.foodMilli, tick)

	-- Headless outcome fixture, not a claim of normal-input gameplay completion.
	world.pendingKillGold, world.pendingKillXp, world.killCounts.scrapper = 18, 12, 1
	check(
		"leftover-projectile-created",
		true,
		env.ProjectileSystem.launch(world, {
			ownerId = world.heroId,
			projectileId = "pulse_bolt",
			damage = 100,
			releaseTick = world.tick,
			x = 10,
			direction = 1,
		}),
		tick
	)
	world.entities[world.coreId].hp = 0
	tick += 1
	match.stepAll()
	local result = match.resultOf(1)
	check("settling-before-result-write", "Settling", match.phaseOf(1), tick)
	check("snapshot-pending", "Pending", match.snapshot(1).settlementStatus, tick)
	check("result-frozen", true, table.isfrozen(result) and table.isfrozen(result.killCounts), tick)
	check("result-pending-kills", 18, result.pendingKillGold, tick)
	check("result-kill-copy", 1, result.killCounts.scrapper, tick)
	check("result-seed", 12345, result.seed, tick)
	check("leftover-units-cleared", 2, #world.order, tick)
	check("leftover-projectiles-cleared", 0, world.projectileCount + #world.projectileOrder, tick)
	command("ReturnToLobby")
	check("return-locked-until-commit", "WrongPhase", messages[#messages].reason, tick)
	local endDigest = World.digest(world)
	for _ = 1, 20 do
		match.stepAll()
	end
	check("settling-no-combat", endDigest, World.digest(world), tick)
	profiles.finishRun(1, result, function() end) -- duplicate queued write, same operation identity
	flush()
	check("result-committed", "Settled", match.phaseOf(1), tick)
	check("snapshot-committed", "Committed", match.snapshot(1).settlementStatus, tick)
	check("wins-once", 1, profiles.profileOf(1).stageProgress.s01.wins, tick)
	check("result-revision-once", 2, profiles.profileOf(1).revision, tick)
	check("committed-victory-gold", 218, profiles.profileOf(1).gold, tick)
	check("committed-victory-xp", 72, profiles.profileOf(1).totalXp, tick)
	command("ReturnToLobby")
	check("lobby-after-commit", "LobbyReady", match.phaseOf(1), tick)
	check(
		"lobby-summary-refresh",
		1,
		messages[#messages].profileSummary.stageProgress.s01.wins,
		tick
	)
	check("lobby-result-released", nil, match.resultOf(1), tick)
	command("StartStage", "s03")
	flush()
	check("s03-still-locked", "LockedStage", messages[#messages].reason, tick)
	for _, stageId in { "s02", "s03" } do
		command("StartStage", stageId)
		flush()
		check(stageId .. "-unlocked", "Running", match.phaseOf(1), tick)
		world = match.worldOf(1)
		check(stageId .. "-fresh-resources", 0, world.resources.foodMilli, tick)
		world.entities[world.coreId].hp = 0
		tick += 1
		match.stepAll()
		flush()
		check(
			stageId .. "-recorded-win",
			1,
			profiles.profileOf(1).stageProgress[stageId].wins,
			tick
		)
		command("ReturnToLobby")
	end
	command("StartStage", "s01")
	flush()
	local active = profiles.profileOf(1).activeRun.ordinal
	profiles.finishRun(1, result, function() end)
	flush()
	check("old-result-cannot-close-new-run", active, profiles.profileOf(1).activeRun.ordinal, tick)
	world = match.worldOf(1)
	world.entities[world.heroId].hp = 0
	tick += 1
	match.stepAll()
	flush()
	check("defeat-committed", "Defeat", match.resultOf(1).outcome, tick)
	check("defeat-no-extra-unlock", 1, profiles.profileOf(1).stageProgress.s01.wins, tick)
	match.playerLeft(1)
	flush()
	check("leave-drops-world", nil, match.worldOf(1), tick)
	check("leave-drops-result", nil, match.resultOf(1), tick)
end
