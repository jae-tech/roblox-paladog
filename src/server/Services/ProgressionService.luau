--!strict
-- Deterministic growth transforms on a caller-owned profile copy. No storage, engine or clocks.
local Types = require("../ServerTypes")
local Schema = require("./ProfileSchema")
local Config = require("../Config/Generated/Progression").progression

local function award(profile: Types.ProfileV1, gold: number, xp: number): (number, number)
	assert(gold >= 0 and gold % 1 == 0 and gold < math.huge, "invalid gold delta")
	assert(xp >= 0 and xp % 1 == 0 and xp < math.huge, "invalid XP delta")
	local oldGold, oldXp, oldLevel = profile.gold, profile.totalXp, profile.heroLevel
	profile.gold = math.min(Config.goldMax, oldGold + gold)
	profile.totalXp = math.min(Config.totalXpMax, oldXp + xp)
	profile.heroLevel = Schema.heroLevelFor(profile.totalXp)
	profile.unspentPoints += profile.heroLevel - oldLevel
	return profile.gold - oldGold, profile.totalXp - oldXp
end

local function upgradeUnit(profile: Types.ProfileV1, unitId: string): string?
	local level = profile.unitLevels[unitId]
	if profile.activeRun then
		return "WrongPhase"
	elseif not level then
		return "InvalidPayload"
	end
	local cost = Schema.upgradeCost(unitId, level)
	if level >= Schema.unitMaxLevel or cost == nil then
		return "MaxLevel"
	elseif profile.gold < cost then
		return "InsufficientGold"
	end
	profile.gold -= cost
	profile.unitLevels[unitId] = level + 1
	return nil
end

local function allocatePoint(profile: Types.ProfileV1, traitId: string): string?
	local points = profile.heroTraits[traitId]
	if profile.activeRun then
		return "WrongPhase"
	elseif points == nil then
		return "InvalidPayload"
	elseif profile.unspentPoints < 1 then
		return "NoPoints"
	elseif points >= Schema.maxTraitPoints(traitId) then
		return "MaxLevel"
	end
	profile.unspentPoints -= 1
	profile.heroTraits[traitId] = points + 1
	return nil
end

return table.freeze({ award = award, upgradeUnit = upgradeUnit, allocatePoint = allocatePoint })
