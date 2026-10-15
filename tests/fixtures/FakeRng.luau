--!strict
-- Scripted deterministic fake, not the future production combat PRNG.
return function(values: { number })
	local sequence = table.clone(values)
	local index = 0
	return {
		nextInteger = function(minimum: number, maximum: number): number
			index += 1
			local value = sequence[index]
			assert(value ~= nil, "fake RNG sequence exhausted")
			assert(
				value % 1 == 0 and value >= minimum and value <= maximum,
				"fake RNG out of range"
			)
			return value
		end,
	}
end
