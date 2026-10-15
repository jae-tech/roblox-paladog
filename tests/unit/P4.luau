--!strict
-- P4 pure behaviour suite; shared by CLI and Studio through injected modules.
type Check = (string, unknown, unknown, number) -> ()
local EPS = 1e-6

return function(env: any, check: Check)
	local World, Projectile = env.World, env.ProjectileSystem
	local function near(a: number, b: number): boolean
		return math.abs(a - b) <= EPS
	end
	local function fresh(): any
		local w = World.new({ stageId = "s01" })
		w.resources.manaRateMilli = 0
		return w
	end
	local function target(w: any, x: number): any
		local e = World.spawnEnemy(w, "scrapper", x)
		e.moveSpeed, e.attack, e.hitRadius = 0, nil, 0.01
		e.state = "Idle"
		return e
	end
	local function launch(
		w: any,
		owner: any,
		x: number,
		direction: number?,
		definition: string?,
		damage: number?
	): boolean
		return Projectile.launch(w, {
			ownerId = owner.entityId,
			projectileId = definition or "ally_bolt",
			damage = damage or 37,
			releaseTick = w.tick,
			x = x,
			direction = direction or 1,
		})
	end
	local function onlyProjectile(w: any): any
		for _, p in w.projectiles do
			return p
		end
		return nil
	end
	local function advance(w: any): { any }
		w.tick += 1
		return Projectile.advance(w)
	end
	local function steps(w: any, count: number, input: any?)
		for _ = 1, count do
			World.step(w, input)
		end
	end
	local function cast(w: any, seq: number?): any
		return World.step(w, {
			commands = {
				{
					kind = "Cast",
					slot = 1,
					requestId = "cast-" .. tostring(seq or 1),
					commandSeq = seq or 1,
				},
			},
		}).results[1]
	end

	-- T-PROJECTILE-01: a narrow target strictly between endpoints cannot be skipped.
	local swept = fresh()
	local victim = target(swept, 21.5)
	check("tprojectile01-launch", true, launch(swept, swept.entities[swept.heroId], 20), 0)
	check("tprojectile01-new-shot-stationary", 20, onlyProjectile(swept).x, 0)
	local hits = advance(swept)
	check("tprojectile01-swept-hit", 1, #hits, swept.tick)
	check("tprojectile01-correct-target", victim.entityId, hits[1].targetId, swept.tick)
	check("tprojectile01-snapshot-damage", 37, hits[1].damage, swept.tick)
	check("tprojectile01-pierce-one-removed", 0, Projectile.count(swept), swept.tick)
	check("tprojectile01-no-repeat", 0, #advance(swept), swept.tick)

	-- Entry distance wins, not centre distance or insertion order. Equal entry uses entityId.
	local ordering = fresh()
	local farther = target(ordering, 22.5)
	local nearer = target(ordering, 21)
	launch(ordering, ordering.entities[ordering.heroId], 20)
	check(
		"tprojectile02-nearest-not-entity-order",
		nearer.entityId,
		advance(ordering)[1].targetId,
		ordering.tick
	)
	check("tprojectile02-farther-not-hit", farther.maxHp, farther.hp, ordering.tick)
	local entry = fresh()
	local small = target(entry, 21)
	local wide = target(entry, 22)
	wide.hitRadius = 1.5
	launch(entry, entry.entities[entry.heroId], 20)
	check("tprojectile02-entry-not-centre", wide.entityId, advance(entry)[1].targetId, entry.tick)
	check("tprojectile02-small-remains-alive", true, small.hp > 0, entry.tick)
	local tie = fresh()
	local first = target(tie, 21)
	target(tie, 21)
	launch(tie, tie.entities[tie.heroId], 20)
	check("tprojectile02-equal-entry-id", first.entityId, advance(tie)[1].targetId, tie.tick)

	local filters = fresh()
	local friend = World.spawnAlly(filters, "vanguard", 20.5)
	local lane = target(filters, 21)
	lane.laneId = 2
	local dead = target(filters, 21.5)
	dead.hp, dead.state = 0, "Dead"
	local hostile = target(filters, 22.5)
	launch(filters, filters.entities[filters.heroId], 20)
	local filtered = advance(filters)
	check("tprojectile02-filters-hit-count", 1, #filtered, filters.tick)
	check(
		"tprojectile02-hostile-living-same-lane",
		hostile.entityId,
		filtered[1].targetId,
		filters.tick
	)
	check("tprojectile02-friendly-no-damage", friend.maxHp, friend.hp, filters.tick)
	local reverse = fresh()
	local attacker = target(reverse, 20)
	local ally = World.spawnAlly(reverse, "vanguard", 19.5)
	ally.hitRadius = 0.01
	launch(reverse, attacker, 20, -1, "enemy_bolt", 19)
	check(
		"tprojectile02-enemy-negative-direction",
		ally.entityId,
		advance(reverse)[1].targetId,
		reverse.tick
	)

	local dedup = fresh()
	local broad = target(dedup, 22)
	broad.hitRadius = 5
	launch(dedup, dedup.entities[dedup.heroId], 20)
	onlyProjectile(dedup).remainingPierce = 3 -- fixture exercises dedup beyond current pierce-1 catalog
	check("tprojectile01-wide-first-hit", 1, #advance(dedup), dedup.tick)
	check("tprojectile01-overlap-no-second-hit", 0, #advance(dedup), dedup.tick)
	local detached = fresh()
	local owner = World.spawnAlly(detached, "slinger", 20)
	local detachedTarget = target(detached, 21.5)
	launch(detached, owner, 20)
	owner.hp, owner.state = 0, "Dead"
	detached.entities[owner.entityId] = nil
	local orphanHits = advance(detached)
	check("tprojectile02-owner-death-shot-survives", 1, #orphanHits, detached.tick)
	check(
		"tprojectile02-owner-death-target",
		detachedTarget.entityId,
		orphanHits[1].targetId,
		detached.tick
	)

	-- Target identity is not a homing lock: collisions use live positions and all valid bodies.
	local escaped = fresh()
	local oldTarget = target(escaped, 21)
	local interceptor = target(escaped, 22)
	Projectile.launch(escaped, {
		ownerId = escaped.heroId,
		targetId = oldTarget.entityId,
		projectileId = "ally_bolt",
		damage = 37,
		releaseTick = escaped.tick,
		x = 20,
		direction = 1,
	})
	oldTarget.x = 40
	check(
		"tprojectile02-target-escaped-interceptor-hit",
		interceptor.entityId,
		advance(escaped)[1].targetId,
		escaped.tick
	)
	local multi = fresh()
	local multiFar = target(multi, 22)
	local multiNear = target(multi, 21)
	launch(multi, multi.entities[multi.heroId], 20)
	onlyProjectile(multi).remainingPierce = 2
	local multiHits = advance(multi)
	check("tprojectile01-multipierce-two-hits", 2, #multiHits, multi.tick)
	check(
		"tprojectile01-multipierce-near-first",
		multiNear.entityId,
		multiHits[1].targetId,
		multi.tick
	)
	check(
		"tprojectile01-multipierce-far-second",
		multiFar.entityId,
		multiHits[2].targetId,
		multi.tick
	)
	check("tprojectile01-multipierce-exhausted", 0, Projectile.count(multi), multi.tick)

	-- TTL includes the final segment; exhausted distance never reaches beyond the clipped endpoint.
	local ttl = fresh()
	local ttlTarget = target(ttl, 21.5)
	launch(ttl, ttl.entities[ttl.heroId], 20)
	onlyProjectile(ttl).expireTick = 1
	check(
		"tprojectile03-ttl-final-segment-hit",
		ttlTarget.entityId,
		advance(ttl)[1].targetId,
		ttl.tick
	)
	check("tprojectile03-ttl-final-removed", 0, Projectile.count(ttl), ttl.tick)
	local expiry = fresh()
	launch(expiry, expiry.entities[expiry.heroId], 20)
	onlyProjectile(expiry).expireTick = 1
	check("tprojectile03-ttl-empty-hit", 0, #advance(expiry), expiry.tick)
	check("tprojectile03-ttl-empty-removed", 0, Projectile.count(expiry), expiry.tick)
	local distance = fresh()
	target(distance, 21.5)
	launch(distance, distance.entities[distance.heroId], 20)
	onlyProjectile(distance).distanceRemaining = 0.5
	check("tprojectile03-distance-clipped-no-hit", 0, #advance(distance), distance.tick)
	check("tprojectile03-distance-removed", 0, Projectile.count(distance), distance.tick)
	for _, direction in { -1, 1 } do
		local boundary = fresh()
		local x = if direction == 1 then boundary.stage.length - 0.1 else 0.1
		launch(boundary, boundary.entities[boundary.heroId], x, direction)
		advance(boundary)
		check(
			"tprojectile03-map-removed-" .. direction,
			0,
			Projectile.count(boundary),
			boundary.tick
		)
	end

	-- T-HERO-02: costs/locks are atomic; movement continues, release is +4 and recovery is +6.
	local hero = fresh()
	hero.resources.manaMilli = 10000
	check("thero02-cast-accepted", "Accepted", cast(hero).status, hero.tick)
	check("thero02-exact-cost", 0, hero.resources.manaMilli, hero.tick)
	check("thero02-cooldown-from-cast", 31, hero.resources.skillReadyTick, hero.tick)
	check("thero02-slot-reserved", true, hero.heroAction.reservedProjectileSlot, hero.tick)
	check("thero02-no-windup-shot", 0, hero.projectileCount, hero.tick)
	local startX = hero.entities[hero.heroId].x
	hero.resources.manaMilli = 10000
	check("thero03-busy-rejected", "Busy", cast(hero, 2).reason, hero.tick)
	check("thero03-busy-no-charge", 10000, hero.resources.manaMilli, hero.tick)
	steps(hero, 2, { axis = -1 })
	check(
		"thero02-windup-movement",
		true,
		near(hero.entities[hero.heroId].x, startX - 0.6),
		hero.tick
	)
	check("thero02-before-release-empty", 0, hero.projectileCount, hero.tick)
	World.step(hero, { axis = -1 })
	local pulse = onlyProjectile(hero)
	check("thero02-release-four-ticks", 5, hero.tick, hero.tick)
	check("thero02-release-one-shot", 1, Projectile.count(hero), hero.tick)
	check(
		"thero02-release-reservation-consumed",
		false,
		hero.heroAction.reservedProjectileSlot,
		hero.tick
	)
	check(
		"thero02-release-after-movement",
		true,
		near(pulse.x, hero.entities[hero.heroId].x),
		hero.tick
	)
	check("thero02-new-pulse-unmoved", pulse.x, pulse.previousX, hero.tick)
	check("thero02-pulse-fixed-forward", 1, pulse.direction, hero.tick)
	check("thero02-pulse-fixed-damage", 100, pulse.damage, hero.tick)
	check("thero02-pulse-definition", "pulse_bolt", pulse.definitionId, hero.tick)
	local releaseX = pulse.x
	World.step(hero)
	check("thero02-next-tick-moves", true, near(pulse.x, releaseX + 1.25), hero.tick)
	steps(hero, 3)
	check("thero02-recovery-before-boundary", "Busy", cast(hero, 3).reason, hero.tick)
	check("thero02-recovery-ended-cooldown", "Cooldown", cast(hero, 4).reason, hero.tick)
	steps(hero, 18)
	check("thero02-before-cooldown-rejected", "Cooldown", cast(hero, 5).reason, hero.tick)
	check("thero02-cooldown-boundary-accepted", "Accepted", cast(hero, 6).status, hero.tick)

	local poor = fresh()
	poor.resources.manaMilli = 9999
	check("thero03-insufficient-mana", "InsufficientMana", cast(poor).reason, poor.tick)
	check("thero03-poor-no-charge", 9999, poor.resources.manaMilli, poor.tick)
	check("thero03-poor-no-cooldown", 0, poor.resources.skillReadyTick, poor.tick)
	check("thero03-poor-no-reserve", false, poor.heroAction.reservedProjectileSlot, poor.tick)
	local death = fresh()
	death.resources.manaMilli = 10000
	cast(death)
	death.entities[death.heroId].hp = 0
	World.step(death)
	check(
		"thero03-death-cancels-reserve",
		false,
		death.heroAction.reservedProjectileSlot,
		death.tick
	)
	check("thero03-death-no-refund", 0, death.resources.manaMilli, death.tick)
	check("thero03-death-no-shot", 0, Projectile.count(death), death.tick)
	check("thero03-death-command-rejected", "WrongPhase", cast(death, 2).reason, death.tick)
	local terminal = fresh()
	terminal.resources.manaMilli = 10000
	cast(terminal)
	terminal.entities[terminal.coreId].hp = 0
	World.step(terminal)
	check(
		"thero03-victory-cancels-reserve",
		false,
		terminal.heroAction.reservedProjectileSlot,
		terminal.tick
	)
	check("thero03-victory-no-refund", 0, terminal.resources.manaMilli, terminal.tick)

	-- T-PROJECTILE-03 cap128, including cast's reserved slot.
	local cap = fresh()
	cap.resources.manaMilli = 10000
	local filled = 0
	for _ = 1, 128 do
		if launch(cap, cap.entities[cap.heroId], 20) then
			filled += 1
		end
	end
	check("tprojectile03-cap128-filled", 128, filled, cap.tick)
	check("tprojectile03-cap129-denied", false, launch(cap, cap.entities[cap.heroId], 20), cap.tick)
	check("tprojectile03-cap-unchanged", 128, Projectile.count(cap), cap.tick)
	check("tprojectile03-cap-cast-denied", "ProjectileCap", cast(cap).reason, cap.tick)
	check("tprojectile03-cap-no-charge", 10000, cap.resources.manaMilli, cap.tick)
	check("tprojectile03-cap-no-cooldown", 0, cap.resources.skillReadyTick, cap.tick)
	check("tprojectile03-cap-no-reserve", false, cap.heroAction.reservedProjectileSlot, cap.tick)
	local reserve = fresh()
	reserve.resources.manaMilli = 10000
	cast(reserve)
	local reservedFilled = 0
	for _ = 1, 128 do
		if launch(reserve, reserve.entities[reserve.heroId], 40, 1, "enemy_bolt") then
			reservedFilled += 1
		end
	end
	check("tprojectile03-reserve-leaves127", 127, reservedFilled, reserve.tick)
	steps(reserve, 4)
	check("tprojectile03-reserved-release-fits", 128, Projectile.count(reserve), reserve.tick)
	check(
		"tprojectile03-release-reserve-not-leaked",
		false,
		reserve.heroAction.reservedProjectileSlot,
		reserve.tick
	)

	local autoCap = fresh()
	autoCap.resources.manaMilli = 10000
	cast(autoCap)
	for _ = 1, 127 do
		launch(autoCap, autoCap.entities[autoCap.heroId], 40, 1, "enemy_bolt")
	end
	local blockedSlinger = World.spawnAlly(autoCap, "slinger", 20)
	blockedSlinger.moveSpeed = 0
	local capTarget = target(autoCap, 25)
	blockedSlinger.state = "Windup"
	blockedSlinger.stateUntilTick = autoCap.tick + 1
	blockedSlinger.targetId = capTarget.entityId
	World.step(autoCap)
	check(
		"tprojectile03-auto-cap-miss-enters-recovery",
		"Recovery",
		blockedSlinger.state,
		autoCap.tick
	)
	check("tprojectile03-auto-cannot-steal-reservation", 127, autoCap.projectileCount, autoCap.tick)
	check(
		"tprojectile03-auto-miss-keeps-reservation",
		true,
		autoCap.heroAction.reservedProjectileSlot,
		autoCap.tick
	)

	-- Authoritative World integration: current-tick shots wait, target loss does not home,
	-- snapshotted support power survives owner death, and simultaneous overkill grants one kill.
	local ranged = fresh()
	local slinger = World.spawnAlly(ranged, "slinger", 20)
	slinger.moveSpeed = 0
	ranged.entities[ranged.heroId].x = 20
	local rangedTarget = target(ranged, 25)
	rangedTarget.hp, rangedTarget.maxHp = 1000, 1000
	steps(ranged, 6)
	check("tprojectile02-auto-release-shot", 1, Projectile.count(ranged), ranged.tick)
	check(
		"tprojectile02-auto-shot-snapshot-support",
		44,
		onlyProjectile(ranged).damage,
		ranged.tick
	)
	check("tprojectile02-auto-release-no-immediate-hit", 1000, rangedTarget.hp, ranged.tick)
	slinger.hp = 0
	steps(ranged, 2)
	check("tprojectile02-auto-owner-dead-damage", 956, rangedTarget.hp, ranged.tick)
	local overkill = fresh()
	local doomed = target(overkill, 21.5)
	doomed.hp = 30
	launch(overkill, overkill.entities[overkill.heroId], 20)
	launch(overkill, overkill.entities[overkill.heroId], 20)
	World.step(overkill)
	check("tprojectile02-overkill-one-kill", 1, overkill.killCounts.scrapper, overkill.tick)
	check(
		"tprojectile02-overkill-gold-once",
		doomed.killGold,
		overkill.pendingKillGold,
		overkill.tick
	)
	check(
		"tprojectile02-overkill-projectiles-removed",
		0,
		Projectile.count(overkill),
		overkill.tick
	)

	-- Automatic enemy attacks use the same launch/advance/damage path, without friendly fire.
	local spit = fresh()
	local spitter = World.spawnEnemy(spit, "spitter", 12)
	spitter.moveSpeed = 0
	local spitFriend = target(spit, 11.5)
	local heroHp = spit.entities[spit.heroId].hp
	steps(spit, 9)
	check("tprojectile02-spitter-windup-no-shot", 0, spit.projectileCount, spit.tick)
	World.step(spit)
	local enemyShot = onlyProjectile(spit)
	check("tprojectile02-spitter-release-tick", 10, spit.tick, spit.tick)
	check("tprojectile02-spitter-definition", "enemy_bolt", enemyShot.definitionId, spit.tick)
	check("tprojectile02-spitter-negative-direction", -1, enemyShot.direction, spit.tick)
	check(
		"tprojectile02-spitter-release-no-damage",
		heroHp,
		spit.entities[spit.heroId].hp,
		spit.tick
	)
	check("tprojectile02-spitter-release-position", spitter.x, enemyShot.x, spit.tick)
	World.step(spit)
	check(
		"tprojectile02-spitter-following-tick-damage30",
		heroHp - 30,
		spit.entities[spit.heroId].hp,
		spit.tick
	)
	check("tprojectile02-spitter-friendly-unharmed", spitFriend.maxHp, spitFriend.hp, spit.tick)
	check("tprojectile02-spitter-pierce-consumed", 0, spit.projectileCount, spit.tick)

	-- Lethal damage on release tick occurs after the paid shot is emitted, then freezes the world.
	local releaseDeath = fresh()
	releaseDeath.resources.manaMilli = 10000
	cast(releaseDeath)
	releaseDeath.entities[releaseDeath.heroId].hp = 20
	local releaseKiller = World.spawnEnemy(releaseDeath, "scrapper", 11)
	releaseKiller.moveSpeed = 0
	releaseKiller.state = "Windup"
	releaseKiller.stateUntilTick = 5
	releaseKiller.targetId = releaseDeath.heroId
	steps(releaseDeath, 3)
	local lethalRelease = World.step(releaseDeath)
	check("thero03-release-tick-lethal-defeat", "Defeat", lethalRelease.outcome, releaseDeath.tick)
	check("thero03-release-tick-lethal-time", 5, releaseDeath.tick, releaseDeath.tick)
	check("thero03-release-tick-shot-exists", 1, releaseDeath.projectileCount, releaseDeath.tick)
	check(
		"thero03-release-tick-reserve-cleared",
		false,
		releaseDeath.heroAction.reservedProjectileSlot,
		releaseDeath.tick
	)
	check("thero03-release-tick-no-refund", 0, releaseDeath.resources.manaMilli, releaseDeath.tick)
	local terminalX = onlyProjectile(releaseDeath).x
	local killerHp = releaseKiller.hp
	local terminalStep = World.step(releaseDeath)
	check("thero03-terminal-no-further-hit", 0, terminalStep.hits, releaseDeath.tick)
	check(
		"thero03-terminal-projectile-frozen",
		terminalX,
		onlyProjectile(releaseDeath).x,
		releaseDeath.tick
	)
	check("thero03-terminal-target-unharmed", killerHp, releaseKiller.hp, releaseDeath.tick)

	-- Existing projectile and two melee releases share one batch: lethal trade + overkill pay once.
	local trade = fresh()
	local tradeAlly = World.spawnAlly(trade, "vanguard", 20)
	local tradeEnemy = World.spawnEnemy(trade, "scrapper", 21)
	tradeAlly.moveSpeed, tradeEnemy.moveSpeed = 0, 0
	tradeAlly.hp, tradeAlly.attackPower = 20, 200
	tradeAlly.state, tradeEnemy.state = "Windup", "Windup"
	tradeAlly.stateUntilTick, tradeEnemy.stateUntilTick = 1, 1
	tradeAlly.targetId, tradeEnemy.targetId = tradeEnemy.entityId, tradeAlly.entityId
	launch(trade, tradeAlly, 20)
	local tradeResult = World.step(trade)
	check("tprojectile02-trade-combined-three-hits", 3, tradeResult.hits, trade.tick)
	check("tprojectile02-trade-two-deaths", 2, #tradeResult.deaths, trade.tick)
	check("tprojectile02-trade-ally-died", nil, trade.entities[tradeAlly.entityId], trade.tick)
	check("tprojectile02-trade-enemy-died", nil, trade.entities[tradeEnemy.entityId], trade.tick)
	check("tprojectile02-trade-overkill-one-kill", 1, trade.killCounts.scrapper, trade.tick)
	check("tprojectile02-trade-gold-once", tradeEnemy.killGold, trade.pendingKillGold, trade.tick)
	check("tprojectile02-trade-xp-once", tradeEnemy.killXp, trade.pendingKillXp, trade.tick)
	local afterTrade = World.step(trade)
	check("tprojectile02-trade-no-repeat-death", 0, #afterTrade.deaths, trade.tick)
	check(
		"tprojectile02-trade-no-repeat-reward",
		tradeEnemy.killGold,
		trade.pendingKillGold,
		trade.tick
	)

	-- All live projectile and cast state belongs in deterministic replay, not public damage DTOs.
	local function replay(): string
		local w = fresh()
		w.resources.manaMilli = 100000
		for index = 1, 80 do
			if index % 31 == 1 then
				cast(w, index)
			else
				World.step(w, { axis = if index % 10 < 5 then 1 else -1 })
			end
		end
		return World.digest(w)
	end
	check("replay-p4-casts-deterministic", replay(), replay(), 80)
	local digestA, digestB = fresh(), fresh()
	launch(digestB, digestB.entities[digestB.heroId], 20)
	check(
		"replay-digest-projectile-sensitive",
		true,
		World.digest(digestA) ~= World.digest(digestB),
		0
	)
	local actionA, actionB = fresh(), fresh()
	actionB.heroAction.skillId = "pulse"
	actionB.heroAction.releaseTick = 4
	actionB.heroAction.endTick = 10
	actionB.heroAction.reservedProjectileSlot = true
	check(
		"replay-digest-hero-action-sensitive",
		true,
		World.digest(actionA) ~= World.digest(actionB),
		0
	)
	local dto = World.snapshotProjectiles(digestB)[1]
	check("snapshot-projectile-definition", "ally_bolt", dto.definitionId, 0)
	for _, key in { "damage", "hitEntityIds", "remainingPierce", "attackSerial" } do
		check("snapshot-projectile-private-" .. key, nil, dto[key], 0)
	end
	local x = onlyProjectile(digestB).x
	dto.x = 999
	check("snapshot-projectile-detached", x, onlyProjectile(digestB).x, 0)

	-- MatchService ack cache must not double-charge / double-reserve a repeated Cast.
	local Protocol = env.Protocol
	local sent: { any } = {}
	local clock = 0
	local profiles = env.ProfileService.new({
		store = env.newStore(),
		clock = function()
			return 1000
		end,
		spawn = function(fn)
			fn()
		end,
		sessionId = "p4",
		jobId = "p4",
		receiptCap = Protocol.LIMITS.receiptCap,
		queueCap = Protocol.LIMITS.profileQueueCap,
		log = function() end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return clock
		end,
		newMatchId = function()
			return "p4-match"
		end,
		balanceHash = "p4-hash",
		send = function(_, message)
			table.insert(sent, message)
		end,
		maxMatches = Protocol.LIMITS.maxMatches,
		ackCacheSize = Protocol.LIMITS.ackCacheSize,
		moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
	})
	local function tickOnce()
		clock += 1
		match.stepAll()
	end
	local function lastAck(requestId: string): any
		for index = #sent, 1, -1 do
			if sent[index].requestId == requestId then
				return sent[index]
			end
		end
		return nil
	end
	match.playerJoined(1)
	match.handleCommand(
		1,
		{ kind = "StartStage", requestId = "p4-start", stageId = "s01", expectedRevision = 0 }
	)
	local mw = match.worldOf(1)
	mw.resources.manaRateMilli, mw.resources.manaMilli = 0, 10000
	local command =
		{ kind = "Cast", requestId = "p4-cast", matchId = "p4-match", commandSeq = 1, slot = 1 }
	match.handleCommand(1, command)
	check("ms-p4-cast-pending", "Pending", lastAck(command.requestId).status, clock)
	match.handleCommand(1, command)
	tickOnce()
	check("ms-p4-cast-accepted", "Accepted", lastAck(command.requestId).status, clock)
	check("ms-p4-duplicate-one-charge", 0, mw.resources.manaMilli, clock)
	match.handleCommand(1, command)
	check("ms-p4-duplicate-final-ack", "Accepted", lastAck(command.requestId).status, clock)
	for _ = 1, 4 do
		tickOnce()
	end
	check("ms-p4-duplicate-one-shot", 1, Projectile.count(mw), clock)
	local snap = match.snapshot(1)
	check("ms-p4-snapshot-one-projectile", 1, #snap.projectiles, clock)
	check("ms-p4-snapshot-hero-action", "table", typeof(snap.heroAction), clock)
	check("ms-p4-snapshot-no-damage", nil, snap.projectiles[1].damage, clock)
	local before = World.digest(mw)
	for _, field in { "damage", "attackPower", "x", "targetId", "projectileId" } do
		local forged: any = {
			protocolVersion = Protocol.VERSION,
			kind = "Cast",
			requestId = "p4-spoof-" .. field,
			matchId = "p4-match",
			commandSeq = 2,
			slot = 1,
		}
		forged[field] = if field == "projectileId" then "pulse_bolt" else 999999
		local validated, reason = Protocol.validateCommand(forged)
		check("tsec-p4-spoof-" .. field, "InvalidPayload", reason, clock)
		if validated then
			match.handleCommand(1, validated)
		end
	end
	check("tsec-p4-spoof-no-world-side-effects", before, World.digest(mw), clock)
end
