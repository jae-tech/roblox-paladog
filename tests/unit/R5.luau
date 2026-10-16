--!strict
-- Shadow campaign regression suite. Expected constants come from E02/E03/E04, not the implementation.
return function(env: any, check: any)
	local Battle, Rules, Db = env.Battle, env.Rules, env.Db
	local function loadout(over: any?): any
		local l: any = {
			heroKind = "shadow",
			level = 1,
			exp = 0,
			skills = {},
			equip = { [1] = { num = 1, grade = 0 } },
			difficulty = 1,
			unitLevels = { 1, 1, 1, 1, 1, 1, 1, 1, 1 },
		}
		for k, v in over or {} do
			l[k] = v
		end
		return l
	end
	local function battle(stage: number?, over: any?): any
		local b = Battle.new({ stage = stage or 1, seed = 4242, loadout = loadout(over) })
		if not b.jump then
			b.spawn.need = math.huge
			b.stats.critPercent, b.stats.evadePercent = -1, -1
			b.stats.maxFood = 1000 -- fixture capacity for testing expensive totems without farming
		end
		return b
	end
	local function run(b: any, n: number, input: any?)
		for _ = 1, n do
			Battle.step(b, input)
		end
	end
	local function command(b: any, kind: string, fields: any?): any
		local c = table.clone(fields or {})
		c.kind, c.requestId = kind, "r5-command"
		return Battle.step(b, { commands = { c } }).results[1]
	end
	local function first(b: any, kind: string, n: number?): any
		for _, id in b.order do
			local e = b.entities[id]
			if e.kind == kind and (not n or e.n == n) then
				return e
			end
		end
		return nil
	end
	local function enemy(b: any, x: number): any
		local e = Battle.spawnEnemy(b, 1, 0, x)
		e.hp, e.maxHp, e.speed, e.ap = 1e8, 1e8, 0, 0
		return e
	end
	local function round(n: number): number
		return math.floor(n * 1e6 + 0.5) / 1e6
	end

	-- Formula and gear matrix (E03 §1.6/1.8/2.6/4.3).
	do
		local s = Rules.heroStats(loadout())
		local baseExpected: { [string]: number } = {
			maxHp = 3000,
			maxMana = 200,
			maxFood = 40,
			moveSpeed = 80,
			hpRegen5 = 240,
			manaPerTenth = 0.7,
			foodPerTenth = 0.15,
			auraRadius = 110,
			critPercent = 5,
			critMul = 5,
			evadePercent = 0,
			auraHinder = 0.95,
			thornDamage = 10,
		}
		for key, value in baseExpected do
			check("stats-base-" .. key, value, s[key], 0)
		end
		local skills = table.create(24, 1)
		local trained = Rules.heroStats(loadout({ skills = skills }))
		local trainedExpected: { [string]: number } = {
			maxHp = 4500,
			maxMana = 250,
			maxFood = 80,
			moveSpeed = 100,
			hpRegen5 = 340,
			manaPerTenth = 0.82,
			foodPerTenth = 0.2,
			auraRadius = 143,
			critPercent = 6,
			critMul = 7,
			evadePercent = 10,
			auraHinder = 0.86,
			auraCorrode = 1.3,
			auraWeaken = 0.92,
			thornDamage = 25,
		}
		for key, value in trainedExpected do
			check("stats-trained-" .. key, value, round(trained[key]), 0)
		end
		local gear = Rules.heroStats(loadout({
			skills = skills,
			equip = {
				[4] = { num = 4, grade = 2 },
				[7] = { num = 5, grade = 2 },
				[8] = { num = 5, grade = 2 },
				[9] = { num = 5, grade = 2 },
			},
		}))
		check("gear-amulet-mastery", 6375, gear.maxHp, 0)
		check("gear-crit-helmet", 7, gear.critPercent, 0)
		check("gear-evade-armor", 15.8, gear.evadePercent, 0)
		check("gear-crit-foot", 2, gear.critFootMul, 0)
		local l = loadout({ skills = skills, equip = { [1] = { num = 2, grade = 20 } } })
		check("sword-effective-grade", 21, Rules.swordGrade(l, 1), 0)
		check("sword-dexterity-cost", 36, Rules.swordCost(l, 2, 21), 0)
		check("sword-gold-cost", 1000, Rules.swordCost(l, 11, 0), 0)
	end

	-- 120 campaign entries select the correct mode and shadow replacement rows.
	for s = 1, 120 do
		local b = battle(s)
		local mode = ({ [0] = "Boss", [3] = "Jump", [6] = "Horse", [9] = "Dungeon" })[s % 12]
			or "Normal"
		check("mode-" .. s, mode, b.mode, 0)
		check("snapshot-mode-" .. s, mode, Battle.snapshot(b).mode, 0)
	end
	for _, row in Db.darkReplaced do
		check("replacement-" .. row.stage, row.castleHp, battle(row.stage).stage.castleHp, 0)
	end

	-- Totems, three food-paid hero skills, cooldown and lifetime.
	for _, n in { 1, 3, 4, 6, 7, 8 } do
		local b = battle()
		b.food = 500
		local accepted = command(b, "Summon", { unit = n })
		local e = first(b, "Totem", n)
		check("totem-accepted-" .. n, "Accepted", accepted.status, b.tick)
		check("totem-exists-" .. n, true, e ~= nil, b.tick)
		check("totem-hp-level-" .. n, Db.totems[n].levels.hp[1], e.maxHp, b.tick)
		check("totem-cooldown-" .. n, "Cooldown", command(b, "Summon", { unit = n }).reason, b.tick)
	end
	do
		local b = battle()
		b.food = 0
		check(
			"totem-insufficient-food",
			"InsufficientFood",
			command(b, "Summon", { unit = 1 }).reason,
			b.tick
		)
		check("totem-no-cost-on-reject", 0, b.rewards.summons[1] or 0, b.tick)
		b.food = 500
		command(b, "Summon", { unit = 6 })
		local bull = first(b, "Totem", 6)
		local hp = bull.hp
		Battle.strike(b, nil, bull, 100, false, false)
		check("bull-half-damage", 50, round(hp - bull.hp), b.tick)
		bull.hp = 0.001
		run(b, 1)
		check("totem-expires", nil, b.entities[bull.id], b.tick)
	end
	do
		local b = battle()
		local e = enemy(b, 160)
		b.food = 500
		command(b, "Summon", { unit = 2 })
		check("shout-knock", "Knock", e.state, b.tick)
		check(
			"shout-wait-from-level",
			math.floor(Db.totems[2].levels.hp[1] / 100 * 30),
			e.knockWaitTicks,
			b.tick
		)
		command(b, "Summon", { unit = 5 })
		check("spike-damage", true, e.hp < e.maxHp, b.tick)
		command(b, "Summon", { unit = 9 })
		check("transform-pose", "Transform", Battle.hero(b).state, b.tick)
		check("transform-pose-no-prediction", 0, Battle.snapshot(b).heroSpeed, b.tick)
		local x = Battle.hero(b).x
		run(b, 10, { axis = 1 })
		check("transform-pose-blocks-move", x, Battle.hero(b).x, b.tick)
		run(b, 30, { axis = 1 })
		check("transform-buff-moves", true, Battle.hero(b).x > x, b.tick)
		check("transform-view-speed", 96, Battle.snapshot(b).heroSpeed, b.tick)
		b.summonPast[9] = 1e6
		check("transform-repeat-busy", "Busy", command(b, "Summon", { unit = 9 }).reason, b.tick)
	end

	-- Enemy aura: correct side/line, weaken/corrode and direct periodic thorns.
	do
		local b = battle()
		for _ = 1, 80 do
			b.food, b.summonPast[1] = 1000, 10000
			command(b, "Summon", { unit = 1 })
		end
		b.food, b.summonPast[1] = 1000, 10000
		check("totem-cap-atomic", "UnitCap", command(b, "Summon", { unit = 1 }).reason, b.tick)
		check("totem-cap-no-cost", 1000, b.food, b.tick)
		check(
			"hero-skill-not-ally-slot",
			"Accepted",
			command(b, "Summon", { unit = 2 }).status,
			b.tick
		)
		local dungeon = battle(9)
		dungeon.mana = 200
		for _ = 1, 256 do
			table.insert(dungeon.traps, { row = 292, x = 112, line = -1 })
		end
		check("trap-cap", "UnitCap", command(dungeon, "Summon", { unit = 1 }).reason, dungeon.tick)
		check("trap-cap-no-cost", 200, dungeon.mana, dungeon.tick)
		check(
			"level5-shadow-candidates",
			"12,10,17",
			table.concat(Battle.candidates(b, 5), ","),
			b.tick
		)
		local retreat = Battle.step(b, {
			commands = {
				{ kind = "Retreat", requestId = "retreat" },
				{ kind = "Summon", unit = 3, requestId = "late" },
			},
		})
		check("terminal-same-batch", "WrongPhase", retreat.results[2].reason, b.tick)
	end

	do
		local b = battle(1, { skills = { [16] = 1, [17] = 1, [18] = 1 } })
		local h = Battle.hero(b)
		local e = enemy(b, h.x + 50)
		local far = enemy(b, h.x + 200)
		Battle.step(b)
		check("aura-enemy-inside", true, e.aura, b.tick)
		check("aura-enemy-outside", false, far.aura, b.tick)
		check("aura-count", 1, b.auraCount, b.tick)
		local hp = h.hp
		Battle.strike(b, e, h, 100, false, false)
		check("aura-weaken", 92, round(hp - h.hp), b.tick)
		local ehp = e.hp
		Battle.strike(b, h, e, 100, false, false)
		check("aura-corrode", 130, round(ehp - e.hp), b.tick)
		ehp = e.hp
		run(b, 29)
		check("aura-thorns-direct", 10, round(ehp - e.hp), b.tick)
		local mana = battle(1, {
			skills = { [20] = 5 },
			equip = {
				[4] = { num = 8, grade = 0 },
				[8] = { num = 1, grade = 0 },
			},
		})
		enemy(mana, 150)
		mana.auraCount = 1
		Battle.step(mana)
		check("vigor-excludes-equipment", 0.796, round(mana.mana * 3), mana.tick)
	end

	-- Every sword can release while moving. Golden sword spends once and poison creates area gas.
	for n = 1, 11 do
		local b = battle(1, { equip = { [1] = { num = n, grade = 0 } } })
		b.mana, b.goldAvailable = 1000, 2000
		local e = enemy(b, 150)
		local x = Battle.hero(b).x
		check("sword-accept-" .. n, "Accepted", command(b, "Mace", { slot = 1 }).status, b.tick)
		check("sword-busy-" .. n, "Busy", command(b, "Mace", { slot = 1 }).reason, b.tick)
		run(b, 20, { axis = 1 })
		check("sword-move-" .. n, true, Battle.hero(b).x > x, b.tick)
		check("sword-effect-" .. n, true, e.hp < e.maxHp or e.poisonLeft > 0 or n == 7, b.tick)
		check("sword-paid-once-" .. n, 1, b.rewards.maceUses[1], b.tick)
		if n == 11 then
			check("gold-sword-fixed-spend", 1000, b.rewards.goldSpent, b.tick)
		end
	end

	-- Dungeon mana traps and auto sword; siege horse win/loss boundary.
	do
		local b = battle(9)
		b.mana, b.food = 200, 0
		for _, pair in { { 1, 20 }, { 4, 50 }, { 8, 100 } } do
			local before = b.mana
			check(
				"trap-accepted-" .. pair[1],
				"Accepted",
				command(b, "Summon", { unit = pair[1] }).status,
				b.tick
			)
			check("trap-mana-" .. pair[1], pair[2], math.floor(before - b.mana + 1), b.tick)
		end
		check("trap-count", 3, #b.traps, b.tick)
		local e = enemy(b, Battle.hero(b).x + 80)
		run(b, 1)
		check("trap-triggered", true, #b.traps < 3, b.tick)
		check("trap-damage", true, e.hp < e.maxHp, b.tick)
		check("dungeon-no-aura", 0, b.auraCount, b.tick)
		check("dungeon-no-prediction", 0, Battle.snapshot(b).heroSpeed, b.tick)
		e.x, e.state = Battle.hero(b).x + 30, "Move"
		local enemyHp = e.hp
		local before = b.mana
		run(b, 30)
		check("dungeon-auto-free", true, b.mana > before, b.tick)
		check("dungeon-auto-used", true, e.hp < enemyHp, b.tick)
	end
	do
		local b = battle(6)
		local horse = first(b, "Horse")
		check("horse-hp", 7000, horse.hp, 0)
		check("horse-attack", 250, horse.ap, 0)
		horse.x = 140
		Battle.step(b)
		check("horse-reaches-left-defeat", "Defeat", b.outcome, b.tick)
		b = battle(6)
		first(b, "Horse").hp = 0
		Battle.step(b)
		check("horse-destroyed-victory", "Victory", b.outcome, b.tick)
	end

	-- Jump: immutable loadout, server movement, swept coins, checkpoint respawn, terminal commands.
	do
		local b = battle(3)
		check("jump-speed", 280, b.speed, 0)
		check("jump-gold-per-coin", 2, b.coinGold, 0)
		local snap = Battle.snapshot(b)
		check("jump-view-valid", true, env.SnapshotBuffer.new("remake-db-1") ~= nil, 0)
		check("jump-visible-objects", true, #snap.objects > 0, 0)
		b.map.spikes = { 70 }
		run(b, 1)
		check("jump-spike-death", 1, b.deaths, b.tick)
		run(b, 30)
		check("jump-respawn", 50, Battle.hero(b).x, b.tick)
		b.map.spikes = {}
		b.map.coins = { 55 }
		run(b, 1)
		check("jump-coin", 1, b.coins, b.tick)
		check("jump-coin-gold", 2, b.rewards.gold, b.tick)
		Battle.hero(b).x = 50
		run(b, 1)
		check("jump-coin-no-duplicate", 2, b.rewards.gold, b.tick)
		check("jump-start", "Accepted", command(b, "Jump").status, b.tick)
		check("jump-no-double", "Busy", command(b, "Jump").reason, b.tick)
		check("jump-wrong-mode", "WrongMode", command(b, "Mace", { slot = 1 }).reason, b.tick)
		Battle.hero(b).x = b.map.finish + 100
		run(b, 1)
		check("jump-victory", "Victory", b.outcome, b.tick)
		local digest, tick = Battle.digest(b), b.tick
		check("jump-terminal-reject", "WrongPhase", command(b, "Jump").reason, b.tick)
		check("jump-terminal-no-time", tick, b.tick, b.tick)
		check("jump-terminal-immutable", digest, Battle.digest(b), b.tick)
	end

	-- New state must participate in determinism, and identical runs remain reproducible.
	for index = 1, 10 do
		local b = battle(3 + (index - 1) * 12)
		for _ = 1, 6000 do
			if b.outcome then
				break
			end
			local jump = false
			for _, spike in b.map.spikes do
				local gap = spike - Battle.hero(b).x
				if gap >= -20 and gap <= 60 then
					jump = true
					break
				end
			end
			Battle.step(b, { commands = if jump and b.air == 0 then { { kind = "Jump" } } else {} })
		end
		check("jump-course-completes-" .. index, "Victory", b.outcome, b.tick)
		check("jump-course-no-death-" .. index, 0, b.deaths, b.tick)
		check("jump-course-all-coins-" .. index, b.stage.unitCount, b.coins, b.tick)
		check("jump-course-gold-" .. index, b.coins * b.stage.s12, b.rewards.gold, b.tick)
	end

	do
		local a, b = battle(), battle()
		a.food, b.food = 500, 500
		command(a, "Summon", { unit = 9 })
		command(b, "Summon", { unit = 9 })
		run(a, 90, { axis = 1 })
		run(b, 90, { axis = 1 })
		check("shadow-deterministic", Battle.digest(a), Battle.digest(b), a.tick)
		b.transformTicks += 1
		check("digest-transform-state", true, Battle.digest(a) ~= Battle.digest(b), a.tick)
		b.transformTicks -= 1
		table.insert(b.traps, { x = 250, row = 293, line = -1 })
		check("digest-traps", true, Battle.digest(a) ~= Battle.digest(b), a.tick)
	end

	-- Critical/evade and transformed attacks are server-only, without relying on lucky RNG seeds.
	do
		local b = battle()
		local h, e = Battle.hero(b), enemy(b, 150)
		b.stats.evadePercent = 100
		Battle.strike(b, e, h, 1000, false, false)
		check("evade-full", 3000, h.hp, 0)
		b.stats.evadePercent, b.stats.critPercent = -1, 100
		b.mana = 200
		command(b, "Mace", { slot = 1 })
		run(b, 5)
		check("critical-x5", 60, round(e.maxHp - e.hp), b.tick)
		local transformed = battle()
		transformed.food = 300
		command(transformed, "Summon", { unit = 9 })
		run(transformed, 29)
		check(
			"transform-full-duration-after-pose",
			900,
			transformed.transformTicks,
			transformed.tick
		)
		local th, te = Battle.hero(transformed), enemy(transformed, 150)
		Battle.strike(transformed, te, th, 100, false, false)
		check("transform-damage-half", 2950, th.hp, transformed.tick)
		transformed.mana = 200
		command(transformed, "Mace", { slot = 1 })
		run(transformed, 5)
		check("transform-sword-x3", 36, round(te.maxHp - te.hp), transformed.tick)
		local wind = battle(1, { equip = { [1] = { num = 2, grade = 0 } } })
		wind.mana = 200
		command(wind, "Mace", { slot = 1 })
		run(wind, 5, { axis = -1 })
		local o = wind.objects[wind.objectOrder[1]]
		check("sword-wind-still-right", 1, o and o.dir, wind.tick)
	end

	do
		local b = battle(1, { equip = { [1] = { num = 4, grade = 0 } } })
		local e1, e2 = enemy(b, 150), enemy(b, 170)
		b.mana = 200
		command(b, "Mace", { slot = 1 })
		run(b, 25)
		check("poison-cloud-neighbor", true, e1.poisonLeft > 0 and e2.poisonLeft > 0, b.tick)
		local hp = e2.hp
		run(b, 30)
		check("poison-clock-not-reset", true, e2.hp < hp, b.tick)
		local a = battle()
		a.food = 200
		command(a, "Summon", { unit = 7 })
		local eagle = first(a, "Totem", 7)
		local attacker = enemy(a, 160)
		attacker.speed = 0
		Battle.hero(a).x = -40
		run(a, 2)
		check("eagle-untargetable", false, attacker.target == eagle.id, a.tick)
		local bull = battle()
		bull.food = 200
		command(bull, "Summon", { unit = 6 })
		local tank = first(bull, "Totem", 6)
		tank.poisonDps, tank.poisonLeft, tank.poisonTicks = 30, 10, 29
		local before = tank.hp
		run(bull, 1)
		check("stationary-totem-poison", true, before - tank.hp >= 30, bull.tick)
		check("stationary-totem-poison-clock", 9, tank.poisonLeft, bull.tick)
	end

	-- Pure client views use the same public catalog but cannot change authority or resources.
	do
		local Text, catalog = env.Text, env.catalog
		check("client-shadow-stage", "Jump", Text.stageMeta(catalog, "shadow", 3).mode, 0)
		check("client-light-stage", "Destiny", Text.stageMeta(catalog, "light", 3).mode, 0)
		check("client-shadow-skill24", true, #Text.skillDescription(catalog, "shadow", 24) > 0, 0)
		check(
			"client-shadow-different-skill",
			true,
			Text.skillDescription(catalog, "shadow", 13)
				~= Text.skillDescription(catalog, "light", 13),
			0
		)
		local slot = { heroKind = "shadow", skills = table.create(24, 0) }
		local view = { mode = "Dungeon", mana = 49, food = 500, summonPast = table.create(9, 3000) }
		local trap = Text.summonView(catalog, slot, view, 4)
		check("client-trap-cost", 50, trap.cost, 0)
		check("client-trap-resource", "마나", trap.resource, 0)
		check("client-trap-not-food", false, trap.ready, 0)
		view.mana = 50
		check("client-trap-exact-mana", true, Text.summonView(catalog, slot, view, 4).ready, 0)
		view.mode = "Normal"
		check(
			"client-totem-name",
			catalog.totems[4].name,
			Text.summonView(catalog, slot, view, 4).name,
			0
		)
		local reward = { gold = 0, item = { category = "sword", num = 1, grade = 0 } }
		check(
			"client-sword-reward-name",
			catalog.swords[1].name,
			Text.questReward(catalog, reward),
			0
		)
		local actions = 0
		local router = env.ActionRouter.new({
			onAxis = function() end,
			onAction = function(action)
				if action == "Jump" then
					actions += 1
				end
			end,
		})
		router.begin("Jump", "space")
		router.begin("Jump", "space")
		check("client-jump-repeat-suppressed", 1, actions, 0)
		router.finish("space")
		router.begin("Jump", "space")
		check("client-jump-release", 2, actions, 0)
		router.setBlocked("modal", true)
		router.activate("Jump")
		check("client-jump-modal-block", 2, actions, 0)
		for _, s in { 1, 3, 6, 9, 12 } do
			local b = battle(s)
			local snap = {
				balanceHash = "remake-db-1",
				matchId = "r5-view",
				snapshotSeq = 1,
				inputAckSeq = 0,
				battle = Battle.snapshot(b),
			}
			local buffer = env.SnapshotBuffer.new("remake-db-1")
			buffer.setMatch(snap.matchId)
			check("client-shadow-snapshot-" .. s, true, buffer.accept(snap, 0), 0)
			check("snapshot-private-attack-" .. s, nil, snap.battle.entities[1].ap, 0)
		end
	end

	-- Shadow result definitions, ownership and fenced persistence are exercised below by real services.
	local Schema = env.Schema
	local store = env.SessionStore.new()
	local sent: { any } = {}
	local profiles = env.ProfileService.new({
		store = store,
		clock = function()
			return 1000
		end,
		spawn = function(fn)
			fn()
		end,
		sessionId = "r5-session",
		jobId = "r5-job",
		receiptCap = 64,
		queueCap = 4,
		log = function() end,
	})
	local matches = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return 0
		end,
		newMatchId = function()
			return "r5-match-0001"
		end,
		balanceHash = "remake-db-1",
		send = function(_, message)
			table.insert(sent, message)
		end,
		maxMatches = 4,
		ackCacheSize = 128,
		moveTtlTicks = 15,
	})
	matches.playerJoined(1)
	profiles.transact(1, {
		kind = "R5Fixture",
		requestId = "r5-fixture-0001",
		expectedRevision = 0,
		mutate = function(p)
			p.darkUnlocked, p.currentSlot, p.slots[1] = true, 1, Schema.newSlot("shadow", 1)
			p.slots[1].stars[1], p.slots[1].stars[2], p.slots[1].stars[3] = 1, 1, 0
			p.slots[1].bestSec[1], p.slots[1].bestSec[2] = 1, 1
			return nil
		end,
	}, function() end)
	local profile = profiles.profileOf(1)
	check("shadow-profile-valid", true, (Schema.validate(profile)), 0)
	matches.handleCommand(1, {
		kind = "StartStage",
		requestId = "r5-start-0001",
		stage = 3,
		expectedRevision = profile.revision,
	})
	check("server-shadow-start", "Running", matches.phaseOf(1), 0)
	local b = matches.battleOf(1)
	if b then
		local move = {
			kind = "Jump",
			requestId = "r5-jump-request-0001",
			matchId = "r5-match-0001",
			commandSeq = 1,
		}
		check("protocol-jump", true, env.Protocol.validateCommand({
			protocolVersion = 2,
			kind = "Jump",
			requestId = move.requestId,
			matchId = move.matchId,
			commandSeq = 1,
		}) ~= nil, 0)
		matches.playerJoined(2)
		local digest = Battle.digest(b)
		matches.handleCommand(2, move)
		check("server-foreign-jump", "NotOwner", sent[#sent].reason, 0)
		check("server-foreign-no-change", digest, Battle.digest(b), 0)
		matches.handleCommand(1, move)
		matches.stepAll()
		check("server-jump-applied", true, b.air > 0, b.tick)
		b.map.spikes = {}
		b.coins = b.stage.s21
		Battle.hero(b).x = b.map.finish + 100
		matches.stepAll()
		check("server-jump-settled", "Settled", matches.phaseOf(1), b.tick)
		local saved = profiles.profileOf(1)
		check("server-jump-stars", 3, saved.slots[1].stars[3], b.tick)
		check("server-next-stage-unlocked", 0, saved.slots[1].stars[4], b.tick)
		check("server-run-closed", nil, saved.activeRun, b.tick)
		local gold, revision = saved.slots[1].gold, saved.revision
		profiles.finishRun(1, matches.resultOf(1), function() end)
		check("server-no-duplicate-reward", gold, profiles.profileOf(1).slots[1].gold, b.tick)
		check("server-no-duplicate-revision", revision, profiles.profileOf(1).revision, b.tick)
		check("server-saved-valid", true, (Schema.validate(profiles.profileOf(1))), b.tick)
		matches.playerLeft(1)
		local restored = env.ProfileService.new({
			store = store,
			clock = function()
				return 1000
			end,
			spawn = function(fn)
				fn()
			end,
			sessionId = "r5-reconnect",
			jobId = "r5-job",
			receiptCap = 64,
			queueCap = 4,
			log = function() end,
		})
		restored.load(1, function() end)
		local reloaded = restored.profileOf(1)
		check("server-restored-gold", gold, reloaded.slots[1].gold, b.tick)
		check("server-restored-stars", 3, reloaded.slots[1].stars[3], b.tick)
		check("server-restored-valid", true, (Schema.validate(reloaded)), b.tick)
		local p = Schema.deepClone(reloaded)
		for stage = 1, 6 do
			p.slots[1].stars[stage], p.slots[1].bestSec[stage] = 1, 1
		end
		p.slots[1].stars[7] = 0
		p.runCounter += 1
		p.activeRun = {
			ordinal = p.runCounter,
			matchId = "r5-item",
			slot = 1,
			stage = 7,
			balanceHash = "remake-db-1",
			startOperationId = "r5-quest-item",
		}
		local itemResult = {
			matchId = "r5-item",
			runOrdinal = p.runCounter,
			slot = 1,
			stage = 7,
			balanceHash = "remake-db-1",
			seed = 1,
			outcome = "Victory",
			elapsedTicks = 100,
			gold = 0,
			goldSpent = 0,
			exp = 0,
			levelUps = 0,
			picks = {},
			drops = 0,
			revives = 0,
			killTotal = 1,
			quests = { true, true, true },
		}
		local awarded = env.Settlement.reduce(p, itemResult)
		check(
			"shadow-quest-weapon-category",
			6,
			awarded and awarded.slots[1].inventory[1] // 100000,
			b.tick
		)
		itemResult.matchId = "foreign-result"
		local invalid, reason = env.Settlement.reduce(p, itemResult)
		check("shadow-result-identity", "WrongPhase", reason, b.tick)
		check("shadow-result-no-mutation", nil, invalid, b.tick)
	end
end
