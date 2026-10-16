--!strict
-- P2 suite: protocol allowlist (T-SEC-01/02/03/04), owner isolation (T-ISOLATION core), profile store contract.
-- Modules are injected so the same suite runs in the Luau CLI and in Studio.
type Check = (string, unknown, unknown, number) -> ()

local REQ = "req-0000000000000"

-- Stable deep encoding for whole-document equality checks.
local function encode(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local item = value[key]
		if item == nil then
			item = value[tonumber(key)]
		end
		table.insert(parts, key .. "=" .. encode(item))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

return function(env: any, check: Check)
	local Protocol = env.Protocol

	-- ---------------------------------------------------------------- protocol allowlist
	local function summon(extra: { [string]: any }?): { [string]: any }
		local payload: { [string]: any } = {
			protocolVersion = 1,
			requestId = REQ .. "1",
			kind = "Summon",
			matchId = "m1",
			commandSeq = 1,
			slot = 2,
		}
		if extra then
			for key, value in extra do
				payload[key] = value
			end
		end
		return payload
	end
	local function reasonOf(payload: any): string?
		local command, reason = Protocol.validateCommand(payload)
		return if command then "OK" else reason
	end

	check("protocol-valid-summon", "OK", reasonOf(summon()), 0)
	check("protocol-command-frozen", true, table.isfrozen(Protocol.validateCommand(summon())), 0)
	for _, field in { "hp", "attackPower", "gold", "target", "x", "userId", "price" } do
		check(
			"tsec01-reject-field-" .. field,
			"InvalidPayload",
			reasonOf(summon({ [field] = 1 })),
			0
		)
	end
	local bad: { [string]: any } = {
		["nan-slot"] = { slot = 0 / 0 },
		["inf-seq"] = { commandSeq = math.huge },
		["negative-seq"] = { commandSeq = -1 },
		["fractional-slot"] = { slot = 1.5 },
		["slot-out-of-range"] = { slot = 4 },
		["long-request-id"] = { requestId = string.rep("a", 65) },
		["short-request-id"] = { requestId = "short" },
		["non-ascii-request-id"] = { requestId = REQ .. "한" },
		["nested-table"] = { matchId = { "m1" } },
		["boolean-value"] = { slot = true },
		["string-number"] = { slot = "2" },
		["unknown-kind"] = { kind = "GrantReward" },
	}
	for name, extra in bad do
		check("tsec02-" .. name, "InvalidPayload", reasonOf(summon(extra)), 0)
	end
	check("tsec02-not-a-table", "InvalidPayload", reasonOf("Summon"), 0)
	check("tsec02-array-keys", "InvalidPayload", reasonOf({ 1, 2, 3 }), 0)
	local huge = summon()
	for index = 1, 10000 do
		huge["k" .. index] = index
	end
	check("tsec02-huge-table-bounded", "InvalidPayload", reasonOf(huge), 0)
	check(
		"protocol-version-mismatch",
		"ProtocolMismatch",
		reasonOf(summon({ protocolVersion = 2 })),
		0
	)
	check(
		"protocol-version-string",
		"InvalidPayload",
		reasonOf(summon({ protocolVersion = "1" })),
		0
	)
	check(
		"protocol-cast-slot-1-only",
		"InvalidPayload",
		reasonOf(summon({ kind = "Cast", slot = 2 })),
		0
	)
	local start = {
		protocolVersion = 1,
		requestId = REQ .. "s",
		kind = "StartStage",
		stageId = "s09",
		expectedRevision = 0,
	}
	check("protocol-unknown-stage", "InvalidPayload", reasonOf(start), 0)
	check(
		"protocol-move-valid",
		true,
		Protocol.validateMove({ protocolVersion = 1, matchId = "m1", seq = 1, axis = -1 }) ~= nil,
		0
	)
	check(
		"protocol-move-fractional-axis",
		nil,
		Protocol.validateMove({ protocolVersion = 1, matchId = "m1", seq = 1, axis = 0.5 }),
		0
	)
	check(
		"protocol-move-extra-field",
		nil,
		Protocol.validateMove({ protocolVersion = 1, matchId = "m1", seq = 1, axis = 1, x = 5 }),
		0
	)
	check("protocol-bootstrap-valid", nil, Protocol.validateBootstrap({ protocolVersion = 1 }), 0)
	check(
		"protocol-bootstrap-extra",
		"InvalidPayload",
		Protocol.validateBootstrap({ protocolVersion = 1, a = 1 }),
		0
	)
	check(
		"protocol-echo-bounded",
		"",
		Protocol.echoRequestId({ requestId = string.rep("x", 1000) }),
		0
	)

	-- ---------------------------------------------------------------- world helper
	local function world(options: { [string]: any }?)
		local opts: { [string]: any } = options or {}
		local w: { [string]: any } =
			{ wall = 1000, now = 0, tick = 0, sent = {}, matchCount = 0, tasks = {} }
		w.store = opts.store or env.newStore()
		w.profiles = env.ProfileService.new({
			store = w.store,
			clock = function()
				return w.wall
			end,
			spawn = function(fn)
				if opts.deferred then
					table.insert(w.tasks, fn)
				else
					fn()
				end
			end,
			sessionId = opts.sessionId or "session-A",
			jobId = "job-1",
			receiptCap = opts.receiptCap or Protocol.LIMITS.receiptCap,
			queueCap = opts.queueCap or Protocol.LIMITS.profileQueueCap,
			log = function() end,
		})
		local function send(userId: number, channel: string, payload: any)
			table.insert(w.sent, { userId = userId, channel = channel, payload = payload })
		end
		w.match = env.MatchService.new({
			profiles = w.profiles,
			tick = function()
				return w.tick
			end,
			newMatchId = function()
				w.matchCount += 1
				return "match-" .. w.matchCount
			end,
			balanceHash = "hash",
			send = function(userId: number, message: any)
				send(userId, "ServerMessage", message)
			end,
			maxMatches = Protocol.LIMITS.maxMatches,
			ackCacheSize = Protocol.LIMITS.ackCacheSize,
			moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
		})
		w.gateway = env.RemoteGateway.newCore({
			protocol = Protocol,
			publicCatalog = env.Catalog,
			match = w.match,
			profiles = w.profiles,
			clock = function()
				return w.now
			end,
			tick = function()
				return w.tick
			end,
			balanceHash = "hash",
			send = send,
		})
		function w.command(userId: number, payload: any)
			w.gateway.clientCommand(userId, payload)
			w.gateway.drain()
		end
		-- Deferred mode: run queued store work in a chosen order to reproduce async interleavings.
		function w.run(index: number?)
			local fn: (() -> ())? = table.remove(w.tasks, index or 1)
			if fn then
				fn()
			end
		end
		function w.runAll()
			while #w.tasks > 0 do
				w.run(1)
			end
		end
		function w.last(userId: number): any
			for index = #w.sent, 1, -1 do
				local entry = w.sent[index]
				if entry.userId == userId and entry.channel == "ServerMessage" then
					return entry.payload
				end
			end
			return nil
		end
		function w.start(userId: number, stageId: string, id: string, revision: number?)
			w.command(userId, {
				protocolVersion = 1,
				requestId = REQ .. id,
				kind = "StartStage",
				stageId = stageId,
				expectedRevision = revision or 0,
			})
			return w.last(userId)
		end
		function w.battle(
			userId: number,
			kind: string,
			matchId: string,
			seq: number,
			id: string,
			slot: number?
		)
			w.now += 0.2 -- stay inside the discrete token budget
			w.command(userId, {
				protocolVersion = 1,
				requestId = REQ .. id,
				kind = kind,
				matchId = matchId,
				commandSeq = seq,
				slot = slot or 1,
			})
			return w.last(userId)
		end
		return w
	end

	-- ---------------------------------------------------------------- bootstrap
	local w = world()
	w.gateway.playerAdded(1)
	check("profile-new-lobby", "LobbyReady", w.match.phaseOf(1), 0)
	local thread = coroutine.create(w.gateway.getBootstrap)
	local resumed, boot = coroutine.resume(thread, 1, { protocolVersion = 1 })
	check("bootstrap-no-yield", "dead", coroutine.status(thread), 0)
	check("bootstrap-ready", "Ready", resumed and boot.status, 0)
	check("bootstrap-mock-storage-shown", "Mock/InMemory", boot.storage, 0)
	check("bootstrap-summary-gold", 0, boot.profileSummary.gold, 0)
	local bootKeys = {}
	for key in boot do
		table.insert(bootKeys, key)
	end
	table.sort(bootKeys)
	check(
		"bootstrap-exact-keys",
		"balanceHash,phase,profileRevision,profileSummary,protocolVersion,publicCatalog,status,storage",
		table.concat(bootKeys, ","),
		0
	)
	local summaryKeys = {}
	for key in boot.profileSummary do
		table.insert(summaryKeys, key)
	end
	table.sort(summaryKeys)
	check(
		"bootstrap-summary-exact-keys",
		"gold,heroLevel,heroTraits,nextLevelXp,stageProgress,totalXp,unitLevels,unitUpgradeCosts,unlockedStages,unspentPoints", -- P7 lobby DTO (owner-only, derived)
		table.concat(summaryKeys, ","),
		0
	)
	w.gateway.getBootstrap(1, { protocolVersion = 1 })
	local limited = w.gateway.getBootstrap(1, { protocolVersion = 1 })
	check("bootstrap-rate-limited", "RateLimited", limited.status, 0)
	check("bootstrap-retry-after", true, limited.retryAfterSeconds > 0, 0)
	w.now += 2
	check(
		"bootstrap-protocol-mismatch",
		"ProtocolMismatch",
		w.gateway.getBootstrap(1, { protocolVersion = 9 }).status,
		0
	)

	-- ---------------------------------------------------------------- start / phase rules
	check("start-locked-stage", "LockedStage", w.start(1, "s02", "a1").reason, 0)
	check("start-stale-revision", "StaleRevision", w.start(1, "s01", "a2", 7).reason, 0)
	local started = w.start(1, "s01", "a3")
	check("start-committed", "Committed", started.status, 0)
	check("start-running", "Running", w.match.phaseOf(1), 0)
	local matchA = started.matchId
	local profileA = w.profiles.profileOf(1)
	check("start-active-run", matchA, profileA.activeRun.matchId, 0)
	check("start-revision", 1, profileA.revision, 0)
	check("start-again-wrong-phase", "WrongPhase", w.start(1, "s01", "a4", 1).reason, 0)
	local replayed
	w.profiles.startRun(1, {
		requestId = REQ .. "a3",
		expectedRevision = 0,
		stageId = "s01",
		matchId = "other",
		balanceHash = "hash",
	}, function(profile)
		replayed = profile
	end)
	check("start-replay-same-run", matchA, replayed and replayed.activeRun.matchId, 0)
	check("start-replay-no-second-effect", 1, replayed and replayed.runCounter, 0)

	-- ---------------------------------------------------------------- battle commands
	check("summon-pending", "Pending", w.battle(1, "Summon", matchA, 1, "b1").status, 0)
	local duplicate = w.battle(1, "Summon", matchA, 1, "b1")
	check("summon-duplicate-same-ack", "Pending", duplicate.status, 0)
	check("tsec04-old-seq", "StaleCommand", w.battle(1, "Summon", matchA, 1, "b2").reason, 0)
	check("cast-pending", "Pending", w.battle(1, "Cast", matchA, 2, "b3").status, 0)
	check(
		"tsec04-unknown-match",
		"WrongPhase",
		w.battle(1, "Summon", "match-999", 3, "b4").reason,
		0
	)
	check("pending-queued-once", 2, #w.match.takePending(1), 0)

	-- ---------------------------------------------------------------- isolation (two owners)
	w.gateway.playerAdded(2)
	local matchB = w.start(2, "s01", "c1").matchId
	check("isolation-distinct-matches", true, matchB ~= nil and matchB ~= matchA, 0)
	local sentBefore = #w.sent
	check(
		"isolation-foreign-match-not-owner",
		"NotOwner",
		w.battle(1, "Summon", matchB, 10, "d1").reason,
		0
	)
	check("isolation-b-untouched", 0, #w.match.takePending(2), 0)
	check("isolation-a-untouched", 0, #w.match.takePending(1), 0)
	local leaked = false
	for index = sentBefore + 1, #w.sent do
		leaked = leaked or w.sent[index].userId ~= 1
	end
	check("isolation-reply-to-sender-only", false, leaked, 0)
	check(
		"isolation-foreign-move-ignored",
		false,
		w.gateway.moveIntent(1, { protocolVersion = 1, matchId = matchB, seq = 1, axis = 1 }),
		0
	)
	w.gateway.publishSnapshots()
	local foreignSnapshot = false
	for _, entry in w.sent do
		if entry.channel == "MatchSnapshot" then
			local expected = if entry.userId == 1
				then matchA
				elseif entry.userId == 2 then matchB
				else nil
			foreignSnapshot = foreignSnapshot or entry.payload.matchId ~= expected
		end
	end
	check("isolation-snapshot-owner-only", false, foreignSnapshot, 0)
	check("isolation-profiles-separate", 1, w.profiles.profileOf(2).revision, 0)

	-- ---------------------------------------------------------------- movement
	w.now += 1
	check(
		"move-accepted",
		true,
		w.gateway.moveIntent(1, { protocolVersion = 1, matchId = matchA, seq = 1, axis = 1 }),
		0
	)
	check(
		"move-stale-seq",
		false,
		w.gateway.moveIntent(1, { protocolVersion = 1, matchId = matchA, seq = 1, axis = -1 }),
		0
	)
	check("move-axis", 1, w.match.effectiveAxis(1), 0)
	w.tick += Protocol.LIMITS.moveTtlTicks + 1
	check("move-ttl-expired", 0, w.match.effectiveAxis(1), w.tick)

	-- ---------------------------------------------------------------- flood (T-SEC-03)
	local before = #w.sent
	for index = 1, 1000 do
		w.gateway.clientCommand(
			1,
			summon({ requestId = REQ .. "f" .. index, matchId = matchA, commandSeq = 100 + index })
		)
	end
	w.gateway.drain()
	local repliesToA = 0
	for index = before + 1, #w.sent do
		repliesToA += if w.sent[index].userId == 1 then 1 else 0
	end
	check("flood-bucket-caps-admission", true, repliesToA <= Protocol.LIMITS.discreteBurst, w.tick)
	check(
		"flood-drops-counted",
		true,
		(w.gateway.rejectCounts(1).RateLimited or 0) >= 1000 - Protocol.LIMITS.discreteBurst,
		w.tick
	)
	check(
		"flood-other-player-normal",
		"Pending",
		w.battle(2, "Summon", matchB, 1, "g1").status,
		w.tick
	)

	-- queue capacity: refill tokens between sends but never drain
	local q = world()
	q.gateway.playerAdded(7)
	local qMatch = q.start(7, "s01", "q0").matchId
	for index = 1, 40 do
		q.now += 0.2
		q.gateway.clientCommand(
			7,
			summon({ requestId = REQ .. "q" .. index, matchId = qMatch, commandSeq = index })
		)
	end
	check("queue-cap-busy", "Busy", q.last(7).reason, 0)
	q.gateway.drain()
	check("queue-cap-32-processed", Protocol.LIMITS.queueCapacity, #q.match.takePending(7), 0)

	-- server-wide match cap
	local cap = world()
	for userId = 11, 15 do
		cap.gateway.playerAdded(userId)
	end
	for userId = 11, 14 do
		cap.start(userId, "s01", "cap" .. userId)
	end
	check("match-cap-4", "Busy", cap.start(15, "s01", "cap15").reason, 0)

	-- ---------------------------------------------------------------- growth transactions
	local g = world()
	g.gateway.playerAdded(3)
	local function upgrade(id: string, revision: number)
		g.now += 0.2
		g.command(3, {
			protocolVersion = 1,
			requestId = REQ .. id,
			kind = "UpgradeUnit",
			unitId = "vanguard",
			expectedRevision = revision,
		})
		return g.last(3)
	end
	check("upgrade-insufficient-gold", "InsufficientGold", upgrade("u1", 0).reason, 0)
	g.now += 0.2
	g.command(3, {
		protocolVersion = 1,
		requestId = REQ .. "p1",
		kind = "AllocatePoint",
		traitId = "focus",
		expectedRevision = 0,
	})
	check("allocate-no-points", "NoPoints", g.last(3).reason, 0)

	local rich = env.newStore()
	local seeded = env.ProfileSchema.newProfile()
	seeded.gold = 25
	rich.setRaw(4, seeded)
	local r = world({ store = rich })
	r.gateway.playerAdded(4)
	r.store.inject("updateAfter") -- commit succeeds, response is lost
	r.now += 0.2
	local upgradeCommand = {
		protocolVersion = 1,
		requestId = REQ .. "v1",
		kind = "UpgradeUnit",
		unitId = "vanguard",
		expectedRevision = 0,
	}
	r.command(4, upgradeCommand)
	check("upgrade-lost-response-not-committed", "StorageUnavailable", r.last(4).reason, 0)
	check("upgrade-lost-response-store-spent", 0, r.store.raw(4).gold, 0)
	r.now += 0.2
	r.command(4, upgradeCommand)
	check("upgrade-retry-committed", "Committed", r.last(4).status, 0)
	check("upgrade-retry-no-double-spend", 0, r.profiles.profileOf(4).gold, 0)
	check("upgrade-level-2", 2, r.profiles.profileOf(4).unitLevels.vanguard, 0)
	check("upgrade-receipt-once", 1, #r.profiles.profileOf(4).recentOperations, 0)

	local capped = env.newStore()
	local wealthy = env.ProfileSchema.newProfile()
	wealthy.gold = 1000
	capped.setRaw(5, wealthy)
	local c = world({ store = capped, receiptCap = 3 })
	c.gateway.playerAdded(5)
	for index = 0, 3 do
		c.now += 0.2
		c.command(5, {
			protocolVersion = 1,
			requestId = REQ .. "w" .. index,
			kind = "UpgradeUnit",
			unitId = "vanguard",
			expectedRevision = index,
		})
	end
	check("upgrade-to-max", 5, c.profiles.profileOf(5).unitLevels.vanguard, 0)
	check("receipts-capped", 3, #c.profiles.profileOf(5).recentOperations, 0)
	c.now += 0.2
	c.command(5, {
		protocolVersion = 1,
		requestId = REQ .. "w9",
		kind = "UpgradeUnit",
		unitId = "vanguard",
		expectedRevision = 4,
	})
	check("upgrade-max-level", "MaxLevel", c.last(5).reason, 0)

	-- ---------------------------------------------------------------- load failure classes
	local failing = env.newStore()
	failing.inject("loadAndLock")
	local f = world({ store = failing })
	f.gateway.playerAdded(6)
	check("load-error-unavailable", "Unavailable", f.match.phaseOf(6), 0)
	check("load-error-no-new-account", nil, failing.raw(6), 0)
	check(
		"load-error-bootstrap",
		"Unavailable",
		f.gateway.getBootstrap(6, { protocolVersion = 1 }).status,
		0
	)

	local corrupt = env.newStore()
	local broken = env.ProfileSchema.newProfile()
	broken.gold = -5
	corrupt.setRaw(8, broken)
	local k = world({ store = corrupt })
	k.gateway.playerAdded(8)
	check("load-corrupt-unavailable", "Unavailable", k.match.phaseOf(8), 0)
	check("load-corrupt-not-overwritten", encode(broken), encode(corrupt.raw(8)), 0)

	local future = env.newStore()
	local newer = env.ProfileSchema.newProfile()
	newer.schemaVersion = 2
	future.setRaw(9, newer)
	local fw = world({ store = future })
	fw.gateway.playerAdded(9)
	check("load-future-schema-unavailable", "Unavailable", fw.match.phaseOf(9), 0)
	check("load-future-schema-not-written", encode(newer), encode(future.raw(9)), 0)

	-- ---------------------------------------------------------------- lease / stale writer
	local shared = env.newStore()
	local first = world({ store = shared, sessionId = "server-1" })
	first.gateway.playerAdded(20)
	local second = world({ store = shared, sessionId = "server-2" })
	second.gateway.playerAdded(20)
	check("lease-second-owner-locked", "Unavailable", second.match.phaseOf(20), 0)
	second.gateway.playerRemoving(20)
	second.wall = first.wall + 181
	second.gateway.playerAdded(20)
	check("lease-expired-takeover", "LobbyReady", second.match.phaseOf(20), 0)
	check("lease-epoch-increments", 2, shared.raw(20).fenceEpoch, 0)
	first.now += 0.2
	first.command(20, {
		protocolVersion = 1,
		requestId = REQ .. "z1",
		kind = "AllocatePoint",
		traitId = "focus",
		expectedRevision = 0,
	})
	check("lease-stale-writer-rejected", "SessionLost", first.last(20).reason, 0)
	second.gateway.playerRemoving(20)
	check("lease-released-on-leave", nil, shared.raw(20).lease, 0)
	check("lease-epoch-preserved", 2, shared.raw(20).fenceEpoch, 0)
	-- ---------------------------------------------------------------- review regressions
	-- ack semantics: cached requestId with another seq, eviction then replay, cache reset per match
	local a = world()
	a.gateway.playerAdded(30)
	local mA = a.start(30, "s01", "ack0").matchId
	a.battle(30, "Summon", mA, 1, "ack1")
	check(
		"ack-same-id-other-seq-stale",
		"StaleCommand",
		a.battle(30, "Summon", mA, 2, "ack1").reason,
		0
	)
	for index = 2, 130 do
		a.battle(30, "Summon", mA, index + 1, "ackfill" .. index)
	end
	a.match.takePending(30)
	check(
		"ack-evicted-replay-stale",
		"StaleCommand",
		a.battle(30, "Summon", mA, 1, "ack1").reason,
		0
	)
	check("ack-evicted-replay-no-effect", 0, #a.match.takePending(30), 0)
	check(
		"return-to-lobby-outside-settled",
		"WrongPhase",
		(function()
			a.now += 0.2
			a.command(30, {
				protocolVersion = 1,
				requestId = REQ .. "rtl",
				kind = "ReturnToLobby",
				matchId = mA,
			})
			return a.last(30).reason
		end)(),
		0
	)

	-- bootstrap isolation and move token bucket
	local b = world()
	b.gateway.playerAdded(31)
	b.gateway.playerAdded(32)
	local m31 = b.start(31, "s01", "iso31").matchId
	b.now += 2
	local boot32 = b.gateway.getBootstrap(32, { protocolVersion = 1 })
	check("bootstrap-other-player-no-match", nil, boot32.currentMatch, 0)
	check("bootstrap-other-player-own-revision", 0, boot32.profileRevision, 0)
	check(
		"bootstrap-unknown-player-loading",
		"Loading",
		b.gateway.getBootstrap(99, { protocolVersion = 1 }).status,
		0
	)
	local moves = 0
	for seq = 1, 100 do
		moves += if b.gateway.moveIntent(
				31,
				{ protocolVersion = 1, matchId = m31, seq = seq, axis = 1 }
			)
			then 1
			else 0
	end
	check("move-bucket-caps-burst", Protocol.LIMITS.moveBurst, moves, 0)

	-- idempotent join: a duplicate PlayerAdded must not reload or steal the lease
	local d = world({ deferred = true })
	d.gateway.playerAdded(33)
	d.gateway.playerAdded(33)
	check("join-idempotent-one-load", 1, #d.tasks, 0)
	d.runAll()
	check("join-idempotent-ready", "LobbyReady", d.match.phaseOf(33), 0)

	-- leave then rejoin while the old release is still queued: fenced release keeps the new lease
	local r2 = world({ deferred = true })
	r2.gateway.playerAdded(34)
	r2.runAll()
	r2.gateway.playerRemoving(34) -- old release queued (not yet run)
	r2.gateway.playerAdded(34)
	r2.run(2) -- new load first
	r2.run(1) -- then the late release of the old session
	check("rejoin-late-release-fenced", "LobbyReady", r2.match.phaseOf(34), 0)
	check("rejoin-lease-kept", true, r2.store.raw(34).lease ~= nil, 0)
	check("rejoin-start-works", "Pending", r2.start(34, "s01", "rejoin").status, 0)
	r2.runAll()
	check("rejoin-start-committed", "Running", r2.match.phaseOf(34), 0)

	-- leave during an in-flight write: release waits for the write, callbacks after leave are ignored
	local l = world({ deferred = true })
	l.gateway.playerAdded(35)
	l.runAll()
	l.start(35, "s01", "leave1")
	l.gateway.playerRemoving(35)
	check("leave-release-not-parallel", 1, #l.tasks, 0)
	l.runAll()
	check("leave-lease-released-after-write", nil, l.store.raw(35).lease, 0)
	check("leave-run-left-open", true, l.store.raw(35).activeRun ~= nil, 0)

	-- rejoin closes the orphaned run as Abandoned, then StartStage works again
	local o = world({ store = l.store })
	o.gateway.playerAdded(35)
	local orphan = o.profiles.profileOf(35)
	check("orphan-abandoned-on-load", "Abandoned", orphan and orphan.lastRunResult.outcome, 0)
	check("orphan-active-run-cleared", nil, orphan and orphan.activeRun, 0)
	check("orphan-no-reward", 0, orphan and orphan.lastRunResult.awardedGold, 0)
	local revision = orphan and orphan.revision or 0
	check("orphan-start-again", "Committed", o.start(35, "s01", "after-orphan", revision).status, 0)
	-- replaying the original start of the closed run: committed receipt but no matching run -> concrete reason
	local replay = o.start(35, "s01", "leave1", 0)
	check("start-replay-closed-run-rejected", "Rejected", replay.status, 0)
	check("start-replay-reason-not-nil", true, replay.reason ~= nil, 0)

	-- stale writer with queued jobs: everything fails fast, no session stuck in Preparing
	local st = env.newStore()
	local s1 = world({ store = st, sessionId = "server-1", deferred = true })
	s1.gateway.playerAdded(36)
	s1.runAll()
	local s2 = world({ store = st, sessionId = "server-2" })
	s2.wall = s1.wall + 181
	s2.gateway.playerAdded(36) -- steals the expired lease
	s1.now += 0.2
	s1.command(36, {
		protocolVersion = 1,
		requestId = REQ .. "st1",
		kind = "AllocatePoint",
		traitId = "focus",
		expectedRevision = 0,
	})
	s1.now += 0.2
	s1.command(36, {
		protocolVersion = 1,
		requestId = REQ .. "st2",
		kind = "StartStage",
		stageId = "s01",
		expectedRevision = 0,
	})
	s1.runAll()
	check("stale-session-unavailable", "Unavailable", s1.match.phaseOf(36), 0)
	check("stale-queued-start-failed", "Rejected", s1.last(36).status, 0)
	check("stale-no-match-slot-held", 0, s1.match.activeMatches(), 0)

	-- store budget: stale revisions are refused from memory; per-profile queue is capped
	local bud = world({ deferred = true })
	bud.gateway.playerAdded(37)
	bud.runAll()
	local updatesBefore = bud.store.calls.update
	bud.now += 0.2
	bud.command(37, {
		protocolVersion = 1,
		requestId = REQ .. "bud0",
		kind = "AllocatePoint",
		traitId = "focus",
		expectedRevision = 9,
	})
	check("budget-stale-revision-precheck", "StaleRevision", bud.last(37).reason, 0)
	for index = 1, 6 do
		bud.now += 0.2
		bud.command(37, {
			protocolVersion = 1,
			requestId = REQ .. "bud" .. index,
			kind = "AllocatePoint",
			traitId = "focus",
			expectedRevision = 0,
		})
	end
	check("budget-queue-capped", "Busy", bud.last(37).reason, 0)
	bud.runAll()
	check(
		"budget-store-calls-bounded",
		true,
		bud.store.calls.update - updatesBefore <= 1 + Protocol.LIMITS.profileQueueCap,
		0
	)

	-- receipts are bound to the operation kind
	local kd = world()
	kd.gateway.playerAdded(38)
	kd.start(38, "s01", "kind1")
	local mismatch
	kd.profiles.upgradeUnit(
		38,
		{ requestId = REQ .. "kind1", expectedRevision = 1, unitId = "vanguard" },
		function(_, reason)
			mismatch = reason
		end
	)
	check("receipt-kind-mismatch", "StaleCommand", mismatch, 0)

	-- commands queued by a previous session are dropped at drain, queue accounting stays non-negative
	local qq = world()
	qq.gateway.playerAdded(39)
	local mq = qq.start(39, "s01", "qq0").matchId
	qq.now += 0.2
	qq.gateway.clientCommand(39, summon({ requestId = REQ .. "qq1", matchId = mq, commandSeq = 1 }))
	qq.gateway.playerRemoving(39)
	qq.gateway.playerAdded(39)
	qq.gateway.drain()
	check("rejoin-old-command-dropped", 0, #qq.match.takePending(39), 0)
end
