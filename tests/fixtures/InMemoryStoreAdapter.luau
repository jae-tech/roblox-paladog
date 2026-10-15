--!strict
-- P2 MOCK StoreAdapter (ARCHITECTURE §8.2/8.3 contract) for CLI and Studio test rigs. Never a DataStore.
-- Leases expire on the injected clock; fenceEpoch increments on every new acquisition and is never cleared.
local LEASE_SECONDS = 180

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepClone(item)
	end
	return copy
end

return function()
	local records: { [number]: any } = {}
	local faults: { [string]: number } = {}
	local calls = { loadAndLock = 0, update = 0, release = 0, transforms = 0 }

	local function fault(operation: string): boolean
		local pending = faults[operation] or 0
		if pending > 0 then
			faults[operation] = pending - 1
			return true
		end
		return false
	end

	local function owns(record: any, session: any, now: number): boolean
		local lease = record.lease
		return lease ~= nil
			and lease.sessionId == session.sessionId
			and record.fenceEpoch == session.fenceEpoch
			and lease.expiresAt > now
	end

	local adapter = {
		backend = "Mock/InMemory",
		leaseSeconds = nil :: number?,
		renew = nil :: ((number, any, number) -> any)?,
		calls = calls,
	}

	function adapter.loadAndLock(
		userId: number,
		key: any,
		now: number,
		makeNew: () -> any,
		validate: (any) -> (boolean, string?)
	): any
		calls.loadAndLock += 1
		if fault("loadAndLock") then
			return { kind = "error", message = "injected load failure" }
		end
		local record = records[userId]
		local created = record == nil
		if created then
			record = makeNew()
		else
			local valid, problem = validate(deepClone(record))
			if not valid then
				return { kind = "invalid", message = problem } -- no lock, no write
			end
		end
		local lease = record.lease
		if lease and lease.sessionId ~= key.sessionId and lease.expiresAt > now then
			return { kind = "locked" }
		end
		record.fenceEpoch = (record.fenceEpoch or 0) + 1
		record.lease =
			{ sessionId = key.sessionId, ownerJobId = key.jobId, expiresAt = now + LEASE_SECONDS }
		records[userId] = record
		return { kind = "ok", profile = deepClone(record), created = created }
	end

	function adapter.update(
		userId: number,
		session: any,
		now: number,
		transform: (any) -> (any, string?)
	): any
		calls.update += 1
		if fault("updateBefore") then
			return { kind = "error", message = "injected failure before commit" }
		end
		local record = records[userId]
		if not record then
			return { kind = "error", message = "missing record" }
		end
		if not owns(record, session, now) then
			return { kind = "stale" }
		end
		calls.transforms += 1
		local nextValue, reason = transform(deepClone(record))
		if nextValue == nil then
			return { kind = "rejected", reason = reason }
		end
		nextValue.lease, nextValue.fenceEpoch = record.lease, record.fenceEpoch -- store owns the lock fields
		records[userId] = deepClone(nextValue)
		if fault("updateAfter") then
			return { kind = "error", message = "injected failure after commit (response lost)" }
		end
		return { kind = "ok", profile = deepClone(nextValue) }
	end

	function adapter.release(userId: number, session: any): boolean
		calls.release += 1
		local record = records[userId]
		if
			record
			and record.lease
			and record.lease.sessionId == session.sessionId
			and record.fenceEpoch == session.fenceEpoch
		then
			record.lease = nil -- fenceEpoch is preserved
			return true
		end
		return false
	end

	-- Test controls (not part of the StoreAdapter contract).
	function adapter.inject(operation: string, count: number?)
		faults[operation] = (faults[operation] or 0) + (count or 1)
	end
	function adapter.raw(userId: number): any
		return deepClone(records[userId])
	end
	function adapter.setRaw(userId: number, value: any)
		records[userId] = deepClone(value)
	end

	return adapter
end
