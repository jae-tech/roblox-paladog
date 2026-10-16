--!strict
-- Full-state owner snapshots (remake protocol v2) and presentation-only interpolation of battle positions.
-- No simulation or engine dependency; everything is validated before it is kept.
local MAX_ENTITIES, MAX_OBJECTS = 320, 256
local TICKS_PER_SECOND = 30

local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function integer(n: any): boolean
	return finite(n) and n >= 0 and n % 1 == 0
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result: { [any]: any } = {}
	for k, v in value do
		result[k] = if type(v) == "table" then copy(v) else v
	end
	return result
end

local function validBattle(battle: any): boolean
	if
		type(battle) ~= "table"
		or not integer(battle.tick)
		or type(battle.entities) ~= "table"
		or #battle.entities > MAX_ENTITIES
		or type(battle.objects) ~= "table"
		or #battle.objects > MAX_OBJECTS
	then
		return false
	end
	for _, key in { "food", "mana", "maxFood", "maxMana", "heroSpeed", "heroMinX", "heroMaxX" } do
		if not finite(battle[key]) then
			return false
		end
	end
	if battle.spatial and (not finite(battle.heroMinZ) or not finite(battle.heroMaxZ)) then
		return false
	end
	for _, list in { battle.entities, battle.objects } do
		local seen: { [number]: boolean } = {}
		for _, e in list do
			if
				type(e) ~= "table"
				or not integer(e.id)
				or not finite(e.x)
				or seen[e.id]
				or (e.z ~= nil and not finite(e.z))
			then
				return false
			end
			seen[e.id] = true
		end
	end
	for _, e in battle.entities do
		if not finite(e.hp) or not finite(e.maxHp) or e.maxHp <= 0 then
			return false
		end
	end
	return true
end

local function valid(snapshot: any, hash: string): boolean
	return type(snapshot) == "table"
		and snapshot.balanceHash == hash
		and type(snapshot.matchId) == "string"
		and integer(snapshot.snapshotSeq)
		and integer(snapshot.inputAckSeq)
		and (snapshot.profileRevision == nil or integer(snapshot.profileRevision))
		and (snapshot.battle == nil or validBattle(snapshot.battle))
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
		if latest and snapshot.snapshotSeq <= latest.snapshotSeq then
			return false
		end
		previous, latest, receivedAt = latest, copy(snapshot), now
		return true
	end
	local function age(now: number): number
		return math.max(0, now - receivedAt)
	end
	-- Positions between the last two snapshots, rendered ~0.1 s behind the newest tick.
	local function frame(now: number): any
		local battle = latest and latest.battle
		if not battle then
			return nil
		end
		local before = previous and previous.battle
		local result = copy(battle)
		if before and before.tick < battle.tick and latest.phase == "Running" then
			local renderTick = battle.tick + (math.min(age(now), 0.25) - 0.1) * TICKS_PER_SECOND
			local alpha =
				math.clamp((renderTick - before.tick) / (battle.tick - before.tick), 0, 1.5)
			for _, key in { "entities", "objects" } do
				local old: { [number]: any } = {}
				for _, e in before[key] do
					old[e.id] = e
				end
				for _, e in result[key] do
					local prior = old[e.id]
					if prior then
						e.x = prior.x + (e.x - prior.x) * alpha
						if e.z ~= nil and prior.z ~= nil then
							e.z = prior.z + (e.z - prior.z) * alpha
						end
					end
				end
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

return table.freeze({ new = new, finite = finite, TICKS_PER_SECOND = TICKS_PER_SECOND })
