--!strict
-- Per-owner admission, stage/result flow and atomic progression command boundaries.
local ProfileService = require("./ProfileService")
local ProfileSchema = require("./ProfileSchema")
local ServerTypes = require("../ServerTypes")
local World = require("../Simulation/World")
local SimTypes = require("../Simulation/SimTypes")

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
	stageId: string?,
	runOrdinal: number?,
	commandHigh: number,
	acks: { [string]: Ack },
	ackOrder: { string },
	moveSeq: number,
	moveAxis: number,
	moveTick: number,
	pending: { any },
	snapshotSeq: number,
	world: SimTypes.World?,
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
	stageFlow: boolean?,
	newSeed: (() -> number)?,
}

local ACTIVE: { [Phase]: boolean } =
	{ Preparing = true, Running = true, Settling = true, Settled = true }

-- Freeze in one boundary so both pinned Luau analyzers retain the declared DTO type.
local function freezeResult(result: ServerTypes.MatchResult)
	table.freeze(result.killCounts)
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
				if session.matchId then
					owners[session.matchId] = nil
				end
				session.phase, session.matchId, session.stageId, session.runOrdinal =
					"Unavailable", nil, nil, nil
				session.pending, session.world = {}, nil
			end
		end)
	end

	local function playerLeft(userId: number)
		local session = sessions[userId]
		if session and session.matchId then
			owners[session.matchId] = nil
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
		local reason = if session.phase ~= "Running"
			then "WrongPhase"
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
			slot = command.slot,
			commandSeq = command.commandSeq,
			requestId = command.requestId,
		})
		local message =
			reply(userId, command.requestId, "Pending", nil, { matchId = session.matchId })
		rememberAck(session, command.requestId, command.commandSeq, message)
	end

	local function profileCommand(
		userId: number,
		session: Session,
		command: any,
		start: (any) -> ()
	)
		if session.phase ~= "LobbyReady" then
			reply(userId, command.requestId, "Rejected", "WrongPhase")
			return
		end
		reply(userId, command.requestId, "Pending")
		start(function(profile, reason)
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
			stageId = command.stageId,
			matchId = matchId,
			balanceHash = deps.balanceHash,
		}, function(profile, reason)
			if sessions[userId] ~= session then
				return
			end
			local run = profile and profile.activeRun
			-- The committed document must carry the run this request started (operation identity, ARCH §6.1).
			if not run or run.startOperationId ~= command.requestId then
				if session.phase == "Preparing" then
					session.phase = "LobbyReady"
				end
				reply(userId, command.requestId, "Rejected", reason or "StaleCommand")
				return
			end
			-- Running starts only after activeRun is committed; a replayed start returns the stored run.
			local loaded = profile :: any
			local world =
				World.new({ -- built first: a config error must not leave a Running session without a world
					stageId = run.stageId,
					stageSpawns = deps.stageFlow,
					seed = if deps.newSeed then deps.newSeed() else 12345,
					unitLevels = loaded.unitLevels,
					heroTraits = loaded.heroTraits, -- copied by World: growth is fixed for the whole match
				})
			session.phase, session.matchId, session.stageId, session.runOrdinal =
				"Running", run.matchId, run.stageId, run.ordinal
			session.commandHigh, session.moveSeq, session.moveAxis, session.snapshotSeq = 0, 0, 0, 0
			session.acks, session.ackOrder, session.pending = {}, {}, {} -- request cache is scoped to one match
			session.world = world
			session.result = nil
			owners[run.matchId] = userId
			reply(userId, command.requestId, "Committed", nil, {
				matchId = run.matchId,
				profileRevision = (profile :: any).revision,
			})
		end)
	end

	local function handleCommand(userId: number, command: any)
		local session = sessions[userId]
		if not session then
			return
		end
		local kind = command.kind
		if kind == "Summon" or kind == "Cast" then
			battleCommand(userId, session, command)
		elseif kind == "StartStage" then
			startStage(userId, session, command)
		elseif kind == "UpgradeUnit" then
			profileCommand(userId, session, command, function(done)
				deps.profiles.upgradeUnit(userId, command, done)
			end)
		elseif kind == "AllocatePoint" then
			profileCommand(userId, session, command, function(done)
				deps.profiles.allocatePoint(userId, command, done)
			end)
		elseif kind == "ReturnToLobby" then
			local reason = if session.phase ~= "Settled"
				then "WrongPhase"
				else ownershipReason(userId, session, command.matchId)
			if reason then
				reply(userId, command.requestId, "Rejected", reason)
				return
			end
			owners[session.matchId :: string] = nil
			session.phase, session.matchId, session.stageId, session.runOrdinal =
				"LobbyReady", nil, nil, nil
			session.world = nil
			session.result = nil
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

	-- Owner-only snapshot (complete state each time, no deltas). Attack power and internals stay server-side.
	local function snapshot(userId: number): { [string]: any }?
		local session = sessions[userId]
		if not session or not session.matchId then
			return nil
		end
		session.snapshotSeq += 1
		local world = session.world
		local committedProfile = if session.phase == "Settled"
			then deps.profiles.profileOf(userId)
			else nil
		local ledger = if committedProfile then committedProfile.lastRunResult else nil
		return {
			matchId = session.matchId,
			snapshotSeq = session.snapshotSeq,
			tick = if world then world.tick else deps.tick(),
			phase = session.phase,
			stageId = session.stageId,
			balanceHash = deps.balanceHash,
			inputAckSeq = session.moveSeq,
			commandAckSeq = session.commandHigh,
			stageLength = if world then world.stage.length else nil,
			advanceLimitX = if world then world.stage.advanceLimitX else nil,
			heroMoveSpeed = if world then world.entities[world.heroId].moveSpeed else nil,
			pendingKillGold = if world then world.pendingKillGold else 0,
			pendingKillXp = if world then world.pendingKillXp else 0,
			resources = if world
				then {
					foodMilli = world.resources.foodMilli,
					manaMilli = world.resources.manaMilli,
					foodMaxMilli = world.resources.foodMaxMilli,
					manaMaxMilli = world.resources.manaMaxMilli,
					summonReadyTick = table.clone(world.resources.summonReadyTick),
					skillReadyTick = world.resources.skillReadyTick,
				}
				else nil,
			entities = if world then World.snapshotEntities(world) else {},
			projectiles = if world then World.snapshotProjectiles(world) else {},
			heroAction = if world then World.snapshotHeroAction(world) else {},
			outcome = if world then world.outcome else nil,
			result = session.result,
			profileRevision = if committedProfile then committedProfile.revision else nil,
			profileSummary = if committedProfile
				then ProfileSchema.summary(committedProfile)
				else nil,
			rewards = if ledger
					and ledger.matchId == session.matchId
					and ledger.ordinal == session.runOrdinal
				then { gold = ledger.awardedGold, xp = ledger.awardedXp }
				else nil,
			settlementStatus = if session.phase == "Settling"
				then "Pending"
				elseif session.phase == "Settled" then "Committed"
				elseif session.result then "Failed"
				else nil,
		}
	end

	-- One simulation tick for every running match; replies carry the final Accepted/Rejected per command.
	local function stepAll()
		for userId, session in sessions do
			local world = session.world
			if session.phase == "Running" and world then
				local commands = session.pending
				session.pending = {}
				local result =
					World.step(world, { commands = commands, axis = effectiveAxis(userId) })
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
					if deps.stageFlow then
						local frozen: ServerTypes.MatchResult = {
							matchId = session.matchId :: string,
							runOrdinal = session.runOrdinal :: number,
							stageId = world.stageId,
							balanceHash = deps.balanceHash,
							seed = if world.spawner then world.spawner.seed else 12345,
							outcome = result.outcome,
							elapsedTicks = world.tick,
							killCounts = table.clone(world.killCounts),
							pendingKillGold = world.pendingKillGold,
							pendingKillXp = world.pendingKillXp,
						}
						freezeResult(frozen)
						session.result = frozen
						World.clearBattle(world)
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
				end
			end
		end
	end

	local function takePending(userId: number): { any }
		local session = sessions[userId]
		if not session then
			return {}
		end
		local pending = session.pending
		session.pending = {}
		return pending
	end

	return table.freeze({
		playerJoined = playerJoined,
		playerLeft = playerLeft,
		handleCommand = handleCommand,
		handleMove = handleMove,
		effectiveAxis = effectiveAxis,
		phaseOf = phaseOf,
		snapshot = snapshot,
		takePending = takePending,
		stepAll = stepAll,
		worldOf = function(userId: number): SimTypes.World?
			local session = sessions[userId]
			return if session then session.world else nil -- server diagnostics/tests only; never replicated
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
