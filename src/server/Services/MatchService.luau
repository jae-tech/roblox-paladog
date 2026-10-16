--!strict
-- Per-owner admission, stage/result flow and lobby transaction boundaries (remake R3).
-- Battles are server-only `Battle` instances; clients see owner-only snapshots.
local ProfileService = require("./ProfileService")
local ProfileSchema = require("./ProfileSchema")
local Economy = require("./Economy")
local Quests = require("./Quests")
local ServerTypes = require("../ServerTypes")
local Battle = require("../Battle/Battle")

type Phase =
	"ProfileLoading"
	| "LobbyReady"
	| "Preparing"
	| "Running"
	| "Settling"
	| "Settled"
	| "Unavailable"

export type Message = {
	requestId: string,
	status: "Accepted" | "Rejected" | "Pending" | "Committed",
	reason: string?,
	serverTick: number,
	profileRevision: number?,
	matchId: string?,
	profileSummary: any?,
}

type Ack = { commandSeq: number, message: Message }

type Session = {
	phase: Phase,
	matchId: string?,
	stage: number?,
	slot: number?,
	runOrdinal: number?,
	commandHigh: number,
	acks: { [string]: Ack },
	ackOrder: { string },
	moveSeq: number,
	moveAxis: number,
	moveStrafe: number,
	moveTick: number,
	pending: { any },
	snapshotSeq: number,
	battle: any?,
	finalView: any?,
	result: ServerTypes.MatchResult?,
}

export type Deps = {
	profiles: ProfileService.Service,
	tick: () -> number,
	newMatchId: () -> string,
	balanceHash: string,
	send: (userId: number, message: Message) -> (),
	maxMatches: number,
	ackCacheSize: number,
	moveTtlTicks: number,
	newSeed: (() -> number)?,
	spatial: boolean?,
}

local ACTIVE: { [Phase]: boolean } =
	{ Preparing = true, Running = true, Settling = true, Settled = true }
local REVIVE_GEMS = 20

-- Lobby kinds -> pure Economy transform (each re-checked against the stored document).
local LOBBY: { [string]: (ServerTypes.ProfileV1, any) -> string? } = {
	CreateSlot = function(p, c)
		return Economy.createSlot(p, c.slot, c.heroKind, c.difficulty)
	end,
	DeleteSlot = function(p, c)
		return Economy.deleteSlot(p, c.slot)
	end,
	SelectSlot = function(p, c)
		return Economy.selectSlot(p, c.slot)
	end,
	UpgradeUnit = function(p, c)
		return Economy.upgradeUnit(p, c.unit)
	end,
	LearnSkill = function(p, c)
		return Economy.learnSkill(p, c.skill)
	end,
	ResetSkills = function(p, _c)
		return Economy.resetSkills(p)
	end,
	BuyItem = function(p, c)
		return Economy.buyItem(p, c.category, c.num)
	end,
	SellItem = function(p, c)
		return Economy.sellItem(p, c.index)
	end,
	Equip = function(p, c)
		return Economy.equip(p, c.index, c.slot)
	end,
	Unequip = function(p, c)
		return Economy.unequip(p, c.slot)
	end,
	Enchant = function(p, c)
		return Economy.enchant(p, c.where, c.index)
	end,
	GemShop = function(p, c)
		return Economy.gemShop(p, c.item)
	end,
}

local function freezeResult(result: ServerTypes.MatchResult)
	table.freeze(result.picks)
	table.freeze(result.quests)
	table.freeze(result)
end

local function new(deps: Deps)
	local sessions: { [number]: Session } = {}
	local owners: { [string]: number } = {} -- matchId -> owner userId

	local function reply(
		userId: number,
		requestId: string,
		status: any,
		reason: string?,
		extra: { [string]: any }?
	)
		local message: Message =
			{ requestId = requestId, status = status, reason = reason, serverTick = deps.tick() }
		if extra then
			message.profileRevision = extra.profileRevision
			message.matchId = extra.matchId
			message.profileSummary = extra.profileSummary
		end
		deps.send(userId, message)
		return message
	end

	local function activeMatches(): number
		local count = 0
		for _, session in sessions do
			if ACTIVE[session.phase] then
				count += 1
			end
		end
		return count
	end

	local function leaveMatch(session: Session)
		if session.matchId then
			owners[session.matchId] = nil
		end
		session.matchId, session.stage, session.slot, session.runOrdinal = nil, nil, nil, nil
		session.battle, session.finalView, session.result, session.pending = nil, nil, nil, {}
	end

	local function playerJoined(userId: number)
		if sessions[userId] then
			return -- PlayerAdded and the initial GetPlayers() sweep may both report the same player
		end
		local session: Session = {
			phase = "ProfileLoading",
			commandHigh = 0,
			acks = {},
			ackOrder = {},
			moveSeq = 0,
			moveAxis = 0,
			moveStrafe = 0,
			moveTick = -math.huge,
			pending = {},
			snapshotSeq = 0,
		}
		sessions[userId] = session
		deps.profiles.load(userId, function(status)
			if sessions[userId] ~= session then
				return
			end
			if status == "Ready" then
				session.phase = if session.phase == "ProfileLoading"
					then "LobbyReady"
					else session.phase
			elseif status == "Unavailable" then
				-- Storage lost (load failure or a stale writer): stop the session so nothing waits on it.
				leaveMatch(session)
				session.phase = "Unavailable"
			end
		end)
	end

	local function playerLeft(userId: number)
		local session = sessions[userId]
		if session then
			leaveMatch(session)
		end
		sessions[userId] = nil
		deps.profiles.release(userId)
	end

	local function ownershipReason(userId: number, session: Session, matchId: string?): string?
		if matchId ~= nil and owners[matchId] ~= nil and owners[matchId] ~= userId then
			return "NotOwner" -- someone else's match: never touches either session
		elseif session.matchId == nil or matchId ~= session.matchId then
			return "WrongPhase"
		end
		return nil
	end

	local function rememberAck(
		session: Session,
		requestId: string,
		commandSeq: number,
		message: Message
	)
		session.acks[requestId] = { commandSeq = commandSeq, message = message }
		table.insert(session.ackOrder, requestId)
		if #session.ackOrder > deps.ackCacheSize then
			session.acks[table.remove(session.ackOrder, 1) :: string] = nil
		end
	end

	local function battleCommand(userId: number, session: Session, command: any)
		local cached = session.acks[command.requestId]
		if cached then
			if cached.commandSeq == command.commandSeq then
				deps.send(userId, cached.message) -- duplicate delivery: same ack, no second effect
			else
				reply(userId, command.requestId, "Rejected", "StaleCommand")
			end
			return
		end
		-- A foreign match id is reported as such in every phase; it never touches either session.
		local owner = owners[command.matchId]
		local reason = if owner ~= nil and owner ~= userId
			then "NotOwner"
			elseif session.phase ~= "Running" then "WrongPhase"
			else ownershipReason(userId, session, command.matchId)
		if
			reason == "NotOwner" or (reason == nil and command.commandSeq <= session.commandHigh)
		then
			reply(userId, command.requestId, "Rejected", reason or "StaleCommand")
			return
		elseif reason then
			reply(userId, command.requestId, "Rejected", reason)
			return
		end
		session.commandHigh = command.commandSeq
		table.insert(session.pending, {
			kind = command.kind,
			unit = command.unit,
			lane = if command.lane and command.lane > 0 then command.lane else nil,
			slot = command.slot,
			index = command.index,
			choice = command.choice,
			requestId = command.requestId,
		})
		local message =
			reply(userId, command.requestId, "Pending", nil, { matchId = session.matchId })
		rememberAck(session, command.requestId, command.commandSeq, message)
	end

	local function lobbyCommand(userId: number, session: Session, command: any)
		if session.phase ~= "LobbyReady" then
			reply(userId, command.requestId, "Rejected", "WrongPhase")
			return
		end
		local mutate = LOBBY[command.kind]
		reply(userId, command.requestId, "Pending")
		deps.profiles.transact(userId, {
			kind = command.kind,
			requestId = command.requestId,
			expectedRevision = command.expectedRevision,
			mutate = function(profile)
				return mutate(profile, command)
			end,
		}, function(profile, reason)
			if sessions[userId] ~= session then
				return
			end
			if profile then
				reply(userId, command.requestId, "Committed", nil, {
					profileRevision = profile.revision,
					profileSummary = ProfileSchema.summary(profile),
				})
			else
				local current = deps.profiles.profileOf(userId)
				reply(userId, command.requestId, "Rejected", reason, {
					profileRevision = if current then current.revision else nil,
					profileSummary = if current then ProfileSchema.summary(current) else nil,
				})
			end
		end)
	end

	local function startStage(userId: number, session: Session, command: any)
		if session.phase ~= "LobbyReady" then
			reply(userId, command.requestId, "Rejected", "WrongPhase")
			return
		elseif activeMatches() >= deps.maxMatches then
			reply(userId, command.requestId, "Rejected", "Busy")
			return
		end
		local matchId = deps.newMatchId()
		session.phase = "Preparing"
		reply(userId, command.requestId, "Pending")
		deps.profiles.startRun(userId, {
			requestId = command.requestId,
			expectedRevision = command.expectedRevision,
			stage = command.stage,
			matchId = matchId,
			balanceHash = deps.balanceHash,
		}, function(profile, reason)
			if sessions[userId] ~= session then
				return
			end
			local run = profile and profile.activeRun
			-- The committed document must carry the run this request started (operation identity).
			if not profile or not run or run.startOperationId ~= command.requestId then
				if session.phase == "Preparing" then
					session.phase = "LobbyReady"
				end
				reply(userId, command.requestId, "Rejected", reason or "StaleCommand")
				return
			end
			local runSlot = profile.slots[run.slot] :: ServerTypes.Slot
			local battle =
				Battle.new({ -- built first: a config error must not leave Running without a battle
					spatial = deps.spatial,
					stage = run.stage,
					seed = if deps.newSeed then deps.newSeed() else 12345,
					loadout = ProfileSchema.loadoutOf(runSlot),
					cleared = run.stage >= 1 and runSlot.stars[run.stage] >= 1,
					goldAvailable = runSlot.gold,
					revives = if profile.gems >= REVIVE_GEMS then 1 else 0,
					darkEvent = run.stage == 0 and not profile.darkUnlocked, -- D-SVV-05
				})
			session.phase, session.matchId, session.stage, session.runOrdinal =
				"Running", run.matchId, run.stage, run.ordinal
			session.slot = run.slot
			session.commandHigh, session.moveSeq, session.moveAxis, session.snapshotSeq = 0, 0, 0, 0
			session.moveStrafe = 0
			session.acks, session.ackOrder, session.pending = {}, {}, {} -- request cache is scoped to one match
			session.battle, session.finalView, session.result = battle, nil, nil
			owners[run.matchId] = userId
			reply(userId, command.requestId, "Committed", nil, {
				matchId = run.matchId,
				profileRevision = profile.revision,
			})
		end)
	end

	local function handleCommand(userId: number, command: any)
		local session = sessions[userId]
		if not session then
			return
		end
		local kind = command.kind
		if command.commandSeq ~= nil then
			battleCommand(userId, session, command)
		elseif kind == "StartStage" then
			startStage(userId, session, command)
		elseif LOBBY[kind] then
			lobbyCommand(userId, session, command)
		elseif kind == "ReturnToLobby" then
			local reason = if session.phase ~= "Settled"
				then "WrongPhase"
				else ownershipReason(userId, session, command.matchId)
			if reason then
				reply(userId, command.requestId, "Rejected", reason)
				return
			end
			leaveMatch(session)
			session.phase = "LobbyReady"
			local profile = deps.profiles.profileOf(userId)
			reply(userId, command.requestId, "Accepted", nil, {
				profileRevision = if profile then profile.revision else nil,
				profileSummary = if profile then ProfileSchema.summary(profile) else nil,
			})
		end
	end

	-- Returns false when ignored (stale seq, foreign/unknown match, wrong phase); only the newest intent counts.
	local function handleMove(userId: number, intent: any): boolean
		local session = sessions[userId]
		if
			not session
			or session.phase ~= "Running"
			or intent.matchId ~= session.matchId
			or intent.seq <= session.moveSeq
		then
			return false
		end
		session.moveSeq, session.moveAxis, session.moveTick = intent.seq, intent.axis, deps.tick()
		session.moveStrafe = intent.strafe or 0
		return true
	end

	local function effectiveAxis(userId: number): number
		local session = sessions[userId]
		if not session or deps.tick() - session.moveTick > deps.moveTtlTicks then
			return 0
		end
		return session.moveAxis
	end

	local function phaseOf(userId: number): Phase?
		local session = sessions[userId]
		return if session then session.phase else nil
	end

	local function effectiveStrafe(userId: number): number
		local s = sessions[userId]
		return if s and deps.tick() - s.moveTick <= deps.moveTtlTicks then s.moveStrafe else 0
	end

	-- Owner-only snapshot (complete state each time, no deltas). Attack power and internals stay server-side.
	local function snapshot(userId: number): { [string]: any }?
		local session = sessions[userId]
		if not session or not session.matchId then
			return nil
		end
		session.snapshotSeq += 1
		local view = if session.battle then Battle.snapshot(session.battle) else session.finalView
		local committedProfile = if session.phase == "Settled"
			then deps.profiles.profileOf(userId)
			else nil
		local ledger = if committedProfile then committedProfile.lastRunResult else nil
		return {
			matchId = session.matchId,
			snapshotSeq = session.snapshotSeq,
			phase = session.phase,
			stage = session.stage,
			balanceHash = deps.balanceHash,
			inputAckSeq = session.moveSeq,
			commandAckSeq = session.commandHigh,
			battle = view,
			result = session.result,
			profileRevision = if committedProfile then committedProfile.revision else nil,
			profileSummary = if committedProfile
				then ProfileSchema.summary(committedProfile)
				else nil,
			rewards = if ledger
					and ledger.matchId == session.matchId
					and ledger.ordinal == session.runOrdinal
				then ProfileSchema.deepClone(ledger)
				else nil,
			settlementStatus = if session.phase == "Settling"
				then "Pending"
				elseif session.phase == "Settled" then "Committed"
				elseif session.result then "Failed"
				else nil,
		}
	end

	local function settle(userId: number, session: Session, battle: any)
		local stats = Quests.statsOf(battle, Battle)
		local frozen: ServerTypes.MatchResult = {
			matchId = session.matchId :: string,
			runOrdinal = session.runOrdinal :: number,
			slot = session.slot :: number,
			stage = session.stage :: number,
			balanceHash = deps.balanceHash,
			seed = battle.seed,
			outcome = battle.outcome,
			elapsedTicks = battle.tick,
			gold = battle.rewards.gold,
			goldSpent = battle.rewards.goldSpent,
			exp = battle.exp,
			levelUps = battle.rewards.levelUps,
			picks = table.clone(battle.rewards.picks),
			drops = #battle.rewards.drops,
			revives = battle.rewards.revives,
			killTotal = battle.rewards.killTotal,
			quests = Quests.evaluate(session.stage :: number, stats, battle.loadout.heroKind),
		}
		if battle.mode == "Survival" then
			frozen.wave, frozen.gems, frozen.darkUnlock =
				battle.wave, battle.rewards.gems, battle.rewards.darkUnlock
		end
		freezeResult(frozen)
		session.result = frozen
		session.finalView = Battle.snapshot(battle)
		session.battle = nil -- the final view stays for the result screen; the battle state is released
		deps.profiles.finishRun(userId, frozen, function(profile)
			if sessions[userId] == session and session.phase == "Settling" then
				local saved = profile and profile.lastRunResult
				local committed = profile ~= nil
					and saved ~= nil
					and saved.matchId == frozen.matchId
					and saved.ordinal == frozen.runOrdinal
					and saved.outcome == frozen.outcome
					and not profile.activeRun
				session.phase = if committed then "Settled" else "Unavailable"
			end
		end)
	end

	-- One simulation tick for every running match; replies carry the final Accepted/Rejected per command.
	local function stepAll()
		for userId, session in sessions do
			local battle = session.battle
			if session.phase == "Running" and battle then
				local commands = session.pending
				session.pending = {}
				local result = Battle.step(battle, {
					commands = commands,
					axis = effectiveAxis(userId),
					strafe = effectiveStrafe(userId),
				})
				for _, outcome in result.results do
					local requestId = outcome.requestId or ""
					local message = reply(
						userId,
						requestId,
						outcome.status,
						outcome.reason,
						{ matchId = session.matchId }
					)
					local cached = session.acks[requestId]
					if cached then
						cached.message = message -- duplicates now get the final answer
					end
				end
				if result.outcome then
					session.phase = "Settling"
					settle(userId, session, battle)
				end
			end
		end
	end

	return table.freeze({
		playerJoined = playerJoined,
		playerLeft = playerLeft,
		handleCommand = handleCommand,
		handleMove = handleMove,
		effectiveAxis = effectiveAxis,
		effectiveStrafe = effectiveStrafe,
		phaseOf = phaseOf,
		snapshot = snapshot,
		stepAll = stepAll,
		takePending = function(
			userId: number
		): { any } -- tests/diagnostics: drains queued battle commands
			local session = sessions[userId]
			if not session then
				return {}
			end
			local pending = session.pending
			session.pending = {}
			return pending
		end,
		battleOf = function(userId: number): any
			local session = sessions[userId]
			return if session then session.battle else nil -- server diagnostics/tests only; never replicated
		end,
		activeMatches = activeMatches,
		ownedMatchCount = function(): number -- diagnostics/tests: must return to 0 after matches end
			local count = 0
			for _ in owners do
				count += 1
			end
			return count
		end,
		resultOf = function(userId: number): ServerTypes.MatchResult?
			local session = sessions[userId]
			return if session then session.result else nil
		end,
	})
end

export type Service = typeof(new(...))

return table.freeze({ new = new })
