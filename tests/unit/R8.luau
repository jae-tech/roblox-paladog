--!strict
-- R8 plaza (D-PLAZA-01/02): leaderboard stats and ranking from real v2 profiles.
return function(env: any, check: any)
	local Board, Schema = env.PlazaBoard, env.Schema
	local empty = Board.statsOf(Schema.newProfile())
	check("board-no-slot-level", 0, empty.level, 0)
	check("board-no-slot-stage", 0, empty.stage, 0)
	check("board-nil-profile", 0, Board.statsOf(nil).stage, 0)

	local p = Schema.newProfile()
	p.slots[1], p.currentSlot = Schema.newSlot("light", 1), 1
	local slot = p.slots[1]
	slot.stars[1], slot.stars[2], slot.stars[30] = 3, 1, 0
	slot.level, slot.survivalBest = 17, 42
	local s = Board.statsOf(p)
	check("board-highest-cleared", 2, s.stage, 0)
	check("board-level", 17, s.level, 0)
	check("board-wave", 42, s.wave, 0)
	slot.stars[30] = 1
	check("board-chapter2", 30, Board.statsOf(p).stage, 0)
	check("board-label-1-1", "1-1", Board.stageLabel(1), 0)
	check("board-label-2-6", "2-6", Board.stageLabel(30), 0)
	check("board-label-5-24", "5-24", Board.stageLabel(120), 0)
	check("board-label-none", "-", Board.stageLabel(0), 0)

	local rows = {}
	for i = 1, 14 do
		table.insert(
			rows,
			{ userId = 100 + i, name = "p" .. i, level = i, stage = i % 5, wave = 0 }
		)
	end
	table.insert(rows, { userId = 1, name = "wave", level = 1, stage = 4, wave = 9 })
	local ranked = Board.rank(rows)
	check("board-capped", Board.BOARD_SIZE, #ranked, 0)
	check("board-top-stage", 4, ranked[1].stage, 0)
	check("board-wave-breaks-tie", "wave", ranked[1].name, 0)
	check("board-level-breaks-tie", "p14", ranked[2].name, 0)
	local ordered = true
	for i = 2, #ranked do
		if ranked[i - 1].stage < ranked[i].stage then
			ordered = false
		end
	end
	check("board-descending", true, ordered, 0)
	check("board-input-untouched", 15, #rows, 0)

	-- D-PLAZA-03 avatar combat: the hero chases the real character at its own speed, server side.
	local Space = env.ArenaSpace
	if Space then
		local ox, oz = Space.origin(2)
		local wx, wz = Space.toWorld(ox, oz, 250, -30)
		local bx, bz = Space.toBattle(ox, oz, wx, wz)
		check("space-roundtrip-x", "250.000", string.format("%.3f", bx), 0)
		check("space-roundtrip-z", "-30.000", string.format("%.3f", bz), 0)
		local o1x, o1z = Space.origin(1)
		check("space-slots-apart", true, math.abs(oz - o1z) >= 300 and ox == o1x, 0)
	end
	if env.MatchService then
		local Protocol, Battle = env.Protocol, env.Battle
		local srv: { tick: number, target: { number }? } = { tick = 0, target = nil }
		local profiles = env.ProfileService.new({
			store = env.SessionStore.new(),
			clock = function()
				return 1000 + srv.tick
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			sessionId = "r8",
			jobId = "r8",
			receiptCap = Protocol.LIMITS.receiptCap,
			queueCap = Protocol.LIMITS.profileQueueCap,
			log = function(_m: string) end,
		})
		local match = env.MatchService.new({
			spatial = true,
			profiles = profiles,
			tick = function()
				return srv.tick
			end,
			newMatchId = function()
				return "r8-match"
			end,
			newSeed = function()
				return 4242
			end,
			balanceHash = "remake-db-1",
			maxMatches = Protocol.LIMITS.maxMatches,
			ackCacheSize = Protocol.LIMITS.ackCacheSize,
			moveTtlTicks = Protocol.LIMITS.moveTtlTicks,
			send = function(_u: number, _m: any) end,
			follow = function(_userId: number): (number?, number?)
				local t = srv.target
				if t then
					return t[1], t[2]
				end
				return nil, nil
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
		local function send(payload: { [string]: any })
			seq += 1
			srv.tick += 40
			payload.protocolVersion = Protocol.VERSION
			payload.requestId = string.format("r8-request-%08d", seq)
			gateway.clientCommand(1, payload)
			frame()
		end
		gateway.playerAdded(1)
		frame()
		send({
			kind = "CreateSlot",
			slot = 1,
			heroKind = "light",
			difficulty = 1,
			expectedRevision = profiles.profileOf(1).revision,
		})
		send({ kind = "StartStage", stage = 1, expectedRevision = profiles.profileOf(1).revision })
		local b = match.battleOf(1)
		check("follow-battle-started", true, b ~= nil, srv.tick)
		if b then
			local h = Battle.hero(b)
			local x0 = h.x
			srv.target = { x0 + 300, 40 }
			for _ = 1, 30 do
				frame()
			end
			local moved = h.x - x0
			check("follow-moves-toward", true, moved > 0, srv.tick)
			local speed = b.stats.moveSpeed + b.stats.moveSpeedRing
			-- diagonal chase: never faster than the hero's own speed per second
			check("follow-speed-capped", true, moved <= speed * 1.0001, srv.tick)
			check("follow-strafes", true, (h.z or 0) > 0, srv.tick)
			srv.target = { h.x + 2, (h.z or 0) - 2 }
			local xs, zs = h.x, h.z
			for _ = 1, 10 do
				frame()
			end
			check("follow-dead-zone-x", xs, h.x, srv.tick)
			check("follow-dead-zone-z", zs, h.z, srv.tick)
			-- a teleported character does not drag the hero: still one step per tick at hero speed
			srv.target = { h.x + 5000, h.z or 0 }
			local before = h.x
			frame()
			check("follow-no-teleport", true, h.x - before <= speed / 30 + 1e-6, srv.tick)
			-- client MoveIntent is ignored while the character is being followed
			srv.target = { h.x, h.z or 0 }
			local still = h.x
			gateway.moveIntent(1, {
				protocolVersion = Protocol.VERSION,
				matchId = match.snapshot(1).matchId,
				seq = 1,
				axis = 1,
			})
			for _ = 1, 10 do
				frame()
			end
			check("follow-overrides-move-intent", true, math.abs(h.x - still) <= 4, srv.tick)
			-- without a character position the regular MoveIntent path applies again
			srv.target = nil
			gateway.moveIntent(1, {
				protocolVersion = Protocol.VERSION,
				matchId = match.snapshot(1).matchId,
				seq = 2,
				axis = 0,
			})
			frame()
			local free = h.x
			for _ = 1, 5 do
				frame()
			end
			check("follow-none-stands", free, h.x, srv.tick)
		end
	end

	-- D-GEAR-01: every item has a valid, distinct look on the avatar
	local Gear = env.GearLook
	check("gear-module-present", true, Gear ~= nil, 0)
	if not Gear then
		return
	end
	local SLOT_OF = { 1, 4, 7, 8, 9, 1, 4, 7, 8, 9 }
	local valid, distinct, cored, total = true, true, true, 0
	local problem = ""
	for category = 1, 10 do
		local seen: { [string]: boolean } = {}
		for num = 1, Gear.CATEGORY_COUNT[category] do
			total += 1
			local code = category * 100000 + num * 1000
			local pieces = Gear.pieces(SLOT_OF[category], code)
			local signature = {}
			local hasCore = false
			if #pieces == 0 then
				valid, problem = false, "no pieces " .. code
			end
			for _, piece in pieces do
				if not Gear.ANCHORS[piece.anchor] then
					valid, problem = false, "anchor " .. piece.anchor
				end
				for _, part in piece.parts do
					hasCore = hasCore or part.core == true
					if not Gear.SHAPES[part.shape] then
						valid, problem = false, "shape " .. tostring(part.shape)
					end
					for axis = 1, 3 do
						if not (part.size[axis] > 0) or part.at[axis] ~= part.at[axis] then
							valid, problem = false, "size " .. code
						end
						if part.color[axis] < 0 or part.color[axis] > 255 then
							valid, problem = false, "color " .. code
						end
					end
					local view: any = part
					table.insert(
						signature,
						tostring(piece.anchor)
							.. tostring(view.shape)
							.. table.concat(view.size, ",")
							.. table.concat(view.color, ",")
					)
				end
			end
			local key = table.concat(signature, "|")
			if seen[key] then
				distinct, problem = false, "same look " .. code
			end
			seen[key] = true
			cored = cored and hasCore
		end
	end
	check("gear-all-items-valid", "", if valid then "" else problem, 0)
	check("gear-item-count", 82, total, 0)
	check("gear-looks-distinct", true, distinct, 0)
	check("gear-every-item-glows-with-grade", true, cored, 0)
	check("gear-empty-slot", 0, #Gear.pieces(1, 0), 0)
	check("gear-unknown-code", 0, #Gear.pieces(1, 199000), 0)
	check("gear-weapon-hand", "RightHand", Gear.pieces(1, 101000)[1].anchor, 0)
	check("gear-weapon-back", "UpperTorso", Gear.pieces(2, 101000)[1].anchor, 0)
	check("gear-weapon-hip", "LowerTorso", Gear.pieces(3, 601000)[1].anchor, 0)
	check("gear-grade-carried", 4, Gear.pieces(1, 101004)[1].grade, 0)
	check("gear-helmet-hides-hair", true, Gear.pieces(7, 301000)[1].hidesHair == true, 0)
	check("gear-mount-companion", true, Gear.pieces(9, 503000)[1].companion == true, 0)
	check("gear-circlet-keeps-hair", false, Gear.pieces(7, 804000)[1].hidesHair == true, 0)
	check("gear-boots-both-feet", 4, #Gear.pieces(9, 1001000), 0)
	local fresh = Schema.newSlot("light", 1)
	local look, key = Gear.look(fresh.equip)
	local inHand = false
	for _, piece in look do
		inHand = inHand or piece.anchor == "RightHand"
	end
	check("gear-new-record-holds-weapon", true, inHand, 0)
	local changed = table.clone(fresh.equip)
	changed[7] = 301000
	local _, key2 = Gear.look(changed)
	check("gear-key-follows-equip", true, key ~= key2, 0)
end
