--!strict
-- Advancing -> Windup -> Recovery -> Cooldown -> Advancing/new Windup (ARCHITECTURE §5).
-- Total cycle = windup + recovery + cooldown. At release the target is re-validated; a miss still
-- consumes the cycle (deliberate difference from the original, E02 §2.9).
local SimTypes = require("./SimTypes")
local Targeting = require("./Targeting")

type World = SimTypes.World
type Entity = SimTypes.Entity

local function damageOf(entity: Entity, numerator: number): number
	return (entity.attackPower * numerator + 50) // 100 -- floor(AP*num/100 + 0.5) in integers
end

local function enterWindup(world: World, entity: Entity, target: Entity)
	local attack = entity.attack :: SimTypes.AttackDef
	entity.state = "Windup"
	entity.stateUntilTick = world.tick + attack.windupTicks
	entity.targetId = target.entityId
end

-- Called in the targeting phase for idle attackers that found nobody to walk past.
local function acquireTargets(world: World)
	for _, id in world.order do
		local entity = world.entities[id]
		if entity and entity.attack and entity.state == "Advancing" and Targeting.alive(entity) then
			local target = Targeting.acquire(world, entity)
			if target then
				enterWindup(world, entity, target)
			end
		end
	end
end

local function release(world: World, entity: Entity, hits: { SimTypes.Hit })
	local attack = entity.attack :: SimTypes.AttackDef
	local target = if entity.targetId then world.entities[entity.targetId] else nil
	entity.attackSerial += 1
	if target and Targeting.canHit(world, entity, target) then
		-- Support multiplier is snapshotted at release (melee) / launch (ranged).
		local numerator = if entity.inSupport then world.supportDamageNumerator else 100
		local damage = damageOf(entity, numerator)
		if attack.kind == "Projectile" then
			table.insert(world.projectileRequests, {
				ownerId = entity.entityId,
				targetId = target.entityId,
				projectileId = attack.projectileId :: string,
				damage = damage,
				releaseTick = world.tick,
				x = entity.x,
				direction = entity.facing,
			})
		else
			table.insert(hits, {
				attackerId = entity.entityId,
				targetId = target.entityId,
				damage = damage,
				releaseTick = world.tick,
				attackSerial = entity.attackSerial,
			})
		end
	end
	entity.state = "Recovery"
	entity.stateUntilTick = world.tick + attack.recoveryTicks
	entity.targetId = nil
end

-- Advances timers for every living attacker; returns this tick's melee hit batch.
local function progress(world: World): { SimTypes.Hit }
	local hits: { SimTypes.Hit } = {}
	for _, id in world.order do
		local entity = world.entities[id]
		if
			entity
			and entity.attack
			and Targeting.alive(entity)
			and world.tick >= entity.stateUntilTick
		then
			local attack = entity.attack
			if entity.state == "Windup" then
				release(world, entity, hits)
			elseif entity.state == "Recovery" then
				entity.state = "Cooldown"
				entity.stateUntilTick = world.tick + attack.cooldownTicks
			elseif entity.state == "Cooldown" then
				entity.state = "Advancing"
				local target = Targeting.acquire(world, entity)
				if target then
					enterWindup(world, entity, target) -- back-to-back cycles keep the exact period
				end
			end
		end
	end
	return hits
end

return table.freeze({ damageOf = damageOf, acquireTargets = acquireTargets, progress = progress })
