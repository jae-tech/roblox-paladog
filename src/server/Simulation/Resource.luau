--!strict
-- Food/mana in milli units with per-tick integer regen and carried remainder (DATA_MODELS §1).
local SimTypes = require("./SimTypes")

local TICKS_PER_SECOND = 20

local function new(config: any, traits: { [string]: number }, traitConfig: any): SimTypes.Resources
	return {
		foodMilli = config.foodStartMilli,
		manaMilli = config.manaStartMilli,
		foodRemainder = 0,
		manaRemainder = 0,
		foodRateMilli = config.foodRegenMilliPerSec
			+ (traits.provisions or 0) * traitConfig.provisions.foodRegenMilliPerSecPerPoint,
		manaRateMilli = config.manaRegenMilliPerSec
			+ (traits.focus or 0) * traitConfig.focus.manaRegenMilliPerSecPerPoint,
		foodMaxMilli = config.foodMaxMilli,
		manaMaxMilli = config.manaMaxMilli,
		summonReadyTick = { 0, 0, 0 }, -- summon slots start ready; food starts at 0
		skillReadyTick = 0,
	}
end

-- n = rate + remainder; plus = floor(n / 20); remainder = n % 20; at the cap the remainder resets to 0.
local function regenOne(
	value: number,
	remainder: number,
	rate: number,
	max: number
): (number, number)
	if value >= max then
		return max, 0
	end
	local n = rate + remainder
	local plus = n // TICKS_PER_SECOND
	local nextValue = value + plus
	if nextValue >= max then
		return max, 0
	end
	return nextValue, n % TICKS_PER_SECOND
end

local function regen(resources: SimTypes.Resources)
	resources.foodMilli, resources.foodRemainder = regenOne(
		resources.foodMilli,
		resources.foodRemainder,
		resources.foodRateMilli,
		resources.foodMaxMilli
	)
	resources.manaMilli, resources.manaRemainder = regenOne(
		resources.manaMilli,
		resources.manaRemainder,
		resources.manaRateMilli,
		resources.manaMaxMilli
	)
end

return table.freeze({
	TICKS_PER_SECOND = TICKS_PER_SECOND,
	new = new,
	regen = regen,
	regenOne = regenOne,
})
