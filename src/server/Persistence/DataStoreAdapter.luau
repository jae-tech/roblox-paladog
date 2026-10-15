--!strict
-- Engine-free adapter over injected UpdateAsync/GetAsync (uncached). Cancelled callbacks return nil;
-- classification reads happen afterwards, so callbacks never mutate external status/counters.
local Types = require("../ServerTypes")
local Schema = require("../Services/ProfileSchema")
local Validator = require("./ProfileValidator")
local Runner = require("./RequestRunner")

export type Deps = {
	updateAsync: (string, (any) -> any) -> any,
	read: (string) -> any,
	clock: () -> number,
	monotonic: () -> number,
	wait: (number) -> (),
	budget: (string) -> boolean,
	jitter: () -> number,
	keyPrefix: string,
}

local LEASE_SECONDS = 180
local function owns(profile: any, session: Types.Session, now: number): boolean
	local lease = profile and profile.lease
	return lease ~= nil
		and lease.sessionId == session.sessionId
		and lease.ownerJobId == session.jobId
		and profile.fenceEpoch == session.fenceEpoch
		and lease.expiresAt > now
end

local function new(deps: Deps): Types.StoreAdapter
	assert(deps.keyPrefix == "qa:u:", "only QA profile keys are enabled")
	local function key(userId: number): string
		assert(userId % 1 == 0 and math.abs(userId) < math.huge, "invalid user id")
		return deps.keyPrefix .. string.format("%.0f", userId)
	end
	local function loadAndLock(
		userId: number,
		owner: Types.SessionKey,
		_now: number,
		makeNew: () -> Types.ProfileV1,
		_validate: (any) -> (boolean, string?)
	): Types.LoadResult
		local template = makeNew()
		local ok, saved = Runner.run(deps, "write", function()
			local now = deps.clock() -- fixed before entering the no-yield callback
			return deps.updateAsync(key(userId), function(old: any): any
				if old ~= nil and not Validator.validate(old) then
					return nil
				end
				local value = if old == nil
					then Schema.deepClone(template)
					else Schema.deepClone(old)
				if not Validator.validate(value) then
					return nil
				end
				local lease = value.lease
				if lease then
					if lease.sessionId == owner.sessionId and lease.ownerJobId == owner.jobId then
						return if lease.expiresAt > now then value else nil -- retry, never resurrect expired token
					elseif lease.expiresAt > now then
						return nil
					end
				end
				value.fenceEpoch += 1
				value.lease = {
					sessionId = owner.sessionId,
					ownerJobId = owner.jobId,
					expiresAt = now + LEASE_SECONDS,
				}
				return value
			end)
		end)
		if not ok then
			return { kind = "error", message = saved }
		end
		if saved == nil then
			local readOk, existing = Runner.run(deps, "read", function()
				return deps.read(key(userId))
			end)
			if not readOk or existing == nil then
				return { kind = "error", message = "unconfirmed acquisition" }
			end
			local valid, reason = Validator.validate(existing)
			return if valid then { kind = "locked" } else { kind = "invalid", message = reason }
		end
		local valid, reason = Validator.validate(saved)
		if not valid then
			return { kind = "invalid", message = reason }
		end
		local token: Types.Session =
			{ sessionId = owner.sessionId, jobId = owner.jobId, fenceEpoch = saved.fenceEpoch }
		if not owns(saved, token, deps.clock() + 30) then
			return { kind = "error", message = "late or foreign acquisition" }
		end
		return { kind = "ok", profile = Schema.deepClone(saved) }
	end

	local function update(
		userId: number,
		session: Types.Session,
		_now: number,
		transform: Types.Transform
	): Types.UpdateResult
		local function permitted(): boolean
			return session.leaseExpiresAt == nil or deps.clock() < session.leaseExpiresAt - 30
		end
		local ok, saved = Runner.run(deps, "write", function()
			local now = deps.clock()
			return deps.updateAsync(key(userId), function(old: any): any
				if not Validator.validate(old) or not owns(old, session, now) then
					return nil
				end
				local nextValue = transform(Schema.deepClone(old))
				if not nextValue then
					return nil
				end
				nextValue.fenceEpoch = old.fenceEpoch
				nextValue.lease = {
					sessionId = session.sessionId,
					ownerJobId = session.jobId,
					expiresAt = now + LEASE_SECONDS,
				}
				return if Validator.validate(nextValue) then nextValue else nil
			end)
		end, permitted)
		if not ok then
			return { kind = if saved == "SessionLost" then "stale" else "error", message = saved }
		end
		if saved == nil then
			local readOk, existing = Runner.run(deps, "read", function()
				return deps.read(key(userId))
			end, permitted)
			if not readOk then
				return { kind = "error", message = "unconfirmed update" }
			end
			if not Validator.validate(existing) then
				return { kind = "error", message = "invalid stored profile" }
			end
			if not owns(existing, session, deps.clock()) then
				return { kind = "stale" }
			end
			local nextValue, reason = transform(Schema.deepClone(existing))
			return if not nextValue
				then { kind = "rejected", reason = reason }
				else { kind = "error", message = "unconfirmed transform" }
		end
		if not Validator.validate(saved) or not owns(saved, session, deps.clock() + 30) then
			return { kind = "stale" }
		end
		return { kind = "ok", profile = Schema.deepClone(saved) }
	end

	local function release(userId: number, session: Types.Session): boolean
		local ok, saved = Runner.run(deps, "write", function()
			local now = deps.clock()
			return deps.updateAsync(key(userId), function(old: any): any
				if not Validator.validate(old) or old.fenceEpoch ~= session.fenceEpoch then
					return nil
				end
				if old.lease == nil then
					return Schema.deepClone(old)
				end -- lost response, same released fence
				if not owns(old, session, now) then
					return nil
				end
				local nextValue = Schema.deepClone(old)
				nextValue.lease = nil
				return nextValue
			end)
		end)
		return ok
			and saved ~= nil
			and Validator.validate(saved)
			and saved.fenceEpoch == session.fenceEpoch
			and saved.lease == nil
	end
	return {
		backend = "DataStore/QA",
		leaseSeconds = LEASE_SECONDS,
		loadAndLock = loadAndLock,
		update = update,
		renew = function(userId, session, now)
			return update(userId, session, now, function(p)
				return p, nil
			end)
		end,
		release = release,
	}
end

return table.freeze({ new = new })
