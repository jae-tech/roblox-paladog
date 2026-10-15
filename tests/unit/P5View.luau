--!strict
-- Pure presentation contracts, injectable into both CLI and the guarded Studio harness.
type Check = (string, unknown, unknown, number) -> ()
return function(env: any, check: Check)
	local Layout, CameraMath, Definitions = env.Layout, env.CameraMath, env.ViewDefinitions
	local function intersects(a: any, b: any): boolean
		return a.x < b.x + b.width
			and b.x < a.x + a.width
			and a.y < b.y + b.height
			and b.y < a.y + a.height
	end
	for _, viewport in
		{
			{ 1280, 720 },
			{ 1920, 1080 },
			{ 844, 390 },
			{ 740, 360 },
			{ 390, 844 },
			{ 480, 320 },
			{ 544, 320 },
			{ 320, 280 },
			{ 480, 280 },
			{ 700, 280 },
		}
	do
		local width, height = viewport[1], viewport[2]
		local layout = Layout.compute(width, height)
		local prefix = "tdevice-" .. width .. "x" .. height
		check(prefix .. "-portrait", height > width, layout.portrait, 0)
		local names = { "Left", "Right", "Summon1", "Summon2", "Summon3", "Cast" }
		for i, name in names do
			local a = layout.buttons[name]
			check(prefix .. "-" .. name .. "-min48", true, a.width >= 48 and a.height >= 48, 0)
			check(
				prefix .. "-" .. name .. "-inside-safe-content",
				true,
				a.x >= 0 and a.y >= 0 and a.x + a.width <= width and a.y + a.height <= height,
				0
			)
			check(prefix .. "-" .. name .. "-hud-clear", false, intersects(a, layout.hud), 0)
			for j = i + 1, #names do
				local b = layout.buttons[names[j]]
				local gap = math.max(
					b.x - a.x - a.width,
					a.x - b.x - b.width,
					b.y - a.y - a.height,
					a.y - b.y - b.height
				)
				check(prefix .. "-" .. name .. "-" .. names[j] .. "-gap8", true, gap >= 8 - 1e-6, 0)
			end
		end
		check(
			prefix .. "-stage-inside-safe-content",
			true,
			layout.stage.x >= 0
				and layout.stage.y >= 0
				and layout.stage.x + layout.stage.width <= width
				and layout.stage.y + layout.stage.height <= height,
			0
		)
	end
	check(
		"tasset-pulse-bolt-alias",
		"pulse_placeholder",
		Definitions.resolve("pulse_bolt").presentationId,
		0
	)
	check(
		"tasset-enemy-core-alias",
		"core_placeholder",
		Definitions.resolve("enemy_core").presentationId,
		0
	)
	local centre = CameraMath.compute(50, 100, 1, 50)
	check("tcamera-follow-hero", 50, centre.centre, 0)
	check("tcamera-left-clamp", centre.halfWidth, CameraMath.compute(-100, 100, 1, 50).centre, 0)
	check(
		"tcamera-right-clamp",
		100 - centre.halfWidth,
		CameraMath.compute(200, 100, 1, 50).centre,
		0
	)
	check("tcamera-short-map-centred", 5, CameraMath.compute(999, 10, 2, 50).centre, 0)
	check("tcamera-empty-map-centred", 0, CameraMath.compute(20, 0, 2, 50).centre, 0)
	check(
		"tasset-missing-sprite-falls-back",
		"Placeholder",
		Definitions.chooseRenderer("Sprite", { Placeholder = true }),
		0
	)
	check(
		"tasset-missing-model-falls-back",
		"Placeholder",
		Definitions.chooseRenderer("Model", { Placeholder = true }),
		0
	)
	check(
		"tasset-injected-sprite-adapter",
		"Sprite",
		Definitions.chooseRenderer("Sprite", { Placeholder = true, Sprite = true }),
		0
	)
	check(
		"tasset-default-placeholder",
		"Placeholder",
		Definitions.chooseRenderer(nil, { Placeholder = true }),
		0
	)
	check(
		"tasset-unknown-renderer-placeholder",
		"Placeholder",
		Definitions.chooseRenderer("Missing", {}),
		0
	)
	check(
		"tasset-original-hero-id",
		"wayfinder_placeholder",
		Definitions.resolve("wayfinder", "Hero").presentationId,
		0
	)
	check(
		"tasset-objective-fallback",
		"core_placeholder",
		Definitions.resolve("missing-core", "Objective").presentationId,
		0
	)
	check(
		"tasset-unknown-unit-fallback",
		"vanguard_placeholder",
		Definitions.resolve("missing-unit", "Ally").presentationId,
		0
	)
	for _, id in
		{
			"vanguard",
			"slinger",
			"bulwark",
			"scrapper",
			"spitter",
			"brute",
			"core",
			"ally_bolt",
			"enemy_bolt",
			"pulse",
			"environment",
		}
	do
		local def = Definitions.resolve(id)
		check("tasset-" .. id .. "-own-identity", id .. "_placeholder", def.presentationId, 0)
		check(
			"tasset-" .. id .. "-visible-geometry",
			true,
			def.height > 0 and #def.label > 0 and #def.shape > 0,
			0
		)
	end
	for id = 1, 16 do
		check(
			"tasset-jitter-deterministic-" .. id,
			Definitions.jitter(id),
			Definitions.jitter(id),
			0
		)
		check("tasset-jitter-bounded-" .. id, true, math.abs(Definitions.jitter(id)) <= 0.4, 0)
	end
end
