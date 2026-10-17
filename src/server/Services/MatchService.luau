--!strict
-- Per-owner admission, stage/result flow and lobby transaction boundaries (remake R3).
-- Battles are server-only `Battle` instances; clients see owner-only snapshots.
local ProfileService = require("./ProfileService")
local ProfileSchema = require("./ProfileSchema")
local Economy = require("./Economy")
local Quests = require("./Quests")
local Store = require("./Store")
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
	passes: { [string]: boolean }, -- owned game passes (D-PAY-01), set by the market binding
	speed: number, -- battle steps per server tick: 1, or 2 with the speed pass
	holdUntil: number, -- tick until which a revive offer waits for an open purchase prompt
	purchaseRequest: string?, -- the Purchase request whose prompt is open
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
	-- R8 avatar combat: battle-unit (x, z) of the player's real character; the hero walks toward it.
	follow: ((userId: number) -> (number?, number?))?,
	-- D-PAY-01: opens the Robux prompt for Store item; returns a rejection reason (e.g. not configured)
	prompt: ((userId: number, item: number) -> string?)?,
	reviveForSale: (() -> boolean)?, -- the revive product is configured: offer revives without gems
}

-- Within this many battle units the hero stops chasing the character (no jitter around the target).
local FOLLOW_DEAD_ZONE = 4

local ACTIVE: { [Phase]: boolean } =
	{ Preparing = true, Running = true, Settling = true, Settled = true }
local REVIVE_GEMS = 20
local PROMPT_HOLD_TICKS = 90 * 30 -- a revive offer waits up to 90 s while its purchase prompt is open
local RECEIPT_WAIT_TICKS = 15 * 30 -- after a successful prompt, up to 15 s for the receipt to commit

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
	local passBook: { [number]: { [string]: boolean } } = {} -- D-PAY-01, may arrive before the session

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
			passes = passBook[userId] or {},
			speed = 1,
			holdUntil = 0,
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
		passBook[userId] = nil
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
		local profile = deps.profiles.profileOf(userId)
		if command.kind == "Revive" and (not profile or profile.gems < REVIVE_GEMS) then
			-- the offer may exist without gems when revives are for sale (D-PAY-01)
			local message = reply(
				userId,
				command.requestId,
				"Rejected",
				"InsufficientGems",
				{ matchId = session.matchId }
			)
			rememberAck(session, command.requestId, command.commandSeq, message)
			return
		end
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
					revives = if profile.gems >= REVIVE_GEMS
							or (deps.reviveForSale ~= nil and deps.reviveForSale())
						then 1
						else 0,
					darkEvent = run.stage == 0 and not profile.darkUnlocked, -- D-SVV-05
					rewardRate = if session.passes.goldExp then 2 else 1, -- D-PAY-01
				})
			battle.timeScale = session.speed
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

	-- D-PAY-01: the server opens the prompt so a revive offer can wait for it; the grant comes by receipt.
	local function purchase(userId: number, session: Session, command: any)
		local item = command.item
		local battle = session.battle
		local reason = if not deps.prompt
			then "Locked"
			elseif session.purchaseRequest then "Busy"
			else Store.canOffer(deps.profiles.profileOf(userId), item, session.passes)
		if not reason and item == Store.REVIVE and not (battle and battle.reviveOffer) then
			reason = "WrongPhase" -- a revive is bought only while it is offered
		end
		if not reason and deps.prompt then
			reason = deps.prompt(userId, item)
		end
		if reason then
			reply(userId, command.requestId, "Rejected", reason)
			return
		end
		session.purchaseRequest = command.requestId
		if item == Store.REVIVE then
			session.holdUntil = deps.tick() + PROMPT_HOLD_TICKS
		end
		reply(userId, command.requestId, "Pending")
	end

	local function setSpeed(userId: number, session: Session, command: any)
		local reason = if not session.passes.speed and command.speed ~= 1
			then "Locked"
			else ownershipReason(userId, session, command.matchId)
		if reason then
			reply(userId, command.requestId, "Rejected", reason)
			return
		end
		session.speed = command.speed
		if session.battle then
			session.battle.timeScale = command.speed
		end
		reply(userId, command.requestId, "Accepted", nil, { matchId = session.matchId })
	end

	local function handleCommand(userId: number, command: any)
		local session = sessions[userId]
		if not session then
			return
		end
		local kind = command.kind
		if kind == "Purchase" then
			if session.phase == "ProfileLoading" or session.phase == "Unavailable" then
				reply(userId, command.requestId, "Rejected", "NotReady")
			else
				purchase(userId, session, command)
			end
		elseif kind == "SetSpeed" then
			setSpeed(userId, session, command)
		elseif command.commandSeq ~= nil then
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
			speed = session.speed,
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
			local holding = battle ~= nil and battle.reviveOffer and session.holdUntil > deps.tick()
			for step = 1, if holding then 0 else session.speed do
				battle = session.battle
				if session.phase ~= "Running" or not battle then
					break
				end
				local commands = if step == 1 then session.pending else {}
				if step == 1 then
					session.pending = {}
				end
				local axis, strafe = effectiveAxis(userId), effectiveStrafe(userId)
				local follow = deps.follow
				if follow and battle.spatial and not battle.jump then
					-- server-side chase at the hero's own speed: the character never moves the hero faster
					local tx, tz = follow(userId)
					local hero = Battle.hero(battle)
					if tx and tz and hero then
						local dx, dz = tx - hero.x, tz - (hero.z or 0)
						axis = if math.abs(dx) > FOLLOW_DEAD_ZONE then math.sign(dx) else 0
						strafe = if math.abs(dz) > FOLLOW_DEAD_ZONE then math.sign(dz) else 0
					end
				end
				local result = Battle.step(battle, {
					commands = commands,
					axis = axis,
					strafe = strafe,
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

	-- Market binding hooks (D-PAY-01).
	local function setPasses(userId: number, passes: { [string]: boolean })
		passBook[userId] = table.clone(passes)
		local session = sessions[userId]
		if session then
			session.passes = table.clone(passes)
			if not passes.speed and session.speed ~= 1 then
				session.speed = 1
				if session.battle then
					session.battle.timeScale = 1
				end
			end
		end
	end
	-- the prompt closed; a bought product still arrives through its receipt, so a revive keeps waiting a bit
	local function purchaseClosed(userId: number, bought: boolean)
		local session = sessions[userId]
		if session then
			session.holdUntil = if bought and session.holdUntil > 0
				then deps.tick() + RECEIPT_WAIT_TICKS
				else 0
			local requestId = session.purchaseRequest
			session.purchaseRequest = nil
			if requestId then
				reply(userId, requestId, "Accepted")
			end
		end
	end
	-- a receipt was committed: refresh the client, and a bought revive is used at once
	local function granted(userId: number, item: number, profile: ServerTypes.ProfileV1)
		local session = sessions[userId]
		if not session then
			return
		end
		local battle = session.battle
		if
			item == Store.REVIVE
			and battle
			and battle.reviveOffer
			and session.phase == "Running"
		then
			table.insert(session.pending, { kind = "Revive", requestId = "store-revive" })
		end
		session.holdUntil = 0
		local requestId = session.purchaseRequest or "store-grant"
		session.purchaseRequest = nil
		reply(userId, requestId, "Committed", nil, {
			profileRevision = profile.revision,
			profileSummary = ProfileSchema.summary(profile),
		})
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
		setPasses = setPasses,
		purchaseClosed = purchaseClosed,
		granted = granted,
		speedOf = function(userId: number): number
			local session = sessions[userId]
			return if session then session.speed else 1
		end,
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
