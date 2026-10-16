--!strict
-- Authoritative remake battle (docs/REMAKE_PLAN.md R1). Original px/second units on a fixed 30 Hz tick
-- (one tick = one 1/30 s animation frame). Pure Luau: no Instances, clocks or engine RNG.
-- Rule sources: E02 (combat/units), E03 (hero/maces/aura), E04 (resources/spawn/stages).
local Db = require("../Config/Remake/Db")
local Rng = require("./Rng")
local Rules = require("./Rules")

local DT = 1 / 30
local SCROLL_MAX = 1024
local CASTLE_X = SCROLL_MAX - 120
local ALLY_LIMIT_CASTLE = SCROLL_MAX - 160
local ALLY_LIMIT_BOSS = SCROLL_MAX - 40
local KNOCK_SPEED = 180
local KNOCK_FRAMES = 16
local KNOCK_WAIT = 3
local SLIDE_PX = 5
local PROJECTILE_HALF_WIDTH = 10 -- D-PROJ-01: sprite half width is not in the research data
local MACE_FRAMES, MACE_EFFECT_FRAME = 18, 8 -- D-ANIM-02: hero part animations were not parsed
local FIFTEEN_MINUTES = 900
-- Server protection only; the original has no unit cap (E02 §5). D-CAP-01.
local ALLY_CAP, ENEMY_CAP, OBJECT_CAP = 80, 120, 256
-- E02 §2.9 documented attack animation frame counts {attack1, skill}; others use D-ANIM-01.
local UNIT_ANIM: { [number]: { number } } =
	{ [1] = { 10, 16 }, [2] = { 20, 20 }, [5] = { 20, 20 }, [8] = { 20, 20 } }
local ENEMY_ANIM: { [number]: number } = { [1] = 10, [17] = 75 }
local OBJECTS: { [string]: any } = Db.objects :: any
local SKILL_MULTIPLIED = { [1] = true, [2] = true, [3] = true, [5] = true, [7] = true, [9] = true }

export type Entity = {
	id: number,
	kind: string, -- "Hero" | "Unit" | "Enemy" | "Boss" | "Castle"
	n: number,
	team: number, -- 1 ally, 2 enemy
	x: number,
	line: number,
	y: number,
	dir: number,
	hp: number,
	maxHp: number,
	ap: number,
	speed: number,
	attackDist: number,
	hitDist: number,
	attackDelay: number,
	skillPercent: number,
	skillDamage: number,
	knockPercent: number,
	skillDist: number,
	atkFrame: number,
	skillFrame: number,
	atkAnim: number,
	skillAnim: number,
	state: string,
	stateTicks: number,
	stateLimit: number,
	attackPast: number,
	target: number?,
	aura: boolean,
	auraTicks: number,
	statMul: number,
	scale: number,
	giant: boolean,
	enhanced: boolean,
	rewardGold: number,
	rewardExp: number,
	knockMul: number,
	ghostUsed: boolean,
	ghostX: number,
	poisonDps: number,
	poisonLeft: number,
	poisonTicks: number,
	oneGold: boolean,
	struck: boolean,
	removed: boolean,
}

export type Object = {
	id: number,
	kind: string, -- "Straight" | "Lob" | "Drop"
	row: number,
	team: number,
	owner: number,
	x: number,
	line: number,
	dir: number,
	speed: number,
	ap: number,
	pierce: number,
	maxPierce: number,
	hit: { [number]: boolean },
	aura: boolean,
	freeze: number,
	poison: number,
	area: number,
	areaMul: number,
	single: boolean,
	fromX: number,
	toX: number,
	ticks: number,
	duration: number,
	oneGold: boolean,
	born: number,
}

export type Options = {
	stage: number,
	seed: number,
	loadout: Rules.Loadout,
	cleared: boolean?, -- stage already has a star: kill rewards x0.5 (E04 §2-2)
	goldAvailable: number?, -- profile gold, for the gold weapon (E03 §3.1)
}

local function stageRow(stage: number): any
	return Db.campaign[stage]
end

local function newEntity(b: any, kind: string, n: number, team: number): Entity
	local id = b.nextId
	b.nextId += 1
	return {
		id = id,
		kind = kind,
		n = n,
		team = team,
		x = 0,
		line = -1,
		y = 0,
		dir = if team == 1 then 1 else -1,
		hp = 1,
		maxHp = 1,
		ap = 0,
		speed = 0,
		attackDist = 0,
		hitDist = 0,
		attackDelay = 0,
		skillPercent = 0,
		skillDamage = 0,
		knockPercent = 0,
		skillDist = 0,
		atkFrame = 0,
		skillFrame = 0,
		atkAnim = 10,
		skillAnim = 10,
		state = "Move",
		stateTicks = 0,
		stateLimit = 0,
		attackPast = 1e9, -- accumulates from creation, so the first attack is immediate (E02 §2.9)
		target = nil,
		aura = false,
		auraTicks = 0,
		statMul = 1,
		scale = 1,
		giant = false,
		enhanced = false,
		rewardGold = 0,
		rewardExp = 0,
		knockMul = 1,
		ghostUsed = false,
		ghostX = 0,
		poisonDps = 0,
		poisonLeft = 0,
		poisonTicks = 0,
		oneGold = false,
		struck = false,
		removed = false,
	}
end

local function add(b: any, e: Entity): Entity
	b.entities[e.id] = e
	table.insert(b.order, e.id)
	return e
end

local function alive(e: Entity?): boolean
	return e ~= nil and not e.removed and e.state ~= "Dead" and e.hp > 0
end

local function count(b: any, team: number, unitsOnly: boolean): number
	local total = 0
	for _, id in b.order do
		local e = b.entities[id]
		if
			alive(e)
			and e.team == team
			and (not unitsOnly or e.kind == "Unit" or e.kind == "Enemy")
		then
			total += 1
		end
	end
	return total
end

-- E04 §6 / E02 §2.8: depth band by iCLine (render only, drawn from the battle RNG like the original).
local function depthY(b: any, line: number): number
	local low, span = 145, 40
	if line == 1 then
		low, span = 165, 20
	elseif line == 2 then
		low, span = 155, 20
	elseif line == 3 then
		low, span = 145, 20
	end
	return low + Rng.rand(b.rng) % span
end

local function frames(hitFrame: number, known: number?): number
	return known or math.max(hitFrame + 4, 10) -- D-ANIM-01
end

local function spawnUnit(b: any, n: number): Entity
	local row = Db.units[n]
	local level = math.clamp(b.loadout.unitLevels[n] or 1, 1, 20)
	local e = newEntity(b, "Unit", n, 1)
	e.hp, e.maxHp, e.ap = row.levels.hp[level], row.levels.hp[level], row.levels.ap[level] -- level table replaces base (E02 §1.4)
	e.speed, e.attackDist, e.hitDist, e.attackDelay =
		row.moveSpeed, row.attackDist, row.hitDist, row.attackDelay
	e.skillPercent, e.skillDamage, e.knockPercent, e.skillDist =
		row.skillPercent, row.skillDamage, row.knockPercent, row.skillDist
	e.atkFrame, e.skillFrame = row.attackFrame, row.skillFrame
	local known = UNIT_ANIM[n]
	e.atkAnim = frames(row.attackFrame, known and known[1])
	e.skillAnim = frames(row.skillFrame, known and known[2])
	if n == 4 then
		e.skillAnim = 14 -- kangaroo fires 5 fists over frames 4..12 (E02 §4.3)
	end
	e.x, e.y = 0, depthY(b, row.createLine)
	return add(b, e)
end

-- Enemy id rules (E04 §3-3): 1..20 base, 21..40 enhanced x1.3, 101..110 bosses.
local function spawnEnemy(
	b: any,
	enemyId: number,
	slot: number,
	x: number?,
	forceGiant: boolean?
): Entity?
	if enemyId <= 0 or count(b, 2, true) >= ENEMY_CAP then
		return nil
	end
	local boss = enemyId > 100
	local base = if boss then enemyId - 100 elseif enemyId > 20 then enemyId - 20 else enemyId
	local row = if boss then Db.bosses[base] else Db.enemies[base]
	local e = newEntity(b, if boss then "Boss" else "Enemy", base, 2)
	local statMul, scale = 1, 1
	if forceGiant or (slot == 3 and Rng.rand(b.rng) % 1000 <= 100) then
		scale, statMul = Db.multipliers.bigScale, Db.multipliers.bigStat
		e.giant = true
	end
	if not boss and enemyId > 20 then
		statMul *= Db.multipliers.enhancedStat
		e.enhanced = true
	end
	e.statMul, e.scale = statMul, scale
	e.hp = row.hp * statMul * b.difficulty.hp
	e.maxHp = e.hp
	e.ap = row.attackPower * statMul
	e.speed = row.moveSpeed * scale
	e.attackDist, e.hitDist, e.attackDelay = row.attackDist, row.hitDist, row.attackDelay
	e.skillPercent, e.skillDamage, e.knockPercent, e.skillDist =
		row.skillPercent, row.skillDamage, row.knockPercent, row.skillDist
	e.atkFrame = row.attackFrame
	e.atkAnim = frames(row.attackFrame, if boss then nil else ENEMY_ANIM[base])
	e.skillAnim = e.atkAnim
	e.rewardGold, e.rewardExp = row.rewardGold, row.rewardExp
	e.x, e.y = x or SCROLL_MAX, depthY(b, 0)
	return add(b, e)
end

local function newRewards(): any
	return {
		gold = 0,
		exp = 0,
		goldSpent = 0,
		kills = {},
		killTotal = 0,
		drops = {},
		levelUps = 0,
		picks = {},
	}
end

local function new(options: Options): any
	local stage = stageRow(options.stage)
	assert(stage, "unknown stage " .. tostring(options.stage))
	local loadout = options.loadout
	local stats = Rules.heroStats(loadout)
	local b: any = {
		tick = 0,
		stageNumber = options.stage,
		stage = stage,
		loadout = loadout,
		stats = stats,
		difficulty = Rules.DIFFICULTY[loadout.difficulty] or Rules.DIFFICULTY[1],
		clearedMul = if options.cleared then 0.5 else 1,
		rng = Rng.new(options.seed),
		seed = options.seed,
		entities = {},
		order = {},
		objects = {},
		objectOrder = {},
		nextId = 1,
		food = 0,
		mana = 0,
		hpRegenTicks = 0,
		summonPast = { 100, 100, 100, 100, 100, 100, 100, 100, 100 }, -- all ready at start (E04 §1-1)
		auraCount = 0,
		level = loadout.level,
		exp = 0,
		expBase = 0,
		pendingPicks = {},
		rewards = newRewards(),
		spawn = { created = 0, total = 0, fifth = 0, timer = 0, need = 0 },
		rush = { started = false, left = 0, timer = 0 },
		outcome = nil,
		heroId = 0,
		castleId = 0,
		axis = 0,
		offer = nil,
		activeMace = nil,
		goldAvailable = options.goldAvailable or 0,
	}
	b.expBase = loadout.exp or 0
	local hero = newEntity(b, "Hero", 0, 1)
	hero.x, hero.hp, hero.maxHp = 100, stats.maxHp, stats.maxHp
	hero.hitDist, hero.speed, hero.state = Db.specials.lightHero.hitDist, stats.moveSpeed, "Idle"
	hero.y = 165
	b.heroId = add(b, hero).id
	local castle = newEntity(b, "Castle", 11, 2)
	castle.x, castle.hitDist, castle.state = CASTLE_X, Db.specials.castle.hitDist, "Idle"
	castle.hp = stage.castleHp * b.difficulty.hp
	castle.maxHp = castle.hp
	b.castleId = add(b, castle).id
	b.spawn.need = -1
	return b
end

-- E04 §3-1: next spawn gap in [min, max+0.9] seconds at 0.1 s resolution.
local function nextSpawnGap(b: any): number
	local s = b.stage
	local lo, hi = s.s21, s.s22
	if b.spawn.created < s.unitCount then
		lo, hi = s.s11, s.s12
	end
	local range = hi - lo + 1
	return ((Rng.rand(b.rng) % 10000) % (range * 10)) / 10 + lo
end

local function hero(b: any): Entity
	return b.entities[b.heroId]
end

local function castle(b: any): Entity
	return b.entities[b.castleId]
end

-- ------------------------------------------------------------------ damage (E02 §2.1-§2.2)

local function needSlide(e: Entity): boolean
	if e.kind ~= "Unit" and e.kind ~= "Enemy" then
		return false -- hero, bosses, castle never slide
	end
	if e.kind == "Unit" and e.n == 6 then
		return false
	end
	if e.kind == "Enemy" and (e.n == 12 or e.n == 20 or e.n == 17) then
		return false
	end
	return e.state ~= "Knock" and e.state ~= "KnockWait"
end

local function knockdown(e: Entity, mul: number?)
	if e.kind ~= "Unit" and e.kind ~= "Enemy" then
		return -- hero, boss and castle are immune (E02 §4.4)
	end
	e.state, e.stateTicks, e.knockMul, e.target = "Knock", 0, mul or 1, nil
end

local kill: (b: any, target: Entity, killer: Entity?) -> ()

local function gainExp(b: any, amount: number)
	b.exp += amount
	while b.level < Rules.MAX_LEVEL and b.expBase + b.exp >= Rules.expForLevel(b.level) do
		b.level += 1
		b.rewards.levelUps += 1
		table.insert(b.pendingPicks, b.level)
	end
end

local function reward(b: any, e: Entity)
	local playTime = b.tick * DT
	local gold, exp
	if playTime >= FIFTEEN_MINUTES then
		gold, exp = 1, 0 -- over 15 minutes outside survival (E04 §2-2)
	else
		gold = e.rewardGold * e.statMul * b.difficulty.gold * b.clearedMul
		gold += b.stats.goldBonus * gold
		exp = e.rewardExp * e.statMul * b.difficulty.exp * b.clearedMul
		exp += b.stats.expBonus * exp
		if e.oneGold then
			gold = 1
		end
	end
	b.rewards.gold += math.floor(gold)
	gainExp(b, math.floor(exp))
	local allow = if e.kind == "Boss" then 100 else b.stats.dropPercent
	if Rng.rand(b.rng) % 1000 < allow * 10 then
		table.insert(b.rewards.drops, { tick = b.tick, boss = e.kind == "Boss", n = e.n })
	end
end

kill = function(b: any, target: Entity, killer: Entity?)
	if target.state == "Dead" then
		return
	end
	target.hp = math.min(target.hp, 0)
	target.state, target.stateTicks, target.target = "Dead", 0, nil
	if target.team == 2 and (target.kind == "Enemy" or target.kind == "Boss") then
		local key = (if target.kind == "Boss" then "b" else "e") .. target.n
		b.rewards.kills[key] = (b.rewards.kills[key] or 0) + 1
		b.rewards.killTotal += 1
		reward(b, target)
	elseif target.kind == "Unit" then
		local stats = b.stats
		b.mana = math.min(b.mana + stats.onAllyDeathMana, stats.maxMana)
		b.food = math.min(b.food + stats.onAllyDeathFood, stats.maxFood)
		local h = hero(b)
		if alive(h) then
			h.hp = math.min(h.hp + stats.onAllyDeathHeroHp, h.maxHp)
		end
	end
	local _ = killer
end

-- One hit. `skill` applies the per-unit skill multiplier; `ap` overrides attacker power for projectiles.
local function strike(
	b: any,
	attacker: Entity?,
	target: Entity,
	ap: number,
	skill: boolean,
	auraHit: boolean,
	oneGold: boolean?
)
	if not alive(target) then
		return
	end
	if target.kind == "Unit" and target.n == 4 and target.state == "Skill" then
		return -- a kangaroo mid-skill cannot be hit; the attacker loses it (E02 §4.3)
	end
	local stats = b.stats
	local dmg = ap
	if auraHit then
		dmg *= stats.auraWar
	end
	if attacker and attacker.kind == "Unit" and stats.armedHorse > 0 then
		dmg *= 1 + stats.armedHorse * b.auraCount
	end
	if target.aura then
		dmg *= stats.auraDefense
	end
	if target.kind == "Hero" then
		dmg *= stats.damageTakenMul
	end
	if target.kind == "Unit" and target.n == 6 and target.aura then
		dmg *= 0.5
	end
	if skill and attacker and attacker.kind == "Unit" and SKILL_MULTIPLIED[attacker.n] then
		dmg *= attacker.skillDamage
	end
	local before = target.hp
	target.hp -= dmg
	if oneGold then
		target.oneGold = true
	end
	if target.kind == "Hero" then
		b.mana = math.min(b.mana + stats.onHeroHitMana, stats.maxMana)
		b.food = math.min(b.food + stats.onHeroHitFood, stats.maxFood)
		if attacker and alive(attacker) and stats.reflect > 0 then
			attacker.hp -= dmg * stats.reflect
			if attacker.hp <= 0 then
				kill(b, attacker, target)
			end
		end
	end
	if target.hp <= 0 then
		kill(b, target, attacker)
		return
	end
	-- Allied units fall when HP crosses 20% of max (E02 §2.1); skills knock by fSkKnd percent.
	local crossed = target.kind == "Unit"
		and before > target.maxHp * 0.2
		and target.hp <= target.maxHp * 0.2
	if crossed or (skill and attacker and Rng.rand(b.rng) % 1000 < attacker.knockPercent * 10) then
		knockdown(target)
	end
	if needSlide(target) then
		target.x -= target.dir * SLIDE_PX
	end
end

-- ------------------------------------------------------------------ targeting (E02 §2.8)

local function targetable(e: Entity): boolean
	return alive(e) and e.state ~= "Ghost"
end

local function nearestFront(b: any, e: Entity, reach: number): Entity?
	local best, bestDist = nil, math.huge
	for _, id in b.order do
		local c = b.entities[id]
		if c and c.team ~= e.team and targetable(c) and c.line == e.line then
			local dx = (c.x - e.x) * e.dir
			if dx >= 0 and dx <= reach + c.hitDist and dx < bestDist then
				best, bestDist = c, dx
			end
		end
	end
	return best
end

local function area(b: any, e: Entity, x: number, reach: number, both: boolean, fn: (Entity) -> ())
	local hit: { Entity } = {}
	for _, id in b.order do
		local c = b.entities[id]
		if c and c.team ~= e.team and targetable(c) and c.line == e.line then
			local dx = (c.x - x) * e.dir
			if (both or dx >= 0) and math.abs(dx) <= reach + c.hitDist then
				table.insert(hit, c)
			end
		end
	end
	for _, c in hit do
		fn(c)
	end
end

-- ------------------------------------------------------------------ objects (E02 §3)

local function launch(b: any, spec: any): Object?
	if #b.objectOrder >= OBJECT_CAP then
		return nil
	end
	local id = b.nextId
	b.nextId += 1
	local row = OBJECTS["r" .. spec.row]
	local o: Object = {
		id = id,
		kind = spec.kind,
		row = spec.row,
		team = spec.team,
		owner = spec.owner,
		x = spec.x,
		line = spec.line,
		dir = spec.dir,
		speed = spec.speed or (if row then row.speed else 0),
		ap = spec.ap,
		pierce = spec.pierce or (if row then row.pierce else 1),
		maxPierce = spec.pierce or (if row then row.pierce else 1),
		hit = {},
		aura = spec.aura or false,
		freeze = spec.freeze or 0,
		poison = spec.poison or 0,
		area = spec.area or 0,
		areaMul = spec.areaMul or 1,
		single = spec.single or false,
		fromX = spec.x,
		toX = spec.toX or spec.x,
		ticks = 0,
		duration = spec.duration or 0,
		oneGold = spec.oneGold or false,
		born = b.tick,
	}
	b.objects[id] = o
	table.insert(b.objectOrder, id)
	return o
end

local function ownerOf(b: any, o: Object): Entity?
	return b.entities[o.owner]
end

local function projectileHit(b: any, o: Object, target: Entity)
	local owner = ownerOf(b, o)
	local auraHit = o.aura
	local ap = o.ap
	-- Berserker (skill 21) checks the projectile's own HP ratio, so it rarely triggers (E03 §5.2).
	if auraHit and o.pierce / o.maxPierce <= 0.3 then
		ap *= b.stats.berserker
	end
	strike(b, owner, target, ap, false, auraHit, o.oneGold)
	if o.freeze > 0 and alive(target) and (target.kind == "Unit" or target.kind == "Enemy") then
		target.state, target.stateTicks, target.stateLimit, target.target =
			"Ice", 0, math.floor(o.freeze * 30 + 0.5), nil
	end
	if o.poison > 0 and alive(target) then
		target.poisonDps, target.poisonLeft, target.poisonTicks = o.poison, 10, 0
	end
end

local function stepObjects(b: any)
	local kept: { number } = {}
	for _, id in b.objectOrder do
		local o: Object = b.objects[id]
		local done = false
		if o.born == b.tick then
			table.insert(kept, id) -- released this frame: starts moving next frame
			continue
		end
		o.ticks += 1
		if o.kind == "Straight" then
			o.x += o.dir * o.speed * DT
			local best: Entity?, bestDist = nil, math.huge
			for _, eid in b.order do
				local c: Entity? = b.entities[eid]
				if
					c
					and c.team ~= o.team
					and targetable(c)
					and c.line == o.line
					and not o.hit[c.id]
				then
					local d = math.abs(c.x - o.x)
					if d <= PROJECTILE_HALF_WIDTH + c.hitDist and d < bestDist then
						best, bestDist = c, d
					end
				end
			end
			if best then
				o.hit[best.id] = true
				o.pierce -= 1
				projectileHit(b, o, best)
				done = o.pierce <= 0
			end
			if o.x < -PROJECTILE_HALF_WIDTH * 2 or o.x > SCROLL_MAX + PROJECTILE_HALF_WIDTH * 2 then
				done = true
			end
		elseif o.kind == "Lob" or o.kind == "Drop" then
			if o.kind == "Lob" then
				o.x = o.fromX + (o.toX - o.fromX) * math.min(o.ticks / o.duration, 1)
			end
			if o.ticks >= o.duration then
				local owner = ownerOf(b, o)
				local probe: Entity = { team = o.team, line = o.line, dir = o.dir, x = o.x } :: any
				if o.single then
					local best, bestDist = nil, math.huge
					for _, eid in b.order do
						local c = b.entities[eid]
						if c and c.team ~= o.team and targetable(c) and c.line == o.line then
							local d = math.abs(c.x - o.x)
							if d <= o.area + c.hitDist and d < bestDist then
								best, bestDist = c, d
							end
						end
					end
					if best then
						strike(b, owner, best, o.ap * o.areaMul, false, o.aura)
					end
				else
					area(b, probe, o.x, o.area, true, function(c)
						strike(b, owner, c, o.ap * o.areaMul, false, o.aura)
					end)
				end
				done = true
			end
		end
		if done then
			b.objects[id] = nil
		else
			table.insert(kept, id)
		end
	end
	b.objectOrder = kept
end

-- ------------------------------------------------------------------ attacks (E02 §4.3-§4.4)

local function fire(b: any, e: Entity, row: number, ap: number, extra: any?)
	local obj = OBJECTS["r" .. row]
	local spec = {
		kind = "Straight",
		row = row,
		team = e.team,
		owner = e.id,
		x = e.x + e.dir * (if obj then obj.offsetX else 0),
		line = e.line,
		dir = e.dir,
		ap = ap,
		aura = e.aura,
	}
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	launch(b, spec)
end

local function lob(
	b: any,
	e: Entity,
	row: number,
	target: Entity,
	ap: number,
	reach: number,
	mul: number,
	single: boolean,
	extraDist: number
)
	launch(b, {
		kind = "Lob",
		row = row,
		team = e.team,
		owner = e.id,
		x = e.x,
		toX = e.x + (target.x - e.x) + e.dir * extraDist,
		line = e.line,
		dir = e.dir,
		ap = ap,
		aura = e.aura,
		area = reach,
		areaMul = mul,
		single = single,
		duration = 15, -- lands exactly 0.5 s after release (E02 §3.3)
	})
end

-- The release frame of an attack or skill animation.
local function release(b: any, e: Entity, skill: boolean)
	local target = if e.target then b.entities[e.target] else nil
	if e.kind == "Unit" then
		local n = e.n
		if n == 2 then
			fire(b, e, if skill then 261 else 260, e.ap)
		elseif n == 5 then
			if target then
				lob(
					b,
					e,
					if skill then 263 else 262,
					target,
					e.ap,
					if skill then 60 else 40,
					if skill then 1.2 else 1,
					false,
					30
				)
			end
		elseif n == 8 then
			fire(b, e, if skill then 265 else 264, e.ap, { freeze = if skill then 3 else 0 })
		elseif n == 9 then
			if skill then
				area(b, e, e.x, e.skillDist, true, function(c)
					strike(b, e, c, e.ap, true, e.aura)
				end)
			else
				area(b, e, e.x, e.attackDist + 30, true, function(c)
					strike(b, e, c, e.ap, false, e.aura)
				end)
			end
		elseif n == 3 and skill then
			area(b, e, e.x, e.skillDist, true, function(c)
				strike(b, e, c, e.ap, true, e.aura)
			end)
		elseif target and alive(target) and not (n == 4 and skill) then -- kangaroo fists fire per frame
			strike(b, e, target, e.ap, skill, e.aura)
		end
		return
	end
	-- enemies
	local n = e.n
	if e.kind == "Enemy" then
		if n == 2 then
			fire(b, e, 295, e.ap)
		elseif n == 6 then
			fire(b, e, 296, e.ap)
		elseif n == 18 then
			fire(b, e, 299, e.ap)
		elseif n == 10 and target then
			lob(b, e, 297, target, e.ap, Db.objects.r297.range, 1, true, 0)
		elseif n == 14 and target then
			launch(b, {
				kind = "Drop",
				row = 298,
				team = e.team,
				owner = e.id,
				x = target.x,
				line = e.line,
				dir = e.dir,
				ap = e.ap,
				area = Db.objects.r298.range,
				single = true,
				duration = Db.objects.r298.frame,
			})
		elseif n == 17 then
			-- bomber self-destructs over everyone near it (E02 §4.4), no kill reward
			area(b, e, e.x, e.attackDist + 30, true, function(c)
				strike(b, e, c, e.ap, false, false)
			end)
			e.removed, e.state = true, "Dead"
			b.rewards.killTotal += 1
		elseif target and alive(target) then
			strike(b, e, target, e.ap, false, false)
		end
	elseif target and alive(target) then
		strike(b, e, target, e.ap, skill, false)
	end
end

local function isWall(e: Entity): boolean
	return (e.kind == "Unit" and e.n == 6) or (e.kind == "Enemy" and (e.n == 12 or e.n == 20))
end

local function moveLimit(b: any, e: Entity): number
	if e.team == 1 then
		return if alive(castle(b)) then ALLY_LIMIT_CASTLE else ALLY_LIMIT_BOSS
	end
	return math.huge
end

local function enter(e: Entity, state: string, limit: number?)
	e.state, e.stateTicks, e.stateLimit = state, 0, limit or 0
end

local function stepEntity(b: any, e: Entity)
	if e.kind == "Hero" or e.kind == "Castle" or not alive(e) then
		return
	end
	e.stateTicks += 1
	e.attackPast += DT
	-- poison: 1 s ticks for 10 s, never below 1 HP (E02 §3.4)
	if e.poisonLeft > 0 then
		e.poisonTicks += 1
		if e.poisonTicks >= 30 then
			e.poisonTicks = 0
			e.poisonLeft -= 1
			e.hp = math.max(e.hp - e.poisonDps, math.min(e.hp, 1))
		end
	end
	local state = e.state
	if state == "Knock" then
		e.x -= e.dir * KNOCK_SPEED * e.knockMul * DT
		if e.stateTicks >= KNOCK_FRAMES then
			enter(e, "KnockWait", KNOCK_WAIT * 30)
		end
		return
	elseif state == "KnockWait" or state == "Ice" or state == "Wait" then
		if e.stateTicks >= e.stateLimit then
			enter(e, "Move")
		end
		return
	elseif state == "Ghost" then
		-- 0.5 s fade, untargetable advance of 150 px at walking speed (D-GHOST-01), 0.5 s return (E02 §4.4).
		-- stateLimit holds the phase: 0 fade-out, 1 advance, 2 fade-in.
		if e.stateLimit == 0 and e.stateTicks >= 15 then
			e.stateLimit, e.stateTicks = 1, 0
		elseif e.stateLimit == 1 then
			e.x += e.dir * e.speed * DT
			if math.abs(e.x - e.ghostX) >= 150 then
				e.stateLimit, e.stateTicks = 2, 0
			end
		elseif e.stateLimit == 2 and e.stateTicks >= 15 then
			enter(e, "Move")
		end
		return
	end
	local target = if e.target then b.entities[e.target] else nil
	if state == "Move" then
		local found = nearestFront(b, e, e.attackDist)
		if found then
			e.target = found.id
			if e.kind == "Enemy" and e.n == 9 and not e.ghostUsed then
				e.ghostUsed, e.ghostX, e.target = true, e.x, nil
				enter(e, "Ghost")
				return
			end
			if isWall(e) then
				enter(e, "Wait", 5 * 30)
				return
			end
			enter(e, "Delay")
			state = "Delay"
		else
			local speed = e.speed
			if e.kind == "Unit" and e.aura then
				speed *= b.stats.auraMove
			end
			e.x += e.dir * speed * DT
			if e.team == 1 then
				e.x = math.min(e.x, moveLimit(b, e))
			elseif e.x <= 0 then
				e.x = SCROLL_MAX -- enemies that cross the left edge loop back (E02 §2.7)
			end
			return
		end
	end
	target = if e.target then b.entities[e.target] else nil
	if state == "Delay" then
		if
			not target
			or not targetable(target)
			or math.abs(target.x - e.x) > e.attackDist + target.hitDist
		then
			e.target = nil
			enter(e, "Move")
			return
		end
		local delay = e.attackDelay
			* (if e.kind == "Unit" and e.aura then b.stats.auraEnergy else 1)
		if e.attackPast >= delay then
			local p = e.skillPercent
			if e.kind == "Unit" and e.aura then
				p *= b.stats.auraSkill
			end
			local roll = Rng.rand(b.rng) % 1000
			if e.kind == "Unit" and not e.aura then
				roll = p * 10 -- outside the aura allied units never use skills (E03 §5.2)
			end
			e.struck = false
			if roll < p * 10 then
				enter(e, "Skill", e.skillAnim)
			else
				enter(e, "Attack", e.atkAnim)
			end
		end
		return
	end
	if state == "Attack" or state == "Skill" then
		local skill = state == "Skill"
		local hitFrame = if skill then e.skillFrame else e.atkFrame
		if e.kind == "Unit" and e.n == 4 and skill then
			local t = e.stateTicks
			if t == 4 or t == 6 or t == 8 or t == 10 or t == 12 then
				fire(b, e, 266, e.ap * e.skillDamage)
			end
		elseif not e.struck and e.stateTicks >= hitFrame then
			e.struck = true
			release(b, e, skill)
			if not alive(e) then
				return
			end
		end
		if e.stateTicks >= e.stateLimit then
			e.attackPast = 0
			if target and targetable(target) then
				enter(e, "Delay")
			else
				e.target = nil
				enter(e, "Move")
			end
		end
	end
end

-- ------------------------------------------------------------------ hero and maces (E03 §1, §3.1)

local function nearestEnemyWithin(b: any, h: Entity, reach: number): Entity?
	local best, bestDist = nil, math.huge
	for _, id in b.order do
		local c = b.entities[id]
		if c and c.team == 2 and targetable(c) and c.kind ~= "Castle" then
			local d = c.x - h.x
			if d >= 0 and d <= reach and d < bestDist then
				best, bestDist = c, d
			end
		end
	end
	return best
end

local function maceEffect(b: any, mace: any)
	local h = hero(b)
	local num, g = mace.num, mace.grade
	local row = Db.maces[num]
	local main = row.a1 + row.b1 * g
	if num == 1 then
		fire(b, h, 268, main, { pierce = 3 + g // 20, aura = false })
	elseif num == 2 then
		for _, id in b.order do
			local c = b.entities[id]
			if
				c
				and c.team == 1
				and alive(c)
				and c.line == h.line
				and (c.kind == "Unit" or c.kind == "Hero")
			then
				if math.abs(c.x - h.x) <= 150 + c.hitDist then
					c.hp = math.min(c.hp + main, c.maxHp)
				end
			end
		end
	elseif num == 3 then
		local chance = (row.a2 * 10 + row.b2 * 10 * g) -- per mille: (10 + 0.5g)%
		for _, id in b.order do
			local c = b.entities[id]
			if c and c.team == 2 and targetable(c) and c.kind ~= "Castle" then
				local dx = c.x - h.x
				if dx >= 0 and dx <= 300 + c.hitDist then
					if c.kind ~= "Boss" and Rng.rand(b.rng) % 1000 < chance then
						strike(b, h, c, c.hp + 1, false, false)
					else
						strike(b, h, c, main, false, false)
					end
				end
			end
		end
	elseif num == 4 then
		fire(b, h, 269, main, { freeze = 3 + g // 5, aura = false })
	elseif num == 5 or num == 7 or num == 11 then
		local reach = if num == 5 then 250 else 300
		local found = nearestEnemyWithin(b, h, reach)
		local x
		if num == 5 then
			-- lightning: a random enemy within 250, else 250 ahead (E03 §3.1)
			local candidates: { Entity } = {}
			for _, id in b.order do
				local c = b.entities[id]
				if
					c
					and c.team == 2
					and targetable(c)
					and c.kind ~= "Castle"
					and c.x - h.x >= 0
					and c.x - h.x <= 250
				then
					table.insert(candidates, c)
				end
			end
			x = if #candidates > 0
				then candidates[Rng.rand(b.rng) % #candidates + 1].x
				else h.x + 250
		else
			x = if found then math.min(found.x + 40, h.x + 300) else h.x + 300
		end
		local radius = if num == 5 then 35 else 60
		area(b, h, x, radius, true, function(c)
			strike(b, h, c, main, false, false, num == 11)
		end)
	elseif num == 6 then
		for _, id in b.order do
			local c = b.entities[id]
			if
				c
				and c.team == 2
				and targetable(c)
				and c.line == h.line
				and c.x - h.x <= c.hitDist + 180
			then
				strike(b, h, c, main, false, false)
			end
		end
	elseif num == 8 then
		local maxCount = 3 + g // 20
		local hits = 0
		for _, id in b.order do
			local c = b.entities[id]
			if hits >= maxCount then
				break
			end
			if
				c
				and c.team == 2
				and targetable(c)
				and c.kind == "Enemy"
				and math.abs(c.x - h.x) <= 150 + c.hitDist
			then
				knockdown(c, main / 96)
				hits += 1
			end
		end
	elseif num == 9 then
		b.food = math.min(b.food + math.floor(main), b.stats.maxFood) -- D-MACE-09
	elseif num == 10 then
		fire(b, h, 273, 0, { poison = row.a2 + row.b2 * g, aura = false })
	end
end

local function heroLimit(b: any): number
	return if alive(castle(b)) then ALLY_LIMIT_CASTLE else ALLY_LIMIT_BOSS
end

local function stepHero(b: any)
	local h = hero(b)
	if not alive(h) then
		return
	end
	if h.state == "Mace" then
		h.stateTicks += 1
		if h.stateTicks == MACE_EFFECT_FRAME then
			local mace = b.activeMace
			b.activeMace = nil
			if mace then
				maceEffect(b, mace)
			end
		end
		if h.stateTicks >= MACE_FRAMES then
			enter(h, if b.axis ~= 0 then "Move" else "Idle")
		end
		return
	end
	if b.axis ~= 0 then
		h.state, h.dir = "Move", b.axis
		local speed = b.stats.moveSpeed + b.stats.moveSpeedRing
		h.x = math.clamp(h.x + b.axis * speed * DT, -40, heroLimit(b))
	else
		h.state = "Idle"
	end
end

local function useMace(b: any, slot: number): string?
	local h = hero(b)
	local item = b.loadout.equip[slot]
	if slot < 1 or slot > 3 or not item then
		return "InvalidPayload"
	elseif not alive(h) or (h.state ~= "Idle" and h.state ~= "Move") then
		return "Busy"
	end
	local grade = Rules.maceGrade(b.loadout, slot, false)
	local cost = Rules.maceCost(b.loadout, item.num, grade)
	if item.num == 11 then
		if (b.goldAvailable or 0) + b.rewards.gold - b.rewards.goldSpent < cost then
			return "InsufficientGold"
		end
		b.rewards.goldSpent += cost
	else
		if b.mana < cost then
			return "InsufficientMana"
		end
		b.mana -= cost
	end
	b.activeMace = { num = item.num, grade = grade }
	h.dir = 1
	enter(h, "Mace")
	return nil
end

local function summon(b: any, n: number): string?
	local row = Db.units[n]
	if not row or (b.loadout.unitLevels[n] or 0) < 1 then
		return "InvalidPayload"
	end
	local need = row.cooldown * b.stats.summonCooldownMul
	if b.summonPast[n] < need then
		return "Cooldown"
	elseif b.food < row.cost then
		return "InsufficientFood"
	elseif count(b, 1, true) >= ALLY_CAP then
		return "UnitCap"
	end
	b.food -= row.cost
	b.summonPast[n] = 0
	spawnUnit(b, n)
	return nil
end

-- ------------------------------------------------------------------ level-up choice (E03 §4.1)

local LIGHT_MAX = { 9, 9, 5, 20, 20, 5, 5, 10, 20, 5, 20, 10, 3, 5, 20, 5, 3, 5, 3, 5, 2, 5, 5 }

local function candidates(b: any, level: number): { number }
	local skills = b.loadout.skills
	local open: { number } = {}
	for i, max in LIGHT_MAX do
		if (skills[i] or 0) < max then
			table.insert(open, i)
		end
	end
	if #open <= 3 then
		return open
	end
	local picked: { number } = {}
	local function take(i: number)
		if (skills[i] or 0) < LIGHT_MAX[i] and not table.find(picked, i) then
			table.insert(picked, i)
		end
	end
	if level % 5 == 0 then
		take(11)
		take(9)
		take(({ 19, 12, 20 })[(level // 5 - 1) % 3 + 1])
	end
	while #picked < 3 do
		take(open[Rng.rand(b.rng) % #open + 1])
	end
	return picked
end

local function refreshStats(b: any)
	local h = hero(b)
	local old = b.stats
	b.stats = Rules.heroStats(b.loadout)
	h.maxHp = b.stats.maxHp
	h.hp = math.min(h.hp + math.max(b.stats.maxHp - old.maxHp, 0), h.maxHp)
end

local function pickSkill(b: any, choice: number): string?
	if not b.pendingPicks[1] or not b.offer then
		return "WrongPhase"
	end
	local level = b.pendingPicks[1]
	local skillIndex = b.offer[choice]
	if not skillIndex then
		return "InvalidPayload"
	end
	b.loadout.skills[skillIndex] = (b.loadout.skills[skillIndex] or 0) + 1
	b.loadout.level = level
	table.insert(b.rewards.picks, skillIndex)
	table.remove(b.pendingPicks, 1)
	b.offer = nil
	refreshStats(b)
	return nil
end

-- Draws the next offer inside `step` so views never touch the RNG.
local function prepareOffer(b: any)
	if b.pendingPicks[1] and not b.offer then
		b.offer = candidates(b, b.pendingPicks[1])
	end
end

-- ------------------------------------------------------------------ spawner (E04 §3)

local function pickEnemy(b: any): (number, number)
	local s = b.stage
	if s.p5 <= 0 or b.spawn.fifth < s.p5 then
		local v = ((Rng.rand(b.rng) % 10000) % 1000) // 10
		local check = 0
		for i = 1, 4 do
			check += s["p" .. i]
			if v < check then
				return s["u" .. i], i
			end
		end
		return 0, 0
	end
	b.spawn.fifth = -1
	return s.u5, 5
end

local function stepSpawner(b: any)
	local sp = b.spawn
	if sp.need < 0 then
		sp.need = nextSpawnGap(b) -- StartStage draws the first gap before any enemy (E04 §3-1)
	end
	sp.timer += DT
	if sp.timer < sp.need then
		return
	end
	local id, slot = pickEnemy(b)
	if id <= 0 then
		return -- empty band: retry next frame without resetting the timer (E04 §3-3)
	end
	if not spawnEnemy(b, id, slot) then
		return
	end
	sp.created += 1
	sp.total += 1
	sp.fifth += 1
	if sp.created >= b.stage.unitCount * 2 then
		sp.created = 0
	end
	sp.timer = 0
	sp.need = nextSpawnGap(b)
end

-- E04 §3-5: castle below 50% releases 10 giants one second apart: five of U3, then five of U2.
local function stepRush(b: any)
	local c = castle(b)
	local rush = b.rush
	if not rush.started then
		if alive(c) and c.hp < c.maxHp * 0.5 then
			rush.started, rush.left, rush.timer = true, 10, 1
		end
		return
	end
	if rush.left <= 0 then
		return
	end
	rush.timer += DT
	if rush.timer >= 1 then
		rush.timer = 0
		local id = if rush.left > 5 then b.stage.u3 else b.stage.u2
		spawnEnemy(b, id, 0, SCROLL_MAX, true)
		rush.left -= 1
	end
end

-- ------------------------------------------------------------------ step

local function regen(b: any)
	local h = hero(b)
	local stats = b.stats
	if not alive(h) then
		return
	end
	-- MP and food: per-0.1 s amounts x10 per second (E04 §1-4)
	b.mana = math.min(
		b.mana + (stats.manaPerTenth + stats.manaPerTenthPerAura * b.auraCount) * 10 * DT,
		stats.maxMana
	)
	b.food = math.min(
		b.food + (stats.foodPerTenth + stats.foodPerTenthPerAura * b.auraCount) * 10 * DT,
		stats.maxFood
	)
	b.hpRegenTicks += 1
	if b.hpRegenTicks >= 150 then
		b.hpRegenTicks = 0
		h.hp = math.min(h.hp + stats.hpRegen5, h.maxHp)
	end
	for n = 1, 9 do
		b.summonPast[n] += DT
	end
end

-- E03 §5.1: allied units within the radius on the hero's line are in the aura; regen aura every 5 s.
local function updateAura(b: any)
	local h = hero(b)
	local radius = b.stats.auraRadius
	local inside = 0
	for _, id in b.order do
		local e = b.entities[id]
		if e and e.kind == "Unit" then
			local was = e.aura
			e.aura = alive(e) and alive(h) and e.line == h.line and math.abs(h.x - e.x) <= radius
			if e.aura then
				inside += 1
				if not was then
					e.auraTicks = 0
				end
				e.auraTicks += 1
				if e.auraTicks >= 150 then
					e.auraTicks = 0
					e.hp = math.min(e.hp + e.maxHp * b.stats.auraRegen, e.maxHp)
				end
			end
		end
	end
	b.auraCount = inside
end

local function runCommands(b: any, commands: { any }): { any }
	local results = {}
	for _, command in commands do
		local reason: string?
		if command.kind == "PickSkill" then
			reason = pickSkill(b, command.choice)
		elseif #b.pendingPicks > 0 then
			reason = "WrongPhase" -- battle is paused for the level-up choice (D-LVUP-01)
		elseif command.kind == "Summon" then
			reason = summon(b, command.unit)
		elseif command.kind == "Mace" then
			reason = useMace(b, command.slot)
		else
			reason = "InvalidPayload"
		end
		table.insert(results, {
			requestId = command.requestId,
			status = if reason then "Rejected" else "Accepted",
			reason = reason,
		})
	end
	return results
end

local function decideOutcome(b: any)
	if not alive(hero(b)) then
		b.outcome = "Defeat"
	elseif not alive(castle(b)) then
		b.outcome = "Victory"
	end
end

local function cleanup(b: any)
	local kept: { number } = {}
	for _, id in b.order do
		local e = b.entities[id]
		if e and (alive(e) or id == b.heroId or id == b.castleId) then
			table.insert(kept, id)
		else
			b.entities[id] = nil
		end
	end
	b.order = kept
end

export type Input = { commands: { any }?, axis: number? }

local function step(b: any, input: Input?): any
	local commands: { any } = if input and input.commands then input.commands else {}
	if b.outcome then
		local rejected: { any } = {}
		for _, command in commands do
			table.insert(
				rejected,
				{ requestId = command.requestId, status = "Rejected", reason = "WrongPhase" }
			)
		end
		return { results = rejected, outcome = b.outcome }
	end
	local axis = if input and input.axis then math.sign(input.axis) else 0
	b.axis = axis
	local results = runCommands(b, commands)
	if #b.pendingPicks > 0 then
		prepareOffer(b)
		return { results = results, outcome = nil, paused = true }
	end
	b.tick += 1
	regen(b)
	stepSpawner(b)
	stepRush(b)
	stepHero(b)
	updateAura(b)
	local snapshotOrder = table.clone(b.order)
	for _, id in snapshotOrder do
		local e = b.entities[id]
		if e then
			stepEntity(b, e)
		end
	end
	stepObjects(b)
	decideOutcome(b)
	cleanup(b)
	prepareOffer(b)
	return { results = results, outcome = b.outcome }
end

-- ------------------------------------------------------------------ views and digest

local function snapshot(b: any): any
	local list = {}
	for _, id in b.order do
		local e = b.entities[id]
		table.insert(list, {
			id = e.id,
			kind = e.kind,
			n = e.n,
			team = e.team,
			x = e.x,
			y = e.y,
			line = e.line,
			dir = e.dir,
			hp = e.hp,
			maxHp = e.maxHp,
			state = e.state,
			aura = e.aura,
			giant = e.giant,
			enhanced = e.enhanced,
		})
	end
	local objects = {}
	for _, id in b.objectOrder do
		local o = b.objects[id]
		table.insert(objects, {
			id = o.id,
			kind = o.kind,
			row = o.row,
			team = o.team,
			x = o.x,
			line = o.line,
			dir = o.dir,
		})
	end
	return {
		tick = b.tick,
		food = b.food,
		mana = b.mana,
		maxFood = b.stats.maxFood,
		maxMana = b.stats.maxMana,
		summonPast = table.clone(b.summonPast),
		level = b.level,
		exp = b.expBase + b.exp,
		gold = b.rewards.gold,
		offer = if b.offer then table.clone(b.offer) else nil,
		outcome = b.outcome,
		entities = list,
		objects = objects,
	}
end

local function digest(b: any): string
	local parts = {
		string.format(
			"t%d|r%d|f%.17g|m%.17g|h%d|l%d|x%.17g|g%d,%d|k%d|o%s|s%d,%d,%d,%.17g,%.17g|u%s,%d,%.17g",
			b.tick,
			b.rng.state,
			b.food,
			b.mana,
			b.hpRegenTicks,
			b.level,
			b.exp,
			b.rewards.gold,
			b.rewards.goldSpent,
			b.rewards.killTotal,
			tostring(b.outcome),
			b.spawn.created,
			b.spawn.total,
			b.spawn.fifth,
			b.spawn.timer,
			b.spawn.need,
			tostring(b.rush.started),
			b.rush.left,
			b.rush.timer
		),
	}
	for n = 1, 9 do
		table.insert(parts, string.format("%.17g", b.summonPast[n]))
	end
	for _, id in b.order do
		local e = b.entities[id]
		table.insert(
			parts,
			string.format(
				"%d:%s%d:%.17g:%.17g/%.17g:%s:%d:%.17g:%s:%s:%d",
				e.id,
				e.kind,
				e.n,
				e.x,
				e.hp,
				e.maxHp,
				e.state,
				e.stateTicks,
				e.attackPast,
				tostring(e.target),
				tostring(e.aura),
				e.poisonLeft
			)
		)
	end
	for _, id in b.objectOrder do
		local o = b.objects[id]
		table.insert(
			parts,
			string.format("o%d:%d:%.17g:%d:%d", o.id, o.row, o.x, o.pierce, o.ticks)
		)
	end
	local text = table.concat(parts, "|")
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 403 + bit32.lshift(hash, 24)) % 4294967296
	end
	return string.format("%08x", hash)
end

return table.freeze({
	DT = DT,
	SCROLL_MAX = SCROLL_MAX,
	new = new,
	step = step,
	snapshot = snapshot,
	digest = digest,
	spawnUnit = spawnUnit,
	spawnEnemy = spawnEnemy,
	strike = strike,
	count = count,
	hero = hero,
	castle = castle,
	alive = alive,
	candidates = candidates,
})
