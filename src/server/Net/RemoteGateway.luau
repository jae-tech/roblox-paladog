--!strict
-- Remote ingress core (ARCHITECTURE §6.1). Pure and testable in the Luau CLI; RemoteBinding attaches it to
-- RemoteFunction/RemoteEvents. Identity comes only from the engine's Player argument, never the payload.
local TokenBucket = require("./TokenBucket")
local MatchService = require("../Services/MatchService")
local ProfileService = require("../Services/ProfileService")
local ProfileSchema = require("../Services/ProfileSchema")

type Bucket = TokenBucket.Bucket

type PlayerState = {
	discrete: Bucket,
	move: Bucket,
	bootstrap: Bucket,
	queued: number,
	rejects: { [string]: number },
}

type Ingress = { ordinal: number, userId: number, state: PlayerState, command: any }

export type Deps = {
	protocol: any, -- shared Protocol module (injected: server and shared trees cannot require each other by path)
	publicCatalog: { [string]: any },
	match: MatchService.Service,
	profiles: ProfileService.Service,
	clock: () -> number, -- monotonic seconds for rate limiting
	tick: () -> number,
	balanceHash: string,
	send: (userId: number, channel: string, payload: any) -> (),
}

local function newCore(deps: Deps)
	local limits = deps.protocol.LIMITS
	local players: { [number]: PlayerState } = {}
	local queue: { Ingress } = {}
	local nextOrdinal = 0
	local metrics = { dropped = 0 }

	local function playerAdded(userId: number)
		if players[userId] then
			return -- idempotent: PlayerAdded may race the initial GetPlayers() sweep
		end
		local now = deps.clock()
		players[userId] = {
			discrete = TokenBucket.new(limits.discreteRate, limits.discreteBurst, now),
			move = TokenBucket.new(limits.moveRate, limits.moveBurst, now),
			bootstrap = TokenBucket.new(limits.bootstrapRate, limits.bootstrapBurst, now),
			queued = 0,
			rejects = {},
		}
		deps.match.playerJoined(userId)
	end

	local function playerRemoving(userId: number)
		players[userId] = nil
		deps.match.playerLeft(userId)
	end

	-- Aggregated (bounded: reason enum) rejection counts instead of a log line per bad packet.
	local function reject(userId: number, state: PlayerState, requestId: string, reason: string)
		state.rejects[reason] = (state.rejects[reason] or 0) + 1
		deps.send(userId, "ServerMessage", {
			requestId = requestId,
			status = "Rejected",
			reason = reason,
			serverTick = deps.tick(),
		})
	end

	local function clientCommand(userId: number, payload: unknown)
		local state = players[userId]
		if not state then
			return
		end
		if not TokenBucket.take(state.discrete, deps.clock()) then
			state.rejects.RateLimited = (state.rejects.RateLimited or 0) + 1
			metrics.dropped += 1 -- over budget: dropped without a reply so floods cannot amplify outbound traffic
			return
		end
		local command, reason = deps.protocol.validateCommand(payload)
		if not command then
			reject(userId, state, deps.protocol.echoRequestId(payload), reason)
			return
		end
		if state.queued >= limits.queueCapacity then
			reject(userId, state, command.requestId, "Busy")
			return
		end
		nextOrdinal += 1
		state.queued += 1
		table.insert(
			queue,
			{ ordinal = nextOrdinal, userId = userId, state = state, command = command }
		)
	end

	local function moveIntent(userId: number, payload: unknown): boolean
		local state = players[userId]
		if not state or not TokenBucket.take(state.move, deps.clock()) then
			return false
		end
		local intent = deps.protocol.validateMove(payload)
		return intent ~= nil and deps.match.handleMove(userId, intent)
	end

	-- Runs inside the RemoteFunction callback: memory reads only, no yield, no store access.
	local function getBootstrap(userId: number, payload: unknown)
		local result: { [string]: any } = {
			protocolVersion = deps.protocol.VERSION,
			storage = deps.profiles.backend,
			balanceHash = deps.balanceHash,
		}
		local state = players[userId]
		local now = deps.clock()
		if not state then
			result.status = "Loading" -- not yet registered by PlayerAdded
			return result
		elseif not TokenBucket.take(state.bootstrap, now) then
			result.status = "RateLimited"
			result.retryAfterSeconds = TokenBucket.retryAfter(state.bootstrap, now)
			return result
		end
		local reason = deps.protocol.validateBootstrap(payload)
		if reason then
			result.status = if reason == "ProtocolMismatch"
				then "ProtocolMismatch"
				else "Unavailable"
			return result
		end
		local status = deps.profiles.status(userId)
		local profile = deps.profiles.profileOf(userId)
		result.status = if status == "Ready"
			then "Ready"
			elseif status == "Loading" then "Loading"
			else "Unavailable"
		result.phase = deps.match.phaseOf(userId)
		result.catalogVersion = deps.publicCatalog.version -- the client requires the shared catalog itself
		if profile then
			result.profileRevision = profile.revision
			result.profileSummary = ProfileSchema.summary(profile)
		end
		result.currentMatch = deps.match.snapshot(userId)
		return result
	end

	-- Called once per server step: processes accepted commands in ingress order.
	local function drain()
		local batch = queue
		queue = {}
		for _, item in batch do
			-- Commands from a previous session (leave/rejoin before drain) are discarded, not replayed.
			if players[item.userId] == item.state then
				item.state.queued -= 1
				deps.match.handleCommand(item.userId, item.command)
			end
		end
	end

	local function publishSnapshots()
		for userId in players do
			local snapshot = deps.match.snapshot(userId)
			if snapshot then
				deps.send(userId, "MatchSnapshot", snapshot) -- owner only
			end
		end
	end

	local function rejectCounts(userId: number): { [string]: number }
		local state = players[userId]
		return if state then table.clone(state.rejects) else {}
	end

	return table.freeze({
		playerAdded = playerAdded,
		playerRemoving = playerRemoving,
		clientCommand = clientCommand,
		moveIntent = moveIntent,
		getBootstrap = getBootstrap,
		drain = drain,
		publishSnapshots = publishSnapshots,
		rejectCounts = rejectCounts,
		metrics = metrics,
	})
end

export type Core = typeof(newCore(...))

return table.freeze({ newCore = newCore })
