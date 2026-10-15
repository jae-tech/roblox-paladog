--!strict
-- Full-state owner snapshots and presentation-only interpolation. No simulation or engine dependency.
local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function integer(n: any): boolean
	return finite(n) and n >= 0 and n % 1 == 0
end

local function copy(snapshot: any): any
	if type(snapshot) ~= "table" then
		return snapshot
	end
	local result: { [any]: any } = {}
	for k, v in snapshot do
		result[k] = if type(v) == "table" then copy(v) else v
	end
	return result
end

local function valid(snapshot: any, hash: string): boolean
	if
		type(snapshot) ~= "table"
		or snapshot.balanceHash ~= hash
		or type(snapshot.matchId) ~= "string"
		or not integer(snapshot.snapshotSeq)
		or not integer(snapshot.tick)
		or not integer(snapshot.inputAckSeq)
		or type(snapshot.entities) ~= "table"
		or #snapshot.entities > 72
		or type(snapshot.projectiles) ~= "table"
		or #snapshot.projectiles > 128
	then
		return false
	end
	for _, list in { snapshot.entities, snapshot.projectiles } do
		local seen: { [number]: boolean } = {}
		for _, e in list do
			if
				type(e) ~= "table"
				or not integer(e.entityId)
				or not finite(e.x)
				or seen[e.entityId]
			then
				return false
			end
			seen[e.entityId] = true
		end
	end
	if type(snapshot.resources) ~= "table" then
		return false
	end
	for _, key in { "foodMilli", "manaMilli" } do
		if not integer(snapshot.resources[key]) then
			return false
		end
	end
	for _, key in { "stageLength", "advanceLimitX", "heroMoveSpeed", "commandAckSeq" } do
		if snapshot[key] ~= nil and (not finite(snapshot[key]) or snapshot[key] < 0) then
			return false
		end
	end
	for _, key in { "foodMaxMilli", "manaMaxMilli", "skillReadyTick" } do
		if snapshot.resources[key] ~= nil and not integer(snapshot.resources[key]) then
			return false
		end
	end
	for _, e in snapshot.entities do
		if not integer(e.hp) or not integer(e.maxHp) or e.maxHp < 1 or e.hp > e.maxHp then
			return false
		end
	end
	for _, p in snapshot.projectiles do
		if not finite(p.previousX) or (p.direction ~= 1 and p.direction ~= -1) then
			return false
		end
	end
	return true
end

local function new(balanceHash: string)
	local matchId: string? = nil
	local previous: any = nil
	local latest: any = nil
	local receivedAt = -math.huge
	local function setMatch(id: string?)
		if id ~= matchId then
			matchId, latest, previous, receivedAt = id, nil, nil, -math.huge
		end
	end
	local function accept(snapshot: any, now: number): boolean
		if not finite(now) or not valid(snapshot, balanceHash) or snapshot.matchId ~= matchId then
			return false
		end
		if
			latest and (snapshot.snapshotSeq <= latest.snapshotSeq or snapshot.tick < latest.tick)
		then
			return false
		end
		previous, latest, receivedAt = latest, copy(snapshot), now
		return true
	end
	local function age(now: number): number
		return math.max(0, now - receivedAt)
	end
	local function frame(now: number): any
		if not latest then
			return {
				entities = {},
				projectiles = {},
				heroX = 10,
				stageLength = 102.4,
				advanceLimitX = 86.4,
			}
		end
		local renderTick = latest.tick + (math.min(age(now), 0.25) - 0.1) * 20
		local result = {
			entities = {},
			projectiles = {},
			heroX = 10,
			stageLength = latest.stageLength or 102.4,
			advanceLimitX = latest.advanceLimitX or 86.4,
		}
		for _, key in { "entities", "projectiles" } do
			local old: { [number]: any } = {}
			if previous then
				for _, e in previous[key] do
					old[e.entityId] = e
				end
			end
			for _, e in latest[key] do
				local visual = copy(e)
				local before = old[e.entityId]
				if before and previous.tick < latest.tick then
					local alpha = math.clamp(
						(renderTick - previous.tick) / (latest.tick - previous.tick),
						0,
						1 + 3 / (latest.tick - previous.tick)
					)
					visual.x = before.x + (e.x - before.x) * alpha
				end
				-- Terminal authoritative positions snap immediately, never drift during settlement.
				if latest.phase ~= "Running" then
					visual.x = e.x
				end
				if key == "entities" then
					visual.x = math.clamp(visual.x, 0, result.stageLength)
					if e.kind == "Hero" then
						result.heroX = e.x
					end
				end
				table.insert((result :: any)[key], visual)
			end
		end
		return result
	end
	return table.freeze({
		setMatch = setMatch,
		accept = accept,
		age = age,
		frame = frame,
		latest = function(): any
			return copy(latest)
		end,
	})
end

return table.freeze({ new = new, finite = finite })
