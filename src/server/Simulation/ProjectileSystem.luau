--!strict
-- Server-only 1D swept collision. No target tracking, physics, visual markers or owner-liveness
-- dependency after launch. All impacts join the same tick damage batch as melee.
local SimTypes = require("./SimTypes")
local Targeting = require("./Targeting")
local Resource = require("./Resource")
local Config = require("../Config/Generated/Hero")

type World = SimTypes.World
type Projectile = SimTypes.Projectile

local function count(world: World): number
	return world.projectileCount + (if world.heroAction.reservedProjectileSlot then 1 else 0)
end

local function launch(world: World, request: SimTypes.ProjectileRequest): boolean
	local owner = world.entities[request.ownerId]
	local def = (Config.projectiles :: any)[request.projectileId]
	if
		not owner
		or not Targeting.alive(owner)
		or not def
		or count(world) >= world.limits.projectileCap
	then
		return false
	end
	local id = world.nextEntityId
	world.nextEntityId += 1
	world.projectiles[id] = {
		entityId = id,
		definitionId = request.projectileId,
		ownerEntityId = owner.entityId,
		team = owner.team,
		laneId = owner.laneId,
		x = request.x,
		previousX = request.x,
		direction = request.direction,
		damage = request.damage,
		attackSerial = request.attackSerial or 0,
		spawnTick = world.tick,
		expireTick = world.tick + def.ttlTicks,
		distanceRemaining = def.maxDistance,
		remainingPierce = def.pierce,
		hitEntityIds = {},
	}
	table.insert(world.projectileOrder, id)
	world.projectileCount += 1
	return true
end

local function sweep(world: World, projectile: Projectile, distance: number, hits: { SimTypes.Hit })
	local def = (Config.projectiles :: any)[projectile.definitionId]
	local contacts: { { id: number, distance: number } } = {}
	for _, id in world.order do
		local target = world.entities[id]
		if
			target
			and Targeting.alive(target)
			and target.team ~= projectile.team
			and target.laneId == projectile.laneId
			and not projectile.hitEntityIds[id]
		then
			local center = (target.x - projectile.previousX) * projectile.direction
			local radius = target.hitRadius + def.radius
			local entry = math.max(0, center - radius)
			if center + radius >= -Targeting.EPSILON and entry <= distance + Targeting.EPSILON then
				table.insert(contacts, { id = id, distance = entry })
			end
		end
	end
	-- Exact ordering is transitive even for near-equal floating distances. Exact ties use entityId.
	table.sort(
		contacts,
		function(a: { id: number, distance: number }, b: { id: number, distance: number })
			return if a.distance == b.distance then a.id < b.id else a.distance < b.distance
		end
	)
	for _, contact in contacts do
		projectile.hitEntityIds[contact.id] = true
		projectile.remainingPierce -= 1
		table.insert(hits, {
			attackerId = projectile.ownerEntityId,
			targetId = contact.id,
			damage = projectile.damage,
			releaseTick = projectile.spawnTick,
			attackSerial = projectile.attackSerial,
		})
		if projectile.remainingPierce == 0 then
			break
		end
	end
end

local function advance(world: World): { SimTypes.Hit }
	local hits: { SimTypes.Hit } = {}
	local kept: { number } = {}
	for _, id in world.projectileOrder do
		local projectile = world.projectiles[id]
		local def = (Config.projectiles :: any)[projectile.definitionId]
		local alive = projectile.remainingPierce > 0
			and projectile.distanceRemaining > 0
			and projectile.x >= 0
			and projectile.x <= world.stage.length
			and world.tick <= projectile.expireTick
		if alive and world.tick > projectile.spawnTick then
			projectile.previousX = projectile.x
			local toEdge = if projectile.direction == 1
				then world.stage.length - projectile.x
				else projectile.x
			local distance = math.min(
				def.speed / Resource.TICKS_PER_SECOND,
				projectile.distanceRemaining,
				toEdge
			)
			projectile.x += projectile.direction * distance
			projectile.distanceRemaining = math.max(0, projectile.distanceRemaining - distance)
			sweep(world, projectile, distance, hits)
			-- The final TTL/distance/map segment still collides; nothing can hit beyond the endpoint.
			alive = projectile.remainingPierce > 0
				and projectile.distanceRemaining > 0
				and distance < toEdge
				and world.tick < projectile.expireTick
		end
		if alive then
			table.insert(kept, id)
		else
			world.projectiles[id] = nil
			world.projectileCount -= 1
		end
	end
	world.projectileOrder = kept
	return hits
end

return table.freeze({ count = count, launch = launch, advance = advance })
