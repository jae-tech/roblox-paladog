--!strict
-- Only this module touches Roblox DataStore APIs. Requiring it does not access a data store.
local Policy = require("./PersistencePolicy")
local Adapter = require("./DataStoreAdapter")

local function new()
	assert(
		Policy.allowed(Policy.config, game.GameId, game:GetService("RunService"):IsStudio()),
		"DataStore access is disabled"
	)
	local service = game:GetService("DataStoreService")
	local store = service:GetDataStore(Policy.config.namespace)
	local options = Instance.new("DataStoreGetOptions")
	options.UseCache = false
	return Adapter.new({
		keyPrefix = Policy.config.keyPrefix,
		clock = os.time,
		monotonic = os.clock,
		wait = function(seconds)
			task.wait(seconds)
		end,
		jitter = function()
			return math.random() * 0.5
		end,
		budget = function(mode)
			local read =
				service:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead)
			return read > 0
				and (
					mode == "read"
					or service:GetRequestBudgetForRequestType(
							Enum.DataStoreRequestType.StandardWrite
						)
						> 0
				)
		end,
		read = function(key)
			return store:GetAsync(key, options)
		end,
		updateAsync = function(key, transform)
			return store:UpdateAsync(key, function(old, info)
				local nextValue = transform(old)
				if nextValue == nil then
					return nil
				end
				return nextValue,
					if info then info:GetUserIds() else {},
					if info then info:GetMetadata() else {}
			end)
		end,
	})
end

return table.freeze({ new = new })
