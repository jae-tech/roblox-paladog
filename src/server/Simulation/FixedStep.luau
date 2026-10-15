--!strict
-- Heartbeat dt -> fixed 0.05s ticks (ARCHITECTURE §5). Due ticks are derived from total elapsed time (with a
-- small epsilon), so 60fps, 30fps and uneven frames covering the same time give the same tick count; per-frame
-- rounding would drift. At most 4 ticks per frame; backlog beyond 0.25s (5 ticks) is dropped and reported.
local TICKS_PER_SECOND = 20
local MAX_BACKLOG_TICKS = 5
local MAX_STEPS_PER_FRAME = 4

export type Driver = { elapsed: number, ticks: number, droppedTicks: number }

local function new(): Driver
	return { elapsed = 0, ticks = 0, droppedTicks = 0 }
end

-- Returns how many ticks `stepFn` was run for this frame.
local function advance(driver: Driver, dt: number, stepFn: () -> ()): number
	driver.elapsed += math.max(0, dt)
	local due = math.floor(driver.elapsed * TICKS_PER_SECOND + 1e-6)
		- driver.ticks
		- driver.droppedTicks
	if due > MAX_BACKLOG_TICKS then
		driver.droppedTicks += due - MAX_BACKLOG_TICKS -- simDroppedSeconds = droppedTicks / 20
		due = MAX_BACKLOG_TICKS
	end
	local steps = math.min(due, MAX_STEPS_PER_FRAME)
	for _ = 1, steps do
		driver.ticks += 1
		stepFn()
	end
	return steps
end

local function droppedSeconds(driver: Driver): number
	return driver.droppedTicks / TICKS_PER_SECOND
end

return table.freeze({
	new = new,
	advance = advance,
	droppedSeconds = droppedSeconds,
	MAX_STEPS_PER_FRAME = MAX_STEPS_PER_FRAME,
})
