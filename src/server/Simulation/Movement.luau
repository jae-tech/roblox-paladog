--!strict
-- 1D movement, advance limit and the left-edge breach rule (DATA_MODELS §3.5).
local SimTypes = require("./SimTypes")
local Resource = require("./Resource")
local Targeting = require("./Targeting")

type World = SimTypes.World
type Entity = SimTypes.Entity

local DT = 1 / Resource.TICKS_PER_SECOND

local function moveHero(world: World, axis: number)
	local hero = world.entities[world.heroId]
	if not Targeting.alive(hero) or axis == 0 then
		return
	end
	hero.x = math.clamp(hero.x + axis * hero.moveSpeed * DT, 0, world.stage.advanceLimitX)
	hero.facing = axis
end

local function moveEnemy(world: World, enemy: Entity)
	local step = enemy.moveSpeed * DT
	if enemy.breachReturn then
		local hero = world.entities[world.heroId]
		if not Targeting.alive(hero) then
			return
		end
		local gap = hero.x - enemy.x
		if gap ~= 0 then
			enemy.facing = if gap > 0 then 1 else -1 -- re-faces the hero if it walked past
		end
		enemy.x = if math.abs(gap) <= step then hero.x else enemy.x + enemy.facing * step -- stops at the hero
		return
	end
	enemy.x -= step
	if enemy.x <= 0 then
		-- One-time relocation just left of the hero; afterwards it only chases and targets the hero.
		local hero = world.entities[world.heroId]
		enemy.x = math.max(0, (if hero then hero.x else 0) - 1)
		enemy.breachReturn = true
		enemy.facing = 1
	end
end

local function moveUnits(world: World)
	for _, id in world.order do
		local entity = world.entities[id]
		if
			entity
			and entity.state == "Advancing"
			and Targeting.alive(entity)
			and not Targeting.acquire(world, entity)
		then
			if entity.kind == "Ally" then
				entity.x = math.min(entity.x + entity.moveSpeed * DT, world.stage.advanceLimitX)
			elseif entity.kind == "Enemy" then
				moveEnemy(world, entity)
			end
		end
	end
end

-- Support field: allies (not the hero or core) within supportRadius of a living hero.
local function updateSupport(world: World)
	local hero = world.entities[world.heroId]
	local heroAlive = Targeting.alive(hero)
	for _, id in world.order do
		local entity = world.entities[id]
		if entity and entity.kind == "Ally" then
			entity.inSupport = heroAlive
				and math.abs(entity.x - (hero :: Entity).x)
					<= world.supportRadius + Targeting.EPSILON
		end
	end
end

return table.freeze({
	DT = DT,
	moveHero = moveHero,
	moveUnits = moveUnits,
	updateSupport = updateSupport,
})
