--!strict
-- Remake client controller: bootstrap, lobby/battle intents, server message/snapshot authority and bounded
-- local hero prediction. The server decides everything; this only builds requests and views.
local SnapshotBuffer = require("./SnapshotBuffer")

export type Deps = {
	protocol: any,
	send: (string, any) -> (),
	requestId: () -> string,
}

local PREDICTION_LEAD = 0.15 -- seconds of unacknowledged input the hero may lead the server

local function new(deps: Deps)
	local protocol = deps.protocol
	local buffer = SnapshotBuffer.new(protocol.BALANCE_HASH)
	local state: any = {
		phase = "ProfileLoading",
		storage = "연결 대기",
		profileRevision = 0,
		summary = nil,
		matchId = nil,
		commandSeq = 0,
		moveSeq = 0,
		axis = 0,
		strafe = 0,
		reason = nil,
		reasonAt = -math.huge,
		profileRequest = nil,
		profileBusyAt = 0,
	}
	local pending: { [string]: any } = {}
	local order: { string } = {}
	local history: { any } = {}
	local destroyed = false
	local nextBootstrap, token, epoch = 0, 0, 0
	local inflight: any = nil
	local lastSnapshot = -math.huge
	local matchStarted = 0
	local preparingAt = 0

	local function applyProfile(revision: any, summary: any)
		if type(revision) ~= "number" or revision % 1 ~= 0 or revision < state.profileRevision then
			return
		end
		state.profileRevision = revision
		if type(summary) == "table" then
			state.summary = summary
		end
	end
	local function switchMatch(id: string?, now: number)
		if state.matchId ~= id then
			epoch += 1
			state.matchId = id
			state.moveSeq, state.commandSeq, state.axis, state.strafe = 0, 0, 0, 0
			table.clear(history)
			buffer.setMatch(id)
			lastSnapshot, matchStarted = -math.huge, now
		end
	end
	local function setReason(reason: string?, now: number)
		state.reason, state.reasonAt = reason, now
	end
	local function receiveSnapshot(payload: any, now: number): boolean
		if destroyed or not buffer.accept(payload, now) then
			return false
		end
		lastSnapshot = now
		state.phase = payload.phase
		applyProfile(payload.profileRevision, payload.profileSummary)
		state.moveSeq = math.max(state.moveSeq, payload.inputAckSeq)
		state.commandSeq = math.max(state.commandSeq, payload.commandAckSeq or 0)
		local keep = {}
		for _, input in history do
			if input.seq > payload.inputAckSeq then
				table.insert(keep, input)
			end
		end
		history = keep
		return true
	end
	local function beginBootstrap(now: number): number?
		if destroyed or inflight or now < nextBootstrap then
			return nil
		end
		token += 1
		inflight = { token = token, time = now, epoch = epoch }
		nextBootstrap = now + 1
		return token
	end
	local function finishBootstrap(id: number, payload: any, now: number): boolean
		if destroyed or not inflight or inflight.token ~= id then
			return false
		end
		local requestedEpoch = inflight.epoch
		inflight = nil
		if requestedEpoch ~= epoch then
			return false
		end
		if type(payload) ~= "table" then
			setReason("StorageUnavailable", now)
			return false
		end
		if
			payload.protocolVersion ~= protocol.VERSION
			or payload.balanceHash ~= protocol.BALANCE_HASH
		then
			state.phase = "Unavailable"
			setReason("ProtocolMismatch", now)
			return false
		end
		state.storage = payload.storage or "Unknown"
		if payload.status ~= "Ready" then
			setReason(payload.status, now)
			if payload.status == "Unavailable" then
				state.profileRequest = nil
				switchMatch(nil, now)
				state.phase, state.axis = "Unavailable", 0
			end
			return false
		end
		applyProfile(payload.profileRevision or 0, payload.profileSummary)
		if state.profileRequest and now - state.profileBusyAt >= 3 then
			state.profileRequest = nil -- release only the UI wait after an authoritative read
		end
		local snapshot = payload.currentMatch
		if snapshot then
			switchMatch(snapshot.matchId, now)
			receiveSnapshot(snapshot, now)
		else
			switchMatch(nil, now)
			state.phase = payload.phase
		end
		return true
	end
	local function sendCommand(payload: any, now: number, profileOp: boolean)
		local id = deps.requestId()
		payload.protocolVersion, payload.requestId = protocol.VERSION, id
		pending[id] = { kind = payload.kind, matchId = payload.matchId, epoch = epoch }
		if profileOp then
			state.profileRequest, state.profileBusyAt = id, now
		end
		table.insert(order, id)
		if #order > 128 then
			local expired = table.remove(order, 1)
			if expired then
				pending[expired] = nil
			end
		end
		deps.send("ClientCommand", payload)
	end

	-- Lobby transaction (CreateSlot, UpgradeUnit, Equip, ...): one in flight at a time, revision-guarded.
	local function lobby(kind: string, fields: { [string]: any }?, now: number): boolean
		if destroyed or state.phase ~= "LobbyReady" or state.profileRequest then
			return false
		end
		local payload: { [string]: any } = { kind = kind, expectedRevision = state.profileRevision }
		local extra: { [string]: any } = fields or {}
		for k, v in extra do
			payload[k] = v
		end
		sendCommand(payload, now, true)
		return true
	end
	local function start(stage: number, now: number): boolean
		if destroyed or state.phase ~= "LobbyReady" or state.profileRequest then
			return false
		end
		sendCommand(
			{ kind = "StartStage", stage = stage, expectedRevision = state.profileRevision },
			now,
			false
		)
		state.phase, preparingAt = "Preparing", now
		return true
	end
	local function returnToLobby(now: number): boolean
		if destroyed or state.phase ~= "Settled" or not state.matchId then
			return false
		end
		sendCommand({ kind = "ReturnToLobby", matchId = state.matchId }, now, false)
		return true
	end
	-- Battle command (Summon/Mace/Box/PickSkill/Revive/GiveUp/Retreat); refused on a stale view.
	local function battle(kind: string, fields: { [string]: any }?, now: number): boolean
		if
			destroyed
			or not protocol.BATTLE_KINDS[kind]
			or state.phase ~= "Running"
			or not state.matchId
			or buffer.age(now) >= 0.5
		then
			return false
		end
		state.commandSeq += 1
		local payload: { [string]: any } =
			{ kind = kind, matchId = state.matchId, commandSeq = state.commandSeq }
		for _, name in protocol.FIELDS[kind] do
			if payload[name] == nil then
				payload[name] = if fields and fields[name] ~= nil then fields[name] else 0
			end
		end
		sendCommand(payload, now, false)
		return true
	end
	-- Robux store (D-PAY-01): the server opens the prompt; the grant arrives as a profile update.
	local function purchase(item: number, now: number): boolean
		if destroyed or state.phase == "ProfileLoading" or state.phase == "Unavailable" then
			return false
		end
		sendCommand({ kind = "Purchase", item = item }, now, false)
		return true
	end
	-- battle speed game pass: 1 or 2
	local function setSpeed(speed: number, now: number): boolean
		if destroyed or state.phase ~= "Running" or not state.matchId then
			return false
		end
		sendCommand({ kind = "SetSpeed", matchId = state.matchId, speed = speed }, now, false)
		return true
	end
	local function receiveMessage(message: any, now: number): boolean
		if destroyed or type(message) ~= "table" then
			return false
		end
		if message.requestId == "store-grant" then
			applyProfile(message.profileRevision, message.profileSummary) -- a Robux receipt (D-PAY-01)
			return true
		end
		local command = pending[message.requestId]
		if
			not command
			or (command.matchId and command.matchId ~= state.matchId)
			or (command.matchId and message.matchId and message.matchId ~= command.matchId)
			or (
				command.kind == "StartStage"
				and command.epoch < epoch
				and message.matchId ~= state.matchId
			)
		then
			return false
		end
		if message.status == "Rejected" then
			setReason(message.reason, now)
		end
		applyProfile(message.profileRevision, message.profileSummary)
		if state.profileRequest == message.requestId and message.status ~= "Pending" then
			state.profileRequest = nil
		end
		if command.kind == "StartStage" then
			if message.status == "Committed" and type(message.matchId) == "string" then
				switchMatch(message.matchId, now)
				state.phase = "Running"
			elseif message.status == "Rejected" and state.phase == "Preparing" then
				state.phase = "LobbyReady"
			end
		elseif command.kind == "ReturnToLobby" and message.status == "Accepted" then
			switchMatch(nil, now)
			state.phase = "LobbyReady"
		end
		if message.status ~= "Pending" then
			pending[message.requestId] = nil
		end
		return true
	end
	local function move(axis: number, now: number, side: number?): boolean
		local strafe = side or 0
		if
			destroyed
			or (axis ~= -1 and axis ~= 0 and axis ~= 1)
			or (strafe ~= -1 and strafe ~= 0 and strafe ~= 1)
			or not state.matchId
			or state.phase ~= "Running"
		then
			return false
		end
		if (axis ~= 0 or strafe ~= 0) and buffer.age(now) >= 0.5 then
			return false
		end
		state.axis, state.strafe, state.moveSeq = axis, strafe, state.moveSeq + 1
		table.insert(history, { seq = state.moveSeq, axis = axis, strafe = strafe, time = now })
		if #history > 32 then
			table.remove(history, 1)
		end
		deps.send("MoveIntent", {
			protocolVersion = protocol.VERSION,
			matchId = state.matchId,
			seq = state.moveSeq,
			axis = axis,
			strafe = if strafe ~= 0 then strafe else nil,
		})
		return true
	end
	local function currentSlot(): any
		local summary = state.summary
		if not summary or summary.currentSlot == 0 then
			return nil
		end
		local slot = summary.slots[summary.currentSlot]
		return if type(slot) == "table" then slot else nil
	end
	local function model(now: number): any
		local latest = buffer.latest()
		return {
			phase = state.phase,
			storage = state.storage,
			profileRevision = state.profileRevision,
			summary = state.summary,
			slot = currentSlot(),
			busy = state.profileRequest ~= nil,
			reason = if now - state.reasonAt < 3 then state.reason else nil,
			matchId = state.matchId,
			stage = latest and latest.stage,
			battle = latest and latest.battle,
			speed = latest and latest.speed or 1,
			result = latest and latest.result,
			rewards = latest and latest.rewards,
			settlementStatus = latest and latest.settlementStatus,
			network = if inflight and now - inflight.time >= 3
				then "응답 지연"
				elseif
					state.matchId
					and state.phase == "Running"
					and buffer.age(now) >= 0.5
				then "연결 불안"
				elseif inflight then "동기화 중"
				elseif state.phase == "ProfileLoading" then "연결 대기"
				else "연결됨",
		}
	end
	-- Interpolated field with the hero led by unacknowledged input (bounded; snaps back on correction).
	local function frame(now: number): any
		local view = buffer.frame(now)
		if not view then
			return nil
		end
		local latest = buffer.latest()
		if latest and latest.phase == "Running" and not view.paused and buffer.age(now) < 0.5 then
			local lead, sideLead = 0, 0
			local cursor = math.max(lastSnapshot, now - PREDICTION_LEAD)
			local axis: number = state.axis
			local strafe: number = state.strafe
			local function accumulate(seconds: number)
				local n = math.max(1, math.sqrt(axis * axis + strafe * strafe))
				lead += axis / n * seconds
				sideLead += strafe / n * seconds
			end
			for index = #history, 1, -1 do
				if history[index].time <= cursor then
					axis, strafe = history[index].axis, history[index].strafe or 0
					break
				end
			end
			for _, input in history do
				if input.time > cursor then
					accumulate(input.time - cursor)
					cursor, axis, strafe = input.time, input.axis, input.strafe or 0
				end
			end
			accumulate(now - cursor)
			for _, e in view.entities do
				if e.kind == "Hero" then
					e.x = math.clamp(e.x + lead * view.heroSpeed, view.heroMinX, view.heroMaxX)
					if view.spatial then
						e.z = math.clamp(
							(e.z or 0) + sideLead * view.heroSpeed,
							view.heroMinZ,
							view.heroMaxZ
						)
					end
				end
			end
		end
		return view
	end
	return table.freeze({
		beginBootstrap = beginBootstrap,
		finishBootstrap = finishBootstrap,
		receiveSnapshot = receiveSnapshot,
		receiveMessage = receiveMessage,
		move = move,
		lobby = lobby,
		purchase = purchase,
		setSpeed = setSpeed,
		start = start,
		battle = battle,
		returnToLobby = returnToLobby,
		model = model,
		frame = frame,
		step = function(now: number)
			if buffer.age(now) >= 0.5 then
				state.axis, state.strafe = 0, 0
			end
		end,
		needsBootstrap = function(now: number): boolean
			return not destroyed
				and not inflight
				and now >= nextBootstrap
				and (
					state.phase == "ProfileLoading"
					-- Server-side Unavailable can recover (e.g. lease wait on rejoin); a mismatch cannot.
					or (state.phase == "Unavailable" and state.reason ~= "ProtocolMismatch")
					or (state.profileRequest ~= nil and now - state.profileBusyAt >= 3)
					or (state.phase == "Preparing" and now - preparingAt >= 1)
					or (state.matchId ~= nil and now - matchStarted >= 1 and buffer.age(now) >= 1)
				)
		end,
		inspect = function(_now: number): any
			return {
				phase = state.phase,
				matchId = state.matchId,
				commandSeq = state.commandSeq,
				moveSeq = state.moveSeq,
				inflight = inflight ~= nil,
				history = #history,
				pending = #order,
				axis = state.axis,
				strafe = state.strafe,
			}
		end,
		destroy = function()
			destroyed = true
			table.clear(history)
			table.clear(pending)
		end,
	})
end

return table.freeze({ new = new })
