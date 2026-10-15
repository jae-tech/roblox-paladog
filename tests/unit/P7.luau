--!strict
-- Economic regressions prepared without execution during the user's verification pause.
return function(env: any, check: any)
	local Schema, Growth, Reducer = env.Schema, env.Growth, env.ResultReducer
	local function opened(profile: any?): any
		local p = if profile then Schema.deepClone(profile) else Schema.newProfile()
		p.runCounter += 1
		p.activeRun = {
			ordinal = p.runCounter,
			matchId = "run-" .. p.runCounter,
			stageId = "s01",
			balanceHash = env.Catalog.balanceHash,
			startOperationId = "start-" .. p.runCounter,
		}
		return p
	end
	local function resultFor(p: any, outcome: string): any
		return {
			matchId = p.activeRun.matchId,
			runOrdinal = p.activeRun.ordinal,
			stageId = "s01",
			balanceHash = env.Catalog.balanceHash,
			seed = 12345,
			outcome = outcome,
			elapsedTicks = 100,
			killCounts = { scrapper = 2 },
			pendingKillGold = 36,
			pendingKillXp = 24,
		}
	end
	local original = opened()
	local result = resultFor(original, "Victory")
	local won = Reducer.reduce(original, result)
	check("victory-kill-stage-first-gold", 236, won.gold, 0)
	check("victory-kill-stage-xp", 84, won.totalXp, 0)
	check("pure-input-not-mutated", 0, original.gold + original.stageProgress.s01.wins, 0)
	check("pure-input-run-retained", true, original.activeRun ~= nil, 0)
	check("actual-gold-ledger", 236, won.lastRunResult.awardedGold, 0)
	check("closed-run", nil, won.activeRun, 0)
	check("closed-run-cannot-reduce-twice", nil, Reducer.reduce(won, result), 0)
	local nextRun = opened(won)
	local later = resultFor(nextRun, "Victory")
	later.elapsedTicks = 200
	local wonAgain = Reducer.reduce(nextRun, later)
	check("first-bonus-once", 136, wonAgain.lastRunResult.awardedGold, 0)
	check("best-ticks-minimum", 100, wonAgain.stageProgress.s01.bestTicks, 0)
	check("win-count", 2, wonAgain.stageProgress.s01.wins, 0)
	check("summary-unlocks-s02", true, Schema.summary(won).unlockedStages.s02, 0)
	check("summary-keeps-s03-locked", false, Schema.summary(won).unlockedStages.s03, 0)
	for _, outcome in { "Defeat", "Timeout", "Abandoned" } do
		local closed = Reducer.reduce(original, resultFor(original, outcome))
		check(outcome .. "-no-rewards", 0, closed.gold + closed.totalXp, 0)
		check(outcome .. "-no-unlock", 0, closed.stageProgress.s01.wins, 0)
		check(outcome .. "-closes-run", nil, closed.activeRun, 0)
	end
	local bad = resultFor(original, "Victory")
	bad.pendingKillGold += 1
	local rejected, reason = Reducer.reduce(original, bad)
	check("kill-ledger-mismatch-rejected", nil, rejected, 0)
	check("kill-ledger-mismatch-reason", "InvalidPayload", reason, 0)
	bad = resultFor(original, "Victory")
	bad.matchId = "other-run"
	check("foreign-result-rejected", nil, Reducer.reduce(original, bad), 0)
	bad = resultFor(original, "Victory")
	bad.killCounts = { unknown = 2 }
	check("unknown-enemy-rejected", nil, Reducer.reduce(original, bad), 0)
	bad = resultFor(original, "Victory")
	bad.killCounts.scrapper = -2
	check("negative-kill-count-rejected", nil, Reducer.reduce(original, bad), 0)

	local p = Schema.newProfile()
	Growth.award(p, 0, 400)
	check("xp-400-level-3", 3, p.heroLevel, 0)
	check("xp-400-two-points", 2, p.unspentPoints, 0)
	check("xp-not-consumed", 400, p.totalXp, 0)
	check("next-cumulative-threshold", 900, Schema.summary(p).nextLevelXp, 0)
	Growth.allocatePoint(p, "vitality")
	Growth.allocatePoint(p, "provisions")
	check(
		"point-conservation",
		2,
		p.heroTraits.vitality + p.heroTraits.provisions + p.unspentPoints,
		0
	)
	check("no-free-points", "NoPoints", Growth.allocatePoint(p, "focus"), 0)
	local world =
		env.World.new({ stageId = "s01", heroTraits = p.heroTraits, unitLevels = p.unitLevels })
	check("next-match-hp-growth", 2200, world.entities[world.heroId].maxHp, 0)
	check("next-match-food-growth", 2250, world.resources.foodRateMilli, 0)
	Growth.award(p, 1000, 2100)
	for _ = 1, 2 do
		Growth.allocatePoint(p, "vitality")
	end
	check("trait-cap-three", "MaxLevel", Growth.allocatePoint(p, "vitality"), 0)
	check("running-world-snapshot-unchanged", 2200, world.entities[world.heroId].maxHp, 0)
	check("unit-l1-next-row-cost", 25, Schema.summary(p).unitUpgradeCosts.vanguard, 0)
	Growth.upgradeUnit(p, "vanguard")
	check("unit-next-row-charge", 975, p.gold, 0)
	for _ = 1, 3 do
		Growth.upgradeUnit(p, "vanguard")
	end
	check("unit-max-five", 5, p.unitLevels.vanguard, 0)
	check("unit-cap-no-next-price", nil, Schema.summary(p).unitUpgradeCosts.vanguard, 0)
	local before = p.gold
	check("unit-max-rejected", "MaxLevel", Growth.upgradeUnit(p, "vanguard"), 0)
	check("unit-max-no-charge", before, p.gold, 0)
	local poor = Schema.newProfile()
	check("insufficient-gold", "InsufficientGold", Growth.upgradeUnit(poor, "vanguard"), 0)
	check("insufficient-gold-no-level", 1, poor.unitLevels.vanguard, 0)
	local high = Schema.newProfile()
	Growth.award(high, env.Config.progression.goldMax - 3, env.Config.progression.totalXpMax - 5)
	local capped = opened(high)
	local saturated = Reducer.reduce(capped, resultFor(capped, "Victory"))
	check("gold-saturation-actual-ledger", 3, saturated.lastRunResult.awardedGold, 0)
	check("xp-saturation-actual-ledger", 5, saturated.lastRunResult.awardedXp, 0)
	check("hero-cap-ten", 10, saturated.heroLevel, 0)
	check("hero-cap-nine-points", 9, saturated.unspentPoints, 0)
	check("saturated-profile-valid", true, Schema.validate(saturated), 0)

	local store = env.newStore()
	local funded = Schema.newProfile()
	Growth.award(funded, 50, 400)
	store.setRaw(1, funded)
	local jobs: { () -> () } = {}
	local function flush()
		local n = 0
		while #jobs > 0 do
			n += 1
			assert(n <= 100, "bounded profile queue")
			local fn = table.remove(jobs, 1) :: () -> ()
			fn()
		end
	end
	local profiles = env.ProfileService.new({
		store = store,
		clock = function()
			return 0
		end,
		spawn = function(fn: () -> ())
			table.insert(jobs, fn)
		end,
		sessionId = "growth",
		jobId = "cli",
		receiptCap = 64,
		queueCap = 4,
		log = function(_s: string) end,
	})
	local messages: { any } = {}
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return 0
		end,
		newMatchId = function()
			return "growth-match"
		end,
		balanceHash = env.Catalog.balanceHash,
		maxMatches = 4,
		ackCacheSize = 128,
		moveTtlTicks = 10,
		stageFlow = true,
		send = function(_id: number, message: any)
			table.insert(messages, message)
		end,
	})
	match.playerJoined(1)
	flush()
	local op = {
		kind = "UpgradeUnit",
		requestId = "upgrade-operation-0001",
		unitId = "vanguard",
		expectedRevision = 0,
	}
	match.handleCommand(1, op)
	check("growth-pending-ack", "Pending", messages[#messages].status, 0)
	match.handleCommand(1, {
		kind = "UpgradeUnit",
		requestId = "upgrade-operation-0002",
		unitId = "vanguard",
		expectedRevision = 0,
	})
	flush()
	check("same-revision-one-purchase", 25, profiles.profileOf(1).gold, 0)
	check("same-revision-level-once", 2, profiles.profileOf(1).unitLevels.vanguard, 0)
	check("stale-purchase-rejected", "StaleRevision", messages[#messages].reason, 0)
	check("stale-summary-refresh", 25, messages[#messages].profileSummary.gold, 0)
	match.handleCommand(1, op)
	flush()
	check("same-operation-no-double-charge", 25, profiles.profileOf(1).gold, 0)
	check("same-operation-revision-once", 1, profiles.profileOf(1).revision, 0)
	match.handleCommand(1, {
		kind = "AllocatePoint",
		requestId = "trait-operation-00001",
		traitId = "vitality",
		expectedRevision = 1,
	})
	flush()
	match.handleCommand(1, {
		kind = "StartStage",
		requestId = "start-operation-00001",
		stageId = "s01",
		expectedRevision = 2,
	})
	flush()
	check("growth-next-match-hp", 2200, match.worldOf(1).entities[match.worldOf(1).heroId].maxHp, 0)
	check("growth-next-match-unit-level", 2, match.worldOf(1).unitLevels.vanguard, 0)
	match.handleCommand(1, {
		kind = "UpgradeUnit",
		requestId = "running-operation-01",
		unitId = "vanguard",
		expectedRevision = 3,
	})
	check("running-upgrade-rejected", "WrongPhase", messages[#messages].reason, 0)
	match.handleCommand(1, {
		kind = "AllocatePoint",
		requestId = "running-operation-02",
		traitId = "focus",
		expectedRevision = 3,
	})
	check("running-trait-rejected", "WrongPhase", messages[#messages].reason, 0)
	local finished = resultFor(profiles.profileOf(1), "Victory")
	profiles.finishRun(1, finished, function() end)
	flush()
	local after = profiles.profileOf(1)
	local balance, revision = after.gold, after.revision
	profiles.finishRun(1, finished, function() end)
	flush()
	check("result-retry-no-double-award", balance, profiles.profileOf(1).gold, 0)
	check("result-retry-no-extra-revision", revision, profiles.profileOf(1).revision, 0)
	check("result-retry-first-win-once", 1, profiles.profileOf(1).stageProgress.s01.wins, 0)

	local outbound: { any } = {}
	local seq = 0
	local client = env.ClientController.new({
		protocol = env.Protocol,
		catalog = env.Catalog,
		requestId = function()
			seq += 1
			return string.format("client-operation-%016d", seq)
		end,
		send = function(_channel: string, payload: any)
			table.insert(outbound, payload)
		end,
	})
	client.finishBootstrap(client.beginBootstrap(0), {
		protocolVersion = 1,
		balanceHash = env.Catalog.balanceHash,
		status = "Ready",
		phase = "LobbyReady",
		profileRevision = 0,
		profileSummary = Schema.summary(funded),
	}, 0)
	check("client-growth-action", true, client.action("Upgrade_vanguard", 0), 0)
	check("client-no-predicted-spend", 50, client.model(0).profileSummary.gold, 0)
	check("client-serial-growth-ui", false, client.action("Trait_focus", 0), 0)
	check("client-start-locked-during-purchase", false, client.action("Start_s01", 0), 0)
	check("client-no-gold-payload", nil, outbound[1].gold, 0)
	check("client-protocol-valid", true, env.Protocol.validateCommand(outbound[1]) ~= nil, 0)
	client.receiveMessage({
		requestId = outbound[1].requestId,
		status = "Rejected",
		reason = "StaleRevision",
		profileRevision = revision,
		profileSummary = Schema.summary(after),
	}, 0)
	check("client-stale-refresh", balance, client.model(0).profileSummary.gold, 0)
	check("client-no-auto-respend", 1, #outbound, 0)
	check("client-busy-cleared", false, client.model(0).profileBusy, 0)
	client.action("Trait_focus", 0)
	check("client-timeout-refresh", true, client.needsBootstrap(3.1), 0)
	client.finishBootstrap(client.beginBootstrap(3.1), {
		protocolVersion = 1,
		balanceHash = env.Catalog.balanceHash,
		status = "Ready",
		phase = "LobbyReady",
		profileRevision = revision,
		profileSummary = Schema.summary(after),
	}, 3.1)
	check("client-refresh-clears-ui-wait", false, client.model(3.1).profileBusy, 0)
end
