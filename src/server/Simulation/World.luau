--!strict
-- One authoritative match simulation. `step` processes exactly one 0.05s tick in the fixed order of
-- ARCHITECTURE §5. Pure Luau: no Instances, Heartbeat, animation or clocks.
local SimTypes = require("./SimTypes")
local Resource = require("./Resource")
local Movement = require("./Movement")
local Targeting = require("./Targeting")
local Attack = require("./Attack")
local Damage = require("./Damage")
local ProjectileSystem = require("./ProjectileSystem")
local HeroActionSystem = require("./HeroActionSystem")
local Units = require("../Config/Generated/Units")
local Enemies = require("../Config/Generated/Enemies")
local HeroConfig = require("../Config/Generated/Hero")
local Stages = require("../Config/Generated/Stages")
local Generated = require("../Config/Generated/Progression")

type World = SimTypes.World
type Entity = SimTypes.Entity

local PHASES = table.freeze({
	"regen",
	"commands",
	"spawn",
	"move",
	"support",
	"target",
	"attack",
	"damage",
	"outcome",
	"cleanup",
})
local SLOT_UNITS = table.freeze({ "vanguard", "slinger", "bulwark" })
local LANE = 1

local function addEntity(world: World, entity: Entity): Entity
	world.entities[entity.entityId] = entity
	table.insert(world.order, entity.entityId) -- ids only increase, so order stays sorted
	return entity
end

local function base(
	world: World,
	definitionId: string,
	kind: SimTypes.EntityKind,
	team: SimTypes.Team
): Entity
	local id = world.nextEntityId
	world.nextEntityId += 1
	return {
		entityId = id,
		definitionId = definitionId,
		kind = kind,
		team = team,
		laneId = LANE,
		x = 0,
		facing = if team == "Ally" then 1 else -1,
		hp = 1,
		maxHp = 1,
		attackPower = 0,
		moveSpeed = 0,
		attackRange = 0,
		hitRadius = 0,
		state = "Idle",
		stateUntilTick = 0,
		targetId = nil,
		inSupport = false,
		attackSerial = 0,
		breachReturn = false,
		attack = nil,
		killGold = 0,
		killXp = 0,
	}
end

local function spawnAlly(world: World, unitId: string, x: number?): Entity
	local def = (Units :: any)[unitId]
	local level = def.levels[world.unitLevels[unitId] or 1]
	local entity = base(world, unitId, "Ally", "Ally")
	entity.x = x or world.stage.allySpawnX
	entity.hp, entity.maxHp, entity.attackPower = level.maxHp, level.maxHp, level.attackPower
	entity.moveSpeed, entity.attackRange, entity.hitRadius =
		def.moveSpeed, def.attackRange, def.hitRadius
	entity.state, entity.attack = "Advancing", def.attack
	return addEntity(world, entity)
end

local function aliveCount(world: World, kind: SimTypes.EntityKind): number
	local count = 0
	for _, id in world.order do
		local entity = world.entities[id]
		if entity and entity.kind == kind and Targeting.alive(entity) then
			count += 1
		end
	end
	return count
end

-- Returns nil when the enemy cap is reached (stage spawner freezes its timer, P6).
local function spawnEnemy(world: World, enemyId: string, x: number?): Entity?
	if aliveCount(world, "Enemy") >= world.limits.enemyCap then
		return nil
	end
	local def = (Enemies :: any)[enemyId]
	local entity = base(world, enemyId, "Enemy", "Enemy")
	entity.x = x or world.stage.enemySpawnX
	entity.hp, entity.maxHp, entity.attackPower =
		def.stats.maxHp, def.stats.maxHp, def.stats.attackPower
	entity.moveSpeed, entity.attackRange, entity.hitRadius =
		def.stats.moveSpeed, def.stats.attackRange, def.stats.hitRadius
	entity.state, entity.attack = "Advancing", def.attack
	entity.killGold, entity.killXp = def.killGold, def.killXp
	return addEntity(world, entity)
end

export type Options = {
	stageId: string,
	unitLevels: { [string]: number }?,
	heroTraits: { [string]: number }?,
	trace: boolean?,
}

local function new(options: Options): World
	local stage = (Stages :: any)[options.stageId]
	assert(stage, "unknown stage " .. tostring(options.stageId))
	local traits: { [string]: number } = table.clone(options.heroTraits or {})
	local progression = Generated.progression
	local hero = HeroConfig.hero
	local world: World = {
		tick = 0,
		stageId = options.stageId,
		stage = stage,
		entities = {},
		order = {},
		nextEntityId = 1,
		heroId = 0,
		coreId = 0,
		resources = Resource.new(HeroConfig.resources, traits, progression.traits),
		supportRadius = hero.supportRadius,
		supportDamageNumerator = hero.supportDamageNumerator,
		unitLevels = table.clone(options.unitLevels or { vanguard = 1, slinger = 1, bulwark = 1 }), -- fixed per match
		limits = {
			allyCap = Generated.limits.allyCap,
			enemyCap = Generated.limits.enemyCap,
			projectileCap = Generated.limits.projectileCap,
		},
		outcome = nil,
		outcomeTick = nil,
		pendingKillGold = 0,
		pendingKillXp = 0,
		killCounts = {},
		projectileRequests = {},
		projectiles = {},
		projectileOrder = {},
		projectileCount = 0,
		heroAction = { reservedProjectileSlot = false },
		trace = if options.trace then {} else nil,
	}
	local heroEntity = base(world, hero.id, "Hero", "Ally")
	heroEntity.x = stage.heroStartX
	heroEntity.maxHp = hero.baseMaxHp
		+ (traits.vitality or 0) * progression.traits.vitality.heroMaxHpPerPoint
	heroEntity.hp = heroEntity.maxHp
	heroEntity.moveSpeed, heroEntity.hitRadius = hero.moveSpeed, hero.hitRadius
	world.heroId = addEntity(world, heroEntity).entityId
	local core = base(world, "enemy_core", "Objective", "Enemy")
	core.x, core.hp, core.maxHp, core.hitRadius =
		stage.coreX, stage.coreMaxHp, stage.coreMaxHp, stage.coreHitRadius
	world.coreId = addEntity(world, core).entityId
	return world
end

-- Cost, cooldown and capacity are checked first and only then reserved together (no partial charge).
local function summon(world: World, slot: number): string?
	local unitId = SLOT_UNITS[slot]
	local def = unitId and (Units :: any)[unitId]
	if not def then
		return "InvalidPayload"
	end
	local resources = world.resources
	if world.tick < resources.summonReadyTick[slot] then
		return "Cooldown"
	elseif resources.foodMilli < def.foodCostMilli then
		return "InsufficientFood"
	elseif aliveCount(world, "Ally") >= world.limits.allyCap then
		return "UnitCap"
	end
	resources.foodMilli -= def.foodCostMilli
	resources.summonReadyTick[slot] = world.tick + def.summonCooldownTicks
	spawnAlly(world, unitId)
	return nil
end

local function runCommands(world: World, commands: { any }): { SimTypes.CommandResult }
	local results: { SimTypes.CommandResult } = {}
	for _, command in commands do
		local reason: string? = "InvalidPayload"
		if command.kind == "Summon" then
			reason = summon(world, command.slot)
		elseif command.kind == "Cast" then
			reason = HeroActionSystem.cast(world, command.slot)
		end
		table.insert(results, {
			requestId = command.requestId,
			commandSeq = command.commandSeq,
			status = if reason then "Rejected" else "Accepted",
			reason = reason,
		})
	end
	return results
end

local function decideOutcome(world: World)
	local hero, core = world.entities[world.heroId], world.entities[world.coreId]
	-- Same-tick hero and core destruction is a defeat (PRD §3.2.6); time-out is checked last.
	if not Targeting.alive(hero) then
		world.outcome = "Defeat"
	elseif not Targeting.alive(core) then
		world.outcome = "Victory"
	elseif world.tick >= world.stage.timeLimitTicks then
		world.outcome = "Timeout"
	end
	if world.outcome then
		world.outcomeTick = world.tick
	end
end

local function cleanup(world: World)
	local kept: { number } = {}
	for _, id in world.order do
		local entity = world.entities[id]
		if entity and (entity.state ~= "Dead" or id == world.heroId or id == world.coreId) then
			table.insert(kept, id)
		else
			world.entities[id] = nil -- server dead records are dropped immediately; visuals keep their own TTL
		end
	end
	world.order = kept
end

export type Input = { commands: { any }?, axis: number? }
export type StepResult = {
	results: { SimTypes.CommandResult },
	deaths: { SimTypes.Death },
	hits: number,
	outcome: string?,
}

local function mark(world: World, phase: string)
	if world.trace then
		table.insert(world.trace, phase)
	end
end

local function step(world: World, input: Input?): StepResult
	local commands: { any } = if input and input.commands then input.commands else {}
	if world.outcome then
		local rejected: { SimTypes.CommandResult } = {}
		for _, command in commands do
			table.insert(rejected, {
				requestId = command.requestId,
				commandSeq = command.commandSeq,
				status = "Rejected",
				reason = "WrongPhase",
			})
		end
		return { results = rejected, deaths = {}, hits = 0, outcome = world.outcome }
	end
	world.tick += 1
	table.clear(world.projectileRequests)
	mark(world, "regen")
	Resource.regen(world.resources)
	mark(world, "commands")
	local results = runCommands(world, commands)
	mark(world, "spawn") -- stage spawner joins here in P6
	mark(world, "move")
	Movement.moveHero(world, if input and input.axis then input.axis else 0)
	Movement.moveUnits(world)
	mark(world, "support")
	Movement.updateSupport(world)
	mark(world, "target")
	Attack.acquireTargets(world)
	mark(world, "attack")
	local hits = Attack.progress(world)
	for _, request in world.projectileRequests do
		ProjectileSystem.launch(world, request) -- full cap makes automatic ranged releases miss
	end
	HeroActionSystem.progress(world)
	for _, hit in ProjectileSystem.advance(world) do
		table.insert(hits, hit)
	end
	mark(world, "damage")
	local deaths = Damage.apply(world, hits)
	mark(world, "outcome")
	decideOutcome(world)
	mark(world, "cleanup")
	HeroActionSystem.cleanup(world)
	cleanup(world)
	return { results = results, deaths = deaths, hits = #hits, outcome = world.outcome }
end

local function snapshotProjectiles(world: World): { { [string]: any } }
	local list: { { [string]: any } } = {}
	for _, id in world.projectileOrder do
		local p = world.projectiles[id]
		local view: { [string]: any } = {
			entityId = p.entityId,
			definitionId = p.definitionId,
			team = p.team,
			laneId = p.laneId,
			x = p.x,
			previousX = p.previousX,
			direction = p.direction,
			spawnTick = p.spawnTick,
			expireTick = p.expireTick,
		}
		table.insert(list, view)
	end
	return list
end

local function snapshotHeroAction(world: World): { [string]: any }
	return {
		skillId = world.heroAction.skillId,
		releaseTick = world.heroAction.releaseTick,
		endTick = world.heroAction.endTick,
	}
end

-- Owner-facing view: positions/HP/state only; attack power and internals stay on the server.
local function snapshotEntities(world: World): { { [string]: any } }
	local list: { { [string]: any } } = {}
	for _, id in world.order do
		local e = world.entities[id]
		if e then
			local view: { [string]: any } = {
				entityId = e.entityId,
				definitionId = e.definitionId,
				kind = e.kind,
				team = e.team,
				x = e.x,
				facing = e.facing,
				hp = e.hp,
				maxHp = e.maxHp,
				state = e.state,
				stateUntilTick = e.stateUntilTick,
				inSupport = e.inSupport,
			}
			table.insert(list, view)
		end
	end
	return list
end

-- FNV-1a over a canonical dump of the full simulation state; equal inputs must give equal digests.
local function digest(world: World): string
	local resources = world.resources
	local kills: { string } = {}
	for id, count in world.killCounts do
		table.insert(kills, id .. "=" .. count)
	end
	table.sort(kills)
	local parts = {
		string.format(
			"t%d|n%d|o%s|f%d,%d,%d|m%d,%d,%d|r%d,%d,%d|g%d,%d|k%s",
			world.tick,
			world.nextEntityId,
			tostring(world.outcome),
			resources.foodMilli,
			resources.foodRemainder,
			resources.foodRateMilli,
			resources.manaMilli,
			resources.manaRemainder,
			resources.manaRateMilli,
			resources.summonReadyTick[1],
			resources.summonReadyTick[2],
			resources.summonReadyTick[3],
			world.pendingKillGold,
			world.pendingKillXp,
			table.concat(kills, ",")
		),
	}
	local action = world.heroAction
	table.insert(
		parts,
		string.format(
			"h%s,%s,%s,%s|s%d|pc%d",
			tostring(action.skillId),
			tostring(action.releaseTick),
			tostring(action.endTick),
			tostring(action.reservedProjectileSlot),
			resources.skillReadyTick,
			world.projectileCount
		)
	)
	for _, id in world.order do
		local e = world.entities[id] :: Entity
		table.insert(
			parts,
			string.format(
				"%d:%s:%.17g:%d:%d/%d:%d:%s:%d:%s:%d:%s:%s",
				id,
				e.definitionId,
				e.x,
				e.facing,
				e.hp,
				e.maxHp,
				e.attackPower,
				e.state,
				e.stateUntilTick,
				tostring(e.targetId),
				e.attackSerial,
				tostring(e.inSupport),
				tostring(e.breachReturn)
			)
		)
	end
	for _, id in world.projectileOrder do
		local p = world.projectiles[id]
		local hitIds: { number } = {}
		for hitId in p.hitEntityIds do
			table.insert(hitIds, hitId)
		end
		table.sort(hitIds)
		local hitStrings: { string } = {}
		for _, hitId in hitIds do
			table.insert(hitStrings, tostring(hitId))
		end
		table.insert(
			parts,
			string.format(
				"b%d:%s:%d:%s:%d:%.17g:%.17g:%d:%d:%d:%d:%d:%.17g:%d:%s",
				id,
				p.definitionId,
				p.ownerEntityId,
				p.team,
				p.laneId,
				p.x,
				p.previousX,
				p.direction,
				p.damage,
				p.attackSerial,
				p.spawnTick,
				p.expireTick,
				p.distanceRemaining,
				p.remainingPierce,
				table.concat(hitStrings, ",")
			)
		)
	end
	for _, request in world.projectileRequests do
		table.insert(
			parts,
			string.format(
				"p%d>%s:%d@%d",
				request.ownerId,
				tostring(request.targetId),
				request.damage,
				request.releaseTick
			)
		)
	end
	local text = table.concat(parts, "|")
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 403 + bit32.lshift(hash, 24)) % 4294967296 -- * FNV prime (2^24+403), exact in doubles
	end
	return string.format("%08x", hash)
end

return table.freeze({
	PHASES = PHASES,
	SLOT_UNITS = SLOT_UNITS,
	new = new,
	step = step,
	spawnAlly = spawnAlly,
	spawnEnemy = spawnEnemy,
	aliveCount = aliveCount,
	snapshotEntities = snapshotEntities,
	snapshotProjectiles = snapshotProjectiles,
	snapshotHeroAction = snapshotHeroAction,
	digest = digest,
})
