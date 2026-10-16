--!strict
-- Account achievements (E05 B11): granted once per account, gems on first grant. Codes 14, 29..38 and 40
-- depend on rankings/friends (no social server in the remake) and are never granted.
local ServerTypes = require("../ServerTypes")

type Profile = ServerTypes.ProfileV1
type Slot = ServerTypes.Slot

local GEMS: { [number]: number } = {
	[0] = 25,
	[1] = 25,
	[2] = 25,
	[3] = 10,
	[4] = 10,
	[5] = 10,
	[6] = 10,
	[7] = 15,
	[8] = 15,
	[9] = 15,
	[10] = 15,
	[11] = 20,
	[12] = 30,
	[13] = 100,
	[15] = 20,
	[16] = 10,
	[17] = 10,
	[18] = 10,
	[19] = 10,
	[20] = 10,
	[21] = 10,
	[22] = 10,
	[23] = 10,
	[24] = 10,
	[25] = 100,
	[26] = 30,
	[27] = 500,
	[28] = 1000,
	[39] = 200,
}
-- Codes 16..24 map to units by code position; 20 is the turtle (unit 6), 21 the monkey (unit 5).
local UNIT_CODE =
	{ [1] = 16, [2] = 17, [3] = 18, [4] = 19, [6] = 20, [5] = 21, [7] = 22, [8] = 23, [9] = 24 }

export type BattleContext = {
	stage: number,
	victory: boolean,
	elapsedTicks: number,
	levelUps: number,
	kills: number,
}

local function has(profile: Profile, code: number): boolean
	return table.find(profile.achievements, code) ~= nil
end

local function grant(profile: Profile, code: number): number
	if has(profile, code) then
		return 0
	end
	table.insert(profile.achievements, code)
	table.sort(profile.achievements)
	local gems = GEMS[code] or 0
	profile.gems = math.min(profile.gems + gems, 99999)
	return gems
end

-- Checks every state-based code for `slot`, plus battle codes when a context is given. Returns gems gained.
local function evaluate(profile: Profile, slot: Slot, battle: BattleContext?): number
	local gained = 0
	if battle and battle.victory then
		if battle.elapsedTicks <= 60 * 30 then
			gained += grant(profile, 0)
		end
		if battle.stage % 12 == 0 and slot.heroKind == "light" then
			gained += grant(profile, 2 + battle.stage // 12) -- bosses 1..10 at 1-12 .. 5-24
		end
		if battle.stage == 120 and slot.heroKind == "shadow" then
			gained += grant(profile, 39)
		end
	end
	if battle then
		if battle.levelUps >= 2 then
			gained += grant(profile, 1)
		end
		if battle.kills >= 100 then
			gained += grant(profile, 2)
		end
	end
	if slot.level >= 200 then
		gained += grant(profile, 13)
	end
	if slot.heroKind == "light" then
		local all = true
		for n = 1, 9 do
			if slot.units[n] < 1 then
				all = false
			end
			if slot.units[n] >= 20 then
				gained += grant(profile, UNIT_CODE[n])
			end
		end
		if all then
			gained += grant(profile, 15)
		end
	end
	local stars = 0
	for _, star in slot.stars do
		stars += math.max(star, 0)
	end
	if stars >= 360 then
		gained += grant(profile, 25)
	end
	for code, amount in { [26] = 1000000, [27] = 10000000, [28] = 100000000 } do
		if slot.gold >= amount then
			gained += grant(profile, code)
		end
	end
	return gained
end

return table.freeze({ evaluate = evaluate, GEMS = GEMS })
