--!strict
return function(initialTick: number?)
	local tick = initialTick or 0
	assert(tick >= 0 and tick % 1 == 0, "initial tick must be a nonnegative integer")
	return {
		now = function(): number
			return tick
		end,
		stepTicks = function(count: number)
			assert(count >= 0 and count < math.huge and count % 1 == 0, "invalid tick count")
			tick += count
		end,
	}
end
