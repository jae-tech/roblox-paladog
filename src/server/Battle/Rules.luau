--!strict
-- Light-hero formulas from the research specs (E03 §1-§5, E04 §1, E05 B6-B8), resolved once per battle
-- from the slot loadout. Values that depend on the live aura count stay as per-ally coefficients.
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

-- Sum of `a + b*g` over ring slots 4..6 holding ring `num`; ring grade adds ring mastery (skill 23).
local function ringSum(loadout: Loadout, num: number): number
	local total = 0
	for slot = 4, 6 do
		local item = loadout.equip[slot]
		if item and item.num == num then
			local row = Db.rings[num]
			total += row.a + row.b * (item.grade + skill(loadout, 23))
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

local function heroStats(loadout: Loadout): HeroStats
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

-- Accumulated EXP needed to leave `level` (E03 §4.1): level^2 * 100.
local function expForLevel(level: number): number
	return level * level * 100
end

return table.freeze({
	DIFFICULTY = DIFFICULTY,
	heroStats = heroStats,
	maceGrade = maceGrade,
	maceCost = maceCost,
	expForLevel = expForLevel,
	MAX_LEVEL = 200,
})
