--!strict
-- Shadow-hero rules (docs/REMAKE_PLAN.md R5): totems and the three hero skills (E05 B1/B5, E02 §4.5),
-- swords (E03 §3.2), enemy-debuff aura with thorns (E03 §5.4), dungeon traps and auto attack (E04 §1-1, §4),
-- and the siege horse (E04 §4). Engine internals arrive through `api`, so this module never requires Battle.
local Db = require("../Config/Remake/Db")
local Rng = require("./Rng")
local Rules = require("./Rules")

local DT = 1 / 30
local OBJECTS: { [string]: any } = Db.objects :: any
local SWORD_FRAMES, SWORD_EFFECT_FRAME = 15, 6 -- D-ANIM-03: shadow hero part animations were not parsed
local TRANSFORM_FRAMES = 30 -- D-SHADOW-01: one second transform pose, then the 30 s buff
local TRAP_OFFSET = 80 -- D-DUNGEON-02: traps land 80 px ahead of the hero
local SPIKE_OFFSETS = { 60, 120, 180 } -- D-SPIKE-01: three spikes ahead of the hero
local SKILL_TOTEMS = { [2] = true, [5] = true, [9] = true } -- shout, spike, transform (E05 B1)
local TRAP_BUTTONS = { [1] = 292, [4] = 293, [8] = 294 } -- dungeon buttons 1/4/8 (E04 §1-1)
local TRAP_CAP = 256 -- D-CAP-01 also bounds stationary objects.

local Shadow = {}

-- Rewards/kill bookkeeping live in Battle; totems behave like allied units in targeting.
function Shadow.spawnTotem(api: any, b: any, n: number): any
	local row = Db.totems[n]
	local level = math.clamp(b.loadout.unitLevels[n] or 1, 1, 20)
	local h = api.hero(b)
	local e = api.newEntity(b, "Totem", n, 1)
	e.hp, e.maxHp, e.ap = row.levels.hp[level], row.levels.hp[level], row.levels.ap[level]
	e.speed, e.attackDist, e.hitDist, e.attackDelay =
		row.moveSpeed * b.scale, row.attackDist, row.hitDist, row.attackDelay
	e.atkFrame = row.attackFrame
	e.atkAnim = math.max(row.attackFrame + 4, 10) -- D-ANIM-01
	e.skillAnim = e.atkAnim
	e.x = h.x + (row.spawnOffset or 0) -- totems appear relative to the hero (E02 §5)
	e.line = h.line
	e.y = api.depthY(b, row.createLine)
	e.lifetime = row.lifetime or 0
	e.hold = row.moveSpeed <= 0 -- every totem but the boar stands where it was placed
	return api.add(b, e)
end

local function shout(api: any, b: any, level: number)
	-- Knocks down up to AP(level) enemies within 150 px for HP(level)/100 seconds (E05 B5 totem 2).
	local row = Db.totems[2]
	local count = row.levels.ap[level]
	local seconds = row.levels.hp[level] / 100
	local h = api.hero(b)
	local hit = 0
	for _, id in b.order do
		local c = b.entities[id]
		if hit >= count then
			break
		end
		if c and c.team == 2 and api.targetable(c) and c.kind == "Enemy" and c.line == h.line then
			if math.abs(c.x - h.x) <= OBJECTS.r279.range + c.hitDist then
				api.knockdown(c)
				c.knockWaitTicks = math.floor(seconds * 30)
				hit += 1
			end
		end
	end
end

local function spike(api: any, b: any, level: number)
	-- Spikes for AP(level) damage each (E05 B5 totem 5); D-SPIKE-01 places three ahead of the hero.
	local damage = Db.totems[5].levels.ap[level]
	local h = api.hero(b)
	for _, offset in SPIKE_OFFSETS do
		api.area(b, h, h.x + offset, OBJECTS.r281.range, true, function(c)
			api.strike(b, h, c, damage, false, false)
		end)
	end
end

local function transform(api: any, b: any, level: number)
	-- AP/100 attack multiplier (3..6), HP/100 damage-taken multiplier (0.5..0.3), 30 s, speed x1.2
	-- (E05 B5 totem 9, E03 §1.3).
	local row = Db.totems[9]
	local h = api.hero(b)
	b.transformTicks = 30 * 30 + TRANSFORM_FRAMES
	b.transformAttack = row.levels.ap[level] / 100
	b.transformTaken = row.levels.hp[level] / 100
	api.enter(h, "Transform", TRANSFORM_FRAMES)
end

-- Summon button for the shadow hero: food + cooldown like units, but 2/5/9 are hero skills and dungeon
-- buttons 1/4/8 are traps paid with mana.
function Shadow.summon(api: any, b: any, n: number): string?
	local row = Db.totems[n]
	if not row or (b.loadout.unitLevels[n] or 0) < 1 then
		return "InvalidPayload"
	end
	local h = api.hero(b)
	if not api.alive(h) then
		return "Busy"
	end
	local trapRow = if b.mode == "Dungeon" then TRAP_BUTTONS[n] else nil
	if trapRow then
		local cost = OBJECTS["r" .. trapRow].mana
		if #b.traps >= TRAP_CAP then
			return "UnitCap"
		elseif b.mana < cost then
			return "InsufficientMana"
		end
		b.mana -= cost
		table.insert(b.traps, { row = trapRow, x = h.x + TRAP_OFFSET, line = h.line })
		return nil
	end
	if b.summonPast[n] < row.cooldown * 30 - 1e-6 then
		return "Cooldown"
	elseif b.food < row.cost then
		return "InsufficientFood"
	end
	if SKILL_TOTEMS[n] and (h.state == "Transform" or (n == 9 and b.transformTicks > 0)) then
		return "Busy"
	end
	if not SKILL_TOTEMS[n] and api.count(b, 1, true) >= 80 then
		return "UnitCap"
	end
	b.food -= row.cost
	b.summonPast[n] = 0
	b.rewards.summons[n] = (b.rewards.summons[n] or 0) + 1
	local level = math.clamp(b.loadout.unitLevels[n], 1, 20)
	if n == 2 then
		shout(api, b, level)
	elseif n == 5 then
		spike(api, b, level)
	elseif n == 9 then
		transform(api, b, level)
	else
		Shadow.spawnTotem(api, b, n)
	end
	return nil
end

-- Totem behaviour per kind (E02 §4.5): decay by lifetime, stationary turrets, the boar walks like a unit.
function Shadow.stepTotem(api: any, b: any, e: any): boolean
	if e.lifetime and e.lifetime > 0 then
		e.hp -= e.maxHp / e.lifetime * DT
		if e.hp <= 0 then
			api.kill(b, e, nil)
			return true
		end
	end
	local n = e.n
	if e.state == "Knock" or e.state == "KnockWait" or e.state == "Ice" or e.frogTicks > 0 then
		return false -- NPC control effects use the shared state machine, including stationary totems.
	end
	if n == 7 then
		-- eagle: shadows the hero 20 px behind, untargetable, dives at the nearest enemy every 3.5 s
		local h = api.hero(b)
		e.x = h.x - 20
		e.attackPast += 1
		if e.attackPast >= e.attackDelay * 30 then
			local target = api.nearestFront(b, e, e.attackDist)
			if target then
				e.attackPast = 0
				api.strike(b, e, target, e.ap, false, false)
			end
		end
		return true
	elseif n == 4 then
		-- whale: forced attack every fAtDly over everything in front (E02 §4.5)
		e.attackPast += 1
		if e.attackPast >= e.attackDelay * 30 then
			e.attackPast = 0
			api.area(b, e, e.x, e.attackDist, false, function(c)
				api.strike(b, e, c, e.ap, false, false)
			end)
		end
		return true
	elseif n == 6 then
		return true -- the bull only stands and absorbs hits (damage taken x0.5)
	end
	return false -- chicken (eggs), boar and salamander use the shared attack loop
end

-- Ranged totem releases at the attack frame.
function Shadow.release(api: any, b: any, e: any, target: any)
	if e.n == 1 then
		api.fire(b, e, 278, e.ap) -- eggs
	elseif e.n == 8 and target then
		api.lob(b, e, 275, target, e.ap, 30, 1, false, 0) -- D-TOTEM-08: a flame burst at the target
	elseif target and api.alive(target) then
		api.strike(b, e, target, e.ap, false, false)
	end
end

-- Enemy-debuff aura (E03 §5.1, §5.4): enemies (not castle/horse) on the hero's line within the radius.
function Shadow.updateAura(api: any, b: any)
	local h = api.hero(b)
	local radius = b.stats.auraRadius
	local inside = 0
	local live = api.alive(h) and b.mode ~= "Dungeon" and b.mode ~= "Jump"
	b.thornTicks += 1
	local thorns = b.thornTicks >= 30
	if thorns then
		b.thornTicks = 0
	end
	local hurt: { any } = {}
	for _, id in b.order do
		local e = b.entities[id]
		if e and e.team == 2 and (e.kind == "Enemy" or e.kind == "Boss") then
			e.aura = live and api.alive(e) and e.line == h.line and math.abs(h.x - e.x) <= radius
			if e.aura then
				inside += 1
				if thorns then
					table.insert(hurt, e)
				end
			end
		end
	end
	b.auraCount = inside
	-- thorns: (10 + 15 x Lv) every second, even at level 0 (E03 §5.3)
	for _, e in hurt do
		e.hp -= b.stats.thornDamage -- direct HP subtraction: no corrode/critical multiplier (E03 §5.3).
		if e.hp <= 0 then
			api.kill(b, e, h)
		end
	end
end

-- Sword attack damage with crit, berserk aura, armed boots and transform (E02 §2.4, E03 §3.2).
local function swordDamage(b: any, base: number): number
	local stats = b.stats
	local dmg = base
	if Rng.rand(b.rng) % 1000 <= stats.critPercent * 10 then
		dmg *= stats.critMul * stats.critFootMul
	end
	dmg *= (100 + stats.auraBerserkPer * b.auraCount) / 100
	dmg *= 1 + stats.armedFoot * b.auraCount
	if b.transformTicks > 0 then
		dmg *= b.transformAttack
	end
	return dmg
end

local function inFront(b: any, h: any, reach: number): { any }
	local list = {}
	for _, id in b.order do
		local c = b.entities[id]
		if
			c
			and c.team == 2
			and c.line == h.line
			and c.x > h.x
			and c.x - h.x <= c.hitDist + reach
		then
			if c.state ~= "Ghost" and c.state ~= "Blink" and c.state ~= "Dead" and c.hp > 0 then
				table.insert(list, c)
			end
		end
	end
	return list
end

function Shadow.swordEffect(api: any, b: any, sword: any)
	local h = api.hero(b)
	local num, g = sword.num, sword.grade
	local row = Db.swords[num]
	local base = row.a1 + row.b1 * g
	if num == 2 then
		api.fire(b, h, 282, swordDamage(b, base), { pierce = 3 + g // 20, aura = false, dir = 1 })
		return
	elseif num == 4 then
		api.fire(b, h, 283, 0, { poison = row.a1 + row.b1 * g, aura = false, dir = 1 })
		return
	elseif num == 10 then
		api.area(b, h, h.x, row.range, true, function(c)
			api.strike(b, h, c, swordDamage(b, base), false, false)
		end)
		return
	end
	local first = true
	for _, c in inFront(b, h, row.range) do
		local dmg = swordDamage(b, base)
		api.strike(b, h, c, dmg, false, false, num == 11)
		if api.alive(c) then
			if num == 1 and c.kind == "Enemy" then
				c.x += 4 -- dark slide
			elseif num == 5 and c.kind == "Enemy" and Rng.rand(b.rng) % 1000 < 200 then
				api.knockdown(c)
			elseif num == 7 and c.kind == "Enemy" then
				c.x = Rng.rand(b.rng) % (1024 - 160) -- dimension hammer (E03 §3.2)
			elseif num == 8 then
				api.freeze(c, row.a2)
			elseif num == 9 then
				c.burnTicks, c.burnLeft, c.burnDamage = 0, 4, dmg -- 4 burns 0.3 s apart
			end
		end
		if first then
			first = false
			if num == 3 then
				h.hp = math.min(h.hp + dmg * row.a2, h.maxHp) -- vampire: once per swing
			elseif num == 6 then
				b.food = math.min(b.food + dmg * row.a2, b.stats.maxFood) -- soul scythe
			end
		end
	end
end

function Shadow.useSword(api: any, b: any, slot: number): string?
	local h = api.hero(b)
	local item = b.loadout.equip[slot]
	if slot < 1 or slot > 3 or not item then
		return "InvalidPayload"
	elseif not api.alive(h) or h.state == "Transform" or b.swordTicks > 0 then
		return "Busy"
	end
	local grade = Rules.swordGrade(b.loadout, slot)
	local cost = Rules.swordCost(b.loadout, item.num, grade)
	if item.num == 11 then
		if (b.goldAvailable or 0) + b.rewards.gold - b.rewards.goldSpent < cost then
			return "InsufficientGold"
		end
		b.rewards.goldSpent += cost
	elseif b.mana < cost then
		return "InsufficientMana"
	else
		b.mana -= cost
	end
	b.rewards.maceUses[slot] = (b.rewards.maceUses[slot] or 0) + 1
	b.activeSword, b.swordTicks = { num = item.num, grade = grade }, SWORD_FRAMES
	return nil
end

-- Shadow hero frame: moves independently of attacks except while transforming (E03 §1.2).
function Shadow.stepHero(api: any, b: any)
	local h = api.hero(b)
	if b.transformTicks > 0 then
		b.transformTicks -= 1
	end
	if h.state == "Transform" then
		h.stateTicks += 1
		if h.stateTicks >= h.stateLimit then
			api.enter(h, "Idle")
		end
		return
	end
	if b.swordTicks > 0 then
		b.swordTicks -= 1
		if b.swordTicks == SWORD_FRAMES - SWORD_EFFECT_FRAME and b.activeSword then
			local sword = b.activeSword
			b.activeSword = nil
			Shadow.swordEffect(api, b, sword)
		end
	end
	if b.mode == "Dungeon" then
		-- auto dark sword every 0.5 s on a near enemy, free (E03 §1.5, D-DUNGEON-03)
		b.dungeonTicks += 1
		if
			b.dungeonTicks >= 15
			and b.swordTicks == 0
			and #inFront(b, h, Db.swords[1].range) > 0
		then
			b.dungeonTicks = 0
			b.activeSword, b.swordTicks =
				{ num = 1, grade = Rules.swordGrade(b.loadout, 0) }, SWORD_FRAMES
		end
		return
	end
	if b.axis ~= 0 then
		h.dir = b.axis
		local speed = b.stats.moveSpeed + b.stats.moveSpeedRing
		if b.transformTicks > 0 then
			speed *= 1.2
		end
		h.x = math.clamp(h.x + b.axis * speed * DT, -40, api.heroLimit(b))
		h.state = "Move"
	else
		h.state = "Idle"
	end
end

-- Burn ticks from the flame sword and the fire mine.
function Shadow.stepBurn(api: any, b: any, e: any)
	if (e.burnLeft or 0) <= 0 then
		return
	end
	e.burnTicks += 1
	if e.burnTicks >= 9 then
		e.burnTicks = 0
		e.burnLeft -= 1
		api.strike(b, api.hero(b), e, e.burnDamage, false, false)
	end
end

-- Dungeon traps trigger when an enemy steps on them (E04 §1-1; damage formula E02 §3.1).
function Shadow.stepTraps(api: any, b: any)
	local kept = {}
	local tier = (b.stageNumber - 9) // 12 + 1
	for _, trap in b.traps do
		local row = OBJECTS["r" .. trap.row]
		local victim = nil
		for _, id in b.order do
			local c = b.entities[id]
			if c and c.team == 2 and c.kind == "Enemy" and api.alive(c) and c.line == trap.line then
				if math.abs(c.x - trap.x) <= row.range + c.hitDist then
					victim = c
					break
				end
			end
		end
		if victim then
			local damage = row.attackPower + (row.perStage or 0) * tier
			if trap.row == 292 then
				api.knockdown(victim) -- banana peel: a slip
			elseif trap.row == 293 then
				local h = api.hero(b)
				api.area(b, h, trap.x, row.range, true, function(c)
					api.strike(b, h, c, damage, false, false)
				end)
			else
				victim.burnTicks, victim.burnLeft, victim.burnDamage = 0, 10, damage
			end
		else
			table.insert(kept, trap)
		end
	end
	b.traps = kept
end

-- Siege horse (E04 §4 shadow W): rolls left, every iSkDst seconds hits everything within reach.
function Shadow.stepHorse(api: any, b: any)
	local horse = b.entities[b.horseId]
	if not api.alive(horse) then
		return
	end
	horse.x -= horse.speed * DT
	horse.attackPast += 1
	if horse.attackPast >= Db.specials.woodenHorse.skillDist * 30 then
		horse.attackPast = 0
		api.area(b, horse, horse.x, horse.attackDist, false, function(c)
			api.strike(b, horse, c, horse.ap, false, false)
		end)
	end
end

-- Level-up candidates (E03 §4.1): shadow fixes farming, prayer and a rotation of weaken/storehouse/radius.
function Shadow.fixedCandidates(level: number): { number }
	return { 12, 10, ({ 17, 11, 22 })[(level // 5 - 1) % 3 + 1] }
end

return table.freeze(Shadow)
