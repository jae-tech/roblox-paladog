--!strict
-- Profile session + transaction queue over an injected StoreAdapter (ARCHITECTURE §7-8, DATA_MODELS §5.1).
-- Store calls may yield (real DataStore), so they run inside deps.spawn; readers only touch memory.
-- One writer per profile: transactions, the load-time abandon and the final release all go through the
-- same busy flag, so a release never races an in-flight write.
local ServerTypes = require("../ServerTypes")
local Schema = require("./ProfileSchema")
local Growth = require("./ProgressionService")
local ResultReducer = require("../Simulation/ResultReducer")

type ProfileV1 = ServerTypes.ProfileV1
type Session = ServerTypes.Session

export type Status = "Loading" | "Ready" | "Unavailable"
export type Done = (ProfileV1?, string?) -> ()
export type OnStatus = (Status, string?) -> ()

type Job = {
	kind: string,
	requestId: string,
	expectedRevision: number,
	mutate: (ProfileV1) -> string?,
	done: Done,
	result: ServerTypes.MatchResult?,
}

type State = {
	status: Status,
	reason: string?,
	profile: ProfileV1?,
	session: Session?,
	queue: { Job },
	busy: boolean,
	closed: boolean,
	onStatus: OnStatus,
	closing: boolean?,
	renewPending: boolean?,
	nextRenewAt: number?,
}

export type Deps = {
	store: ServerTypes.StoreAdapter,
	clock: () -> number, -- wall-clock seconds, lease timing only
	spawn: (() -> ()) -> (),
	sessionId: string,
	jobId: string,
	receiptCap: number,
	queueCap: number,
	log: (string) -> (),
}

local function hasReceipt(profile: ProfileV1?, requestId: string): boolean
	if profile then
		for _, receipt in profile.recentOperations do
			if receipt.id == requestId then
				return true
			end
		end
	end
	return false
end

local function finished(profile: ProfileV1, result: ServerTypes.MatchResult): boolean
	local last = profile.lastRunResult
	return last ~= nil
		and not profile.activeRun
		and profile.runCounter == result.runOrdinal
		and profile.lastClosedRunOrdinal == result.runOrdinal
		and last.ordinal == result.runOrdinal
		and last.matchId == result.matchId
		and last.outcome == result.outcome
end

local function new(deps: Deps)
	local states: { [number]: State } = {}
	local closing: { [number]: State } = {}
	local waiting: { [number]: OnStatus } = {}
	local workers, generation = 0, 0
	local shuttingDown = false
	local load: (number, OnStatus) -> ()
	local function work(fn: () -> ())
		workers += 1
		deps.spawn(function()
			local ok = pcall(fn)
			workers -= 1
			if not ok then
				deps.log("profile worker failed; commit status must not be assumed")
			end
		end)
	end

	local function setStatus(state: State, status: Status, reason: string?)
		state.status, state.reason = status, reason
		if status ~= "Ready" then
			state.profile = nil
		end
		state.onStatus(status, reason)
	end

	local function failQueued(state: State, reason: string)
		local queued = state.queue
		state.queue = {}
		for _, job in queued do
			job.done(nil, reason)
		end
	end

	local function releaseLease(userId: number, session: Session)
		work(function()
			pcall(deps.store.release, userId, session) -- fenced: cannot clear a newer session's lease
		end)
	end

	local function leaseSafe(state: State): boolean
		local session = state.session
		return not deps.store.leaseSeconds
			or not session
			or not session.leaseExpiresAt
			or deps.clock() < session.leaseExpiresAt - 30
	end
	local function unavailable(state: State, reason: string)
		state.renewPending = false
		setStatus(state, "Unavailable", reason)
		failQueued(state, reason)
	end
	local function acknowledgeLease(userId: number, state: State, profile: ProfileV1): boolean
		if not deps.store.leaseSeconds then
			return true
		end
		local session, lease = state.session, profile.lease
		if
			not session
			or not lease
			or lease.sessionId ~= session.sessionId
			or lease.ownerJobId ~= session.jobId
			or profile.fenceEpoch ~= session.fenceEpoch
			or lease.expiresAt <= deps.clock() + 30
		then
			return false
		end
		session.leaseExpiresAt = lease.expiresAt
		state.nextRenewAt, state.renewPending = deps.clock() + 40 + userId % 11, false
		return true
	end

	local function transform(job: Job): ServerTypes.Transform
		return function(old: ProfileV1): (ProfileV1?, string?)
			local profile = Schema.deepClone(old)
			if job.result and profile.lastClosedRunOrdinal >= job.result.runOrdinal then
				return if finished(profile, job.result) then profile else nil,
					if finished(profile, job.result) then nil else "StaleCommand"
			end
			for _, receipt in profile.recentOperations do
				if receipt.id == job.requestId then
					if receipt.kind ~= job.kind then
						return nil, "StaleCommand" -- requestId reused for a different operation
					end
					return profile, nil -- already committed: idempotent replay, no second effect
				end
			end
			if profile.revision ~= job.expectedRevision then
				return nil, "StaleRevision"
			end
			local reason = job.mutate(profile)
			if reason then
				return nil, reason
			end
			profile.revision += 1
			table.insert(
				profile.recentOperations,
				{ id = job.requestId, kind = job.kind, revision = profile.revision }
			)
			while #profile.recentOperations > deps.receiptCap do
				table.remove(profile.recentOperations, 1)
			end
			return profile, nil
		end
	end

	local pump: (number, State) -> ()
	local abandonJob: (ProfileV1, Done) -> Job

	local function runJob(userId: number, state: State, job: Job)
		if not leaseSafe(state) then
			unavailable(state, "SessionLost")
			job.done(nil, "SessionLost")
			pump(userId, state)
			return
		end
		state.busy = true
		local session = state.session :: Session
		work(function()
			local ok: boolean
			local result: any
			local renew = deps.store.renew
			if job.kind == "RenewLease" and renew then
				ok, result = pcall(renew, userId, session, deps.clock())
			else
				ok, result = pcall(deps.store.update, userId, session, deps.clock(), transform(job))
			end
			state.busy = false
			if state.closed then
				job.done(nil, "SessionLost") -- player left; a committed effect is reconciled by the next load
				releaseLease(userId, session)
				return
			end
			if state.status == "Unavailable" then
				job.done(nil, "SessionLost") -- a late response cannot revive a stopped generation
				pump(userId, state)
				return
			end
			if not ok or result.kind == "error" then
				if deps.store.leaseSeconds then
					if job.kind == "RenewLease" and leaseSafe(state) then
						state.nextRenewAt, state.renewPending = deps.clock() + 5, false
					else
						unavailable(state, "StorageUnavailable")
					end
				end
				job.done(nil, "StorageUnavailable")
			elseif result.kind == "stale" then
				unavailable(state, "SessionLost")
				job.done(nil, "SessionLost")
				pump(userId, state)
				return
			elseif result.kind == "rejected" then
				job.done(nil, result.reason or "StorageUnavailable")
			else
				local saved = result.profile
				local committed = job.kind == "RenewLease"
					or (saved ~= nil and job.result ~= nil and finished(saved, job.result))
				if saved then
					for _, receipt in saved.recentOperations do
						committed = committed
							or (receipt.id == job.requestId and receipt.kind == job.kind)
					end
				end
				-- Success means the returned document carries this operation's receipt, not merely "no error".
				if
					saved
					and committed
					and Schema.validate(saved, deps.receiptCap)
					and acknowledgeLease(userId, state, saved)
				then
					state.profile = saved
					if state.closing then
						job.done(nil, "SessionLost")
					else
						job.done(saved, nil)
					end
				else
					if deps.store.leaseSeconds then
						unavailable(state, "StorageUnavailable")
					end
					job.done(nil, "StorageUnavailable")
				end
			end
			pump(userId, state)
		end)
	end

	pump = function(userId: number, state: State)
		if state.busy or state.closed then
			return
		end
		if state.closing then
			local ready = state.status == "Ready"
			if ready and #state.queue > 0 then
				runJob(userId, state, table.remove(state.queue, 1) :: Job)
			elseif state.profile and state.profile.activeRun and ready and leaseSafe(state) then
				runJob(userId, state, abandonJob(state.profile, function() end))
			else
				state.busy = true
				work(function()
					local session = state.session
					if session then
						pcall(deps.store.release, userId, session)
					end
					state.busy, state.closed = false, true
					closing[userId] = nil
					local callback = waiting[userId]
					waiting[userId] = nil
					if callback and not shuttingDown then
						load(userId, callback)
					end
				end)
			end
		elseif state.status == "Ready" then
			if state.renewPending then
				state.renewPending = false
				runJob(userId, state, {
					kind = "RenewLease",
					requestId = "lease-heartbeat",
					expectedRevision = 0,
					mutate = function()
						return nil
					end,
					done = function() end,
				})
			elseif #state.queue > 0 then
				runJob(userId, state, table.remove(state.queue, 1) :: Job)
			end
		end
	end

	-- Reconnect after a crash or a leave mid-run: close the leftover run as Abandoned with no reward (ARCH §7).
	abandonJob = function(profile: ProfileV1, done: Done): Job
		local run = profile.activeRun :: ServerTypes.ActiveRun
		return {
			kind = "AbandonRun",
			requestId = `abandon-{run.ordinal}-{run.matchId}`,
			expectedRevision = profile.revision,
			done = done,
			mutate = function(current: ProfileV1): string?
				local active = current.activeRun
				if active and active.ordinal > current.lastClosedRunOrdinal then
					current.lastClosedRunOrdinal = active.ordinal
					current.lastRunResult = {
						ordinal = active.ordinal,
						matchId = active.matchId,
						outcome = "Abandoned",
						awardedGold = 0,
						awardedXp = 0,
					}
				end
				current.activeRun = nil
				return nil
			end,
		}
	end

	load = function(userId: number, onStatus: OnStatus)
		if shuttingDown then
			onStatus("Unavailable", "StorageUnavailable")
			return
		end
		if closing[userId] then
			waiting[userId] = onStatus
			return
		end
		if states[userId] then
			return -- already loading/loaded for this server session
		end
		local state: State =
			{ status = "Loading", queue = {}, busy = false, closed = false, onStatus = onStatus }
		states[userId] = state
		generation += 1
		local key = {
			sessionId = if deps.store.leaseSeconds
				then `{deps.sessionId}-{generation}`
				else deps.sessionId,
			jobId = deps.jobId,
		}
		state.busy = true
		work(function()
			local validator = function(value: any): (boolean, string?)
				return Schema.validate(value, deps.receiptCap)
			end
			local ok, result = pcall(
				deps.store.loadAndLock,
				userId,
				key,
				deps.clock(),
				Schema.newProfile,
				validator
			)
			state.busy = false
			local loaded = if ok and result.kind == "ok" then result.profile else nil
			if loaded and not Schema.validate(loaded, deps.receiptCap) then
				loaded = nil
			end
			local session: Session? = if loaded
				then {
					sessionId = key.sessionId,
					jobId = deps.jobId,
					fenceEpoch = loaded.fenceEpoch,
					leaseExpiresAt = if deps.store.leaseSeconds and loaded.lease
						then loaded.lease.expiresAt
						else nil,
				}
				else nil
			if state.closed then
				if session then
					releaseLease(userId, session)
				end
				return
			end
			-- Only an ok load of a valid profile becomes Ready; errors are never treated as a new account.
			if not loaded or not session then
				local reason = if ok and result.kind == "locked"
					then "Busy"
					else "StorageUnavailable"
				if ok and result.kind == "invalid" then
					deps.log(`profile {userId} unavailable: {result.message}`) -- left untouched, never rewritten
				end
				setStatus(state, "Unavailable", reason)
				if state.closing then
					pump(userId, state)
				end
				return
			end
			state.profile, state.session = loaded, session
			if not acknowledgeLease(userId, state, loaded) then
				unavailable(state, "SessionLost")
				if state.closing then
					pump(userId, state)
				end
				return
			end
			if state.closing then
				state.status = "Ready"
				pump(userId, state)
				return
			end
			if not loaded.activeRun then
				setStatus(state, "Ready", nil)
				return
			end
			runJob(
				userId,
				state,
				abandonJob(loaded, function(profile)
					if profile then
						setStatus(state, "Ready", nil)
						pump(userId, state)
					elseif not state.closed and state.status == "Loading" then
						setStatus(state, "Unavailable", "StorageUnavailable")
					end
				end)
			)
		end)
	end

	local function enqueue(userId: number, job: Job)
		local state = states[userId]
		if state and not leaseSafe(state) then
			unavailable(state, "SessionLost")
		end
		if not state or state.status ~= "Ready" then
			job.done(
				nil,
				if state and state.status == "Loading" then "NotReady" else "StorageUnavailable"
			)
			return
		end
		-- Cheap memory pre-checks spare store budget; the transform re-checks against the stored document.
		if
			state.profile
			and state.profile.revision ~= job.expectedRevision
			and not hasReceipt(state.profile, job.requestId)
		then
			job.done(nil, "StaleRevision")
			return
		end
		if #state.queue >= deps.queueCap then
			job.done(nil, "Busy")
			return
		end
		table.insert(state.queue, job)
		pump(userId, state)
	end

	local function startRun(
		userId: number,
		op: {
			requestId: string,
			expectedRevision: number,
			stageId: string,
			matchId: string,
			balanceHash: string,
		},
		done: Done
	)
		enqueue(userId, {
			kind = "StartRun",
			requestId = op.requestId,
			expectedRevision = op.expectedRevision,
			done = done,
			mutate = function(profile: ProfileV1): string?
				if profile.activeRun then
					return "Busy"
				elseif not Schema.isUnlocked(profile, op.stageId) then
					return "LockedStage"
				end
				profile.runCounter += 1
				profile.activeRun = {
					ordinal = profile.runCounter,
					matchId = op.matchId,
					stageId = op.stageId,
					balanceHash = op.balanceHash,
					startOperationId = op.requestId,
				}
				return nil
			end,
		})
	end

	local function upgradeUnit(
		userId: number,
		op: { requestId: string, expectedRevision: number, unitId: string },
		done: Done
	)
		enqueue(userId, {
			kind = "UpgradeUnit",
			requestId = op.requestId,
			expectedRevision = op.expectedRevision,
			done = done,
			mutate = function(profile: ProfileV1): string?
				return Growth.upgradeUnit(profile, op.unitId)
			end,
		})
	end

	local function allocatePoint(
		userId: number,
		op: { requestId: string, expectedRevision: number, traitId: string },
		done: Done
	)
		enqueue(userId, {
			kind = "AllocatePoint",
			requestId = op.requestId,
			expectedRevision = op.expectedRevision,
			done = done,
			mutate = function(profile: ProfileV1): string?
				return Growth.allocatePoint(profile, op.traitId)
			end,
		})
	end

	-- One transaction closes the run and applies rewards/growth/progression together.
	local function finishRun(userId: number, result: ServerTypes.MatchResult, done: Done)
		local profile = states[userId] and states[userId].profile
		if not profile then
			done(nil, "WrongPhase")
			return
		end
		local fixed = Schema.deepClone(result) :: ServerTypes.MatchResult -- owned copy across retries/yields
		enqueue(userId, {
			kind = "FinishRun",
			requestId = `finish-{fixed.runOrdinal}-{fixed.matchId}`,
			result = fixed,
			expectedRevision = profile.revision,
			done = done,
			mutate = function(current)
				local reduced, reason = ResultReducer.reduce(current, fixed)
				if not reduced then
					return reason
				end
				current.gold, current.totalXp = reduced.gold, reduced.totalXp
				current.heroLevel, current.unspentPoints = reduced.heroLevel, reduced.unspentPoints
				current.stageProgress = reduced.stageProgress
				current.lastClosedRunOrdinal = reduced.lastClosedRunOrdinal
				current.lastRunResult, current.activeRun = reduced.lastRunResult, nil
				return nil
			end,
		})
	end

	-- Leave: fail queued work, then release the lease after any in-flight write (never in parallel with it).
	local function release(userId: number)
		waiting[userId] = nil
		local state = states[userId]
		if not state then
			return
		end
		states[userId] = nil
		if deps.store.leaseSeconds then
			state.closing = true
			closing[userId] = state
			local kept: { Job } = {}
			for _, job in state.queue do
				if job.kind == "FinishRun" then
					table.insert(kept, job)
				else
					job.done(nil, "SessionLost")
				end
			end
			state.queue = kept
			pump(userId, state)
			return
		end
		state.closed = true
		failQueued(state, "SessionLost")
		if not state.busy and state.session then
			releaseLease(userId, state.session)
		end
	end

	local function poll()
		if not deps.store.leaseSeconds then
			return
		end
		for userId, state in states do
			if state.status == "Ready" then
				if not leaseSafe(state) then
					unavailable(state, "SessionLost")
				elseif state.nextRenewAt and deps.clock() >= state.nextRenewAt then
					state.renewPending = true
					pump(userId, state)
				end
			end
		end
	end
	local function shutdown()
		shuttingDown = true
		for userId, callback in waiting do
			waiting[userId] = nil
			callback("Unavailable", "SessionLost")
		end
		local ids: { number } = {}
		for userId in states do
			table.insert(ids, userId)
		end
		for _, userId in ids do
			release(userId)
		end
	end

	local function status(userId: number): (Status?, string?)
		local state = states[userId]
		return if state then state.status else nil, if state then state.reason else nil
	end

	-- Memory-only reader (safe inside GetBootstrap: no yield).
	local function profileOf(userId: number): ProfileV1?
		local state = states[userId]
		return if state and state.status == "Ready" then state.profile else nil
	end

	return table.freeze({
		backend = deps.store.backend,
		load = load,
		release = release,
		status = status,
		profileOf = profileOf,
		startRun = startRun,
		upgradeUnit = upgradeUnit,
		allocatePoint = allocatePoint,
		finishRun = finishRun,
		poll = poll,
		shutdown = shutdown,
		isIdle = function(): boolean
			return workers == 0 and next(states) == nil and next(closing) == nil
		end,
	})
end

export type Service = typeof(new(...))

return table.freeze({ new = new })
