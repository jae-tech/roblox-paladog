--!strict
-- R6 survival (docs/REMAKE_PLAN.md R6, E04 §4-4): wave table, scaling, rewards, boss gems, shadow unlock
-- event, revive, and the server admission/settlement path. Save integrity, server authority and duplicate
-- reward checks run through the real services as required by the test policy.
return function(env: any, check: any)
	local Battle, Db, Schema, Settlement, Protocol =
		env.Battle, env.Db, env.Schema, env.Settlement, env.Protocol
	local serial = 0
	local function rid(): string
		serial += 1
		return string.format("r6-request-%08d", serial)
	end
	local function f3(value: number): string
		return string.format("%.3f", value)
	end
	local function loadout(heroKind: string?, difficulty: number?): any
		local slot = Schema.newSlot(heroKind or "light", difficulty or 1)
		return Schema.loadoutOf(slot)
	end
	local function survival(options: { [string]: any }?): any
		local o: { [string]: any } = options or {}
		return Battle.new({
			stage = 0,
			seed = o.seed or 4242,
			loadout = o.loadout or loadout(),
			revives = o.revives,
			darkEvent = o.darkEvent,
		})
	end
	local function kill(b: any, e: any)
		Battle.strike(b, nil, e, 1e12, false, false)
	end
	-- One tick; level-up choices (frequent with the x27 EXP) are answered through the real command.
	local function advance(b: any, input: any?)
		local result = Battle.step(b, input)
		if result.paused and b.offer then
			Battle.step(b, { commands = { { kind = "PickSkill", choice = 1, requestId = rid() } } })
			if #b.pendingPicks > 0 then
				table.clear(b.pendingPicks) -- every skill capped: no valid choice left
				b.offer = nil
			end
		end
	end
	local function enemies(b: any): { any }
		local list = {}
		for _, id in b.order do
			local e = b.entities[id]
			if e.team == 2 and Battle.alive(e) and (e.kind == "Enemy" or e.kind == "Boss") then
				table.insert(list, e)
			end
		end
		return list
	end

	-- ------------------------------------------------ wave table and multipliers (E04 §4-4)
	do
		check("wave-row-1", 1, Battle.waveRow(1), 0)
		check("wave-row-30", 30, Battle.waveRow(30), 0)
		check("wave-row-31-loop-start", 31, Battle.waveRow(31), 0)
		check("wave-row-50", 50, Battle.waveRow(50), 0)
		check("wave-row-51-wraps", 31, Battle.waveRow(51), 0)
		check("wave-row-71-wraps", 31, Battle.waveRow(71), 0)
		check("wave-db-row-140", 140, Db.survival[Battle.waveRow(1)].row, 0)
		check("wave-db-row-189", 189, Db.survival[Battle.waveRow(70)].row, 0)
		local scale, stat = Battle.survivalMul(1, Db.survival[1])
		check("svv-w1-scale", "1.000", f3(scale), 0)
		check("svv-w1-stat-1.10", "1.100", f3(stat), 0)
		scale, stat = Battle.survivalMul(30, Db.survival[30])
		check("svv-w30-stat", "1.100", f3(stat), 0)
		scale, stat = Battle.survivalMul(31, Db.survival[31])
		check("svv-w31-scale", "1.100", f3(scale), 0)
		check("svv-w31-stat-row170", "2.700", f3(stat), 0)
		scale, stat = Battle.survivalMul(32, Db.survival[32])
		check("svv-w32-stat", "34.240", f3(stat), 0) -- (1 + 0.07*1*1) * 32.0
		scale, stat = Battle.survivalMul(51, Db.survival[31])
		check("svv-w51-scale", "1.200", f3(scale), 0)
		check("svv-w51-stat", "10.260", f3(stat), 0) -- (1 + 0.07*2*20) * 2.70
	end

	-- ------------------------------------------------ battle setup
	do
		local b = survival({ loadout = loadout("light", 3) })
		check("svv-mode", "Survival", b.mode, 0)
		check("svv-modeOf", "Survival", Battle.modeOf(0), 0)
		check("svv-no-castle", nil, Battle.castle(b), 0)
		check("svv-wave-1", 1, b.wave, 0)
		check("svv-hell-plays-normal-hp", 1, b.difficulty.hp, 0)
		check("svv-start-food", 0, b.food, 0)
		local view = Battle.snapshot(b)
		check("svv-snapshot-wave", 1, view.wave, 0)
		check("svv-snapshot-gems", 0, view.gems, 0)
		check(
			"campaign-snapshot-no-wave",
			nil,
			Battle.snapshot(Battle.new({
				stage = 1,
				seed = 1,
				loadout = loadout(),
			})).wave,
			0
		)

		local e = Battle.spawnEnemy(b, 21, 1)
		check("svv-enemy21-hp", f3(Db.enemies[1].hp * 1.3 * 1.1), f3(e.hp), 0)
		check("svv-enemy21-ap", f3(Db.enemies[1].attackPower * 1.3 * 1.1), f3(e.ap), 0)
		local boss1 = Battle.spawnEnemy(b, 101, 0)
		check("svv-boss-hp-x0.2", f3(Db.bosses[1].hp * 1.1 * 0.2), f3(boss1.hp), 0)
		local boss10 = Battle.spawnEnemy(b, 110, 0)
		check("svv-boss10-hp-x0.5", f3(Db.bosses[10].hp * 1.1 * 0.5), f3(boss10.hp), 0)
		local boss8 = Battle.spawnEnemy(b, 108, 0)
		check("svv-boss8-ap-x0.5", f3(Db.bosses[8].attackPower * 1.1 * 0.5), f3(boss8.ap), 0)
		check("svv-boss8-hp-x0.2", f3(Db.bosses[8].hp * 1.1 * 0.2), f3(boss8.hp), 0)

		-- units: level-1 row x (1 + 0.2 (L - 1)) instead of the campaign level row (E05 B3)
		local lo = loadout()
		lo.unitLevels[1] = 5
		local u = Battle.spawnUnit(survival({ loadout = lo }), 1)
		check("svv-unit-l5-hp", f3(Db.units[1].levels.hp[1] * 1.8), f3(u.hp), 0)
		check("svv-unit-l5-ap", f3(Db.units[1].levels.ap[1] * 1.8), f3(u.ap), 0)
		local campaignUnit = Battle.spawnUnit(Battle.new({ stage = 1, seed = 1, loadout = lo }), 1)
		check("campaign-unit-l5-row", Db.units[1].levels.hp[5], campaignUnit.hp, 0)
		local shadowLo = loadout("shadow")
		shadowLo.unitLevels[1] = 3
		local sb = survival({ loadout = shadowLo })
		check("svv-shadow-mode", "Survival", sb.mode, 0)
		local result = Battle.step(sb, { commands = {} })
		check("svv-shadow-steps", nil, result.outcome, sb.tick)
	end

	-- ------------------------------------------------ kill rewards (D-SVV-04) and boss gems (E04 §2-5)
	do
		local b = survival({ loadout = loadout("light", 3) })
		local e = Battle.spawnEnemy(b, 21, 1)
		kill(b, e)
		check("svv-gold-no-statmul", math.floor(Db.enemies[1].rewardGold), b.rewards.gold, b.tick)
		check("svv-exp-x27", math.floor(Db.enemies[1].rewardExp * 27), b.exp, b.tick)
		b.tick = 900 * 30 + 5 -- past 15 minutes: the 1-gold rule does not apply in survival
		local gold = b.rewards.gold
		kill(b, Battle.spawnEnemy(b, 1, 1))
		check("svv-no-15min-rule", gold + Db.enemies[1].rewardGold, b.rewards.gold, b.tick)
		local minion = Battle.spawnEnemy(b, 1, 0)
		minion.minion = true
		gold = b.rewards.gold
		kill(b, minion)
		check("svv-minion-1-gold", gold + 1, b.rewards.gold, b.tick)
		check("svv-no-gems-for-enemy", 0, b.rewards.gems, b.tick)
		kill(b, Battle.spawnEnemy(b, 101, 0))
		check("svv-boss-gem-wave1", 1, b.rewards.gems, b.tick)
		b.wave = 60
		kill(b, Battle.spawnEnemy(b, 102, 0))
		check("svv-boss-gem-wave60", 4, b.rewards.gems, b.tick) -- 1 + (60/30 + 1)
		b.wave = 600
		kill(b, Battle.spawnEnemy(b, 103, 0))
		check("svv-boss-gem-cap-15", 19, b.rewards.gems, b.tick)
	end

	-- ------------------------------------------------ wave flow: iUCnt_ x 2 enemies, clear, interlude
	do
		local b = survival()
		Battle.hero(b).invulnTicks = 1e9
		local maxTotal, clearedAt, nextAt = 0, -1, -1
		for _ = 1, 6000 do
			advance(b)
			if b.wave == 1 then
				maxTotal = math.max(maxTotal, b.spawn.total)
				if b.waveRest > 0 and clearedAt < 0 then
					clearedAt = b.tick
				end
			elseif nextAt < 0 then
				nextAt = b.tick
				break
			end
			for _, e in enemies(b) do
				kill(b, e)
			end
		end
		check("svv-wave1-spawns-30", Db.survival[1].unitCount * 2, maxTotal, b.tick)
		check("svv-wave-cleared", true, clearedAt > 0, b.tick)
		check("svv-interlude-90", 90, nextAt - clearedAt, b.tick)
		check("svv-wave-2", 2, b.wave, b.tick)
		check("svv-wave2-row", 141, b.stage.row, b.tick)
		check("svv-spawn-reset", 0, b.spawn.total, b.tick)
		check("svv-food-carries", true, b.food > 0, b.tick)
		check("svv-no-victory", nil, b.outcome, b.tick)
		check("svv-kills-carry", maxTotal, b.rewards.killTotal, b.tick)
	end

	-- ------------------------------------------------ shadow unlock event at wave 4 (D-SVV-05)
	local function toWave(b: any, wave: number)
		Battle.hero(b).invulnTicks = 1e9
		for _ = 1, 40000 do
			if b.wave >= wave then
				return
			end
			advance(b)
			if b.darkBossId == 0 then
				for _, e in enemies(b) do
					kill(b, e)
				end
			end
		end
	end
	do
		local b = survival({ darkEvent = true })
		toWave(b, 4)
		check("dark-reached-wave4", 4, b.wave, b.tick)
		local boss = b.entities[b.darkBossId]
		check(
			"dark-boss-spawned",
			true,
			boss ~= nil and boss.kind == "Boss" and boss.n == 13,
			b.tick
		)
		check("dark-boss-raw-hp", Db.shadowBoss.hp, boss and boss.hp, b.tick)
		check("dark-snapshot-flag", true, Battle.snapshot(b).darkEvent, b.tick)
		for _ = 1, 300 do
			advance(b)
		end
		check("dark-spawn-paused", 0, b.spawn.total, b.tick)
		-- transform at <= 40% HP: attack x5 once (E02 §4.4)
		local unit = Battle.spawnUnit(b, 1)
		unit.x, unit.hp, unit.maxHp = boss.x - 40, 1e9, 1e9
		boss.hp = boss.maxHp * 0.39
		for _ = 1, 300 do
			advance(b)
			if boss.boosted then
				break
			end
		end
		check("dark-boss-transformed", true, boss.boosted, b.tick)
		check("dark-boss-attack-x5", f3(Db.shadowBoss.attackPower * 5), f3(boss.ap), b.tick)
		local gems = b.rewards.gems
		kill(b, boss)
		advance(b)
		check("dark-unlock-won", true, b.rewards.darkUnlock, b.tick)
		check("dark-boss-no-gems", gems, b.rewards.gems, b.tick)
		check("dark-boss-cleared", 0, b.darkBossId, b.tick)
		for _ = 1, 300 do
			advance(b)
		end
		check("dark-spawn-resumes", true, b.spawn.total > 0, b.tick)

		local plain = survival({ darkEvent = false })
		toWave(plain, 4)
		check("dark-none-when-unlocked", 0, plain.darkBossId, plain.tick)
		local shadowRun = survival({ darkEvent = true, loadout = loadout("shadow") })
		check("dark-none-for-shadow", false, shadowRun.darkPending, 0)
	end

	-- ------------------------------------------------ death, revive, determinism
	do
		local b = survival({ revives = 1 })
		local h = Battle.hero(b)
		kill(b, h)
		advance(b)
		check("svv-revive-offered", true, b.reviveOffer, b.tick)
		Battle.step(b, { commands = { { kind = "Revive", requestId = rid() } } })
		check("svv-revived", false, b.reviveOffer, b.tick)
		h.invulnTicks = 0
		kill(b, h)
		advance(b)
		check("svv-death-defeat", "Defeat", b.outcome, b.tick)
		check("svv-revive-count", 1, b.rewards.revives, b.tick)

		local function run(seed: number): string
			local x = survival({ seed = seed })
			for t = 1, 900 do
				advance(x, {
					commands = if t % 120 == 0
						then { { kind = "Summon", unit = 1, requestId = "s" .. t } }
						else {},
					axis = if t % 200 < 100 then 1 else 0,
				})
			end
			return Battle.digest(x)
		end
		local d1 = run(9)
		check("svv-deterministic", d1, run(9), 900)
		check("svv-seed-matters", true, d1 ~= run(10), 900)
	end

	-- ------------------------------------------------ settlement guards (pure, D-SVV-01)
	local function runProfile(heroKind: string, stage: number): any
		local p = Schema.newProfile()
		if heroKind == "shadow" then
			p.darkUnlocked = true
		end
		p.slots[1], p.currentSlot = Schema.newSlot(heroKind, 1), 1
		p.runCounter = 1
		p.activeRun = {
			ordinal = 1,
			matchId = "m-1",
			slot = 1,
			stage = stage,
			balanceHash = "h",
			startOperationId = "op-1",
		}
		return p
	end
	local function result(overrides: { [string]: any }): any
		local r: any = {
			matchId = "m-1",
			runOrdinal = 1,
			slot = 1,
			stage = 0,
			balanceHash = "h",
			seed = 1,
			outcome = "Defeat",
			elapsedTicks = 3000,
			gold = 400,
			goldSpent = 0,
			exp = 0,
			levelUps = 0,
			picks = {},
			drops = 0,
			revives = 0,
			killTotal = 10,
			quests = { false, false, false },
			wave = 5,
			gems = 3,
			darkUnlock = true,
		}
		for k, v in overrides do
			r[k] = v
		end
		return r
	end
	do
		local p = runProfile("light", 0)
		p.gems = 7
		local done, reason = Settlement.reduce(p, result({}))
		check("settle-svv-ok", nil, reason, 0)
		check("settle-svv-gems", 10, done and done.gems, 0)
		check("settle-svv-best", 5, done and done.slots[1].survivalBest, 0)
		check("settle-svv-unlock", true, done and done.darkUnlocked, 0)
		check("settle-svv-gold", 10400, done and done.slots[1].gold, 0)
		check("settle-svv-ledger-wave", 5, done and done.lastRunResult.wave, 0)
		check("settle-svv-ledger-gems", 3, done and done.lastRunResult.gems, 0)
		check("settle-svv-no-star", true, done and done.slots[1].stars[1] == 0, 0)
		check("settle-svv-valid", true, done and (Schema.validate(done)), 0)
		local again, againReason = Settlement.reduce(done, result({}))
		check("settle-svv-replay-refused", "WrongPhase", againReason, 0)
		check("settle-svv-replay-nil", nil, again, 0)
		-- a lower wave never lowers the record
		local p2 = runProfile("light", 0)
		p2.slots[1].survivalBest = 9
		local lower = Settlement.reduce(p2, result({ wave = 4, darkUnlock = false, gems = 0 }))
		check("settle-svv-best-kept", 9, lower and lower.slots[1].survivalBest, 0)
		check("settle-svv-no-unlock", false, lower and lower.darkUnlocked, 0)

		local function refused(stageProfile: any, r: any): string?
			local _, why = Settlement.reduce(stageProfile, r)
			return why
		end
		check(
			"forge-svv-victory",
			"InvalidPayload",
			refused(
				runProfile("light", 0),
				result({
					outcome = "Victory",
				})
			),
			0
		)
		check(
			"forge-svv-gems",
			"InvalidPayload",
			refused(
				runProfile("light", 0),
				result({
					gems = 11, -- 10 kills x 1 gem at wave 5
				})
			),
			0
		)
		check(
			"forge-svv-wave0",
			"InvalidPayload",
			refused(
				runProfile("light", 0),
				result({
					wave = 0,
				})
			),
			0
		)
		check(
			"forge-svv-shadow-unlock",
			"InvalidPayload",
			refused(
				runProfile("shadow", 0),
				result({
					darkUnlock = true,
				})
			),
			0
		)
		check(
			"forge-campaign-wave",
			"InvalidPayload",
			refused(
				runProfile("light", 1),
				result({
					stage = 1,
				})
			),
			0
		)
		local abandoned =
			Settlement.reduce(runProfile("light", 0), result({ outcome = "Abandoned" }))
		check("svv-abandon-no-gems", 0, abandoned and abandoned.gems, 0)
		check("svv-abandon-no-best", 0, abandoned and abandoned.slots[1].survivalBest, 0)
		check("svv-abandon-no-unlock", false, abandoned and abandoned.darkUnlocked, 0)
	end

	-- ------------------------------------------------ server flow (admission, unlock, settlement)
	local function server(store: any, sessionId: string): any
		local s = { tick = 0, now = 0, sent = {} :: { any } }
		s.profiles = env.ProfileService.new({
			store = store,
			clock = function()
				return 1000 + s.now
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			sessionId = sessionId,
			jobId = "r6",
			receiptCap = Protocol.LIMITS.receiptCap,
			queueCap = Protocol.LIMITS.profileQueueCap,
			log = function(_m: string) end,
		})
		local matches = 0
		s.match = env.MatchService.new({
			profiles = s.profiles,
			tick = function()
				return s.tick
			end,
			newMatchId = function()
				matches += 1
				return sessionId .. "-match-" .. matches
			end,
			newSeed = function()
				return 4242
			end,
			balanceHash = "remake-db-1",
			maxMatches = Protocol.LIMITS.maxMatches,
			ackCacheSize = Protocol.LIMITS.ackCacheSize,
			moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
			send = function(userId: number, message: any)
				table.insert(s.sent, { userId = userId, payload = message })
			end,
		})
		s.gateway = env.RemoteGateway.newCore({
			protocol = Protocol,
			publicCatalog = { version = "remake-db-1" },
			match = s.match,
			profiles = s.profiles,
			clock = function()
				return s.now
			end,
			tick = function()
				return s.tick
			end,
			balanceHash = "remake-db-1",
			send = function(userId: number, _channel: string, payload: any)
				table.insert(s.sent, { userId = userId, payload = payload })
			end,
		})
		function s.frame()
			s.now += 1 / 30
			s.tick += 1
			s.gateway.drain()
			s.match.stepAll()
		end
		function s.last(userId: number): any
			for index = #s.sent, 1, -1 do
				if s.sent[index].userId == userId then
					return s.sent[index].payload
				end
			end
			return nil
		end
		function s.send(userId: number, payload: { [string]: any }): string
			payload.protocolVersion = Protocol.VERSION
			payload.requestId = payload.requestId or rid()
			s.gateway.clientCommand(userId, payload)
			s.frame()
			return payload.requestId
		end
		function s.lobby(userId: number, payload: { [string]: any }): any
			s.now += 1 -- stays clear of the gateway rate limit
			payload.expectedRevision = s.profiles.profileOf(userId).revision
			s.send(userId, payload)
			return s.last(userId)
		end
		function s.profile(userId: number): any
			return s.profiles.profileOf(userId)
		end
		-- Server fixture transaction (no client path): clears stages 1..12 and sets gems.
		function s.fixture(userId: number, gems: number)
			s.profiles.transact(userId, {
				kind = "TestFixture",
				requestId = rid(),
				expectedRevision = s.profile(userId).revision,
				mutate = function(doc: any)
					local slot = doc.slots[doc.currentSlot]
					for stage = 1, 12 do
						slot.stars[stage], slot.bestSec[stage] = 1, 60
					end
					slot.stars[13] = 0
					doc.gems = gems
					return nil
				end,
			}, function() end)
		end
		return s
	end

	do
		local s = server(env.SessionStore.new(), "svv-A")
		s.gateway.playerAdded(1)
		s.gateway.playerAdded(2)
		s.frame()
		s.lobby(1, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 2 })
		s.lobby(2, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
		local locked = s.lobby(1, { kind = "StartStage", stage = 0 })
		check("flow-svv-locked-before-12", "LockedStage", locked.reason, s.tick)
		check("flow-svv-locked-no-run", nil, s.profile(1).activeRun, s.tick)
		s.fixture(1, 25)
		local started = s.lobby(1, { kind = "StartStage", stage = 0 })
		check("flow-svv-start", "Committed", started.status, s.tick)
		local fight = s.match.battleOf(1)
		check("flow-svv-battle-mode", "Survival", fight and fight.mode, s.tick)
		check("flow-svv-dark-pending", true, fight and fight.darkPending, s.tick)
		check("flow-svv-revive-offer", 1, fight and fight.revivesLeft, s.tick)
		local view = s.match.snapshot(1)
		check("flow-svv-snapshot-wave", 1, view and view.battle.wave, s.tick)
		check("flow-svv-other-no-snapshot", nil, s.match.snapshot(2), s.tick)
		local matchId = view.matchId
		-- another player cannot drive this survival run
		s.send(2, { kind = "Summon", unit = 1, lane = 0, matchId = matchId, commandSeq = 1 })
		check("flow-svv-foreign-refused", "NotOwner", s.last(2).reason, s.tick)

		-- reach a later wave and win the unlock event (server memory fixture), then die
		fight.wave, fight.rewards.gems, fight.rewards.darkUnlock = 7, 3, true
		fight.rewards.killTotal = math.max(fight.rewards.killTotal, 10)
		fight.rewards.gold = 500
		local hero = Battle.hero(fight)
		kill(fight, hero)
		s.frame()
		s.send(1, { kind = "Revive", matchId = matchId, commandSeq = 1 })
		check("flow-svv-revive", "Accepted", s.last(1).status, s.tick)
		hero.invulnTicks = 0
		kill(fight, hero)
		for _ = 1, 4 do
			s.frame()
		end
		local p = s.profile(1)
		check("flow-svv-settled", "Settled", s.match.phaseOf(1), s.tick)
		check("flow-svv-gems-revive-and-boss", 25 - 20 + 3, p.gems, s.tick)
		check("flow-svv-best", 7, p.slots[1].survivalBest, s.tick)
		check("flow-svv-unlocked", true, p.darkUnlocked, s.tick)
		check("flow-svv-gold", 10500, p.slots[1].gold, s.tick)
		check("flow-svv-run-closed", nil, p.activeRun, s.tick)
		check("flow-svv-valid", true, (Schema.validate(p)), s.tick)
		local settled = s.match.snapshot(1)
		check(
			"flow-svv-ledger-wave",
			7,
			settled and settled.rewards and settled.rewards.wave,
			s.tick
		)
		check("flow-svv-result-wave", 7, settled and settled.result.wave, s.tick)
		local revision = p.revision
		for _ = 1, 30 do
			s.frame()
		end
		check("flow-svv-settle-once", revision, s.profile(1).revision, s.tick)
		check("flow-svv-gems-once", 8, s.profile(1).gems, s.tick)
		s.send(1, { kind = "ReturnToLobby", matchId = matchId })
		check("flow-svv-lobby", "LobbyReady", s.match.phaseOf(1), s.tick)
		check("flow-svv-owner-freed", 0, s.match.ownedMatchCount(), s.tick)

		-- with the shadow hero unlocked there is no second event
		local again = s.lobby(1, { kind = "StartStage", stage = 0 })
		check("flow-svv-restart", "Committed", again.status, s.tick)
		check("flow-svv-no-second-event", false, s.match.battleOf(1).darkPending, s.tick)
	end
end
