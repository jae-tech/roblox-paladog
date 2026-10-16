--!strict
-- R2 remake stage modes and bosses (docs/REMAKE_PLAN.md R2). Expected values cite the research specs.
return function(env: any, check: any)
	local Battle = env.Battle

	local function loadout(over: { [string]: any }?): any
		local l: any = {
			heroKind = "light",
			level = 1,
			exp = 0,
			skills = {},
			equip = { [1] = { num = 1, grade = 0 } },
			difficulty = 1,
			unitLevels = { 1, 1, 1, 1, 1, 1, 1, 1, 1 },
		}
		local overrides: { [string]: any } = over or {}
		for k, v in overrides do
			l[k] = v
		end
		return l
	end
	local function battle(stage: number, over: { [string]: any }?, extra: { [string]: any }?): any
		local options: any = { stage = stage, seed = 4242, loadout = loadout(over) }
		local extras: { [string]: any } = extra or {}
		for k, v in extras do
			options[k] = v
		end
		return Battle.new(options)
	end
	local function run(b: any, ticks: number, input: any?)
		for _ = 1, ticks do
			Battle.step(b, input)
		end
	end
	local function quiet(b: any)
		b.spawn.need = math.huge
	end
	local function first(b: any, kind: string, n: number?): any
		for _, id in b.order do
			local e = b.entities[id]
			if e.kind == kind and (n == nil or e.n == n) then
				return e
			end
		end
		return nil
	end
	local function tough(e: any)
		e.hp, e.maxHp = 1e9, 1e9
	end

	-- ------------------------------------------------ modes (E04 §0)
	check("mode-1", "Normal", Battle.modeOf(1), 0)
	check("mode-3", "Destiny", Battle.modeOf(3), 0)
	check("mode-6", "Wagon", Battle.modeOf(6), 0)
	check("mode-9", "Tower", Battle.modeOf(9), 0)
	check("mode-12", "Boss", Battle.modeOf(12), 0)
	check("mode-120", "Boss", Battle.modeOf(120), 0)
	check("destiny-level-3", 1, Battle.destinyLevel(3), 0)
	check("destiny-level-111", 19, Battle.destinyLevel(111), 0)

	-- ------------------------------------------------ boss stage (E04 §3-7)
	do
		local b = battle(12)
		quiet(b)
		local unit = Battle.spawnUnit(b, 1)
		unit.x = 500
		Battle.castle(b).hp = 0
		Battle.step(b)
		local boss = first(b, "Boss", 1)
		check("boss-stage-not-won-yet", nil, b.outcome, b.tick)
		check("boss-released", true, boss ~= nil, b.tick)
		check("boss-at-scroll-80", 944, boss and boss.x, b.tick)
		check("boss-knocks-allies", "Knock", unit.state, b.tick)
		check("boss-knock-x3", 3, unit.knockMul, b.tick)
		boss.hp = 0
		Battle.step(b)
		check("boss-stage-victory", "Victory", b.outcome, b.tick)
		local stage120 = battle(120)
		quiet(stage120)
		Battle.castle(stage120).hp = 0
		Battle.step(stage120)
		check("boss-120-is-10", true, first(stage120, "Boss", 10) ~= nil, stage120.tick)
	end

	-- ------------------------------------------------ boss patterns (E02 §4.4)
	do
		-- 01 summons two harmless escorts per attack; escorts pay 1 gold, 0 EXP
		local b = battle(1)
		quiet(b)
		local king = Battle.spawnEnemy(b, 101, 0, 400)
		local wall = Battle.spawnUnit(b, 6)
		wall.x = 300
		tough(wall)
		local minions = 0
		for _ = 1, 90 do
			Battle.step(b)
			minions = 0
			for _, id in b.order do
				local e = b.entities[id]
				if e.kind == "Enemy" and e.minion then
					minions += 1
				end
			end
			if minions >= 2 then
				break
			end
		end
		check("boss1-two-escorts", 2, minions, b.tick)
		local escort = first(b, "Enemy", 1)
		check("boss1-escort-ap0", 0, escort and escort.ap, b.tick)
		local gold0 = b.rewards.gold
		Battle.strike(b, nil, escort, 1e6, false, false)
		check("boss1-escort-1-gold", gold0 + 1, b.rewards.gold, b.tick)
		check("boss1-escort-0-exp", 0, b.exp, b.tick)
		local _ = king

		-- 02 frogs the first unit, never targets the hero
		local w = battle(1)
		quiet(w)
		local witch = Battle.spawnEnemy(w, 102, 0, 300)
		tough(witch)
		Battle.hero(w).x = 250
		run(w, 30)
		check("boss2-ignores-hero", nil, witch.target, w.tick)
		local mouse = Battle.spawnUnit(w, 1)
		mouse.x = 200
		tough(mouse)
		local frogged = false
		for _ = 1, 120 do
			Battle.step(w)
			if mouse.frogTicks > 0 then
				frogged = true
				break
			end
		end
		check("boss2-frogs-unit", true, frogged, w.tick)
		check("boss2-frog-8s", true, mouse.frogTicks > 230 and mouse.frogTicks <= 240, w.tick)
		run(w, 10)
		check("boss2-frog-no-attack", nil, mouse.target, w.tick)

		-- 06 swallows the hero whole
		local g = battle(1)
		quiet(g)
		local glutton = Battle.spawnEnemy(g, 106, 0, 150)
		tough(glutton)
		for _ = 1, 200 do
			Battle.step(g)
			if g.outcome then
				break
			end
		end
		check("boss6-instant-defeat", "Defeat", g.outcome, g.tick)

		-- 07 only takes hero damage
		local m = battle(1)
		quiet(m)
		local mirror = Battle.spawnEnemy(m, 107, 0, 400)
		local rabbit = Battle.spawnUnit(m, 2)
		rabbit.x = 300
		tough(rabbit)
		run(m, 90)
		check("boss7-units-cannot-target", 20000, mirror.hp, m.tick)
		m.mana = 100
		Battle.hero(m).x = 330
		Battle.step(m, { commands = { { kind = "Mace", slot = 1 } } })
		for _ = 1, 30 do
			Battle.step(m)
		end
		check("boss7-hero-hits", true, mirror.hp < 20000, m.tick)

		-- 09 kiss poisons for 2000/s but never below 1 HP
		local k = battle(1)
		quiet(k)
		local succubus = Battle.spawnEnemy(k, 109, 0, 300)
		tough(succubus)
		local h = Battle.hero(k)
		h.x = 120
		local poisoned = false
		for _ = 1, 150 do
			Battle.step(k)
			if h.poisonLeft > 0 then
				poisoned = true
				break
			end
		end
		check("boss9-poison", true, poisoned, k.tick)
		check("boss9-poison-2000", 2000, h.poisonDps, k.tick)
		run(k, 60)
		check("boss9-poison-floor", true, h.hp >= 1, k.tick)

		-- 05 blinks to x >= 400 untargetable
		local t = battle(1)
		quiet(t)
		local ghost = Battle.spawnEnemy(t, 105, 0, 200)
		tough(ghost)
		local wall2 = Battle.spawnUnit(t, 6)
		wall2.x = 150
		tough(wall2)
		local blinked = false
		for _ = 1, 30 * 120 do
			Battle.step(t)
			if ghost.state == "Blink" then
				blinked = true
				break
			end
		end
		check("boss5-blinks", true, blinked, t.tick)
		run(t, 31)
		check("boss5-lands-far", true, ghost.x >= 400, t.tick)

		-- 08 breath hits at most three
		local d = battle(1)
		quiet(d)
		local dragon = Battle.spawnEnemy(d, 108, 0, 300)
		tough(dragon)
		local mice = {}
		for i = 1, 5 do
			local u = Battle.spawnUnit(d, 6)
			u.x = 240 + i
			tough(u)
			table.insert(mice, u)
		end
		run(d, 40)
		local hurt = 0
		for _, u in mice do
			if u.hp < 1e9 then
				hurt += 1
			end
		end
		check("boss8-breath-max-3", true, hurt >= 1 and hurt <= 3, d.tick)
	end

	-- ------------------------------------------------ destiny (E04 §4-1)
	do
		local b = battle(3, { unitLevels = { 20, 20, 20, 20, 20, 20, 20, 20, 20 } })
		check("destiny-forced-level", 1, b.loadout.unitLevels[5], 0)
		check(
			"destiny-maces",
			"6,4,3",
			b.loadout.equip[1].num .. "," .. b.loadout.equip[2].num .. "," .. b.loadout.equip[3].num,
			0
		)
		check("destiny-hero-x", 45, Battle.hero(b).x, 0)
		check("destiny-spawn-x", 480, b.enemySpawnX, 0)
		b.food = 40
		local r = Battle.step(b, { commands = { { kind = "Summon", unit = 1 } } })
		check("destiny-no-normal-summon", "WrongMode", r.results[1].reason, b.tick)
		run(b, 30 * 3 - 1)
		local filled = 0
		for i = 1, 9 do
			if b.boxes[i] then
				filled += 1
			end
		end
		check("destiny-box-every-3s", 1, filled, b.tick)
		run(b, 30 * 3, { axis = 1 })
		check("destiny-hero-cannot-move", 45, Battle.hero(b).x, b.tick)
		local index = nil
		for i = 1, 9 do
			if b.boxes[i] then
				index = i
				break
			end
		end
		r = Battle.step(b, { commands = { { kind = "Box", index = index } } })
		check("destiny-box-opens", "Accepted", r.results[1].status, b.tick)
		check("destiny-box-consumed", nil, b.boxes[index], b.tick)
		b.rewards.killTotal = 60
		Battle.step(b)
		check("destiny-60-kills", "Victory", b.outcome, b.tick)
		local s = battle(3)
		local h = Battle.hero(s)
		h.hp, h.maxHp = 1e12, 1e12
		s.spawn.total = 60
		run(s, 30 * 20)
		local enemies = 0
		for _, id in s.order do
			if s.entities[id].kind == "Enemy" then
				enemies += 1
			end
		end
		check("destiny-spawn-stops-60", 0, enemies, s.tick)
	end

	-- ------------------------------------------------ wagon escort (E04 §4, D-WAGON-01)
	do
		local b = battle(6)
		quiet(b)
		local wagon = first(b, "Wagon")
		check("wagon-hp", 40000, wagon.maxHp, 0)
		check("wagon-start", -100, wagon.x, 0)
		run(b, 30)
		check("wagon-8px", "-92.000", string.format("%.3f", wagon.x), b.tick)
		local blocker = Battle.spawnEnemy(b, 12, 1, wagon.x + 125)
		tough(blocker)
		local x0 = wagon.x
		run(b, 30)
		check("wagon-blocked", x0, wagon.x, b.tick)
		blocker.hp = 0
		wagon.x = 869
		run(b, 5)
		check("wagon-victory", "Victory", b.outcome, b.tick)
		local d = battle(6)
		quiet(d)
		first(d, "Wagon").hp = 0
		Battle.step(d)
		check("wagon-lost-defeat", "Defeat", d.outcome, d.tick)
	end

	-- ------------------------------------------------ tower (E04 §4-2)
	do
		local b = battle(9)
		quiet(b)
		local guard = first(b, "Boss", 1)
		check(
			"tower-guard-boss1",
			true,
			guard ~= nil and guard.hold and guard.x == 420 and guard.line == 3,
			0
		)
		check("tower-hero-x32", 32, Battle.hero(b).x, 0)
		b.food = 40
		local r = Battle.step(b, { commands = { { kind = "Summon", unit = 1 } } })
		check("tower-summon-needs-lane", "InvalidPayload", r.results[1].reason, b.tick)
		r = Battle.step(b, { commands = { { kind = "Summon", unit = 1, lane = 2 } } })
		check("tower-summon-lane", "Accepted", r.results[1].status, b.tick)
		local mouse = first(b, "Unit", 1)
		check("tower-unit-lane", 2, mouse.line, b.tick)
		check("tower-speed-scale", "18.000", string.format("%.3f", mouse.speed), b.tick) -- 30 * 0.6
		check("tower-no-aura", false, mouse.aura, b.tick)
		mouse.x = 479.9
		Battle.step(b)
		check("tower-ally-scores", 1, b.points, b.tick)
		check("tower-ally-leaves", nil, b.entities[mouse.id], b.tick)
		local runner = Battle.spawnEnemy(b, 1, 1, 0.1, false, 4)
		Battle.step(b)
		check("tower-enemy-scores", 0, b.points, b.tick)
		local _ = runner
		b.mana = 100
		r = Battle.step(b, { commands = { { kind = "Mace", slot = 1, unit = 1 } } })
		check("tower-button0-90mp", "Accepted", r.results[1].status, b.tick)
		local lanes: { [number]: boolean } = {}
		for _, id in b.order do
			local e = b.entities[id]
			if e.kind == "Unit" then
				lanes[e.line] = true
			end
		end
		check(
			"tower-button0-all-lanes",
			true,
			lanes[1] and lanes[2] and lanes[3] and lanes[4] and lanes[5],
			b.tick
		)
		b.points = 14
		local m2 = Battle.spawnUnit(b, 1, 1)
		m2.x = 480
		Battle.step(b)
		check("tower-victory-15", "Victory", b.outcome, b.tick)
		local l = battle(9)
		quiet(l)
		l.points = -14
		Battle.spawnEnemy(l, 1, 1, 0.1, false, 1)
		Battle.step(l)
		check("tower-defeat-minus-15", "Defeat", l.outcome, l.tick)
	end

	-- ------------------------------------------------ revive (D-REVIVE-01/02)
	do
		local b = battle(1, nil, { revives = 1 })
		quiet(b)
		local h = Battle.hero(b)
		Battle.strike(b, nil, h, 1e6, false, false)
		Battle.step(b)
		check("revive-offered", true, b.reviveOffer, b.tick)
		check("revive-no-outcome", nil, b.outcome, b.tick)
		local tick = b.tick
		Battle.step(b)
		check("revive-paused", tick, b.tick, b.tick)
		local r = Battle.step(b, { commands = { { kind = "Revive" } } })
		check("revive-accepted", "Accepted", r.results[1].status, b.tick)
		check("revive-full-hp", h.maxHp, h.hp, b.tick)
		check("revive-full-food", b.stats.maxFood, b.food, b.tick)
		check("revive-invulnerable", true, h.invulnTicks > 290, b.tick)
		Battle.strike(b, nil, h, 1e6, false, false)
		check("revive-no-damage", h.maxHp, h.hp, b.tick)
		h.invulnTicks = 0
		Battle.strike(b, nil, h, 1e6, false, false)
		Battle.step(b)
		check("revive-once-then-defeat", "Defeat", b.outcome, b.tick)
		local t = battle(1, nil, { revives = 1 })
		quiet(t)
		Battle.strike(t, nil, Battle.hero(t), 1e6, false, false)
		run(t, 301)
		check("revive-timeout-defeat", "Defeat", t.outcome, t.tick)
	end

	-- ------------------------------------------------ determinism per mode
	do
		local function play(stage: number, seed: number): string
			local b = Battle.new({ stage = stage, seed = seed, loadout = loadout() })
			for t = 1, 30 * 60 do
				local commands: { any } = {}
				if t % 40 == 0 then
					table.insert(commands, { kind = "Summon", unit = 1 + t % 3, lane = 1 + t % 5 })
				end
				if t % 90 == 0 then
					table.insert(commands, { kind = "Box", index = 1 + t % 9 })
				end
				if #b.pendingPicks > 0 then
					table.insert(commands, { kind = "PickSkill", choice = 1 })
				end
				Battle.step(b, { commands = commands, axis = 1 })
			end
			return Battle.digest(b)
		end
		for _, stage in { 3, 6, 9, 12 } do
			check("determinism-stage-" .. stage, play(stage, 5), play(stage, 5), 1800)
		end
	end
end
