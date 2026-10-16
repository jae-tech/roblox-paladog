--!strict
-- Safe-content px. Narrow screens put the scrollable summon strip above movement/weapon controls.
local function plan(width: number): any
	local compact = width < 900
	local inner = math.max(width - 16, 1)
	local weaponWidth = if compact then (if width < 360 then 56 else 64) else 74
	local unitWidth = if compact then inner else inner - 380
	return {
		compact = compact,
		bottomHeight = if compact then 196 else 128,
		unitX = if compact then 0 else 142,
		unitY = if compact then 24 else 22,
		unitWidth = unitWidth,
		unitHeight = if compact then 84 else 100,
		unitButtonWidth = if compact then 64 else math.max(48, unitWidth / 9 - 4),
		moveSize = if compact then 48 else 64,
		moveY = if compact then 148 else 64,
		weaponWidth = weaponWidth,
		weaponX = inner - (weaponWidth * 3 + 8),
		weaponY = if compact then 132 else 22,
		weaponHeight = if compact then 64 else 100,
		foodX = if compact then 0 else 142,
		foodWidth = if compact then (inner - 8) / 2 else unitWidth,
		manaWidth = if compact then (inner - 8) / 2 else 230,
	}
end

return table.freeze({ plan = plan })
