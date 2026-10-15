--!strict
-- ProfileV1 creation, invariant validation and client summary (DATA_MODELS §5).
-- Invalid profiles are reported, never clamped or overwritten.
local ServerTypes = require("../ServerTypes")
local Units = require("../Config/Generated/Units")
local Stages = require("../Config/Generated/Stages")
local Generated = require("../Config/Generated/Progression")

type ProfileV1 = ServerTypes.ProfileV1

local progression = Generated.progression
local traitLimits: { [string]: { maxPoints: number } } = progression.traits :: any
local SCHEMA_VERSION = 1
local UNIT_IDS = { "bulwark", "slinger", "vanguard" }
local STAGE_IDS = { "s01", "s02", "s03" }
local TRAIT_IDS = { "focus", "provisions", "vitality" }

local function heroLevelFor(totalXp: number): number
	local level = 1
	while level < progression.heroLevelCap and totalXp >= progression.xpCurveBase * level * level do
		level += 1
	end
	return level
end

local function newProfile(): ProfileV1
	local unitLevels: { [string]: number } = {}
	for _, id in UNIT_IDS do
		unitLevels[id] = 1
	end
	local traits: { [string]: number } = {}
	for _, id in TRAIT_IDS do
		traits[id] = 0
	end
	local stageProgress: { [string]: { wins: number, bestTicks: number? } } = {}
	for _, id in STAGE_IDS do
		stageProgress[id] = { wins = 0 }
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		revision = 0,
		gold = progression.startGold,
		totalXp = 0,
		heroLevel = 1,
		unspentPoints = 0,
		heroTraits = traits,
		unitLevels = unitLevels,
		stageProgress = stageProgress,
		runCounter = 0,
		lastClosedRunOrdinal = 0,
		fenceEpoch = 0,
		recentOperations = {},
	}
end

local function isInt(value: any, low: number, high: number): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= low
		and value <= high
end

local function exactKeys(map: any, ids: { string }): boolean
	if type(map) ~= "table" then
		return false
	end
	local count = 0
	for _ in map do
		count += 1
	end
	for _, id in ids do
		if map[id] == nil then
			return false
		end
	end
	return count == #ids
end

local function isUnlocked(profile: ProfileV1, stageId: string): boolean
	local prerequisite = (Stages :: any)[stageId] and (Stages :: any)[stageId].prerequisiteId
	if (Stages :: any)[stageId] == nil then
		return false
	end
	return prerequisite == nil or profile.stageProgress[prerequisite].wins > 0
end

-- Returns (true) or (false, problem). "FutureSchema" is distinguished for diagnostics.
local function validate(value: any, receiptCap: number?): (boolean, string?)
	if type(value) ~= "table" then
		return false, "not a table"
	end
	local p = value
	if p.schemaVersion ~= SCHEMA_VERSION then
		return false,
			if isInt(p.schemaVersion, SCHEMA_VERSION + 1, math.huge)
				then "FutureSchema"
				else "schemaVersion"
	end
	if
		not (isInt(p.gold, 0, progression.goldMax) and isInt(p.totalXp, 0, progression.totalXpMax))
	then
		return false, "gold/totalXp range"
	end
	if p.heroLevel ~= heroLevelFor(p.totalXp) then
		return false, "heroLevel does not match totalXp"
	end
	if not (exactKeys(p.heroTraits, TRAIT_IDS) and exactKeys(p.unitLevels, UNIT_IDS)) then
		return false, "traits/unitLevels keys"
	end
	local spent = 0
	for _, id in TRAIT_IDS do
		local points = p.heroTraits[id]
		if not isInt(points, 0, traitLimits[id].maxPoints) then
			return false, "trait range " .. id
		end
		spent += points
	end
	if
		not isInt(p.unspentPoints, 0, progression.heroLevelCap)
		or spent + p.unspentPoints ~= p.heroLevel - 1
	then
		return false, "points do not match heroLevel"
	end
	for _, id in UNIT_IDS do
		if not isInt(p.unitLevels[id], 1, progression.unitMaxLevel) then
			return false, "unit level " .. id
		end
	end
	if not exactKeys(p.stageProgress, STAGE_IDS) then
		return false, "stageProgress keys"
	end
	for _, id in STAGE_IDS do
		local progress = p.stageProgress[id]
		local timeLimit = (Stages :: any)[id].timeLimitTicks
		if
			type(progress) ~= "table"
			or not isInt(progress.wins, 0, math.huge)
			or (progress.bestTicks ~= nil and not isInt(progress.bestTicks, 1, timeLimit))
			or (progress.wins > 0 and not isUnlocked(p, id))
		then
			return false, "stage progress " .. id
		end
	end
	if
		not isInt(p.revision, 0, math.huge)
		or not isInt(p.fenceEpoch, 0, math.huge)
		or not isInt(p.runCounter, 0, math.huge)
		or not isInt(p.lastClosedRunOrdinal, 0, p.runCounter)
	then
		return false, "revision/epoch/run counters"
	end
	local run = p.activeRun
	if
		run ~= nil
		and (
			type(run) ~= "table"
			or run.ordinal ~= p.runCounter
			or run.ordinal <= p.lastClosedRunOrdinal
			or type(run.matchId) ~= "string"
			or type(run.stageId) ~= "string"
			or (Stages :: any)[run.stageId] == nil
			or type(run.balanceHash) ~= "string"
			or type(run.startOperationId) ~= "string"
		)
	then
		return false, "activeRun"
	end
	local last = p.lastRunResult
	if
		last ~= nil
		and (
			type(last) ~= "table"
			or not isInt(last.ordinal, 1, p.lastClosedRunOrdinal)
			or type(last.matchId) ~= "string"
			or type(last.outcome) ~= "string"
			or not isInt(last.awardedGold, 0, progression.goldMax)
			or not isInt(last.awardedXp, 0, progression.totalXpMax)
		)
	then
		return false, "lastRunResult"
	end
	local lease = p.lease
	if
		lease ~= nil
		and (
			type(lease) ~= "table"
			or type(lease.sessionId) ~= "string"
			or type(lease.expiresAt) ~= "number"
		)
	then
		return false, "lease"
	end
	if type(p.recentOperations) ~= "table" or #p.recentOperations > (receiptCap or 64) then
		return false, "recentOperations"
	end
	for _, receipt in p.recentOperations do
		if
			type(receipt) ~= "table"
			or type(receipt.id) ~= "string"
			or type(receipt.kind) ~= "string"
			or not isInt(receipt.revision, 1, p.revision)
		then
			return false, "receipt"
		end
	end
	return true, nil
end

local function upgradeCost(unitId: string, currentLevel: number): number?
	local unit = (Units :: any)[unitId]
	local nextLevel = unit and unit.levels[currentLevel + 1]
	return nextLevel and nextLevel.purchaseCostGold
end

local function summary(profile: ProfileV1)
	local stageProgress = {}
	local unlockedStages: { [string]: boolean } = {}
	local unitUpgradeCosts: { [string]: number } = {}
	for _, id in STAGE_IDS do
		stageProgress[id] = {
			wins = profile.stageProgress[id].wins,
			bestTicks = profile.stageProgress[id].bestTicks,
		}
		unlockedStages[id] = isUnlocked(profile, id)
	end
	for _, id in UNIT_IDS do
		local cost = upgradeCost(id, profile.unitLevels[id])
		if cost then
			unitUpgradeCosts[id] = cost
		end
	end
	return {
		gold = profile.gold,
		totalXp = profile.totalXp,
		heroLevel = profile.heroLevel,
		unspentPoints = profile.unspentPoints,
		heroTraits = table.clone(profile.heroTraits),
		unitLevels = table.clone(profile.unitLevels),
		stageProgress = stageProgress,
		unlockedStages = unlockedStages,
		unitUpgradeCosts = unitUpgradeCosts,
		nextLevelXp = if profile.heroLevel < progression.heroLevelCap
			then progression.xpCurveBase * profile.heroLevel * profile.heroLevel
			else nil,
		lastRunResult = if profile.lastRunResult then table.clone(profile.lastRunResult) else nil,
	}
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepClone(item)
	end
	return copy
end

return table.freeze({
	SCHEMA_VERSION = SCHEMA_VERSION,
	UNIT_IDS = UNIT_IDS,
	STAGE_IDS = STAGE_IDS,
	TRAIT_IDS = TRAIT_IDS,
	newProfile = newProfile,
	validate = validate,
	summary = summary,
	isUnlocked = isUnlocked,
	heroLevelFor = heroLevelFor,
	deepClone = deepClone,
	upgradeCost = upgradeCost,
	maxTraitPoints = function(traitId: string): number
		return traitLimits[traitId].maxPoints
	end,
	unitMaxLevel = progression.unitMaxLevel,
})
