--!strict
-- R1 remake battle core: light-hero normal stages (docs/REMAKE_PLAN.md R1). Every expected value is
-- derived from the research specs cited next to it, not from running the engine.
return function(env: any, check: any)
	local Battle = env.Battle
	local Rules = env.Rules

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
	local function battle(stage: number?, over: { [string]: any }?, seed: number?): any
		return Battle.new({ stage = stage or 1, seed = seed or 12345, loadout = loadout(over) })
	end
	local function f3(v: number): string
		return string.format("%.3f", v)
	end
	local function run(b: any, ticks: number, input: any?)
		for _ = 1, ticks do
			Battle.step(b, input)
		end
	end
	local function quiet(b: any)
		b.spawn.need = math.huge -- no stage spawns
	end
	local function kinds(b: any, kind: string): { any }
		local list = {}
		for _, id in b.order do
			local e = b.entities[id]
			if e.kind == kind then
				table.insert(list, e)
			end
		end
		return list
	end

	-- ------------------------------------------------ resources (E04 §1-2..§1-4)
	do
		local b = battle()
		quiet(b)
		check("res-start-food", "0.000", f3(b.food), 0)
		check("res-start-mana", "0.000", f3(b.mana), 0)
		run(b, 30)
		check("res-food-2-per-sec", "2.000", f3(b.food), b.tick)
		check("res-mana-2-per-sec", "2.000", f3(b.mana), b.tick)
		local skilled = battle(1, { skills = { [9] = 2, [11] = 4, [12] = 1, [8] = 1 } })
		quiet(skilled)
		run(skilled, 30)
		check("res-farming-food", "4.000", f3(skilled.food), 30) -- 2 + 0.5*4
		check("res-prayer-mana", "3.000", f3(skilled.mana), 30) -- 2 + 0.5*2
		check("res-food-max", 80, skilled.stats.maxFood, 30) -- 40 + 40*1
		check("res-mana-max", 150, skilled.stats.maxMana, 30) -- 100 + 50*1
		local regen = battle(1, { skills = { [5] = 2 } })
		quiet(regen)
		Battle.hero(regen).hp = 1000
		run(regen, 149)
		check("res-hp-regen-wait", 1000, Battle.hero(regen).hp, regen.tick)
		run(regen, 1)
		check("res-hp-regen-5s", 1120, Battle.hero(regen).hp, regen.tick) -- 60*2 every 5 s
	end

	-- ------------------------------------------------ summon (E02 §5, E04 §1-1)
	do
		local b = battle()
		quiet(b)
		local r = Battle.step(b, { commands = { { kind = "Summon", unit = 1, requestId = "a" } } })
		check("summon-needs-food", "InsufficientFood", r.results[1].reason, b.tick)
		b.food = 30
		r = Battle.step(
			b,
			{ commands = { { kind = "Summon", unit = 1 }, { kind = "Summon", unit = 1 } } }
		)
		check("summon-accepted", "Accepted", r.results[1].status, b.tick)
		check("summon-cooldown", "Cooldown", r.results[2].reason, b.tick)
		check("summon-food-spent", "20.000", f3(b.food - 2 / 30), b.tick) -- 30 - 10, plus one tick of regen
		local mouse = kinds(b, "Unit")[1]
		check("summon-l1-hp", 100, mouse.maxHp, b.tick) -- level table L1, not base row 300 (E02 §1.4)
		check("summon-l1-ap", 20, mouse.ap, b.tick)
		check("summon-x0", true, mouse.x >= 0 and mouse.x < 2, b.tick)
		local locked = battle(1, { unitLevels = { 1, 0, 0, 0, 0, 0, 0, 0, 0 } })
		locked.food = 40
		r = Battle.step(locked, { commands = { { kind = "Summon", unit = 2 } } })
		check("summon-locked-unit", "InvalidPayload", r.results[1].reason, 1)
		local lead = battle(1, { skills = { [13] = 3 } })
		check("summon-leadership", "0.5", tostring(lead.stats.summonCooldownMul), 0) -- (6-3)/6
		local maxed = battle(1, { unitLevels = { 20, 1, 1, 1, 1, 1, 1, 1, 1 } })
		local m20 = Battle.spawnUnit(maxed, 1)
		check("unit-l20-hp", 200, m20.maxHp, 0)
		check("unit-l20-ap", 40, m20.ap, 0)
		check("unit5-is-monkey", 320, Battle.spawnUnit(maxed, 5).maxHp, 0) -- D-UNIT-56
		check("unit6-is-turtle", 4000, Battle.spawnUnit(maxed, 6).maxHp, 0)
	end

	-- ------------------------------------------------ enemy scaling (E04 §3-4)
	do
		local b = battle()
		local plain = Battle.spawnEnemy(b, 1, 1, 500)
		check("enemy-hp", 130, plain.maxHp, 0)
		local strong = Battle.spawnEnemy(b, 21, 1, 500)
		check("enemy-enhanced-hp", "169.000", f3(strong.maxHp), 0) -- x1.3
		local giant = Battle.spawnEnemy(b, 1, 3, 500, true)
		check("enemy-giant-hp", "429.000", f3(giant.maxHp), 0) -- x3.3
		check("enemy-giant-speed", "36.000", f3(giant.speed), 0) -- scale 1.2 on move speed only
		local hard = battle(1, { difficulty = 2 })
		check("enemy-hard-hp", "182.000", f3(Battle.spawnEnemy(hard, 1, 1, 500).maxHp), 0)
		check("castle-hard-hp", "4200.000", f3(Battle.castle(hard).maxHp), 0)
		local hell = battle(1, { difficulty = 3 })
		check("castle-hell-hp-x1", "3000.000", f3(Battle.castle(hell).maxHp), 0)
		local boss = Battle.spawnEnemy(b, 101, 1, 500)
		check("boss-row", "Boss", boss.kind, 0)
		check("boss-hp", 15000, boss.maxHp, 0)
	end

	-- ------------------------------------------------ damage and aura (E02 §2.1, E03 §5)
	do
		local b = battle(1, { skills = { [15] = 2, [16] = 3 } })
		quiet(b)
		local h = Battle.hero(b)
		local mouse = Battle.spawnUnit(b, 1)
		mouse.x = h.x + 10
		local far = Battle.spawnUnit(b, 1)
		far.x = h.x + 400
		run(b, 1)
		check("aura-near", true, mouse.aura, b.tick)
		check("aura-far", false, far.aura, b.tick)
		check("aura-count", 1, b.auraCount, b.tick)
		local enemy = Battle.spawnEnemy(b, 21, 1, 900)
		local hp0 = enemy.hp
		Battle.strike(b, mouse, enemy, mouse.ap, false, mouse.aura)
		check("damage-war-aura", "32.000", f3(hp0 - enemy.hp), b.tick) -- 20 * (1 + 0.3*2)
		local before = mouse.hp
		Battle.strike(b, enemy, mouse, 10, false, false)
		check("damage-defense-aura", "7.000", f3(before - mouse.hp), b.tick) -- 10 * (1 - 0.1*3)
		local skillHit = Battle.spawnEnemy(b, 1, 1, 900)
		skillHit.hp, skillHit.maxHp = 1000, 1000
		Battle.strike(b, mouse, skillHit, mouse.ap, true, false)
		check("damage-mouse-skill-x3", "940.000", f3(skillHit.hp), b.tick) -- 20 * fSkDmg 3
		local def = battle(1, { skills = { [7] = 2 } })
		local dh = Battle.hero(def)
		Battle.strike(def, nil, dh, 100, false, false)
		check("damage-hero-defense", "1920.000", f3(dh.hp), 0) -- 2000 - 100*0.8
	end

	-- ------------------------------------------------ allied units only use skills inside the aura
	do
		local b = battle()
		quiet(b)
		local penguin = Battle.spawnUnit(b, 8) -- fSkPct 100
		local enemy = Battle.spawnEnemy(b, 12, 1, 0) -- stone golem: AP 0, stands still once engaged
		enemy.hp, enemy.maxHp = 1e9, 1e9
		penguin.x = 700
		enemy.x = 750
		local skills, attacks = 0, 0
		for _ = 1, 300 do
			Battle.step(b)
			if penguin.state == "Skill" and penguin.stateTicks == 1 then
				skills += 1
			elseif penguin.state == "Attack" and penguin.stateTicks == 1 then
				attacks += 1
			end
		end
		check("aura-outside-no-skill", 0, skills, b.tick)
		check("aura-outside-attacks", true, attacks > 0, b.tick)
		local near = battle()
		quiet(near)
		local p2 = Battle.spawnUnit(near, 8)
		local e2 = Battle.spawnEnemy(near, 12, 1, 0)
		e2.hp, e2.maxHp = 1e9, 1e9
		p2.x, e2.x = 120, 170
		local s2, a2 = 0, 0
		for _ = 1, 300 do
			Battle.step(near)
			if p2.state == "Skill" and p2.stateTicks == 1 then
				s2 += 1
			elseif p2.state == "Attack" and p2.stateTicks == 1 then
				a2 += 1
			end
		end
		check("aura-inside-always-skill", true, s2 > 0 and a2 == 0, near.tick)
	end

	-- ------------------------------------------------ kill rewards (E04 §2-2)
	do
		local b = battle()
		quiet(b)
		local e = Battle.spawnEnemy(b, 1, 1, 500)
		Battle.strike(b, nil, e, 1000, false, false)
		check("reward-gold", 18, b.rewards.gold, 0)
		check("reward-exp", 12, b.exp, 0)
		local cleared = Battle.new({ stage = 1, seed = 1, loadout = loadout(), cleared = true })
		Battle.strike(cleared, nil, Battle.spawnEnemy(cleared, 1, 1, 500), 1000, false, false)
		check("reward-cleared-half", 9, cleared.rewards.gold, 0)
		local easy = battle(1, { difficulty = 0, skills = { [2] = 1 } })
		Battle.strike(easy, nil, Battle.spawnEnemy(easy, 1, 1, 500), 1000, false, false)
		check("reward-easy-merchant", 43, easy.rewards.gold, 0) -- 18*2 = 36, +20% -> 43.2
		check("reward-easy-exp", 18, easy.exp, 0) -- 12 * 1.5
		local late = battle()
		late.tick = 27000
		Battle.strike(late, nil, Battle.spawnEnemy(late, 1, 1, 500), 1000, false, false)
		check("reward-15min-gold", 1, late.rewards.gold, late.tick)
		check("reward-15min-exp", 0, late.exp, late.tick)
		check("reward-kill-count", 1, b.rewards.kills.e1, 0)
	end

	-- ------------------------------------------------ spawner (E04 §3)
	do
		local b = battle(1)
		Battle.hero(b).hp, Battle.hero(b).maxHp = 1e12, 1e12
		Battle.castle(b).hp = 1e12
		local first: number? = nil
		local ids: { string } = {}
		local seen: { [number]: boolean } = {}
		for _ = 1, 30 * 120 do
			Battle.step(b)
			for _, id in b.order do
				local e = b.entities[id]
				if (e.kind == "Enemy" or e.kind == "Boss") and not seen[id] then
					seen[id] = true
					first = first or b.tick
					table.insert(ids, (if e.enhanced then "+" else "") .. e.n)
				end
			end
			if #ids >= 20 then
				break
			end
		end
		check(
			"spawn-first-in-5s-band",
			true,
			first ~= nil and first >= 150 and first <= 177,
			first or -1
		)
		local plain = 0
		for i = 1, 19 do
			if ids[i] == "1" then
				plain += 1
			end
		end
		check("spawn-1-1-plain-first-19", 19, plain, b.tick)
		check("spawn-1-1-special-20th", "+1", ids[20], b.tick) -- U5=21 every P5+1=20 spawns
	end

	-- ------------------------------------------------ castle 50% rush (E04 §3-5)
	do
		local b = battle(7) -- 1-7: U3 = 1, U2 = 21
		quiet(b)
		local c = Battle.castle(b)
		c.hp = c.maxHp * 0.49
		local giants, enhancedGiants = 0, 0
		local seen: { [number]: boolean } = {}
		for _ = 1, 30 * 12 do
			Battle.step(b)
			for _, id in b.order do
				local e = b.entities[id]
				if e.kind == "Enemy" and not seen[id] then
					seen[id] = true
					if e.giant then
						giants += 1
						if e.enhanced then
							enhancedGiants += 1
						end
					end
				end
			end
		end
		check("rush-ten-giants", 10, giants, b.tick)
		check("rush-five-from-u2", 5, enhancedGiants, b.tick)
	end

	-- ------------------------------------------------ weapons (E03 §3.1)
	do
		local b = battle(1, {
			equip = {
				[1] = { num = 1, grade = 0 },
				[2] = { num = 2, grade = 0 },
				[3] = { num = 9, grade = 10 },
			},
		})
		quiet(b)
		local r = Battle.step(b, { commands = { { kind = "Mace", slot = 1 } } })
		check("mace-needs-mana", "InsufficientMana", r.results[1].reason, b.tick)
		b.mana = 100
		r = Battle.step(b, { commands = { { kind = "Mace", slot = 1 } } })
		check("mace-accepted", "Accepted", r.results[1].status, b.tick)
		check("mace-cost-10", "90.067", f3(b.mana), b.tick) -- 100 - 10 + one tick of regen
		r = Battle.step(b, { commands = { { kind = "Mace", slot = 2 } } })
		check("mace-busy", "Busy", r.results[1].reason, b.tick)
		run(b, 10)
		local fist = nil
		for _, id in b.objectOrder do
			fist = b.objects[id]
		end
		check("fist-projectile", 268, fist and fist.row, b.tick)
		check("fist-pierce", 3, fist and fist.maxPierce, b.tick)
		check("fist-damage", 80, fist and fist.ap, b.tick)
		run(b, 20)
		local h = Battle.hero(b)
		h.hp = 100
		b.mana = 100
		Battle.step(b, { commands = { { kind = "Mace", slot = 2 } } })
		run(b, 10)
		check("mace-heal", 700, h.hp, b.tick) -- +600
		run(b, 20)
		b.food = 0
		Battle.step(b, { commands = { { kind = "Mace", slot = 3 } } })
		run(b, 10)
		check("mace-food", true, b.food >= 7 and b.food < 8, b.tick) -- int(4 + 0.3*10) = 7
		local master =
			battle(1, { skills = { [10] = 2, [22] = 3 }, equip = { [1] = { num = 7, grade = 4 } } })
		check("mace-grade-mastery", 7, Rules.maceGrade(master.loadout, 1, false), 0)
		check("mace-grade-destiny", 4, Rules.maceGrade(master.loadout, 1, true), 0)
		check("mace-cost-magic-master", 44, Rules.maceCost(master.loadout, 7, 7), 0) -- int(55 * 0.8)
	end

	-- ------------------------------------------------ unit behaviours (E02 §4.3-§4.4)
	do
		local b = battle()
		quiet(b)
		local kanga = Battle.spawnUnit(b, 4)
		local wall = Battle.spawnEnemy(b, 12, 1, 0)
		wall.hp, wall.maxHp = 1e9, 1e9
		kanga.x, wall.x = 100, 150
		kanga.aura = true
		local fists = 0
		for _ = 1, 600 do
			local before = wall.hp
			Battle.step(b)
			if math.abs(before - wall.hp - 12) < 1e-6 then
				fists += 1 -- each fist is AP 20 x fSkDmg 0.6 = 12; plain hits deal 20
			end
			if fists >= 5 then
				break
			end
		end
		check("kangaroo-five-fists", 5, fists, b.tick)

		local t = battle()
		quiet(t)
		local turtle = Battle.spawnUnit(t, 6)
		local zombie = Battle.spawnEnemy(t, 1, 1, 0)
		turtle.x, zombie.x = 600, 640
		zombie.hp, zombie.maxHp = 1e6, 1e6
		run(t, 60)
		check("turtle-waits", "Wait", turtle.state, t.tick)
		check("turtle-deals-nothing", 1e6, zombie.hp, t.tick)

		local bomb = battle()
		quiet(bomb)
		local mouse = Battle.spawnUnit(bomb, 1)
		mouse.hp, mouse.maxHp = 1e5, 1e5
		mouse.x = 600
		local bomber = Battle.spawnEnemy(bomb, 17, 1, 640)
		local exploded = false
		for _ = 1, 200 do
			Battle.step(bomb)
			if not bomb.entities[bomber.id] then
				exploded = true
				break
			end
		end
		check("bomber-self-destructs", true, exploded, bomb.tick)
		check("bomber-3000-damage", true, mouse.hp <= 1e5 - 3000 + 0.001, bomb.tick)
		check("bomber-no-reward", 0, bomb.rewards.gold, bomb.tick)

		local loop = battle()
		quiet(loop)
		local runner = Battle.spawnEnemy(loop, 1, 1, 2)
		Battle.hero(loop).x = 800
		run(loop, 3)
		check("enemy-loops-left-edge", true, runner.x > 1000, loop.tick)

		local fall = battle()
		quiet(fall)
		local unit = Battle.spawnUnit(fall, 3)
		local hitter = Battle.spawnEnemy(fall, 1, 1, 500)
		unit.hp = unit.maxHp * 0.25
		Battle.strike(fall, hitter, unit, unit.maxHp * 0.1, false, false)
		check("ally-falls-at-20pct", "Knock", unit.state, 0)
	end

	-- ------------------------------------------------ status effects and lobs (E02 §3.3-§3.4, §4.4)
	do
		local b = battle()
		quiet(b)
		local target = Battle.spawnEnemy(b, 1, 1, 400)
		target.hp, target.maxHp = 1e6, 1e6
		local penguin = Battle.spawnUnit(b, 8)
		penguin.x = 300
		penguin.target = target.id
		penguin.aura = true
		-- fire a skill ice shard directly at the release frame
		penguin.state, penguin.stateTicks, penguin.stateLimit =
			"Skill", penguin.skillFrame - 1, penguin.skillAnim
		local frozenAt: number? = nil
		for _ = 1, 30 do
			Battle.step(b)
			if target.state == "Ice" then
				frozenAt = b.tick
				break
			end
		end
		check("ice-skill-freezes", true, frozenAt ~= nil, b.tick)
		run(b, 89)
		check("ice-3s-held", "Ice", target.state, b.tick)
		run(b, 2)
		check("ice-3s-ends", true, target.state ~= "Ice", b.tick)

		local p = battle()
		quiet(p)
		local victim = Battle.spawnEnemy(p, 1, 1, 900)
		victim.hp = 150
		victim.poisonDps, victim.poisonLeft = 80, 10
		run(p, 30)
		check("poison-1s", 70, victim.hp, p.tick)
		run(p, 30)
		check("poison-floor-1", 1, victim.hp, p.tick)
		run(p, 30 * 9)
		check("poison-ends-alive", true, Battle.alive(victim), p.tick)

		local g = battle()
		quiet(g)
		local ghost = Battle.spawnEnemy(g, 9, 1, 600)
		local wallUnit = Battle.spawnUnit(g, 6)
		wallUnit.x = 580
		wallUnit.hp, wallUnit.maxHp = 1e6, 1e6
		run(g, 2)
		check("ghost-first-contact", "Ghost", ghost.state, g.tick)
		check(
			"ghost-untargetable",
			nil,
			(function()
				local arrow = Battle.spawnUnit(g, 1)
				arrow.x = ghost.x - 10
				return nil
			end)(),
			g.tick
		)
		local startX = ghost.ghostX
		for _ = 1, 300 do
			Battle.step(g)
			if ghost.state ~= "Ghost" then
				break
			end
		end
		check(
			"ghost-advances-150",
			true,
			math.abs(startX - ghost.x) >= 150 and math.abs(startX - ghost.x) < 152,
			g.tick
		)
		check("ghost-once", true, ghost.ghostUsed, g.tick)

		local m = battle()
		quiet(m)
		local monkey = Battle.spawnUnit(m, 5)
		monkey.x = 300
		local a1 = Battle.spawnEnemy(m, 1, 1, 400)
		local a2 = Battle.spawnEnemy(m, 1, 1, 420)
		a1.hp, a1.maxHp, a2.hp, a2.maxHp = 1e6, 1e6, 1e6, 1e6
		monkey.target = a1.id
		monkey.state, monkey.stateTicks, monkey.stateLimit =
			"Attack", monkey.atkFrame - 1, monkey.atkAnim
		Battle.step(m)
		local landTick = m.tick + 15
		run(m, 14)
		check("bomb-in-flight", 1e6, a1.hp, m.tick)
		run(m, 1)
		check("bomb-lands-0.5s", landTick, m.tick, m.tick)
		check("bomb-area-hits-both", true, a1.hp < 1e6 and a2.hp < 1e6, m.tick)
	end

	-- ------------------------------------------------ hero movement and area maces (E03 §1.3-§1.4, §3.1)
	do
		local b = battle(1, { skills = { [6] = 2 } })
		quiet(b)
		local h = Battle.hero(b)
		run(b, 30, { axis = 1 })
		check("hero-speed-100", "200.000", f3(h.x), b.tick) -- 100 + (60 + 20*2) px/s
		run(b, 30 * 20, { axis = 1 })
		check("hero-stops-before-castle", "864.000", f3(h.x), b.tick)
		run(b, 30 * 30, { axis = -1 })
		check("hero-left-bound", "-40.000", f3(h.x), b.tick)

		local w = battle(1, {
			equip = {
				[1] = { num = 8, grade = 0 },
				[2] = { num = 3, grade = 0 },
				[3] = { num = 6, grade = 0 },
			},
		})
		quiet(w)
		w.mana = 100
		local wh = Battle.hero(w)
		local near = Battle.spawnEnemy(w, 1, 1, wh.x + 100)
		near.hp, near.maxHp = 1e6, 1e6
		Battle.step(w, { commands = { { kind = "Mace", slot = 1 } } })
		run(w, 8)
		check("wind-knocks", "Knock", near.state, w.tick)
		run(w, 20)
		local fireTarget = Battle.spawnEnemy(w, 1, 1, wh.x + 150)
		fireTarget.hp, fireTarget.maxHp = 1e6, 1e6
		w.mana = 100
		Battle.step(w, { commands = { { kind = "Mace", slot = 3 } } })
		run(w, 8)
		check("fire-damage-80", "999920.000", f3(fireTarget.hp), w.tick)
		run(w, 20)
		local undead = Battle.spawnEnemy(w, 1, 1, wh.x + 250)
		undead.hp, undead.maxHp = 1e6, 1e6
		w.mana = 100
		Battle.step(w, { commands = { { kind = "Mace", slot = 2 } } })
		run(w, 8)
		check("turn-undead-hits", true, undead.hp < 1e6 or not Battle.alive(undead), w.tick)
	end

	-- ------------------------------------------------ enemy ranged attacks and gold/poison weapons
	do
		local b = battle()
		quiet(b)
		local skeleton = Battle.spawnEnemy(b, 2, 1, 400)
		local mouse = Battle.spawnUnit(b, 1)
		mouse.x = 320
		mouse.hp, mouse.maxHp = 1e6, 1e6
		local bone = false
		for _ = 1, 120 do
			Battle.step(b)
			for _, id in b.objectOrder do
				if b.objects[id].row == 295 and b.objects[id].team == 2 then
					bone = true
				end
			end
			if bone then
				break
			end
		end
		check("skeleton-throws-bone", true, bone, b.tick)
		check("skeleton-holds-range", true, skeleton.x > mouse.x + 50, b.tick)

		local g =
			battle(1, { equip = { [1] = { num = 11, grade = 0 }, [2] = { num = 10, grade = 0 } } })
		quiet(g)
		g.goldAvailable = 999
		local r = Battle.step(g, { commands = { { kind = "Mace", slot = 1 } } })
		check("gold-weapon-needs-gold", "InsufficientGold", r.results[1].reason, g.tick)
		g.goldAvailable = 1000
		r = Battle.step(g, { commands = { { kind = "Mace", slot = 1 } } })
		check("gold-weapon-spends-1000", 1000, g.rewards.goldSpent, g.tick)
		run(g, 20)
		local victim = Battle.spawnEnemy(g, 1, 1, Battle.hero(g).x + 60)
		victim.hp, victim.maxHp = 1e6, 1e6
		g.mana = 100
		Battle.step(g, { commands = { { kind = "Mace", slot = 2 } } })
		for _ = 1, 40 do
			Battle.step(g)
			if victim.poisonLeft > 0 then
				break
			end
		end
		check("poison-weapon-80dps", 80, victim.poisonDps, g.tick)
	end

	-- ------------------------------------------------ outcome (E04 §4)
	do
		local b = battle()
		quiet(b)
		Battle.castle(b).hp = 0
		Battle.step(b)
		check("outcome-victory", "Victory", b.outcome, b.tick)
		local d = battle()
		quiet(d)
		Battle.hero(d).hp = 0
		Battle.castle(d).hp = 0
		Battle.step(d)
		check("outcome-same-tick-defeat", "Defeat", d.outcome, d.tick)
		local r = Battle.step(d, { commands = { { kind = "Summon", unit = 1 } } })
		check("outcome-rejects-commands", "WrongPhase", r.results[1].reason, d.tick)
	end

	-- ------------------------------------------------ level-up choice (E03 §4.1, D-LVUP-01)
	do
		local b = battle()
		quiet(b)
		Battle.strike(b, nil, Battle.spawnEnemy(b, 101, 1, 500), 1e9, false, false) -- boss: 50 EXP
		Battle.strike(b, nil, Battle.spawnEnemy(b, 101, 1, 500), 1e9, false, false)
		Battle.step(b)
		local tick = b.tick
		check("levelup-level", 2, b.level, tick)
		check("levelup-offer-3", 3, b.offer and #b.offer, tick)
		local digest = Battle.digest(b)
		Battle.snapshot(b)
		check("levelup-snapshot-pure", digest, Battle.digest(b), tick)
		Battle.step(b)
		check("levelup-paused", tick, b.tick, b.tick)
		local chosen = b.offer[2]
		local r = Battle.step(b, { commands = { { kind = "PickSkill", choice = 2 } } })
		check("levelup-pick", "Accepted", r.results[1].status, b.tick)
		check("levelup-applied", 1, b.loadout.skills[chosen], b.tick)
		check("levelup-resumes", tick + 1, b.tick, b.tick)
		local fives = Battle.new({ stage = 1, seed = 9, loadout = loadout({ level = 4 }) })
		local offer = Battle.candidates(fives, 5)
		check("levelup-5th-fixed", "11,9,19", table.concat(offer, ","), 0)
	end

	-- ------------------------------------------------ determinism
	do
		local function play(seed: number): string
			local b = battle(2, { unitLevels = { 5, 3, 1, 1, 1, 1, 1, 1, 1 } }, seed)
			for t = 1, 30 * 90 do
				local commands: { any } = {}
				if t % 45 == 0 then
					table.insert(commands, { kind = "Summon", unit = if t % 90 == 0 then 2 else 1 })
				end
				if t % 200 == 0 then
					table.insert(commands, { kind = "Mace", slot = 1 })
				end
				if #b.pendingPicks > 0 then
					table.insert(commands, { kind = "PickSkill", choice = 1 })
				end
				Battle.step(b, { commands = commands, axis = if t % 300 < 150 then 1 else 0 })
			end
			return Battle.digest(b) .. "/" .. b.rewards.killTotal
		end
		local a, again = play(777), play(777)
		check("determinism-same-seed", a, again, 2700)
		check("determinism-other-seed", true, play(778) ~= a, 2700)
	end
end
