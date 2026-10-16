--!strict
-- Boar jump stages (shadow hero, E04 §4-3). The original tile maps (.mje) were never parsed, so D-JUMP-01
-- builds an original deterministic track from the stage row: boar speed (iCSp11 x difficulty jump factor),
-- gold per coin (iCSp12), coin counts for stars (iUCnt_, iCSp21) and five safe-zone tiles (iECHP_, iEU01_,
-- iEU01P, iEU02_, iEU02P). Spikes kill a grounded boar; it restarts at x = 50 + furthest safe tile * width.
local Rng = require("./Rng")

local DT = 1 / 30
local TILE = 64 -- D-JUMP-01: tile width (iBaseW) is not in the research data
local JUMP_TICKS = 18 -- D-JUMP-02: 0.6 s jump arc
local SPIKE_HALF = 20
local RESPAWN_TICKS = 30
local JUMP_SPEED = { [0] = 0.95, [1] = 1.0, [2] = 1.05, [3] = 1.1 } -- E04 §2-2 difficulty column

local function track(row: any, stageNumber: number): any
	local safe = { row.castleHp, row.u1, row.p1, row.u2, row.p2 }
	table.sort(safe)
	local finish = (safe[#safe] + 12) * TILE
	local rng = Rng.new(stageNumber * 7919 + 17)
	local spikes: { number } = {}
	local x = 400
	while x < finish - TILE do
		local nearSafe = false
		for _, tile in safe do
			if math.abs(x - tile * TILE) < TILE * 1.5 then
				nearSafe = true
			end
		end
		if not nearSafe then
			table.insert(spikes, x)
		end
		x += 260 + Rng.rand(rng) % 161
	end
	local coins: { number } = {}
	local count = math.max(row.unitCount, 1)
	local spacing = (finish - 300) / count
	for i = 1, count do
		local at = 150 + (i - 0.5) * spacing
		table.insert(coins, at)
	end
	return { safe = safe, finish = finish, spikes = spikes, coins = coins }
end

local function newRewards(): any
	return {
		gold = 0,
		exp = 0,
		goldSpent = 0,
		kills = {},
		killTotal = 0,
		drops = {},
		levelUps = 0,
		picks = {},
		revives = 0,
		summons = {},
		maceUses = {},
		maceKills = 0,
		passed = 0,
	}
end

local function new(options: any, row: any, stageNumber: number): any
	local map = track(row, stageNumber)
	local hero = {
		id = 1,
		kind = "Hero",
		n = 0,
		team = 1,
		x = 50,
		y = 165,
		line = -1,
		dir = 1,
		hp = 1,
		maxHp = 1,
		state = "Move",
	}
	local boss = {
		id = 2,
		kind = "Runner",
		n = 13,
		team = 2,
		x = 600,
		y = 165,
		line = -1,
		dir = 1,
		hp = 1,
		maxHp = 1,
		state = "Move",
	}
	local loadout = table.clone(options.loadout)
	loadout.skills, loadout.unitLevels =
		table.clone(loadout.skills), table.clone(loadout.unitLevels)
	loadout.equip = {}
	for slot, item in options.loadout.equip do
		loadout.equip[slot] = table.clone(item)
	end
	return {
		jump = true,
		mode = "Jump",
		stageNumber = stageNumber,
		stage = row,
		seed = options.seed,
		tick = 0,
		outcome = nil,
		loadout = loadout,
		speed = row.s11 * (JUMP_SPEED[options.loadout.difficulty] or 1),
		coinGold = row.s12,
		map = map,
		collected = {},
		coins = 0,
		deaths = 0,
		air = 0,
		dead = 0,
		furthestSafe = 0,
		entities = { [1] = hero, [2] = boss },
		order = { 1, 2 },
		heroId = 1,
		boxes = {},
		rewards = newRewards(),
		exp = 0,
		pendingPicks = {},
		reviveOffer = false,
	}
end

local function step(b: any, input: any): any
	local results = {}
	for _, command in (input and input.commands) or {} do
		local reason: string? = nil
		if b.outcome then
			reason = "WrongPhase"
		elseif command.kind == "Retreat" then
			b.outcome = "Defeat"
		elseif command.kind ~= "Jump" then
			reason = "WrongMode"
		elseif b.air > 0 or b.dead > 0 then
			reason = "Busy"
		else
			b.air = JUMP_TICKS
		end
		table.insert(results, {
			requestId = command.requestId,
			status = if reason then "Rejected" else "Accepted",
			reason = reason,
		})
	end
	if b.outcome then
		return { results = results, outcome = b.outcome }
	end
	b.tick += 1
	local hero, boss = b.entities[1], b.entities[2]
	local map = b.map
	boss.x = math.min(boss.x + b.speed * 0.9 * DT, map.finish)
	if b.dead > 0 then
		b.dead -= 1
		if b.dead == 0 then
			hero.x, hero.state = 50 + b.furthestSafe * TILE, "Move"
		end
		return { results = results }
	end
	local before = hero.x
	hero.x += b.speed * DT
	-- the boar hops the runner automatically within 0..100 px behind it (E04 §4-3)
	local gap = boss.x - hero.x
	if b.air == 0 and gap >= 0 and gap <= 100 then
		b.air = JUMP_TICKS
	end
	if b.air > 0 then
		b.air -= 1
		hero.state = "Jump"
	else
		hero.state = "Move"
		for _, spike in map.spikes do
			if math.abs(hero.x - spike) <= SPIKE_HALF then
				b.deaths += 1
				b.dead = RESPAWN_TICKS
				hero.state = "Dead"
				return { results = results }
			end
		end
	end
	-- D-JUMP-03: collect by swept X while grounded or airborne; original coin heights were not parsed.
	for index, coin in map.coins do
		if not b.collected[index] and before < coin and hero.x >= coin then
			b.collected[index] = true
			b.coins += 1
			b.rewards.gold += b.coinGold
		end
	end
	for _, tile in map.safe do
		if hero.x >= tile * TILE and tile > b.furthestSafe then
			b.furthestSafe = tile
		end
	end
	if hero.x >= map.finish + 100 and hero.x > boss.x then
		b.outcome = "Victory"
	end
	return { results = results, outcome = b.outcome }
end

local function snapshot(b: any): any
	local list = {}
	for _, id in b.order do
		local e = b.entities[id]
		table.insert(list, {
			id = e.id,
			kind = e.kind,
			n = e.n,
			team = e.team,
			x = e.x,
			y = e.y + (if e.kind == "Hero" and b.air > 0
				then math.sin(math.pi * (1 - b.air / JUMP_TICKS)) * 50
				else 0),
			line = e.line,
			dir = 1,
			hp = e.hp,
			maxHp = e.maxHp,
			state = e.state,
		})
	end
	local objects = {}
	local hero = b.entities[1]
	for index, spike in b.map.spikes do
		if math.abs(spike - hero.x) < 700 then
			table.insert(objects, {
				id = 10000 + index,
				kind = "Spike",
				row = 0,
				team = 2,
				x = spike,
				line = -1,
				dir = 1,
				t = 0,
			})
		end
	end
	for index, coin in b.map.coins do
		if not b.collected[index] and math.abs(coin - hero.x) < 700 then
			table.insert(objects, {
				id = 20000 + index,
				kind = "Coin",
				row = 0,
				team = 1,
				x = coin,
				line = -1,
				dir = 1,
				t = 0,
			})
		end
	end
	return {
		tick = b.tick,
		mode = "Jump",
		heroKind = "shadow",
		food = 0,
		mana = 0,
		maxFood = 1,
		maxMana = 1,
		heroSpeed = 0,
		heroMinX = -40,
		heroMaxX = b.map.finish + 200,
		summonPast = {},
		level = b.loadout.level,
		exp = b.loadout.exp,
		gold = b.rewards.gold,
		kills = 0,
		points = 0,
		boxes = {},
		coins = b.coins,
		coinTotal = #b.map.coins,
		finish = b.map.finish + 100,
		deaths = b.deaths,
		traps = {},
		offer = nil,
		reviveOffer = false,
		paused = false,
		outcome = b.outcome,
		entities = list,
		objects = objects,
	}
end

local function digest(b: any): string
	local hero, boss = b.entities[1], b.entities[2]
	local text = string.format(
		"j%d|%.17g|%.17g|%d|%d|%d|%d|%d|%s",
		b.tick,
		hero.x,
		boss.x,
		b.air,
		b.dead,
		b.coins,
		b.deaths,
		b.furthestSafe,
		tostring(b.outcome)
	)
	text ..= string.format("|gold%d|speed%.17g|seed%d", b.rewards.gold, b.speed, b.seed)
	for index = 1, #b.map.coins do
		text ..= if b.collected[index] then "1" else "0"
	end
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 403 + bit32.lshift(hash, 24)) % 4294967296
	end
	return string.format("%08x", hash)
end

return table.freeze({
	new = new,
	step = step,
	snapshot = snapshot,
	digest = digest,
	track = track,
	TILE = TILE,
})
