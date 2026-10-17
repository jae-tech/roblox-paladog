--!strict
-- R4 remake client (pure modules): controller requests and authority, snapshot validation/interpolation,
-- input routing and UI text. Runs in the Luau CLI and the Studio client harness.
return function(env: any, check: any)
	local Protocol, Controller, Buffer, Router, Text, catalog =
		env.Protocol,
		env.ClientController,
		env.SnapshotBuffer,
		env.ActionRouter,
		env.Text,
		env.catalog
	local function controller()
		local sent: { any } = {}
		local serial = 0
		local c = Controller.new({
			protocol = Protocol,
			send = function(channel: string, payload: any)
				table.insert(sent, { channel = channel, payload = payload })
			end,
			requestId = function()
				serial += 1
				return string.format("client-request-%06d", serial)
			end,
		})
		return c, sent
	end
	local function boot(c: any, extra: { [string]: any }?)
		local payload: { [string]: any } = {
			protocolVersion = Protocol.VERSION,
			balanceHash = Protocol.BALANCE_HASH,
			status = "Ready",
			storage = "ServerMemory",
			phase = "LobbyReady",
			profileRevision = 1,
			profileSummary = {
				currentSlot = 1,
				gems = 0,
				slots = { { heroKind = "light", units = { 1 } } :: any, false, false },
			},
		}
		local overrides: { [string]: any } = extra or {}
		for k, v in overrides do
			payload[k] = v
		end
		return c.finishBootstrap(c.beginBootstrap(0), payload, 0)
	end
	local function battleView(tick: number, heroX: number): any
		return {
			tick = tick,
			mode = "Normal",
			food = 10,
			mana = 5,
			maxFood = 40,
			maxMana = 100,
			heroSpeed = 60,
			heroMinX = -40,
			heroMaxX = 864,
			summonPast = { 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000 },
			level = 1,
			exp = 0,
			gold = 0,
			kills = 0,
			points = 0,
			boxes = {},
			entities = {
				{
					id = 1,
					kind = "Hero",
					n = 0,
					team = 1,
					x = heroX,
					y = 165,
					dir = 1,
					hp = 2000,
					maxHp = 2000,
					state = "Idle",
				},
				{
					id = 2,
					kind = "Castle",
					n = 11,
					team = 2,
					x = 904,
					y = 145,
					dir = -1,
					hp = 3000,
					maxHp = 3000,
					state = "Idle",
				},
			},
			objects = {},
		}
	end
	local function snapshot(
		matchId: string,
		seq: number,
		tick: number,
		heroX: number,
		phase: string?
	): any
		return {
			matchId = matchId,
			snapshotSeq = seq,
			phase = phase or "Running",
			stage = 1,
			balanceHash = Protocol.BALANCE_HASH,
			inputAckSeq = 0,
			commandAckSeq = 0,
			battle = battleView(tick, heroX),
		}
	end

	-- ------------------------------------------------ bootstrap and storage loss (moved from P8)
	do
		local c = controller()
		check("boot-ready", true, boot(c), 0)
		check("boot-lobby", "LobbyReady", c.model(0).phase, 0)
		local m = controller()
		m.finishBootstrap(
			m.beginBootstrap(0),
			{ protocolVersion = 1, balanceHash = "x", status = "Ready" },
			0
		)
		check("boot-mismatch-unavailable", "Unavailable", m.model(0).phase, 0)
		check("boot-mismatch-no-retry", false, m.needsBootstrap(5), 5)
		local offline = controller()
		offline.finishBootstrap(offline.beginBootstrap(0), {
			protocolVersion = Protocol.VERSION,
			balanceHash = Protocol.BALANCE_HASH,
			status = "Unavailable",
		}, 0)
		check("client-storage-loss-disables-play", "Unavailable", offline.model(0).phase, 0)
		check("client-storage-loss-retries", true, offline.needsBootstrap(2), 2)
	end

	-- ------------------------------------------------ lobby requests
	do
		local c, sent = controller()
		boot(c)
		check("lobby-send", true, c.lobby("UpgradeUnit", { unit = 2 }, 0), 0)
		local last = sent[#sent].payload
		check("lobby-payload-kind", "UpgradeUnit", last.kind, 0)
		check("lobby-payload-revision", 1, last.expectedRevision, 0)
		check("lobby-payload-valid", true, (Protocol.validateCommand(last)) ~= nil, 0)
		check("lobby-one-in-flight", false, c.lobby("UpgradeUnit", { unit = 2 }, 0.1), 0)
		check("lobby-busy-flag", true, c.model(0.1).busy, 0)
		c.receiveMessage({
			requestId = last.requestId,
			status = "Committed",
			profileRevision = 2,
			profileSummary = { currentSlot = 1, slots = {}, gems = 0 },
		}, 0.2)
		check("lobby-released", false, c.model(0.2).busy, 0)
		check("lobby-revision-applied", 2, c.model(0.2).profileRevision, 0)
		check("lobby-next-ok", true, c.lobby("LearnSkill", { skill = 4 }, 0.3), 0)
		local rejected = sent[#sent].payload
		c.receiveMessage(
			{ requestId = rejected.requestId, status = "Rejected", reason = "NoPoints" },
			0.4
		)
		check("lobby-reason-shown", "NoPoints", c.model(0.5).reason, 0)
		check("lobby-reason-expires", nil, c.model(4).reason, 4)
	end

	-- ------------------------------------------------ start, battle commands, settle
	do
		local c, sent = controller()
		boot(c)
		check("start-sent", true, c.start(1, 0), 0)
		check("start-preparing", "Preparing", c.model(0).phase, 0)
		local startId = sent[#sent].payload.requestId
		check(
			"start-payload-valid",
			true,
			(Protocol.validateCommand(sent[#sent].payload)) ~= nil,
			0
		)
		c.receiveMessage(
			{ requestId = startId, status = "Committed", matchId = "m1", profileRevision = 2 },
			0.1
		)
		check("start-running", "Running", c.model(0.1).phase, 0)
		check("battle-needs-snapshot", false, c.battle("Summon", { unit = 1 }, 0.2), 0)
		check("snapshot-accepted", true, c.receiveSnapshot(snapshot("m1", 1, 3, 100), 0.2), 0)
		check(
			"snapshot-foreign-rejected",
			false,
			c.receiveSnapshot(snapshot("m2", 2, 6, 100), 0.21),
			0
		)
		check("battle-summon", true, c.battle("Summon", { unit = 3 }, 0.25), 0)
		local summon = sent[#sent].payload
		check("battle-seq-1", 1, summon.commandSeq, 0)
		check("battle-lane-filled", 0, summon.lane, 0)
		check("battle-payload-valid", true, (Protocol.validateCommand(summon)) ~= nil, 0)
		check("battle-mace", true, c.battle("Mace", { slot = 2 }, 0.26), 0)
		local mace = sent[#sent].payload
		check("battle-mace-valid", true, (Protocol.validateCommand(mace)) ~= nil, 0)
		check("battle-unknown-kind", false, c.battle("GrantGold", nil, 0.27), 0)
		check("battle-stale-view-refused", false, c.battle("Summon", { unit = 1 }, 1.0), 1)
		-- prediction leads the hero by unacknowledged input, bounded to 0.15 s of motion
		c.receiveSnapshot(snapshot("m1", 2, 6, 100), 1.0)
		c.move(1, 1.0)
		local f = c.frame(1.1)
		local hero = nil
		for _, e in f.entities do
			if e.kind == "Hero" then
				hero = e
			end
		end
		check("predict-ahead", true, hero.x > 100 and hero.x <= 100 + 60 * 0.15 + 1e-6, 1)
		c.receiveSnapshot(snapshot("m1", 3, 9, 100, "Settled"), 1.2)
		check("settled-phase", "Settled", c.model(1.2).phase, 1)
		check("return-sent", true, c.returnToLobby(1.3), 1)
		local back = sent[#sent].payload
		c.receiveMessage(
			{ requestId = back.requestId, status = "Accepted", profileRevision = 3 },
			1.4
		)
		check("return-lobby", "LobbyReady", c.model(1.4).phase, 1)
		check("return-match-cleared", nil, c.model(1.4).matchId, 1)
	end

	-- ------------------------------------------------ snapshot buffer validation and interpolation
	do
		local b = Buffer.new(Protocol.BALANCE_HASH)
		b.setMatch("m1")
		local bad = snapshot("m1", 1, 3, 100)
		bad.battle.entities[1].hp = 0 / 0
		check("buffer-rejects-nan", false, b.accept(bad, 0), 0)
		local huge = snapshot("m1", 1, 3, 100)
		for i = 3, 400 do
			huge.battle.entities[i] = { id = i, kind = "Enemy", x = 1, hp = 1, maxHp = 1 }
		end
		check("buffer-rejects-oversize", false, b.accept(huge, 0), 0)
		local dupe = snapshot("m1", 1, 3, 100)
		dupe.battle.entities[2].id = 1
		check("buffer-rejects-duplicate-id", false, b.accept(dupe, 0), 0)
		check("buffer-accepts", true, b.accept(snapshot("m1", 1, 3, 100), 0), 0)
		check("buffer-rejects-old-seq", false, b.accept(snapshot("m1", 1, 6, 120), 0.1), 0)
		check("buffer-accepts-next", true, b.accept(snapshot("m1", 2, 6, 130), 0.1), 0)
		local mid = b.frame(0.15) -- rendered 0.1 s behind: halfway between ticks 3 and 6
		local x = 0
		for _, e in mid.entities do
			if e.kind == "Hero" then
				x = e.x
			end
		end
		check("buffer-interpolates-between", true, x > 100 and x < 130, 0)
	end

	-- ------------------------------------------------ input router
	do
		local actions: { string } = {}
		local r = Router.new({
			onAxis = function(_: number) end,
			onAction = function(action: string)
				table.insert(actions, action)
			end,
		})
		r.begin("Summon9", "k9")
		r.begin("Mace3", "ke")
		r.begin("Cast", "kq")
		check("router-summon9", "Summon9", actions[1], 0)
		check("router-mace3", "Mace3", actions[2], 0)
		check("router-unknown-ignored", 2, #actions, 0)
		r.setBlocked("modal", true)
		r.begin("Summon1", "k1")
		check("router-blocked", 2, #actions, 0)
	end

	-- ------------------------------------------------ UI text
	do
		check("text-stage-label", "2-1", Text.stageLabel(25), 0)
		check("text-item-name", "빛의 주먹 +3", Text.itemName(catalog, Text.encode(1, 1, 3)), 0)
		check(
			"text-weapon-desc",
			"전방 관통 탄 140 피해 · 마나 10",
			Text.itemDescription(catalog, Text.encode(1, 1, 3)),
			0
		)
		check(
			"text-ring-desc",
			"최대 체력 +1000",
			Text.itemDescription(catalog, Text.encode(2, 4, 2)),
			0
		)
		local price, currency = Text.buyPrice(catalog, 1, 2)
		check("text-weapon-price", "500/gold", tostring(price) .. "/" .. currency, 0)
		local gearPrice, gearCurrency = Text.buyPrice(catalog, 3, 7)
		check("text-gear-price", "200/gems", tostring(gearPrice) .. "/" .. gearCurrency, 0)
		check("text-gold-weapon-unsold", nil, (Text.buyPrice(catalog, 1, 11)), 0)
		check("text-sale-half", 250, Text.saleValue(catalog, Text.encode(1, 2, 0)), 0)
		check("text-enchant-cost", 8, Text.enchantCost(Text.encode(1, 1, 3)), 0)
		check(
			"text-quest-1-1-sub2",
			"생쥐 창병 10회 이상 소환",
			Text.questText(catalog, "light", catalog.stages[1].quests[3]),
			0
		)
		check(
			"text-quest-time",
			"5분 20초 안에 승리",
			Text.questText(catalog, "light", catalog.stages[1].quests[2]),
			0
		)
		check(
			"text-quest-reward-item",
			true,
			string.find(Text.questReward(catalog, catalog.stages[3].quests[3]), "빛의 주먹")
				~= nil,
			0
		)
		check(
			"text-cooldown-leadership",
			"0.5",
			tostring(Text.cooldownLeft(catalog, "light", 1, 3, 0)),
			0
		)
		check("text-reason", "식량이 부족합니다", Text.reason("InsufficientFood"), 0)
		check("text-number", "1,234,567", Text.number(1234567), 0)
	end
	-- Regression: Studio portrait 390px produced a -6px summon strip and negative button widths.
	check("hud-responsive-plan-present", true, env.HudLayout ~= nil, 0)
	if env.HudLayout then
		for _, width in { 320, 360, 390, 640, 844, 900, 1072 } do
			local p = env.HudLayout.plan(width)
			check("hud-unit-width-positive-" .. width, true, p.unitWidth > 0, 0)
			check("hud-unit-button-minimum-" .. width, true, p.unitButtonWidth >= 48, 0)
			check("hud-controls-separated-" .. width, true, p.weaponX >= p.moveSize * 2 + 8, 0)
			check(
				"hud-weapons-in-bounds-" .. width,
				true,
				p.weaponX + p.weaponWidth * 3 + 8 <= width - 16,
				0
			)
			-- touch avatar combat keeps the jump button corner (110 px) clear where the screen allows
			local r = env.HudLayout.plan(width, 110)
			check(
				"hud-jump-corner-clear-" .. width,
				true,
				(width < 640 or r.weaponX + r.weaponWidth * 3 + 8 <= width - 16 - 110)
					and r.weaponX >= r.moveSize * 2 + 8
					and (r.compact or r.unitX + r.unitWidth <= r.weaponX),
				0
			)
			check(
				"hud-strip-in-bounds-" .. width,
				true,
				p.unitX >= 0 and p.unitX + p.unitWidth <= width - 16,
				0
			)
			check("hud-compact-" .. width, width < 900, p.compact, 0)
		end
		-- Regression: a 667x375 phone cut off the lobby nav and the 6-tab chapter row (762 px).
		local L = env.HudLayout
		for _, size in { { 667, 375 }, { 844, 390 }, { 375, 667 }, { 912, 544 }, { 1920, 1080 } } do
			local w, h = size[1], size[2]
			local scale = L.lobbyScale(w, h)
			local tag = w .. "x" .. h
			check("lobby-fits-width-" .. tag, true, L.LOBBY_WIDTH * scale <= w, 0)
			check("lobby-fits-height-" .. tag, true, L.LOBBY_HEIGHT * scale <= h, 0)
			check("lobby-no-upscale-" .. tag, true, scale <= 1, 0)
		end
		check("lobby-desktop-unscaled", 1, L.lobbyScale(1920, 1080), 0)
	end
	-- D-AUTO-01: a summon/weapon press toggles that slot's auto; auto sends only what the HUD shows ready.
	check("auto-module-present", true, env.AutoAssist ~= nil, 0)
	if env.AutoAssist then
		local auto = env.AutoAssist.new(catalog)
		check("auto-toggle-on", true, auto.toggle("Summon", 1), 0)
		check("auto-state-on", true, auto.state().summon[1], 0)
		check("auto-toggle-off", false, auto.toggle("Summon", 1), 0)
		check("auto-state-off", nil, auto.state().summon[1], 0)
		check("auto-eligible-normal", true, auto.eligible("Normal"), 0)
		check("auto-eligible-survival", true, auto.eligible("Survival"), 0)
		check("auto-manual-destiny", false, auto.eligible("Destiny"), 0)
		check("auto-manual-tower", false, auto.eligible("Tower"), 0)
		check("auto-manual-jump", false, auto.eligible("Jump"), 0)
		local skills = table.create(24, 0)
		local slot = {
			heroKind = "light",
			units = { 1, 1, 0, 0, 0, 0, 0, 0, 0 },
			skills = skills,
			equip = { Text.encode(1, 1, 1), Text.encode(1, 11, 1), 0 },
		}
		local cost = catalog.units[1].cost
		local function view(over: { [string]: any }?): any
			local v: { [string]: any } = {
				mode = "Normal",
				paused = false,
				food = cost,
				mana = 1000,
				summonPast = { 99999, 99999 },
				heroState = "Idle",
				entities = {
					{ kind = "Hero", team = 1, x = 100, z = 0, hp = 1 },
					{ kind = "Enemy", team = 2, x = 400, z = 0, hp = 10 },
				},
			}
			local extra: { [string]: any } = over or {}
			for k, value in extra do
				v[k] = value
			end
			return v
		end
		local function kinds(list: { any }): string
			local parts = {}
			for _, d in list do
				table.insert(parts, d.kind .. (d.unit or d.slot))
			end
			return table.concat(parts, ",")
		end
		check("auto-off-sends-nothing", "", kinds(auto.decide(view(), slot, 10)), 0)
		auto.toggle("Summon", 1)
		check("auto-summon-ready", "Summon1", kinds(auto.decide(view(), slot, 10)), 0)
		check("auto-summon-retry-wait", "", kinds(auto.decide(view(), slot, 10.2)), 0)
		check("auto-summon-again", "Summon1", kinds(auto.decide(view(), slot, 10.6)), 0)
		check("auto-summon-no-food", "", kinds(auto.decide(view({ food = cost - 1 }), slot, 20)), 0)
		check(
			"auto-summon-cooldown",
			"",
			kinds(auto.decide(view({ summonPast = { 0, 0 } }), slot, 30)),
			0
		)
		check("auto-paused-idle", "", kinds(auto.decide(view({ paused = true }), slot, 40)), 0)
		check("auto-destiny-idle", "", kinds(auto.decide(view({ mode = "Destiny" }), slot, 50)), 0)
		auto.toggle("Summon", 1)
		auto.toggle("Mace", 1)
		check("auto-weapon-enemy-near", "Mace1", kinds(auto.decide(view(), slot, 60)), 0)
		local far = {
			{ kind = "Hero", team = 1, x = 100, z = 0, hp = 1 },
			{ kind = "Enemy", team = 2, x = 700, z = 0, hp = 10 },
		}
		check(
			"auto-weapon-no-target",
			"",
			kinds(auto.decide(view({ entities = far }), slot, 70)),
			0
		)
		check("auto-weapon-no-mana", "", kinds(auto.decide(view({ mana = 0 }), slot, 80)), 0)
		check(
			"auto-weapon-hero-busy",
			"",
			kinds(auto.decide(view({ heroState = "Attack" }), slot, 90)),
			0
		)
		auto.toggle("Mace", 1)
		auto.toggle("Mace", 2)
		check("auto-gold-weapon-never", "", kinds(auto.decide(view(), slot, 100)), 0)
		auto.toggle("Mace", 1)
		auto.toggle("Summon", 2)
		check(
			"auto-both-one-frame",
			"Summon2,Mace1",
			kinds(auto.decide(view({ food = 1000 }), slot, 110)),
			0
		)
	end
	-- R8 plaza: the dungeon entrance opens the menu; menu or battle turns avatar controls off.
	check("plaza-state-present", true, env.PlazaState ~= nil, 0)
	if env.PlazaState then
		local P = env.PlazaState
		local walk = P.view("LobbyReady", false)
		check("plaza-walk-no-menu", false, walk.menuVisible, 0)
		check("plaza-walk-controls", true, walk.controlsEnabled, 0)
		local menu = P.view("LobbyReady", true)
		check("plaza-menu-open", true, menu.menuVisible, 0)
		check("plaza-menu-locks-avatar", false, menu.controlsEnabled, 0)
		local fight = P.view("Running", true)
		check("plaza-battle-hides-menu", false, fight.menuVisible, 0)
		check("plaza-battle-locks-avatar", false, fight.controlsEnabled, 0)
		check("plaza-battle-flag", true, fight.inBattle, 0)
		check("plaza-result-locks-avatar", false, P.view("Settled", false).controlsEnabled, 0)
		check("plaza-unavailable-shown", true, P.view("Unavailable", false).menuVisible, 0)
		check("plaza-loading-walks", true, P.view("ProfileLoading", false).controlsEnabled, 0)
		check("plaza-nil-phase", true, P.view(nil, true).controlsEnabled, 0)
		-- D-PLAZA-03: in an arena the real character walks during the battle, not on the result screen
		check("plaza-avatar-battle-walks", true, P.view("Running", false, true).controlsEnabled, 0)
		check("plaza-avatar-still-battle", true, P.view("Running", false, true).inBattle, 0)
		-- the dungeon entrance is expeditions only; everything else opens from the plaza menu
		check("menu-dungeon-only-stages", "Stages", table.concat(P.tabs("dungeon", true), ","), 0)
		check("menu-town-no-stages", nil, table.find(P.tabs("town", true), "Stages"), 0)
		check("menu-town-has-upgrades", true, table.find(P.tabs("town", true), "Units") ~= nil, 0)
		check("menu-town-has-shop", true, table.find(P.tabs("town", true), "Equipment") ~= nil, 0)
		check("menu-no-record-records", "Records", P.landing("dungeon", false, "Stages"), 0)
		check("menu-town-keeps-tab", "Skills", P.landing("town", true, "Skills"), 0)
		check("menu-town-refuses-stages", "Units", P.landing("town", true, "Stages"), 0)
		check("menu-dungeon-refuses-units", "Stages", P.landing("dungeon", true, "Units"), 0)
		check(
			"plaza-avatar-result-locked",
			false,
			P.view("Settled", false, true).controlsEnabled,
			0
		)
	end
end
