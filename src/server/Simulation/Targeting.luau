--!strict
-- Target choice (ARCHITECTURE §5): same lane, hostile, alive, in front, |dx| <= range + target radius;
-- nearest wins, ties go to the smaller entityId. breachReturn enemies may only target the hero.
local SimTypes = require("./SimTypes")

type World = SimTypes.World
type Entity = SimTypes.Entity

local EPSILON = 1e-6 -- positions are floats; integer HP/ticks are compared exactly elsewhere

local function alive(entity: Entity?): boolean
	return entity ~= nil and entity.state ~= "Dead" and entity.hp > 0
end

local function inRange(attacker: Entity, target: Entity): boolean
	return math.abs(target.x - attacker.x) <= attacker.attackRange + target.hitRadius + EPSILON
end

local function inFront(attacker: Entity, target: Entity): boolean
	return (target.x - attacker.x) * attacker.facing >= -EPSILON
end

local function canHit(world: World, attacker: Entity, target: Entity?): boolean
	if
		not target
		or not alive(target)
		or target.team == attacker.team
		or target.laneId ~= attacker.laneId
	then
		return false
	end
	if attacker.breachReturn and target.entityId ~= world.heroId then
		return false
	end
	return inFront(attacker, target) and inRange(attacker, target)
end

local function acquire(world: World, attacker: Entity): Entity?
	local best: Entity? = nil
	local bestDistance = math.huge
	for _, id in world.order do
		local candidate = world.entities[id]
		if candidate and canHit(world, attacker, candidate) then
			local distance = math.abs(candidate.x - attacker.x)
			if
				distance < bestDistance - EPSILON
				or (math.abs(distance - bestDistance) <= EPSILON and best and id < best.entityId)
			then
				best, bestDistance = candidate, distance
			end
		end
	end
	return best
end

return table.freeze({
	EPSILON = EPSILON,
	alive = alive,
	canHit = canHit,
	acquire = acquire,
	inRange = inRange,
})
