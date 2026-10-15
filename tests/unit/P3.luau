--!strict
-- P3 suite: T-RESOURCE-01..04, T-COMBAT-01..06, T-HERO-01, seed replay and fixed tick order.
-- Modules are injected so the same suite runs in the Luau CLI and in Studio.
type Check = (string, unknown, unknown, number) -> ()

local EPS = 1e-6

return function(env: any, check: Check)
	local World = env.World
	local FixedStep = env.FixedStep
	local Targeting = env.Targeting

	local function near(a: number, b: number): boolean
		return math.abs(a - b) <= EPS
	end
	local function newWorld(options: { [string]: any }?)
		local opts: { [string]: any } = options or {}
		return World.new({
			stageId = opts.stageId or "s01",
			unitLevels = opts.unitLevels,
			heroTraits = opts.heroTraits,
			trace = opts.trace,
		})
	end
	local function steps(world: any, count: number, input: any?)
		for _ = 1, count do
			World.step(world, input)
		end
	end
	-- Pin an entity in place (no movement, no own attacks) for isolated combat checks.
	local function dummy(entity: any)
		entity.state = "Idle"
		entity.moveSpeed = 0
		return entity
	end

	-- ---------------------------------------------------------------- T-RESOURCE
	local w = newWorld()
	steps(w, 100)
	check("tres01-food-100-ticks", 10000, w.resources.foodMilli, w.tick)
	check("tres01-mana-100-ticks", 10000, w.resources.manaMilli, w.tick)
	local overFood, overMana = false, false
	for _ = 1, 1100 do
		World.step(w)
		overFood = overFood or w.resources.foodMilli > 40000
		overMana = overMana or w.resources.manaMilli > 100000
	end
	check("tres01-food-cap", 40000, w.resources.foodMilli, w.tick)
	check("tres01-mana-cap", 100000, w.resources.manaMilli, w.tick)
	check("tres01-never-over-cap", false, overFood or overMana, w.tick)
	check("tres01-remainder-reset-at-cap", 0, w.resources.foodRemainder, w.tick)

	local r2 = newWorld()
	r2.resources.foodMilli = 9900 -- +100 regen at the start of the tick -> 10000 when commands run
	local twice = World.step(r2, {
		commands = {
			{ kind = "Summon", slot = 1, requestId = "a", commandSeq = 1 },
			{ kind = "Summon", slot = 1, requestId = "b", commandSeq = 2 },
		},
	})
	check("tres02-first-accepted", "Accepted", twice.results[1].status, r2.tick)
	check("tres02-second-cooldown", "Cooldown", twice.results[2].reason, r2.tick)
	check("tres02-food-zero", 0, r2.resources.foodMilli, r2.tick)
	check("tres02-one-unit", 1, World.aliveCount(r2, "Ally"), r2.tick)
	check("tres02-ready-tick-once", r2.tick + 20, r2.resources.summonReadyTick[1], r2.tick)

	local r3 = newWorld()
	r3.resources.foodMilli = 9899 -- 9999 after regen
	local poor = World.step(
		r3,
		{ commands = { { kind = "Summon", slot = 1, requestId = "p", commandSeq = 1 } } }
	)
	check("tres03-insufficient-food", "InsufficientFood", poor.results[1].reason, r3.tick)
	check("tres03-no-charge", 9999, r3.resources.foodMilli, r3.tick)
	check("tres03-no-cooldown-set", 0, r3.resources.summonReadyTick[1], r3.tick)
	r3.resources.summonReadyTick[1] = r3.tick + 5
	r3.resources.foodMilli = 19900
	local cooling = World.step(
		r3,
		{ commands = { { kind = "Summon", slot = 1, requestId = "c", commandSeq = 2 } } }
	)
	check("tres03-cooldown", "Cooldown", cooling.results[1].reason, r3.tick)
	check("tres03-cooldown-no-charge", 20000, r3.resources.foodMilli, r3.tick)
	check("tres03-cooldown-ready-unchanged", r3.tick + 4, r3.resources.summonReadyTick[1], r3.tick)
	r3.resources.summonReadyTick[1] = 0
	for _ = 1, 30 do
		dummy(World.spawnAlly(r3, "vanguard", 5))
	end
	local before = r3.resources.foodMilli
	local capped = World.step(
		r3,
		{ commands = { { kind = "Summon", slot = 1, requestId = "u", commandSeq = 3 } } }
	)
	check("tres03-unit-cap", "UnitCap", capped.results[1].reason, r3.tick)
	check("tres03-cap-no-charge", before + 100, r3.resources.foodMilli, r3.tick)
	check("tres03-cap-no-unit", 30, World.aliveCount(r3, "Ally"), r3.tick)
	check("tres03-cap-ready-unchanged", 0, r3.resources.summonReadyTick[1], r3.tick)
	local edge = newWorld()
	edge.resources.foodMilli = 9900
	check(
		"tres03-boundary-10000-ok",
		"Accepted",
		World.step(
			edge,
			{ commands = { { kind = "Summon", slot = 1, requestId = "e", commandSeq = 1 } } }
		).results[1].status,
		edge.tick
	)

	local r4 = newWorld({ heroTraits = { provisions = 1, vitality = 0, focus = 0 } })
	steps(r4, 200)
	check("tres04-provisions-rate", 22500, r4.resources.foodMilli, r4.tick)
	check("tres04-no-remainder-leak", 0, r4.resources.foodRemainder, r4.tick)
	check("tres04-mana-unchanged-rate", 20000, r4.resources.manaMilli, r4.tick)

	-- ---------------------------------------------------------------- T-COMBAT-01 targeting
	local t = newWorld()
	local vanguard = dummy(World.spawnAlly(t, "vanguard", 20))
	local behind = dummy(World.spawnEnemy(t, "scrapper", 18))
	local otherLane = dummy(World.spawnEnemy(t, "scrapper", 21))
	otherLane.laneId = 2
	local tieA = dummy(World.spawnEnemy(t, "scrapper", 22))
	local tieB = dummy(World.spawnEnemy(t, "scrapper", 22))
	check(
		"tcombat01-not-behind-or-other-lane",
		tieA.entityId,
		(Targeting.acquire(t, vanguard) or {}).entityId,
		0
	)
	check(
		"tcombat01-ids-distinct",
		true,
		behind.entityId < otherLane.entityId and otherLane.entityId < tieA.entityId,
		0
	)
	check("tcombat01-tie-smaller-id", tieA.entityId, Targeting.acquire(t, vanguard).entityId, 0)
	tieA.hp, tieA.state = 0, "Dead"
	check("tcombat01-dead-excluded", tieB.entityId, Targeting.acquire(t, vanguard).entityId, 0)
	local reach = 3.5 + 1.2 -- vanguard range + scrapper radius
	local edgeWorld = newWorld()
	local probe = dummy(World.spawnAlly(edgeWorld, "vanguard", 30))
	local target = dummy(World.spawnEnemy(edgeWorld, "scrapper", 30 + reach))
	check(
		"tcombat01-range-exact-in",
		target.entityId,
		(Targeting.acquire(edgeWorld, probe) or {}).entityId,
		0
	)
	target.x = 30 + reach - 0.001
	check(
		"tcombat01-range-inside",
		target.entityId,
		(Targeting.acquire(edgeWorld, probe) or {}).entityId,
		0
	)
	target.x = 30 + reach + 0.001
	check("tcombat01-range-outside", nil, Targeting.acquire(edgeWorld, probe), 0)

	-- ---------------------------------------------------------------- T-COMBAT-02 damage/timing
	local function hitTicks(heroX: number)
		local cw = newWorld()
		cw.entities[cw.heroId].x = heroX
		local attacker = World.spawnAlly(cw, "vanguard", 50)
		local victim = dummy(World.spawnEnemy(cw, "scrapper", 53))
		victim.hp, victim.maxHp = 100000, 100000
		local ticks, damages, last = {}, {}, victim.hp
		for _ = 1, 200 do
			World.step(cw)
			if victim.hp ~= last then
				table.insert(ticks, cw.tick)
				table.insert(damages, last - victim.hp)
				last = victim.hp
			end
		end
		return ticks, damages, attacker
	end
	local plainTicks, plainDamage = hitTicks(10)
	check("tcombat02-damage-20", 20, plainDamage[1], plainTicks[1])
	check("tcombat02-first-release-windup3", 4, plainTicks[1], plainTicks[1]) -- windup starts tick 1
	check("tcombat02-cycle-76", 76, plainTicks[2] - plainTicks[1], plainTicks[2])
	check("tcombat02-cycle-stable", 76, plainTicks[3] - plainTicks[2], plainTicks[3])
	local _, supportDamage, supported = hitTicks(50)
	check("tcombat02-support-22", 22, supportDamage[1], 0)
	check("tcombat02-support-flag", true, supported.inSupport, 0)
	local killWorld = newWorld()
	killWorld.entities[killWorld.heroId].x = 50
	World.spawnAlly(killWorld, "vanguard", 50)
	local scrapper = dummy(World.spawnEnemy(killWorld, "scrapper", 53))
	local hitsToKill = 0
	local lastHp = scrapper.hp
	for _ = 1, 600 do
		World.step(killWorld)
		if scrapper.hp ~= lastHp then
			hitsToKill += 1
			lastHp = scrapper.hp
		end
		if scrapper.hp == 0 then
			break
		end
	end
	check("tcombat02-hp130-six-supported-hits", 6, hitsToKill, killWorld.tick) -- ceil(130 / 22)

	-- ---------------------------------------------------------------- T-COMBAT-03 release re-validation
	local function windupScenario(mutate: (any, any) -> ())
		local mw = newWorld()
		local attacker = World.spawnAlly(mw, "vanguard", 50)
		local victim = dummy(World.spawnEnemy(mw, "scrapper", 53))
		World.step(mw) -- tick 1: acquire + windup
		mutate(attacker, victim)
		local hpBefore = victim.hp
		local hits = 0
		for _ = 1, 3 do -- release tick 4
			hits += World.step(mw).hits
		end
		return attacker, victim, hpBefore, mw, hits
	end
	local a1, _, _, w1, hits1 = windupScenario(function(_, victim)
		victim.hp, victim.state = 0, "Dead"
	end)
	check("tcombat03-target-died-no-hit", 0, hits1, 0)
	check("tcombat03-target-died-no-reward", 0, w1.pendingKillGold, 0)
	check("tcombat03-target-died-recovery", "Recovery", a1.state, 0)
	local a2, v2, hp2, _, hits2 = windupScenario(function(_, victim)
		victim.x = 70
	end)
	check("tcombat03-target-left-no-damage", hp2, v2.hp, 0)
	check("tcombat03-target-left-no-hit", 0, hits2, 0)
	check("tcombat03-target-left-recovery", "Recovery", a2.state, 0)
	local a3, v3, hp3, _, hits3 = windupScenario(function(attacker)
		attacker.facing = -1
	end)
	check("tcombat03-reversed-no-damage", hp3, v3.hp, 0)
	check("tcombat03-reversed-no-hit", 0, hits3, 0)
	local _, controlVictim, _, _, hitsControl = windupScenario(function() end)
	check("tcombat03-control-hits-once", 1, hitsControl, 0)
	check("tcombat03-control-damage-20", controlVictim.maxHp - 20, controlVictim.hp, 0)
	check("tcombat03-one-serial-per-cycle", 1, a3.attackSerial, 0)
	check("tcombat03-dead-target-serial", 1, a1.attackSerial, 0)

	-- ---------------------------------------------------------------- T-COMBAT-04 batch / single death
	local bw = newWorld()
	local s1 = World.spawnAlly(bw, "vanguard", 50)
	local s2 = World.spawnAlly(bw, "vanguard", 50)
	local prey = dummy(World.spawnEnemy(bw, "scrapper", 53))
	prey.hp = 15 -- either hit alone is lethal
	local deaths = 0
	for _ = 1, 10 do
		deaths += #World.step(bw).deaths
	end
	check("tcombat04-two-lethal-one-death", 1, deaths, bw.tick)
	check("tcombat04-kill-reward-once", 18, bw.pendingKillGold, bw.tick)
	check("tcombat04-kill-xp-once", 12, bw.pendingKillXp, bw.tick)
	check("tcombat04-kill-count", 1, bw.killCounts.scrapper, bw.tick)
	check("tcombat04-dead-record-dropped", nil, bw.entities[prey.entityId], bw.tick)
	check("tcombat04-attackers-alive", true, s1.hp > 0 and s2.hp > 0, bw.tick)
	local guardWorld = newWorld()
	local corpse = dummy(World.spawnEnemy(guardWorld, "scrapper", 40))
	corpse.hp, corpse.state = 0, "Dead"
	local lateHits = {
		{
			attackerId = 1,
			targetId = corpse.entityId,
			damage = 50,
			releaseTick = 1,
			attackSerial = 1,
		},
	}
	check("tcombat04-dead-target-no-second-death", 0, #env.Damage.apply(guardWorld, lateHits), 0)
	check("tcombat04-dead-target-no-second-reward", 0, guardWorld.pendingKillGold, 0)

	local mutual = newWorld()
	local ally = World.spawnAlly(mutual, "vanguard", 50)
	local enemy = World.spawnEnemy(mutual, "scrapper", 53) -- within both reaches (4.7 and 3.2)
	ally.hp, enemy.hp = 5, 5
	enemy.attack = { kind = "Melee", windupTicks = 3, recoveryTicks = 7, cooldownTicks = 66 } -- same timing
	local mutualDeaths = {}
	for _ = 1, 6 do
		for _, death in World.step(mutual).deaths do
			table.insert(mutualDeaths, death.tick)
		end
	end
	check("tcombat04-mutual-both-die", 2, #mutualDeaths, mutual.tick)
	check("tcombat04-mutual-same-tick", mutualDeaths[1], mutualDeaths[2], mutual.tick)

	-- ---------------------------------------------------------------- T-COMBAT-05 frame-rate independence
	local function scenario(frames: { number }): (any, { string })
		local fw = newWorld()
		fw.resources.foodMilli = 40000
		World.spawnEnemy(fw, "scrapper", 20)
		local driver = FixedStep.new()
		local digests: { string } = {}
		for _, dt in frames do
			FixedStep.advance(driver, dt, function()
				local commands: { any } = if fw.tick == 4
					then { { kind = "Summon", slot = 1, requestId = "s", commandSeq = 1 } }
					else {}
				World.step(fw, { commands = commands, axis = 1 })
				table.insert(digests, (World.digest(fw)) :: string)
			end)
		end
		return driver, digests
	end
	local function repeatFrames(dt: number, count: number)
		local frames = {}
		for _ = 1, count do
			table.insert(frames, dt)
		end
		return frames
	end
	local d60, g60 = scenario(repeatFrames(1 / 60, 180))
	local d30, g30 = scenario(repeatFrames(1 / 30, 90))
	local uneven = {}
	local pattern = { 0.01, 0.03, 0.07, 0.04, 0.05 }
	for _ = 1, 15 do
		for _, dt in pattern do
			table.insert(uneven, dt)
		end
	end
	local dUneven, gUneven = scenario(uneven) -- 15 * 0.2s = 3s
	check("tcombat05-60fps-ticks", 60, d60.ticks, 0)
	check("tcombat05-30fps-ticks", 60, d30.ticks, 0)
	check("tcombat05-uneven-ticks", 60, dUneven.ticks, 0)
	check("tcombat05-same-digest-60-30", g60[60], g30[60], 60)
	check("tcombat05-same-digest-uneven", g60[60], gUneven[60], 60)
	local spike = FixedStep.new()
	local spikeSteps = FixedStep.advance(spike, 1.0, function() end)
	check("tcombat05-catchup-max-4", 4, spikeSteps, 0)
	check("tcombat05-dropped-reported", 0.75, FixedStep.droppedSeconds(spike), 0)
	local burst = newWorld()
	burst.entities[burst.heroId].x = 50
	World.spawnAlly(burst, "vanguard", 50)
	local tank = dummy(World.spawnEnemy(burst, "scrapper", 53))
	tank.hp, tank.maxHp = 100000, 100000
	local burstDriver = FixedStep.new()
	FixedStep.advance(burstDriver, 1.0, function()
		World.step(burst)
	end)
	check("tcombat05-big-dt-only-4-ticks", 4, burst.tick, burst.tick)
	check("tcombat05-big-dt-one-hit-at-most", true, 100000 - tank.hp <= 22, burst.tick)
	check("tcombat05-backlog-carried", 1, FixedStep.advance(spike, 0, function() end), 0)
	local tiny = FixedStep.new()
	local tinySteps = 0
	for _ = 1, 3 do
		tinySteps += FixedStep.advance(tiny, 0.0166, function() end)
	end
	check("tcombat05-no-early-tick", 0, tinySteps, 0)

	-- ---------------------------------------------------------------- T-COMBAT-06 boundaries
	local bnd = newWorld()
	local runner = World.spawnAlly(bnd, "vanguard", 80)
	local core = bnd.entities[bnd.coreId]
	core.hp, core.x = 1000000, 200 -- out of reach: the ally must stop at the advance limit, not the core
	steps(bnd, 200)
	check("tcombat06-ally-advance-limit", true, near(runner.x, 86.4), bnd.tick)
	core.x = 90.4 -- real core position: still targetable from the limit (reach 3.5 + 2.5 >= 4)
	steps(bnd, 100)
	check("tcombat06-core-attacked-from-limit", true, core.hp < 1000000, bnd.tick)
	local hero = bnd.entities[bnd.heroId]
	steps(bnd, 400, { axis = 1 })
	check("tcombat06-hero-right-limit", true, near(hero.x, 86.4), bnd.tick)
	steps(bnd, 400, { axis = -1 })
	check("tcombat06-hero-left-limit", true, near(hero.x, 0), bnd.tick)

	local br = newWorld()
	br.entities[br.heroId].x = 30
	local guard = dummy(World.spawnAlly(br, "bulwark", 29)) -- standing right where the breacher lands
	local breacher = World.spawnEnemy(br, "scrapper", 0.1)
	World.step(br)
	check("tcombat06-breach-relocated", true, near(breacher.x, 29), br.tick)
	check("tcombat06-breach-flag", true, breacher.breachReturn, br.tick)
	check("tcombat06-breach-faces-hero", 1, breacher.facing, br.tick)
	local relocations = 0
	local lastX = breacher.x
	for _ = 1, 60 do
		World.step(br)
		if breacher.x < lastX - 1 then
			relocations += 1
		end
		lastX = breacher.x
	end
	check("tcombat06-breach-once", 0, relocations, br.tick)
	check(
		"tcombat06-breach-targets-hero-only",
		true,
		breacher.targetId == nil or breacher.targetId == br.heroId,
		br.tick
	)
	check("tcombat06-breach-ignores-ally", guard.maxHp, guard.hp, br.tick)
	check(
		"tcombat06-breach-hurts-hero",
		true,
		br.entities[br.heroId].hp < br.entities[br.heroId].maxHp,
		br.tick
	)

	local chase = newWorld()
	local chaseHero = chase.entities[chase.heroId]
	chaseHero.x = 30
	local runnerEnemy = World.spawnEnemy(chase, "scrapper", 0.1)
	World.step(chase)
	local monotonic, flips, maxStep = true, 0, 0
	local previous = runnerEnemy.x
	local wasBreach = runnerEnemy.breachReturn
	for _ = 1, 150 do -- attackers stand still during their own attack cycle, so give the chase time
		World.step(chase, { axis = 1 }) -- hero walks away right: breacher must chase, never relocate again
		monotonic = monotonic and runnerEnemy.x >= previous - EPS
		maxStep = math.max(maxStep, math.abs(runnerEnemy.x - previous))
		previous = runnerEnemy.x
		if runnerEnemy.breachReturn ~= wasBreach then
			flips += 1
			wasBreach = runnerEnemy.breachReturn
		end
	end
	check("tcombat06-breach-chases-right", true, monotonic and runnerEnemy.x > 29 + 5, chase.tick)
	check("tcombat06-breach-flag-stable", 0, flips, chase.tick)
	check("tcombat06-breach-walks-not-teleports", true, maxStep <= 3 * 0.05 + EPS, chase.tick)
	local farthest = runnerEnemy.x
	for _ = 1, 250 do
		World.step(chase, { axis = -1 }) -- hero walks back past the breacher
	end
	check("tcombat06-breach-refaces-left", -1, runnerEnemy.facing, chase.tick)
	check("tcombat06-breach-hero-passed", true, chaseHero.x < farthest, chase.tick)
	check("tcombat06-breach-follows-left", true, runnerEnemy.x < farthest, chase.tick)
	local edgeHero = newWorld()
	edgeHero.entities[edgeHero.heroId].x = 0.5
	local edgeEnemy = World.spawnEnemy(edgeHero, "scrapper", 0.1)
	World.step(edgeHero)
	check("tcombat06-breach-at-zero", true, near(edgeEnemy.x, 0), edgeHero.tick)

	-- ---------------------------------------------------------------- T-HERO-01 keepalive + TTL
	local hw = newWorld()
	local axisTick = -math.huge
	local function effectiveAxis(): number
		return if hw.tick + 1 - axisTick > 10 then 0 else 1 -- MatchService rule: TTL 10 ticks from receipt
	end
	for index = 1, 20 do
		if index % 2 == 1 then
			axisTick = hw.tick + 1
		end
		World.step(hw, { axis = effectiveAxis() })
	end
	check("thero01-x16", true, near(hw.entities[hw.heroId].x, 16), hw.tick)
	local stopTicks = 0
	for _ = 1, 30 do
		local axis = effectiveAxis()
		World.step(hw, { axis = axis })
		if axis == 0 and stopTicks == 0 then
			stopTicks = hw.tick
		end
	end
	check(
		"thero01-axis-zero-after-ttl",
		true,
		stopTicks > 0 and stopTicks - axisTick <= 11,
		hw.tick
	)
	check("thero01-bounded", true, hw.entities[hw.heroId].x <= 86.4 + EPS, hw.tick)

	-- ---------------------------------------------------------------- seed replay / tick order / outcome
	local function replay()
		local rw = newWorld({ stageId = "s03" })
		rw.resources.foodMilli = 40000
		World.spawnEnemy(rw, "brute", 60)
		World.spawnEnemy(rw, "spitter", 70)
		local digests: { string } = {}
		local ranged = 0
		for index = 1, 300 do
			local commands: { any } = {}
			if index % 25 == 0 then
				table.insert(commands, {
					kind = "Summon",
					slot = (index // 25) % 3 + 1,
					requestId = "r" .. index,
					commandSeq = index,
				})
			end
			World.step(rw, { commands = commands, axis = if index % 50 < 20 then 1 else 0 })
			table.insert(digests, (World.digest(rw)) :: string)
			ranged += #rw.projectileRequests
		end
		return digests, ranged
	end
	local first, rangedReleases = replay()
	local second = replay()
	check("replay-same-digest-300", first[300], second[300], 300)
	local identical = true
	for index = 1, 300 do
		identical = identical and first[index] == second[index]
	end
	check("replay-every-tick-identical", true, identical, 300)
	check("replay-ranged-requests-recorded", true, rangedReleases > 0, 300)
	local changed = newWorld({ stageId = "s03" })
	changed.resources.foodMilli = 40000
	World.spawnEnemy(changed, "brute", 60)
	World.spawnEnemy(changed, "spitter", 70)
	World.step(
		changed,
		{ commands = { { kind = "Summon", slot = 1, requestId = "x", commandSeq = 1 } } }
	)
	local sameFirst = newWorld({ stageId = "s03" })
	sameFirst.resources.foodMilli = 40000
	World.spawnEnemy(sameFirst, "brute", 60)
	World.spawnEnemy(sameFirst, "spitter", 70)
	World.step(sameFirst)
	check("replay-digest-sensitive", true, World.digest(changed) ~= World.digest(sameFirst), 1)

	local ow = newWorld({ trace = true })
	World.step(ow)
	check("tick-order-fixed", table.concat(World.PHASES, ","), table.concat(ow.trace, ","), 1)

	local win = newWorld()
	win.entities[win.coreId].hp = 1
	World.spawnAlly(win, "vanguard", 87)
	local outcome
	for _ = 1, 10 do
		outcome = World.step(win).outcome or outcome
	end
	check("outcome-core-victory", "Victory", outcome, win.tick)
	local frozen = win.resources.foodMilli
	local after = World.step(
		win,
		{ commands = { { kind = "Summon", slot = 1, requestId = "late", commandSeq = 9 } } }
	)
	check("outcome-commands-rejected", "WrongPhase", after.results[1].reason, win.tick)
	check("outcome-no-regen-after-end", frozen, win.resources.foodMilli, win.tick)
	local lose = newWorld()
	lose.entities[lose.heroId].hp = 1
	lose.entities[lose.coreId].hp = 1
	World.spawnAlly(lose, "vanguard", 87)
	local killer = World.spawnEnemy(lose, "scrapper", 11)
	killer.attack = { kind = "Melee", windupTicks = 3, recoveryTicks = 7, cooldownTicks = 66 } -- lands on tick 4 too
	local both
	for _ = 1, 10 do
		both = World.step(lose).outcome or both
	end
	check("outcome-defeat-precedence", "Defeat", both, lose.tick)
	check("outcome-core-also-died-same-tick", 0, lose.entities[lose.coreId].hp, lose.tick)
	local slow = newWorld()
	slow.tick = 11999
	check("outcome-timeout-at-12000", "Timeout", World.step(slow).outcome, 12000)

	local snapshot = World.snapshotEntities(newWorld())
	check("snapshot-no-attack-power", nil, snapshot[1].attackPower, 0)
	-- ---------------------------------------------------------------- tick order (behavioural)
	local mo = newWorld()
	local mover = World.spawnAlly(mo, "vanguard", 40)
	dummy(World.spawnEnemy(mo, "scrapper", 40 + 4.7 + 0.1)) -- 0.1 out of reach; one 0.15 step closes it
	World.step(mo)
	check("order-move-before-target", "Windup", mover.state, mo.tick)
	local so = newWorld()
	local supportHero = so.entities[so.heroId]
	supportHero.x = 50 - 7.5 - 0.2 -- just outside the support radius
	World.spawnAlly(so, "vanguard", 50)
	local supportTarget = dummy(World.spawnEnemy(so, "scrapper", 53))
	supportTarget.hp, supportTarget.maxHp = 1000, 1000
	steps(so, 3)
	World.step(so, { axis = 1 }) -- tick 4: hero moves into radius, then support, then release
	check("order-move-support-attack", 22, 1000 - supportTarget.hp, so.tick)

	-- ---------------------------------------------------------------- MatchService integration
	local Protocol = env.Protocol
	local clock = { tick = 0 }
	local sent: { any } = {}
	local profiles = env.ProfileService.new({
		store = env.newStore(),
		clock = function()
			return 1000
		end,
		spawn = function(fn)
			fn()
		end,
		sessionId = "s",
		jobId = "j",
		receiptCap = Protocol.LIMITS.receiptCap,
		queueCap = Protocol.LIMITS.profileQueueCap,
		log = function() end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return clock.tick
		end,
		newMatchId = function()
			return "m-1"
		end,
		balanceHash = "h",
		send = function(_, message)
			table.insert(sent, message)
		end,
		maxMatches = Protocol.LIMITS.maxMatches,
		ackCacheSize = Protocol.LIMITS.ackCacheSize,
		moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
	})
	local function tickOnce()
		clock.tick += 1
		match.stepAll()
	end
	local function lastFor(requestId: string): any
		for index = #sent, 1, -1 do
			if sent[index].requestId == requestId then
				return sent[index]
			end
		end
		return nil
	end
	match.playerJoined(1)
	match.handleCommand(1, {
		kind = "StartStage",
		requestId = "start-000000000001",
		stageId = "s01",
		expectedRevision = 0,
	})
	check("ms-running", "Running", match.phaseOf(1), 0)
	local summonPoor = {
		kind = "Summon",
		requestId = "summon-00000000001",
		matchId = "m-1",
		commandSeq = 1,
		slot = 1,
	}
	match.handleCommand(1, summonPoor)
	check("ms-pending-first", "Pending", lastFor(summonPoor.requestId).status, 0)
	tickOnce()
	check("ms-final-rejected", "InsufficientFood", lastFor(summonPoor.requestId).reason, clock.tick)
	match.handleCommand(1, summonPoor)
	check(
		"ms-duplicate-gets-final",
		"InsufficientFood",
		lastFor(summonPoor.requestId).reason,
		clock.tick
	)
	local world = match.worldOf(1)
	world.resources.foodMilli = 20000
	local summonOk = {
		kind = "Summon",
		requestId = "summon-00000000002",
		matchId = "m-1",
		commandSeq = 2,
		slot = 1,
	}
	match.handleCommand(1, summonOk)
	tickOnce()
	check("ms-final-accepted", "Accepted", lastFor(summonOk.requestId).status, clock.tick)
	local snap = match.snapshot(1)
	check("ms-snapshot-world-tick", world.tick, snap.tick, clock.tick)
	check("ms-snapshot-food", world.resources.foodMilli, snap.resources.foodMilli, clock.tick)
	check("ms-snapshot-entities", 3, #snap.entities, clock.tick) -- hero, core, vanguard
	check("ms-snapshot-no-attack-power", nil, snap.entities[3].attackPower, clock.tick)

	-- T-HERO-01 through the real MatchService TTL: keepalive every 2 ticks for 20 ticks, then stop
	local heroStart = world.entities[world.heroId].x
	for index = 1, 20 do
		if index % 2 == 1 then
			match.handleMove(1, { matchId = "m-1", seq = index, axis = 1 })
		end
		tickOnce()
	end
	check("thero01-ms-x16", true, near(world.entities[world.heroId].x, heroStart + 6), clock.tick)
	local stoppedAt = world.entities[world.heroId].x
	for _ = 1, 20 do
		tickOnce()
	end
	local drift = world.entities[world.heroId].x - stoppedAt
	check(
		"thero01-ms-ttl-stops",
		true,
		drift > 0 and drift <= 0.3 * Protocol.LIMITS.moveTtlTicks + EPS,
		clock.tick
	)
	check("thero01-ms-axis-zero", 0, match.effectiveAxis(1), clock.tick)

	-- outcome -> Settling, nothing further simulated
	world.entities[world.coreId].hp = 1
	World.spawnAlly(world, "vanguard", world.entities[world.coreId].x - 3)
	for _ = 1, 10 do
		tickOnce()
	end
	check("ms-outcome-settling", "Settling", match.phaseOf(1), clock.tick)
	check("ms-outcome-in-snapshot", "Victory", match.snapshot(1).outcome, clock.tick)
	local frozenTick = world.tick
	tickOnce()
	check("ms-no-step-after-outcome", frozenTick, world.tick, clock.tick)
	match.handleCommand(1, {
		kind = "Summon",
		requestId = "summon-00000000009",
		matchId = "m-1",
		commandSeq = 9,
		slot = 1,
	})
	check(
		"ms-summon-after-outcome-rejected",
		"WrongPhase",
		lastFor("summon-00000000009").reason,
		clock.tick
	)
end
