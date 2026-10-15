--!strict
-- Intent building, snapshot authority, bounded local hero prediction and one in-flight bootstrap.
local SnapshotBuffer = require("./SnapshotBuffer")

export type Deps = {
	protocol: any,
	catalog: any,
	send: (string, any) -> (),
	requestId: () -> string,
}

local function new(deps: Deps)
	local buffer = SnapshotBuffer.new(deps.catalog.balanceHash)
	local state: any = {
		phase = "ProfileLoading",
		storage = "연결 대기",
		profileRevision = 0,
		stageProgress = {},
		matchId = nil,
		commandSeq = 0,
		moveSeq = 0,
		axis = 0,
		reason = nil,
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
	local correction, correctionAt = 0, 0
	local renderedHero: number? = nil
	local function switchMatch(id: string?, now: number)
		if state.matchId ~= id then
			epoch += 1
			state.matchId = id
			state.moveSeq, state.commandSeq, state.axis = 0, 0, 0
			table.clear(history)
			buffer.setMatch(id)
			lastSnapshot, matchStarted = -math.huge, now
			correction, renderedHero = 0, nil
		end
	end
	local function predicted(now: number): number
		local snapshot = buffer.latest()
		if not snapshot then
			return 10
		end
		local hero: any = nil
		for _, e in snapshot.entities do
			if e.kind == "Hero" then
				hero = e
				break
			end
		end
		if not hero then
			return 10
		end
		if snapshot.phase ~= "Running" or buffer.age(now) >= 0.5 then
			return hero.x
		end
		local start = lastSnapshot
		if #history > 0 then
			start = math.min(start, history[1].time)
		end
		start = math.max(start, now - 0.15)
		local axis = if #history > 0 then history[1].axis else state.axis
		local delta, cursor = 0, start
		for _, input in history do
			local at = math.clamp(input.time, start, now)
			delta += axis * (at - cursor)
			cursor, axis = at, input.axis
		end
		delta += axis * (now - cursor)
		return math.clamp(
			hero.x + delta * (snapshot.heroMoveSpeed or 6),
			0,
			snapshot.advanceLimitX or 86.4
		)
	end
	local function receiveSnapshot(payload: any, now: number): boolean
		if destroyed or not buffer.accept(payload, now) then
			return false
		end
		lastSnapshot = now
		state.phase = payload.phase
		state.moveSeq = math.max(state.moveSeq, payload.inputAckSeq)
		state.commandSeq = math.max(state.commandSeq, payload.commandAckSeq or 0)
		local keep = {}
		for _, input in history do
			if input.seq > payload.inputAckSeq then
				table.insert(keep, input)
			end
		end
		history = keep
		local target = predicted(now)
		local error = if renderedHero then (renderedHero :: number) - target else 0
		correction = if payload.phase == "Running" and math.abs(error) <= 0.1 then error else 0
		correctionAt = now
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
			state.reason = "StorageUnavailable"
			return false
		end
		if
			payload.protocolVersion ~= deps.protocol.VERSION
			or payload.balanceHash ~= deps.catalog.balanceHash
		then
			state.phase, state.reason = "Unavailable", "ProtocolMismatch"
			return false
		end
		state.storage = payload.storage or "Unknown"
		if payload.status ~= "Ready" then
			state.reason = payload.status
			return false
		end
		state.reason = nil
		if (payload.profileRevision or 0) >= state.profileRevision then
			state.profileRevision = payload.profileRevision or state.profileRevision
			state.stageProgress = if payload.profileSummary
				then payload.profileSummary.stageProgress
				else {}
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
	local function sendCommand(payload: any)
		local id = deps.requestId()
		payload.protocolVersion, payload.requestId = deps.protocol.VERSION, id
		pending[id] = { kind = payload.kind, matchId = payload.matchId, epoch = epoch }
		table.insert(order, id)
		if #order > 128 then
			local expired = table.remove(order, 1)
			if expired then
				pending[expired] = nil
			end
		end
		deps.send("ClientCommand", payload)
	end
	local function action(name: string, now: number): boolean
		if destroyed then
			return false
		end
		if name == "ReturnToLobby" then
			if state.phase ~= "Settled" or not state.matchId then
				return false
			end
			sendCommand({ kind = "ReturnToLobby", matchId = state.matchId })
			return true
		end
		if string.sub(name, 1, 6) == "Start_" then
			local stage = string.sub(name, 7)
			if state.phase ~= "LobbyReady" or not deps.catalog.stages[stage] then
				return false
			end
			sendCommand({
				kind = "StartStage",
				stageId = stage,
				expectedRevision = state.profileRevision,
			})
			state.phase = "Preparing"
			preparingAt = now
			return true
		end
		if state.phase ~= "Running" or not state.matchId or buffer.age(now) >= 0.5 then
			return false
		end
		local slot = ({ Summon1 = 1, Summon2 = 2, Summon3 = 3 })[name]
		if not slot and name ~= "Cast" then
			return false
		end
		state.commandSeq += 1
		sendCommand({
			kind = if slot then "Summon" else "Cast",
			slot = slot or 1,
			matchId = state.matchId,
			commandSeq = state.commandSeq,
		})
		return true
	end
	local function receiveMessage(message: any, now: number): boolean
		if destroyed or type(message) ~= "table" then
			return false
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
		state.reason = message.reason
		if message.profileRevision and message.profileRevision >= state.profileRevision then
			state.profileRevision = message.profileRevision
			if message.profileSummary then
				state.stageProgress = message.profileSummary.stageProgress
			end
		end
		if command.kind == "StartStage" then
			if message.status == "Committed" and type(message.matchId) == "string" then
				switchMatch(message.matchId, now)
				local snapshot = buffer.latest()
				state.phase = if snapshot then snapshot.phase else "Running"
			elseif message.status == "Rejected" and state.phase == "Preparing" then
				state.phase = "LobbyReady"
			end
		end
		if command.kind == "ReturnToLobby" and message.status == "Accepted" then
			switchMatch(nil, now)
			state.phase = "LobbyReady"
		end
		if message.status ~= "Pending" then
			pending[message.requestId] = nil
		end
		return true
	end
	local function move(axis: number, now: number): boolean
		if
			destroyed
			or (axis ~= -1 and axis ~= 0 and axis ~= 1)
			or not state.matchId
			or state.phase ~= "Running"
		then
			return false
		end
		if axis ~= 0 and buffer.age(now) >= 0.5 then
			return false
		end
		state.axis, state.moveSeq = axis, state.moveSeq + 1
		table.insert(history, { seq = state.moveSeq, axis = axis, time = now })
		if #history > 32 then
			table.remove(history, 1)
		end
		deps.send("MoveIntent", {
			protocolVersion = deps.protocol.VERSION,
			matchId = state.matchId,
			seq = state.moveSeq,
			axis = axis,
		})
		return true
	end
	local function model(now: number): any
		local snapshot = buffer.latest()
		local m: any = {
			phase = state.phase,
			storage = state.storage,
			profileRevision = state.profileRevision,
			stageProgress = state.stageProgress,
			catalog = deps.catalog,
			reason = state.reason,
			matchId = state.matchId,
			network = if inflight and now - inflight.time >= 3
				then "응답 지연"
				elseif state.matchId and buffer.age(now) >= 0.5 then "연결 불안"
				elseif inflight then "동기화 중"
				elseif state.phase == "ProfileLoading" then "연결 대기"
				else "연결됨",
		}
		if snapshot then
			m.tick, m.heroAction, m.outcome = snapshot.tick, snapshot.heroAction, snapshot.outcome
			m.result, m.settlementStatus = snapshot.result, snapshot.settlementStatus
			for k, v in snapshot.resources or {} do
				m[k] = v
			end
			m.pendingKillGold, m.pendingKillXp =
				snapshot.pendingKillGold or 0, snapshot.pendingKillXp or 0
			for _, e in snapshot.entities do
				if e.kind == "Hero" then
					m.heroHp, m.heroMaxHp = e.hp, e.maxHp
				elseif e.kind == "Objective" then
					m.coreHp, m.coreMaxHp = e.hp, e.maxHp
				end
			end
		end
		return m
	end
	local function frame(now: number): any
		local f = buffer.frame(now)
		local x = predicted(now) + correction * math.clamp(1 - (now - correctionAt) / 0.1, 0, 1)
		f.heroX = math.clamp(x, 0, f.advanceLimitX)
		for _, e in f.entities do
			if e.kind == "Hero" then
				e.x = f.heroX
			end
		end
		renderedHero = f.heroX
		return f
	end
	return table.freeze({
		beginBootstrap = beginBootstrap,
		finishBootstrap = finishBootstrap,
		receiveSnapshot = receiveSnapshot,
		receiveMessage = receiveMessage,
		move = move,
		action = action,
		model = model,
		frame = frame,
		step = function(now: number)
			if buffer.age(now) >= 0.5 then
				state.axis = 0
			end
		end,
		needsBootstrap = function(now: number): boolean
			return not destroyed
				and not inflight
				and now >= nextBootstrap
				and (
					state.phase == "ProfileLoading"
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
