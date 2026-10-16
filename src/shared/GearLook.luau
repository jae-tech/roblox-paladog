--!strict
-- Equipment looks on the player's real Roblox avatar (D-GEAR-01). Pure data: every equipped item code maps
-- to code-built pieces (blocks, balls, cylinders) that the server welds onto body parts, so everyone in the
-- plaza and the arena sees what a player wears. Numbers only, so the CLI can check every item.
--
-- Part fields: shape Block|Ball|Cyl (along X)|VCyl (along Y)|ZCyl (along Z)|Wedge, size {x,y,z},
-- at {x,y,z}, rot {x,y,z} degrees, color {r,g,b}, mat (Enum.Material name), neon, transp, core (the part
-- that glows with the item grade). rel = size and at are fractions of the anchor body part's size (armour,
-- helmets, boots); otherwise studs at the default R15 scale (weapons, the companion mount).
local GearLook = {}

export type Part = {
	shape: string,
	size: { number },
	at: { number },
	rot: { number }?,
	color: { number },
	mat: string?,
	neon: boolean?,
	transp: number?,
	core: boolean?,
	rel: boolean?,
}
-- anchor: body part name (R15), frame: piece offset {x,y,z,rx,ry,rz} in studs/degrees from the anchor
export type Piece = {
	id: string,
	slot: number,
	anchor: string,
	frame: { number }?,
	parts: { Part },
	grade: number,
	hidesHair: boolean?,
	companion: boolean?,
}

local function P(
	shape: string,
	size: { number },
	at: { number },
	color: { number },
	extra: { [string]: any }?
): Part
	local part: Part = { shape = shape, size = size, at = at, color = color }
	if extra then
		for key, value in extra do
			(part :: any)[key] = value
		end
	end
	return part
end

-- palette -------------------------------------------------------------------------------------------
local C = {
	gold = { 255, 200, 70 },
	brass = { 196, 150, 60 },
	steel = { 150, 158, 176 },
	darkSteel = { 82, 86, 100 },
	iron = { 120, 124, 134 },
	leather = { 110, 72, 44 },
	darkLeather = { 58, 44, 40 },
	wood = { 120, 84, 50 },
	red = { 190, 40, 46 },
	blue = { 60, 90, 200 },
	navy = { 36, 44, 96 },
	purple = { 112, 64, 170 },
	shadow = { 52, 40, 70 },
	bone = { 226, 220, 196 },
	white = { 244, 244, 240 },
	black = { 28, 28, 32 },
	green = { 70, 170, 80 },
	toxic = { 140, 230, 60 },
	cyan = { 110, 220, 255 },
	ice = { 190, 236, 255 },
	orange = { 255, 130, 40 },
	yellow = { 255, 230, 80 },
	pink = { 255, 120, 200 },
	brown = { 150, 100, 60 },
	fur = { 170, 120, 80 },
	soulTeal = { 90, 255, 200 },
}

-- light hero weapons: a lantern staff whose head shows the spell (maces 1..11) -------------------------
local function staff(head: { Part }): { Part }
	local parts = {
		P("VCyl", { 0.2, 3.4, 0.2 }, { 0, 0.9, 0 }, C.wood, { mat = "Wood" }),
		P("VCyl", { 0.3, 0.2, 0.3 }, { 0, 2.55, 0 }, C.brass, { mat = "Metal" }),
		P("VCyl", { 0.26, 0.16, 0.26 }, { 0, -0.75, 0 }, C.brass, { mat = "Metal" }),
	}
	for _, part in head do
		table.insert(parts, part)
	end
	return parts
end
local function orb(color: { number }, size: number): Part
	return P("Ball", { size, size, size }, { 0, 3.05, 0 }, color, { neon = true, core = true })
end
local MACES: { { Part } } = {
	-- 1 light fist: golden gauntlet-knuckle head
	staff({
		P("Block", { 0.7, 0.55, 0.55 }, { 0, 2.95, 0 }, C.gold, { mat = "Metal", core = true }),
		P("Ball", { 0.3, 0.3, 0.3 }, { 0, 3.3, 0 }, C.yellow, { neon = true }),
	}),
	-- 2 healing lantern: caged lantern
	staff({
		P(
			"Block",
			{ 0.55, 0.7, 0.55 },
			{ 0, 3.05, 0 },
			C.green,
			{ neon = true, core = true, transp = 0.2 }
		),
		P("Block", { 0.65, 0.08, 0.65 }, { 0, 3.44, 0 }, C.brass, { mat = "Metal" }),
		P("Block", { 0.65, 0.08, 0.65 }, { 0, 2.66, 0 }, C.brass, { mat = "Metal" }),
	}),
	-- 3 purify: white star orb with a halo ring
	staff({
		orb(C.white, 0.6),
		P(
			"VCyl",
			{ 0.95, 0.06, 0.95 },
			{ 0, 3.05, 0 },
			C.gold,
			{ neon = true, rot = { 70, 0, 0 } }
		),
	}),
	-- 4 frost orb
	staff({
		orb(C.cyan, 0.75),
		P(
			"Wedge",
			{ 0.2, 0.5, 0.3 },
			{ 0.32, 2.75, 0 },
			C.ice,
			{ mat = "Ice", rot = { 0, 0, -30 } }
		),
		P(
			"Wedge",
			{ 0.2, 0.5, 0.3 },
			{ -0.32, 2.75, 0 },
			C.ice,
			{ mat = "Ice", rot = { 0, 0, 30 } }
		),
	}),
	-- 5 lightning: forked yellow prongs
	staff({
		orb(C.yellow, 0.45),
		P(
			"Block",
			{ 0.1, 0.8, 0.1 },
			{ 0.25, 3.25, 0 },
			C.yellow,
			{ neon = true, rot = { 0, 0, -20 } }
		),
		P(
			"Block",
			{ 0.1, 0.8, 0.1 },
			{ -0.25, 3.25, 0 },
			C.yellow,
			{ neon = true, rot = { 0, 0, 20 } }
		),
	}),
	-- 6 flame wave
	staff({
		orb(C.orange, 0.65),
		P("Wedge", { 0.25, 0.6, 0.4 }, { 0, 3.5, 0 }, C.red, { neon = true }),
	}),
	-- 7 meteor: rock head with a burning core
	staff({
		P("Ball", { 0.85, 0.75, 0.8 }, { 0, 3.05, 0 }, C.darkLeather, { mat = "Slate" }),
		P("Ball", { 0.4, 0.4, 0.4 }, { 0, 3.05, -0.3 }, C.orange, { neon = true, core = true }),
	}),
	-- 8 gust: pale green swirl blades
	staff({
		orb({ 180, 255, 210 }, 0.45),
		P(
			"Wedge",
			{ 0.08, 0.35, 0.7 },
			{ 0, 3.05, 0.35 },
			{ 200, 255, 220 },
			{ rot = { 0, 0, 0 } }
		),
		P(
			"Wedge",
			{ 0.08, 0.35, 0.7 },
			{ 0, 3.05, -0.35 },
			{ 200, 255, 220 },
			{ rot = { 0, 180, 0 } }
		),
	}),
	-- 9 abundance: sprouting leaves
	staff({
		orb(C.green, 0.5),
		P(
			"Wedge",
			{ 0.1, 0.5, 0.35 },
			{ 0.25, 3.35, 0 },
			C.green,
			{ mat = "Grass", rot = { 0, 90, -30 } }
		),
		P(
			"Wedge",
			{ 0.1, 0.5, 0.35 },
			{ -0.25, 3.35, 0 },
			C.green,
			{ mat = "Grass", rot = { 0, -90, 30 } }
		),
	}),
	-- 10 poison orb
	staff({
		orb(C.toxic, 0.7),
		P("Ball", { 0.25, 0.25, 0.25 }, { 0.3, 2.7, 0 }, C.purple, { neon = true }),
	}),
	-- 11 golden hammer
	{
		P("VCyl", { 0.22, 2.6, 0.22 }, { 0, 0.6, 0 }, C.brass, { mat = "Metal" }),
		P("ZCyl", { 0.75, 0.75, 1.3 }, { 0, 2.05, 0 }, C.gold, { mat = "Metal", core = true }),
	},
}

-- shadow hero weapons (swords 1..11): blade along +Y from the hand
local function blade(
	length: number,
	width: number,
	color: { number },
	extra: { [string]: any }?
): { Part }
	local metal = if extra and extra.neon then nil else "Metal"
	local parts = {
		P("VCyl", { 0.2, 0.7, 0.2 }, { 0, 0, 0 }, C.darkLeather, { mat = "Fabric" }),
		P(
			"Block",
			{ 0.9, 0.12, 0.25 },
			{ 0, 0.4, 0 },
			(extra and extra.guard) or C.darkSteel,
			{ mat = "Metal" }
		),
		P(
			"Block",
			{ width, length, 0.08 },
			{ 0, 0.45 + length / 2, 0 },
			color,
			{ mat = metal, neon = extra and extra.neon, core = true }
		),
		P(
			"Wedge",
			{ width, 0.4, 0.08 },
			{ 0, 0.65 + length, 0 },
			color,
			{ mat = metal, rot = { 0, 90, 0 } }
		),
	}
	return parts
end
local function hammerHead(color: { number }, glow: { number }): { Part }
	return {
		P("VCyl", { 0.2, 2.6, 0.2 }, { 0, 0.7, 0 }, C.darkSteel, { mat = "Metal" }),
		P("Block", { 1.2, 0.7, 0.7 }, { 0, 2.1, 0 }, color, { mat = "Metal" }),
		P("Block", { 1.25, 0.18, 0.75 }, { 0, 2.1, 0 }, glow, { neon = true, core = true }),
	}
end
local SWORDS: { { Part } } = {
	blade(2.4, 0.3, C.shadow, { guard = C.purple }), -- shadow blade
	blade(2.8, 0.14, { 210, 230, 240 }), -- wind rapier
	blade(2.4, 0.32, C.red, { guard = C.black }), -- vampire sword
	blade(1.3, 0.25, C.toxic, { neon = true }), -- poison dagger
	blade(3.4, 0.6, C.iron, { guard = C.brass }), -- giant greatsword
	-- soul scythe: long haft with a curved teal blade
	{
		P("VCyl", { 0.18, 3.6, 0.18 }, { 0, 1.0, 0 }, C.black, { mat = "Wood" }),
		P(
			"Block",
			{ 1.6, 0.3, 0.08 },
			{ -0.6, 2.75, 0 },
			C.soulTeal,
			{ neon = true, core = true, rot = { 0, 0, -15 } }
		),
		P(
			"Wedge",
			{ 0.08, 0.3, 0.6 },
			{ -1.55, 2.5, 0 },
			C.soulTeal,
			{ neon = true, rot = { 0, 90, 0 } }
		),
	},
	hammerHead(C.shadow, C.purple), -- dimension hammer
	blade(2.6, 0.3, C.ice, { guard = C.cyan }), -- frost sword
	blade(2.6, 0.32, C.orange, { guard = C.red, neon = true }), -- flame sword
	hammerHead(C.darkSteel, C.yellow), -- thunder hammer
	blade(2.6, 0.32, C.gold, { guard = C.gold }), -- golden sword
}

-- helmets (rel to Head) ------------------------------------------------------------------------------
local function dome(color: { number }, mat: string?): Part
	return P(
		"Ball",
		{ 1.12, 0.95, 1.12 },
		{ 0, 0.18, 0.02 },
		color,
		{ rel = true, mat = mat or "Metal" }
	)
end
local function rim(color: { number }, y: number?): Part
	return P(
		"VCyl",
		{ 1.2, 0.12, 1.2 },
		{ 0, y or 0.12, 0.02 },
		color,
		{ rel = true, mat = "Metal" }
	)
end
local HELMET_SHAPES: { [string]: (base: { number }, accent: { number }) -> { Part } } = {
	commander = function(base, accent)
		return {
			dome(base),
			rim(C.gold),
			P("Block", { 0.1, 0.4, 0.08 }, { 0, 0.05, -0.56 }, base, { rel = true, mat = "Metal" }),
			P(
				"Block",
				{ 0.1, 0.4, 0.6 },
				{ 0, 0.72, 0.08 },
				accent,
				{ rel = true, mat = "Fabric", core = true }
			),
		}
	end,
	guardian = function(base, accent)
		return {
			dome(base),
			rim(accent, 0.1),
			P(
				"Block",
				{ 0.14, 0.55, 0.4 },
				{ 0.53, -0.08, -0.1 },
				base,
				{ rel = true, mat = "Metal" }
			),
			P(
				"Block",
				{ 0.14, 0.55, 0.4 },
				{ -0.53, -0.08, -0.1 },
				base,
				{ rel = true, mat = "Metal" }
			),
			P(
				"Block",
				{ 0.7, 0.12, 0.1 },
				{ 0, 0.32, -0.55 },
				accent,
				{ rel = true, neon = true, core = true }
			),
		}
	end,
	arcane = function(base, accent)
		return {
			P("VCyl", { 1.5, 0.06, 1.5 }, { 0, 0.32, 0 }, base, { rel = true, mat = "Fabric" }),
			P("VCyl", { 0.95, 0.35, 0.95 }, { 0, 0.5, 0 }, base, { rel = true, mat = "Fabric" }),
			P("VCyl", { 0.65, 0.35, 0.65 }, { 0, 0.8, 0.04 }, base, { rel = true, mat = "Fabric" }),
			P(
				"VCyl",
				{ 0.35, 0.35, 0.35 },
				{ 0, 1.08, 0.1 },
				base,
				{ rel = true, mat = "Fabric", rot = { 12, 0, 0 } }
			),
			P(
				"Ball",
				{ 0.18, 0.18, 0.18 },
				{ 0, 1.25, 0.16 },
				accent,
				{ rel = true, neon = true, core = true }
			),
			P("VCyl", { 0.98, 0.08, 0.98 }, { 0, 0.4, 0 }, accent, { rel = true }),
		}
	end,
	horned = function(base, accent)
		return {
			dome(base),
			rim(accent),
			P(
				"Wedge",
				{ 0.14, 0.55, 0.22 },
				{ 0.62, 0.45, 0 },
				C.bone,
				{ rel = true, rot = { 0, 90, -25 } }
			),
			P(
				"Wedge",
				{ 0.14, 0.55, 0.22 },
				{ -0.62, 0.45, 0 },
				C.bone,
				{ rel = true, rot = { 0, -90, 25 } }
			),
			P(
				"Ball",
				{ 0.16, 0.16, 0.16 },
				{ 0, 0.3, -0.55 },
				accent,
				{ rel = true, neon = true, core = true }
			),
		}
	end,
	necro = function(base, accent)
		return {
			dome(base, "Slate"),
			P(
				"Block",
				{ 0.14, 0.3, 0.9 },
				{ 0, 0.68, 0.05 },
				C.bone,
				{ rel = true, mat = "Marble" }
			),
			P(
				"Block",
				{ 0.75, 0.08, 0.06 },
				{ 0, 0.22, -0.56 },
				accent,
				{ rel = true, neon = true, core = true }
			),
			P("Wedge", { 0.1, 0.25, 0.2 }, { 0.3, 0.6, -0.3 }, C.bone, { rel = true }),
			P("Wedge", { 0.1, 0.25, 0.2 }, { -0.3, 0.6, -0.3 }, C.bone, { rel = true }),
		}
	end,
	pinwheel = function(base, accent)
		return {
			dome(base, "Fabric"),
			P("VCyl", { 0.05, 0.4, 0.05 }, { 0, 0.85, 0 }, C.wood, { rel = true }),
			P("Wedge", { 0.04, 0.3, 0.3 }, { 0, 1.15, -0.15 }, C.red, { rel = true, core = true }),
			P(
				"Wedge",
				{ 0.04, 0.3, 0.3 },
				{ 0, 1.15, 0.15 },
				C.blue,
				{ rel = true, rot = { 180, 0, 0 } }
			),
			P(
				"Wedge",
				{ 0.04, 0.3, 0.3 },
				{ 0, 1.0, 0 },
				C.yellow,
				{ rel = true, rot = { 90, 0, 0 } }
			),
			P(
				"Wedge",
				{ 0.04, 0.3, 0.3 },
				{ 0, 1.3, 0 },
				accent,
				{ rel = true, rot = { -90, 0, 0 } }
			),
			P(
				"Block",
				{ 1.0, 0.06, 0.45 },
				{ 0, 0.18, -0.6 },
				base,
				{ rel = true, mat = "Fabric" }
			),
		}
	end,
	golden = function(base, accent)
		return {
			dome(base),
			rim(accent),
			P(
				"Block",
				{ 0.12, 0.5, 0.85 },
				{ 0, 0.68, 0.02 },
				accent,
				{ rel = true, mat = "Metal" }
			),
			P(
				"Ball",
				{ 0.2, 0.2, 0.2 },
				{ 0, 0.4, -0.56 },
				C.red,
				{ rel = true, neon = true, core = true }
			),
		}
	end,
	fur = function(base, accent)
		return {
			P("VCyl", { 1.18, 0.55, 1.18 }, { 0, 0.5, 0.02 }, base, { rel = true, mat = "Fabric" }),
			P(
				"VCyl",
				{ 1.24, 0.2, 1.24 },
				{ 0, 0.25, 0.02 },
				accent,
				{ rel = true, mat = "Fabric" }
			),
			P(
				"Ball",
				{ 0.3, 0.3, 0.3 },
				{ 0, 0.85, 0 },
				accent,
				{ rel = true, mat = "Fabric", core = true }
			),
		}
	end,
	chef = function(base, accent)
		return {
			P(
				"VCyl",
				{ 1.05, 0.25, 1.05 },
				{ 0, 0.42, 0.02 },
				base,
				{ rel = true, mat = "Fabric" }
			),
			P("VCyl", { 1.0, 0.6, 1.0 }, { 0, 0.82, 0.02 }, base, { rel = true, mat = "Fabric" }),
			P(
				"Ball",
				{ 1.3, 0.55, 1.3 },
				{ 0, 1.15, 0.02 },
				base,
				{ rel = true, mat = "Fabric", core = true }
			),
			P("VCyl", { 1.07, 0.06, 1.07 }, { 0, 0.55, 0.02 }, accent, { rel = true }),
		}
	end,
	scholar = function(base, accent)
		return {
			P(
				"VCyl",
				{ 1.05, 0.35, 1.05 },
				{ 0, 0.42, 0.02 },
				base,
				{ rel = true, mat = "Fabric" }
			),
			P(
				"Block",
				{ 1.5, 0.06, 1.5 },
				{ 0, 0.62, 0.02 },
				base,
				{ rel = true, rot = { 0, 45, 0 } }
			),
			P("Ball", { 0.12, 0.12, 0.12 }, { 0, 0.67, 0.02 }, accent, { rel = true, core = true }),
			P("Block", { 0.04, 0.45, 0.04 }, { 0.62, 0.42, 0.02 }, accent, { rel = true }),
		}
	end,
	circlet = function(base, accent)
		return {
			P("VCyl", { 1.08, 0.08, 1.08 }, { 0, 0.22, 0 }, base, { rel = true, mat = "Metal" }),
			P(
				"Ball",
				{ 0.16, 0.2, 0.08 },
				{ 0, 0.26, -0.55 },
				accent,
				{ rel = true, neon = true, core = true }
			),
		}
	end,
	hood = function(base, accent)
		return {
			P("Ball", { 1.24, 1.15, 1.2 }, { 0, 0.12, 0.1 }, base, { rel = true, mat = "Fabric" }),
			P("Block", { 0.9, 0.35, 0.1 }, { 0, -0.3, -0.5 }, base, { rel = true, mat = "Fabric" }),
			P(
				"Block",
				{ 0.5, 0.06, 0.04 },
				{ 0, 0.05, -0.62 },
				accent,
				{ rel = true, neon = true, core = true }
			),
		}
	end,
}
-- light helmets 1..10 and dark helmets 1..10: shape and colours
local HELMETS = {
	{ shape = "commander", base = C.steel, accent = C.red },
	{ shape = "guardian", base = C.steel, accent = C.blue },
	{ shape = "arcane", base = C.navy, accent = C.cyan },
	{ shape = "horned", base = C.brass, accent = C.orange },
	{ shape = "necro", base = C.black, accent = C.toxic },
	{ shape = "pinwheel", base = C.yellow, accent = C.green },
	{ shape = "golden", base = C.gold, accent = C.brass },
	{ shape = "fur", base = C.fur, accent = C.white },
	{ shape = "chef", base = C.white, accent = C.red },
	{ shape = "scholar", base = C.black, accent = C.gold },
}
local DARK_HELMETS = {
	{ shape = "commander", base = C.darkSteel, accent = C.purple },
	{ shape = "guardian", base = C.darkSteel, accent = C.soulTeal },
	{ shape = "horned", base = C.shadow, accent = C.purple },
	{ shape = "circlet", base = C.gold, accent = C.purple },
	{ shape = "hood", base = C.darkLeather, accent = C.red },
	{ shape = "pinwheel", base = C.shadow, accent = C.purple },
	{ shape = "golden", base = C.brass, accent = C.purple },
	{ shape = "fur", base = C.darkLeather, accent = C.bone },
	{ shape = "chef", base = C.bone, accent = C.purple },
	{ shape = "scholar", base = C.shadow, accent = C.purple },
}

-- armour: chest plate + belt + pauldrons, optional cape or robe panels -----------------------------------
type ArmorStyle = {
	base: { number },
	trim: { number },
	mat: string,
	pauldron: boolean,
	cape: { number }?,
	robe: boolean?,
	glow: { number }?,
}
local function armor(style: ArmorStyle): { [string]: { Part } }
	local chest = {
		P(
			"Block",
			{ 1.08, 0.92, 1.18 },
			{ 0, 0.03, 0 },
			style.base,
			{ rel = true, mat = style.mat }
		),
		P("Block", { 1.1, 0.1, 1.2 }, { 0, -0.42, 0 }, style.trim, { rel = true, mat = "Metal" }),
	}
	if style.glow then
		table.insert(
			chest,
			P(
				"Ball",
				{ 0.16, 0.16, 0.08 },
				{ 0, 0.2, -0.6 },
				style.glow,
				{ rel = true, neon = true, core = true }
			)
		)
	else
		table.insert(
			chest,
			P(
				"Block",
				{ 0.2, 0.2, 0.06 },
				{ 0, 0.2, -0.6 },
				style.trim,
				{ rel = true, mat = "Metal", core = true }
			)
		)
	end
	if style.cape then
		table.insert(
			chest,
			P(
				"Block",
				{ 0.95, 1.75, 0.05 },
				{ 0, -0.4, 0.62 },
				style.cape,
				{ rel = true, mat = "Fabric", rot = { -6, 0, 0 } }
			)
		)
	end
	local pieces: { [string]: { Part } } = {
		UpperTorso = chest,
		LowerTorso = {
			P(
				"Block",
				{ 1.1, 0.5, 1.2 },
				{ 0, 0.15, 0 },
				style.trim,
				{ rel = true, mat = "Leather" }
			),
		},
	}
	if style.robe then
		table.insert(
			pieces.LowerTorso,
			P(
				"Block",
				{ 0.75, 2.2, 0.06 },
				{ 0, -0.95, -0.6 },
				style.base,
				{ rel = true, mat = "Fabric" }
			)
		)
		table.insert(
			pieces.LowerTorso,
			P(
				"Block",
				{ 0.9, 2.2, 0.06 },
				{ 0, -0.95, 0.6 },
				style.base,
				{ rel = true, mat = "Fabric" }
			)
		)
	end
	if style.pauldron then
		for _, side in { "LeftUpperArm", "RightUpperArm" } do
			pieces[side] = {
				P(
					"Ball",
					{ 1.35, 0.55, 1.35 },
					{ 0, 0.32, 0 },
					style.base,
					{ rel = true, mat = style.mat }
				),
				P(
					"VCyl",
					{ 1.38, 0.08, 1.38 },
					{ 0, 0.18, 0 },
					style.trim,
					{ rel = true, mat = "Metal" }
				),
			}
		end
	end
	return pieces
end
local ARMORS: { ArmorStyle } = {
	{ base = C.steel, trim = C.gold, mat = "Metal", pauldron = true, cape = C.red }, -- commander
	{ base = C.iron, trim = C.blue, mat = "DiamondPlate", pauldron = true, glow = C.cyan }, -- guardian
	{ base = C.navy, trim = C.gold, mat = "Fabric", pauldron = false, robe = true, glow = C.cyan }, -- arcane
	{ base = { 170, 70, 50 }, trim = C.brass, mat = "Metal", pauldron = true, glow = C.orange }, -- spirit
	{
		base = C.black,
		trim = C.bone,
		mat = "Slate",
		pauldron = true,
		cape = C.shadow,
		glow = C.toxic,
	}, -- necro
}
local DARK_ARMORS: { ArmorStyle } = {
	{ base = C.darkSteel, trim = C.purple, mat = "Metal", pauldron = true, cape = C.shadow },
	{
		base = C.darkSteel,
		trim = C.soulTeal,
		mat = "DiamondPlate",
		pauldron = true,
		glow = C.soulTeal,
	},
	{ base = C.shadow, trim = C.red, mat = "Metal", pauldron = true, glow = C.red },
	{
		base = C.purple,
		trim = C.gold,
		mat = "Fabric",
		pauldron = false,
		robe = true,
		glow = C.pink,
	},
	{ base = C.darkLeather, trim = C.black, mat = "Leather", pauldron = false, cape = C.black },
}

-- dark feet: boots over the feet and shins
local BOOTS = {
	{ base = C.darkSteel, trim = C.purple, mat = "Metal" },
	{ base = C.darkSteel, trim = C.soulTeal, mat = "DiamondPlate" },
	{ base = C.shadow, trim = C.red, mat = "Metal" },
	{ base = C.purple, trim = C.gold, mat = "Leather" },
	{ base = C.darkLeather, trim = C.black, mat = "Leather" },
}

-- rings (left hand bands) and amulets (pendant), by stat theme 1..10
local GEM = {
	C.cyan, -- learning
	C.gold, -- wealth
	C.green, -- luck
	C.red, -- vitality
	C.pink, -- recovery
	{ 200, 255, 200 }, -- speed
	C.blue, -- mana
	C.purple, -- mana regen / origin
	C.orange, -- harvest
	C.brown, -- storehouse
}

-- companion mounts (horses 1..5): walk beside the hero; studs from the mount root
type HorseStyle = {
	body: { number },
	mane: { number },
	saddle: { number },
	mat: string,
	extra: string?,
}
local HORSES: { HorseStyle } = {
	{ body = C.brown, mane = C.black, saddle = C.red, mat = "SmoothPlastic" }, -- commander
	{ body = C.white, mane = C.steel, saddle = C.blue, mat = "SmoothPlastic", extra = "barding" }, -- guardian
	{ body = C.white, mane = C.pink, saddle = C.gold, mat = "SmoothPlastic", extra = "horn" }, -- unicorn
	{ body = C.iron, mane = C.darkSteel, saddle = C.black, mat = "Metal", extra = "steel" }, -- steel
	{ body = C.bone, mane = C.black, saddle = C.shadow, mat = "Marble", extra = "skeleton" }, -- skeleton
}
local function horse(style: HorseStyle): { Part }
	local parts = {
		P("Block", { 1.4, 1.3, 3.2 }, { 0, 0, 0 }, style.body, { mat = style.mat }),
		P(
			"Block",
			{ 0.7, 1.5, 0.8 },
			{ 0, 0.95, -1.45 },
			style.body,
			{ mat = style.mat, rot = { -30, 0, 0 } }
		),
		P("Block", { 0.7, 0.7, 1.3 }, { 0, 1.6, -2.05 }, style.body, { mat = style.mat }),
		P(
			"Block",
			{ 0.2, 1.3, 0.9 },
			{ 0, 1.15, -1.3 },
			style.mane,
			{ mat = "Fabric", rot = { -30, 0, 0 } }
		),
		P(
			"Block",
			{ 0.22, 1.1, 0.25 },
			{ 0, -0.05, 1.75 },
			style.mane,
			{ mat = "Fabric", rot = { 25, 0, 0 } }
		),
		P(
			"Block",
			{ 1.5, 0.25, 1.2 },
			{ 0, 0.72, 0.1 },
			style.saddle,
			{ mat = "Leather", core = true }
		),
	}
	for _, leg in { { 0.45, -1.15 }, { -0.45, -1.15 }, { 0.45, 1.15 }, { -0.45, 1.15 } } do
		table.insert(
			parts,
			P(
				"VCyl",
				{ 0.35, 2.0, 0.35 },
				{ leg[1], -1.6, leg[2] },
				style.body,
				{ mat = style.mat }
			)
		)
		table.insert(parts, P("VCyl", { 0.4, 0.25, 0.4 }, { leg[1], -2.55, leg[2] }, C.black, {}))
	end
	if style.extra == "barding" then
		table.insert(
			parts,
			P("Block", { 1.5, 0.8, 3.3 }, { 0, -0.15, 0 }, C.steel, { mat = "Metal" })
		)
		table.insert(
			parts,
			P("Block", { 0.75, 0.3, 1.0 }, { 0, 1.8, -2.1 }, C.steel, { mat = "Metal" })
		)
	elseif style.extra == "horn" then
		table.insert(
			parts,
			P(
				"Block",
				{ 0.14, 0.9, 0.14 },
				{ 0, 2.2, -2.45 },
				C.gold,
				{ neon = true, rot = { -40, 0, 0 } }
			)
		)
	elseif style.extra == "skeleton" then
		for i = 0, 3 do
			table.insert(
				parts,
				P(
					"Block",
					{ 1.5, 0.12, 0.15 },
					{ 0, -0.1, -0.9 + i * 0.55 },
					C.black,
					{ mat = "Slate" }
				)
			)
		end
		table.insert(
			parts,
			P("Ball", { 0.18, 0.18, 0.18 }, { 0.3, 1.75, -2.4 }, C.toxic, { neon = true })
		)
		table.insert(
			parts,
			P("Ball", { 0.18, 0.18, 0.18 }, { -0.3, 1.75, -2.4 }, C.toxic, { neon = true })
		)
	elseif style.extra == "steel" then
		table.insert(
			parts,
			P("Block", { 0.72, 0.12, 1.32 }, { 0, 1.6, -2.05 }, C.cyan, { neon = true })
		)
	end
	return parts
end

-- weapon placement by equip slot: 1 in the right hand, 2 across the back, 3 at the left hip
local WEAPON_FRAMES: { { anchor: string, frame: { number } } } = {
	{ anchor = "RightHand", frame = { 0, -0.15, 0, -20, 0, 0 } },
	{ anchor = "UpperTorso", frame = { 0, -0.4, 0.7, 0, 0, 35 } },
	{ anchor = "LowerTorso", frame = { -0.95, 0.1, 0, 0, 0, 160 } },
}

local CATEGORY_COUNT = { 11, 10, 10, 5, 5, 11, 10, 10, 5, 5 }
GearLook.CATEGORY_COUNT = CATEGORY_COUNT

local function decode(code: number): (number, number, number)
	return code // 100000, (code // 1000) % 100, code % 1000
end
GearLook.decode = decode

-- Pieces for one equipped item in equip slot `slot` (1..9), or {} for empty/unknown codes.
function GearLook.pieces(slot: number, code: number): { Piece }
	if code == 0 then
		return {}
	end
	local category, num, grade = decode(code)
	if not CATEGORY_COUNT[category] or num < 1 or num > CATEGORY_COUNT[category] then
		return {}
	end
	local id = string.format("%d:%d", category, num)
	if category == 1 or category == 6 then
		local place = WEAPON_FRAMES[slot]
		if not place then
			return {}
		end
		local parts = if category == 1 then MACES[num] else SWORDS[num]
		return {
			{
				id = id,
				slot = slot,
				anchor = place.anchor,
				frame = place.frame,
				parts = parts,
				grade = grade,
			},
		}
	elseif category == 2 or category == 7 then
		local gem = GEM[num]
		local index = math.clamp(slot - 3, 1, 3)
		if category == 2 then
			-- a band per ring slot, stacked down the left hand
			local y = 0.2 - (index - 1) * 0.22
			return {
				{
					id = id,
					slot = slot,
					anchor = "LeftHand",
					parts = {
						P(
							"VCyl",
							{ 1.12, 0.12, 1.12 },
							{ 0, y, 0 },
							C.gold,
							{ rel = true, mat = "Metal" }
						),
						P(
							"Ball",
							{ 0.28, 0.2, 0.22 },
							{ 0, y, -0.55 },
							gem,
							{ rel = true, neon = true, core = true }
						),
					},
					grade = grade,
				},
			}
		end
		-- amulets hang on the chest, side by side
		local x = (index - 2) * 0.22
		return {
			{
				id = id,
				slot = slot,
				anchor = "UpperTorso",
				parts = {
					P(
						"Block",
						{ 0.04, 0.35, 0.04 },
						{ x, 0.32, -0.55 },
						C.brass,
						{ rel = true, mat = "Metal" }
					),
					P(
						"Ball",
						{ 0.13, 0.13, 0.1 },
						{ x, 0.12, -0.57 },
						gem,
						{ rel = true, neon = true, core = true }
					),
				},
				grade = grade,
			},
		}
	elseif category == 3 or category == 8 then
		local row = (if category == 3 then HELMETS else DARK_HELMETS)[num]
		local shape = HELMET_SHAPES[row.shape]
		return {
			{
				id = id,
				slot = slot,
				anchor = "Head",
				parts = shape(row.base, row.accent),
				grade = grade,
				hidesHair = row.shape ~= "circlet", -- a circlet sits on the hair
			},
		}
	elseif category == 4 or category == 9 then
		local pieces: { Piece } = {}
		local byPart = armor((if category == 4 then ARMORS else DARK_ARMORS)[num])
		for _, anchor in { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" } do
			if byPart[anchor] then
				table.insert(
					pieces,
					{ id = id, slot = slot, anchor = anchor, parts = byPart[anchor], grade = grade }
				)
			end
		end
		return pieces
	elseif category == 10 then
		local row = BOOTS[num]
		local pieces: { Piece } = {}
		for _, side in { "Left", "Right" } do
			table.insert(pieces, {
				id = id,
				slot = slot,
				anchor = side .. "Foot",
				parts = {
					P(
						"Block",
						{ 1.12, 1.1, 1.08 },
						{ 0, 0.05, 0 },
						row.base,
						{ rel = true, mat = row.mat }
					),
					P("Block", { 1.14, 0.12, 1.1 }, { 0, -0.42, 0 }, C.black, { rel = true }),
				},
				grade = grade,
			})
			table.insert(pieces, {
				id = id,
				slot = slot,
				anchor = side .. "LowerLeg",
				parts = {
					P(
						"Block",
						{ 1.12, 0.55, 1.12 },
						{ 0, -0.2, 0 },
						row.base,
						{ rel = true, mat = row.mat }
					),
					P(
						"Block",
						{ 1.16, 0.1, 1.16 },
						{ 0, 0.08, 0 },
						row.trim,
						{ rel = true, neon = true, core = true }
					),
				},
				grade = grade,
			})
		end
		return pieces
	end
	-- category 5: companion horse beside the hero (root at hip height, right side, a little behind)
	return {
		{
			id = id,
			slot = slot,
			anchor = "HumanoidRootPart",
			frame = { 3.6, -0.4, 1.2, 0, 0, 0 },
			parts = horse(HORSES[num]),
			grade = grade,
			companion = true,
		},
	}
end

-- Every piece the slot's equipment shows; key changes whenever the look changes.
function GearLook.look(equip: { number }): ({ Piece }, string)
	local pieces: { Piece } = {}
	local codes = {}
	for slot = 1, 9 do
		local code = equip[slot] or 0
		table.insert(codes, tostring(code))
		for _, piece in GearLook.pieces(slot, code) do
			table.insert(pieces, piece)
		end
	end
	return pieces, table.concat(codes, ",")
end

GearLook.SHAPES =
	table.freeze({ Block = true, Ball = true, Cyl = true, VCyl = true, ZCyl = true, Wedge = true })
GearLook.ANCHORS = table.freeze({
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	RightUpperArm = true,
	LeftHand = true,
	RightHand = true,
	LeftFoot = true,
	RightFoot = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
	HumanoidRootPart = true,
})

return table.freeze(GearLook)
