--!strict
-- Pure settlement: validates server result identity/kill ledger and returns a new profile.
-- Operation receipts and revision checks belong to ProfileService's surrounding transaction.
local Types = require("../ServerTypes")
local Schema = require("../Services/ProfileSchema")
local Growth = require("../Services/ProgressionService")
local Stages = require("../Config/Generated/Stages")
local Enemies = require("../Config/Generated/Enemies")

local function nonnegativeInteger(value: number): boolean
	return value >= 0 and value % 1 == 0 and value <= 2147483647
end

local function reduce(
	profile: Types.ProfileV1,
	result: Types.MatchResult
): (Types.ProfileV1?, string?)
	if not Schema.validate(profile) then
		return nil, "StorageUnavailable"
	end
	local run = profile.activeRun
	if
		not run
		or run.matchId ~= result.matchId
		or run.ordinal ~= result.runOrdinal
		or run.stageId ~= result.stageId
		or run.balanceHash ~= result.balanceHash
		or profile.lastClosedRunOrdinal >= result.runOrdinal
	then
		return nil, "WrongPhase"
	end
	local stage = (Stages :: any)[result.stageId]
	if
		not stage
		or not nonnegativeInteger(result.elapsedTicks)
		or result.elapsedTicks < 1
		or result.elapsedTicks > stage.timeLimitTicks
		or (
			result.outcome ~= "Victory"
			and result.outcome ~= "Defeat"
			and result.outcome ~= "Timeout"
			and result.outcome ~= "Abandoned"
		)
	then
		return nil, "InvalidPayload"
	end
	local killGold, killXp = 0, 0
	for id, count in result.killCounts do
		local enemy = (Enemies :: any)[id]
		if not enemy or not nonnegativeInteger(count) then
			return nil, "InvalidPayload"
		end
		killGold += count * enemy.killGold
		killXp += count * enemy.killXp
	end
	if killGold ~= result.pendingKillGold or killXp ~= result.pendingKillXp then
		return nil, "InvalidPayload"
	end
	local nextProfile = Schema.deepClone(profile) :: Types.ProfileV1
	local gold, xp = 0, 0
	if result.outcome == "Victory" then
		local progress = nextProfile.stageProgress[result.stageId]
		gold, xp = Growth.award(
			nextProfile,
			killGold + stage.winGold + (if progress.wins == 0 then stage.firstWinGold else 0),
			killXp + stage.winXp
		)
		progress.wins += 1
		progress.bestTicks =
			math.min(progress.bestTicks or result.elapsedTicks, result.elapsedTicks)
	end
	nextProfile.lastClosedRunOrdinal = result.runOrdinal
	nextProfile.lastRunResult = {
		ordinal = result.runOrdinal,
		matchId = result.matchId,
		outcome = result.outcome :: string,
		awardedGold = gold,
		awardedXp = xp,
	}
	nextProfile.activeRun = nil
	return nextProfile, nil
end

return table.freeze({ reduce = reduce })
