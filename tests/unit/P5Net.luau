--!strict
-- Pure T-NET contract fixtures; injected unchanged into CLI and Studio.
type Check = (string, unknown, unknown, number) -> ()

return function(env: any, check: Check)
	local Buffer, Controller, catalog = env.SnapshotBuffer, env.ClientController, env.catalog
	local function near(a: number, b: number): boolean
		return math.abs(a - b) < 1e-6
	end
	local function entity(id: number, kind: string, x: number): any
		return {
			entityId = id,
			kind = kind,
			definitionId = if kind == "Hero" then "hero" else "scrapper",
			x = x,
			hp = 100,
			maxHp = 100,
			facing = 1,
			team = if kind == "Enemy" then "Enemy" else "Ally",
			state = "Advancing",
			stateUntilTick = 0,
			inSupport = false,
		}
	end
	local function shot(id: number, x: number): any
		return {
			entityId = id,
			definitionId = "ally_bolt",
			x = x,
			previousX = x - 1,
			direction = 1,
			spawnTick = 0,
			expireTick = 100,
			team = "Ally",
			laneId = 1,
		}
	end
	local function snap(seq: number?, tick: number?, heroX: number?): any
		return {
			matchId = "match-a",
			snapshotSeq = seq or 1,
			tick = tick or 10,
			balanceHash = catalog.balanceHash,
			phase = "Running",
			stageId = "s01",
			inputAckSeq = 0,
			stageLength = 102.4,
			advanceLimitX = 86.4,
			heroMoveSpeed = 6,
			resources = {
				foodMilli = 20000,
				manaMilli = 30000,
				foodMaxMilli = 40000,
				manaMaxMilli = 100000,
				summonReadyTick = { 0, 0, 0 },
				skillReadyTick = 0,
			},
			heroAction = {},
			entities = { entity(1, "Hero", heroX or 10), entity(2, "Enemy", 30) },
			projectiles = { shot(3, 20) },
		}
	end
	local function buffer(): any
		local b = Buffer.new(catalog.balanceHash)
		b.setMatch("match-a")
		return b
	end
	local function boot(snapshot: any?): any
		return {
			protocolVersion = 1,
			status = "Ready",
			phase = if snapshot then snapshot.phase else "LobbyReady",
			balanceHash = catalog.balanceHash,
			publicCatalog = catalog,
			profileRevision = 0,
			profileSummary = {
				gold = 0,
				heroLevel = 1,
				totalXp = 0,
				unspentPoints = 0,
				heroTraits = { vitality = 0, provisions = 0, focus = 0 },
				unitLevels = { vanguard = 1, ranger = 1, bulwark = 1 },
				stageProgress = {},
			},
			storage = "Mock/InMemory",
			currentMatch = snapshot,
		}
	end
	local function client(snapshot: any?, now: number?): (any, { any })
		local sent: { any } = {}
		local ordinal = 0
		local c = Controller.new({
			protocol = env.Protocol,
			catalog = catalog,
			send = function(channel: string, payload: any)
				table.insert(sent, { channel = channel, payload = payload })
			end,
			requestId = function(): string
				ordinal += 1
				return string.format("p5-request-%08d", ordinal)
			end,
		})
		local t = now or 0
		local token = c.beginBootstrap(t)
		check("net-fixture-bootstrap-token-" .. tostring(t), true, token ~= nil, 0)
		check(
			"net-fixture-bootstrap-ready-" .. tostring(t),
			true,
			c.finishBootstrap(token, boot(snapshot), t),
			0
		)
		return c, sent
	end

	-- Rejected data must not advance sequence, mutate accepted state, or choose a match.
	local b = buffer()
	check("net-empty-age-infinite", math.huge, b.age(0), 0)
	check("net-initial-full-snapshot", true, b.accept(snap(), 0), 0)
	check("net-duplicate-sequence", false, b.accept(snap(), 0.01), 0)
	check("net-old-sequence", false, b.accept(snap(0), 0.01), 0)
	check("net-backwards-tick", false, b.accept(snap(2, 9), 0.01), 0)
	check("net-same-tick-new-sequence", true, b.accept(snap(2, 10), 0.02), 0)
	local foreign = snap(3)
	foreign.matchId = "match-foreign"
	check("net-foreign-match", false, b.accept(foreign, 0.03), 0)
	local badHash = snap(3)
	badHash.balanceHash = "wrong-balance"
	check("net-wrong-balance", false, b.accept(badHash, 0.03), 0)
	local badValues: { any } = { nil, false, "snapshot", {}, { matchId = "match-a" } }
	-- nil has no array slot, so exercise it separately.
	check("net-nil-payload", false, b.accept(nil, 0.03), 0)
	for index, value in badValues do
		check("net-malformed-" .. index, false, b.accept(value, 0.03), 0)
	end
	for index, value in { 0 / 0, math.huge, -math.huge } do
		local invalid = snap(3)
		invalid.entities[2].x = value
		check("net-nonfinite-entity-" .. index, false, b.accept(invalid, 0.03), 0)
		invalid = snap(3)
		invalid.projectiles[1].x = value
		check("net-nonfinite-projectile-" .. index, false, b.accept(invalid, 0.03), 0)
	end
	local invalidHp = snap(3)
	invalidHp.entities[1].hp = 0 / 0
	check("net-nonfinite-authoritative-hp", false, buffer().accept(invalidHp, 0.03), 0)
	local invalidMana = snap(3)
	invalidMana.resources.manaMilli = math.huge
	check("net-nonfinite-authoritative-mana", false, buffer().accept(invalidMana, 0.03), 0)
	local invalidPreviousX = snap(3)
	invalidPreviousX.projectiles[1].previousX = 0 / 0
	check("net-nonfinite-projectile-previous-x", false, buffer().accept(invalidPreviousX, 0.03), 0)
	local duplicateEntity = snap(3)
	duplicateEntity.entities[2].entityId = 1
	check("net-duplicate-entity-id", false, buffer().accept(duplicateEntity, 0.03), 0)
	local duplicateShot = snap(3)
	table.insert(duplicateShot.projectiles, shot(3, 21))
	check("net-duplicate-projectile-id", false, buffer().accept(duplicateShot, 0.03), 0)
	local fractionalTick = snap(3, 10.5)
	check("net-fractional-tick", false, buffer().accept(fractionalTick, 0.03), 0)
	local invalidAck = snap(3)
	invalidAck.inputAckSeq = -1
	check("net-negative-ack-sequence", false, buffer().accept(invalidAck, 0.03), 0)
	local fractional = snap(3.5)
	check("net-fractional-sequence", false, b.accept(fractional, 0.03), 0)
	check("net-invalid-does-not-advance", 2, b.latest().snapshotSeq, 0)
	check("net-invalid-does-not-refresh-age", true, near(b.age(0.52), 0.5), 0)
	local crowded = snap(3)
	for id = 3, 73 do
		table.insert(crowded.entities, entity(id, "Enemy", 30))
	end
	check("net-entity-cap", false, b.accept(crowded, 0.03), 0)
	crowded = snap(3)
	for id = 4, 131 do
		table.insert(crowded.projectiles, shot(id, 20))
	end
	check("net-projectile-cap", false, b.accept(crowded, 0.03), 0)
	local capacity = snap()
	for id = 3, 72 do
		table.insert(capacity.entities, entity(id, "Enemy", 30))
	end
	for id = 4, 130 do
		table.insert(capacity.projectiles, shot(id, 20))
	end
	check("net-exact-entity-projectile-cap-accepted", true, buffer().accept(capacity, 0), 0)
	local owned = snap(3, 11)
	check("net-next-valid-after-invalid", true, b.accept(owned, 0.1), 0)
	owned.entities[1].x, owned.resources.manaMilli = 99, 1
	check("net-input-table-not-retained", 10, b.latest().entities[1].x, 0)
	check("net-input-resource-table-not-retained", 30000, b.latest().resources.manaMilli, 0)
	local exposed = b.latest()
	exposed.entities[1].hp = 1
	exposed.resources.foodMilli = 1
	check("net-latest-copy-protects-hp", 100, b.latest().entities[1].hp, 0)
	check("net-latest-copy-protects-economy", 20000, b.latest().resources.foodMilli, 0)
	local removed = snap(4, 12)
	removed.entities = { removed.entities[1] }
	removed.projectiles = {}
	b.accept(removed, 0.2)
	check("net-full-snapshot-removes-entity", 1, #b.frame(0.3).entities, 0)
	check("net-full-snapshot-removes-projectile", 0, #b.frame(0.3).projectiles, 0)
	b.setMatch("match-b")
	check("net-match-change-clears-latest", nil, b.latest(), 0)
	check("net-match-change-clears-age", math.huge, b.age(0.3), 0)
	check("net-old-match-cannot-return", false, b.accept(snap(99, 99), 0.3), 0)

	local interpolation = buffer()
	interpolation.accept(snap(1, 10), 0)
	local nextSnapshot = snap(2, 12)
	nextSnapshot.entities[2].x, nextSnapshot.projectiles[1].x = 32, 22
	interpolation.accept(nextSnapshot, 0.1)
	check(
		"net-enemy-interpolation-100ms-behind",
		true,
		near(interpolation.frame(0.15).entities[2].x, 31),
		0
	)
	check(
		"net-projectile-interpolation",
		true,
		near(interpolation.frame(0.15).projectiles[1].x, 21),
		0
	)
	local early = interpolation.frame(0.4)
	local late = interpolation.frame(5)
	check("net-extrapolation-time-cap", true, early.entities[2].x <= 35.000001, 0)
	check("net-extrapolation-freezes", early.entities[2].x, late.entities[2].x, 0)
	check("net-extrapolation-authoritative-hp", 100, late.entities[2].hp, 0)
	check("net-frame-authority-not-mutated", 32, interpolation.latest().entities[2].x, 0)

	-- RemoteFunction timeouts are display-only; a late response retains its single flight.
	local raw = Controller.new({
		protocol = env.Protocol,
		catalog = catalog,
		send = function() end,
		requestId = function()
			return "p5-timeout-request"
		end,
	})
	check("net-startup-needs-bootstrap", true, raw.needsBootstrap(0), 0)
	local token = raw.beginBootstrap(0)
	check("net-bootstrap-single-flight", nil, raw.beginBootstrap(0.2), 0)
	raw.step(3.1)
	check("net-timeout-does-not-duplicate", nil, raw.beginBootstrap(3.1), 0)
	check(
		"net-timeout-late-response-accepted",
		true,
		raw.finishBootstrap(token, boot(snap()), 3.2),
		0
	)
	check("net-duplicate-completion-ignored", false, raw.finishBootstrap(token, boot(), 3.3), 0)
	check("net-fresh-snapshot-not-resync", false, raw.needsBootstrap(3.3), 0)
	check("net-one-second-gap-resync", true, raw.needsBootstrap(4.21), 0)

	local unavailable = Controller.new({
		protocol = env.Protocol,
		catalog = catalog,
		send = function() end,
		requestId = function()
			return "p5-unavailable-id"
		end,
	})
	local unavailableToken = unavailable.beginBootstrap(0)
	local unavailableBoot = boot()
	unavailableBoot.status, unavailableBoot.phase = "Unavailable", "Unavailable"
	check(
		"net-unavailable-response-not-ready",
		false,
		unavailable.finishBootstrap(unavailableToken, unavailableBoot, 0.1),
		0
	)
	check("net-bootstrap-rate-limited-after-failure", false, unavailable.needsBootstrap(0.99), 0)
	check("net-bootstrap-retry-after-failure", true, unavailable.needsBootstrap(1), 0)
	local c, sent = client(snap())
	check("net-foreign-controller-snapshot", false, c.receiveSnapshot(foreign, 0.01), 0)
	check("net-invalid-move-axis", false, c.move(2, 0.01), 0)
	check("net-move-accepted", true, c.move(1, 0.01), 0)
	check("net-move-channel", "MoveIntent", sent[1].channel, 0)
	check("net-move-current-match", "match-a", sent[1].payload.matchId, 0)
	check("net-move-first-sequence", 1, sent[1].payload.seq, 0)
	check("net-move-valid-protocol", true, env.Protocol.validateMove(sent[1].payload) ~= nil, 0)
	check("net-hero-local-prediction", true, c.frame(0.11).heroX > 10, 0)
	check("net-hero-prediction-cap", true, c.frame(0.4).heroX <= 10.900001, 0)
	check("net-cast-accepted", true, c.action("Cast", 0.1), 0)
	check("net-summon-accepted", true, c.action("Summon2", 0.11), 0)
	local cast, summon = sent[#sent - 1].payload, sent[#sent].payload
	check("net-cast-kind", "Cast", cast.kind, 0)
	check("net-cast-slot-one", 1, cast.slot, 0)
	check("net-summon-slot-two", 2, summon.slot, 0)
	check("net-shared-command-sequence", cast.commandSeq + 1, summon.commandSeq, 0)
	check("net-independent-move-command-sequences", 1, cast.commandSeq, 0)
	check("net-command-request-id-length", true, #cast.requestId >= 16, 0)
	check("net-command-request-id-unique", true, cast.requestId ~= summon.requestId, 0)
	check("net-cast-protocol-valid", true, env.Protocol.validateCommand(cast) ~= nil, 0)
	check("net-summon-protocol-valid", true, env.Protocol.validateCommand(summon) ~= nil, 0)
	check("net-unknown-action-refused", false, c.action("GrantMana", 0.12), 0)
	check("net-stale-nonzero-refused", false, c.move(1, 0.51), 0)
	check("net-stale-zero-permitted", true, c.move(0, 0.51), 0)
	check("net-no-optimistic-food-cost", 20000, c.model(0.2).foodMilli, 0)
	check("net-no-optimistic-mana-cost", 30000, c.model(0.2).manaMilli, 0)
	check("net-no-optimistic-hit-damage", 100, c.model(0.2).heroHp, 0)
	check("net-half-second-warning", "연결 불안", c.model(0.51).network, 0)
	local acknowledged = snap(2, 12, 10.3)
	acknowledged.inputAckSeq = 2
	check("net-ack-snapshot-accepted", true, c.receiveSnapshot(acknowledged, 0.6), 0)
	check("net-acked-history-discarded", 0, c.inspect(0.6).history, 0)
	check("net-acked-movement-not-replayed", true, near(c.frame(0.8).heroX, 10.3), 0)
	local terminal = snap(3, 13, 4)
	terminal.phase = "Settling"
	check("net-terminal-snapshot", true, c.receiveSnapshot(terminal, 0.9), 0)
	check("net-terminal-immediate-snap", 4, c.frame(0.9).heroX, 0)
	check("net-terminal-movement-refused", false, c.move(1, 0.91), 0)
	check("net-terminal-cast-refused", false, c.action("Cast", 0.91), 0)
	c.destroy()
	check("net-destroy-move-refused", false, c.move(1, 1), 0)
	check("net-destroy-command-refused", false, c.action("Cast", 1), 0)

	local bounded = client(snap(1, 10, 86.3), 10)
	bounded.move(1, 10)
	check("net-prediction-forward-boundary", true, bounded.frame(10.15).heroX <= 86.4, 0)
	local left = client(snap(1, 10, 0.1), 20)
	left.move(-1, 20)
	check("net-prediction-left-boundary", true, left.frame(20.15).heroX >= 0, 0)
	local lobby, lobbySent = client(nil, 30)
	check("net-lobby-no-movement", false, lobby.move(1, 30), 0)
	check("net-lobby-start-stage", true, lobby.action("Start_s01", 30), 0)
	check("net-start-revision", 0, lobbySent[1].payload.expectedRevision, 0)
	check("net-start-stage-id", "s01", lobbySent[1].payload.stageId, 0)
	check("net-unsolicited-match-does-not-select", false, lobby.receiveSnapshot(snap(), 30.1), 0)
	check(
		"net-foreign-start-ack-rejected",
		false,
		lobby.receiveMessage({
			requestId = "unknown-request-id",
			status = "Committed",
			matchId = "match-a",
			serverTick = 10,
		}, 30.1),
		0
	)
	check("net-foreign-ack-cannot-enable-movement", false, lobby.move(1, 30.1), 0)
	local startId = lobbySent[1].payload.requestId
	check(
		"net-matching-start-ack-selects",
		true,
		lobby.receiveMessage(
			{ requestId = startId, status = "Committed", matchId = "match-a", serverTick = 10 },
			30.2
		),
		0
	)
	check("net-selected-match-snapshot", true, lobby.receiveSnapshot(snap(), 30.2), 0)
	check("net-selected-match-enables-move", true, lobby.move(1, 30.21), 0)
	check("net-selected-match-move-sequence-reset", 1, lobbySent[#lobbySent].payload.seq, 0)
	local replayed =
		{ requestId = startId, status = "Committed", matchId = "old-match", serverTick = 1 }
	check("net-old-start-ack-does-not-switch", false, lobby.receiveMessage(replayed, 30.3), 0)
	check("net-current-match-after-old-ack", "match-a", lobby.inspect(30.3).matchId, 0)
	local backlog, backlogSent = client(snap(), 40)
	for _ = 1, 160 do
		backlog.action("Cast", 40)
	end
	check("net-pending-history-bounded", true, backlog.inspect(40).pending <= 128, 0)
	check(
		"net-evicted-request-ack-ignored",
		false,
		backlog.receiveMessage({
			requestId = backlogSent[1].payload.requestId,
			status = "Accepted",
			matchId = "match-a",
			serverTick = 10,
		}, 40),
		0
	)
	local replay = client(snap(), 50)
	replay.move(1, 50)
	local updated = snap(2, 12, 10.2)
	replay.receiveSnapshot(updated, 50.05)
	check("net-unacked-history-retained", 1, replay.inspect(50.05).history, 0)
	check("net-unacked-input-replayed", true, replay.frame(50.1).heroX > 10.2, 0)
	local smooth = client(snap(), 60)
	check("net-small-error-initial-frame", 10, smooth.frame(60).heroX, 0)
	smooth.receiveSnapshot(snap(2, 12, 10.05), 60.1)
	check("net-small-error-no-visual-jump", true, near(smooth.frame(60.1).heroX, 10), 0)
	check("net-small-error-halfway", true, near(smooth.frame(60.15).heroX, 10.025), 0)
	check("net-small-error-correction-complete", true, near(smooth.frame(60.2).heroX, 10.05), 0)
	local relocated = snap(3, 14, 50)
	relocated.inputAckSeq = 1
	replay.receiveSnapshot(relocated, 50.1)
	check("net-large-error-immediate-snap", 50, replay.frame(50.1).heroX, 0)

	-- Recreating a client must continue the existing server high-water marks.
	local reconnectSnapshot = snap(8, 80)
	reconnectSnapshot.inputAckSeq, reconnectSnapshot.commandAckSeq = 50, 90
	local reconnect, reconnectSent = client(reconnectSnapshot, 70)
	check("net-reconnect-move-sent", true, reconnect.move(1, 70.01), 0)
	check("net-reconnect-move-after-server-highwater", 51, reconnectSent[1].payload.seq, 0)
	check("net-reconnect-cast-sent", true, reconnect.action("Cast", 70.02), 0)
	check(
		"net-reconnect-command-after-server-highwater",
		91,
		reconnectSent[2].payload.commandSeq,
		0
	)

	-- An in-flight read can complete after a newer live terminal snapshot.
	local staleRead = client(snap(), 80)
	local staleToken = staleRead.beginBootstrap(81)
	local newerTerminal = snap(3, 14, 4)
	newerTerminal.phase = "Settling"
	newerTerminal.resources.foodMilli, newerTerminal.resources.manaMilli = 12000, 13000
	check(
		"net-late-bootstrap-live-terminal-accepted",
		true,
		staleRead.receiveSnapshot(newerTerminal, 81.1),
		0
	)
	staleRead.finishBootstrap(staleToken, boot(snap(2, 12, 10)), 81.2)
	check("net-late-bootstrap-keeps-terminal-phase", "Settling", staleRead.model(81.2).phase, 0)
	check("net-late-bootstrap-does-not-unlock-cast", false, staleRead.action("Cast", 81.2), 0)
	check("net-late-bootstrap-does-not-unlock-movement", false, staleRead.move(1, 81.2), 0)
	check("net-late-bootstrap-keeps-authoritative-food", 12000, staleRead.model(81.2).foodMilli, 0)
	check("net-late-bootstrap-keeps-authoritative-mana", 13000, staleRead.model(81.2).manaMilli, 0)
	check("net-late-bootstrap-keeps-terminal-position", 4, staleRead.frame(81.2).heroX, 0)

	-- Missing StartStage Committed events recover through a trusted bounded read,
	-- never by selecting an unsolicited MatchSnapshot.
	local lostStart, lostStartSent = client(nil, 90)
	check("net-lost-start-command-sent", true, lostStart.action("Start_s01", 90), 0)
	check(
		"net-lost-start-untrusted-snapshot-rejected",
		false,
		lostStart.receiveSnapshot(snap(), 90.1),
		0
	)
	check("net-lost-start-retains-preparing", "Preparing", lostStart.model(90.1).phase, 0)
	check("net-lost-start-not-resync-before-deadline", false, lostStart.needsBootstrap(90.99), 0)
	check("net-lost-start-resync-at-one-second", true, lostStart.needsBootstrap(91), 0)
	local recoveryToken = lostStart.beginBootstrap(91)
	check("net-lost-start-single-flight-read", true, recoveryToken ~= nil, 0)
	check(
		"net-lost-start-trusted-bootstrap-recovers",
		true,
		lostStart.finishBootstrap(recoveryToken, boot(snap()), 91.1),
		0
	)
	check("net-lost-start-recovered-running", "Running", lostStart.model(91.1).phase, 0)
	check("net-lost-start-recovered-match", "match-a", lostStart.inspect(91.1).matchId, 0)
	check("net-lost-start-recovered-input", true, lostStart.move(1, 91.11), 0)
	local recoveredTerminal = snap(2, 12, 4)
	recoveredTerminal.phase = "Settling"
	check(
		"net-lost-start-terminal-snapshot",
		true,
		lostStart.receiveSnapshot(recoveredTerminal, 91.2),
		0
	)
	lostStart.receiveMessage({
		requestId = lostStartSent[1].payload.requestId,
		status = "Committed",
		matchId = "match-a",
		serverTick = 10,
	}, 91.3)
	check("net-late-start-ack-keeps-terminal-phase", "Settling", lostStart.model(91.3).phase, 0)
	check("net-late-start-ack-cannot-resurrect-cast", false, lostStart.action("Cast", 91.3), 0)
	check("net-late-start-ack-cannot-resurrect-move", false, lostStart.move(1, 91.3), 0)
end
