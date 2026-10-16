--!strict
-- Pure settlement of one battle into the profile (remake R3). Validates run identity and result ranges, then
-- applies gold/EXP/level-up picks, revive gems, drops, quest rewards, stars, unlocks and achievements in one
-- transform. Receipts and revision checks belong to ProfileService's surrounding transaction.
local ServerTypes = require("../ServerTypes")
local Schema = require("./ProfileSchema")
local Achievements = require("./Achievements")
local Economy = require("./Economy")
local Rng = require("../Battle/Rng")
local Db = require("../Config/Remake/Db")

type Profile = ServerTypes.ProfileV1
type Slot = ServerTypes.Slot
type Result = ServerTypes.MatchResult

local REVIVE_GEMS = 20 -- E04 §2-5

local function int(value: any, low: number, high: number): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= low
		and value <= high
end

-- D-DROP-01: a drop is a hero weapon or ring/amulet, grade within the chapter band; seeded per run.
local function dropItem(slot: Slot, stage: number, rng: Rng.Rng): number
	local light = slot.heroKind == "light"
	local weapon = Rng.rand(rng) % 2 == 0
	local category = if light
		then (if weapon then Schema.CATEGORY.mace else Schema.CATEGORY.ring)
		else (if weapon then Schema.CATEGORY.sword else Schema.CATEGORY.amulet)
	local num = Rng.rand(rng) % 10 + 1
	local chapter = math.max(1, (stage - 1) // 24 + 1)
	local grade = math.min((chapter - 1) * 2 + Rng.rand(rng) % 3, Schema.gradeLimit(slot))
	return Schema.encodeItem(category, num, grade)
end

-- Inventory full: the item is sold on the spot (D-DROP-02) so a reward is never silently lost.
local function giveItem(slot: Slot, code: number, items: { number })
	if #slot.inventory < Schema.INVENTORY_MAX then
		table.insert(slot.inventory, code)
		table.insert(items, code)
	else
		slot.gold = math.min(slot.gold + Economy.saleValue(code), Schema.GOLD_MAX)
	end
end

local function reduce(profile: Profile, result: Result): (Profile?, string?)
	if not Schema.validate(profile) then
		return nil, "StorageUnavailable"
	end
	local run = profile.activeRun
	if
		not run
		or run.matchId ~= result.matchId
		or run.ordinal ~= result.runOrdinal
		or run.slot ~= result.slot
		or run.stage ~= result.stage
		or run.balanceHash ~= result.balanceHash
		or profile.lastClosedRunOrdinal >= result.runOrdinal
	then
		return nil, "WrongPhase"
	end
	local outcome = result.outcome
	if
		(outcome ~= "Victory" and outcome ~= "Defeat" and outcome ~= "Abandoned")
		or not int(result.elapsedTicks, 0, 2 ^ 31)
		or not int(result.gold, 0, Schema.GOLD_MAX)
		or not int(result.goldSpent, 0, Schema.GOLD_MAX)
		or not int(result.exp, 0, 2 ^ 40)
		or not int(result.levelUps, 0, Schema.LEVEL_MAX)
		or not int(result.drops, 0, 10000)
		or not int(result.revives, 0, 1)
		or not int(result.killTotal, 0, 2 ^ 31)
		or type(result.picks) ~= "table"
		or #result.picks > result.levelUps
		or type(result.quests) ~= "table"
	then
		return nil, "InvalidPayload"
	end
	local nextProfile = Schema.deepClone(profile) :: Profile
	local slot = nextProfile.slots[result.slot] :: Slot
	if type(slot) ~= "table" then
		return nil, "InvalidPayload"
	end
	local stage = result.stage
	local abandoned = outcome == "Abandoned"
	local goldDelta, expGain = 0, 0
	local items: { number } = {}
	local stars = 0
	if not abandoned then
		-- Gold weapon spending can never exceed what the slot had plus what this battle earned.
		if result.goldSpent > slot.gold + result.gold then
			return nil, "InvalidPayload"
		end
		goldDelta = result.gold - result.goldSpent
		slot.gold = math.clamp(slot.gold + goldDelta, 0, Schema.GOLD_MAX)
		-- Level-ups found in battle must match the EXP curve; unchosen levels become free points.
		local oldLevel = slot.level
		slot.exp += result.exp
		expGain = result.exp
		slot.level = Schema.levelFor(slot.exp)
		if slot.level - oldLevel ~= result.levelUps then
			return nil, "InvalidPayload"
		end
		local caps = Schema.SKILL_MAX[slot.heroKind]
		for _, index in result.picks do
			if not int(index, 1, #caps) or slot.skills[index] >= caps[index] then
				return nil, "InvalidPayload"
			end
			slot.skills[index] += 1
		end
		slot.freePoints += result.levelUps - #result.picks
		if result.revives > 0 then
			if nextProfile.gems < REVIVE_GEMS * result.revives then
				return nil, "InvalidPayload"
			end
			nextProfile.gems -= REVIVE_GEMS * result.revives
		end
		local rng = Rng.new(result.seed + result.runOrdinal)
		for _ = 1, result.drops do
			giveItem(slot, dropItem(slot, stage, rng), items)
		end
		if outcome == "Victory" and stage >= 1 then
			local defs = (if slot.heroKind == "shadow" then Db.questsShadow else Db.quests)[stage]
			for i = 1, 3 do
				if result.quests[i] == true then
					stars += 1
					local def = defs[i]
					if def.gold > 0 then
						slot.gold = math.min(slot.gold + def.gold, Schema.GOLD_MAX) -- repeatable (E05 B10)
						goldDelta += def.gold
					elseif def.item.num > 0 then
						local category = Schema.CATEGORY[def.item.category]
						giveItem(
							slot,
							Schema.encodeItem(category, def.item.num, def.item.grade),
							items
						)
					end
				end
			end
			if stars < 1 then
				return nil, "InvalidPayload" -- a win always meets the main quest
			end
			slot.stars[stage] = math.max(slot.stars[stage], stars)
			slot.bestSec[stage] = if slot.bestSec[stage] > 0
				then math.min(slot.bestSec[stage], math.max(1, result.elapsedTicks // 30))
				else math.max(1, result.elapsedTicks // 30)
			if stage < Schema.STAGES and slot.stars[stage + 1] < 0 then
				slot.stars[stage + 1] = 0 -- next stage opens (E04 §5)
			end
		end
	end
	local gems = Achievements.evaluate(nextProfile, slot, {
		stage = stage,
		victory = outcome == "Victory",
		elapsedTicks = result.elapsedTicks,
		levelUps = result.levelUps,
		kills = result.killTotal,
	})
	nextProfile.lastClosedRunOrdinal = result.runOrdinal
	nextProfile.lastRunResult = {
		ordinal = result.runOrdinal,
		matchId = result.matchId,
		outcome = outcome :: string,
		awardedGold = goldDelta,
		awardedXp = expGain,
		stars = stars,
		items = items,
		gems = gems,
	}
	nextProfile.activeRun = nil
	return nextProfile, nil
end

return table.freeze({ reduce = reduce, dropItem = dropItem })
