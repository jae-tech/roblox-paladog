--!strict
-- Stage quests (E05 B10 types, D-QUEST-01/02 definitions generated into Db.quests). A quest only counts on
-- a victory; stars = quests met (0..3, the main quest is always met by winning).
local Db = require("../Config/Remake/Db")

export type Stats = {
	victory: boolean,
	elapsedTicks: number,
	heroHpRatio: number,
	gold: number,
	maceKills: number,
	summons: { [number]: number },
	maceUses: { [number]: number },
	alliesAlive: number,
	passed: number,
	boxesLeft: number,
	wagonHpRatio: number,
}

local function met(quest: any, stats: Stats): boolean
	local t, a, b = quest.type, quest.a, quest.b
	if t == 1 or t == 3 or t == 5 or t == 7 or t == 9 then
		return true -- mode goal: reached by winning
	elseif t == 2 then
		return stats.heroHpRatio * 100 >= a
	elseif t == 4 then
		return stats.boxesLeft >= a
	elseif t == 6 then
		return stats.wagonHpRatio * 100 >= a
	elseif t == 8 then
		return stats.passed <= a
	elseif t == 10 then
		return stats.elapsedTicks <= (a * 60 + b) * 30
	elseif t == 11 then
		return stats.gold >= a
	elseif t == 12 then
		return stats.maceKills >= a
	elseif t == 13 then
		return (stats.summons[a] or 0) == 0
	elseif t == 14 then
		return (stats.summons[a] or 0) >= b
	elseif t == 15 then
		return stats.alliesAlive >= a
	elseif t == 16 then
		return (stats.maceUses[a] or 0) == 0
	elseif t == 17 then
		return (stats.maceUses[a] or 0) >= b
	end
	return false
end

local function evaluate(stage: number, stats: Stats): { boolean }
	local defs = Db.quests[stage]
	local out = { false, false, false }
	if stats.victory and defs then
		for i = 1, 3 do
			out[i] = met(defs[i], stats)
		end
	end
	return out
end

-- Battle -> quest stats at the terminal tick.
local function statsOf(battle: any, Battle: any): Stats
	local hero = Battle.hero(battle)
	local allies, wagonRatio = 0, 0
	for _, id in battle.order do
		local e: any = battle.entities[id]
		local kind: string = e.kind
		if kind == "Unit" and Battle.alive(e) then
			allies += 1
		elseif kind == "Wagon" then
			wagonRatio = math.max(e.hp, 0) / e.maxHp
		end
	end
	local boxes = 0
	for i = 1, 9 do
		if battle.boxes[i] then
			boxes += 1
		end
	end
	return {
		victory = battle.outcome == "Victory",
		elapsedTicks = battle.tick,
		heroHpRatio = math.max(hero.hp, 0) / hero.maxHp,
		gold = battle.rewards.gold,
		maceKills = battle.rewards.maceKills,
		summons = battle.rewards.summons,
		maceUses = battle.rewards.maceUses,
		alliesAlive = allies,
		passed = battle.rewards.passed,
		boxesLeft = boxes,
		wagonHpRatio = wagonRatio,
	}
end

return table.freeze({ evaluate = evaluate, statsOf = statsOf, met = met })
