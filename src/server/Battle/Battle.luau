--!strict
-- Authoritative remake battle (docs/REMAKE_PLAN.md R1-R2). Original px/second units on a fixed 30 Hz
-- tick (one tick = one 1/30 s animation frame). Pure Luau: no Instances, clocks or engine RNG.
-- Rule sources: E02 (combat/units/bosses), E03 (hero/maces/aura), E04 (resources/spawn/stage modes).
local Db = require("../Config/Remake/Db")
local Rng = require("./Rng")
local Rules = require("./Rules")

local DT = 1 / 30
local SCROLL_MAX = 1024
local CASTLE_X = SCROLL_MAX - 120
local ALLY_LIMIT_CASTLE = SCROLL_MAX - 160
local ALLY_LIMIT_BOSS = SCROLL_MAX - 40
local WAGON_GOAL = SCROLL_MAX - 154 -- 870 (E04 §4)
local NEAR_SPAWN_X = 480 -- destiny / tower spawn x and tower scoring line (E04 §4-2, §6)
local KNOCK_SPEED = 180
local KNOCK_FRAMES = 16
local KNOCK_WAIT = 3
local SLIDE_PX = 5
local PROJECTILE_HALF_WIDTH = 10 -- D-PROJ-01: sprite half width is not in the research data
local MACE_FRAMES, MACE_EFFECT_FRAME = 18, 8 -- D-ANIM-02: hero part animations were not parsed
local FIFTEEN_MINUTES = 900
local DESTINY_KILLS, DESTINY_SPAWNS = 60, 60
local TOWER_POINTS = 15
local REVIVE_INVULN_TICKS = 300 -- 10 s after a revive (E03 §1.6)
local REVIVE_WAIT_STEPS = 300 -- D-REVIVE-02: unanswered offer gives up after 10 s
-- Server protection only; the original has no unit cap (E02 §5). D-CAP-01.
local ALLY_CAP, ENEMY_CAP, OBJECT_CAP = 80, 120, 256
-- E02 §2.9 documented attack animation frame counts {attack1, skill}; others use D-ANIM-01.
local UNIT_ANIM: { [number]: { number } } =
	{ [1] = { 10, 16 }, [2] = { 20, 20 }, [5] = { 20, 20 }, [8] = { 20, 20 } }
local ENEMY_ANIM: { [number]: number } = { [1] = 10, [17] = 75 }
local OBJECTS: { [string]: any } = Db.objects :: any
local SKILL_MULTIPLIED = { [1] = true, [2] = true, [3] = true, [5] = true, [7] = true, [9] = true }
-- E04 §0: stage number mod 12 picks the light-hero mode; tower and dungeon shrink everything.
local MODE_BY_REMAINDER = { [0] = "Boss", [3] = "Destiny", [6] = "Wagon", [9] = "Tower" }

export type Entity = {
	id: number,
	kind: string, -- "Hero" | "Unit" | "Enemy" | "Boss" | "Castle" | "Wagon"
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
	frogTicks: number,
	invulnTicks: number,
	minion: boolean,
	hold: boolean,
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
	ownerKind: string,
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
	deathChance: number,
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
	revives: number?, -- revive offers available (gems checked by the caller, D-REVIVE-01)
}

local function modeOf(stage: number): string
	return MODE_BY_REMAINDER[stage % 12] or "Normal"
end

local function cloneLoadout(l: Rules.Loadout): Rules.Loadout
	local equip = {}
	for slot, item in l.equip do
		equip[slot] = { num = item.num, grade = item.grade }
	end
	return {
		heroKind = l.heroKind,
		level = l.level,
		exp = l.exp,
		skills = table.clone(l.skills),
		equip = equip,
		difficulty = l.difficulty,
		unitLevels = table.clone(l.unitLevels),
	}
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
		frogTicks = 0,
		invulnTicks = 0,
		minion = false,
		hold = false,
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
			and (not unitsOnly or e.kind == "Unit" or e.kind == "Enemy" or e.kind == "Boss")
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

-- Tower lanes are drawn at y = (lane - 1) * 33 + 75 (E04 §4-2).
local function laneY(lane: number): number
	return (lane - 1) * 33 + 75
end

local function frames(hitFrame: number, known: number?): number
	return known or math.max(hitFrame + 4, 10) -- D-ANIM-01
end

local function spawnUnit(b: any, n: number, lane: number?): Entity
	local row = Db.units[n]
	local level = math.clamp(b.loadout.unitLevels[n] or 1, 1, 20)
	local e = newEntity(b, "Unit", n, 1)
	e.hp, e.maxHp, e.ap = row.levels.hp[level], row.levels.hp[level], row.levels.ap[level] -- level table replaces base (E02 §1.4)
	e.speed, e.attackDist, e.hitDist, e.attackDelay =
		row.moveSpeed * b.scale, row.attackDist, row.hitDist, row.attackDelay
	e.skillPercent, e.skillDamage, e.knockPercent, e.skillDist =
		row.skillPercent, row.skillDamage, row.knockPercent, row.skillDist
	e.atkFrame, e.skillFrame = row.attackFrame, row.skillFrame
	local known = UNIT_ANIM[n]
	e.atkAnim = frames(row.attackFrame, known and known[1])
	e.skillAnim = frames(row.skillFrame, known and known[2])
	if n == 4 then
		e.skillAnim = 14 -- kangaroo fires 5 fists over frames 4..12 (E02 §4.3)
	end
	e.x = 0
	if lane then
		e.line, e.y = lane, laneY(lane)
	else
		e.y = depthY(b, row.createLine)
	end
	return add(b, e)
end

-- Enemy id rules (E04 §3-3): 1..20 base, 21..40 enhanced x1.3, 101..110 bosses.
local function spawnEnemy(
	b: any,
	enemyId: number,
	slot: number,
	x: number?,
	forceGiant: boolean?,
	line: number?
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
	e.speed = row.moveSpeed * scale * b.scale
	e.attackDist, e.hitDist, e.attackDelay = row.attackDist, row.hitDist, row.attackDelay
	e.skillPercent, e.skillDamage, e.knockPercent, e.skillDist =
		row.skillPercent, row.skillDamage, row.knockPercent, row.skillDist
	e.atkFrame = row.attackFrame
	e.atkAnim = frames(row.attackFrame, if boss then nil else ENEMY_ANIM[base])
	e.skillAnim = e.atkAnim
	e.rewardGold, e.rewardExp = row.rewardGold, row.rewardExp
	e.x = x or b.enemySpawnX
	if line and line > 0 then
		e.line, e.y = line, laneY(line)
	else
		e.y = depthY(b, 0)
	end
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
		revives = 0,
		summons = {},
		maceUses = {},
		maceKills = 0,
		passed = 0,
	}
end

-- E04 §4-1: destiny forces every unit to 1, 3, 5, ..., 19 by twelve-stage block (D-DESTINY-01 reuses it
-- for the forced weapon grade, which the research leaves unspecified).
local function destinyLevel(stage: number): number
	return 2 * ((stage - 1) // 12) + 1
end

local function destinyAux(stage: number): (any, any)
	local index = ((stage - 3) // 12) * 2 + 1
	return Db.destinyAux[index], Db.destinyAux[index + 1]
end

local function new(options: Options): any
	local stageNumber = options.stage
	local stage = Db.campaign[stageNumber]
	assert(stage, "unknown stage " .. tostring(stageNumber))
	local mode = modeOf(stageNumber)
	local loadout = cloneLoadout(options.loadout)
	local destinyMace, destinyUnit = nil, nil
	if mode == "Destiny" then
		destinyMace, destinyUnit = destinyAux(stageNumber)
		local level, grade = destinyLevel(stageNumber), destinyLevel(stageNumber)
		for n = 1, 9 do
			loadout.unitLevels[n] = level
		end
		loadout.equip[1] = { num = destinyMace.u1, grade = grade }
		loadout.equip[2] = { num = destinyMace.u2, grade = grade }
		loadout.equip[3] = { num = destinyMace.u5, grade = grade }
	end
	local stats = Rules.heroStats(loadout)
	local b: any = {
		tick = 0,
		stageNumber = stageNumber,
		stage = stage,
		mode = mode,
		scale = if mode == "Tower" then 0.6 else 1, -- E04 §0 global scale
		enemySpawnX = if mode == "Destiny" or mode == "Tower" then NEAR_SPAWN_X else SCROLL_MAX,
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
		summonPast = { 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000 }, -- ticks; all ready at start (E04 §1-1)
		auraCount = 0,
		level = loadout.level,
		exp = 0,
		expBase = loadout.exp or 0,
		pendingPicks = {},
		offer = nil,
		rewards = newRewards(),
		spawn = { created = 0, total = 0, fifth = 0, timer = 0, need = -1 },
		rush = { started = false, left = 0, timer = 0 },
		outcome = nil,
		heroId = 0,
		castleId = 0,
		wagonId = 0,
		bossId = 0,
		axis = 0,
		activeMace = nil,
		goldAvailable = options.goldAvailable or 0,
		revivesLeft = options.revives or 0,
		reviveOffer = false,
		reviveWait = 0,
		points = 0,
		boxes = {},
		boxTimer = 0,
		destinyMace = destinyMace,
		destinyUnit = destinyUnit,
		auxFifth = { mace = 0, unit = 0 },
	}
	local hero = newEntity(b, "Hero", 0, 1)
	hero.hp, hero.maxHp = stats.maxHp, stats.maxHp
	hero.hitDist, hero.speed, hero.state = Db.specials.lightHero.hitDist, stats.moveSpeed, "Idle"
	hero.x = if mode == "Destiny" then 45 elseif mode == "Tower" then 32 else 100 -- E04 §6
	hero.y = 165
	if mode == "Tower" then
		hero.line, hero.y = 0, laneY(0)
	end
	b.heroId = add(b, hero).id
	if mode == "Normal" or mode == "Boss" then
		local castle = newEntity(b, "Castle", 11, 2)
		castle.x, castle.hitDist, castle.state = CASTLE_X, Db.specials.castle.hitDist, "Idle"
		castle.hp = stage.castleHp * b.difficulty.hp
		castle.maxHp = castle.hp
		b.castleId = add(b, castle).id
	elseif mode == "Wagon" then
		-- Escort wagon: HP is the stage iECHP_ column, starts at x = -100 (E04 §4).
		local wagon = newEntity(b, "Wagon", 1, 1)
		wagon.x, wagon.hitDist, wagon.state = -100, Db.specials.wagon.hitDist, "Move"
		wagon.hp, wagon.maxHp = stage.castleHp, stage.castleHp
		wagon.speed = Db.specials.wagon.moveSpeed
		wagon.y = 165
		b.wagonId = add(b, wagon).id
	elseif mode == "Tower" then
		-- Fixed mid boss s/12 + 1 at x = 420, holding position (E04 §3-7); lane 3 is D-TOWER-02.
		local guard = spawnEnemy(b, 100 + stageNumber // 12 + 1, 0, 420, false, 3)
		if guard then
			guard.hold = true
		end
	end
	return b
end

local function hero(b: any): Entity
	return b.entities[b.heroId]
end

local function castle(b: any): Entity?
	return b.entities[b.castleId]
end

-- E04 §3-1: next spawn gap in [min, max+0.9] seconds at 0.1 s resolution.
local function gapIn(b: any, lo: number, hi: number): number
	local range = hi - lo + 1
	return ((Rng.rand(b.rng) % 10000) % (range * 10)) / 10 + lo
end

local function nextSpawnGap(b: any): number
	local s = b.stage
	if b.mode == "Destiny" then
		-- fixed pattern on the running total (E04 §3-1): forced 5 s at 10/20/30
		local total = b.spawn.total
		if total == 10 or total == 20 or total == 30 then
			return 5
		end
		if total < 10 or (total >= 20 and total <= 30) then
			return gapIn(b, s.s11, s.s12)
		end
		return gapIn(b, s.s21, s.s22)
	end
	if b.spawn.created < s.unitCount then
		return gapIn(b, s.s11, s.s12)
	end
	return gapIn(b, s.s21, s.s22)
end

-- ------------------------------------------------------------------ damage (E02 §2.1-§2.2)

local function needSlide(e: Entity): boolean
	if e.kind ~= "Unit" and e.kind ~= "Enemy" then
		return false -- hero, bosses, castle and wagon never slide
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
		return -- hero, boss, castle and wagon are immune (E02 §4.4)
	end
	e.state, e.stateTicks, e.knockMul, e.target = "Knock", 0, mul or 1, nil
end

local function freeze(e: Entity, seconds: number)
	if e.kind == "Unit" or e.kind == "Enemy" then
		e.state, e.stateTicks, e.stateLimit, e.target =
			"Ice", 0, math.floor(seconds * 30 + 0.5), nil
	end
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
	-- Boss-summoned minions and kills after 15 minutes outside survival pay 1 gold, 0 EXP (E04 §2-2).
	if e.minion or playTime >= FIFTEEN_MINUTES then
		gold, exp = 1, 0
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
		if killer and killer.kind == "Hero" then
			b.rewards.maceKills += 1
		end
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
	if target.kind == "Hero" and target.invulnTicks > 0 then
		return -- 10 s invulnerability after a revive (E03 §1.6)
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
	return alive(e) and e.state ~= "Ghost" and e.state ~= "Blink"
end

-- Who may hit whom: the mirror knight only takes hero damage; the frost witch never targets the hero.
local function canHit(attackerKind: string, attackerN: number, c: Entity): boolean
	local targetKind: string = c.kind
	local mirror = targetKind == "Boss" and c.n == 7 -- E02 §4.4 boss 07
	local witch = attackerKind == "Boss" and attackerN == 2 -- E02 §4.4 boss 02
	return not ((mirror and attackerKind ~= "Hero") or (witch and targetKind == "Hero"))
end

local function nearestFront(b: any, e: Entity, reach: number): Entity?
	local best, bestDist = nil, math.huge
	for _, id in b.order do
		local c = b.entities[id]
		if
			c
			and c.team ~= e.team
			and targetable(c)
			and c.line == e.line
			and canHit(e.kind, e.n, c)
		then
			local dx = (c.x - e.x) * e.dir
			if dx >= 0 and dx <= reach + c.hitDist and dx < bestDist then
				best, bestDist = c, dx
			end
		end
	end
	return best
end

local function area(
	b: any,
	e: Entity,
	x: number,
	reach: number,
	both: boolean,
	fn: (Entity) -> (),
	limit: number?
)
	local hit: { Entity } = {}
	for _, id in b.order do
		local c = b.entities[id]
		if
			c
			and c.team ~= e.team
			and targetable(c)
			and c.line == e.line
			and canHit(e.kind, e.n, c)
		then
			local dx = (c.x - x) * e.dir
			if (both or dx >= 0) and math.abs(dx) <= reach + c.hitDist then
				table.insert(hit, c)
				if limit and #hit >= limit then
					break
				end
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
		ownerKind = spec.ownerKind or "",
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
		deathChance = spec.deathChance or 0,
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

local function poison(e: Entity, dps: number)
	e.poisonDps, e.poisonLeft, e.poisonTicks = dps, 10, 0
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
	if o.freeze > 0 and alive(target) then
		freeze(target, o.freeze)
	end
	if o.poison > 0 and alive(target) then
		poison(target, o.poison)
	end
end

local function hitsFrom(o: Object, c: Entity): boolean
	return c.team ~= o.team and targetable(c) and c.line == o.line and canHit(o.ownerKind, 0, c)
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
				if c and hitsFrom(o, c) and not o.hit[c.id] then
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
				local hitList: { Entity } = {}
				if o.single then
					local best: Entity?, bestDist = nil, math.huge
					for _, eid in b.order do
						local c: Entity? = b.entities[eid]
						if c and hitsFrom(o, c) then
							local d = math.abs(c.x - o.x)
							if d <= o.area + c.hitDist and d < bestDist then
								best, bestDist = c, d
							end
						end
					end
					if best then
						table.insert(hitList, best)
					end
				else
					for _, eid in b.order do
						local c: Entity? = b.entities[eid]
						if c and hitsFrom(o, c) and math.abs(c.x - o.x) <= o.area + c.hitDist then
							table.insert(hitList, c)
						end
					end
				end
				for _, c in hitList do
					if o.deathChance > 0 and Rng.rand(b.rng) % 100 < o.deathChance then
						-- death knight: instant kill, the hero keeps 1 HP (E02 §4.4 boss 10)
						if c.kind == "Hero" then
							c.hp = math.min(c.hp, 1)
						elseif c.kind ~= "Boss" then
							kill(b, c, owner)
						end
					else
						strike(b, owner, c, o.ap * o.areaMul, false, o.aura)
					end
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
		ownerKind = e.kind,
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
		ownerKind = e.kind,
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

local function summonMinions(b: any, boss: Entity, enemyId: number)
	for _ = 1, 2 do
		local minion = spawnEnemy(b, enemyId, 0, boss.x, false, boss.line)
		if minion then
			minion.minion = true
			if enemyId == 1 then
				minion.ap = 0 -- the zombie king's escorts deal no damage (E02 §4.4 boss 01)
			end
		end
	end
end

local function bossRelease(b: any, e: Entity, target: Entity?)
	local n = e.n
	if n == 1 then
		summonMinions(b, e, 1)
		if target and alive(target) then
			strike(b, e, target, e.ap, false, false)
		end
	elseif n == 2 then
		-- frost witch: turns the first target in range into a frog for 8 s (E02 §4.4)
		if target and alive(target) then
			strike(b, e, target, e.ap, false, false)
			if alive(target) and target.kind == "Unit" then
				target.frogTicks, target.target = 8 * 30, nil
				if
					target.state == "Delay"
					or target.state == "Attack"
					or target.state == "Skill"
				then
					target.state, target.stateTicks = "Move", 0
				end
			end
		end
	elseif n == 3 then
		if target and alive(target) then
			strike(b, e, target, e.ap, false, false)
			if alive(target) then
				knockdown(target, 3) -- every hit knocks back about 288 px
			end
		end
	elseif n == 4 then
		summonMinions(b, e, 27)
		if target and alive(target) then
			strike(b, e, target, e.ap, false, false)
		end
	elseif n == 6 then
		if target and alive(target) then
			kill(b, target, e) -- the glutton swallows its target whole, hero included
		end
	elseif n == 7 then
		fire(b, e, 301, e.ap)
	elseif n == 8 then
		-- breath over at most three targets, each 25% to freeze for 3 s
		area(b, e, e.x, e.attackDist + 30, true, function(c)
			strike(b, e, c, e.ap, false, false)
			if alive(c) and Rng.rand(b.rng) % 100 < e.skillPercent then
				freeze(c, 3)
			end
		end, 3)
	elseif n == 9 then
		fire(b, e, 302, 0, { poison = OBJECTS.r302.attackPower })
	elseif n == 10 then
		area(b, e, e.x, e.attackDist, false, function(c)
			launch(b, {
				kind = "Drop",
				row = 303,
				team = e.team,
				owner = e.id,
				ownerKind = e.kind,
				x = c.x,
				line = e.line,
				dir = e.dir,
				ap = e.ap,
				area = 0,
				single = true,
				deathChance = OBJECTS.r303.percent,
				duration = OBJECTS.r303.frame,
			})
		end)
	elseif target and alive(target) then
		strike(b, e, target, e.ap, false, false)
	end
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
	if e.kind == "Boss" then
		bossRelease(b, e, target)
		return
	end
	local n = e.n
	if n == 2 then
		fire(b, e, 295, e.ap)
	elseif n == 6 then
		fire(b, e, 296, e.ap)
	elseif n == 18 then
		fire(b, e, 299, e.ap)
	elseif n == 10 and target then
		lob(b, e, 297, target, e.ap, OBJECTS.r297.range, 1, true, 0)
	elseif n == 14 and target then
		launch(b, {
			kind = "Drop",
			row = 298,
			team = e.team,
			owner = e.id,
			ownerKind = e.kind,
			x = target.x,
			line = e.line,
			dir = e.dir,
			ap = e.ap,
			area = OBJECTS.r298.range,
			single = true,
			duration = OBJECTS.r298.frame,
		})
	elseif n == 17 then
		-- bomber self-destructs over everyone near it (E02 §4.4), counted as a kill without reward
		area(b, e, e.x, e.attackDist + 30, true, function(c)
			strike(b, e, c, e.ap, false, false)
		end)
		e.removed, e.state = true, "Dead"
		b.rewards.killTotal += 1
	elseif target and alive(target) then
		strike(b, e, target, e.ap, false, false)
	end
end

local function isWall(e: Entity): boolean
	return (e.kind == "Unit" and e.n == 6) or (e.kind == "Enemy" and (e.n == 12 or e.n == 20))
end

local function allyLimit(b: any): number
	if b.mode == "Tower" then
		return math.huge -- scored at the far line instead
	end
	return if alive(castle(b)) then ALLY_LIMIT_CASTLE else ALLY_LIMIT_BOSS
end

local function enter(e: Entity, state: string, limit: number?)
	e.state, e.stateTicks, e.stateLimit = state, 0, limit or 0
end

local function tickPoison(b: any, e: Entity)
	-- 1 s ticks for 10 s, never below 1 HP (E02 §3.4)
	if e.poisonLeft > 0 then
		e.poisonTicks += 1
		if e.poisonTicks >= 30 then
			e.poisonTicks = 0
			e.poisonLeft -= 1
			e.hp = math.max(e.hp - e.poisonDps, math.min(e.hp, 1))
		end
	end
	local _ = b
end

-- Tower scoring (E04 §4-2): allies past x 480 score +1, enemies past x 0 score -1; both leave the field.
local function towerScore(b: any, e: Entity): boolean
	if b.mode ~= "Tower" then
		return false
	end
	if e.team == 1 and e.kind == "Unit" and e.x >= NEAR_SPAWN_X then
		b.points = math.min(b.points + 1, TOWER_POINTS)
	elseif e.team == 2 and e.x <= 0 then
		b.points = math.max(b.points - 1, -TOWER_POINTS)
		b.rewards.passed += 1
	else
		return false
	end
	e.removed, e.state = true, "Dead"
	return true
end

local function stepEntity(b: any, e: Entity)
	if e.kind == "Hero" or e.kind == "Castle" or e.kind == "Wagon" or not alive(e) then
		return
	end
	e.stateTicks += 1
	e.attackPast += 1 -- timers count whole ticks; seconds compare as ticks (no float drift)
	tickPoison(b, e)
	if e.frogTicks > 0 then
		e.frogTicks -= 1
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
	elseif state == "Blink" then
		-- teleport ghost boss: 1 s fade-out, jump to a random x >= 400, 1 s fade-in (E02 §4.4 boss 05)
		if e.stateLimit == 0 and e.stateTicks >= 30 then
			e.x = 400 + Rng.rand(b.rng) % (SCROLL_MAX - 80 - 400)
			e.stateLimit, e.stateTicks = 1, 0
		elseif e.stateLimit == 1 and e.stateTicks >= 30 then
			enter(e, "Move")
		end
		return
	end
	local target = if e.target then b.entities[e.target] else nil
	if state == "Move" then
		local found = if e.frogTicks > 0 then nil else nearestFront(b, e, e.attackDist)
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
			if e.hold then
				return
			end
			local speed = e.speed
			if e.kind == "Unit" and e.aura then
				speed *= b.stats.auraMove
			end
			e.x += e.dir * speed * DT
			if towerScore(b, e) then
				return
			end
			if e.team == 1 then
				e.x = math.min(e.x, allyLimit(b))
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
			or e.frogTicks > 0
			or math.abs(target.x - e.x) > e.attackDist + target.hitDist
		then
			e.target = nil
			enter(e, "Move")
			return
		end
		local delay = e.attackDelay
			* (if e.kind == "Unit" and e.aura then b.stats.auraEnergy else 1)
		if e.attackPast >= delay * 30 - 1e-6 then
			local p = e.skillPercent
			if e.kind == "Unit" and e.aura then
				p *= b.stats.auraSkill
			end
			local roll = Rng.rand(b.rng) % 1000
			if e.kind == "Unit" and not e.aura then
				roll = p * 10 -- outside the aura allied units never use skills (E03 §5.2)
			end
			if e.kind == "Boss" and (e.n == 8 or e.n == 10) then
				roll = p * 10 -- these bosses never enter the skill state (E02 §2.3)
			end
			e.struck = false
			if roll < p * 10 then
				if e.kind == "Boss" and e.n == 5 then
					e.target = nil
					enter(e, "Blink")
					return
				end
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
			if target and targetable(target) and e.frogTicks == 0 then
				enter(e, "Delay")
			else
				e.target = nil
				enter(e, "Move")
			end
		end
	end
end

-- D-WAGON-01: the escort wagon rolls forward unless an enemy body touches its front.
local function stepWagon(b: any)
	local w = b.entities[b.wagonId]
	if not alive(w) then
		return
	end
	for _, id in b.order do
		local c = b.entities[id]
		if c and c.team == 2 and targetable(c) and c.line == w.line then
			local dx = c.x - w.x
			if dx >= 0 and dx <= w.hitDist + c.hitDist then
				return
			end
		end
	end
	w.x += w.speed * DT
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
			local found = nearestEnemyWithin(b, h, 300)
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
	if b.mode == "Destiny" then
		return 480 - 40 -- fScreenW - 40 (E03 §1.4)
	end
	return if alive(castle(b)) then ALLY_LIMIT_CASTLE else ALLY_LIMIT_BOSS
end

local function heroCanMove(b: any): boolean
	return b.mode ~= "Destiny" and b.mode ~= "Tower" -- move buttons are disabled there (E03 §1.1)
end

local function stepHero(b: any)
	local h = hero(b)
	if not alive(h) then
		return
	end
	tickPoison(b, h)
	if h.invulnTicks > 0 then
		h.invulnTicks -= 1
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
	if b.axis ~= 0 and heroCanMove(b) then
		h.state, h.dir = "Move", b.axis
		local speed = b.stats.moveSpeed + b.stats.moveSpeedRing
		h.x = math.clamp(h.x + b.axis * speed * DT, -40, heroLimit(b))
	else
		h.state = "Idle"
	end
end

local function startMace(b: any, num: number, grade: number)
	b.activeMace = { num = num, grade = grade }
	b.rewards.maceUses[num] = (b.rewards.maceUses[num] or 0) + 1
	local h = hero(b)
	h.dir = 1
	enter(h, "Mace")
end

local function useMace(b: any, slot: number): string?
	local h = hero(b)
	local item = b.loadout.equip[slot]
	if slot < 1 or slot > 3 or not item then
		return "InvalidPayload"
	elseif not alive(h) or (h.state ~= "Idle" and h.state ~= "Move") then
		return "Busy"
	end
	local grade = Rules.maceGrade(b.loadout, slot, b.mode == "Destiny")
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
	startMace(b, item.num, grade)
	return nil
end

local function unitReady(b: any, n: number): (string?, any)
	local row = Db.units[n]
	if not row or (b.loadout.unitLevels[n] or 0) < 1 then
		return "InvalidPayload", nil
	elseif count(b, 1, true) >= ALLY_CAP then
		return "UnitCap", nil
	end
	return nil, row
end

local function summon(b: any, n: number, lane: number?): string?
	if b.mode == "Destiny" then
		return "WrongMode" -- destiny summons only through boxes (D-DESTINY-03)
	end
	if b.mode == "Tower" and (type(lane) ~= "number" or lane < 1 or lane > 5 or lane % 1 ~= 0) then
		return "InvalidPayload" -- tower summons pick a lane (E04 §4-2)
	end
	local problem, row = unitReady(b, n)
	if problem then
		return problem
	end
	local need = row.cooldown * b.stats.summonCooldownMul
	if b.summonPast[n] < need * 30 - 1e-6 then
		return "Cooldown"
	elseif b.food < row.cost then
		return "InsufficientFood"
	end
	b.food -= row.cost
	b.summonPast[n] = 0
	b.rewards.summons[n] = (b.rewards.summons[n] or 0) + 1
	spawnUnit(b, n, if b.mode == "Tower" then lane else nil)
	return nil
end

-- Tower weapon buttons cost 90/90/30 MP (E04 §1-1). Button 1 summons five at once; D-TOWER-01 fixes
-- button 0 as one unit on every lane and button 2 as a full heal of allied units.
local TOWER_COST = { 90, 90, 30 }
local function towerButton(b: any, slot: number, n: number?, lane: number?): string?
	local cost = TOWER_COST[slot]
	if not cost then
		return "InvalidPayload"
	elseif b.mana < cost then
		return "InsufficientMana"
	end
	if slot == 3 then
		b.mana -= cost
		for _, id in b.order do
			local c = b.entities[id]
			if c and c.kind == "Unit" and alive(c) then
				c.hp = c.maxHp
			end
		end
		return nil
	end
	if type(n) ~= "number" then
		return "InvalidPayload"
	end
	local problem = unitReady(b, n)
	if problem then
		return problem
	end
	if slot == 1 then
		b.mana -= cost
		for l = 1, 5 do
			spawnUnit(b, n, l)
		end
		return nil
	end
	if type(lane) ~= "number" or lane < 1 or lane > 5 or lane % 1 ~= 0 then
		return "InvalidPayload"
	end
	b.mana -= cost
	for _ = 1, 5 do
		spawnUnit(b, n, lane)
	end
	return nil
end

-- ------------------------------------------------------------------ destiny boxes (E04 §4-1)

-- Same draw as enemy selection (E04 §3-3) over an auxiliary row: U5 every (P5+1)th draw.
local function pickAux(b: any, row: any, key: string): number
	if row.p5 <= 0 or b.auxFifth[key] < row.p5 then
		local v = ((Rng.rand(b.rng) % 10000) % 1000) // 10
		local check = 0
		for i = 1, 4 do
			check += row["p" .. i]
			if v < check and row["u" .. i] > 0 then
				b.auxFifth[key] += 1
				return row["u" .. i]
			end
		end
		return 0
	end
	b.auxFifth[key] = 0
	return row.u5
end

local function stepBoxes(b: any)
	if b.mode ~= "Destiny" then
		return
	end
	local interval = b.destinyMace.s11 * (if b.loadout.difficulty == 3 then 2 / 3 else 1)
	b.boxTimer += 1
	if b.boxTimer < interval * 30 - 1e-6 then
		return
	end
	local slot = nil
	for i = 1, 9 do
		if not b.boxes[i] then
			slot = i
			break
		end
	end
	if not slot then
		return -- all nine boxes full: wait (timer keeps its value)
	end
	b.boxTimer = 0
	if Rng.rand(b.rng) % 2 == 0 then
		local unitId = pickAux(b, b.destinyUnit, "unit")
		if unitId > 0 then
			b.boxes[slot] = { kind = "Unit", id = unitId }
		end
	else
		local maceId = pickAux(b, b.destinyMace, "mace")
		if maceId > 0 then
			b.boxes[slot] = { kind = "Mace", id = maceId }
		end
	end
end

-- A box spends itself for free: a unit at the forced level or a weapon effect (D-DESTINY-02: no food).
local function openBox(b: any, index: number): string?
	if b.mode ~= "Destiny" then
		return "WrongMode"
	end
	local box = type(index) == "number" and b.boxes[index]
	if not box then
		return "InvalidPayload"
	end
	if box.kind == "Unit" then
		local problem = unitReady(b, box.id)
		if problem then
			return problem
		end
		spawnUnit(b, box.id)
	else
		local h = hero(b)
		if not alive(h) or (h.state ~= "Idle" and h.state ~= "Move") then
			return "Busy"
		end
		startMace(b, box.id, destinyLevel(b.stageNumber))
	end
	b.boxes[index] = nil
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

-- ------------------------------------------------------------------ revive (D-REVIVE-01/02)

local function revive(b: any): string?
	if not b.reviveOffer then
		return "WrongPhase"
	end
	local h = hero(b)
	b.reviveOffer, b.reviveWait = false, 0
	b.revivesLeft -= 1
	b.rewards.revives += 1
	h.state, h.stateTicks, h.hp = "Idle", 0, h.maxHp
	h.invulnTicks = REVIVE_INVULN_TICKS
	h.poisonLeft = 0
	b.food, b.mana = b.stats.maxFood, b.stats.maxMana -- revive refills both (E04 §1-2)
	return nil
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

-- E04 §3-6: tower rush picks U4, U3, U2 on successive coin flips, else U1.
local function towerRushId(b: any): number
	local s = b.stage
	for _, i in { 4, 3, 2 } do
		if s["u" .. i] > 0 and Rng.rand(b.rng) % 2 == 0 then
			return s["u" .. i]
		end
	end
	return if s.u1 > 0 then s.u1 else s.u4
end

local function towerRush(b: any)
	if Rng.rand(b.rng) % 2 == 0 then
		for lane = 1, 5 do
			spawnEnemy(b, towerRushId(b), 0, NEAR_SPAWN_X, false, lane)
		end
	else
		for i = 0, 4 do
			spawnEnemy(b, towerRushId(b), 0, NEAR_SPAWN_X + 40 * i, false, Rng.rand(b.rng) % 5 + 1)
		end
	end
end

local function stepSpawner(b: any)
	local sp = b.spawn
	if b.mode == "Destiny" and sp.total >= DESTINY_SPAWNS then
		return -- destiny stops after 60 enemies (E04 §3-2)
	end
	if sp.need < 0 then
		sp.need = nextSpawnGap(b) -- StartStage draws the first gap before any enemy (E04 §3-1)
	end
	sp.timer += 1
	if sp.timer < sp.need * 30 - 1e-6 then
		return
	end
	local id, slot = pickEnemy(b)
	if id <= 0 then
		return -- empty band: retry next frame without resetting the timer (E04 §3-3)
	end
	local lane = if b.mode == "Tower" then Rng.rand(b.rng) % 5 + 1 else nil
	if not spawnEnemy(b, id, slot, nil, false, lane) then
		return
	end
	sp.created += 1
	sp.total += 1
	sp.fifth += 1
	local unitCount = b.stage.unitCount
	if b.mode == "Tower" and (sp.created == unitCount or sp.created == unitCount * 2) then
		towerRush(b)
	end
	if b.mode ~= "Destiny" and sp.created >= unitCount * 2 then
		sp.created = 0
	end
	sp.timer = 0
	sp.need = nextSpawnGap(b)
end

-- E04 §3-5: castle below 50% releases 10 giants one second apart: five of U3, then five of U2.
local function stepRush(b: any)
	local c = castle(b)
	local rush = b.rush
	if not c then
		return
	end
	if not rush.started then
		if alive(c) and c.hp < c.maxHp * 0.5 then
			rush.started, rush.left, rush.timer = true, 10, 30
		end
		return
	end
	if rush.left <= 0 then
		return
	end
	rush.timer += 1
	if rush.timer >= 30 then
		rush.timer = 0
		local id = if rush.left > 5 then b.stage.u3 else b.stage.u2
		spawnEnemy(b, id, 0, SCROLL_MAX, true)
		rush.left -= 1
	end
end

-- E04 §3-7: in boss stages the castle falling releases boss s/12 and knocks every ally back.
local function releaseBoss(b: any)
	local boss = spawnEnemy(b, 100 + b.stageNumber // 12, 0, SCROLL_MAX - 80)
	if not boss then
		return
	end
	b.bossId = boss.id
	for _, id in b.order do
		local c = b.entities[id]
		if c and c.kind == "Unit" and alive(c) then
			knockdown(c, 3)
		end
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
		b.summonPast[n] += 1
	end
end

-- E03 §5.1: allied units within the radius on the hero's line are in the aura; regen aura every 5 s.
-- Tower has no aura (E03 §5.1 exclusions).
local function updateAura(b: any)
	local h = hero(b)
	local radius = b.stats.auraRadius
	local inside = 0
	local enabled = b.mode ~= "Tower"
	for _, id in b.order do
		local e = b.entities[id]
		if e and e.kind == "Unit" then
			local was = e.aura
			e.aura = enabled
				and alive(e)
				and alive(h)
				and e.line == h.line
				and math.abs(h.x - e.x) <= radius
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
		local kind = command.kind
		if kind == "PickSkill" then
			reason = pickSkill(b, command.choice)
		elseif b.reviveOffer then
			if kind == "Revive" then
				reason = revive(b)
			elseif kind == "GiveUp" then
				b.reviveOffer = false
				b.outcome = "Defeat"
			else
				reason = "WrongPhase"
			end
		elseif #b.pendingPicks > 0 then
			reason = "WrongPhase" -- battle is paused for the level-up choice (D-LVUP-01)
		elseif kind == "Summon" then
			reason = summon(b, command.unit, command.lane)
		elseif kind == "Mace" then
			if b.mode == "Tower" then
				reason = towerButton(b, command.slot, command.unit, command.lane)
			else
				reason = useMace(b, command.slot)
			end
		elseif kind == "Box" then
			reason = openBox(b, command.index)
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
	local h = hero(b)
	if not alive(h) then
		if b.revivesLeft > 0 then
			b.reviveOffer, b.reviveWait = true, 0
			return
		end
		b.outcome = "Defeat"
		return
	end
	local mode = b.mode
	if mode == "Normal" then
		if not alive(castle(b)) then
			b.outcome = "Victory"
		end
	elseif mode == "Boss" then
		if b.bossId == 0 then
			if not alive(castle(b)) then
				releaseBoss(b)
			end
		elseif not alive(b.entities[b.bossId]) then
			b.outcome = "Victory"
		end
	elseif mode == "Destiny" then
		if b.rewards.killTotal >= DESTINY_KILLS then
			b.outcome = "Victory"
		end
	elseif mode == "Wagon" then
		local w = b.entities[b.wagonId]
		if not alive(w) then
			b.outcome = "Defeat"
		elseif w.x > WAGON_GOAL then
			b.outcome = "Victory"
		end
	elseif mode == "Tower" then
		if b.points >= TOWER_POINTS then
			b.outcome = "Victory"
		elseif b.points <= -TOWER_POINTS then
			b.outcome = "Defeat"
		end
	end
end

local function cleanup(b: any)
	local kept: { number } = {}
	for _, id in b.order do
		local e = b.entities[id]
		local keep = id == b.heroId or id == b.castleId or id == b.wagonId or id == b.bossId
		if e and (alive(e) or keep) then
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
	b.axis = if input and input.axis then math.sign(input.axis) else 0
	local results = runCommands(b, commands)
	if b.outcome then
		return { results = results, outcome = b.outcome }
	end
	if b.reviveOffer then
		b.reviveWait += 1
		if b.reviveWait >= REVIVE_WAIT_STEPS then
			b.reviveOffer = false
			b.outcome = "Defeat"
		end
		return { results = results, outcome = b.outcome, paused = true }
	end
	if #b.pendingPicks > 0 then
		prepareOffer(b)
		return { results = results, outcome = nil, paused = true }
	end
	b.tick += 1
	regen(b)
	stepSpawner(b)
	stepRush(b)
	stepBoxes(b)
	stepHero(b)
	updateAura(b)
	local snapshotOrder = table.clone(b.order)
	for _, id in snapshotOrder do
		local e = b.entities[id]
		if e then
			stepEntity(b, e)
		end
	end
	stepWagon(b)
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
			frog = e.frogTicks > 0,
			poisoned = e.poisonLeft > 0,
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
	local boxes = {}
	for i = 1, 9 do
		local box = b.boxes[i]
		boxes[i] = if box then box.kind .. ":" .. box.id else ""
	end
	return {
		tick = b.tick,
		mode = b.mode,
		food = b.food,
		mana = b.mana,
		maxFood = b.stats.maxFood,
		maxMana = b.stats.maxMana,
		summonPast = table.clone(b.summonPast),
		level = b.level,
		exp = b.expBase + b.exp,
		gold = b.rewards.gold,
		kills = b.rewards.killTotal,
		points = b.points,
		boxes = boxes,
		offer = if b.offer then table.clone(b.offer) else nil,
		reviveOffer = b.reviveOffer,
		outcome = b.outcome,
		entities = list,
		objects = objects,
	}
end

local function digest(b: any): string
	local parts = {
		string.format(
			"t%d|r%d|f%.17g|m%.17g|h%d|l%d|x%.17g|g%d,%d|k%d|o%s|s%d,%d,%d,%.17g,%.17g|u%s,%d,%.17g|p%d|v%s,%d,%d|b%.17g,%d,%d",
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
			b.rush.timer,
			b.points,
			tostring(b.reviveOffer),
			b.revivesLeft,
			b.bossId,
			b.boxTimer,
			b.auxFifth.mace,
			b.auxFifth.unit
		),
	}
	for n = 1, 9 do
		local box = b.boxes[n]
		table.insert(
			parts,
			string.format("%.17g/%s", b.summonPast[n], if box then box.kind .. box.id else "-")
		)
	end
	for _, id in b.order do
		local e = b.entities[id]
		table.insert(
			parts,
			string.format(
				"%d:%s%d:%.17g:%.17g/%.17g:%s:%d:%d:%.17g:%s:%s:%d:%d:%d",
				e.id,
				e.kind,
				e.n,
				e.x,
				e.hp,
				e.maxHp,
				e.state,
				e.stateTicks,
				e.stateLimit,
				e.attackPast,
				tostring(e.target),
				tostring(e.aura),
				e.poisonLeft,
				e.frogTicks,
				e.invulnTicks
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
	modeOf = modeOf,
	destinyLevel = destinyLevel,
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
