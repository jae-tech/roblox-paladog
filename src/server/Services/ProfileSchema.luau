--!strict
-- Remake profile schema v2 (docs/REMAKE_PLAN.md R3, D-SLOT-01): account-wide gems/achievements/unlocks and
-- three save slots. Invalid profiles are reported, never clamped or overwritten.
-- Items are packed integers like the original bit-packed ids (E05 B8): category*100000 + num*1000 + grade.
local ServerTypes = require("../ServerTypes")
local Db = require("../Config/Remake/Db")

type Profile = ServerTypes.ProfileV1
type Slot = ServerTypes.Slot

local SCHEMA_VERSION = 2
local SLOT_COUNT = 3
local STAGES = 120
local GOLD_MAX = 999999999 -- E05 B0
local GEM_MAX = 99999
local LEVEL_MAX = 200 -- E03 §4.1
local INVENTORY_MAX = 100 -- E05 B8
local START_GOLD = 10000 -- new game bonus (E05 B0)
local ACHIEVEMENT_MAX = 40

-- Skill caps (E03 §4.2, §4.3).
local SKILL_MAX: { [string]: { number } } = {
	light = table.freeze({
		9,
		9,
		5,
		20,
		20,
		5,
		5,
		10,
		20,
		5,
		20,
		10,
		3,
		5,
		20,
		5,
		3,
		5,
		3,
		5,
		2,
		5,
		5,
	}),
	shadow = table.freeze({
		9,
		9,
		5,
		20,
		20,
		5,
		5,
		3,
		10,
		20,
		10,
		20,
		5,
		5,
		10,
		5,
		5,
		5,
		5,
		5,
		5,
		3,
		5,
		5,
	}),
}

-- Unit unlock prerequisites by code position (E05 B4): light 6 <- 4 and 5 <- 6; shadow is sequential.
local PREREQUISITE: { [string]: { number } } = {
	light = table.freeze({ 0, 1, 2, 3, 6, 4, 5, 7, 8 }),
	shadow = table.freeze({ 0, 1, 2, 3, 4, 5, 6, 7, 8 }),
}

-- Item categories and their numbers; equip slot -> category per hero kind (E03 §2.1).
local CATEGORY: { [string]: number } = {
	mace = 1,
	ring = 2,
	helmet = 3,
	armor = 4,
	horse = 5,
	sword = 6,
	amulet = 7,
	darkHelmet = 8,
	darkArmor = 9,
	darkFoot = 10,
}
local CATEGORY_NAME: { [number]: string } = {}
for name, index in CATEGORY do
	CATEGORY_NAME[index] = name
end
local CATEGORY_COUNT: { number } = table.freeze({ 11, 10, 10, 5, 5, 11, 10, 10, 5, 5 })
local SLOT_CATEGORY: { [string]: { number } } = {
	light = table.freeze({ 1, 1, 1, 2, 2, 2, 3, 4, 5 }),
	shadow = table.freeze({ 6, 6, 6, 7, 7, 7, 8, 9, 10 }),
}

local function isInt(value: any, low: number, high: number): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= low
		and value <= high
end

local function encodeItem(category: number, num: number, grade: number): number
	return category * 100000 + num * 1000 + grade
end

local function decodeItem(code: number): (number, number, number)
	return code // 100000, (code // 1000) % 100, code % 1000
end

local function validItem(code: any): boolean
	if not isInt(code, 100000, 1099999) then
		return false
	end
	local category, num, grade = decodeItem(code)
	return CATEGORY_COUNT[category] ~= nil
		and num >= 1
		and num <= CATEGORY_COUNT[category]
		and grade <= 100
end

-- Accumulated EXP needed to leave `level` is level^2 * 100 (E03 §4.1).
local function levelFor(exp: number): number
	local level = 1
	while level < LEVEL_MAX and exp >= level * level * 100 do
		level += 1
	end
	return level
end

-- Weapon/ring grade cap: 5 + 5 per cleared 12th stage, up to 50 (E03 §2.3).
local function gradeLimit(slot: Slot): number
	-- D-DIFF-01: a slot that finished a whole difficulty keeps the full cap after its stars reset
	if ((slot :: any).clearedDifficulty or 0) > 0 then
		return 50
	end
	local limit = 5
	for k = 1, 9 do
		if (slot.stars[k * 12] or -1) >= 1 then
			limit += 5
		end
	end
	return limit
end

local function newSlot(heroKind: string, difficulty: number): Slot
	local skills = table.create(#SKILL_MAX[heroKind], 0)
	local stars = table.create(STAGES, -1)
	stars[1] = 0
	local equip = table.create(9, 0)
	-- New game: unit 1 at level 1 and one default weapon equipped (E05 B0).
	equip[1] = encodeItem(if heroKind == "light" then CATEGORY.mace else CATEGORY.sword, 1, 0)
	local units = table.create(9, 0)
	units[1] = 1
	return {
		heroKind = heroKind,
		difficulty = difficulty,
		gold = START_GOLD,
		exp = 0,
		level = 1,
		skills = skills,
		freePoints = 0,
		units = units,
		stars = stars,
		bestSec = table.create(STAGES, 0),
		inventory = {},
		equip = equip,
		survivalBest = 0,
	}
end

local function newProfile(): Profile
	return {
		schemaVersion = SCHEMA_VERSION,
		revision = 0,
		gems = 0,
		achievements = {},
		darkUnlocked = false,
		ringSlotUnlocked = false,
		currentSlot = 0,
		slots = { false, false, false },
		runCounter = 0,
		lastClosedRunOrdinal = 0,
		fenceEpoch = 0,
		recentOperations = {},
	}
end

local function isArray(value: any, length: number?): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key in value do
		if type(key) ~= "number" then
			return false
		end
		count += 1
	end
	return #value == count and (length == nil or count == length)
end

local function validateSlot(slot: any): string?
	if type(slot) ~= "table" then
		return "slot"
	end
	local kind = slot.heroKind
	local caps = SKILL_MAX[kind]
	if not caps then
		return "heroKind"
	end
	if not isInt(slot.difficulty, 0, 3) or not isInt(slot.gold, 0, GOLD_MAX) then
		return "difficulty/gold"
	end
	if not isInt(slot.exp, 0, 2 ^ 40) or slot.level ~= levelFor(slot.exp) then
		return "level does not match exp"
	end
	if not isArray(slot.skills, #caps) or not isInt(slot.freePoints, 0, LEVEL_MAX) then
		return "skills"
	end
	local spent = 0
	for i, cap in caps do
		if not isInt(slot.skills[i], 0, cap) then
			return "skill " .. i
		end
		spent += slot.skills[i]
	end
	if spent + slot.freePoints ~= slot.level - 1 then
		return "skill points do not match level" -- one point per level-up (E03 §4.1)
	end
	if not isArray(slot.units, 9) then
		return "units"
	end
	for n = 1, 9 do
		local level = slot.units[n]
		local before = PREREQUISITE[kind][n]
		if not isInt(level, if n == 1 then 1 else 0, 20) then
			return "unit " .. n
		end
		if level > 0 and before > 0 and slot.units[before] < 1 then
			return "unit prerequisite " .. n
		end
	end
	if not isArray(slot.stars, STAGES) or not isArray(slot.bestSec, STAGES) then
		return "stars"
	end
	for s = 1, STAGES do
		local star, best = slot.stars[s], slot.bestSec[s]
		if not isInt(star, -1, 3) or not isInt(best, 0, 2 ^ 31) then
			return "stage " .. s
		end
		if (s == 1 and star < 0) or (s > 1 and star >= 0 and slot.stars[s - 1] < 1) then
			return "stage unlock " .. s -- a stage opens when the previous one is cleared (E04 §5)
		end
		if (star >= 1) ~= (best > 0) then
			return "stage best time " .. s
		end
	end
	if not isArray(slot.inventory) or #slot.inventory > INVENTORY_MAX then
		return "inventory"
	end
	for _, code in slot.inventory do
		if not validItem(code) then
			return "inventory item"
		end
	end
	if not isArray(slot.equip, 9) then
		return "equip"
	end
	for i = 1, 9 do
		local code = slot.equip[i]
		if code ~= 0 then
			if not validItem(code) or decodeItem(code) ~= SLOT_CATEGORY[kind][i] then
				return "equip slot " .. i
			end
		end
	end
	if not isInt(slot.survivalBest, 0, 2 ^ 31) then
		return "survivalBest"
	end
	-- optional (D-DIFF-01): difficulties fully cleared, counted as the highest cleared tier + 1
	local cleared = (slot :: any).clearedDifficulty
	if cleared ~= nil and not isInt(cleared, 0, 4) then
		return "clearedDifficulty"
	end
	return nil
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
	if not isInt(p.gems, 0, GEM_MAX) then
		return false, "gems"
	end
	if not isArray(p.achievements) or #p.achievements > ACHIEVEMENT_MAX + 1 then
		return false, "achievements"
	end
	local previous = -1
	for _, code in p.achievements do
		if not isInt(code, previous + 1, ACHIEVEMENT_MAX) then
			return false, "achievement order" -- unique and sorted
		end
		previous = code
	end
	if type(p.darkUnlocked) ~= "boolean" or type(p.ringSlotUnlocked) ~= "boolean" then
		return false, "unlock flags"
	end
	if not isArray(p.slots, SLOT_COUNT) or not isInt(p.currentSlot, 0, SLOT_COUNT) then
		return false, "slots"
	end
	for i = 1, SLOT_COUNT do
		local slot = p.slots[i]
		if slot ~= false then
			local problem = validateSlot(slot)
			if problem then
				return false, "slot " .. i .. ": " .. problem
			end
			if slot.heroKind == "shadow" and not p.darkUnlocked then
				return false, "shadow slot without unlock"
			end
		end
	end
	if p.currentSlot ~= 0 and p.slots[p.currentSlot] == false then
		return false, "currentSlot empty"
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
			or not isInt(run.slot, 1, SLOT_COUNT)
			or p.slots[run.slot] == false
			or not isInt(run.stage, 0, STAGES)
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
			or not isInt(last.awardedGold, -GOLD_MAX, GOLD_MAX)
			or not isInt(last.awardedXp, 0, 2 ^ 40)
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

local function currentSlot(profile: Profile): Slot?
	local slot = profile.slots[profile.currentSlot]
	return if type(slot) == "table" then slot :: Slot else nil
end

-- Battle loadout of a slot: equipment unpacked to {num, grade} per original slot (E03 §2.1).
local function loadoutOf(slot: Slot): any
	local equip = {}
	for i = 1, 9 do
		local code = slot.equip[i]
		if code ~= 0 then
			local _, num, grade = decodeItem(code)
			equip[i] = { num = num, grade = grade }
		end
	end
	return {
		heroKind = slot.heroKind,
		level = slot.level,
		exp = slot.exp,
		skills = table.clone(slot.skills),
		equip = equip,
		difficulty = slot.difficulty,
		unitLevels = table.clone(slot.units),
	}
end

-- Client view: everything except lease/receipts, plus derived caps.
local function summary(profile: Profile)
	local slots = {}
	for i = 1, SLOT_COUNT do
		local slot = profile.slots[i]
		if type(slot) == "table" then
			local view = deepClone(slot)
			view.gradeLimit = gradeLimit(slot :: Slot)
			view.nextLevelExp = if slot.level < LEVEL_MAX
				then slot.level * slot.level * 100
				else nil
			slots[i] = view
		else
			slots[i] = false
		end
	end
	return {
		gems = profile.gems,
		achievements = table.clone(profile.achievements),
		darkUnlocked = profile.darkUnlocked,
		ringSlotUnlocked = profile.ringSlotUnlocked,
		currentSlot = profile.currentSlot,
		slots = slots,
		lastRunResult = if profile.lastRunResult then deepClone(profile.lastRunResult) else nil,
	}
end

return table.freeze({
	SCHEMA_VERSION = SCHEMA_VERSION,
	SLOT_COUNT = SLOT_COUNT,
	STAGES = STAGES,
	GOLD_MAX = GOLD_MAX,
	GEM_MAX = GEM_MAX,
	LEVEL_MAX = LEVEL_MAX,
	INVENTORY_MAX = INVENTORY_MAX,
	SKILL_MAX = SKILL_MAX,
	PREREQUISITE = PREREQUISITE,
	CATEGORY = CATEGORY,
	CATEGORY_NAME = CATEGORY_NAME,
	CATEGORY_COUNT = CATEGORY_COUNT,
	SLOT_CATEGORY = SLOT_CATEGORY,
	encodeItem = encodeItem,
	decodeItem = decodeItem,
	validItem = validItem,
	levelFor = levelFor,
	gradeLimit = gradeLimit,
	newSlot = newSlot,
	newProfile = newProfile,
	validate = validate,
	validateSlot = validateSlot,
	deepClone = deepClone,
	currentSlot = currentSlot,
	loadoutOf = loadoutOf,
	summary = summary,
	unitRows = Db.units,
})
