--!strict
-- Shared plaza (R8, D-PLAZA-01): a large code-built square where every player's Roblox avatar meets, with
-- a server leaderboard board and the dungeon entrance (a ProximityPrompt that opens the expedition menu
-- on that client). Battles stay client-rendered far from here, so the plaza never overlaps a battlefield.
local PlazaBoard = require("./PlazaBoard")

local CENTER = Vector3.new(0, 0, -500)
local SIZE = 110
local PRESENTATION_ID = "plaza_3d_placeholder"

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = Enum.Font.BuilderSansBold
	-- shrink to the box on small boards, never past `size`
	l.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.Parent = l
	l.Parent = parent
	return l
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- decoration: no collision, no queries, so avatars never snag on it
local function deco(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(parent, name, size, cf, color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	return p
end

local function cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	at: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = deco(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, size: Vector3, at: Vector3, color: Color3): Part
	local p = deco(parent, name, size, CFrame.new(at), color, Enum.Material.Grass)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function glowLight(p: BasePart, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = p.Color, range, brightness
	light.Shadows = false
	light.Parent = p
end

local STONE = rgb(168, 160, 146)
local STONE_DARK = rgb(112, 104, 96)
local STONE_LIGHT = rgb(206, 196, 176)
local IRON = rgb(44, 42, 48)
local WARM = rgb(255, 200, 110)
local GOLD = rgb(232, 180, 70)
local VIOLET = rgb(150, 100, 255)
local WOOD = rgb(110, 76, 48)

-- an iron street lamp with a hanging lantern
local function streetLamp(parent: Instance, at: Vector3, lit: boolean)
	cylinder(
		parent,
		"LampBase",
		1.6,
		0.6,
		at + Vector3.new(0, 0.3, 0),
		STONE_DARK,
		Enum.Material.Slate
	)
	cylinder(parent, "LampPost", 0.5, 9, at + Vector3.new(0, 4.8, 0), IRON, Enum.Material.Metal)
	deco(
		parent,
		"LampArm",
		Vector3.new(0.3, 0.3, 2.6),
		CFrame.new(at + Vector3.new(0, 9, 0.9)),
		IRON,
		Enum.Material.Metal
	)
	local lantern = deco(
		parent,
		"Lantern",
		Vector3.new(1.1, 1.4, 1.1),
		CFrame.new(at + Vector3.new(0, 8, 1.9)),
		WARM,
		Enum.Material.Neon
	)
	deco(
		parent,
		"LanternCap",
		Vector3.new(1.5, 0.3, 1.5),
		CFrame.new(at + Vector3.new(0, 8.85, 1.9)),
		IRON,
		Enum.Material.Metal
	)
	if lit then
		glowLight(lantern, 20, 1.6)
	end
end

local function planter(parent: Instance, at: Vector3, tall: boolean)
	local box =
		part(parent, "Planter", Vector3.new(7, 2, 7), CFrame.new(at + Vector3.new(0, 1, 0)), STONE)
	box.Material = Enum.Material.Slate
	deco(
		parent,
		"PlanterRim",
		Vector3.new(7.6, 0.4, 7.6),
		CFrame.new(at + Vector3.new(0, 2.1, 0)),
		STONE_LIGHT,
		Enum.Material.Slate
	)
	deco(
		parent,
		"Soil",
		Vector3.new(6.4, 0.2, 6.4),
		CFrame.new(at + Vector3.new(0, 2.05, 0)),
		rgb(70, 50, 36),
		Enum.Material.Ground
	)
	if tall then
		cylinder(parent, "Trunk", 0.9, 6, at + Vector3.new(0, 5, 0), WOOD, Enum.Material.Wood)
		ball(parent, "Crown", Vector3.new(7, 5.5, 7), at + Vector3.new(0, 9, 0), rgb(76, 140, 70))
		ball(
			parent,
			"Crown",
			Vector3.new(4.5, 4, 4.5),
			at + Vector3.new(1.2, 11, -0.6),
			rgb(96, 160, 80)
		)
	else
		ball(
			parent,
			"Hedge",
			Vector3.new(5.5, 3.2, 5.5),
			at + Vector3.new(0, 3.2, 0),
			rgb(70, 130, 64)
		)
		for i = 0, 4 do
			local a = math.rad(i * 72)
			ball(
				parent,
				"Flower",
				Vector3.new(0.9, 0.9, 0.9),
				at + Vector3.new(math.cos(a) * 2.2, 4.4, math.sin(a) * 2.2),
				if i % 2 == 0 then rgb(255, 150, 190) else rgb(255, 230, 110)
			)
		end
	end
end

local function bench(parent: Instance, at: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(at, at + facing)
	deco(
		parent,
		"BenchSeat",
		Vector3.new(5, 0.35, 1.6),
		cf * CFrame.new(0, 1.3, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	deco(
		parent,
		"BenchBack",
		Vector3.new(5, 1.4, 0.3),
		cf * CFrame.new(0, 2.2, 0.75),
		WOOD,
		Enum.Material.WoodPlanks
	)
	for _, x in { -2.1, 2.1 } do
		deco(
			parent,
			"BenchLeg",
			Vector3.new(0.35, 1.3, 1.5),
			cf * CFrame.new(x, 0.65, 0),
			IRON,
			Enum.Material.Metal
		)
	end
end

local function banner(parent: Instance, at: Vector3, color: Color3)
	deco(
		parent,
		"BannerRod",
		Vector3.new(4.4, 0.25, 0.25),
		CFrame.new(at + Vector3.new(0, 3.2, 0)),
		GOLD,
		Enum.Material.Metal
	)
	deco(parent, "Banner", Vector3.new(3.6, 6, 0.12), CFrame.new(at), color, Enum.Material.Fabric)
	deco(
		parent,
		"BannerTip",
		Vector3.new(3.6, 1.2, 0.12),
		CFrame.new(at + Vector3.new(0, -3.4, 0)) * CFrame.Angles(0, 0, math.rad(45)),
		color,
		Enum.Material.Fabric
	).Size =
		Vector3.new(2.5, 2.5, 0.12)
	local emblem = deco(
		parent,
		"BannerEmblem",
		Vector3.new(1.4, 1.4, 0.14),
		CFrame.new(at + Vector3.new(0, 0.6, 0)),
		GOLD,
		Enum.Material.Neon
	)
	emblem.Shape = Enum.PartType.Ball
end

-- the square itself: lawn, patterned stone floor, low crenellated wall, fountain, lamps, planters, benches
local function scenery(root: Instance)
	local half = SIZE / 2
	-- lawn ring around the wall, a little above a place's default baseplate
	local band = 60
	for _, strip in
		{
			{
				size = Vector3.new(SIZE + band * 2, 1, band),
				at = Vector3.new(0, 0, -(half + band / 2)),
			},
			{
				size = Vector3.new(SIZE + band * 2, 1, band),
				at = Vector3.new(0, 0, half + band / 2),
			},
			{ size = Vector3.new(band, 1, SIZE), at = Vector3.new(-(half + band / 2), 0, 0) },
			{ size = Vector3.new(band, 1, SIZE), at = Vector3.new(half + band / 2, 0, 0) },
		}
	do
		local lawn = part(
			root,
			"Lawn",
			strip.size,
			CFrame.new(CENTER + strip.at + Vector3.new(0, -0.4, 0)),
			rgb(92, 140, 76)
		)
		lawn.Material = Enum.Material.Grass
	end
	local floor = part(
		root,
		"Floor",
		Vector3.new(SIZE, 2, SIZE),
		CFrame.new(CENTER - Vector3.new(0, 1, 0)),
		STONE
	)
	floor.Material = Enum.Material.Slate
	-- checker tiles and the two crossing paths
	for x = -half + 5, half - 5, 10 do
		for z = -half + 5, half - 5, 10 do
			if (math.floor((x + half) / 10) + math.floor((z + half) / 10)) % 2 == 0 then
				deco(
					root,
					"Tile",
					Vector3.new(9.6, 0.06, 9.6),
					CFrame.new(CENTER + Vector3.new(x, 0.02, z)),
					rgb(184, 174, 156),
					Enum.Material.Slate
				)
			end
		end
	end
	deco(
		root,
		"PathZ",
		Vector3.new(10, 0.1, SIZE - 4),
		CFrame.new(CENTER + Vector3.new(0, 0.05, 0)),
		STONE_LIGHT,
		Enum.Material.Pavement
	)
	deco(
		root,
		"PathX",
		Vector3.new(SIZE - 4, 0.1, 10),
		CFrame.new(CENTER + Vector3.new(0, 0.05, 0)),
		STONE_LIGHT,
		Enum.Material.Pavement
	)
	for _, side in { -1, 1 } do
		deco(
			root,
			"PathEdge",
			Vector3.new(0.5, 0.14, SIZE - 4),
			CFrame.new(CENTER + Vector3.new(side * 5.2, 0.07, 0)),
			STONE_DARK,
			Enum.Material.Slate
		)
		deco(
			root,
			"PathEdge",
			Vector3.new(SIZE - 4, 0.14, 0.5),
			CFrame.new(CENTER + Vector3.new(0, 0.07, side * 5.2)),
			STONE_DARK,
			Enum.Material.Slate
		)
	end
	cylinder(
		root,
		"Plaza Ring",
		34,
		0.12,
		CENTER + Vector3.new(0, 0.08, 0),
		STONE_DARK,
		Enum.Material.Slate
	)
	cylinder(
		root,
		"Plaza Ring Inner",
		32,
		0.14,
		CENTER + Vector3.new(0, 0.09, 0),
		STONE_LIGHT,
		Enum.Material.Pavement
	)
	-- runner carpet from the fountain to the dungeon gate
	deco(
		root,
		"Carpet",
		Vector3.new(6, 0.18, 26),
		CFrame.new(CENTER + Vector3.new(12, 0.1, -half + 26)),
		rgb(110, 60, 150),
		Enum.Material.Fabric
	)
	deco(
		root,
		"CarpetTrim",
		Vector3.new(6.8, 0.16, 26),
		CFrame.new(CENTER + Vector3.new(12, 0.09, -half + 26)),
		GOLD,
		Enum.Material.Fabric
	)

	-- low wall with caps and pillars; every other pillar carries a small lantern
	for i, edge in
		{
			{ x = half, z = 0, long = "Z" },
			{ x = -half, z = 0, long = "Z" },
			{ x = 0, z = half, long = "X" },
			{ x = 0, z = -half, long = "X" },
		}
	do
		local size = if edge.long == "Z" then Vector3.new(2, 4, SIZE) else Vector3.new(SIZE, 4, 2)
		local wall = part(
			root,
			"Wall" .. i,
			size,
			CFrame.new(CENTER + Vector3.new(edge.x, 2, edge.z)),
			STONE
		)
		wall.Material = Enum.Material.Cobblestone
		local cap = if edge.long == "Z"
			then Vector3.new(2.8, 0.6, SIZE + 0.8)
			else Vector3.new(SIZE + 0.8, 0.6, 2.8)
		deco(
			root,
			"WallCap",
			cap,
			CFrame.new(CENTER + Vector3.new(edge.x, 4.3, edge.z)),
			STONE_LIGHT,
			Enum.Material.Slate
		)
		for k = -5, 5 do
			local offset = k * (SIZE / 10)
			local at = CENTER
				+ (
					if edge.long == "Z"
						then Vector3.new(edge.x, 0, offset)
						else Vector3.new(offset, 0, edge.z)
				)
			local pillar = part(
				root,
				"Pillar",
				Vector3.new(3, 6, 3),
				CFrame.new(at + Vector3.new(0, 3, 0)),
				STONE_DARK
			)
			pillar.Material = Enum.Material.Cobblestone
			deco(
				root,
				"PillarCap",
				Vector3.new(3.6, 0.6, 3.6),
				CFrame.new(at + Vector3.new(0, 6.3, 0)),
				STONE_LIGHT,
				Enum.Material.Slate
			)
			if k % 2 == 0 then
				local flame = deco(
					root,
					"PillarLantern",
					Vector3.new(1, 1.2, 1),
					CFrame.new(at + Vector3.new(0, 7.2, 0)),
					WARM,
					Enum.Material.Neon
				)
				if k == 0 then
					glowLight(flame, 16, 1.2)
				end
			end
		end
	end

	-- two-tier fountain with a lantern on top
	local basin = part(
		root,
		"Fountain",
		Vector3.new(2.2, 24, 24),
		CFrame.new(CENTER + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		STONE
	)
	basin.Shape = Enum.PartType.Cylinder
	basin.Material = Enum.Material.Slate
	local water = cylinder(
		root,
		"Water",
		21.5,
		0.3,
		CENTER + Vector3.new(0, 2.25, 0),
		rgb(70, 160, 220),
		Enum.Material.Glass
	)
	water.Transparency = 0.25
	cylinder(
		root,
		"FountainColumn",
		3.4,
		5,
		CENTER + Vector3.new(0, 4.6, 0),
		STONE,
		Enum.Material.Slate
	)
	cylinder(
		root,
		"UpperBasin",
		9,
		1,
		CENTER + Vector3.new(0, 7.4, 0),
		STONE_LIGHT,
		Enum.Material.Slate
	)
	local upperWater = cylinder(
		root,
		"UpperWater",
		8,
		0.2,
		CENTER + Vector3.new(0, 7.95, 0),
		rgb(90, 180, 235),
		Enum.Material.Glass
	)
	upperWater.Transparency = 0.2
	cylinder(
		root,
		"LanternStem",
		1.2,
		3,
		CENTER + Vector3.new(0, 9.5, 0),
		GOLD,
		Enum.Material.Metal
	)
	local orb = deco(
		root,
		"FountainLantern",
		Vector3.new(2.6, 2.6, 2.6),
		CFrame.new(CENTER + Vector3.new(0, 12, 0)),
		WARM,
		Enum.Material.Neon
	)
	orb.Shape = Enum.PartType.Ball
	glowLight(orb, 28, 2)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(rgb(200, 235, 255))
	spray.Size = NumberSequence.new(0.35, 0.1)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Rate = 30
	spray.Speed = NumberRange.new(5, 7)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -14, 0)
	spray.Parent = upperWater

	-- lamps along the sides and the near half: none on the spawn pad or in front of the gate and board
	for i, degrees in { -30, 0, 30, 60, 120, 150, 180, 210 } do
		local angle = math.rad(degrees)
		streetLamp(
			root,
			CENTER + Vector3.new(math.cos(angle) * 30, 0, math.sin(angle) * 30),
			i % 2 == 0
		)
	end
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		planter(
			root,
			CENTER + Vector3.new(corner[1] * (half - 9), 0, corner[2] * (half - 9)),
			corner[2] > 0
		)
	end
	for _, side in { -1, 1 } do
		planter(root, CENTER + Vector3.new(side * (half - 9), 0, 6), false)
		bench(root, CENTER + Vector3.new(side * 19, 0, -9), Vector3.new(-side, 0, 0))
		bench(root, CENTER + Vector3.new(side * 19, 0, 9), Vector3.new(-side, 0, 0))
	end
	-- trees on the lawn outside the wall
	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		local at = CENTER + Vector3.new(math.cos(a) * (half + 22), -0.2, math.sin(a) * (half + 22))
		cylinder(root, "Trunk", 1.4, 8, at + Vector3.new(0, 4, 0), WOOD, Enum.Material.Wood)
		ball(root, "Crown", Vector3.new(10, 8, 10), at + Vector3.new(0, 10, 0), rgb(70, 128, 64))
	end
end

-- frames, torches and banners around the dungeon gate and the leaderboard
local function gateDecor(root: Instance, gateAt: Vector3, boardAt: Vector3)
	deco(
		root,
		"GateStep",
		Vector3.new(26, 0.6, 6),
		CFrame.new(gateAt + Vector3.new(0, 0.3, 1.5)),
		STONE_LIGHT,
		Enum.Material.Slate
	)
	for _, x in { -9, 9 } do
		deco(
			root,
			"GatePillarCap",
			Vector3.new(5.2, 1.2, 5.2),
			CFrame.new(gateAt + Vector3.new(x, 24.6, 0)),
			GOLD,
			Enum.Material.Metal
		)
		deco(
			root,
			"GatePillarBase",
			Vector3.new(5.2, 1.4, 5.2),
			CFrame.new(gateAt + Vector3.new(x, 0.7, 0)),
			STONE_DARK,
			Enum.Material.Slate
		)
		local torch = deco(
			root,
			"GateTorch",
			Vector3.new(1.2, 1.6, 1.2),
			CFrame.new(gateAt + Vector3.new(x, 12, 2.6)),
			rgb(255, 150, 60),
			Enum.Material.Neon
		)
		deco(
			root,
			"TorchHolder",
			Vector3.new(0.6, 1.4, 1.6),
			CFrame.new(gateAt + Vector3.new(x, 10.8, 2.4)),
			IRON,
			Enum.Material.Metal
		)
		local fire = Instance.new("Fire")
		fire.Size, fire.Heat = 3, 6
		fire.Color, fire.SecondaryColor = rgb(255, 150, 60), rgb(255, 230, 120)
		fire.Parent = torch
		glowLight(torch, 14, 1.4)
	end
	for _, edge in { -7.6, 7.6 } do
		deco(
			root,
			"PortalEdge",
			Vector3.new(0.5, 18.4, 1.2),
			CFrame.new(gateAt + Vector3.new(edge, 9, 0)),
			VIOLET,
			Enum.Material.Neon
		)
	end
	deco(
		root,
		"PortalEdgeTop",
		Vector3.new(15.6, 0.5, 1.2),
		CFrame.new(gateAt + Vector3.new(0, 18.2, 0)),
		VIOLET,
		Enum.Material.Neon
	)
	local swirl = Instance.new("ParticleEmitter")
	swirl.Color = ColorSequence.new(rgb(200, 160, 255))
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new(0.5, 0)
	swirl.Lifetime = NumberRange.new(1, 1.6)
	swirl.Rate = 14
	swirl.Speed = NumberRange.new(1, 2)
	swirl.SpreadAngle = Vector2.new(180, 180)
	local emitterPart = deco(
		root,
		"PortalMotes",
		Vector3.new(12, 16, 0.2),
		CFrame.new(gateAt + Vector3.new(0, 9, 0.8)),
		VIOLET
	)
	emitterPart.Transparency = 1
	swirl.Parent = emitterPart
	banner(root, gateAt + Vector3.new(16, 11, 1.4), rgb(110, 60, 150))
	-- board: wooden frame, a little roof and two lanterns
	local w, h = 26, 16
	for _, x in { -w / 2 - 0.5, w / 2 + 0.5 } do
		deco(
			root,
			"BoardPost",
			Vector3.new(1.2, h + 3, 1.2),
			CFrame.new(boardAt + Vector3.new(x, 0.5, 0)),
			WOOD,
			Enum.Material.Wood
		)
		local lamp = deco(
			root,
			"BoardLantern",
			Vector3.new(1, 1.2, 1),
			CFrame.new(boardAt + Vector3.new(x, h / 2 - 1, 1.2)),
			WARM,
			Enum.Material.Neon
		)
		glowLight(lamp, 12, 1)
	end
	deco(
		root,
		"BoardFrameTop",
		Vector3.new(w + 2.4, 1, 1.4),
		CFrame.new(boardAt + Vector3.new(0, h / 2 + 0.5, 0)),
		WOOD,
		Enum.Material.Wood
	)
	deco(
		root,
		"BoardFrameBottom",
		Vector3.new(w + 2.4, 0.8, 1.4),
		CFrame.new(boardAt + Vector3.new(0, -h / 2 - 0.4, 0)),
		WOOD,
		Enum.Material.Wood
	)
	for _, side in { -1, 1 } do
		local roof = Instance.new("WedgePart")
		roof.Name = "BoardRoof"
		roof.Size = Vector3.new(w + 4, 2, 2.4)
		roof.CFrame = CFrame.new(boardAt + Vector3.new(0, h / 2 + 2, side * 1.2))
			* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
		roof.Color = rgb(120, 50, 60)
		roof.Material = Enum.Material.Slate
		roof.Anchored = true
		roof.CanCollide, roof.CanQuery, roof.CanTouch = false, false, false
		roof.Parent = root
	end
	deco(
		root,
		"BoardTrim",
		Vector3.new(w + 0.6, 0.4, 1.2),
		CFrame.new(boardAt + Vector3.new(0, h / 2 - 0.1, 0.1)),
		GOLD,
		Enum.Material.Metal
	)
	banner(root, boardAt + Vector3.new(-w / 2 - 4, 2, 1.4), rgb(60, 80, 150))
end

local function new(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "Plaza"
	root:SetAttribute("PresentationId", PRESENTATION_ID)
	scenery(root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 30))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(196, 170, 112)
	spawn.Material = Enum.Material.Slate
	spawn.Parent = root

	-- dungeon entrance and the leaderboard side by side on the far side, facing the spawn
	local gateAt = CENTER + Vector3.new(12, 0, -SIZE / 2 + 12)
	local dark = Color3.fromRGB(70, 60, 75)
	part(root, "GateLeft", Vector3.new(4, 20, 4), CFrame.new(gateAt + Vector3.new(-9, 10, 0)), dark)
	part(root, "GateRight", Vector3.new(4, 20, 4), CFrame.new(gateAt + Vector3.new(9, 10, 0)), dark)
	part(root, "GateTop", Vector3.new(22, 4, 4), CFrame.new(gateAt + Vector3.new(0, 22, 0)), dark)
	local portal = part(
		root,
		"DungeonPortal",
		Vector3.new(14, 18, 1),
		CFrame.new(gateAt + Vector3.new(0, 9, 0)),
		Color3.fromRGB(140, 90, 255)
	)
	portal.Material = Enum.Material.Neon
	portal.Transparency = 0.35
	portal.CanCollide = false
	portal:SetAttribute("DungeonEntrance", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterDungeon"
	prompt.ActionText = "던전 입장"
	prompt.ObjectText = "등불 원정"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("DungeonEntrance", true)
	prompt.Parent = portal
	local sign = Instance.new("SurfaceGui")
	sign.Face = Enum.NormalId.Back
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = 20
	sign.Parent = root:FindFirstChild("GateTop")
	sign.LightInfluence = 0
	local signText = label(sign, "던전 입구", 52, Color3.fromRGB(255, 220, 140))
	signText.Size = UDim2.fromScale(1, 1)
	signText.Font = Enum.Font.BuilderSansExtraBold
	signText.TextStrokeColor3, signText.TextStrokeTransparency = Color3.fromRGB(60, 20, 90), 0.2
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(170, 120, 255), 24, 2
	glow.Parent = portal

	-- leaderboard right beside the entrance, facing the spawn
	local boardAt = CENTER + Vector3.new(-17, 9, -SIZE / 2 + 12)
	local board = part(
		root,
		"Leaderboard",
		Vector3.new(26, 16, 1),
		CFrame.new(boardAt),
		Color3.fromRGB(35, 38, 52)
	)
	part(
		root,
		"BoardStand",
		Vector3.new(28, 2, 2),
		CFrame.new(boardAt - Vector3.new(0, 9, 0)),
		dark
	)
	gateDecor(root, gateAt, boardAt)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient below supplies the colour
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(52, 48, 76), Color3.fromRGB(22, 24, 36))
	gradient.Rotation = 90
	gradient.Parent = frame
	local title = label(frame, "랭킹 · 이 서버", 40, Color3.fromRGB(255, 205, 80))
	title.Size = UDim2.fromScale(1, 0.12)
	title.Font = Enum.Font.BuilderSansExtraBold
	-- columns: rank, name, stage, survival, level (x offset as a fraction, width)
	local COLUMNS = {
		{ name = "순위", x = 0.02, w = 0.09 },
		{ name = "이름", x = 0.11, w = 0.3 },
		{ name = "난이도", x = 0.41, w = 0.15 },
		{ name = "스테이지", x = 0.56, w = 0.15 },
		{ name = "서바이벌", x = 0.71, w = 0.15 },
		{ name = "레벨", x = 0.86, w = 0.12 },
	}
	local muted = Color3.fromRGB(170, 172, 190)
	for _, column in COLUMNS do
		local head = label(frame, column.name, 20, muted)
		head.Size = UDim2.fromScale(column.w, 0.06)
		head.Position = UDim2.fromScale(column.x, 0.125)
	end
	local RANK_COLORS = {
		Color3.fromRGB(255, 205, 80),
		Color3.fromRGB(210, 216, 230),
		Color3.fromRGB(214, 150, 96),
	}
	local lines: { { TextLabel } } = {}
	for i = 1, PlazaBoard.BOARD_SIZE do
		local strip = Instance.new("Frame")
		strip.Name = "Row" .. i
		strip.Size = UDim2.fromScale(0.96, 0.07)
		strip.Position = UDim2.fromScale(0.02, 0.19 + (i - 1) * 0.08)
		strip.BackgroundColor3 = Color3.new(1, 1, 1)
		strip.BackgroundTransparency = if i % 2 == 1 then 0.93 else 0.97
		strip.BorderSizePixel = 0
		strip.Parent = frame
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 8)
		round.Parent = strip
		local cells: { TextLabel } = {}
		for c, column in COLUMNS do
			local cell = label(strip, "", 24, RANK_COLORS[i] or Color3.new(1, 1, 1))
			cell.Size = UDim2.fromScale(column.w / 0.96, 1)
			cell.Position = UDim2.fromScale((column.x - 0.02) / 0.96, 0)
			cell.TextTruncate = Enum.TextTruncate.AtEnd
			if c == 2 then
				cell.TextXAlignment = Enum.TextXAlignment.Left
			end
			cells[c] = cell
		end
		lines[i] = cells
	end
	local empty = label(frame, "아직 기록이 없습니다", 24, muted)
	empty.Size = UDim2.fromScale(1, 0.08)
	empty.Position = UDim2.fromScale(0, 0.22)
	root.Parent = parent

	local function updateBoard(rows: { PlazaBoard.Row })
		empty.Visible = #rows == 0
		for i, cells in lines do
			local row = rows[i]
			local strip = cells[1].Parent :: Frame
			strip.Visible = row ~= nil
			if row then
				cells[1].Text = if i <= 3 then ({ "1st", "2nd", "3rd" })[i] else tostring(i)
				cells[2].Text = row.name
				cells[3].Text = PlazaBoard.difficultyLabel(row.difficulty)
				cells[4].Text = PlazaBoard.stageLabel(row.stage)
				cells[5].Text = if row.wave > 0 then "W" .. row.wave else "-"
				cells[6].Text = if row.level > 0 then "Lv." .. row.level else "-"
			end
		end
	end
	updateBoard({})

	-- "원정 중" tag over avatars whose owner is inside a battle
	local function setExpedition(player: Player, inside: boolean)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not head then
			return
		end
		local tag = head:FindFirstChild("ExpeditionTag") :: BillboardGui?
		if inside and not tag then
			local created = Instance.new("BillboardGui")
			created.Name = "ExpeditionTag"
			created.Size = UDim2.fromOffset(96, 26)
			created.StudsOffset = Vector3.new(0, 3, 0)
			created.AlwaysOnTop = true
			created.MaxDistance = 120
			local text = label(created, "원정 중", 16, Color3.fromRGB(34, 26, 14))
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 0.1
			text.BackgroundColor3 = Color3.fromRGB(255, 205, 80)
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = text
			created.Parent = head
		elseif not inside and tag then
			tag:Destroy()
		end
	end

	return {
		root = root,
		portal = portal,
		prompt = prompt,
		spawn = spawn,
		updateBoard = updateBoard,
		setExpedition = setExpedition,
		boardLines = lines,
	}
end

return table.freeze({ new = new, CENTER = CENTER, PRESENTATION_ID = PRESENTATION_ID })
