--!strict
-- Plaza leaderboard (R8, D-PLAZA-02): per-server ranking from loaded profiles. Pure; Plaza.luau shows it.
-- Global (cross-server) ranking would need an OrderedDataStore and stays out until persistence is enabled.
local BOARD_SIZE = 10

export type Stats = { level: number, stage: number, wave: number, difficulty: number }
export type Row = {
	userId: number,
	name: string,
	level: number,
	stage: number,
	wave: number,
	difficulty: number,
}
-- difficulty names (data/remake/design.json text.difficulty); -1 = no record yet
local DIFFICULTY = { [0] = "쉬움", [1] = "보통", [2] = "어려움", [3] = "지옥" }

-- Current slot's level, difficulty, highest cleared campaign stage (any star) and best survival wave.
local function statsOf(profile: any): Stats
	local slot = profile and profile.currentSlot and profile.slots[profile.currentSlot]
	if not slot then
		return { level = 0, stage = 0, wave = 0, difficulty = -1 }
	end
	local stage = 0
	for index, star in slot.stars do
		if star >= 1 and index > stage then
			stage = index
		end
	end
	return {
		level = slot.level,
		stage = stage,
		wave = slot.survivalBest or 0,
		difficulty = slot.difficulty or 0,
	}
end

-- Highest difficulty first (D-DIFF-01: stages restart on each new difficulty), then stage, survival
-- wave, level, and user id so the order is stable.
local function rank(rows: { Row }): { Row }
	local sorted = table.clone(rows)
	table.sort(sorted, function(a: Row, b: Row): boolean
		if a.difficulty ~= b.difficulty then
			return a.difficulty > b.difficulty
		elseif a.stage ~= b.stage then
			return a.stage > b.stage
		elseif a.wave ~= b.wave then
			return a.wave > b.wave
		elseif a.level ~= b.level then
			return a.level > b.level
		end
		return a.userId < b.userId
	end)
	while #sorted > BOARD_SIZE do
		table.remove(sorted)
	end
	return sorted
end

local function stageLabel(stage: number): string
	if stage <= 0 then
		return "-"
	end
	return string.format("%d-%d", (stage - 1) // 24 + 1, (stage - 1) % 24 + 1)
end

local function difficultyLabel(difficulty: number): string
	return DIFFICULTY[difficulty] or "-"
end

return table.freeze({
	BOARD_SIZE = BOARD_SIZE,
	difficultyLabel = difficultyLabel,
	statsOf = statsOf,
	rank = rank,
	stageLabel = stageLabel,
})
