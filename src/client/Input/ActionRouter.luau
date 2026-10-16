--!strict
-- Device-independent input state. Timing is supplied by the caller, never a clock.
local ActionRouter = {}
type Callbacks = { onAxis: (number) -> (), onAction: (string) -> () }
local DISCRETE: { [string]: boolean } = { Mace1 = true, Mace2 = true, Mace3 = true }
for n = 1, 9 do
	DISCRETE["Summon" .. n] = true -- remake: up to nine unit buttons (E02 §5)
end

function ActionRouter.new(callbacks: Callbacks)
	local held: { [any]: string } = {}
	local blockers: { [string]: boolean } = {}
	local axis, now, lastSent = 0, 0, 0
	local destroyed = false
	local function blocked(): boolean
		return next(blockers) ~= nil or destroyed
	end
	local function send(value: number)
		axis, lastSent = value, now
		callbacks.onAxis(value)
	end
	local function updateAxis()
		local left, right = false, false
		for _, action in held do
			left = left or action == "Left"
			right = right or action == "Right"
		end
		local value = if left == right then 0 elseif left then -1 else 1
		if value ~= axis then
			send(value)
		end
	end
	local router = {}
	function router.begin(action: string, token: any)
		if blocked() or token == nil or held[token] ~= nil then
			return
		end
		if action ~= "Left" and action ~= "Right" and not DISCRETE[action] then
			return
		end
		held[token] = action
		if DISCRETE[action] then
			callbacks.onAction(action)
		else
			updateAxis()
		end
	end
	function router.finish(token: any)
		if token == nil then
			return
		end
		held[token] = nil
		updateAxis()
	end
	function router.activate(action: string)
		if not blocked() and DISCRETE[action] then
			callbacks.onAction(action)
		end
	end
	function router.setBlocked(reason: string, value: boolean)
		if destroyed then
			return
		end
		if value then
			if blockers[reason] then
				return
			end
			blockers[reason] = true
			table.clear(held)
			send(0)
		else
			blockers[reason] = nil
		end
	end
	function router.step(timestamp: number)
		if destroyed or timestamp ~= timestamp or timestamp == math.huge or timestamp < now then
			return
		end
		now = timestamp
		if axis ~= 0 and now - lastSent >= 0.1 then
			send(axis)
		end
	end
	function router.inspect()
		local count = 0
		for _ in held do
			count += 1
		end
		return { axis = axis, heldCount = count, blocked = blocked(), destroyed = destroyed }
	end
	function router.destroy()
		if destroyed then
			return
		end
		table.clear(held)
		destroyed = true
		send(0)
	end
	return router
end
return ActionRouter
