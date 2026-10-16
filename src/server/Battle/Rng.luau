--!strict
-- Deterministic xorshift32 standing in for the original `rand()`. All draws in a battle come from
-- one generator, so equal seeds and commands replay to equal digests.
export type Rng = { state: number }

local function new(seed: number): Rng
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	return { state = if state == 0 then 0x9E3779B9 else state }
end

-- 0..2^31-1, like C rand(); callers use `% n` exactly as the original code does.
local function rand(rng: Rng): number
	local x = rng.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	rng.state = x
	return bit32.rshift(x, 1)
end

return table.freeze({ new = new, rand = rand })
