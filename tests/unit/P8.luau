--!strict
-- Offline fault matrix only; prepared but not executed during the user's testing pause.
return function(env: any, check: any)
	local Schema, Adapter = env.Schema, env.Adapter
	local function acquire(fake: any, adapter: any, id: string): any
		return adapter.loadAndLock(
			1,
			{ sessionId = id, jobId = "job" },
			fake.wall,
			Schema.newProfile,
			Schema.validate
		)
	end
	local function token(profile: any): any
		return {
			sessionId = profile.lease.sessionId,
			jobId = profile.lease.ownerJobId,
			fenceEpoch = profile.fenceEpoch,
			leaseExpiresAt = profile.lease.expiresAt,
		}
	end
	check(
		"default-live-access-denied",
		false,
		env.Policy.allowed(env.Policy.config, 10771015944, true),
		0
	)
	check(
		"wrong-universe-denied",
		false,
		env.Policy.allowed({ enabled = true, universeId = 1 }, 1, true),
		0
	)
	check(
		"non-studio-denied",
		false,
		env.Policy.allowed({ enabled = true, universeId = 10771015944 }, 10771015944, false),
		0
	)
	local fake = env.newBackend()
	fake.repeats = 3
	fake.failAfter = 1
	local adapter = Adapter.new(fake.deps)
	local loaded = acquire(fake, adapter, "a")
	check("nil-load-creates-profile", "ok", loaded.kind, 0)
	check("load-response-loss-no-second-fence", 1, loaded.profile.fenceEpoch, 0)
	check("callback-replayed-three-times", true, fake.callbacks >= 6, 0)
	local a = token(loaded.profile)
	check("foreign-live-lock-rejected", "locked", acquire(fake, adapter, "b").kind, 0)
	local revision = loaded.profile.revision
	fake.wall += 45
	local renewed = adapter.renew(1, a, fake.wall)
	check("lease-renews", "ok", renewed.kind, 0)
	check("lease-does-not-increment-revision", revision, renewed.profile.revision, 0)
	a.leaseExpiresAt = renewed.profile.lease.expiresAt
	fake.wall = a.leaseExpiresAt - 30
	local calls = fake.calls
	check(
		"safety-margin-rejects-writes",
		"stale",
		adapter.update(1, a, fake.wall, function(p: any)
			return p
		end).kind,
		0
	)
	check("safety-margin-no-io", calls, fake.calls, 0)
	fake.wall = a.leaseExpiresAt + 1
	check("expired-token-not-resurrected", "locked", acquire(fake, adapter, "a").kind, 0)
	local nextOwner = acquire(fake, adapter, "b")
	check("new-owner-increments-fence", 2, nextOwner.profile.fenceEpoch, 0)
	check("stale-release-rejected", false, adapter.release(1, a), 0)
	check(
		"stale-update-rejected",
		"stale",
		adapter.update(1, a, fake.wall, function(p: any)
			return p
		end).kind,
		0
	)
	local b = token(nextOwner.profile)
	check("current-owner-release", true, adapter.release(1, b), 0)
	check("released-fence-preserved", 2, fake.raw("qa:u:1").fenceEpoch, 0)
	check("new-acquisition-after-release", 3, acquire(fake, adapter, "c").profile.fenceEpoch, 0)

	local unavailable = env.newBackend()
	unavailable.failBefore = 5
	check(
		"load-error-not-new-account",
		"error",
		acquire(unavailable, Adapter.new(unavailable.deps), "a").kind,
		0
	)
	check("failed-load-no-write", 0, unavailable.writes, 0)
	check("api-retries-bounded-five", 5, unavailable.calls, 0)
	local emptyBudget = env.newBackend()
	emptyBudget.hasBudget = false
	check(
		"budget-zero-fails-closed",
		"error",
		acquire(emptyBudget, Adapter.new(emptyBudget.deps), "a").kind,
		0
	)
	check("budget-zero-no-call", 0, emptyBudget.calls, 0)
	local corruptValues: { any } = { { schemaVersion = 99 }, { schemaVersion = 1 }, "broken" }
	for index, bad in corruptValues do
		local corrupt = env.newBackend()
		corrupt.setRaw("qa:u:1", bad)
		check(
			"corrupt-load-rejected-" .. index,
			"invalid",
			acquire(corrupt, Adapter.new(corrupt.deps), "a").kind,
			0
		)
		check("corrupt-profile-not-rewritten-" .. index, 0, corrupt.writes, 0)
	end
	local cyclic: any = {}
	cyclic.self = cyclic
	check("cyclic-document-rejected", false, env.Validator.validate(cyclic), 0)
	local oversized = Schema.newProfile()
	oversized.extra = string.rep("x", 65536)
	check("oversized-document-rejected", false, env.Validator.validate(oversized), 0)

	local function service(backend: any): any
		return env.ProfileService.new({
			store = Adapter.new(backend.deps),
			clock = function()
				return backend.wall
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			sessionId = "server",
			jobId = "job",
			receiptCap = 64,
			queueCap = 4,
			log = function(_message: string) end,
		})
	end
	local economic = env.newBackend()
	economic.repeats = 3
	local profiles = service(economic)
	profiles.load(1, function() end)
	check("durable-load-ready", "Ready", profiles.status(1), 0)
	profiles.startRun(1, {
		requestId = "p8-start-operation-01",
		expectedRevision = 0,
		stageId = "s01",
		matchId = "run",
		balanceHash = env.Catalog.balanceHash,
	}, function() end)
	local result = {
		matchId = "run",
		runOrdinal = 1,
		stageId = "s01",
		balanceHash = env.Catalog.balanceHash,
		seed = 12345,
		outcome = "Victory",
		elapsedTicks = 100,
		killCounts = {},
		pendingKillGold = 0,
		pendingKillXp = 0,
	}
	economic.failAfter = 1
	profiles.finishRun(1, result, function() end)
	check("response-lost-result-reconciled", 200, profiles.profileOf(1).gold, 0)
	check("response-lost-revision-once", 2, profiles.profileOf(1).revision, 0)
	local stored = economic.raw("qa:u:1")
	stored.recentOperations = {}
	economic.setRaw("qa:u:1", stored)
	local reconciled = false
	profiles.finishRun(1, result, function(p: any)
		reconciled = p ~= nil
	end)
	check("closed-result-with-evicted-receipt", true, reconciled, 0)
	check("closed-result-not-paid-twice", 200, profiles.profileOf(1).gold, 0)
	check("closed-result-wins-once", 1, profiles.profileOf(1).stageProgress.s01.wins, 0)
	profiles.startRun(1, {
		requestId = "p8-next-operation-001",
		expectedRevision = 2,
		stageId = "s01",
		matchId = "run-2",
		balanceHash = env.Catalog.balanceHash,
	}, function() end)
	local olderReason: string? = nil
	profiles.finishRun(1, result, function(_p: any, reason: string?)
		olderReason = reason
	end)
	check("older-result-rejected-during-new-run", "StaleCommand", olderReason, 0)
	check("older-result-keeps-new-run", 2, profiles.profileOf(1).activeRun.ordinal, 0)
	profiles.shutdown()
	check("shutdown-drains-single-writer", true, profiles.isIdle(), 0)
	check("shutdown-releases-lease", nil, economic.raw("qa:u:1").lease, 0)

	local leaving = env.newBackend()
	local exiting = service(leaving)
	exiting.load(1, function() end)
	leaving.afterCommit = function()
		exiting.release(1)
		exiting.shutdown()
	end
	exiting.startRun(1, {
		requestId = "p8-leave-operation-01",
		expectedRevision = 0,
		stageId = "s01",
		matchId = "orphan",
		balanceHash = env.Catalog.balanceHash,
	}, function() end)
	check("leave-close-idempotent", true, exiting.isIdle(), 0)
	check("leave-active-run-abandoned", "Abandoned", leaving.raw("qa:u:1").lastRunResult.outcome, 0)
	check("leave-run-reward-zero", 0, leaving.raw("qa:u:1").gold, 0)

	local rejoining = env.newBackend()
	local rejoined = service(rejoining)
	rejoined.load(1, function() end)
	local oldToken = token(rejoining.raw("qa:u:1"))
	local joinedStatus: string? = nil
	rejoining.afterCommit = function()
		rejoined.release(1)
		rejoined.load(1, function(status: string)
			joinedStatus = status
		end)
	end
	rejoined.startRun(1, {
		requestId = "p8-rejoin-operation-1",
		expectedRevision = 0,
		stageId = "s01",
		matchId = "interrupted",
		balanceHash = env.Catalog.balanceHash,
	}, function() end)
	check("rapid-rejoin-waits-for-old-writer", "Ready", joinedStatus, 0)
	check("rapid-rejoin-has-new-fence", 2, rejoining.raw("qa:u:1").fenceEpoch, 0)
	check("rapid-rejoin-no-run-resume", nil, rejoined.profileOf(1).activeRun, 0)
	check(
		"late-old-release-keeps-new-owner",
		false,
		Adapter.new(rejoining.deps).release(1, oldToken),
		0
	)
	rejoined.shutdown()

	local late = env.newBackend()
	local stopped = service(late)
	local match = env.MatchService.new({
		profiles = stopped,
		tick = function()
			return 0
		end,
		newMatchId = function()
			return "late-run"
		end,
		balanceHash = env.Catalog.balanceHash,
		maxMatches = 4,
		ackCacheSize = 128,
		moveTtlTicks = 10,
		stageFlow = true,
		send = function() end,
	})
	match.playerJoined(1)
	late.wall += 41
	late.afterCommit = function()
		late.wall = 1190
		stopped.poll()
	end
	stopped.poll()
	check("late-renew-cannot-revive-profile", "Unavailable", stopped.status(1), 0)
	check("lease-loss-stops-match-session", "Unavailable", match.phaseOf(1), 0)
	local count = late.calls
	stopped.allocatePoint(
		1,
		{ requestId = "stopped-operation-01", expectedRevision = 0, traitId = "focus" },
		function() end
	)
	check("stopped-session-no-new-write", count, late.calls, 0)
	local offline = env.ClientController.new({
		protocol = env.Protocol,
		catalog = env.Catalog,
		send = function() end,
		requestId = function()
			return "client-operation-0001"
		end,
	})
	offline.finishBootstrap(
		offline.beginBootstrap(0),
		{ protocolVersion = 1, balanceHash = env.Catalog.balanceHash, status = "Unavailable" },
		0
	)
	check("client-storage-loss-disables-play", "Unavailable", offline.model(0).phase, 0)
end
