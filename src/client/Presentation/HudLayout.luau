--!strict
-- Safe-content px. Narrow screens put the scrollable summon strip above movement/weapon controls.
local function plan(width: number): any
	local compact = width < 900
	local inner = math.max(width - 16, 1)
	local weaponWidth = if compact then (if width < 360 then 56 else 64) else 74
	local unitWidth = if compact then inner else inner - 380
	return {
		compact = compact,
		bottomHeight = if compact then 228 else 128,
		unitX = if compact then 0 else 142,
		unitY = if compact then 24 else 22,
		unitWidth = unitWidth,
		unitHeight = if compact then 84 else 100,
		unitButtonWidth = if compact then 64 else math.max(48, unitWidth / 9 - 4),
		moveSize = 48,
		moveY = if compact then 116 else 24,
		strafeY = if compact then 172 else 80,
		weaponWidth = weaponWidth,
		weaponX = inner - (weaponWidth * 3 + 8),
		weaponY = if compact then 164 else 22,
		weaponHeight = if compact then 64 else 100,
		foodX = if compact then 0 else 142,
		foodWidth = if compact then (inner - 8) / 2 else unitWidth,
		manaWidth = if compact then (inner - 8) / 2 else 230,
	}
end

-- Lobby layout is authored at 912x544 px (nav 140 + widest content 762, header 54 + stage grid/detail 460 +
-- toast 30). Smaller screens shrink the whole lobby uniformly so every tab and button stays on screen.
local LOBBY_WIDTH, LOBBY_HEIGHT = 912, 544
local function lobbyScale(width: number, height: number): number
	return math.clamp(math.min(width / LOBBY_WIDTH, height / LOBBY_HEIGHT), 0.25, 1)
end

return table.freeze({
	plan = plan,
	lobbyScale = lobbyScale,
	LOBBY_WIDTH = LOBBY_WIDTH,
	LOBBY_HEIGHT = LOBBY_HEIGHT,
})
