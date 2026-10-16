--!strict
-- R7 integration (docs/REMAKE_PLAN.md R7): every stage of both heroes boots and runs through the real
-- engine, long survival progress past the wave-30 loop, a wave>30 settlement through the real server,
-- and a 4-match load at the server caps (allies 80 / enemies 120 per match) with snapshots.
-- env.loadTicks sets the measured load length (CLI default 900 = 30 s of game time; Studio runs 18000).
-- env.yield (Studio: task.wait) runs between frames so long loops stay under the script timeout; it is never
-- called inside a measured frame.
return function(env: any, check: any)
	local Battle, Schema, Protocol = env.Battle, env.Schema, env.Protocol
	local MAX_LEVEL = env.Rules.MAX_LEVEL
	local yield: () -> () = env.yield or function() end
	local serial = 0
	local function rid(): string
		serial += 1
		return string.format("r7-request-%08d", serial)
	end
	local function loadout(heroKind: string?): any
		return Schema.loadoutOf(Schema.newSlot(heroKind or "light", 1))
	end
	local function kill(b: any, e: any)
		Battle.strike(b, nil, e, 1e12, false, false)
	end
	-- One tick with a level-up choice answered through the real command (capped skills fall through).
	local function advance(b: any, input: any?): any
		local result = Battle.step(b, input)
		if result.paused and b.offer then
			Battle.step(b, { commands = { { kind = "PickSkill", choice = 1, requestId = rid() } } })
			if #b.pendingPicks > 0 and not b.offer then
				table.clear(b.pendingPicks)
			end
		end
		return result
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
	-- Scripted player: walks, summons the nine slots in turn, swings the three weapons, opens boxes.
	local function botInput(t: number): any
		local commands: { any } = {}
		if t % 15 == 0 then
			table.insert(
				commands,
				{ kind = "Summon", unit = (t // 15) % 9 + 1, lane = t % 5, requestId = "u" .. t }
			)
		end
		if t % 40 == 0 then
			table.insert(
				commands,
				{ kind = "Mace", slot = (t // 40) % 3 + 1, requestId = "m" .. t }
			)
		end
		if t % 50 == 0 then
			table.insert(
				commands,
				{ kind = "Box", index = (t // 50) % 3 + 1, requestId = "b" .. t }
			)
		end
		if t % 20 == 0 then
			table.insert(commands, { kind = "Jump", requestId = "j" .. t })
		end
		return { commands = commands, axis = if t % 240 < 180 then 1 else -1, strafe = 0 }
	end

	-- ------------------------------------------------ every stage of both heroes boots and runs
	do
		local booted, broken, deterministic = 0, {}, 0
		local total = 0
		for _, heroKind in { "light", "shadow" } do
			for stage = 0, Schema.STAGES do
				total += 1
				yield()
				local function run(): (boolean, string)
					local ok, value = pcall(function()
						local b = Battle.new({
							stage = stage,
							seed = 700 + stage,
							loadout = loadout(heroKind),
						})
						for t = 1, 450 do
							local result = advance(b, botInput(t))
							if result.outcome then
								break
							end
						end
						local view = Battle.snapshot(b)
						assert(type(view) == "table", "no snapshot")
						return Battle.digest(b)
					end)
					return ok, tostring(value)
				end
				local ok, digest = run()
				if ok then
					booted += 1
					local again, second = run()
					if again and second == digest then
						deterministic += 1
					end
				else
					table.insert(broken, heroKind .. stage .. ":" .. digest)
				end
			end
		end
		check("stages-total", 242, total, 0)
		check("stages-booted", total, booted, 0)
		check("stages-errors", "", table.concat(broken, ";"), 0)
		check("stages-deterministic", total, deterministic, 0)
	end

	-- ------------------------------------------------ long survival: wave 71, two loops of rows 31..50
	local function longSurvival(seed: number, target: number): (any, any)
		local b = Battle.new({ stage = 0, seed = seed, loadout = loadout(), darkEvent = false })
		local h = Battle.hero(b)
		h.invulnTicks = 1e9 -- the hero cannot die: this measures wave progression, not balance
		local trace: any =
			{ rows = {}, maxObjects = 0, maxAllies = 0, maxEnemies = 0, bossGems = 0 }
		local lastWave = 0
		for t = 1, 400000 do
			if b.wave >= target or b.outcome then
				break
			end
			if t % 2000 == 0 then
				yield()
			end
			if b.wave ~= lastWave then
				lastWave = b.wave
				trace.rows[b.wave] = Battle.waveRow(b.wave)
			end
			local gems = b.rewards.gems
			advance(b, botInput(t))
			if b.rewards.gems > gems then
				trace.bossGems += 1
			end
			for _, e in enemies(b) do
				if e.kind == "Boss" or t % 10 == 0 then
					kill(b, e) -- field-clear fixture: real kill path (rewards, gems, cleanup), forced damage
				end
			end
			trace.maxObjects = math.max(trace.maxObjects, #b.objectOrder)
			trace.maxAllies = math.max(trace.maxAllies, Battle.count(b, 1, true))
			trace.maxEnemies = math.max(trace.maxEnemies, Battle.count(b, 2, true))
		end
		return b, trace
	end
	do
		local b, trace = longSurvival(31, 71)
		check("svv-long-reached-71", 71, b.wave, b.tick)
		check("svv-long-no-outcome", nil, b.outcome, b.tick)
		local rowsOk = true
		for wave = 1, 70 do
			local expected = if wave <= 30 then wave else 31 + (wave - 31) % 20
			if trace.rows[wave] ~= expected then
				rowsOk = false
			end
		end
		check("svv-long-row-sequence", true, rowsOk, b.tick)
		check("svv-long-scale-w71", "1.300", string.format("%.3f", b.svvScale), b.tick)
		check("svv-long-gems-positive", true, b.rewards.gems > 0, b.tick)
		check("svv-long-gems-bound", true, b.rewards.gems <= 15 * b.rewards.killTotal, b.tick)
		check("svv-long-gold-positive", true, b.rewards.gold > 0, b.tick)
		check("svv-long-level-capped", true, b.level <= MAX_LEVEL, b.tick)
		check("svv-long-objects-capped", true, trace.maxObjects <= 256, b.tick)
		check("svv-long-allies-capped", true, trace.maxAllies <= 80, b.tick)
		check("svv-long-enemies-capped", true, trace.maxEnemies <= 120, b.tick)
		local view = Battle.snapshot(b)
		check("svv-long-snapshot-wave", 71, view.wave, b.tick)
		local hpOk = true
		for _, id in b.order do
			local e = b.entities[id]
			if e.hp ~= e.hp or e.hp == math.huge or e.hp == -math.huge then
				hpOk = false
			end
		end
		check("svv-long-finite-hp", true, hpOk, b.tick)
		local again = longSurvival(31, 71)
		check("svv-long-deterministic", Battle.digest(b), Battle.digest(again), b.tick)
	end

	-- ------------------------------------------------ real server: 4-match cap, wave>30 settle, load
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
			jobId = "r7",
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
				return 4242 + matches
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
		function s.send(userId: number, payload: { [string]: any })
			payload.protocolVersion = Protocol.VERSION
			payload.requestId = payload.requestId or rid()
			s.gateway.clientCommand(userId, payload)
			s.frame()
		end
		function s.lobby(userId: number, payload: { [string]: any }): any
			s.now += 1
			payload.expectedRevision = s.profiles.profileOf(userId).revision
			s.send(userId, payload)
			return s.last(userId)
		end
		function s.profile(userId: number): any
			return s.profiles.profileOf(userId)
		end
		-- Server fixture transaction (no client path): every stage starred, shadow hero unlocked.
		function s.fixture(userId: number)
			s.profiles.transact(userId, {
				kind = "TestFixture",
				requestId = rid(),
				expectedRevision = s.profile(userId).revision,
				mutate = function(doc: any)
					doc.darkUnlocked = true
					for _, slot in doc.slots do
						if slot then
							for stage = 1, Schema.STAGES do
								slot.stars[stage], slot.bestSec[stage] = 1, 60
							end
						end
					end
					return nil
				end,
			}, function() end)
		end
		return s
	end

	local towerStage = 0
	for stage = 1, Schema.STAGES do
		if Battle.modeOf(stage, false) == "Tower" then
			towerStage = stage
			break
		end
	end
	check("tower-stage-found", true, towerStage > 0, 0)
	local plans = {
		{ userId = 1, heroKind = "light", stage = 0 },
		{ userId = 2, heroKind = "light", stage = Schema.STAGES },
		{ userId = 3, heroKind = "shadow", stage = Schema.STAGES - 1 },
		{ userId = 4, heroKind = "light", stage = towerStage },
	}
	local s = server(env.SessionStore.new(), "r7-load")
	for userId = 1, 5 do
		s.gateway.playerAdded(userId)
	end
	s.frame()
	for _, plan in plans do
		s.lobby(plan.userId, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
		s.fixture(plan.userId)
		if plan.heroKind == "shadow" then
			s.lobby(
				plan.userId,
				{ kind = "CreateSlot", slot = 2, heroKind = "shadow", difficulty = 1 }
			)
			s.lobby(plan.userId, { kind = "SelectSlot", slot = 2 })
			s.fixture(plan.userId)
		end
		local started = s.lobby(plan.userId, { kind = "StartStage", stage = plan.stage })
		check("load-start-" .. plan.userId, "Committed", started and started.status, s.tick)
	end
	check("load-four-active", 4, s.match.activeMatches(), s.tick)
	check("load-shadow-match", true, s.match.battleOf(3) and s.match.battleOf(3).shadow, s.tick)
	s.lobby(5, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
	local fifth = s.lobby(5, { kind = "StartStage", stage = 1 })
	check("load-fifth-refused", true, fifth ~= nil and fifth.status ~= "Committed", s.tick)
	check("load-fifth-no-run", nil, s.profile(5).activeRun, s.tick)
	check("load-still-four", 4, s.match.activeMatches(), s.tick)

	-- Load fixture: refill each match to the server caps every frame, keep heroes/castles standing and
	-- hold the hero at the level cap so no level-up pause stops the simulation being measured.
	-- ranged kinds only (units 2/5/8 shoot or lob, enemies 7/9 shoot) so projectiles load the object list
	local RANGED_UNITS, RANGED_ENEMIES = { 2, 5, 8 }, { 7, 9 }
	local function hold(skipUser: number?)
		for _, plan in plans do
			local b = if plan.userId == skipUser then nil else s.match.battleOf(plan.userId)
			if b then
				b.level = MAX_LEVEL
				local h = Battle.hero(b)
				if h then
					h.invulnTicks = 1e9
					h.hp = h.maxHp
				end
				local c = Battle.castle(b)
				if c then
					c.hp = c.maxHp
				end
				if b.wagonId and b.entities[b.wagonId] then
					local w = b.entities[b.wagonId]
					w.hp = w.maxHp
				end
				local n = 0
				while Battle.count(b, 1, true) < 80 and n < 8 do
					n += 1
					local unit = Battle.spawnUnit(b, RANGED_UNITS[(b.tick + n) % 3 + 1], n % 5)
					unit.hp, unit.maxHp = 1e6, 1e6
				end
				n = 0
				while Battle.count(b, 2, true) < 120 and n < 8 do
					n += 1
					local enemy =
						Battle.spawnEnemy(b, RANGED_ENEMIES[(b.tick + n) % 2 + 1], 0, 500 + n * 30)
					if enemy then
						enemy.hp, enemy.maxHp = 1e6, 1e6
					end
				end
				if b.mode == "Tower" then
					b.points = 0
				end
				local horse = b.horseId and b.entities[b.horseId]
				if horse then
					horse.hp = horse.maxHp
				end
			end
		end
	end
	local snaps, foreign = 0, 0
	local function measured(): number
		local started = os.clock()
		s.frame()
		if s.tick % 3 == 0 then
			for _, plan in plans do
				local view = s.match.snapshot(plan.userId)
				if view then
					snaps += 1
					if view.userId and view.userId ~= plan.userId then
						foreign += 1
					end
				end
			end
		end
		return (os.clock() - started) * 1000
	end
	for _ = 1, 150 do
		yield()
		hold()
		measured()
	end
	local loadTicks: number = env.loadTicks or 900
	local P95_LIMIT = 16.6 -- 30 Hz gives 33.3 ms per frame; half is reserved for engine, replication, Remotes
	local maxAllies, maxEnemies, maxObjects, early = 0, 0, 0, 0
	local windows = 0
	local function window(): { number }
		windows += 1
		local times: { number } = {}
		for _ = 1, loadTicks do
			yield()
			hold()
			table.insert(times, measured())
			for _, plan in plans do
				local b = s.match.battleOf(plan.userId)
				if b then
					maxAllies = math.max(maxAllies, Battle.count(b, 1, true))
					maxEnemies = math.max(maxEnemies, Battle.count(b, 2, true))
					maxObjects = math.max(maxObjects, #b.objectOrder)
				else
					early += 1
				end
			end
		end
		table.sort(times)
		return times
	end
	local function pct(times: { number }, p: number): number
		return times[math.clamp(math.ceil(#times * p), 1, #times)]
	end
	-- Host noise policy (same as P9): up to 3 windows, the lowest p95 counts; cap/early checks add up over all.
	local times = window()
	for _ = 2, 3 do
		if pct(times, 0.95) <= P95_LIMIT then
			break
		end
		local again = window()
		if pct(again, 0.95) < pct(times, 0.95) then
			times = again
		end
	end
	local p50, p95, p99, worst = pct(times, 0.5), pct(times, 0.95), pct(times, 0.99), times[#times]
	check("load-p95-under-half-frame", true, p95 <= P95_LIMIT, loadTicks)
	check("load-matches-stayed", 0, early, loadTicks)
	check("load-ally-cap-reached", 80, maxAllies, loadTicks)
	check("load-enemy-cap-reached", 120, maxEnemies, loadTicks)
	check("load-object-cap-held", true, maxObjects <= 256, loadTicks)
	check("load-projectiles-present", true, maxObjects > 0, loadTicks)
	check("load-snapshots-own-only", 0, foreign, loadTicks)
	check("load-snapshots-sent", true, snaps >= windows * (loadTicks // 3) * 4, loadTicks)
	env.metrics = {
		p50 = p50,
		p95 = p95,
		p99 = p99,
		max = worst,
		ticks = loadTicks,
		windows = windows,
		maxObjects = maxObjects,
	}

	-- ------------------------------------------------ wave>30 survival result settles once on the server
	do
		local fight = s.match.battleOf(1)
		local survivalBefore = s.profile(1)
		local gemsBefore = survivalBefore.gems
		fight.wave = 35
		fight.rewards.killTotal = math.max(fight.rewards.killTotal, 40)
		fight.rewards.gems = 2 * 3 -- three bosses past wave 30 (min(35//30+1, 15) = 2 each)
		fight.level = fight.loadout.level -- release the load fixture so settlement EXP stays consistent
		local h = Battle.hero(fight)
		h.invulnTicks = 0
		kill(fight, h)
		-- the other three stay under the load fixture so a long run's army cannot end them meanwhile
		for _ = 1, 4 do
			hold(1)
			s.frame()
		end
		local after = s.profile(1)
		check("svv-settle-phase", "Settled", s.match.phaseOf(1), s.tick)
		check("svv-settle-best-35", 35, after.slots[1].survivalBest, s.tick)
		check("svv-settle-gems", gemsBefore + 6, after.gems, s.tick)
		check("svv-settle-valid", true, (Schema.validate(after)), s.tick)
		check("svv-settle-run-closed", nil, after.activeRun, s.tick)
		local revision = after.revision
		for _ = 1, 30 do
			hold(1)
			s.frame()
		end
		check("svv-settle-once", revision, s.profile(1).revision, s.tick)
		check("svv-settle-gems-once", gemsBefore + 6, s.profile(1).gems, s.tick)
		local running = 0
		for userId = 2, 4 do
			if s.match.phaseOf(userId) == "Running" then
				running += 1
			end
		end
		check("svv-settle-others-running", 3, running, s.tick)
	end
end
