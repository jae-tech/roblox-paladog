--!strict
-- Offline UpdateAsync/uncached-read driver. Fault controls never enter the production tree.
local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = clone(child)
	end
	return copy
end

return function(): any
	local records: { [string]: any } = {}
	local fake: any = {
		wall = 1000,
		time = 0,
		hasBudget = true,
		repeats = 1,
		failBefore = 0,
		failAfter = 0,
		calls = 0,
		writes = 0,
		callbacks = 0,
		reads = 0,
	}
	fake.raw = function(key: string): any
		return clone(records[key])
	end
	fake.setRaw = function(key: string, value: any)
		records[key] = clone(value)
	end
	fake.deps = {
		keyPrefix = "qa:u:",
		clock = function()
			return fake.wall
		end,
		monotonic = function()
			return fake.time
		end,
		wait = function(seconds: number)
			fake.time += seconds
			fake.wall += seconds
		end,
		budget = function(_mode: string)
			return fake.hasBudget
		end,
		jitter = function()
			return 0
		end,
		read = function(key: string): any
			fake.reads += 1
			return clone(records[key])
		end,
		updateAsync = function(key: string, transform: (any) -> any): any
			fake.calls += 1
			if fake.failBefore > 0 then
				fake.failBefore -= 1
				error("offline failure before commit")
			end
			local nextValue: any = nil
			for _ = 1, fake.repeats do
				fake.callbacks += 1
				nextValue = transform(clone(records[key]))
			end
			if nextValue == nil then
				return nil
			end
			records[key] = clone(nextValue)
			fake.writes += 1
			local hook: (() -> ())? = fake.afterCommit
			fake.afterCommit = nil
			if hook then
				hook()
			end
			if fake.failAfter > 0 then
				fake.failAfter -= 1
				error("offline lost response after commit")
			end
			return clone(nextValue)
		end,
	}
	return fake
end
