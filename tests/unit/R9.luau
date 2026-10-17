--!strict
-- R9 Robux store (D-PAY-01): receipt grants are applied once, profile fields stay valid, prompts and the speed
-- toggle are server-gated, the gold/EXP pass doubles kill rewards, and a bought revive is used at once.
return function(env: any, check: any)
	local Store, Schema, Battle, Protocol = env.Store, env.Schema, env.Battle, env.Protocol

	local function profileWithSlot(): any
		local p = Schema.newProfile()
		p.slots[1], p.currentSlot = Schema.newSlot("light", 0), 1
		return p
	end

	-- grants ----------------------------------------------------------------------------------------
	local p = profileWithSlot()
	check("grant-gems50", nil, Store.grant(p, 1, "receipt-a"), 0)
	check("grant-gems50-amount", 50, p.gems, 0)
	check("grant-replay-same-receipt", nil, Store.grant(p, 1, "receipt-a"), 0)
	check("grant-replay-no-second-effect", 50, p.gems, 0)
	Store.grant(p, 4, "receipt-b")
	check("grant-gems800", 850, p.gems, 0)
	check("grant-valid-profile", true, (Schema.validate(p)), 0)
	check("grant-unknown-item", "InvalidPayload", Store.grant(p, 7, "receipt-c"), 0)
	check("grant-empty-receipt", "InvalidPayload", Store.grant(p, 1, ""), 0)
	p.gems = Schema.GEM_MAX - 10
	Store.grant(p, 2, "receipt-cap")
	check("grant-gem-cap", Schema.GEM_MAX, p.gems, 0)

	local starter = profileWithSlot()
	local gold0 = starter.slots[1].gold
	Store.grant(starter, Store.STARTER, "receipt-starter")
	check("starter-gems", 100, starter.gems, 0)
	check("starter-gold", gold0 + 50000, starter.slots[1].gold, 0)
	check(
		"starter-weapon",
		Schema.encodeItem(Schema.CATEGORY.mace, 11, 0),
		starter.slots[1].inventory[1],
		0
	)
	check("starter-flag", true, starter.starterBought, 0)
	check("starter-summary", true, Schema.summary(starter).starterBought, 0)
	check("starter-valid", true, (Schema.validate(starter)), 0)
	check("starter-offer-once", "MaxLevel", Store.canOffer(starter, Store.STARTER, {}), 0)

	local full = profileWithSlot()
	local bag: { number } = full.slots[1].inventory
	for _ = 1, Schema.INVENTORY_MAX do
		table.insert(bag, Schema.encodeItem(1, 1, 0) :: number)
	end
	local fullGold = full.slots[1].gold
	Store.grant(full, Store.STARTER, "receipt-full")
	check("starter-full-bag-gold", fullGold + 150000, full.slots[1].gold, 0)
	check("starter-full-bag-size", Schema.INVENTORY_MAX, #full.slots[1].inventory, 0)

	local bare = Schema.newProfile()
	Store.grant(bare, Store.STARTER, "receipt-bare")
	check("starter-no-slot-gems", 100, bare.gems, 0)
	check(
		"starter-no-slot-offer",
		"NoSlot",
		Store.canOffer(Schema.newProfile(), Store.STARTER, {}),
		0
	)

	local many = profileWithSlot()
	for i = 1, Store.PURCHASE_MEMORY + 5 do
		Store.grant(many, 1, "r" .. i)
	end
	check("purchase-memory-cap", Store.PURCHASE_MEMORY, #many.purchases, 0)
	check("purchase-memory-valid", true, (Schema.validate(many)), 0)
	check(
		"purchase-memory-newest",
		true,
		Store.remembered(many, "r" .. (Store.PURCHASE_MEMORY + 5)),
		0
	)

	local bad = profileWithSlot()
	bad.purchases = { 5 }
	check("schema-bad-purchase", false, (Schema.validate(bad)), 0)
	bad.purchases, bad.vipDay = nil, -1
	check("schema-bad-vipday", false, (Schema.validate(bad)), 0)
	bad.vipDay, bad.starterBought = nil, "yes"
	check("schema-bad-starter", false, (Schema.validate(bad)), 0)

	local vip = profileWithSlot()
	check("vip-first", nil, Store.vipDaily(vip, 20000), 0)
	check("vip-again-same-day", "MaxLevel", Store.vipDaily(vip, 20000), 0)
	check("vip-gems", Store.VIP_DAILY_GEMS, vip.gems, 0)
	Store.vipDaily(vip, 20001)
	check("vip-next-day", Store.VIP_DAILY_GEMS * 2, vip.gems, 0)
	check("vip-valid", true, (Schema.validate(vip)), 0)
	check("offer-pass-owned", "MaxLevel", Store.canOffer(vip, 7, { goldExp = true }), 0)
	check("offer-pass-new", nil, Store.canOffer(vip, 8, { goldExp = true }), 0)
	check("offer-unknown", "InvalidPayload", Store.canOffer(vip, 0, {}), 0)

	-- protocol ----------------------------------------------------------------------------------------
	local function command(fields: { [string]: any }): any
		fields.protocolVersion, fields.requestId = Protocol.VERSION, "r9-protocol-request-1"
		return (Protocol.validateCommand(fields))
	end
	check("protocol-purchase", true, command({ kind = "Purchase", item = 3 }) ~= nil, 0)
	check("protocol-purchase-range", nil, command({ kind = "Purchase", item = 10 }), 0)
	check(
		"protocol-speed",
		true,
		command({ kind = "SetSpeed", matchId = "m1", speed = 2 }) ~= nil,
		0
	)
	check("protocol-speed-range", nil, command({ kind = "SetSpeed", matchId = "m1", speed = 3 }), 0)

	-- gold/EXP pass in the battle --------------------------------------------------------------------
	local function loadout(): any
		return {
			heroKind = "light",
			level = 1,
			exp = 0,
			skills = {},
			equip = { [1] = { num = 1, grade = 0 } },
			difficulty = 1,
			unitLevels = { 1, 1, 1, 1, 1, 1, 1, 1, 1 },
		}
	end
	local function killReward(rate: number?): (number, number)
		local b = Battle.new({ stage = 1, seed = 777, loadout = loadout(), rewardRate = rate })
		local enemy = Battle.spawnEnemy(b, 5, 1, 500)
		Battle.strike(b, Battle.hero(b), enemy, 1e9, false, false)
		return b.rewards.gold, b.exp
	end
	local g1, e1 = killReward(nil)
	local g2, e2 = killReward(2)
	check("pass-base-reward", true, g1 > 1 and e1 > 0, 0)
	check("pass-gold-x2", true, math.abs(g2 - 2 * g1) <= 1, 0)
	check("pass-exp-x2", true, math.abs(e2 - 2 * e1) <= 1, 0)

	-- server flow -------------------------------------------------------------------------------------
	local srv = { tick = 0 }
	local sent: { any } = {}
	local prompts: { number } = {}
	local profiles = env.ProfileService.new({
		store = env.SessionStore.new(),
		clock = function()
			return 1000 + srv.tick
		end,
		spawn = function(fn: () -> ())
			fn()
		end,
		sessionId = "r9",
		jobId = "r9",
		receiptCap = Protocol.LIMITS.receiptCap,
		queueCap = Protocol.LIMITS.profileQueueCap,
		log = function(_m: string) end,
	})
	local match = env.MatchService.new({
		profiles = profiles,
		tick = function()
			return srv.tick
		end,
		newMatchId = function()
			return "r9-match"
		end,
		newSeed = function()
			return 99
		end,
		balanceHash = "remake-db-1",
		maxMatches = Protocol.LIMITS.maxMatches,
		ackCacheSize = Protocol.LIMITS.ackCacheSize,
		moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
		send = function(_u: number, message: any)
			table.insert(sent, message)
		end,
		prompt = function(_u: number, item: number): string?
			table.insert(prompts, item)
			return nil
		end,
		reviveForSale = function(): boolean
			return true
		end,
	})
	local gateway = env.RemoteGateway.newCore({
		protocol = Protocol,
		publicCatalog = { version = "remake-db-1" },
		match = match,
		profiles = profiles,
		clock = function()
			return srv.tick
		end,
		tick = function()
			return srv.tick
		end,
		balanceHash = "remake-db-1",
		send = function(_u: number, _c: string, _p: any) end,
	})
	local seq = 0
	local function frame()
		srv.tick += 1
		gateway.drain()
		match.stepAll()
	end
	local function send(payload: { [string]: any }): string
		seq += 1
		srv.tick += 40
		payload.protocolVersion = Protocol.VERSION
		payload.requestId = string.format("r9-request-%08d", seq)
		gateway.clientCommand(1, payload)
		frame()
		return payload.requestId
	end
	local function last(requestId: string): any
		for i = #sent, 1, -1 do
			if sent[i].requestId == requestId then
				return sent[i]
			end
		end
		return nil
	end
	gateway.playerAdded(1)
	frame()
	send({ kind = "CreateSlot", slot = 1, heroKind = "light", difficulty = 0, expectedRevision = 0 })

	-- lobby purchase: prompt opened, then the receipt grant refreshes the client
	local buy = send({ kind = "Purchase", item = 2 })
	check("flow-prompt-opened", 2, prompts[#prompts], srv.tick)
	check("flow-prompt-pending", "Pending", last(buy).status, srv.tick)
	check("flow-prompt-busy", "Busy", last(send({ kind = "Purchase", item = 1 })).reason, srv.tick)
	local revisionBefore = profiles.profileOf(1).revision
	local granted: any = nil
	profiles.grant(1, {
		kind = "Purchase",
		requestId = "buy-receipt-1",
		mutate = function(current)
			return Store.grant(current, 2, "receipt-1")
		end,
	}, function(saved)
		granted = saved
	end)
	check("flow-grant-committed", true, granted ~= nil and granted.gems == 120, srv.tick)
	check("flow-grant-revision", revisionBefore + 1, profiles.profileOf(1).revision, srv.tick)
	match.granted(1, 2, granted)
	check("flow-grant-reply", "Committed", last(buy).status, srv.tick)
	check("flow-grant-summary", 120, last(buy).profileSummary.gems, srv.tick)
	-- the same receipt again (new transaction id, same receipt id): no second effect
	profiles.grant(1, {
		kind = "Purchase",
		requestId = "buy-receipt-1-retry",
		mutate = function(current)
			return Store.grant(current, 2, "receipt-1")
		end,
	}, function(_saved) end)
	check("flow-receipt-replay", 120, profiles.profileOf(1).gems, srv.tick)
	-- a stale client revision does not block a server grant
	profiles.grant(1, {
		kind = "Purchase",
		requestId = "buy-receipt-2",
		mutate = function(current)
			return Store.grant(current, 1, "receipt-2")
		end,
	}, function(_saved) end)
	check("flow-grant-any-revision", 170, profiles.profileOf(1).gems, srv.tick)
	check("flow-profile-valid", true, (Schema.validate(profiles.profileOf(1))), srv.tick)

	local cancelled = send({ kind = "Purchase", item = 3 })
	match.purchaseClosed(1, false)
	check("flow-cancel-reply", "Accepted", last(cancelled).status, srv.tick)
	check(
		"flow-revive-outside-battle",
		"WrongPhase",
		last(send({ kind = "Purchase", item = 6 })).reason,
		srv.tick
	)
	match.setPasses(1, { goldExp = true })
	check(
		"flow-pass-owned",
		"MaxLevel",
		last(send({ kind = "Purchase", item = 7 })).reason,
		srv.tick
	)

	-- battle: gold/EXP pass, speed toggle, bought revive
	-- spend the gems so a revive must be bought
	profiles.grant(1, {
		kind = "Fixture",
		requestId = "fixture-spend-gems",
		mutate = function(current)
			current.gems = 0
			return nil
		end,
	}, function(_saved) end)
	send({ kind = "StartStage", stage = 1, expectedRevision = profiles.profileOf(1).revision })
	local b = match.battleOf(1)
	check("battle-started", true, b ~= nil, srv.tick)
	if b then
		check("battle-pass-rate", 2, b.rewardRate, srv.tick)
		check("battle-revive-offered-for-sale", 1, b.revivesLeft, srv.tick)
		check(
			"speed-locked",
			"Locked",
			last(send({ kind = "SetSpeed", matchId = "r9-match", speed = 2 })).reason,
			srv.tick
		)
		match.setPasses(1, { goldExp = true, speed = true })
		local fast = send({ kind = "SetSpeed", matchId = "r9-match", speed = 2 })
		check("speed-accepted", "Accepted", last(fast).status, srv.tick)
		check("speed-snapshot", 2, match.snapshot(1).speed, srv.tick)
		check("speed-time-scale", 2, b.timeScale, srv.tick)
		local t0 = b.tick
		frame()
		check("speed-two-steps", t0 + 2, b.tick, srv.tick)
		check(
			"speed-foreign-match",
			"WrongPhase",
			last(send({ kind = "SetSpeed", matchId = "other", speed = 1 })).reason,
			srv.tick
		)
		send({ kind = "SetSpeed", matchId = "r9-match", speed = 1 })
		t0 = b.tick
		frame()
		check("speed-back-to-one", t0 + 1, b.tick, srv.tick)

		-- fixture: the hero has just fallen and the revive is offered
		b.reviveOffer, b.reviveWait = true, 0
		local reviveTry = send({
			kind = "Revive",
			matchId = "r9-match",
			commandSeq = 100,
		})
		check("revive-needs-gems", "InsufficientGems", last(reviveTry).reason, srv.tick)
		local buyRevive = send({ kind = "Purchase", item = 6 })
		check("revive-prompt", 6, prompts[#prompts], srv.tick)
		local wait0 = b.reviveWait
		for _ = 1, 400 do
			frame()
		end
		check("revive-held-while-prompt", wait0, b.reviveWait, srv.tick)
		check("revive-still-offered", true, b.reviveOffer, srv.tick)
		local saved: any = nil
		profiles.grant(1, {
			kind = "Purchase",
			requestId = "buy-receipt-revive",
			mutate = function(current)
				return Store.grant(current, Store.REVIVE, "receipt-revive")
			end,
		}, function(s)
			saved = s
		end)
		match.granted(1, Store.REVIVE, saved)
		frame()
		check("revive-applied", false, b.reviveOffer, srv.tick)
		check("revive-counted", 1, b.rewards.revives, srv.tick)
		check("revive-reply", "Committed", last(buyRevive).status, srv.tick)
	end
	gateway.playerRemoving(1)
end
