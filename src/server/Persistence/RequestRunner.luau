--!strict
-- Sequential I/O retries only. A yielding call is never raced by a timeout/replacement writer.
export type Deps = {
	monotonic: () -> number,
	wait: (number) -> (),
	budget: (string) -> boolean,
	jitter: () -> number,
}

local function run(
	deps: Deps,
	mode: string,
	operation: () -> any,
	permitted: (() -> boolean)?
): (boolean, any)
	local deadline = deps.monotonic() + 20
	for attempt = 1, 5 do
		if permitted and not permitted() then
			return false, "SessionLost"
		end
		if deps.monotonic() >= deadline then
			break
		end
		if deps.budget(mode) then
			local ok, value = pcall(operation)
			if ok then
				return true, value
			end -- late outcomes are reconciled by the caller, not discarded as cancellation
		end
		if attempt < 5 then
			local delay = math.min(
				2 ^ (attempt - 1) + math.clamp(deps.jitter(), 0, 0.5),
				deadline - deps.monotonic()
			)
			if delay <= 0 then
				break
			end
			deps.wait(delay)
		end
	end
	return false, "StorageUnavailable"
end

return table.freeze({ run = run })
