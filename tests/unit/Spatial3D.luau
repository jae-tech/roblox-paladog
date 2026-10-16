--!strict
return function(env: any, check: any)
	local B = env.Battle
	local function battle(extra: any?): any
		local options: any = {
			stage = 1,
			seed = 777,
			spatial = true,
			loadout = {
				heroKind = "light",
				level = 1,
				exp = 0,
				skills = {},
				equip = { [1] = { num = 1, grade = 0 } },
				difficulty = 1,
				unitLevels = { 1, 1, 1, 1, 1, 1, 1, 1, 1 },
			},
		}
		for k, v in extra or {} do
			options[k] = v
		end
		local b = B.new(options)
		b.spawn.need = math.huge
		return b
	end
	local function run(b: any, ticks: number, input: any?)
		for _ = 1, ticks do
			B.step(b, input)
		end
	end
	local function cmd(b: any, kind: string, fields: any?): any
		local c = table.clone(fields or {})
		c.kind, c.requestId = kind, "spatial-command"
		return B.step(b, { commands = { c } }).results[1]
	end
	local function round(n: number): number
		return math.floor(n * 1000 + 0.5) / 1000
	end
	local b = battle()
	check("3d-server-option", true, b.spatial == true, 0)
	local h = B.hero(b)
	check("3d-hero-z", 0, h.z, 0)
	run(b, 30, { strafe = 1 })
	check("3d-strafe-speed", 60, round(h.z or 0), b.tick)
	check("3d-strafe-no-forward", 100, h.x, b.tick)
	run(b, 100, { strafe = 1 })
	check("3d-corridor-clamp", 90, h.z, b.tick)
	local diagonal = battle()
	run(diagonal, 30, { axis = 1, strafe = 1 })
	check(
		"3d-diagonal-normalized",
		60,
		round(math.sqrt((B.hero(diagonal).x - 100) ^ 2 + (B.hero(diagonal).z or 0) ^ 2)),
		diagonal.tick
	)
	b = battle()
	h = B.hero(b)
	h.x, h.z = 400, 50
	b.food = 40
	check("3d-summon-accepted", "Accepted", cmd(b, "Summon", { unit = 1 }).status, b.tick)
	local ally: any = nil
	for _, id in b.order do
		if b.entities[id].kind == "Unit" then
			ally = b.entities[id]
		end
	end
	check("3d-summon-near-player", true, ally and math.abs(ally.x - h.x) < 50, b.tick)
	check("3d-food-not-mana", 0, b.rewards.maceUses[1] or 0, b.tick)
	check("3d-summon-cooldown", "Cooldown", cmd(b, "Summon", { unit = 1 }).reason, b.tick)
	b = battle()
	h = B.hero(b)
	b.mana = 100
	check("3d-magic-accepted", "Accepted", cmd(b, "Mace", { slot = 1 }).status, b.tick)
	local x = h.x
	run(b, 8, { axis = 1, strafe = -1 })
	check("3d-cast-while-moving", true, h.x > x and (h.z or 0) < 0, b.tick)
	check("3d-magic-not-food", 0, b.rewards.summons[1] or 0, b.tick)
	local snap = B.snapshot(b)
	check("3d-snapshot-spatial", true, snap.spatial == true, b.tick)
	check("3d-snapshot-private-ap", nil, snap.entities[1].ap, b.tick)
	local p = env.Protocol
	local valid = p.validateMove({
		protocolVersion = p.VERSION,
		matchId = "3d",
		seq = 1,
		axis = 1,
		strafe = -1,
	})
	check("3d-protocol-strafe", true, valid ~= nil, 0)
	for _, v in { 0 / 0, math.huge, 0.5, 2 } do
		check(
			"3d-invalid-strafe-" .. tostring(v),
			nil,
			p.validateMove({
				protocolVersion = p.VERSION,
				matchId = "3d",
				seq = 1,
				axis = 1,
				strafe = v,
			}),
			0
		)
	end
	local axis, strafe = 0, 0
	local router = env.ActionRouter.new({
		onAxis = function(a)
			axis = a
		end,
		onStrafe = function(a)
			strafe = a
		end,
		onAction = function() end,
	})
	router.begin("Right", "w")
	router.begin("StrafeLeft", "a")
	check("3d-input-forward", 1, axis, 0)
	check("3d-input-strafe", -1, strafe, 0)
	router.setBlocked("focus", true)
	check("3d-focus-forward-zero", 0, axis, 0)
	check("3d-focus-strafe-zero", 0, strafe, 0)
	local a, c = battle(), battle()
	run(a, 90, { axis = 1, strafe = 1 })
	run(c, 90, { axis = 1, strafe = 1 })
	check("3d-deterministic", B.digest(a), B.digest(c), a.tick)
	B.hero(c).z = (B.hero(c).z or 0) + 1
	check("3d-digest-covers-z", true, B.digest(a) ~= B.digest(c), a.tick)
	-- Opposite sides of the corridor cannot hit in melee; AI must close the ground-plane gap.
	b = battle()
	local u = B.spawnUnit(b, 1)
	local enemy = B.spawnEnemy(b, 1, 0, 230, false, 0)
	u.x, u.z, u.hold = 220, -90, true
	enemy.x, enemy.z, enemy.hold = 230, 90, true
	local hp = enemy.hp
	run(b, 45)
	check("3d-melee-no-cross-corridor-hit", hp, enemy.hp, b.tick)
	u.hold = false
	run(b, 10)
	check("3d-mercenary-chases-depth", true, u.z > -90, b.tick)
	enemy.z = u.z
	run(b, 50)
	check("3d-mercenary-auto-attacks", true, enemy.hp < hp, b.tick)
	-- Ranged magic aims in X/Z and can hit a target across the corridor.
	b = battle()
	h = B.hero(b)
	h.z = -80
	enemy = B.spawnEnemy(b, 1, 0, 220, false, 0)
	enemy.z, enemy.state, enemy.stateLimit = 80, "Wait", 10000
	hp = enemy.hp
	b.mana = 100
	cmd(b, "Mace", { slot = 1 })
	run(b, 8)
	local shot = b.objects[b.objectOrder[1]]
	check("3d-magic-depth-aim", true, shot ~= nil and shot.aimZ > 0, b.tick)
	run(b, 50)
	check("3d-magic-depth-hit", true, enemy.hp < hp, b.tick)
	-- Full snapshots reject non-finite depth and interpolate without mutating server data.
	local buffer = env.SnapshotBuffer.new("3d")
	buffer.setMatch("depth")
	local function packet(seq: number): any
		return {
			balanceHash = "3d",
			matchId = "depth",
			snapshotSeq = seq,
			inputAckSeq = 0,
			phase = "Running",
			battle = B.snapshot(b),
		}
	end
	local first = packet(1)
	first.battle.tick, first.battle.entities[1].z = 0, 0
	check("3d-buffer-accept", true, buffer.accept(first, 0), 0)
	local second = packet(2)
	second.battle.tick, second.battle.entities[1].z = 3, 60
	buffer.accept(second, 0.1)
	check("3d-buffer-interpolate-z", 30, round(buffer.frame(0.15).entities[1].z), 0)
	check("3d-buffer-no-mutation", 60, second.battle.entities[1].z, 0)
	local invalid = packet(3)
	invalid.battle.entities[1].z = math.huge
	check("3d-buffer-reject-infinite-z", false, buffer.accept(invalid, 0.2), 0)
	local sent: any = nil
	local controller = env.ClientController.new({
		protocol = p,
		send = function(_, payload)
			sent = payload
		end,
		requestId = function()
			return "3d-client"
		end,
	})
	first.balanceHash = p.BALANCE_HASH
	controller.finishBootstrap(controller.beginBootstrap(0), {
		protocolVersion = p.VERSION,
		balanceHash = p.BALANCE_HASH,
		status = "Ready",
		phase = "Running",
		currentMatch = first,
	}, 0)
	check("3d-client-depth-intent", true, controller.move(1, 0.01, 1), 0)
	check("3d-client-depth-wire", 1, sent.strafe, 0)
	check("3d-client-depth-wire-valid", true, p.validateMove(sent) ~= nil, 0)
	local predicted = controller.frame(0.1).entities[1]
	check("3d-client-depth-prediction", true, predicted.z > 0, 0)
	check(
		"3d-client-diagonal-prediction",
		round(predicted.x - first.battle.entities[1].x),
		round(predicted.z),
		0
	)
	controller.step(1)
	check("3d-client-stale-depth-zero", 0, controller.inspect().strafe, 0)
	check("3d-client-stale-depth-blocked", false, controller.move(0, 1, 1), 0)
	check("3d-client-stale-stop-allowed", true, controller.move(0, 1, 0), 0)
	controller.destroy()
	-- Real MatchService/ProfileService boundaries, memory store only: authority, TTL, settlement replay.
	local tick = 0
	local profiles = env.ProfileService.new({
		store = env.SessionStore.new(),
		clock = function()
			return 1000
		end,
		spawn = function(fn)
			fn()
		end,
		sessionId = "3d",
		jobId = "3d",
		receiptCap = 128,
		queueCap = 32,
		log = function() end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return tick
		end,
		newMatchId = function()
			return "3d-owned"
		end,
		balanceHash = "3d",
		send = function() end,
		spatial = true,
		maxMatches = 8,
		ackCacheSize = 128,
		moveTtlTicks = 15,
	})
	match.playerJoined(1)
	match.playerJoined(2)
	match.handleCommand(1, {
		kind = "CreateSlot",
		slot = 1,
		heroKind = "light",
		difficulty = 1,
		requestId = "3d-create",
		expectedRevision = profiles.profileOf(1).revision,
	})
	match.handleCommand(1, {
		kind = "StartStage",
		stage = 1,
		requestId = "3d-start",
		expectedRevision = profiles.profileOf(1).revision,
	})
	local live = match.battleOf(1)
	check("3d-service-spatial-enabled", true, live.spatial, tick)
	live.spawn.need = math.huge
	check(
		"3d-service-owner-move",
		true,
		match.handleMove(1, { matchId = "3d-owned", seq = 1, axis = 1, strafe = 1 }),
		tick
	)
	check(
		"3d-service-foreign-move",
		false,
		match.handleMove(2, { matchId = "3d-owned", seq = 1, axis = 1, strafe = -1 }),
		tick
	)
	check(
		"3d-service-replay-move",
		false,
		match.handleMove(1, { matchId = "3d-owned", seq = 1, axis = 0, strafe = -1 }),
		tick
	)
	match.stepAll()
	check("3d-service-server-z", true, B.hero(live).z > 0, tick)
	tick = 16
	check("3d-service-depth-ttl", 0, match.effectiveStrafe(1), tick)
	check("3d-service-forward-ttl", 0, match.effectiveAxis(1), tick)
	live.food = 40
	local command =
		{ kind = "Summon", unit = 1, matchId = "3d-owned", commandSeq = 1, requestId = "3d-summon" }
	match.handleCommand(1, command)
	match.stepAll()
	local food, summons = live.food, live.rewards.summons[1]
	match.handleCommand(1, command)
	match.stepAll()
	check("3d-service-summon-once", summons, live.rewards.summons[1], tick)
	check("3d-service-cost-once", true, live.food >= food, tick)
	B.castle(live).hp = 0 -- deterministic victory fixture, not a claim of natural completion.
	match.stepAll()
	check("3d-service-settled", "Settled", match.phaseOf(1), tick)
	local profile = profiles.profileOf(1)
	local gold, revision = profile.slots[1].gold, profile.revision
	profiles.finishRun(1, match.resultOf(1), function() end)
	check("3d-service-reward-once", gold, profiles.profileOf(1).slots[1].gold, tick)
	check("3d-service-revision-once", revision, profiles.profileOf(1).revision, tick)
	check("3d-service-run-closed", nil, profiles.profileOf(1).activeRun, tick)
	match.handleCommand(
		1,
		{ kind = "ReturnToLobby", matchId = "3d-owned", requestId = "3d-return" }
	)
	check("3d-service-cleanup", 0, match.ownedMatchCount(), tick)
	profiles.release(1)
	profiles.release(2)
end
