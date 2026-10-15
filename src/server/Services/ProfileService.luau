--!strict
-- Profile session + transaction queue over an injected StoreAdapter (ARCHITECTURE §7-8, DATA_MODELS §5.1).
-- Store calls may yield (real DataStore), so they run inside deps.spawn; readers only touch memory.
-- One writer per profile: transactions, the load-time abandon and the final release all go through the
-- same busy flag, so a release never races an in-flight write.
local ServerTypes = require("../ServerTypes")
local Schema = require("./ProfileSchema")

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

local function new(deps: Deps)
	local states: { [number]: State } = {}

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
		deps.spawn(function()
			pcall(deps.store.release, userId, session) -- fenced: cannot clear a newer session's lease
		end)
	end

	local function transform(job: Job): ServerTypes.Transform
		return function(old: ProfileV1): (ProfileV1?, string?)
			local profile = Schema.deepClone(old)
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

	local function runJob(userId: number, state: State, job: Job)
		state.busy = true
		local session = state.session :: Session
		deps.spawn(function()
			local ok, result =
				pcall(deps.store.update, userId, session, deps.clock(), transform(job))
			state.busy = false
			if state.closed then
				job.done(nil, "SessionLost") -- player left; a committed effect is reconciled by the next load
				releaseLease(userId, session)
				return
			end
			if not ok or result.kind == "error" then
				job.done(nil, "StorageUnavailable")
			elseif result.kind == "stale" then
				setStatus(state, "Unavailable", "SessionLost")
				job.done(nil, "SessionLost")
				failQueued(state, "SessionLost")
				return
			elseif result.kind == "rejected" then
				job.done(nil, result.reason or "StorageUnavailable")
			else
				local saved = result.profile
				local committed = false
				if saved then
					for _, receipt in saved.recentOperations do
						committed = committed
							or (receipt.id == job.requestId and receipt.kind == job.kind)
					end
				end
				-- Success means the returned document carries this operation's receipt, not merely "no error".
				if saved and committed and Schema.validate(saved, deps.receiptCap) then
					state.profile = saved
					job.done(saved, nil)
				else
					job.done(nil, "StorageUnavailable")
				end
			end
			pump(userId, state)
		end)
	end

	pump = function(userId: number, state: State)
		if not state.busy and #state.queue > 0 and state.status == "Ready" and not state.closed then
			runJob(userId, state, table.remove(state.queue, 1) :: Job)
		end
	end

	-- Reconnect after a crash or a leave mid-run: close the leftover run as Abandoned with no reward (ARCH §7).
	local function abandonJob(profile: ProfileV1, done: Done): Job
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

	local function load(userId: number, onStatus: OnStatus)
		if states[userId] then
			return -- already loading/loaded for this server session
		end
		local state: State =
			{ status = "Loading", queue = {}, busy = false, closed = false, onStatus = onStatus }
		states[userId] = state
		deps.spawn(function()
			local key = { sessionId = deps.sessionId, jobId = deps.jobId }
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
			local loaded = if ok and result.kind == "ok" then result.profile else nil
			local session = if loaded
				then {
					sessionId = deps.sessionId,
					jobId = deps.jobId,
					fenceEpoch = loaded.fenceEpoch,
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
				return
			end
			state.profile, state.session = loaded, session
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
				local level = profile.unitLevels[op.unitId]
				local cost = Schema.upgradeCost(op.unitId, level)
				if profile.activeRun then
					return "WrongPhase"
				elseif level >= Schema.unitMaxLevel or cost == nil then
					return "MaxLevel"
				elseif profile.gold < cost then
					return "InsufficientGold"
				end
				profile.gold -= cost
				profile.unitLevels[op.unitId] = level + 1
				return nil
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
				if profile.activeRun then
					return "WrongPhase"
				elseif profile.unspentPoints < 1 then
					return "NoPoints"
				elseif profile.heroTraits[op.traitId] >= Schema.maxTraitPoints(op.traitId) then
					return "MaxLevel"
				end
				profile.unspentPoints -= 1
				profile.heroTraits[op.traitId] += 1
				return nil
			end,
		})
	end

	-- MVP closes the server-owned result without currency, XP or progression rewards.
	local function finishRun(userId: number, matchId: string, outcome: string, done: Done)
		local profile = states[userId] and states[userId].profile
		if not profile or not profile.activeRun then
			done(nil, "WrongPhase")
			return
		end
		local ordinal = profile.activeRun.ordinal
		enqueue(userId, {
			kind = "FinishRun",
			requestId = `finish-{ordinal}-{matchId}`,
			expectedRevision = profile.revision,
			done = done,
			mutate = function(current)
				local run = current.activeRun
				if not run or run.matchId ~= matchId or run.ordinal ~= ordinal then
					return "WrongPhase"
				elseif outcome ~= "Victory" and outcome ~= "Defeat" and outcome ~= "Timeout" then
					return "WrongPhase"
				end
				current.lastClosedRunOrdinal = ordinal
				current.lastRunResult = {
					ordinal = ordinal,
					matchId = matchId,
					outcome = outcome :: string,
					awardedGold = 0,
					awardedXp = 0,
				}
				current.activeRun = nil
				return nil
			end,
		})
	end

	-- Leave: fail queued work, then release the lease after any in-flight write (never in parallel with it).
	local function release(userId: number)
		local state = states[userId]
		if not state then
			return
		end
		states[userId] = nil
		state.closed = true
		failQueued(state, "SessionLost")
		if not state.busy and state.session then
			releaseLease(userId, state.session)
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
	})
end

export type Service = typeof(new(...))

return table.freeze({ new = new })
