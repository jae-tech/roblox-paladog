--!strict
-- Server-seeded xorshift32. Combat RNG never depends on wall time, rendering or global math.random.
local SimTypes = require("./SimTypes")
type State = SimTypes.SpawnState

local function randomInt(state: State, low: number, high: number): number
	local value = state.rngState
	value = bit32.bxor(value, bit32.lshift(value, 13))
	value = bit32.bxor(value, bit32.rshift(value, 17))
	value = bit32.bxor(value, bit32.lshift(value, 5))
	state.rngState = value
	return low + value % (high - low + 1)
end

local function interval(state: State, config: any): number
	local slow = state.successfulSpawnCount % (2 * config.blockCount) < config.blockCount
	return if slow
		then randomInt(state, config.slowMinTicks, config.slowMaxTicks)
		else randomInt(state, config.fastMinTicks, config.fastMaxTicks)
end

local function new(config: any, seed: number): State
	assert(seed % 1 == 0 and seed >= 1 and seed <= 4294967295, "invalid stage seed")
	local state: State =
		{ seed = seed, rngState = seed, successfulSpawnCount = 0, nextSpawnTicks = 0 }
	state.nextSpawnTicks = interval(state, config)
	return state
end

local function chooseEnemy(config: any, roll: number): string
	assert(roll % 1 == 0 and roll >= 0 and roll < 100, "invalid enemy roll")
	local cumulative = 0
	for _, choice in config.choices do
		cumulative += choice.weight
		if roll < cumulative then
			return choice.enemyId
		end
	end
	error("stage weights must total 100")
end

-- Exactly one potential spawn per tick. At the cap both timer and PRNG state freeze.
local function step(state: State, config: any, atCap: boolean): string?
	if atCap then
		return nil
	end
	state.nextSpawnTicks -= 1
	if state.nextSpawnTicks > 0 then
		return nil
	end
	local id = chooseEnemy(config, randomInt(state, 0, 99))
	state.successfulSpawnCount += 1
	state.nextSpawnTicks = interval(state, config)
	return id
end

return table.freeze({ new = new, step = step, chooseEnemy = chooseEnemy })
