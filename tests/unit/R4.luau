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
end
