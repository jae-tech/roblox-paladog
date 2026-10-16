--!strict
-- Hero formulas from the research specs (E03 §1-§5, E04 §1, E05 B6-B8), resolved once per battle from the
-- slot loadout. Light hero (aura buffs allies) and shadow hero (aura debuffs enemies, crit/evade). Values
-- that depend on the live aura count stay as per-target coefficients.
local Db = require("../Config/Remake/Db")

export type EquipItem = { num: number, grade: number }
-- equip[1..3] weapons, [4..6] rings, [7] helmet, [8] armor, [9] horse (original slots 0..8).
export type Loadout = {
	heroKind: string,
	level: number,
	exp: number,
	skills: { number },
	equip: { [number]: EquipItem },
	difficulty: number,
	unitLevels: { number },
}

export type HeroStats = {
	maxHp: number,
	maxMana: number,
	maxFood: number,
	manaPerTenth: number,
	manaVigorBase: number,
	foodPerTenth: number,
	manaPerTenthPerAura: number,
	foodPerTenthPerAura: number,
	hpRegen5: number,
	moveSpeed: number,
	moveSpeedRing: number,
	damageTakenMul: number,
	summonCooldownMul: number,
	auraRadius: number,
	auraMove: number,
	auraWar: number,
	auraDefense: number,
	auraEnergy: number,
	auraSkill: number,
	auraRegen: number,
	berserker: number,
	maceCostMul: number,
	goldBonus: number,
	expBonus: number,
	dropPercent: number,
	armedHorse: number,
	onHeroHitMana: number,
	onHeroHitFood: number,
	onAllyDeathMana: number,
	onAllyDeathFood: number,
	onAllyDeathHeroHp: number,
	reflect: number,
	-- shadow hero only (zero/neutral for the light hero)
	evadePercent: number,
	critPercent: number,
	critMul: number,
	critFootMul: number,
	auraCorrode: number,
	auraWeaken: number,
	auraHinder: number,
	auraBerserkPer: number,
	auraVigorPer: number,
	thornDamage: number,
	armedFoot: number,
}

-- E04 §2-2 / E05 B6 difficulty table: enemy HP (units and castle), kill gold, kill EXP.
local DIFFICULTY = table.freeze({
	[0] = table.freeze({ hp = 0.7, gold = 2.0, exp = 1.5 }),
	[1] = table.freeze({ hp = 1.0, gold = 1.0, exp = 1.0 }),
	[2] = table.freeze({ hp = 1.4, gold = 0.8, exp = 0.5 }),
	[3] = table.freeze({ hp = 1.0, gold = 0.6, exp = 0.4 }), -- hell keeps HP x1.0 (switch default, E04 §2-2)
})

local function skill(loadout: Loadout, index: number): number
	return loadout.skills[index] or 0
end

-- Sum of `a + b*g` over ring slots 4..6 holding ring `num`; ring grade adds ring mastery (skill 23);
-- the shadow hero's amulets use amulet mastery (skill 24).
local function ringSum(loadout: Loadout, num: number): number
	local total = 0
	local shadow = loadout.heroKind == "shadow"
	local rows = if shadow then Db.amulets else Db.rings
	local mastery = skill(loadout, if shadow then 24 else 23)
	for slot = 4, 6 do
		local item = loadout.equip[slot]
		if item and item.num == num then
			local row = rows[num]
			total += row.a + row.b * (item.grade + mastery)
		end
	end
	return total
end

local function gear(loadout: Loadout, slot: number, num: number, rows: { any }): number
	local item = loadout.equip[slot]
	if not item or item.num ~= num then
		return 0
	end
	local row = rows[num]
	return row.a + row.b * item.grade
end

local shadowStats: (Loadout) -> HeroStats

local function heroStats(loadout: Loadout): HeroStats
	if loadout.heroKind == "shadow" then
		return shadowStats(loadout)
	end
	local function sk(i: number): number
		return skill(loadout, i)
	end
	local horse2 = loadout.equip[9]
	local guardHorse = if horse2 and horse2.num == 2
		then Db.horses[2].a - Db.horses[2].b * horse2.grade -- subtractive (E03 §2.6)
		else 1
	return {
		maxHp = 2000 + 1000 * sk(4) + ringSum(loadout, 4) + gear(loadout, 8, 2, Db.armors),
		maxMana = 100 + 50 * sk(8) + ringSum(loadout, 7) + gear(loadout, 8, 3, Db.armors),
		maxFood = 40 + 40 * sk(12) + ringSum(loadout, 10) + gear(loadout, 7, 8, Db.helmets),
		manaVigorBase = 0,
		manaPerTenth = Db.regen.light.fSkPct
			+ loadout.level * Db.regen.light.fSkKnd
			+ sk(9) * Db.regen.light.fSdwSc
			+ ringSum(loadout, 8)
			+ gear(loadout, 7, 3, Db.helmets),
		foodPerTenth = Db.regen.light.fBigSc
			+ loadout.level * Db.regen.light.fBigSt
			+ sk(11) * Db.regen.light.fZmESt
			+ ringSum(loadout, 9)
			+ gear(loadout, 7, 9, Db.helmets),
		manaPerTenthPerAura = gear(loadout, 8, 1, Db.armors),
		foodPerTenthPerAura = gear(loadout, 7, 1, Db.helmets),
		hpRegen5 = Db.regen.light.fAtDly * loadout.level + sk(5) * Db.regen.light.fSkDmg + ringSum(
			loadout,
			5
		) + gear(loadout, 7, 2, Db.helmets),
		moveSpeed = 60 + 20 * sk(6),
		moveSpeedRing = ringSum(loadout, 6),
		damageTakenMul = (1 - 0.1 * sk(7)) * guardHorse,
		summonCooldownMul = (6 - sk(13)) / 6,
		auraRadius = 75 + 25 * sk(19),
		auraMove = 1.5 + 0.5 * sk(14),
		auraWar = 1 + 0.3 * sk(15),
		auraDefense = 1 - 0.1 * sk(16),
		auraEnergy = (5 - sk(17)) / 5,
		auraSkill = 1 + 0.4 * sk(18),
		auraRegen = 0.04 * sk(20) + gear(loadout, 9, 3, Db.horses),
		berserker = 1 + 1.0 * sk(21),
		maceCostMul = 1 - 0.1 * sk(10),
		goldBonus = 0.2 * sk(2) + ringSum(loadout, 2) / 100 + gear(loadout, 7, 7, Db.helmets) / 100,
		expBonus = 0.2 * sk(1) + ringSum(loadout, 1) / 100 + gear(loadout, 7, 10, Db.helmets) / 100,
		-- Luck ring is divided by 100 before joining a percent value: kept as in the original (E03 §2.5).
		dropPercent = 1 + 0.5 * sk(3) + ringSum(loadout, 3) / 100 + gear(loadout, 7, 6, Db.helmets),
		armedHorse = gear(loadout, 9, 1, Db.horses),
		onHeroHitMana = gear(loadout, 7, 4, Db.helmets),
		onHeroHitFood = gear(loadout, 8, 4, Db.armors),
		onAllyDeathMana = gear(loadout, 7, 5, Db.helmets),
		onAllyDeathFood = gear(loadout, 8, 5, Db.armors),
		onAllyDeathHeroHp = gear(loadout, 9, 5, Db.horses),
		reflect = gear(loadout, 9, 4, Db.horses),
		evadePercent = 0,
		critPercent = 0,
		critMul = 1,
		critFootMul = 1,
		auraCorrode = 1,
		auraWeaken = 1,
		auraHinder = 1,
		auraBerserkPer = 0,
		auraVigorPer = 0,
		thornDamage = 0,
		armedFoot = 0,
	}
end

-- Shadow hero (E03 §1.6, §1.8, §2.6, §4.3, §5.4; values row #6 "skill values (shadow)" and #5 regen).
shadowStats = function(loadout: Loadout): HeroStats
	local function sk(i: number): number
		return skill(loadout, i)
	end
	local v = Db.shadowSkillValues
	local r = Db.regen.shadow
	local hero = Db.specials.shadowHero
	local foot2 = loadout.equip[9]
	local guardFoot = if foot2 and foot2.num == 2
		then Db.darkFeet[2].a - Db.darkFeet[2].b * foot2.grade
		else 1
	local foot5 = loadout.equip[9]
	return {
		maxHp = hero.hp
			+ v.iMaxHP * sk(4)
			+ ringSum(loadout, 4)
			+ gear(loadout, 8, 2, Db.darkArmors),
		maxMana = hero.cost
			+ hero.cooldown * sk(9)
			+ ringSum(loadout, 7)
			+ gear(loadout, 8, 4, Db.darkArmors),
		maxFood = 40 + 40 * sk(11) + ringSum(loadout, 10) + gear(loadout, 7, 8, Db.darkHelmets),
		manaVigorBase = r.fSkPct + loadout.level * r.fSkKnd + sk(10) * r.fSdwSc,
		manaPerTenth = r.fSkPct + loadout.level * r.fSkKnd + sk(10) * r.fSdwSc + ringSum(
			loadout,
			8
		) + gear(loadout, 7, 4, Db.darkHelmets),
		foodPerTenth = r.fBigSc + loadout.level * r.fBigSt + sk(12) * r.fZmESt + ringSum(
			loadout,
			9
		) + gear(loadout, 7, 9, Db.darkHelmets),
		manaPerTenthPerAura = gear(loadout, 8, 1, Db.darkArmors), -- per enemy inside the aura
		foodPerTenthPerAura = gear(loadout, 7, 1, Db.darkHelmets),
		hpRegen5 = r.fAtDly
			+ sk(5) * r.fSkDmg
			+ ringSum(loadout, 5)
			+ gear(loadout, 7, 2, Db.darkHelmets),
		moveSpeed = 80 + 20 * sk(6),
		moveSpeedRing = ringSum(loadout, 6),
		damageTakenMul = (1 - 0.1 * sk(7)) * guardFoot,
		summonCooldownMul = 1, -- only the light hero's leadership shortens summons (E02 §5)
		auraRadius = 110 + 33 * sk(22),
		auraMove = 1,
		auraWar = 1,
		auraDefense = 1,
		auraEnergy = 1,
		auraSkill = 1,
		auraRegen = 0,
		berserker = 1,
		maceCostMul = 1 - 0.1 * sk(8),
		goldBonus = 0.2 * sk(2)
			+ ringSum(loadout, 2) / 100
			+ gear(loadout, 7, 7, Db.darkHelmets) / 100,
		expBonus = 0.2 * sk(1)
			+ ringSum(loadout, 1) / 100
			+ gear(loadout, 7, 10, Db.darkHelmets) / 100,
		dropPercent = 1
			+ 0.5 * sk(3)
			+ ringSum(loadout, 3) / 100
			+ gear(loadout, 7, 6, Db.darkHelmets),
		armedHorse = 0,
		onHeroHitMana = gear(loadout, 7, 3, Db.darkHelmets),
		onHeroHitFood = gear(loadout, 8, 3, Db.darkArmors),
		onAllyDeathMana = 0,
		onAllyDeathFood = 0,
		onAllyDeathHeroHp = 0,
		reflect = gear(loadout, 9, 3, Db.darkFeet),
		evadePercent = v.iMvSpd * sk(13) + gear(loadout, 8, 5, Db.darkArmors),
		critPercent = v.iCltm_ + v.iAtDst * sk(14) + gear(loadout, 7, 5, Db.darkHelmets),
		critMul = v.fAtDly + v.fSkDmg * sk(15),
		critFootMul = if foot5 and foot5.num == 5
			then Db.darkFeet[5].a + Db.darkFeet[5].b * foot5.grade
			else 1,
		auraCorrode = 1 + v.fSkPct * sk(16),
		auraWeaken = 1 - v.fSkKnd * sk(17),
		auraHinder = v.fSdwSc - v.fBigSc * sk(18),
		auraBerserkPer = v.iHtDst * sk(19),
		auraVigorPer = v.iTgDst * sk(20),
		thornDamage = v.iAtPwr + v.fZmESt * sk(21) + gear(loadout, 9, 4, Db.darkFeet),
		armedFoot = gear(loadout, 9, 1, Db.darkFeet),
	}
end

-- Mace effective grade adds mace mastery (skill 22) except in destiny stages (E03 §2.2).
local function maceGrade(loadout: Loadout, slot: number, destiny: boolean): number
	local item = loadout.equip[slot]
	if not item then
		return 0
	end
	return item.grade + (if destiny then 0 else skill(loadout, 22))
end

-- Mana cost (E03 §3.1): int((A3 + B3*g) * (1 - 0.1*magic master)); gold weapon is a fixed gold price.
local function maceCost(loadout: Loadout, num: number, grade: number): number
	local row = Db.maces[num]
	if num == 11 then
		return row.manaA
	end
	return math.floor((row.manaA + row.manaB * grade) * (1 - 0.1 * skill(loadout, 10)))
end

-- Sword effective grade adds weapon mastery (skill 23); cost x (1 - 0.1 * dexterity) (E03 §3.2).
local function swordGrade(loadout: Loadout, slot: number): number
	local item = loadout.equip[slot]
	return if item then item.grade + skill(loadout, 23) else 0
end

local function swordCost(loadout: Loadout, num: number, grade: number): number
	local row = Db.swords[num]
	if num == 11 then
		return row.manaA
	end
	return math.floor((row.manaA + row.manaB * grade) * (1 - 0.1 * skill(loadout, 8)))
end

-- Accumulated EXP needed to leave `level` (E03 §4.1): level^2 * 100.
local function expForLevel(level: number): number
	return level * level * 100
end

return table.freeze({
	DIFFICULTY = DIFFICULTY,
	heroStats = heroStats,
	maceGrade = maceGrade,
	maceCost = maceCost,
	swordGrade = swordGrade,
	swordCost = swordCost,
	expForLevel = expForLevel,
	MAX_LEVEL = 200,
})
