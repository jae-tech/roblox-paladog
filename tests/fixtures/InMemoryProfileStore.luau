--!strict
-- P0 MOCK only: detached numeric records. No DataStore, leases, revisions, or P2 contract.
return function()
	local records: { [string]: { [string]: number } } = {}
	return {
		backend = "Mock/InMemory",
		read = function(key: string): { [string]: number }?
			local record = records[key]
			return if record then table.clone(record) else nil
		end,
		write = function(key: string, value: { [string]: number })
			records[key] = table.clone(value)
		end,
	}
end
