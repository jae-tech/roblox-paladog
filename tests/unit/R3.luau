--!strict
-- R3 remake growth + server flow (docs/REMAKE_PLAN.md R3). Save integrity, server authority and duplicate
-- reward checks are mandatory under the test policy and are all exercised through the real services.
return function(env: any, check: any)
	local Protocol, Schema, Economy, Settlement, Battle =
		env.Protocol, env.Schema, env.Economy, env.Settlement, env.Battle
	local serial = 0
	local function rid(): string
		serial += 1
		return string.format("r3-request-%08d", serial)
	end

	-- ------------------------------------------------ schema v2 (D-SLOT-01)
	do
		local p = Schema.newProfile()
		check("schema-new-valid", true, (Schema.validate(p)), 0)
		check("schema-no-slot", 0, p.currentSlot, 0)
		local slot = Schema.newSlot("light", 1)
		check("schema-start-gold", 10000, slot.gold, 0) -- E05 B0
		check("schema-start-unit", 1, slot.units[1], 0)
		check("schema-start-weapon", Schema.encodeItem(1, 1, 0), slot.equip[1], 0)
		check("schema-stage1-open", 0, slot.stars[1], 0)
		check("schema-stage2-locked", -1, slot.stars[2], 0)
		p.slots[1], p.currentSlot = slot, 1
		check("schema-slot-valid", true, (Schema.validate(p)), 0)
		local function broken(mutate: (any) -> ()): string
			local copy = Schema.deepClone(p)
			mutate(copy)
			local ok, reason = Schema.validate(copy)
			return if ok then "valid" else tostring(reason)
		end
		check("schema-reject-points", true, broken(function(c)
			c.slots[1].skills[1] = 1
		end) ~= "valid", 0)
		check("schema-reject-level", true, broken(function(c)
			c.slots[1].exp = 100
		end) ~= "valid", 0)
		check("schema-reject-unlock-order", true, broken(function(c)
			c.slots[1].stars[3] = 0
		end) ~= "valid", 0)
		check("schema-reject-equip-category", true, broken(function(c)
			c.slots[1].equip[1] = Schema.encodeItem(2, 1, 0)
		end) ~= "valid", 0)
		check("schema-reject-item", true, broken(function(c)
			local inventory = c.slots[1].inventory
			inventory[#inventory + 1] = Schema.encodeItem(1, 12, 0)
		end) ~= "valid", 0)
		check("schema-reject-gems", true, broken(function(c)
			c.gems = -1
		end) ~= "valid", 0)
		check("schema-reject-achievement-order", true, broken(function(c)
			c.achievements = { 3, 1 }
		end) ~= "valid", 0)
		check("schema-reject-shadow-locked", true, broken(function(c)
			c.slots[2] = Schema.newSlot("shadow", 1)
		end) ~= "valid", 0)
		check("schema-reject-prerequisite", true, broken(function(c)
			c.slots[1].units[5] = 1 -- monkey needs the turtle (E05 B4)
		end) ~= "valid", 0)
		check("schema-level-curve", 3, Schema.levelFor(400), 0) -- Lv2 at 100, Lv3 at 400
		local code = Schema.encodeItem(7, 10, 55)
		local c, n, g = Schema.decodeItem(code)
		check("schema-item-roundtrip", "7/10/55", c .. "/" .. n .. "/" .. g, 0)
	end

	-- ------------------------------------------------ economy (E05 B2-B9, E03 §2)
	do
		local p = Schema.newProfile()
		check("eco-shadow-locked", "Locked", Economy.createSlot(p, 1, "shadow", 1), 0)
		check("eco-create", nil, Economy.createSlot(p, 1, "light", 1), 0)
		check("eco-slot-taken", "SlotTaken", Economy.createSlot(p, 1, "light", 2), 0)
		local slot = p.slots[1]
		check("eco-upgrade-mouse", nil, Economy.upgradeUnit(p, 1), 0)
		check("eco-mouse-cost-250", 9750, slot.gold, 0)
		check("eco-unlock-rabbit", nil, Economy.upgradeUnit(p, 2), 0)
		check("eco-rabbit-cost-2000", 7750, slot.gold, 0)
		check("eco-turtle-needs-kangaroo", "Locked", Economy.upgradeUnit(p, 6), 0)
		check("eco-monkey-needs-turtle", "Locked", Economy.upgradeUnit(p, 5), 0)
		slot.gold = 10 ^ 8
		slot.units[1] = 20
		check("eco-max-level", "MaxLevel", Economy.upgradeUnit(p, 1), 0)
		check("eco-skill-no-points", "NoPoints", Economy.learnSkill(p, 4), 0)
		slot.exp, slot.level, slot.freePoints = 100, 2, 1
		check("eco-skill-learn", nil, Economy.learnSkill(p, 4), 0)
		check("eco-skill-applied", 1, slot.skills[4], 0)
		check("eco-reset-needs-gems", "InsufficientGems", Economy.resetSkills(p), 0)
		p.gems = 1000
		check("eco-reset", nil, Economy.resetSkills(p), 0)
		check(
			"eco-reset-refund",
			"0/1/0",
			slot.skills[4] .. "/" .. slot.freePoints .. "/" .. p.gems,
			0
		)
		slot.gold = 1000
		check("eco-buy-heal-weapon", nil, Economy.buyItem(p, 1, 2), 0)
		check("eco-buy-price-500", 500, slot.gold, 0) -- A7 #8 base price
		check("eco-gold-weapon-not-sold", "InvalidPayload", Economy.buyItem(p, 1, 11), 0)
		check("eco-sell", nil, Economy.sellItem(p, 1), 0)
		check("eco-sell-half", 750, slot.gold, 0)
		check("eco-buy-again", nil, Economy.buyItem(p, 2, 4), 0) -- life ring
		check("eco-equip-third-ring-locked", "Locked", Economy.equip(p, 1, 6), 0)
		check("eco-equip-wrong-slot", "InvalidPayload", Economy.equip(p, 1, 1), 0)
		check("eco-equip-ring", nil, Economy.equip(p, 1, 4), 0)
		check("eco-equip-moves", 0, #slot.inventory, 0)
		p.gems = 10
		check("eco-enchant", nil, Economy.enchant(p, "equip", 4), 0)
		check("eco-enchant-cost", 8, p.gems, 0) -- (0+1)*2
		slot.equip[4] = Schema.encodeItem(2, 4, 5)
		check("eco-enchant-limit-5", "MaxLevel", Economy.enchant(p, "equip", 4), 0)
		check("eco-enchant-gear-refused", "InvalidPayload", Economy.enchant(p, "equip", 9), 0)
		p.gems = 1000
		check("eco-gold-pack", nil, Economy.gemShop(p, 2), 0)
		check("eco-gold-pack-amount", 100050, slot.gold, 0) -- 750 - 700 (life ring) + 100000
		p.activeRun = {
			ordinal = 1,
			matchId = "m",
			slot = 1,
			stage = 1,
			balanceHash = "h",
			startOperationId = "x",
		}
		check("eco-blocked-in-run", "WrongPhase", Economy.upgradeUnit(p, 3), 0)
	end

	-- ------------------------------------------------ protocol v2
	do
		local function cmd(fields: { [string]: any }): (any, any)
			fields.protocolVersion = fields.protocolVersion or Protocol.VERSION
			fields.requestId = fields.requestId or "protocol-test-0001"
			return Protocol.validateCommand(fields)
		end
		local ok = cmd({ kind = "Summon", matchId = "m1", commandSeq = 1, unit = 3, lane = 0 })
		check("proto-summon", "Summon", ok and ok.kind, 0)
		local _, r1 = cmd({ kind = "Summon", matchId = "m1", commandSeq = 1, unit = 10, lane = 0 })
		check("proto-unit-range", "InvalidPayload", r1, 0)
		local _, r2 =
			cmd({ kind = "Summon", matchId = "m1", commandSeq = 1, unit = 1, lane = 0, gold = 9 })
		check("proto-extra-field", "InvalidPayload", r2, 0)
		local _, r3 = cmd({
			kind = "CreateSlot",
			slot = 1,
			heroKind = "dark",
			difficulty = 1,
			expectedRevision = 0,
		})
		check("proto-hero-kind-set", "InvalidPayload", r3, 0)
		local _, r4 = cmd({ kind = "Equip", index = 1, slot = 10, expectedRevision = 0 })
		check("proto-equip-slot-range", "InvalidPayload", r4, 0)
		local _, r5 = cmd({ kind = "BuyItem", category = 1.5, num = 1, expectedRevision = 0 })
		check("proto-integer-only", "InvalidPayload", r5, 0)
		local _, r6 = cmd({ kind = "GrantGold", expectedRevision = 0 })
		check("proto-unknown-kind", "InvalidPayload", r6, 0)
		local _, r7 = cmd({ protocolVersion = 1, kind = "ResetSkills", expectedRevision = 0 })
		check("proto-version", "ProtocolMismatch", r7, 0)
		local _, r8 = cmd({ kind = "StartStage", stage = 121, expectedRevision = 0 })
		check("proto-stage-range", "InvalidPayload", r8, 0)
	end

	-- ------------------------------------------------ live server rig (gateway -> match -> profiles -> store)
	local function server(store: any, sessionId: string, seed: number?)
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
			jobId = "r3",
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
				return seed or 777
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
			payload.expectedRevision = s.profiles.profileOf(userId).revision
			s.send(userId, payload)
			return s.last(userId)
		end
		function s.profile(userId: number): any
			return s.profiles.profileOf(userId)
		end
		return s
	end

	local store = env.SessionStore.new()
	local a = server(store, "session-A")
	a.gateway.playerAdded(1)
	a.frame()
	check("flow-lobby", "LobbyReady", a.match.phaseOf(1), a.tick)
	local created =
		a.lobby(1, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
	check("flow-create-slot", "Committed", created.status, a.tick)
	check("flow-summary-slot", 10000, created.profileSummary.slots[1].gold, a.tick)
	local locked = a.lobby(1, { kind = "StartStage", stage = 2 })
	check("flow-locked-stage", "LockedStage", locked.reason, a.tick)
	check("flow-locked-stays-lobby", "LobbyReady", a.match.phaseOf(1), a.tick)

	-- duplicate lobby request: one effect only
	do
		local revision = a.profile(1).revision
		local requestId = rid()
		a.send(
			1,
			{ kind = "UpgradeUnit", unit = 1, expectedRevision = revision, requestId = requestId }
		)
		a.send(
			1,
			{ kind = "UpgradeUnit", unit = 1, expectedRevision = revision, requestId = requestId }
		)
		check("dup-lobby-once", 2, a.profile(1).slots[1].units[1], a.tick)
		check("dup-lobby-gold-once", 9750, a.profile(1).slots[1].gold, a.tick)
		local stale = a.send(1, { kind = "UpgradeUnit", unit = 1, expectedRevision = revision })
		local _ = stale
		check("stale-revision", "StaleRevision", a.last(1).reason, a.tick)
	end

	-- start stage 1 and win it by breaking the castle server-side (fixture), then settle once
	local startId =
		a.send(1, { kind = "StartStage", stage = 1, expectedRevision = a.profile(1).revision })
	check("flow-running", "Running", a.match.phaseOf(1), a.tick)
	local matchId = a.match.snapshot(1).matchId
	local battle = a.match.battleOf(1)
	check("flow-battle-light", "Normal", battle.mode, a.tick)
	check(
		"flow-lobby-blocked-in-run",
		"WrongPhase",
		a.lobby(1, { kind = "UpgradeUnit", unit = 1 }).reason,
		a.tick
	)
	a.send(1, { kind = "Summon", matchId = matchId, commandSeq = 1, unit = 1, lane = 0 })
	check("flow-summon-final", "Rejected", a.last(1).status, a.tick) -- no food at the start
	check("flow-summon-reason", "InsufficientFood", a.last(1).reason, a.tick)
	battle.food = 40
	a.send(1, { kind = "Summon", matchId = matchId, commandSeq = 2, unit = 1, lane = 0 })
	check("flow-summon-accepted", "Accepted", a.last(1).status, a.tick)
	a.send(1, { kind = "Summon", matchId = matchId, commandSeq = 2, unit = 1, lane = 0 })
	check("flow-stale-seq", "StaleCommand", a.last(1).reason, a.tick)
	-- foreign match id from another player
	a.gateway.playerAdded(2)
	a.frame()
	a.lobby(2, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
	a.send(2, { kind = "Summon", matchId = matchId, commandSeq = 1, unit = 1, lane = 0 })
	check("authority-not-owner", "NotOwner", a.last(2).reason, a.tick)
	local gold0 = a.profile(1).slots[1].gold
	for _ = 1, 30 * 20 do
		a.frame()
	end
	Battle.castle(battle).hp = 0
	for _ = 1, 3 do
		a.frame()
	end
	check("flow-settled", "Settled", a.match.phaseOf(1), a.tick)
	local profile = a.profile(1)
	local slot = profile.slots[1]
	local result = a.match.resultOf(1)
	check("flow-victory", "Victory", result.outcome, a.tick)
	check("flow-main-quest", true, result.quests[1], a.tick)
	check("flow-star", true, slot.stars[1] >= 1, a.tick)
	check("flow-unlock-2", 0, slot.stars[2], a.tick)
	check("flow-best-time", true, slot.bestSec[1] > 0, a.tick)
	local questGold = 0
	for i = 1, 3 do
		if result.quests[i] then
			questGold += env.Db.quests[1][i].gold
		end
	end
	check("flow-gold-ledger", gold0 + result.gold - result.goldSpent + questGold, slot.gold, a.tick)
	check(
		"flow-ledger-gold",
		result.gold - result.goldSpent + questGold,
		profile.lastRunResult.awardedGold,
		a.tick
	)
	check("flow-run-closed", nil, profile.activeRun, a.tick)
	local snap = a.match.snapshot(1)
	check("flow-snapshot-committed", "Committed", snap.settlementStatus, a.tick)
	check(
		"flow-snapshot-rewards",
		profile.lastRunResult.awardedGold,
		snap.rewards.awardedGold,
		a.tick
	)

	-- settlement replay: the same result applied twice is a no-op (duplicate reward guard)
	do
		local before = Schema.deepClone(a.profile(1))
		local done: any = nil
		a.profiles.finishRun(1, result, function(p, reason)
			done = { p = p, reason = reason }
		end)
		check("dup-settle-no-change", before.slots[1].gold, a.profile(1).slots[1].gold, a.tick)
		check("dup-settle-revision", before.revision, a.profile(1).revision, a.tick)
		local _ = done
		-- replayed StartStage request id cannot open a second run
		a.send(1, { kind = "ReturnToLobby", matchId = matchId })
		check("flow-back-to-lobby", "LobbyReady", a.match.phaseOf(1), a.tick)
		local runs = a.profile(1).runCounter
		a.send(1, {
			kind = "StartStage",
			stage = 1,
			expectedRevision = a.profile(1).revision,
			requestId = startId,
		})
		check("dup-start-no-new-run", runs, a.profile(1).runCounter, a.tick)
	end

	-- tampered results never reach the profile (integrity)
	do
		local p = Schema.deepClone(a.profile(1))
		p.gems = 0
		p.runCounter += 1
		p.activeRun = {
			ordinal = p.runCounter,
			matchId = "tamper",
			slot = 1,
			stage = 1,
			balanceHash = "remake-db-1",
			startOperationId = "t",
		}
		local base = {
			matchId = "tamper",
			runOrdinal = p.runCounter,
			slot = 1,
			stage = 1,
			balanceHash = "remake-db-1",
			seed = 1,
			outcome = "Victory",
			elapsedTicks = 900,
			gold = 10,
			goldSpent = 0,
			exp = 0,
			levelUps = 0,
			picks = {},
			drops = 0,
			revives = 0,
			killTotal = 1,
			quests = { true, false, false },
		}
		local function try(over: { [string]: any }): any
			local r = table.clone(base)
			for k, v in over do
				r[k] = v
			end
			local _, reason = Settlement.reduce(p, r)
			return reason
		end
		check("tamper-identity", "WrongPhase", try({ matchId = "other" }), 0)
		check("tamper-levelups", "InvalidPayload", try({ levelUps = 3 }), 0)
		check("tamper-gold-spent", "InvalidPayload", try({ goldSpent = 10 ^ 8 }), 0)
		check("tamper-picks", "InvalidPayload", try({ exp = 100, levelUps = 1, picks = { 99 } }), 0)
		check("tamper-outcome", "InvalidPayload", try({ outcome = "Win" }), 0)
		check("tamper-negative", "InvalidPayload", try({ gold = -5 }), 0)
		check("tamper-revive-gems", "InvalidPayload", try({ revives = 1 }), 0)
		check(
			"tamper-no-main-quest",
			"InvalidPayload",
			try({ quests = { false, false, false } }),
			0
		)
		local ok = Settlement.reduce(p, base)
		check("tamper-baseline-ok", true, ok ~= nil, 0)
		local unpicked = Settlement.reduce(
			p,
			(function()
				local r = table.clone(base)
				r.exp, r.levelUps = 100, 1
				return r
			end)()
		)
		check("levelup-unpicked-free-point", 1, unpicked and unpicked.slots[1].freePoints, 0)
	end

	-- leaving mid-run closes the run as Abandoned with no reward on the next load
	do
		a.send(1, { kind = "StartStage", stage = 1, expectedRevision = a.profile(1).revision })
		check("abandon-running", "Running", a.match.phaseOf(1), a.tick)
		local runningBattle = a.match.battleOf(1)
		runningBattle.rewards.gold = 5000
		local goldBefore = a.profile(1).slots[1].gold
		a.gateway.playerRemoving(1)
		a.frame()
		a.gateway.playerAdded(1)
		a.frame()
		local reloaded = a.profile(1)
		check("abandon-closed", nil, reloaded.activeRun, a.tick)
		check("abandon-outcome", "Abandoned", reloaded.lastRunResult.outcome, a.tick)
		check("abandon-no-gold", goldBefore, reloaded.slots[1].gold, a.tick)
		check("abandon-owner-freed", 0, a.match.ownedMatchCount(), a.tick)
	end

	-- modes not wired yet are refused before any run opens
	do
		local zero = a.lobby(1, { kind = "StartStage", stage = 0 })
		check("survival-not-yet", "WrongMode", zero.reason, a.tick)
	end

	-- revive costs 20 gems at settlement; a defeat keeps kill gold and EXP
	do
		local p = a.profile(1)
		local store2 = env.SessionStore.new()
		local b = server(store2, "session-B")
		b.gateway.playerAdded(5)
		b.frame()
		b.lobby(5, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
		local _ = p
		-- grant gems through a server fixture transaction (no client path exists)
		b.profiles.transact(5, {
			kind = "TestGems",
			requestId = rid(),
			expectedRevision = b.profile(5).revision,
			mutate = function(doc: any)
				doc.gems = 25
				return nil
			end,
		}, function() end)
		b.send(5, { kind = "StartStage", stage = 1, expectedRevision = b.profile(5).revision })
		local fight = b.match.battleOf(5)
		check("revive-offered-with-gems", 1, fight.revivesLeft, b.tick)
		local mid = b.match.snapshot(5).matchId
		local hero = Battle.hero(fight)
		Battle.strike(fight, nil, hero, 1e9, false, false)
		b.frame()
		b.send(5, { kind = "Revive", matchId = mid, commandSeq = 1 })
		check("revive-accepted", "Accepted", b.last(5).status, b.tick)
		fight.rewards.gold = 77
		hero.invulnTicks = 0
		Battle.strike(fight, nil, hero, 1e9, false, false)
		for _ = 1, 4 do
			b.frame()
		end
		check("revive-defeat-settled", "Settled", b.match.phaseOf(5), b.tick)
		check("revive-gems-charged", 5, b.profile(5).gems, b.tick)
		check("defeat-keeps-kill-gold", 10077, b.profile(5).slots[1].gold, b.tick)
		check("defeat-no-star", 0, b.profile(5).slots[1].stars[1], b.tick)
	end

	-- ------------------------------------------------ attack matrix vs. an untouched control (server authority)
	do
		local attacked, control =
			server(env.SessionStore.new(), "atk"), server(env.SessionStore.new(), "ctl")
		for _, s in { attacked, control } do
			for userId = 1, 2 do
				s.gateway.playerAdded(userId)
				s.frame()
				s.lobby(
					userId,
					{ kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 }
				)
				s.now += 1
				s.send(userId, {
					kind = "StartStage",
					stage = 1,
					expectedRevision = s.profile(userId).revision,
				})
			end
			for _ = 1, 150 do
				s.frame()
			end
			s.send(1, {
				kind = "Summon",
				matchId = s.match.snapshot(1).matchId,
				commandSeq = 5,
				unit = 1,
				lane = 0,
			})
		end
		local mine, theirs = attacked.match.snapshot(1).matchId, attacked.match.snapshot(2).matchId
		local deep: any = {}
		deep.self = deep
		local attacks: { [string]: any } = {
			extraHp = {
				kind = "Summon",
				matchId = mine,
				commandSeq = 6,
				unit = 1,
				lane = 0,
				hp = 1,
			},
			extraGold = { kind = "UpgradeUnit", unit = 1, expectedRevision = 0, gold = 999 },
			unitNaN = { kind = "Summon", matchId = mine, commandSeq = 6, unit = 0 / 0, lane = 0 },
			unitInf = {
				kind = "Summon",
				matchId = mine,
				commandSeq = 6,
				unit = math.huge,
				lane = 0,
			},
			unitNegative = { kind = "Summon", matchId = mine, commandSeq = 6, unit = -1, lane = 0 },
			unitFraction = { kind = "Summon", matchId = mine, commandSeq = 6, unit = 1.5, lane = 0 },
			unitOutOfRange = {
				kind = "Summon",
				matchId = mine,
				commandSeq = 6,
				unit = 10,
				lane = 0,
			},
			laneOutOfRange = { kind = "Summon", matchId = mine, commandSeq = 6, unit = 1, lane = 6 },
			seqNaN = { kind = "Summon", matchId = mine, commandSeq = 0 / 0, unit = 1, lane = 0 },
			longMatchId = {
				kind = "Summon",
				matchId = string.rep("a", 65),
				commandSeq = 6,
				unit = 1,
				lane = 0,
			},
			hugeRequestId = {
				kind = "Summon",
				matchId = mine,
				commandSeq = 6,
				unit = 1,
				lane = 0,
				requestId = string.rep("r", 100000),
			},
			nested = { kind = "Summon", matchId = mine, commandSeq = 6, unit = { 1 }, lane = 0 },
			cyclic = { kind = "Summon", matchId = mine, commandSeq = 6, unit = deep, lane = 0 },
			unknownKind = { kind = "GrantGold", matchId = mine, commandSeq = 6, unit = 1 },
			unknownStage = { kind = "StartStage", stage = 999, expectedRevision = 0 },
			foreignMatch = { kind = "Summon", matchId = theirs, commandSeq = 6, unit = 1, lane = 0 },
			foreignMace = {
				kind = "Mace",
				matchId = theirs,
				commandSeq = 7,
				slot = 1,
				unit = 0,
				lane = 0,
			},
			pastSeq = { kind = "Summon", matchId = mine, commandSeq = 3, unit = 1, lane = 0 },
			replaySeq = { kind = "Summon", matchId = mine, commandSeq = 5, unit = 1, lane = 0 },
			upgradeInBattle = { kind = "UpgradeUnit", unit = 1, expectedRevision = 0 },
			gemsInBattle = { kind = "GemShop", item = 2, expectedRevision = 0 },
		}
		local names: { string } = {}
		for name in attacks do
			table.insert(names, name)
		end
		table.sort(names) -- deterministic ingress order across runs
		for _, name in names do
			attacked.now += 0.2 -- inside the discrete bucket: judged, not rate-dropped
			local payload = attacks[name]
			payload.protocolVersion = Protocol.VERSION
			payload.requestId = payload.requestId or rid()
			check(
				"attack-no-throw-" .. name,
				true,
				(pcall(attacked.gateway.clientCommand, 1, payload)),
				attacked.tick
			)
		end
		local raws: { any } = {
			"x",
			5,
			true,
			{},
			{ protocolVersion = Protocol.VERSION, requestId = rid(), kind = "Summon" },
		}
		for index, raw in raws do
			attacked.now += 0.2
			check(
				"attack-raw-no-throw-" .. index,
				true,
				(pcall(attacked.gateway.clientCommand, 1, raw)),
				0
			)
		end
		for index, move in
			{
				{ matchId = mine, seq = 1, axis = 5 },
				{ matchId = mine, seq = 0 / 0, axis = 1 },
				{ matchId = mine, seq = 1, axis = 0 / 0 },
				{ matchId = theirs, seq = 1, axis = 1 },
				{ matchId = mine, seq = 1, axis = 1, x = 80 },
			}
		do
			(move :: any).protocolVersion = Protocol.VERSION
			check(
				"attack-move-" .. index,
				false,
				attacked.gateway.moveIntent(1, move),
				attacked.tick
			)
		end
		attacked.frame()
		control.frame()
		for userId = 1, 2 do
			check(
				"attack-battle-unchanged-" .. userId,
				Battle.digest(control.match.battleOf(userId)),
				Battle.digest(attacked.match.battleOf(userId)),
				attacked.tick
			)
			local pa, pc = attacked.profile(userId), control.profile(userId)
			check(
				"attack-gold-unchanged-" .. userId,
				pc.slots[1].gold,
				pa.slots[1].gold,
				attacked.tick
			)
			check("attack-gems-unchanged-" .. userId, pc.gems, pa.gems, attacked.tick)
			check("attack-revision-unchanged-" .. userId, pc.revision, pa.revision, attacked.tick)
		end
		local victimRejects = 0
		local notOwner = 0
		for _, entry in attacked.sent do
			if entry.userId == 2 and entry.payload.status == "Rejected" then
				victimRejects += 1
			elseif entry.userId == 1 and entry.payload.reason == "NotOwner" then
				notOwner += 1
			end
		end
		check("attack-no-reply-to-victim", 0, victimRejects, attacked.tick)
		check("attack-not-owner-reported", 2, notOwner, attacked.tick)
		local rejects = attacked.gateway.rejectCounts(1)
		check("attack-invalid-reported", true, (rejects.InvalidPayload or 0) >= 10, attacked.tick)
		check("attack-no-rate-drops", 0, rejects.RateLimited or 0, attacked.tick)
	end

	-- ------------------------------------------------ 100 match create/end cycles return to baseline
	do
		local cyc = server(env.SessionStore.new(), "cycle")
		cyc.gateway.playerAdded(1)
		cyc.frame()
		cyc.lobby(1, { kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 1 })
		local cycles = 100
		for _ = 1, cycles do
			cyc.now += 1 -- human pacing: faster starts would be (correctly) rate-dropped by the gateway
			cyc.send(
				1,
				{ kind = "StartStage", stage = 1, expectedRevision = cyc.profile(1).revision }
			)
			local fight = cyc.match.battleOf(1)
			if not fight then
				break
			end
			Battle.castle(fight).hp = 0 -- outcome fixture: this measures lifecycle cleanup, not gameplay
			cyc.frame()
			cyc.send(1, { kind = "ReturnToLobby", matchId = cyc.match.resultOf(1).matchId })
		end
		local after = cyc.profile(1)
		check("cycles-all-closed", cycles, after.lastClosedRunOrdinal, cyc.tick)
		check("cycles-lobby", "LobbyReady", cyc.match.phaseOf(1), cyc.tick)
		check("cycles-no-active-match", 0, cyc.match.activeMatches(), cyc.tick)
		check("cycles-no-owned-match", 0, cyc.match.ownedMatchCount(), cyc.tick)
		check("cycles-battle-released", nil, cyc.match.battleOf(1), cyc.tick)
		check("cycles-result-released", nil, cyc.match.resultOf(1), cyc.tick)
		check("cycles-no-snapshot", nil, cyc.match.snapshot(1), cyc.tick)
		check("cycles-run-closed", nil, after.activeRun, cyc.tick)
		check(
			"cycles-receipts-bounded",
			true,
			#after.recentOperations <= Protocol.LIMITS.receiptCap,
			cyc.tick
		)
		check("cycles-profile-valid", true, (Schema.validate(after)), cyc.tick)
	end
end
