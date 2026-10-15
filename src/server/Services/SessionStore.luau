--!strict
-- Process-local MVP storage. Never reads/writes DataStore; all state disappears with the server.
-- Fences last for this process (no expiring distributed lease to renew).
local Types = require("../ServerTypes")
local Schema = require("./ProfileSchema")

local function new(): Types.StoreAdapter
	local records: { [number]: Types.ProfileV1 } = {}
	local function owns(record: Types.ProfileV1?, session: Types.Session): boolean
		return record ~= nil
			and record.lease ~= nil
			and record.lease.sessionId == session.sessionId
			and record.fenceEpoch == session.fenceEpoch
	end
	return {
		backend = "ServerMemory · 영구 저장 아님",
		loadAndLock = function(userId, key, _now, makeNew, validate)
			local existing = records[userId]
			local record = Schema.deepClone(existing or makeNew()) :: Types.ProfileV1
			local valid, reason = validate(record)
			if not valid then
				return { kind = "invalid", message = reason }
			elseif record.lease then
				return { kind = "locked" }
			end
			record.fenceEpoch += 1
			record.lease = { sessionId = key.sessionId, ownerJobId = key.jobId, expiresAt = 0 }
			records[userId] = record
			return { kind = "ok", profile = Schema.deepClone(record), created = existing == nil }
		end,
		update = function(userId, session, _now, transform)
			local record = records[userId]
			if not owns(record, session) then
				return { kind = "stale" }
			end
			local saved, reason = transform(Schema.deepClone(record))
			if not saved then
				return { kind = "rejected", reason = reason }
			end
			saved.lease, saved.fenceEpoch = record.lease, record.fenceEpoch
			local valid, problem = Schema.validate(saved)
			if not valid then
				return { kind = "error", message = problem }
			end
			records[userId] = Schema.deepClone(saved)
			return { kind = "ok", profile = Schema.deepClone(saved) }
		end,
		release = function(userId, session)
			local record = records[userId]
			if not owns(record, session) then
				return false
			end
			record.lease = nil
			return true
		end,
	}
end

return table.freeze({ new = new })
