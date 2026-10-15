--!strict
-- Pulse action is independent of hero movement. Check every rejection before atomically reserving
-- mana, cooldown and one projectile slot. Cancelling a paid action never refunds mana/cooldown.
local SimTypes = require("./SimTypes")
local Targeting = require("./Targeting")
local ProjectileSystem = require("./ProjectileSystem")
local Config = require("../Config/Generated/Hero")

type World = SimTypes.World

local function clear(world: World)
	local action = world.heroAction
	action.skillId = nil
	action.releaseTick = nil
	action.endTick = nil
	action.reservedProjectileSlot = false
end

local function cast(world: World, slot: number): string?
	local hero = world.entities[world.heroId]
	local action = world.heroAction
	local resources = world.resources
	local skill = Config.skills.pulse
	if slot ~= 1 then
		return "InvalidPayload"
	elseif not Targeting.alive(hero) then
		return "WrongPhase"
	elseif action.endTick and world.tick < action.endTick then
		return "Busy"
	elseif world.tick < resources.skillReadyTick then
		return "Cooldown"
	elseif resources.manaMilli < skill.manaCostMilli then
		return "InsufficientMana"
	elseif ProjectileSystem.count(world) >= world.limits.projectileCap then
		return "ProjectileCap"
	end
	resources.manaMilli -= skill.manaCostMilli
	resources.skillReadyTick = world.tick + skill.cooldownTicks
	action.skillId = skill.id
	action.releaseTick = world.tick + skill.windupTicks
	action.endTick = (action.releaseTick :: number) + skill.recoveryTicks
	action.reservedProjectileSlot = true
	return nil
end

local function progress(world: World)
	local hero = world.entities[world.heroId]
	if not Targeting.alive(hero) then
		clear(world)
		return
	end
	local action = world.heroAction
	if not action.skillId then
		return
	end
	if action.reservedProjectileSlot and world.tick >= (action.releaseTick :: number) then
		-- Release our reservation immediately before launch: automatic attacks cannot steal it,
		-- and the normal cap check now sees exactly the reserved slot available.
		action.reservedProjectileSlot = false
		local skill = (Config.skills :: any)[action.skillId]
		hero.attackSerial += 1
		assert(
			ProjectileSystem.launch(world, {
				ownerId = hero.entityId,
				projectileId = skill.projectileId,
				damage = skill.damage,
				releaseTick = world.tick,
				x = hero.x,
				direction = 1, -- pulse always travels +X, not the last movement facing
				attackSerial = hero.attackSerial,
			}),
			"reserved pulse slot must be available"
		)
	end
	if world.tick >= (action.endTick :: number) then
		clear(world)
	end
end

-- Called after damage/outcome as well as before release, so a death/terminal tick cannot leak slots.
local function cleanup(world: World)
	if world.outcome or not Targeting.alive(world.entities[world.heroId]) then
		clear(world)
	end
end

return table.freeze({ cast = cast, progress = progress, cleanup = cleanup })
