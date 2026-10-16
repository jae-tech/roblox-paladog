--!strict
-- Battle figures and dungeon maps (D-FIG-01). Pure data: every mercenary, totem, monster, boss and the
-- chapter dungeons are code-built parts (blocks, balls, cylinders, wedges) that the client turns into
-- anchored, visual-only models. Numbers only, so the CLI can check every design.
--
-- Figure space: studs, feet on y = 0, the figure faces -Z, +X is its right hand. Part fields follow GearLook
-- (shape Block|Ball|Cyl (along X)|VCyl (along Y)|ZCyl (along Z)|Wedge, size, at, rot degrees, color, mat,
-- neon, transp) plus g (animation group) with pv (the joint the group turns around) and light (a point
-- light {range, brightness} in the part's color).
local FigureLook = {}

export type Part = {
	shape: string,
	size: { number },
	at: { number },
	rot: { number }?,
	color: { number },
	mat: string?,
	neon: boolean?,
	transp: number?,
	g: string?,
	pv: { number }?,
	light: { number }?,
}
export type Figure = {
	id: string,
	parts: { Part },
	height: number,
	scale: number,
	flying: boolean,
}
export type Lighting = {
	clock: number,
	ambient: { number },
	outdoor: { number },
	fog: { number },
	fogStart: number,
	fogEnd: number,
	brightness: number,
}
export type Map = {
	chapter: number,
	name: string,
	parts: { Part },
	lighting: Lighting,
}

FigureLook.SHAPES = table.freeze({
	Block = true,
	Ball = true,
	Cyl = true,
	VCyl = true,
	ZCyl = true,
	Wedge = true,
})
-- the axis each animation group turns around
FigureLook.AXIS = table.freeze({
	legL = "X",
	legR = "X",
	armL = "X",
	armR = "X",
	head = "X",
	tail = "Y",
	wingL = "Z",
	wingR = "Z",
})
FigureLook.COUNT = table.freeze({ Unit = 9, Totem = 9, Enemy = 20, Boss = 10 })

-- palette -------------------------------------------------------------------------------------------
local C = {
	gold = { 255, 200, 70 },
	brass = { 196, 150, 60 },
	steel = { 160, 168, 184 },
	darkSteel = { 70, 74, 88 },
	iron = { 112, 116, 126 },
	leather = { 110, 72, 44 },
	darkLeather = { 62, 46, 40 },
	wood = { 120, 84, 50 },
	darkWood = { 74, 52, 36 },
	red = { 196, 44, 48 },
	darkRed = { 120, 28, 34 },
	blue = { 64, 104, 210 },
	navy = { 36, 44, 96 },
	purple = { 120, 70, 180 },
	violet = { 186, 110, 255 },
	shadow = { 52, 40, 70 },
	bone = { 230, 224, 200 },
	white = { 246, 246, 242 },
	black = { 26, 26, 30 },
	green = { 74, 160, 84 },
	darkGreen = { 44, 92, 56 },
	toxic = { 150, 235, 70 },
	cyan = { 110, 220, 255 },
	ice = { 196, 238, 255 },
	orange = { 255, 136, 40 },
	yellow = { 255, 226, 80 },
	pink = { 246, 160, 186 },
	tan = { 222, 196, 150 },
	rot = { 128, 156, 112 },
	cloth = { 100, 84, 70 },
}

-- builder -------------------------------------------------------------------------------------------
type Builder = {
	parts: { Part },
	group: string?,
	pivot: { number }?,
}

local function new(): Builder
	return { parts = {}, group = nil, pivot = nil }
end

local function put(
	b: Builder,
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
	if b.group and part.g == nil then
		part.g, part.pv = b.group, b.pivot
	end
	table.insert(b.parts, part)
	return part
end

-- parts added inside fn turn with the group around the pivot
local function within(b: Builder, group: string, pivot: { number }, fn: () -> ())
	local g, p = b.group, b.pivot
	b.group, b.pivot = group, pivot
	fn()
	b.group, b.pivot = g, p
end

-- parts from index `from` on turn with a group (designs built without within)
local function regroup(b: Builder, group: string, pivot: { number }, from: number)
	for i = from, #b.parts do
		b.parts[i].g, b.parts[i].pv = group, pivot
	end
end

local function done(b: Builder, id: string, scale: number?, flying: boolean?): Figure
	local top = 0
	for _, part in b.parts do
		local reach = part.at[2] + math.max(part.size[1], part.size[2], part.size[3]) * 0.5
		if part.shape ~= "Ball" and not part.rot then
			reach = part.at[2] + part.size[2] * 0.5
		end
		top = math.max(top, reach)
	end
	local s = scale or 1
	return {
		id = id,
		parts = b.parts,
		height = top * s + (if flying then 0.8 * s else 0),
		scale = s,
		flying = flying == true,
	}
end

-- body ------------------------------------------------------------------------------------------------
type BodyOpts = {
	skin: { number },
	cloth: { number }?,
	pants: { number }?,
	feet: { number }?,
	hands: { number }?,
	sleeve: { number }?,
	torso: { number },
	head: { number },
	leg: number,
	arm: number?,
	limb: number?,
	headShape: string?,
	torsoShape: string?,
	mat: string?,
	skinMat: string?,
	headY: number?,
	headZ: number?,
}
type Body = {
	b: Builder,
	hip: number,
	chest: number,
	torso: { number },
	headC: { number },
	headS: { number },
	top: number,
	front: number,
	back: number,
	shoulder: { [string]: { number } },
	hand: { [string]: { number } },
	limb: number,
	blockHead: boolean,
}

local SIDES = { { s = -1, n = "L" }, { s = 1, n = "R" } }

local function biped(o: BodyOpts, b: Builder?): Body
	local builder = b or new()
	local tw, th, td = o.torso[1], o.torso[2], o.torso[3]
	local limb = o.limb or math.min(tw * 0.36, 0.55)
	local leg = o.leg
	local pants = o.pants or o.cloth or o.skin
	local feet = o.feet or pants
	-- bare fur and skin stay smooth; the material is for clothes and armour
	local function matOf(color: { number }): string?
		return if color == o.skin then o.skinMat else o.mat
	end
	for _, side in SIDES do
		local s, n = side.s, side.n
		local x = s * tw * 0.25
		within(builder, "leg" .. n, { x, leg, 0 }, function()
			put(
				builder,
				"Block",
				{ limb, leg, limb * 1.05 },
				{ x, leg / 2, 0 },
				pants,
				{ mat = matOf(pants) }
			)
			put(
				builder,
				"Block",
				{ limb * 1.15, math.min(limb * 0.5, leg * 0.4), limb * 1.45 },
				{ x, math.min(limb * 0.25, leg * 0.2), -limb * 0.22 },
				feet
			)
		end)
	end
	local chest = leg + th / 2
	put(
		builder,
		o.torsoShape or "Block",
		{ tw, th, td },
		{ 0, chest, 0 },
		o.cloth or o.skin,
		{ mat = matOf(o.cloth or o.skin) }
	)
	local hs = o.head
	local hy = o.headY or (leg + th + hs[2] / 2 - 0.08)
	local hz = o.headZ or 0
	put(builder, o.headShape or "Ball", hs, { 0, hy, hz }, o.skin, { mat = o.skinMat })
	local arm = o.arm or th * 0.95
	local shoulderY = leg + th - limb * 0.4
	local shoulder: { [string]: { number } } = {}
	local hand: { [string]: { number } } = {}
	for _, side in SIDES do
		local s, n = side.s, side.n
		local x = s * (tw / 2 + limb * 0.42)
		shoulder[n] = { x, shoulderY, 0 }
		hand[n] = { x, shoulderY - arm + limb * 0.2, 0 }
		within(builder, "arm" .. n, shoulder[n], function()
			put(
				builder,
				"Block",
				{ limb * 0.9, arm, limb * 0.9 },
				{ x, shoulderY - arm / 2 + limb * 0.3, 0 },
				o.sleeve or o.cloth or o.skin,
				{ mat = matOf(o.sleeve or o.cloth or o.skin) }
			)
			put(
				builder,
				"Ball",
				{ limb * 1.05, limb * 1.05, limb * 1.05 },
				hand[n],
				o.hands or o.skin,
				{ mat = o.skinMat }
			)
		end)
	end
	return {
		b = builder,
		hip = leg,
		chest = chest,
		torso = o.torso,
		headC = { 0, hy, hz },
		headS = hs,
		top = hy + hs[2] / 2,
		front = hz - hs[3] / 2,
		back = td / 2,
		shoulder = shoulder,
		hand = hand,
		limb = limb,
		blockHead = o.headShape == "Block",
	}
end

local function eyes(
	body: Body,
	color: { number }?,
	pupil: { number }?,
	size: number?,
	lift: number?,
	spread: number?
)
	local hs, hc = body.headS, body.headC
	local s = size or hs[1] * 0.24
	local y = hc[2] + hs[2] * (lift or 0.08)
	local z = hc[3] - hs[3] * (if body.blockHead then 0.5 else 0.43)
	for _, side in SIDES do
		local x = side.s * hs[1] * (spread or 0.22)
		local glow = color and color ~= C.white
		put(body.b, "Ball", { s, s, s * 0.6 }, { x, y, z }, color or C.white, { neon = glow })
		if pupil then
			put(body.b, "Ball", { s * 0.5, s * 0.5, s * 0.3 }, { x, y, z - s * 0.22 }, pupil)
		end
	end
end

-- something held in a hand: parts turn with that arm
local function hold(body: Body, side: string, fn: (h: { number }) -> ())
	within(body.b, "arm" .. side, body.shoulder[side], function()
		fn(body.hand[side])
	end)
end

local function off(p: { number }, x: number, y: number, z: number): { number }
	return { p[1] + x, p[2] + y, p[3] + z }
end

-- copies parts into b moved by (x, y, z), joints included
local function shift(b: Builder, parts: { Part }, x: number, y: number, z: number)
	for _, part in parts do
		part.at = off(part.at, x, y, z)
		if part.pv then
			part.pv = off(part.pv, x, y, z)
		end
		table.insert(b.parts, part)
	end
end

-- weapons ---------------------------------------------------------------------------------------------
local function spear(b: Builder, h: { number }, length: number, tip: { number }, shaft: { number }?)
	put(
		b,
		"VCyl",
		{ 0.12, length, 0.12 },
		off(h, 0, length * 0.32, -0.05),
		shaft or C.wood,
		{ mat = "Wood" }
	)
	put(
		b,
		"Ball",
		{ 0.22, 0.6, 0.14 },
		off(h, 0, length * 0.82 + 0.15, -0.05),
		tip,
		{ mat = "Metal" }
	)
end

local function sword(
	b: Builder,
	h: { number },
	length: number,
	blade: { number },
	extra: { [string]: any }?
)
	put(
		b,
		"Block",
		{ 0.12, length, 0.32 },
		off(h, 0, length / 2 + 0.3, -0.1),
		blade,
		extra or { mat = "Metal" }
	)
	put(b, "Block", { 0.2, 0.12, 0.75 }, off(h, 0, 0.28, -0.1), C.brass, { mat = "Metal" })
	put(b, "VCyl", { 0.14, 0.4, 0.14 }, off(h, 0, 0.05, -0.1), C.darkLeather)
end

local function axe(b: Builder, h: { number }, length: number, head: { number })
	put(
		b,
		"VCyl",
		{ 0.14, length, 0.14 },
		off(h, 0, length * 0.35, 0),
		C.darkWood,
		{ mat = "Wood" }
	)
	put(b, "Wedge", { 0.14, 0.9, 0.7 }, off(h, 0, length * 0.75, -0.42), head, { mat = "Metal" })
	put(
		b,
		"Wedge",
		{ 0.14, 0.9, 0.7 },
		off(h, 0, length * 0.75, 0.42),
		head,
		{ mat = "Metal", rot = { 0, 180, 0 } }
	)
end

local function bow(b: Builder, h: { number }, size: number, color: { number })
	local z = h[3] - 0.3
	put(b, "Block", { 0.12, size * 0.5, 0.12 }, { h[1], h[2], z - 0.1 }, color, { mat = "Wood" })
	put(
		b,
		"Block",
		{ 0.1, size * 0.45, 0.1 },
		{ h[1], h[2] + size * 0.42, z + 0.02 },
		color,
		{ mat = "Wood", rot = { 22, 0, 0 } }
	)
	put(
		b,
		"Block",
		{ 0.1, size * 0.45, 0.1 },
		{ h[1], h[2] - size * 0.42, z + 0.02 },
		color,
		{ mat = "Wood", rot = { -22, 0, 0 } }
	)
	put(b, "VCyl", { 0.03, size * 1.25, 0.03 }, { h[1], h[2], z + 0.18 }, C.white)
end

local function shield(
	b: Builder,
	at: { number },
	d: number,
	face: { number },
	rim: { number },
	boss: { number }?
)
	put(b, "ZCyl", { d, d, 0.14 }, at, rim, { mat = "Metal" })
	put(b, "ZCyl", { d * 0.84, d * 0.84, 0.16 }, at, face, { mat = "Wood" })
	put(
		b,
		"Ball",
		{ d * 0.25, d * 0.25, d * 0.16 },
		off(at, 0, 0, -0.08),
		boss or rim,
		{ mat = "Metal" }
	)
end

-- a small cone from stacked cylinders (hats, horns pointing up)
local function cone(
	b: Builder,
	at: { number },
	base: number,
	height: number,
	color: { number },
	extra: { [string]: any }?
)
	local steps = 3
	for i = 1, steps do
		local d = base * (1 - (i - 1) / steps)
		put(
			b,
			"VCyl",
			{ d, height / steps, d },
			off(at, 0, (i - 0.5) * height / steps, 0),
			color,
			extra
		)
	end
end

local function horns(
	b: Builder,
	body: Body,
	color: { number },
	length: number,
	spread: number?,
	tilt: number?
)
	local hc, hs = body.headC, body.headS
	for _, side in SIDES do
		local s = side.s
		put(
			b,
			"Ball",
			{ 0.22, length, 0.22 },
			{ s * hs[1] * (spread or 0.38), hc[2] + hs[2] * 0.42 + length * 0.3, hc[3] },
			color,
			{ rot = { 0, 0, -s * (tilt or 28) } }
		)
	end
end

-- skeleton body: thin bone limbs, ribs and a skull with dark sockets
local function skeleton(tint: { number }?, scale: number?): Body
	local k = scale or 1
	local bone = tint or C.bone
	local body = biped({
		skin = bone,
		cloth = { 60, 56, 52 },
		pants = bone,
		feet = bone,
		torso = { 0.9 * k, 1.05 * k, 0.45 * k },
		head = { 0.95 * k, 0.95 * k, 0.95 * k },
		leg = 1.0 * k,
		limb = 0.22 * k,
		headShape = "Ball",
	})
	for i = 0, 2 do
		put(
			body.b,
			"Block",
			{ 1.0 * k, 0.12 * k, 0.55 * k },
			{ 0, body.chest + (0.3 - i * 0.28) * k, 0 },
			bone
		)
	end
	put(body.b, "VCyl", { 0.16 * k, 1.05 * k, 0.16 * k }, { 0, body.chest, 0.15 * k }, bone)
	put(body.b, "Block", { 0.7 * k, 0.22 * k, 0.4 * k }, { 0, body.hip + 0.05 * k, 0 }, bone)
	eyes(body, C.black, nil, 0.3 * k, 0.05, 0.2)
	put(
		body.b,
		"Block",
		{ 0.5 * k, 0.24 * k, 0.5 * k },
		off(body.headC, 0, -0.42 * k, -0.15 * k),
		bone
	)
	return body
end

local QUAD_LEGS = {
	{ x = -1, z = -1, g = "legL" },
	{ x = 1, z = 1, g = "legL" },
	{ x = 1, z = -1, g = "legR" },
	{ x = -1, z = 1, g = "legR" },
}

-- four-legged body; legs on a diagonal share a group so they trot
local function quadruped(
	b: Builder,
	o: {
		body: { number },
		color: { number },
		leg: number,
		legW: number,
		belly: { number }?,
		legColor: { number }?,
		mat: string?,
	}
): { number }
	local w, h, l = o.body[1], o.body[2], o.body[3]
	local y = o.leg + h * 0.4
	put(b, "Ball", { w, h, l }, { 0, y, 0 }, o.color, { mat = o.mat })
	if o.belly then
		put(b, "Ball", { w * 0.75, h * 0.6, l * 0.75 }, { 0, y - h * 0.22, 0 }, o.belly)
	end
	for _, corner in QUAD_LEGS do
		local x, z = corner.x * w * 0.3, corner.z * l * 0.3
		within(b, corner.g, { x, o.leg + 0.2, z }, function()
			put(
				b,
				"Block",
				{ o.legW, o.leg + 0.3, o.legW },
				{ x, (o.leg + 0.3) / 2, z },
				o.legColor or o.color,
				{ mat = o.mat }
			)
			put(b, "Block", { o.legW * 1.1, 0.22, o.legW * 1.15 }, { x, 0.11, z - 0.03 }, C.black)
		end)
	end
	return { 0, y, -l / 2 } -- the chest front, where the neck starts
end

-- mercenaries (light hero) ----------------------------------------------------------------------------
local UNITS: { () -> Figure } = {
	-- 1 mouse spearman
	function()
		local grey, pink = { 168, 168, 178 }, C.pink
		local body = biped({
			skin = grey,
			cloth = C.leather,
			pants = { 92, 72, 52 },
			feet = pink,
			hands = pink,
			sleeve = grey,
			torso = { 1.0, 1.0, 0.75 },
			head = { 1.1, 1.0, 1.0 },
			leg = 0.7,
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		for _, side in SIDES do
			local s = side.s
			put(b, "ZCyl", { 0.8, 0.8, 0.12 }, { s * 0.5, top - 0.02, 0.05 }, grey)
			put(b, "ZCyl", { 0.52, 0.52, 0.13 }, { s * 0.5, top - 0.02, 0.0 }, pink)
		end
		put(b, "Ball", { 0.5, 0.42, 0.62 }, off(hc, 0, -0.12, -0.5), grey)
		put(b, "Ball", { 0.18, 0.16, 0.16 }, off(hc, 0, -0.06, -0.82), pink)
		eyes(body, nil, C.black, 0.24, 0.12, 0.24)
		put(
			b,
			"Ball",
			{ 1.0, 0.45, 0.95 },
			off(hc, 0, 0.36, 0.04),
			C.darkLeather,
			{ mat = "Fabric" }
		)
		within(b, "tail", { 0, body.hip + 0.1, 0.36 }, function()
			put(
				b,
				"Block",
				{ 0.1, 0.1, 0.9 },
				{ 0, body.hip + 0.22, 0.8 },
				pink,
				{ rot = { -25, 0, 0 } }
			)
		end)
		hold(body, "R", function(h)
			spear(b, h, 3.2, C.steel)
			put(b, "Ball", { 0.2, 0.25, 0.2 }, off(h, 0, 2.35, -0.05), C.red, { mat = "Fabric" })
		end)
		hold(body, "L", function(h)
			shield(b, off(h, -0.05, 0.35, -0.3), 0.95, C.wood, C.iron)
		end)
		return done(b, "unit_1_placeholder")
	end,
	-- 2 rabbit archer
	function()
		local white, green = C.white, { 70, 140, 74 }
		local body = biped({
			skin = white,
			cloth = green,
			pants = C.leather,
			feet = white,
			sleeve = green,
			hands = white,
			torso = { 0.95, 1.0, 0.7 },
			head = { 1.0, 1.0, 0.95 },
			leg = 0.8,
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Ball",
				{ 0.3, 1.25, 0.2 },
				{ s * 0.22, top + 0.5, 0.05 },
				white,
				{ rot = { 0, 0, -s * 8 } }
			)
			put(
				b,
				"Ball",
				{ 0.16, 0.9, 0.06 },
				{ s * 0.23, top + 0.5, -0.04 },
				C.pink,
				{ rot = { 0, 0, -s * 8 } }
			)
		end
		put(b, "Ball", { 0.55, 0.4, 0.4 }, off(hc, 0, -0.18, -0.38), white)
		put(b, "Ball", { 0.16, 0.12, 0.12 }, off(hc, 0, -0.08, -0.58), C.pink)
		put(b, "Block", { 0.16, 0.14, 0.05 }, off(hc, 0, -0.33, -0.57), white)
		eyes(body, nil, { 200, 60, 80 }, 0.26, 0.1, 0.23)
		put(
			b,
			"Block",
			{ 1.0, 1.25, 0.12 },
			{ 0, body.chest + 0.05, body.back + 0.08 },
			C.darkGreen,
			{
				mat = "Fabric",
				rot = { 6, 0, 0 },
			}
		)
		put(
			b,
			"VCyl",
			{ 0.3, 0.95, 0.3 },
			{ 0.25, body.chest + 0.15, body.back + 0.25 },
			C.leather,
			{
				rot = { 0, 0, -18 },
			}
		)
		for i = -1, 1 do
			put(
				b,
				"Block",
				{ 0.08, 0.25, 0.14 },
				{ 0.38 + i * 0.07, body.chest + 0.75, body.back + 0.25 + i * 0.05 },
				C.red,
				{
					rot = { 0, 0, -18 },
				}
			)
		end
		put(b, "Ball", { 0.42, 0.42, 0.42 }, { 0, body.hip + 0.1, body.back + 0.08 }, white)
		hold(body, "L", function(h)
			bow(b, off(h, -0.05, 0.25, 0), 1.9, C.darkWood)
		end)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.06, 1.1, 0.06 }, off(h, 0, 0.35, -0.1), C.wood)
			put(b, "Block", { 0.1, 0.18, 0.12 }, off(h, 0, 0.9, -0.1), C.steel, { mat = "Metal" })
		end)
		return done(b, "unit_2_placeholder")
	end,
	-- 3 bear brawler
	function()
		local brown, light = { 132, 88, 56 }, { 214, 176, 128 }
		local body = biped({
			skin = brown,
			cloth = brown,
			pants = { 96, 62, 40 },
			feet = { 80, 52, 34 },
			torso = { 1.75, 1.6, 1.25 },
			head = { 1.3, 1.15, 1.15 },
			leg = 0.9,
			limb = 0.62,
			torsoShape = "Ball",
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		put(
			b,
			"Ball",
			{ 1.15, 1.05, 0.35 },
			{ 0, body.chest - 0.05, -0.5 },
			light,
			{ mat = "Fabric" }
		)
		for _, side in SIDES do
			local s = side.s
			put(b, "Ball", { 0.45, 0.45, 0.25 }, { s * 0.5, top - 0.12, 0.05 }, brown)
		end
		put(b, "Ball", { 0.65, 0.48, 0.5 }, off(hc, 0, -0.2, -0.5), light)
		put(b, "Ball", { 0.28, 0.2, 0.18 }, off(hc, 0, -0.08, -0.74), C.black)
		eyes(body, nil, C.black, 0.2, 0.12, 0.22)
		put(b, "Ball", { 1.25, 0.6, 1.15 }, off(hc, 0, 0.35, 0), C.iron, { mat = "Metal" })
		horns(b, body, C.bone, 0.7, 0.62, 62)
		put(
			b,
			"Block",
			{ 0.25, 1.9, 0.1 },
			{ 0, body.chest + 0.1, -0.62 },
			C.darkLeather,
			{ rot = { 0, 0, 35 } }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.24, 1.5, 0.24 }, off(h, 0, 0.45, -0.1), C.wood, { mat = "Wood" })
			put(
				b,
				"Ball",
				{ 0.75, 1.05, 0.75 },
				off(h, 0, 1.45, -0.1),
				C.darkWood,
				{ mat = "Wood" }
			)
			for i = 0, 3 do
				local a = math.rad(i * 90)
				put(
					b,
					"Block",
					{ 0.18, 0.18, 0.18 },
					off(h, math.cos(a) * 0.4, 1.5, -0.1 + math.sin(a) * 0.4),
					C.steel,
					{
						mat = "Metal",
						rot = { 45, 45, 0 },
					}
				)
			end
		end)
		return done(b, "unit_3_placeholder")
	end,
	-- 4 kangaroo boxer
	function()
		local tan, light = { 204, 160, 108 }, { 236, 210, 168 }
		local body = biped({
			skin = tan,
			cloth = tan,
			pants = tan,
			feet = { 170, 128, 82 },
			torso = { 1.1, 1.4, 0.9 },
			head = { 0.85, 0.95, 1.1 },
			leg = 1.1,
			limb = 0.46,
			torsoShape = "Ball",
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		put(
			b,
			"Ball",
			{ 0.8, 0.95, 0.3 },
			{ 0, body.chest - 0.15, -0.36 },
			light,
			{ mat = "Fabric" }
		)
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Ball",
				{ 0.24, 0.75, 0.15 },
				{ s * 0.26, top + 0.2, 0.1 },
				tan,
				{ rot = { 0, 0, -s * 12 } }
			)
			put(b, "Block", { 0.4, 0.2, 1.0 }, { s * 0.28, 0.1, -0.5 }, { 170, 128, 82 })
		end
		put(b, "Ball", { 0.5, 0.42, 0.62 }, off(hc, 0, -0.15, -0.5), light)
		put(b, "Ball", { 0.2, 0.14, 0.12 }, off(hc, 0, -0.05, -0.82), C.black)
		eyes(body, nil, C.black, 0.2, 0.12, 0.22)
		put(b, "Block", { 0.9, 0.14, 1.0 }, off(hc, 0, 0.22, 0), C.red, { mat = "Fabric" })
		put(
			b,
			"Block",
			{ 0.1, 0.12, 0.5 },
			off(hc, 0.15, 0.12, 0.65),
			C.red,
			{ mat = "Fabric", rot = { -30, 0, 0 } }
		)
		within(b, "tail", { 0, 0.8, 0.4 }, function()
			put(b, "Ball", { 0.45, 0.45, 1.7 }, { 0, 0.5, 1.1 }, tan, { rot = { -18, 0, 0 } })
		end)
		for _, side in SIDES do
			hold(body, side.n, function(h)
				put(
					b,
					"Ball",
					{ 0.7, 0.7, 0.78 },
					off(h, 0, -0.05, -0.05),
					C.red,
					{ mat = "Plastic" }
				)
				put(b, "VCyl", { 0.5, 0.18, 0.5 }, off(h, 0, 0.32, 0), C.white)
			end)
		end
		return done(b, "unit_4_placeholder")
	end,
	-- 5 monkey bomber
	function()
		local brown, face = { 140, 92, 56 }, { 226, 190, 146 }
		local body = biped({
			skin = brown,
			cloth = brown,
			pants = { 96, 70, 48 },
			feet = face,
			hands = face,
			torso = { 0.95, 1.0, 0.75 },
			head = { 1.0, 0.95, 0.95 },
			leg = 0.7,
			arm = 1.25,
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		put(b, "Ball", { 0.78, 0.72, 0.3 }, off(hc, 0, -0.08, -0.38), face)
		put(b, "Ball", { 0.5, 0.32, 0.32 }, off(hc, 0, -0.26, -0.5), face)
		for _, side in SIDES do
			local s = side.s
			put(b, "Cyl", { 0.12, 0.45, 0.45 }, off(hc, s * 0.55, 0.02, 0), face)
			put(
				b,
				"ZCyl",
				{ 0.3, 0.3, 0.12 },
				off(hc, s * 0.2, 0.3, -0.42),
				C.brass,
				{ mat = "Metal" }
			)
			put(
				b,
				"ZCyl",
				{ 0.2, 0.2, 0.13 },
				off(hc, s * 0.2, 0.3, -0.43),
				C.cyan,
				{ transp = 0.3 }
			)
		end
		put(b, "Block", { 1.02, 0.12, 0.98 }, off(hc, 0, 0.3, 0), C.darkLeather)
		eyes(body, nil, C.black, 0.18, 0.0, 0.2)
		put(
			b,
			"Block",
			{ 0.22, 1.35, 0.12 },
			{ 0, body.chest, -0.4 },
			C.darkLeather,
			{ rot = { 0, 0, -35 } }
		)
		for i = -1, 1 do
			put(
				b,
				"Ball",
				{ 0.24, 0.24, 0.24 },
				{ i * 0.28, body.chest + i * -0.2, -0.48 },
				C.black
			)
		end
		within(b, "tail", { 0, body.hip + 0.1, 0.35 }, function()
			put(
				b,
				"Block",
				{ 0.14, 0.14, 0.8 },
				{ 0, body.hip + 0.15, 0.75 },
				brown,
				{ rot = { -20, 0, 0 } }
			)
			put(b, "Block", { 0.14, 0.6, 0.14 }, { 0, body.hip + 0.45, 1.12 }, brown)
		end)
		hold(body, "R", function(h)
			put(b, "Ball", { 0.75, 0.75, 0.75 }, off(h, 0, 0.3, -0.15), C.black, { mat = "Metal" })
			put(b, "VCyl", { 0.08, 0.3, 0.08 }, off(h, 0, 0.78, -0.15), C.tan)
			put(b, "Ball", { 0.2, 0.2, 0.2 }, off(h, 0, 0.95, -0.15), C.orange, { neon = true })
		end)
		return done(b, "unit_5_placeholder")
	end,
	-- 6 turtle shield
	function()
		local green, shell = { 92, 160, 96 }, { 116, 94, 54 }
		local body = biped({
			skin = green,
			cloth = green,
			pants = green,
			feet = { 70, 130, 76 },
			torso = { 1.3, 1.2, 0.9 },
			head = { 0.85, 0.8, 0.95 },
			leg = 0.65,
			limb = 0.5,
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		put(b, "Ball", { 1.7, 1.75, 1.1 }, { 0, body.chest + 0.05, 0.55 }, shell, { mat = "Wood" })
		put(b, "VCyl", { 1.75, 0.16, 1.2 }, { 0, body.chest - 0.35, 0.5 }, { 200, 170, 90 })
		for i = 0, 4 do
			local a = math.rad(i * 72)
			put(
				b,
				"Cyl",
				{ 0.08, 0.42, 0.42 },
				{ math.cos(a) * 0.45, body.chest + 0.1 + math.sin(a) * 0.45, 1.06 },
				{ 84, 66, 36 },
				{
					rot = { 0, 90, 0 },
				}
			)
		end
		put(b, "Ball", { 1.05, 1.05, 0.3 }, { 0, body.chest, -0.4 }, { 224, 206, 130 })
		eyes(body, nil, C.black, 0.2, 0.08, 0.24)
		put(b, "Ball", { 0.95, 0.55, 1.0 }, off(hc, 0, 0.25, 0), C.steel, { mat = "Metal" })
		put(b, "Block", { 0.12, 0.4, 0.1 }, off(hc, 0, 0.0, -0.52), C.steel, { mat = "Metal" })
		hold(body, "L", function(h)
			put(
				b,
				"Block",
				{ 1.4, 1.9, 0.18 },
				off(h, 0.35, 0.65, -0.62),
				C.blue,
				{ mat = "Metal" }
			)
			put(
				b,
				"Block",
				{ 1.5, 0.12, 0.2 },
				off(h, 0.35, 1.55, -0.62),
				C.gold,
				{ mat = "Metal" }
			)
			put(
				b,
				"Block",
				{ 1.5, 0.12, 0.2 },
				off(h, 0.35, -0.25, -0.62),
				C.gold,
				{ mat = "Metal" }
			)
			put(
				b,
				"ZCyl",
				{ 0.75, 0.75, 0.22 },
				off(h, 0.35, 0.7, -0.66),
				C.gold,
				{ mat = "Metal" }
			)
			put(b, "ZCyl", { 0.4, 0.4, 0.24 }, off(h, 0.35, 0.7, -0.67), C.yellow, { neon = true })
		end)
		hold(body, "R", function(h)
			sword(b, h, 1.1, C.steel)
		end)
		return done(b, "unit_6_placeholder")
	end,
	-- 7 rhino charger
	function()
		local b = new()
		local grey = { 138, 138, 148 }
		local neck = quadruped(
			b,
			{ body = { 1.9, 1.7, 3.3 }, color = grey, leg = 1.0, legW = 0.6, mat = "Slate" }
		)
		local hy = neck[2] + 0.05
		put(b, "Block", { 1.15, 1.0, 1.3 }, { 0, hy, neck[3] - 0.45 }, grey, { mat = "Slate" })
		put(b, "Block", { 0.95, 0.7, 0.6 }, { 0, hy - 0.2, neck[3] - 1.2 }, grey, { mat = "Slate" })
		put(
			b,
			"Ball",
			{ 0.34, 1.2, 0.34 },
			{ 0, hy + 0.35, neck[3] - 1.45 },
			C.bone,
			{ rot = { -28, 0, 0 } }
		)
		put(
			b,
			"Ball",
			{ 0.24, 0.6, 0.24 },
			{ 0, hy + 0.32, neck[3] - 0.95 },
			C.bone,
			{ rot = { -18, 0, 0 } }
		)
		for _, side in SIDES do
			local s = side.s
			put(b, "Ball", { 0.18, 0.18, 0.12 }, { s * 0.5, hy + 0.15, neck[3] - 0.8 }, C.black)
			put(
				b,
				"Ball",
				{ 0.22, 0.45, 0.15 },
				{ s * 0.42, hy + 0.65, neck[3] - 0.15 },
				grey,
				{ rot = { 0, 0, -s * 15 } }
			)
			put(
				b,
				"Block",
				{ 0.12, 0.95, 2.0 },
				{ s * 1.0, neck[2] - 0.3, 0.1 },
				C.red,
				{ mat = "Fabric" }
			)
		end
		put(b, "Block", { 1.6, 0.25, 1.9 }, { 0, neck[2] + 0.85, 0.15 }, C.steel, { mat = "Metal" })
		put(
			b,
			"Block",
			{ 1.0, 0.2, 0.7 },
			{ 0, hy + 0.56, neck[3] - 0.45 },
			C.steel,
			{ mat = "Metal" }
		)
		for i = 0, 2 do
			put(
				b,
				"Wedge",
				{ 0.15, 0.35, 0.3 },
				{ 0, neck[2] + 1.15, -0.5 + i * 0.6 },
				C.steel,
				{ mat = "Metal" }
			)
		end
		within(b, "tail", { 0, neck[2] + 0.4, 1.6 }, function()
			put(
				b,
				"Block",
				{ 0.1, 0.1, 0.7 },
				{ 0, neck[2] + 0.25, 1.9 },
				grey,
				{ rot = { 30, 0, 0 } }
			)
		end)
		return done(b, "unit_7_placeholder")
	end,
	-- 8 penguin ice mage
	function()
		local b = new()
		within(b, "legL", { -0.3, 0.3, 0 }, function()
			put(b, "Block", { 0.4, 0.18, 0.6 }, { -0.3, 0.09, -0.15 }, C.orange)
		end)
		within(b, "legR", { 0.3, 0.3, 0 }, function()
			put(b, "Block", { 0.4, 0.18, 0.6 }, { 0.3, 0.09, -0.15 }, C.orange)
		end)
		put(b, "Ball", { 1.35, 1.9, 1.15 }, { 0, 1.1, 0 }, C.black, { mat = "Fabric" })
		put(b, "Ball", { 0.95, 1.5, 0.4 }, { 0, 1.0, -0.42 }, C.white, { mat = "Fabric" })
		put(b, "Ball", { 1.0, 0.92, 0.95 }, { 0, 2.15, 0 }, C.black, { mat = "Fabric" })
		put(b, "Ball", { 0.7, 0.55, 0.3 }, { 0, 2.05, -0.36 }, C.white)
		put(b, "Wedge", { 0.24, 0.18, 0.42 }, { 0, 2.0, -0.62 }, C.orange, { rot = { 0, 180, 0 } })
		for _, side in SIDES do
			local s = side.s
			put(b, "Ball", { 0.18, 0.2, 0.1 }, { s * 0.18, 2.22, -0.5 }, C.black)
		end
		put(b, "VCyl", { 0.95, 0.2, 0.9 }, { 0, 1.72, 0 }, C.cyan, { mat = "Fabric" })
		put(b, "Block", { 0.2, 0.55, 0.12 }, { 0.3, 1.45, -0.42 }, C.cyan, { mat = "Fabric" })
		put(b, "VCyl", { 1.35, 0.08, 1.35 }, { 0, 2.55, 0 }, C.navy, { mat = "Fabric" })
		cone(b, { 0, 2.58, 0.05 }, 0.8, 1.05, C.navy, { mat = "Fabric" })
		put(b, "Ball", { 0.22, 0.22, 0.12 }, { 0, 2.95, -0.32 }, C.yellow, { neon = true })
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "arm" .. n, { s * 0.6, 1.6, 0 }, function()
				put(
					b,
					"Ball",
					{ 0.26, 1.0, 0.5 },
					{ s * 0.72, 1.2, 0 },
					C.black,
					{ rot = { 0, 0, s * 12 } }
				)
				if n == "R" then
					put(
						b,
						"VCyl",
						{ 0.12, 2.5, 0.12 },
						{ 0.82, 1.35, -0.2 },
						C.wood,
						{ mat = "Wood" }
					)
					put(
						b,
						"Ball",
						{ 0.38, 0.65, 0.38 },
						{ 0.82, 2.75, -0.2 },
						C.cyan,
						{ neon = true, light = { 7, 1 } }
					)
					put(b, "Ball", { 0.5, 0.2, 0.5 }, { 0.82, 2.45, -0.2 }, C.ice, { mat = "Ice" })
				end
			end)
		end
		return done(b, "unit_8_placeholder")
	end,
	-- 9 baby dragon (flies)
	function()
		local b = new()
		local red, belly, wing = { 214, 64, 52 }, { 252, 206, 96 }, { 150, 36, 40 }
		put(b, "Ball", { 1.4, 1.6, 1.4 }, { 0, 1.5, 0.1 }, red)
		put(b, "Ball", { 0.95, 1.2, 0.4 }, { 0, 1.42, -0.42 }, belly)
		put(b, "Ball", { 1.15, 1.0, 1.15 }, { 0, 2.65, -0.25 }, red)
		put(b, "Ball", { 0.75, 0.52, 0.65 }, { 0, 2.5, -0.85 }, red)
		for _, side in SIDES do
			local s, n = side.s, side.n
			put(b, "Ball", { 0.1, 0.1, 0.08 }, { s * 0.14, 2.6, -1.16 }, C.black)
			put(b, "Ball", { 0.3, 0.32, 0.18 }, { s * 0.27, 2.82, -0.72 }, C.white)
			put(b, "Ball", { 0.15, 0.2, 0.1 }, { s * 0.27, 2.82, -0.8 }, C.black)
			put(
				b,
				"Ball",
				{ 0.18, 0.6, 0.18 },
				{ s * 0.3, 3.25, -0.05 },
				belly,
				{ rot = { 25, 0, -s * 18 } }
			)
			within(b, "leg" .. n, { s * 0.4, 0.8, 0.1 }, function()
				put(b, "Ball", { 0.42, 0.75, 0.5 }, { s * 0.42, 0.5, 0.05 }, red)
			end)
			within(b, "arm" .. n, { s * 0.55, 1.75, -0.2 }, function()
				put(b, "Ball", { 0.24, 0.55, 0.28 }, { s * 0.62, 1.5, -0.38 }, red)
			end)
			within(b, "wing" .. n, { s * 0.5, 2.0, 0.45 }, function()
				put(
					b,
					"Cyl",
					{ 1.7, 0.14, 0.14 },
					{ s * 1.3, 2.35, 0.5 },
					wing,
					{ rot = { 0, 0, -s * 18 } }
				)
				put(
					b,
					"Block",
					{ 1.6, 0.95, 0.06 },
					{ s * 1.3, 1.95, 0.5 },
					wing,
					{ rot = { 0, 0, -s * 18 } }
				)
			end)
		end
		for i = 0, 2 do
			put(b, "Wedge", { 0.1, 0.26, 0.3 }, { 0, 2.3 - i * 0.45, 0.75 + i * 0.1 }, belly)
		end
		within(b, "tail", { 0, 1.0, 0.7 }, function()
			put(b, "Ball", { 0.45, 0.45, 1.3 }, { 0, 0.85, 1.25 }, red, { rot = { 12, 0, 0 } })
			put(b, "Wedge", { 0.1, 0.4, 0.45 }, { 0, 0.82, 1.98 }, belly)
		end)
		return done(b, "unit_9_placeholder", 1, true)
	end,
}

-- shadow hero totems: spirit beasts with violet eyes and a glowing rune ring ---------------------------
local function rune(b: Builder, d: number)
	put(
		b,
		"VCyl",
		{ d * 0.8, 0.04, d * 0.8 },
		{ 0, 0.03, 0 },
		C.violet,
		{ neon = true, transp = 0.72 }
	)
end

local TOTEMS: { () -> Figure } = {
	-- 1 rooster (throws eggs)
	function()
		local b = new()
		rune(b, 1.8)
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "leg" .. n, { s * 0.25, 0.9, 0 }, function()
				put(b, "VCyl", { 0.12, 0.9, 0.12 }, { s * 0.25, 0.45, 0 }, C.yellow)
				put(b, "Block", { 0.3, 0.08, 0.45 }, { s * 0.25, 0.04, -0.1 }, C.yellow)
			end)
			within(b, "wing" .. n, { s * 0.5, 1.7, 0 }, function()
				put(b, "Ball", { 0.2, 0.7, 0.95 }, { s * 0.6, 1.5, 0.05 }, { 70, 54, 90 })
			end)
		end
		put(b, "Ball", { 1.05, 1.1, 1.35 }, { 0, 1.5, 0.05 }, C.white)
		put(b, "Ball", { 0.7, 0.75, 0.7 }, { 0, 2.3, -0.4 }, C.white)
		put(b, "Wedge", { 0.2, 0.18, 0.35 }, { 0, 2.28, -0.85 }, C.yellow, { rot = { 0, 180, 0 } })
		put(b, "Ball", { 0.16, 0.36, 0.16 }, { 0, 2.0, -0.7 }, C.red)
		for i = 0, 2 do
			put(
				b,
				"Ball",
				{ 0.14, 0.3, 0.28 },
				{ 0, 2.72 + (i == 1 and 0.06 or 0), -0.55 + i * 0.18 },
				C.red
			)
		end
		for i = -1, 1 do
			put(b, "Block", { 0.12, 1.1, 0.35 }, { i * 0.18, 2.05, 0.75 }, { 60, 44, 110 }, {
				rot = { 30, 0, i * 15 },
			})
		end
		for _, side in SIDES do
			put(
				b,
				"Ball",
				{ 0.14, 0.14, 0.08 },
				{ side.s * 0.22, 2.4, -0.7 },
				C.violet,
				{ neon = true }
			)
		end
		return done(b, "totem_1_placeholder")
	end,
	-- 2 roar: a carved lion-head pole
	function()
		local b = new()
		rune(b, 2.2)
		local wood = { 92, 60, 96 }
		put(b, "VCyl", { 1.2, 0.4, 1.2 }, { 0, 0.2, 0 }, C.darkWood, { mat = "Wood" })
		put(b, "Block", { 0.95, 1.4, 0.95 }, { 0, 1.1, 0 }, wood, { mat = "Wood" })
		put(b, "Block", { 1.0, 0.12, 1.0 }, { 0, 1.5, 0 }, C.violet, { neon = true })
		put(b, "Block", { 1.0, 0.12, 1.0 }, { 0, 0.75, 0 }, C.violet, { neon = true })
		local head = #b.parts + 1
		put(b, "Ball", { 1.9, 1.8, 1.2 }, { 0, 2.55, 0.1 }, { 196, 110, 40 }, { mat = "Fabric" })
		put(b, "Ball", { 1.15, 1.15, 1.05 }, { 0, 2.55, -0.3 }, { 236, 176, 80 })
		put(b, "Ball", { 0.55, 0.4, 0.4 }, { 0, 2.35, -0.8 }, { 236, 176, 80 })
		put(b, "Ball", { 0.2, 0.15, 0.12 }, { 0, 2.48, -1.0 }, C.black)
		put(b, "Block", { 0.5, 0.3, 0.1 }, { 0, 2.08, -0.82 }, C.violet, { neon = true })
		for _, side in SIDES do
			put(
				b,
				"Ball",
				{ 0.2, 0.14, 0.1 },
				{ side.s * 0.25, 2.75, -0.8 },
				C.violet,
				{ neon = true }
			)
		end
		regroup(b, "head", { 0, 1.8, 0 }, head)
		return done(b, "totem_2_placeholder")
	end,
	-- 3 boar
	function()
		local b = new()
		rune(b, 2.4)
		local hide = { 92, 64, 50 }
		local neck = quadruped(
			b,
			{ body = { 1.4, 1.3, 2.3 }, color = hide, leg = 0.6, legW = 0.38, mat = "Fabric" }
		)
		put(
			b,
			"Ball",
			{ 1.0, 0.95, 1.0 },
			{ 0, neck[2] + 0.1, neck[3] - 0.2 },
			hide,
			{ mat = "Fabric" }
		)
		put(
			b,
			"ZCyl",
			{ 0.55, 0.45, 0.4 },
			{ 0, neck[2] - 0.05, neck[3] - 0.75 },
			{ 200, 130, 130 }
		)
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Ball",
				{ 0.12, 0.55, 0.12 },
				{ s * 0.32, neck[2] + 0.0, neck[3] - 0.75 },
				C.white,
				{ rot = { -20, 0, s * 20 } }
			)
			put(
				b,
				"Ball",
				{ 0.14, 0.14, 0.08 },
				{ s * 0.25, neck[2] + 0.35, neck[3] - 0.65 },
				C.violet,
				{ neon = true }
			)
			put(
				b,
				"Ball",
				{ 0.2, 0.4, 0.12 },
				{ s * 0.35, neck[2] + 0.6, neck[3] - 0.15 },
				hide,
				{ rot = { 0, 0, -s * 20 } }
			)
		end
		for i = 0, 4 do
			put(
				b,
				"Block",
				{ 0.12, 0.35, 0.3 },
				{ 0, neck[2] + 0.7 - i * 0.05, neck[3] + 0.2 + i * 0.4 },
				C.black
			)
		end
		return done(b, "totem_3_placeholder")
	end,
	-- 4 whale spirit (floats)
	function()
		local b = new()
		local navy, belly = { 60, 76, 150 }, { 210, 226, 240 }
		put(b, "Ball", { 2.3, 1.9, 4.0 }, { 0, 1.5, 0.2 }, navy)
		put(b, "Ball", { 1.8, 1.2, 3.4 }, { 0, 1.15, 0.0 }, belly)
		for i = 0, 3 do
			put(b, "Block", { 1.4, 0.05, 0.1 }, { 0, 0.72, -0.9 + i * 0.45 }, { 160, 176, 200 })
		end
		for _, side in SIDES do
			local s, n = side.s, side.n
			put(b, "Ball", { 0.24, 0.24, 0.12 }, { s * 0.9, 1.6, -1.35 }, C.violet, { neon = true })
			within(b, "wing" .. n, { s * 1.0, 1.1, -0.3 }, function()
				put(
					b,
					"Ball",
					{ 1.3, 0.14, 0.6 },
					{ s * 1.55, 0.9, -0.2 },
					navy,
					{ rot = { 0, 0, -s * 20 } }
				)
			end)
		end
		within(b, "tail", { 0, 1.5, 2.0 }, function()
			put(b, "Ball", { 0.7, 0.7, 1.4 }, { 0, 1.6, 2.6 }, navy)
			put(b, "Block", { 2.2, 0.12, 0.8 }, { 0, 1.75, 3.25 }, navy)
		end)
		put(b, "VCyl", { 0.25, 0.9, 0.25 }, { 0, 2.8, -0.6 }, C.cyan, { neon = true, transp = 0.4 })
		put(b, "Ball", { 0.7, 0.4, 0.7 }, { 0, 3.3, -0.6 }, C.cyan, { neon = true, transp = 0.5 })
		return done(b, "totem_4_placeholder", 1, true)
	end,
	-- 5 thorn bramble
	function()
		local b = new()
		rune(b, 2.4)
		local vine = { 50, 80, 50 }
		put(b, "Ball", { 1.8, 1.0, 1.8 }, { 0, 0.4, 0 }, vine, { mat = "Grass" })
		put(b, "Ball", { 1.1, 1.3, 1.1 }, { 0.2, 1.1, 0.1 }, vine, { mat = "Grass" })
		put(b, "Ball", { 0.8, 0.9, 0.8 }, { -0.35, 1.6, -0.1 }, vine, { mat = "Grass" })
		local thorns = #b.parts + 1
		for i = 0, 9 do
			local a = math.rad(i * 36)
			local y = 0.5 + (i % 3) * 0.55
			put(
				b,
				"Ball",
				{ 0.12, 0.7, 0.12 },
				{ math.cos(a) * 0.75, y, math.sin(a) * 0.75 },
				C.darkWood,
				{
					rot = { math.sin(a) * 60, 0, -math.cos(a) * 60 },
				}
			)
			put(
				b,
				"Ball",
				{ 0.12, 0.12, 0.12 },
				{ math.cos(a) * 1.05, y + 0.2, math.sin(a) * 1.05 },
				C.violet,
				{
					neon = true,
				}
			)
		end
		put(
			b,
			"Ball",
			{ 0.5, 0.5, 0.5 },
			{ -0.35, 2.15, -0.1 },
			C.violet,
			{ neon = true, light = { 6, 0.8 } }
		)
		regroup(b, "tail", { 0, 0, 0 }, thorns)
		return done(b, "totem_5_placeholder")
	end,
	-- 6 bull (stands and absorbs hits)
	function()
		local b = new()
		rune(b, 3.0)
		local hide = { 44, 38, 44 }
		local neck = quadruped(
			b,
			{ body = { 2.0, 1.9, 3.2 }, color = hide, leg = 1.0, legW = 0.55, mat = "Fabric" }
		)
		put(
			b,
			"Ball",
			{ 1.9, 1.4, 1.2 },
			{ 0, neck[2] + 0.4, neck[3] + 0.4 },
			hide,
			{ mat = "Fabric" }
		)
		put(
			b,
			"Block",
			{ 1.0, 1.0, 1.1 },
			{ 0, neck[2] + 0.15, neck[3] - 0.35 },
			hide,
			{ mat = "Fabric" }
		)
		put(b, "Block", { 0.8, 0.5, 0.4 }, { 0, neck[2] - 0.2, neck[3] - 0.95 }, { 120, 96, 100 })
		put(
			b,
			"Cyl",
			{ 0.08, 0.35, 0.35 },
			{ 0, neck[2] - 0.45, neck[3] - 1.1 },
			C.gold,
			{ mat = "Metal", rot = { 0, 90, 0 } }
		)
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Ball",
				{ 0.9, 0.24, 0.24 },
				{ s * 0.8, neck[2] + 0.7, neck[3] - 0.35 },
				C.bone,
				{ rot = { 0, 0, s * 25 } }
			)
			put(
				b,
				"Ball",
				{ 0.2, 0.45, 0.2 },
				{ s * 1.2, neck[2] + 1.0, neck[3] - 0.4 },
				C.bone,
				{ rot = { 0, 0, -s * 20 } }
			)
			put(
				b,
				"Ball",
				{ 0.16, 0.16, 0.08 },
				{ s * 0.3, neck[2] + 0.35, neck[3] - 0.9 },
				C.violet,
				{ neon = true }
			)
		end
		put(b, "Block", { 1.4, 0.12, 1.6 }, { 0, neck[2] + 0.9, 0.3 }, C.purple, { mat = "Fabric" })
		return done(b, "totem_6_placeholder")
	end,
	-- 7 hawk (flies beside the hero)
	function()
		local b = new()
		local brown = { 110, 74, 44 }
		put(b, "Ball", { 0.9, 0.85, 1.6 }, { 0, 1.6, 0.1 }, brown, { mat = "Fabric" })
		put(b, "Ball", { 0.7, 0.7, 0.7 }, { 0, 2.1, -0.65 }, C.white)
		put(b, "Wedge", { 0.2, 0.25, 0.4 }, { 0, 2.0, -1.1 }, C.yellow, { rot = { 0, 180, 0 } })
		for _, side in SIDES do
			local s, n = side.s, side.n
			put(b, "Ball", { 0.14, 0.14, 0.08 }, { s * 0.2, 2.2, -0.95 }, C.violet, { neon = true })
			within(b, "wing" .. n, { s * 0.4, 1.8, 0 }, function()
				put(
					b,
					"Block",
					{ 2.2, 0.1, 0.9 },
					{ s * 1.45, 1.85, 0.1 },
					brown,
					{ mat = "Fabric", rot = { 0, 0, -s * 10 } }
				)
				put(
					b,
					"Block",
					{ 0.9, 0.11, 0.5 },
					{ s * 2.45, 1.95, 0.35 },
					C.black,
					{ rot = { 0, 0, -s * 10 } }
				)
			end)
		end
		put(b, "Block", { 0.7, 0.08, 0.8 }, { 0, 1.5, 1.1 }, C.white)
		for _, side in SIDES do
			put(b, "Block", { 0.12, 0.35, 0.12 }, { side.s * 0.2, 1.05, 0.2 }, C.yellow)
		end
		return done(b, "totem_7_placeholder", 1, true)
	end,
	-- 8 fire salamander
	function()
		local b = new()
		rune(b, 2.4)
		local skin = { 232, 96, 40 }
		local neck =
			quadruped(b, { body = { 1.0, 0.7, 2.2 }, color = skin, leg = 0.35, legW = 0.3 })
		put(b, "Ball", { 0.75, 0.55, 0.95 }, { 0, neck[2] + 0.05, neck[3] - 0.35 }, skin)
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Ball",
				{ 0.24, 0.24, 0.2 },
				{ s * 0.26, neck[2] + 0.25, neck[3] - 0.45 },
				C.yellow,
				{ neon = true }
			)
		end
		for i = 0, 3 do
			put(
				b,
				"Ball",
				{ 0.22, 0.12, 0.22 },
				{ (i % 2 == 0 and 0.22 or -0.22), neck[2] + 0.32, -0.7 + i * 0.45 },
				C.yellow,
				{
					neon = true,
				}
			)
		end
		within(b, "tail", { 0, neck[2], 1.0 }, function()
			put(
				b,
				"Ball",
				{ 0.35, 0.3, 1.5 },
				{ 0, neck[2] - 0.05, 1.7 },
				skin,
				{ rot = { -8, 0, 0 } }
			)
			put(
				b,
				"Ball",
				{ 0.45, 0.6, 0.45 },
				{ 0, neck[2] + 0.25, 2.5 },
				C.orange,
				{ neon = true, light = { 7, 1.1 } }
			)
		end)
		return done(b, "totem_8_placeholder")
	end,
	-- 9 beast form: a shadow werewolf
	function()
		local fur = { 70, 66, 86 }
		local body = biped({
			skin = fur,
			cloth = fur,
			pants = { 50, 44, 60 },
			feet = fur,
			torso = { 1.4, 1.5, 1.0 },
			head = { 0.95, 0.9, 1.0 },
			leg = 1.1,
			limb = 0.5,
			arm = 1.6,
			torsoShape = "Ball",
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		rune(b, 2.4)
		put(b, "Block", { 0.5, 0.42, 0.75 }, off(hc, 0, -0.15, -0.6), fur, { mat = "Fabric" })
		put(b, "Ball", { 0.2, 0.16, 0.14 }, off(hc, 0, -0.02, -0.98), C.black)
		for _, side in SIDES do
			local s = side.s
			put(
				b,
				"Wedge",
				{ 0.12, 0.55, 0.35 },
				{ s * 0.32, top + 0.15, hc[3] },
				fur,
				{ rot = { 0, 90, 0 } }
			)
			for f = -1, 1 do
				put(
					b,
					"Ball",
					{ 0.08, 0.32, 0.08 },
					off(body.hand[side.n], f * 0.12, -0.35, -0.15),
					C.bone,
					{
						g = "arm" .. side.n,
						pv = body.shoulder[side.n],
					}
				)
			end
		end
		eyes(body, C.violet, nil, 0.18, 0.18, 0.22)
		put(
			b,
			"Ball",
			{ 1.2, 0.7, 0.8 },
			{ 0, body.chest + 0.6, 0.3 },
			{ 40, 36, 52 },
			{ mat = "Fabric" }
		)
		within(b, "tail", { 0, body.hip + 0.2, 0.45 }, function()
			put(
				b,
				"Ball",
				{ 0.4, 0.4, 1.2 },
				{ 0, body.hip + 0.2, 0.95 },
				fur,
				{ rot = { -30, 0, 0 }, mat = "Fabric" }
			)
		end)
		return done(b, "totem_9_placeholder")
	end,
}

-- monsters ----------------------------------------------------------------------------------------------
local function zombie(skin: { number }, shirt: { number }, pants: { number }, size: number?): Body
	local k = size or 1
	local body = biped({
		skin = skin,
		cloth = shirt,
		pants = pants,
		feet = C.darkLeather,
		sleeve = shirt,
		torso = { 1.05 * k, 1.15 * k, 0.6 * k },
		head = { 0.95 * k, 1.0 * k, 0.95 * k },
		leg = 1.0 * k,
		headShape = "Block",
		mat = "Fabric",
	})
	eyes(body, C.yellow, nil, 0.2 * k, 0.12, 0.22)
	put(
		body.b,
		"Block",
		{ 0.5 * k, 0.12 * k, 0.05 },
		off(body.headC, 0, -0.28 * k, -0.48 * k),
		C.black
	)
	put(
		body.b,
		"Block",
		{ 0.4 * k, 0.3 * k, 0.05 },
		{ 0.2 * k, body.chest - 0.2 * k, -0.31 * k },
		skin
	)
	return body
end

local function knight(metal: { number }, trim: { number }, cape: { number }?, size: number?): Body
	local k = size or 1
	local body = biped({
		skin = metal,
		cloth = metal,
		pants = { 50, 52, 60 },
		feet = metal,
		hands = metal,
		torso = { 1.35 * k, 1.35 * k, 0.85 * k },
		head = { 1.0 * k, 1.05 * k, 1.0 * k },
		leg = 1.1 * k,
		limb = 0.5 * k,
		headShape = "Block",
		mat = "Metal",
		skinMat = "Metal",
	})
	local b, hc = body.b, body.headC
	put(b, "Block", { 0.75 * k, 0.12 * k, 0.05 }, off(hc, 0, 0.08 * k, -0.51 * k), C.black)
	put(
		b,
		"Block",
		{ 0.75 * k, 0.12 * k, 0.04 },
		off(hc, 0, 0.08 * k, -0.53 * k),
		C.red,
		{ neon = true }
	)
	put(b, "Block", { 1.1 * k, 0.12 * k, 1.1 * k }, off(hc, 0, 0.5 * k, 0), trim, { mat = "Metal" })
	for _, side in SIDES do
		local s = side.s
		put(
			b,
			"Ball",
			{ 0.75 * k, 0.55 * k, 0.8 * k },
			off(body.shoulder[side.n], s * 0.05, 0.1 * k, 0),
			trim,
			{
				mat = "Metal",
			}
		)
	end
	put(
		b,
		"Block",
		{ 1.4 * k, 0.2 * k, 0.9 * k },
		{ 0, body.hip + 0.1 * k, 0 },
		trim,
		{ mat = "Metal" }
	)
	if cape then
		put(
			b,
			"Block",
			{ 1.3 * k, 1.9 * k, 0.1 },
			{ 0, body.chest - 0.15 * k, body.back + 0.08 },
			cape,
			{
				mat = "Fabric",
				rot = { 6, 0, 0 },
			}
		)
	end
	return body
end

local function ghost(b: Builder, color: { number }, size: number, transp: number)
	put(
		b,
		"Ball",
		{ 1.4 * size, 1.5 * size, 1.3 * size },
		{ 0, 2.3 * size, 0 },
		color,
		{ transp = transp }
	)
	put(
		b,
		"Ball",
		{ 1.1 * size, 1.8 * size, 1.0 * size },
		{ 0, 1.3 * size, 0.15 * size },
		color,
		{ transp = transp + 0.1 }
	)
	within(b, "tail", { 0, 1.0 * size, 0.2 * size }, function()
		put(
			b,
			"Ball",
			{ 0.6 * size, 1.2 * size, 0.6 * size },
			{ 0, 0.5 * size, 0.45 * size },
			color,
			{
				transp = transp + 0.2,
				rot = { 30, 0, 0 },
			}
		)
	end)
end

local ENEMIES: { () -> Figure } = {
	-- 1 rotting dead
	function()
		local body = zombie(C.rot, { 96, 82, 64 }, { 64, 60, 72 })
		hold(body, "R", function(h)
			put(body.b, "Block", { 0.25, 0.25, 0.25 }, off(h, 0, -0.15, -0.1), C.rot)
		end)
		put(
			body.b,
			"Block",
			{ 0.4, 0.35, 0.05 },
			{ -0.2, body.chest + 0.25, -0.31 },
			{ 70, 60, 50 }
		)
		return done(body.b, "enemy_1_placeholder")
	end,
	-- 2 bone thrower
	function()
		local body = skeleton()
		hold(body, "R", function(h)
			put(body.b, "VCyl", { 0.14, 0.9, 0.14 }, off(h, 0, 0.35, -0.1), C.bone)
			put(body.b, "Ball", { 0.3, 0.22, 0.22 }, off(h, 0, 0.82, -0.1), C.bone)
		end)
		put(
			body.b,
			"Block",
			{ 0.7, 0.5, 0.3 },
			{ 0.2, body.chest - 0.1, body.back + 0.2 },
			C.leather,
			{ rot = { 0, 0, 10 } }
		)
		return done(body.b, "enemy_2_placeholder")
	end,
	-- 3 swamp witch
	function()
		local robe = { 92, 60, 120 }
		local body = biped({
			skin = { 140, 190, 110 },
			cloth = robe,
			pants = robe,
			feet = C.black,
			sleeve = robe,
			torso = { 1.0, 1.1, 0.7 },
			head = { 0.9, 0.95, 0.9 },
			leg = 0.95,
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		put(
			b,
			"Wedge",
			{ 1.35, 1.2, 1.1 },
			{ 0, 0.6, -0.05 },
			robe,
			{ mat = "Fabric", rot = { 0, 180, 0 } }
		)
		put(b, "Wedge", { 1.35, 1.2, 1.1 }, { 0, 0.6, 0.05 }, robe, { mat = "Fabric" })
		put(
			b,
			"Ball",
			{ 0.24, 0.42, 0.24 },
			off(hc, 0, -0.05, -0.5),
			{ 120, 170, 90 },
			{ rot = { -30, 0, 0 } }
		)
		eyes(body, C.toxic, nil, 0.18, 0.12, 0.22)
		put(b, "VCyl", { 1.55, 0.08, 1.55 }, { 0, top - 0.1, 0 }, C.black, { mat = "Fabric" })
		cone(b, { 0, top - 0.08, 0.1 }, 0.85, 1.25, C.black, { mat = "Fabric" })
		put(b, "VCyl", { 0.9, 0.12, 0.9 }, { 0, top + 0.05, 0.08 }, C.toxic, { mat = "Fabric" })
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.12, 2.3, 0.12 }, off(h, 0, 0.6, -0.1), C.darkWood, { mat = "Wood" })
			put(
				b,
				"Ball",
				{ 0.4, 0.4, 0.4 },
				off(h, 0, 1.85, -0.1),
				C.toxic,
				{ neon = true, light = { 6, 0.8 } }
			)
		end)
		return done(b, "enemy_3_placeholder")
	end,
	-- 4 little imp
	function()
		local red = { 200, 64, 56 }
		local body = biped({
			skin = red,
			cloth = red,
			pants = { 120, 36, 36 },
			feet = C.black,
			torso = { 0.85, 0.85, 0.65 },
			head = { 0.9, 0.85, 0.85 },
			leg = 0.6,
			torsoShape = "Ball",
		})
		local b = body.b
		horns(b, body, C.black, 0.45, 0.32)
		eyes(body, C.yellow, nil, 0.2, 0.08, 0.22)
		put(b, "Block", { 0.35, 0.08, 0.05 }, off(body.headC, 0, -0.2, -0.43), C.white)
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "wing" .. n, { s * 0.3, body.chest + 0.2, 0.35 }, function()
				put(
					b,
					"Block",
					{ 0.9, 0.6, 0.05 },
					{ s * 0.75, body.chest + 0.35, 0.4 },
					{ 70, 24, 30 },
					{ rot = { 0, 0, -s * 25 } }
				)
			end)
		end
		within(b, "tail", { 0, body.hip, 0.3 }, function()
			put(
				b,
				"Block",
				{ 0.08, 0.08, 0.8 },
				{ 0, body.hip - 0.1, 0.65 },
				red,
				{ rot = { 25, 0, 0 } }
			)
			put(b, "Wedge", { 0.08, 0.2, 0.2 }, { 0, body.hip - 0.28, 1.05 }, red)
		end)
		hold(body, "R", function(h)
			put(
				b,
				"VCyl",
				{ 0.08, 1.7, 0.08 },
				off(h, 0, 0.5, -0.1),
				C.darkSteel,
				{ mat = "Metal" }
			)
			for i = -1, 1 do
				put(
					b,
					"Block",
					{ 0.06, 0.3, 0.06 },
					off(h, i * 0.14, 1.45, -0.1),
					C.darkSteel,
					{ mat = "Metal" }
				)
			end
		end)
		return done(b, "enemy_4_placeholder")
	end,
	-- 5 ring wraith (floats)
	function()
		local b = new()
		local teal = { 70, 180, 180 }
		ghost(b, { 40, 70, 80 }, 1, 0.15)
		put(b, "Ball", { 1.2, 1.1, 1.2 }, { 0, 2.55, 0.05 }, { 24, 36, 44 })
		put(b, "Ball", { 0.8, 0.75, 0.3 }, { 0, 2.35, -0.48 }, C.black)
		for _, side in SIDES do
			put(
				b,
				"Ball",
				{ 0.16, 0.12, 0.08 },
				{ side.s * 0.17, 2.4, -0.62 },
				C.cyan,
				{ neon = true }
			)
		end
		put(b, "VCyl", { 2.4, 0.08, 2.4 }, { 0, 1.5, 0 }, teal, { neon = true, transp = 0.35 })
		put(b, "VCyl", { 2.1, 0.09, 2.1 }, { 0, 1.5, 0 }, { 20, 30, 40 }, { transp = 0.1 })
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "arm" .. n, { s * 0.55, 2.0, 0 }, function()
				put(
					b,
					"Ball",
					{ 0.3, 1.0, 0.3 },
					{ s * 0.75, 1.6, -0.2 },
					{ 40, 70, 80 },
					{ transp = 0.2 }
				)
			end)
		end
		return done(b, "enemy_5_placeholder", 1, true)
	end,
	-- 6 skeleton archer
	function()
		local body = skeleton()
		hold(body, "L", function(h)
			bow(body.b, off(h, 0, 0.2, 0), 1.9, C.darkWood)
		end)
		put(
			body.b,
			"VCyl",
			{ 0.3, 0.95, 0.3 },
			{ 0.25, body.chest + 0.1, body.back + 0.2 },
			C.leather,
			{ rot = { 0, 0, -18 } }
		)
		put(
			body.b,
			"Ball",
			{ 1.0, 0.5, 1.0 },
			off(body.headC, 0, 0.35, 0.05),
			{ 60, 64, 52 },
			{ mat = "Fabric" }
		)
		return done(body.b, "enemy_6_placeholder")
	end,
	-- 7 bandaged dead
	function()
		local wrap = { 222, 206, 170 }
		local body = biped({
			skin = wrap,
			cloth = wrap,
			pants = wrap,
			feet = wrap,
			torso = { 1.05, 1.2, 0.65 },
			head = { 0.95, 1.0, 0.95 },
			leg = 1.05,
			headShape = "Block",
			mat = "Fabric",
			skinMat = "Fabric",
		})
		local b = body.b
		for i = 0, 4 do
			put(
				b,
				"Block",
				{ 1.08, 0.08, 0.68 },
				{ 0, body.hip + 0.15 + i * 0.25, 0 },
				{ 176, 160, 124 },
				{
					mat = "Fabric",
					rot = { 0, 0, (i % 2 == 0) and 8 or -8 },
				}
			)
		end
		put(
			b,
			"Block",
			{ 0.98, 0.08, 0.98 },
			off(body.headC, 0, 0.2, 0),
			{ 176, 160, 124 },
			{ rot = { 0, 0, 10 } }
		)
		put(
			b,
			"Ball",
			{ 0.22, 0.22, 0.08 },
			off(body.headC, 0.2, 0.05, -0.49),
			C.orange,
			{ neon = true }
		)
		put(b, "Block", { 0.2, 1.0, 0.05 }, off(body.hand.L, 0, -0.3, 0), wrap, {
			rot = { 15, 0, 0 },
			g = "armL",
			pv = body.shoulder.L,
		})
		return done(b, "enemy_7_placeholder")
	end,
	-- 8 stitched giant
	function()
		local skin = { 120, 150, 120 }
		local body = biped({
			skin = skin,
			cloth = { 70, 60, 80 },
			pants = { 60, 60, 90 },
			feet = C.black,
			sleeve = skin,
			torso = { 1.9, 1.9, 1.2 },
			head = { 1.1, 1.2, 1.1 },
			leg = 1.4,
			limb = 0.72,
			arm = 2.0,
			headShape = "Block",
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		eyes(body, C.yellow, nil, 0.22, 0.1, 0.22)
		put(b, "Block", { 1.15, 0.3, 1.15 }, off(hc, 0, 0.5, 0), C.black, { mat = "Fabric" })
		for _, side in SIDES do
			put(
				b,
				"Cyl",
				{ 0.4, 0.18, 0.18 },
				off(hc, side.s * 0.7, -0.35, 0),
				C.iron,
				{ mat = "Metal" }
			)
		end
		for i = 0, 3 do
			put(b, "Block", { 0.06, 0.25, 0.04 }, off(hc, -0.3 + i * 0.12, 0.25, -0.56), C.black)
		end
		put(b, "Block", { 1.0, 0.06, 0.04 }, off(hc, -0.12, 0.25, -0.56), C.black)
		put(
			b,
			"Block",
			{ 0.6, 0.5, 0.05 },
			{ 0.35, body.chest + 0.3, -0.62 },
			{ 90, 120, 160 },
			{ mat = "Fabric" }
		)
		return done(b, "enemy_8_placeholder")
	end,
	-- 9 wandering soul (floats, turns ghost)
	function()
		local b = new()
		ghost(b, { 220, 236, 255 }, 0.95, 0.35)
		for _, side in SIDES do
			put(b, "Ball", { 0.24, 0.32, 0.1 }, { side.s * 0.25, 2.35, -0.62 }, C.black)
		end
		put(b, "Ball", { 0.3, 0.38, 0.1 }, { 0, 2.0, -0.6 }, C.black)
		put(
			b,
			"Ball",
			{ 0.5, 0.5, 0.5 },
			{ 0, 2.2, 0 },
			C.cyan,
			{ neon = true, transp = 0.6, light = { 6, 0.7 } }
		)
		for _, side in SIDES do
			within(b, "arm" .. side.n, { side.s * 0.5, 2.0, 0 }, function()
				put(
					b,
					"Ball",
					{ 0.28, 0.9, 0.28 },
					{ side.s * 0.72, 1.65, -0.15 },
					{ 220, 236, 255 },
					{ transp = 0.45 }
				)
			end)
		end
		return done(b, "enemy_9_placeholder", 1, true)
	end,
	-- 10 venom-sting dead
	function()
		local body = zombie({ 120, 170, 90 }, { 60, 80, 50 }, { 50, 60, 44 })
		local b = body.b
		within(b, "tail", { 0, body.hip + 0.3, 0.3 }, function()
			put(
				b,
				"Ball",
				{ 0.3, 0.3, 0.8 },
				{ 0, body.hip + 0.5, 0.65 },
				{ 70, 90, 50 },
				{ rot = { -40, 0, 0 } }
			)
			put(
				b,
				"Ball",
				{ 0.28, 0.28, 0.7 },
				{ 0, body.hip + 1.2, 0.95 },
				{ 70, 90, 50 },
				{ rot = { 20, 0, 0 } }
			)
			put(
				b,
				"Ball",
				{ 0.15, 0.5, 0.15 },
				{ 0, body.hip + 1.7, 0.65 },
				C.toxic,
				{ neon = true, rot = { 60, 0, 0 } }
			)
		end)
		for i = 0, 2 do
			put(
				b,
				"Ball",
				{ 0.24, 0.24, 0.1 },
				{ -0.3 + i * 0.3, body.chest + 0.1 * i, -0.32 },
				C.toxic,
				{ neon = true }
			)
		end
		return done(b, "enemy_10_placeholder")
	end,
	-- 11 shipwreck dead
	function()
		local body = zombie({ 120, 150, 160 }, { 210, 210, 220 }, { 50, 60, 100 })
		local b, hc = body.b, body.headC
		for i = 0, 2 do
			put(b, "Block", { 1.07, 0.1, 0.62 }, { 0, body.chest - 0.35 + i * 0.32, 0 }, C.navy)
		end
		put(b, "Block", { 1.4, 0.35, 0.9 }, off(hc, 0, 0.62, 0), C.black, { mat = "Fabric" })
		put(
			b,
			"Wedge",
			{ 1.4, 0.35, 0.3 },
			off(hc, 0, 0.7, -0.55),
			C.black,
			{ mat = "Fabric", rot = { 0, 180, 0 } }
		)
		put(b, "Ball", { 0.25, 0.25, 0.12 }, off(hc, -0.25, 0.15, -0.5), C.black)
		put(b, "Ball", { 0.3, 0.3, 0.2 }, { 0.3, body.chest - 0.3, -0.32 }, { 80, 140, 110 })
		hold(body, "R", function(h)
			put(
				b,
				"Block",
				{ 0.1, 1.3, 0.28 },
				off(h, 0, 0.8, -0.1),
				C.steel,
				{ mat = "Metal", rot = { -10, 0, 0 } }
			)
			put(b, "Ball", { 0.35, 0.2, 0.35 }, off(h, 0, 0.15, -0.1), C.brass, { mat = "Metal" })
		end)
		return done(b, "enemy_11_placeholder")
	end,
	-- 12 rock golem
	function()
		local stone, moss = { 128, 124, 120 }, { 88, 130, 70 }
		local body = biped({
			skin = stone,
			cloth = stone,
			pants = stone,
			feet = stone,
			torso = { 2.4, 1.9, 1.5 },
			head = { 1.1, 0.9, 1.0 },
			leg = 1.1,
			limb = 0.85,
			arm = 2.0,
			headShape = "Block",
			headY = 3.85,
			headZ = -0.35,
			mat = "Slate",
			skinMat = "Slate",
		})
		local b = body.b
		eyes(body, C.orange, nil, 0.24, 0.05, 0.24)
		put(b, "Block", { 2.0, 0.3, 1.3 }, { 0.1, body.chest + 0.98, 0.1 }, moss, { mat = "Grass" })
		put(
			b,
			"Block",
			{ 0.9, 0.12, 0.05 },
			{ -0.2, body.chest + 0.2, -0.76 },
			C.orange,
			{ neon = true, rot = { 0, 0, 30 } }
		)
		put(
			b,
			"Block",
			{ 0.6, 0.12, 0.05 },
			{ 0.35, body.chest - 0.3, -0.76 },
			C.orange,
			{ neon = true, rot = { 0, 0, -25 } }
		)
		for _, side in SIDES do
			local n = side.n
			put(
				b,
				"Block",
				{ 1.15, 1.0, 1.1 },
				body.hand[n],
				stone,
				{ mat = "Slate", g = "arm" .. n, pv = body.shoulder[n] }
			)
			put(
				b,
				"Block",
				{ 1.0, 0.75, 1.0 },
				off(body.shoulder[n], side.s * 0.1, 0.2, 0),
				moss,
				{ mat = "Grass" }
			)
		end
		return done(b, "enemy_12_placeholder")
	end,
	-- 13 miner dead
	function()
		local body = zombie(C.rot, { 120, 100, 70 }, { 70, 80, 110 })
		local b, hc = body.b, body.headC
		put(b, "Ball", { 1.1, 0.6, 1.1 }, off(hc, 0, 0.42, 0), C.yellow, { mat = "Plastic" })
		put(b, "VCyl", { 1.3, 0.06, 1.3 }, off(hc, 0, 0.3, 0), C.yellow)
		put(
			b,
			"ZCyl",
			{ 0.3, 0.3, 0.2 },
			off(hc, 0, 0.55, -0.55),
			C.white,
			{ neon = true, light = { 9, 1.2 } }
		)
		put(
			b,
			"Block",
			{ 0.12, 1.3, 0.62 },
			{ 0.35, body.chest, 0 },
			C.darkLeather,
			{ rot = { 0, 0, 0 } }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.14, 1.6, 0.14 }, off(h, 0, 0.5, -0.1), C.wood, { mat = "Wood" })
			put(
				b,
				"Block",
				{ 0.14, 0.18, 1.6 },
				off(h, 0, 1.3, -0.1),
				C.iron,
				{ mat = "Metal", rot = { 10, 0, 0 } }
			)
		end)
		return done(b, "enemy_13_placeholder")
	end,
	-- 14 pumpkin head
	function()
		local body = biped({
			skin = C.orange,
			cloth = { 110, 90, 60 },
			pants = { 80, 70, 50 },
			feet = C.darkLeather,
			sleeve = { 110, 90, 60 },
			hands = C.tan,
			torso = { 1.0, 1.15, 0.6 },
			head = { 1.35, 1.1, 1.25 },
			leg = 1.05,
			limb = 0.32,
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		for i = -1, 1, 2 do
			put(b, "Ball", { 0.55, 1.05, 1.2 }, off(hc, i * 0.38, 0, 0), { 236, 120, 30 })
		end
		put(b, "VCyl", { 0.18, 0.35, 0.18 }, off(hc, 0, 0.65, 0), C.darkGreen)
		for _, side in SIDES do
			put(
				b,
				"Wedge",
				{ 0.26, 0.24, 0.05 },
				off(hc, side.s * 0.27, 0.15, -0.63),
				C.yellow,
				{ neon = true }
			)
		end
		put(
			b,
			"Block",
			{ 0.65, 0.16, 0.05 },
			off(hc, 0, -0.2, -0.63),
			C.yellow,
			{ neon = true, light = { 6, 0.9 } }
		)
		for i = -1, 1 do
			put(
				b,
				"Block",
				{ 0.1, 0.35, 0.12 },
				{ i * 0.35, body.hip - 0.05, -0.32 },
				C.tan,
				{ mat = "Grass" }
			)
		end
		put(
			b,
			"Block",
			{ 0.9, 0.9, 0.05 },
			{ 0, body.chest, -0.31 },
			{ 140, 50, 40 },
			{ mat = "Fabric" }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.12, 2.6, 0.12 }, off(h, 0, 0.7, -0.1), C.darkWood, { mat = "Wood" })
			put(
				b,
				"Block",
				{ 0.08, 0.3, 1.3 },
				off(h, 0, 1.95, -0.65),
				C.darkSteel,
				{ mat = "Metal", rot = { -15, 0, 0 } }
			)
		end)
		return done(b, "enemy_14_placeholder")
	end,
	-- 15 one-eyed giant
	function()
		local skin = { 196, 150, 110 }
		local body = biped({
			skin = skin,
			cloth = skin,
			pants = C.leather,
			feet = skin,
			torso = { 2.1, 2.1, 1.4 },
			head = { 1.5, 1.45, 1.4 },
			leg = 1.6,
			limb = 0.8,
			arm = 2.2,
			torsoShape = "Ball",
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		put(b, "Ball", { 0.75, 0.75, 0.3 }, off(hc, 0, 0.12, -0.62), C.white)
		put(b, "Ball", { 0.35, 0.35, 0.2 }, off(hc, 0, 0.12, -0.75), { 160, 40, 40 })
		put(b, "Ball", { 0.15, 0.15, 0.1 }, off(hc, 0, 0.12, -0.83), C.black)
		put(b, "Block", { 0.8, 0.12, 0.2 }, off(hc, 0, 0.55, -0.62), { 120, 80, 60 })
		put(b, "Block", { 0.6, 0.15, 0.05 }, off(hc, 0, -0.4, -0.7), C.black)
		horns(b, body, C.bone, 0.5, 0.0)
		put(
			b,
			"Block",
			{ 2.2, 0.55, 1.5 },
			{ 0, body.hip + 0.15, 0 },
			C.leather,
			{ mat = "Fabric" }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.4, 2.6, 0.4 }, off(h, 0, 0.9, -0.1), C.wood, { mat = "Wood" })
			put(b, "VCyl", { 0.75, 1.3, 0.75 }, off(h, 0, 2.2, -0.1), C.darkWood, { mat = "Wood" })
		end)
		return done(b, "enemy_15_placeholder")
	end,
	-- 16 axe knight
	function()
		local body = knight({ 90, 92, 104 }, { 150, 40, 44 }, C.darkRed, 1.1)
		hold(body, "R", function(h)
			axe(body.b, h, 2.6, C.steel)
		end)
		return done(body.b, "enemy_16_placeholder")
	end,
	-- 17 bomb dead
	function()
		local skin = { 150, 170, 110 }
		local body = biped({
			skin = skin,
			cloth = skin,
			pants = { 80, 70, 60 },
			feet = C.black,
			torso = { 1.5, 1.4, 1.4 },
			head = { 0.8, 0.8, 0.8 },
			leg = 0.8,
			torsoShape = "Ball",
			headShape = "Block",
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		eyes(body, C.yellow, nil, 0.16, 0.1, 0.22)
		for i = -1, 1 do
			put(b, "VCyl", { 0.3, 0.75, 0.3 }, { i * 0.38, body.chest, -0.68 }, C.red)
		end
		put(b, "Block", { 1.4, 0.14, 0.2 }, { 0, body.chest + 0.15, -0.7 }, C.darkLeather)
		put(b, "VCyl", { 0.08, 0.45, 0.08 }, off(hc, 0, 0.6, 0), C.tan)
		put(
			b,
			"Ball",
			{ 0.24, 0.24, 0.24 },
			off(hc, 0, 0.88, 0),
			C.orange,
			{ neon = true, light = { 5, 1 } }
		)
		return done(b, "enemy_17_placeholder")
	end,
	-- 18 eyeball monster (floats)
	function()
		local b = new()
		put(b, "Ball", { 1.9, 1.9, 1.9 }, { 0, 2.0, 0 }, C.white)
		put(b, "Ball", { 0.9, 0.9, 0.3 }, { 0, 2.05, -0.86 }, { 70, 50, 140 })
		put(b, "Ball", { 0.45, 0.45, 0.2 }, { 0, 2.05, -0.98 }, C.black)
		put(b, "Ball", { 0.15, 0.15, 0.1 }, { 0.12, 2.18, -1.05 }, C.white, { neon = true })
		for i = 0, 3 do
			put(
				b,
				"Block",
				{ 0.04, 0.4, 0.04 },
				{ -0.5 + i * 0.3, 2.2 + (i % 2) * 0.3, -0.85 },
				C.red,
				{ rot = { 0, 0, 30 * (i - 1.5) } }
			)
		end
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "wing" .. n, { s * 0.8, 2.3, 0.2 }, function()
				put(
					b,
					"Block",
					{ 1.3, 0.8, 0.05 },
					{ s * 1.4, 2.5, 0.3 },
					{ 80, 30, 50 },
					{ rot = { 0, 0, -s * 20 } }
				)
			end)
		end
		within(b, "tail", { 0, 1.2, 0 }, function()
			for i = 0, 3 do
				local a = math.rad(i * 90 + 45)
				put(
					b,
					"Ball",
					{ 0.2, 1.1, 0.2 },
					{ math.cos(a) * 0.4, 0.75, math.sin(a) * 0.4 },
					{ 150, 60, 110 },
					{
						rot = { math.sin(a) * 15, 0, -math.cos(a) * 15 },
					}
				)
			end
		end)
		return done(b, "enemy_18_placeholder", 1, true)
	end,
	-- 19 skeleton spearman
	function()
		local body = skeleton()
		local b = body.b
		put(b, "Ball", { 1.05, 0.55, 1.05 }, off(body.headC, 0, 0.32, 0), C.iron, { mat = "Metal" })
		put(b, "Block", { 0.1, 0.4, 0.15 }, off(body.headC, 0, 0.55, 0), C.red, { mat = "Fabric" })
		hold(body, "R", function(h)
			spear(b, h, 3.1, C.iron, C.darkWood)
		end)
		hold(body, "L", function(h)
			shield(b, off(h, -0.05, 0.35, -0.25), 0.9, { 90, 70, 60 }, C.iron)
		end)
		return done(b, "enemy_19_placeholder")
	end,
	-- 20 shield knight
	function()
		local body = knight({ 150, 156, 170 }, { 70, 80, 140 }, C.navy, 1.2)
		local b = body.b
		hold(body, "L", function(h)
			put(
				b,
				"Block",
				{ 1.7, 2.6, 0.22 },
				off(h, 0.45, 0.8, -0.75),
				{ 110, 116, 132 },
				{ mat = "Metal" }
			)
			put(
				b,
				"Block",
				{ 1.8, 0.15, 0.25 },
				off(h, 0.45, 2.05, -0.75),
				C.gold,
				{ mat = "Metal" }
			)
			put(b, "Ball", { 0.6, 0.6, 0.2 }, off(h, 0.45, 1.0, -0.88), C.gold, { mat = "Metal" })
		end)
		hold(body, "R", function(h)
			sword(b, h, 1.4, C.steel)
		end)
		return done(b, "enemy_20_placeholder")
	end,
}

-- bosses: bigger, each with its own signature ------------------------------------------------------------
local BOSSES: { () -> Figure } = {
	-- 1 king of the dead
	function()
		local body = zombie(C.rot, { 120, 30, 50 }, { 50, 40, 60 })
		local b, hc = body.b, body.headC
		put(b, "VCyl", { 1.05, 0.3, 1.05 }, off(hc, 0, 0.62, 0), C.gold, { mat = "Metal" })
		for i = 0, 4 do
			local a = math.rad(i * 72)
			put(
				b,
				"Wedge",
				{ 0.2, 0.35, 0.15 },
				off(hc, math.cos(a) * 0.42, 0.9, math.sin(a) * 0.42),
				C.gold,
				{ mat = "Metal" }
			)
		end
		put(b, "Ball", { 0.16, 0.16, 0.16 }, off(hc, 0, 0.65, -0.52), C.red, { neon = true })
		put(
			b,
			"Block",
			{ 1.5, 2.0, 0.1 },
			{ 0, body.chest - 0.2, body.back + 0.1 },
			{ 150, 20, 40 },
			{ mat = "Fabric", rot = { 8, 0, 0 } }
		)
		put(
			b,
			"Block",
			{ 1.6, 0.3, 0.8 },
			{ 0, body.chest + 0.55, 0.05 },
			C.white,
			{ mat = "Fabric" }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.14, 2.2, 0.14 }, off(h, 0, 0.6, -0.1), C.gold, { mat = "Metal" })
			put(
				b,
				"Ball",
				{ 0.45, 0.45, 0.45 },
				off(h, 0, 1.8, -0.1),
				C.violet,
				{ neon = true, light = { 8, 1 } }
			)
		end)
		return done(b, "boss_1_placeholder", 1.75)
	end,
	-- 2 frosthead witch
	function()
		local robe = { 120, 170, 220 }
		local body = biped({
			skin = { 210, 230, 250 },
			cloth = robe,
			pants = robe,
			feet = C.navy,
			sleeve = robe,
			torso = { 1.0, 1.15, 0.7 },
			head = { 0.9, 0.95, 0.9 },
			leg = 1.0,
			mat = "Fabric",
		})
		local b, hc, top = body.b, body.headC, body.top
		put(
			b,
			"Wedge",
			{ 1.6, 1.3, 1.3 },
			{ 0, 0.65, -0.05 },
			robe,
			{ mat = "Fabric", rot = { 0, 180, 0 } }
		)
		put(b, "Wedge", { 1.6, 1.3, 1.3 }, { 0, 0.65, 0.05 }, robe, { mat = "Fabric" })
		eyes(body, C.cyan, nil, 0.18, 0.08, 0.22)
		for i = -2, 2 do
			put(
				b,
				"Ball",
				{ 0.2, 0.9 - math.abs(i) * 0.2, 0.2 },
				{ i * 0.22, top + 0.25, hc[3] },
				C.ice,
				{
					mat = "Ice",
					rot = { 0, 0, -i * 12 },
					transp = 0.15,
				}
			)
		end
		put(
			b,
			"Block",
			{ 1.0, 1.4, 0.12 },
			{ 0, body.chest - 0.1, body.back + 0.1 },
			C.white,
			{ mat = "Fabric" }
		)
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.12, 2.4, 0.12 }, off(h, 0, 0.6, -0.1), C.ice, { mat = "Ice" })
			put(
				b,
				"Ball",
				{ 0.35, 0.8, 0.35 },
				off(h, 0, 2.1, -0.1),
				C.cyan,
				{ neon = true, light = { 10, 1.2 } }
			)
		end)
		return done(b, "boss_2_placeholder", 1.8)
	end,
	-- 3 ball-kicking dead
	function()
		local body = zombie({ 130, 160, 110 }, { 230, 230, 230 }, { 40, 40, 60 })
		local b = body.b
		for i = 0, 1 do
			put(b, "Block", { 1.07, 0.18, 0.62 }, { 0, body.chest - 0.2 + i * 0.4, 0 }, C.red)
		end
		put(b, "Block", { 0.35, 0.35, 0.05 }, { 0, body.chest + 0.05, -0.32 }, C.black)
		put(b, "Ball", { 1.4, 1.3, 1.3 }, { 0.2, 0.65, -1.4 }, C.bone)
		for _, side in SIDES do
			put(b, "Ball", { 0.35, 0.4, 0.1 }, { 0.2 + side.s * 0.3, 0.75, -2.03 }, C.black)
		end
		put(b, "Block", { 0.6, 0.12, 0.05 }, { 0.2, 0.3, -1.98 }, C.black)
		return done(b, "boss_3_placeholder", 1.7)
	end,
	-- 4 bandage lord
	function()
		local wrap = { 222, 206, 170 }
		local body = biped({
			skin = wrap,
			cloth = wrap,
			pants = wrap,
			feet = C.gold,
			torso = { 1.2, 1.3, 0.7 },
			head = { 0.95, 1.0, 0.95 },
			leg = 1.1,
			headShape = "Block",
			mat = "Fabric",
			skinMat = "Fabric",
		})
		local b, hc = body.b, body.headC
		for i = 0, 3 do
			put(
				b,
				"Block",
				{ 1.23, 0.08, 0.72 },
				{ 0, body.hip + 0.2 + i * 0.32, 0 },
				{ 176, 160, 124 },
				{ rot = { 0, 0, (i % 2 == 0) and 8 or -8 } }
			)
		end
		put(b, "Block", { 1.15, 0.9, 1.1 }, off(hc, 0, 0.15, 0.05), { 40, 70, 160 })
		for i = 0, 3 do
			put(
				b,
				"Block",
				{ 1.17, 0.1, 1.12 },
				off(hc, 0, -0.15 + i * 0.22, 0.05),
				C.gold,
				{ mat = "Metal" }
			)
		end
		for _, side in SIDES do
			put(b, "Block", { 0.3, 1.0, 0.3 }, off(hc, side.s * 0.55, -0.55, 0.05), { 40, 70, 160 })
		end
		put(b, "Block", { 0.7, 0.9, 0.05 }, off(hc, 0, -0.05, -0.49), wrap)
		eyes(body, C.cyan, nil, 0.18, 0.12, 0.2)
		put(b, "Block", { 1.4, 0.5, 0.75 }, { 0, body.chest + 0.5, 0 }, C.gold, { mat = "Metal" })
		hold(body, "R", function(h)
			put(b, "VCyl", { 0.12, 2.0, 0.12 }, off(h, 0, 0.5, -0.1), C.gold, { mat = "Metal" })
			put(b, "Block", { 0.12, 0.12, 0.5 }, off(h, 0, 1.5, -0.3), C.gold, { mat = "Metal" })
			put(b, "Block", { 0.12, 0.4, 0.12 }, off(h, 0, 1.35, -0.5), C.gold, { mat = "Metal" })
		end)
		return done(b, "boss_4_placeholder", 1.8)
	end,
	-- 5 blink wraith (floats)
	function()
		local b = new()
		ghost(b, { 60, 50, 90 }, 1.3, 0.2)
		put(b, "Ball", { 1.5, 1.4, 1.5 }, { 0, 3.3, 0.05 }, { 30, 24, 50 })
		put(b, "Ball", { 1.0, 0.95, 0.3 }, { 0, 3.1, -0.62 }, C.black)
		for _, side in SIDES do
			put(
				b,
				"Ball",
				{ 0.22, 0.14, 0.08 },
				{ side.s * 0.22, 3.15, -0.8 },
				C.violet,
				{ neon = true }
			)
		end
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "arm" .. n, { s * 0.7, 2.7, 0 }, function()
				put(
					b,
					"Ball",
					{ 0.35, 1.3, 0.35 },
					{ s * 0.95, 2.1, -0.2 },
					{ 60, 50, 90 },
					{ transp = 0.2 }
				)
				if n == "R" then
					put(
						b,
						"VCyl",
						{ 0.12, 3.4, 0.12 },
						{ 1.0, 2.2, -0.35 },
						C.darkWood,
						{ mat = "Wood" }
					)
					put(
						b,
						"Block",
						{ 0.08, 0.35, 1.9 },
						{ 1.0, 3.8, -1.1 },
						C.steel,
						{ mat = "Metal", rot = { -12, 0, 0 } }
					)
				end
			end)
		end
		return done(b, "boss_5_placeholder", 1.5, true)
	end,
	-- 6 glutton beast
	function()
		local skin = { 170, 100, 140 }
		local body = biped({
			skin = skin,
			cloth = skin,
			pants = skin,
			feet = { 120, 70, 100 },
			torso = { 2.6, 2.2, 2.3 },
			head = { 1.6, 1.0, 1.4 },
			leg = 0.8,
			limb = 0.7,
			arm = 1.5,
			torsoShape = "Ball",
			headY = 3.1,
			headZ = -0.35,
		})
		local b, hc = body.b, body.headC
		put(b, "Ball", { 1.9, 1.7, 0.5 }, { 0, body.chest - 0.15, -1.0 }, { 230, 180, 190 })
		put(b, "Block", { 1.3, 0.55, 0.1 }, off(hc, 0, -0.25, -0.7), { 90, 20, 40 })
		for i = -2, 2 do
			put(
				b,
				"Wedge",
				{ 0.18, 0.22, 0.08 },
				off(hc, i * 0.25, -0.08, -0.74),
				C.white,
				{ rot = { 0, 0, 180 } }
			)
			put(b, "Wedge", { 0.18, 0.22, 0.08 }, off(hc, i * 0.25, -0.42, -0.74), C.white)
		end
		eyes(body, C.yellow, nil, 0.3, 0.3, 0.25)
		put(b, "Block", { 0.4, 0.6, 0.1 }, off(hc, 0, -0.75, -0.65), C.toxic, { transp = 0.3 })
		return done(b, "boss_6_placeholder", 1.6)
	end,
	-- 7 mirror knight
	function()
		local body = knight({ 210, 216, 230 }, { 120, 200, 255 }, { 70, 110, 190 }, 1.1)
		local b = body.b
		hold(body, "L", function(h)
			put(b, "ZCyl", { 1.7, 1.7, 0.18 }, off(h, 0.2, 0.6, -0.6), C.steel, { mat = "Metal" })
			put(
				b,
				"ZCyl",
				{ 1.45, 1.45, 0.2 },
				off(h, 0.2, 0.6, -0.61),
				{ 200, 230, 255 },
				{ mat = "Glass", transp = 0.1 }
			)
		end)
		hold(body, "R", function(h)
			sword(b, h, 2.0, C.ice, { neon = true })
		end)
		return done(b, "boss_7_placeholder", 1.7)
	end,
	-- 8 bone dragon
	function()
		local b = new()
		local bone = C.bone
		local neck = quadruped(b, { body = { 1.7, 1.5, 3.4 }, color = bone, leg = 1.2, legW = 0.3 })
		for i = 0, 4 do
			put(
				b,
				"Block",
				{ 1.85, 0.14, 0.18 },
				{ 0, neck[2] - 0.1, -1.2 + i * 0.55 },
				{ 60, 56, 52 }
			)
		end
		put(
			b,
			"Block",
			{ 0.4, 0.4, 1.4 },
			{ 0, neck[2] + 0.7, neck[3] - 0.5 },
			bone,
			{ rot = { -35, 0, 0 } }
		)
		put(b, "Block", { 0.9, 0.75, 1.3 }, { 0, neck[2] + 1.3, neck[3] - 1.3 }, bone)
		put(b, "Block", { 0.75, 0.25, 0.9 }, { 0, neck[2] + 0.95, neck[3] - 1.4 }, bone)
		for _, side in SIDES do
			local s, n = side.s, side.n
			put(
				b,
				"Ball",
				{ 0.24, 0.2, 0.1 },
				{ s * 0.25, neck[2] + 1.4, neck[3] - 1.96 },
				C.toxic,
				{ neon = true }
			)
			put(
				b,
				"Ball",
				{ 0.16, 0.7, 0.16 },
				{ s * 0.3, neck[2] + 1.9, neck[3] - 0.9 },
				bone,
				{ rot = { 40, 0, -s * 10 } }
			)
			within(b, "wing" .. n, { s * 0.6, neck[2] + 0.6, -0.3 }, function()
				put(
					b,
					"Cyl",
					{ 2.6, 0.16, 0.16 },
					{ s * 1.8, neck[2] + 1.2, -0.3 },
					bone,
					{ rot = { 0, 0, -s * 25 } }
				)
				for j = 0, 2 do
					put(
						b,
						"Block",
						{ 0.1, 1.5, 0.1 },
						{ s * (1.2 + j * 0.8), neck[2] + 0.6, -0.3 + j * 0.25 },
						bone,
						{ rot = { 15, 0, 0 } }
					)
				end
				put(
					b,
					"Block",
					{ 2.6, 1.2, 0.05 },
					{ s * 1.9, neck[2] + 0.75, -0.1 },
					{ 70, 90, 70 },
					{ transp = 0.45, rot = { 0, 0, -s * 15 } }
				)
			end)
		end
		within(b, "tail", { 0, neck[2], 1.6 }, function()
			for i = 0, 3 do
				put(
					b,
					"Ball",
					{ 0.45 - i * 0.08, 0.45 - i * 0.08, 0.65 },
					{ 0, neck[2] - 0.15 * i, 2.0 + i * 0.6 },
					bone
				)
			end
		end)
		return done(b, "boss_8_placeholder", 1.5)
	end,
	-- 9 poison-lipped demon (floats)
	function()
		local skin = { 200, 110, 190 }
		local body = biped({
			skin = skin,
			cloth = { 110, 40, 120 },
			pants = { 80, 30, 90 },
			feet = C.black,
			sleeve = skin,
			torso = { 1.1, 1.3, 0.7 },
			head = { 1.0, 1.05, 0.95 },
			leg = 1.0,
			mat = "Fabric",
		})
		local b, hc = body.b, body.headC
		horns(b, body, C.black, 0.6, 0.35)
		eyes(body, C.yellow, nil, 0.2, 0.18, 0.22)
		put(b, "Ball", { 0.6, 0.3, 0.25 }, off(hc, 0, -0.22, -0.45), C.toxic, { neon = true })
		put(
			b,
			"Ball",
			{ 0.14, 0.4, 0.14 },
			off(hc, 0.12, -0.55, -0.45),
			C.toxic,
			{ neon = true, transp = 0.3 }
		)
		for _, side in SIDES do
			local s, n = side.s, side.n
			within(b, "wing" .. n, { s * 0.35, body.chest + 0.3, 0.35 }, function()
				put(
					b,
					"Block",
					{ 1.8, 1.3, 0.06 },
					{ s * 1.2, body.chest + 0.6, 0.45 },
					{ 90, 30, 100 },
					{ rot = { 0, 0, -s * 22 } }
				)
			end)
		end
		within(b, "tail", { 0, body.hip, 0.35 }, function()
			put(
				b,
				"Block",
				{ 0.1, 0.1, 1.2 },
				{ 0, body.hip - 0.2, 0.9 },
				skin,
				{ rot = { 25, 0, 0 } }
			)
			put(
				b,
				"Wedge",
				{ 0.1, 0.3, 0.3 },
				{ 0, body.hip - 0.48, 1.5 },
				C.toxic,
				{ neon = true }
			)
		end)
		return done(b, "boss_9_placeholder", 1.6, true)
	end,
	-- 10 doom knight
	function()
		local body = knight({ 40, 40, 50 }, { 140, 30, 40 }, { 60, 10, 20 }, 1.2)
		local b, hc = body.b, body.headC
		horns(b, body, { 30, 30, 36 }, 0.9, 0.42)
		put(
			b,
			"Block",
			{ 0.9, 0.12, 0.05 },
			off(hc, 0, 0.1, -0.62),
			C.orange,
			{ neon = true, light = { 8, 1.2 } }
		)
		hold(body, "R", function(h)
			put(
				b,
				"Block",
				{ 0.16, 3.4, 0.55 },
				off(h, 0, 2.0, -0.1),
				{ 50, 40, 50 },
				{ mat = "Metal" }
			)
			put(b, "Block", { 0.17, 3.0, 0.15 }, off(h, 0, 2.0, -0.1), C.red, { neon = true })
			put(
				b,
				"Block",
				{ 0.3, 0.16, 1.1 },
				off(h, 0, 0.3, -0.1),
				C.darkSteel,
				{ mat = "Metal" }
			)
		end)
		return done(b, "boss_10_placeholder", 1.75)
	end,
}

-- heroes (figure only when the real avatar is not used, e.g. the jump stage) ------------------------
local function lightHero(): Figure
	local b = new()
	local horse = { 150, 104, 66 }
	local neck = quadruped(b, { body = { 1.4, 1.4, 3.0 }, color = horse, leg = 1.4, legW = 0.38 })
	put(
		b,
		"Block",
		{ 0.6, 1.2, 0.7 },
		{ 0, neck[2] + 0.6, neck[3] - 0.1 },
		horse,
		{ rot = { -25, 0, 0 } }
	)
	put(b, "Block", { 0.55, 0.55, 1.0 }, { 0, neck[2] + 1.15, neck[3] - 0.6 }, horse)
	put(
		b,
		"Block",
		{ 0.15, 0.9, 0.5 },
		{ 0, neck[2] + 0.9, neck[3] + 0.1 },
		C.darkWood,
		{ rot = { -25, 0, 0 } }
	)
	put(b, "Block", { 1.5, 0.9, 1.2 }, { 0, neck[2] + 0.1, 0.2 }, C.blue, { mat = "Fabric" })
	local rider = biped({
		skin = { 240, 210, 180 },
		cloth = C.steel,
		pants = C.navy,
		feet = C.darkLeather,
		sleeve = C.steel,
		torso = { 0.9, 1.0, 0.6 },
		head = { 0.8, 0.85, 0.8 },
		leg = 0.6,
		mat = "Metal",
	}, new())
	shift(b, rider.b.parts, 0, neck[2] + 0.55, 0.2)
	local hy = rider.headC[2] + neck[2] + 0.55
	put(b, "Ball", { 0.9, 0.55, 0.9 }, { 0, hy + 0.2, 0.2 }, C.steel, { mat = "Metal" })
	put(b, "Block", { 0.1, 0.4, 0.5 }, { 0, hy + 0.55, 0.25 }, C.red, { mat = "Fabric" })
	put(
		b,
		"Ball",
		{ 0.55, 0.55, 0.55 },
		{ 0.95, neck[2] + 2.2, -0.2 },
		C.gold,
		{ neon = true, light = { 10, 1.2 } }
	)
	return done(b, "hero_light_placeholder")
end

local function shadowHero(id: string?, transp: number?): Figure
	local cloak = { 50, 40, 74 }
	local body = biped({
		skin = { 200, 190, 220 },
		cloth = cloak,
		pants = { 30, 26, 40 },
		feet = C.black,
		sleeve = cloak,
		torso = { 1.0, 1.2, 0.65 },
		head = { 0.85, 0.9, 0.85 },
		leg = 1.1,
		mat = "Fabric",
	})
	local b, hc = body.b, body.headC
	put(b, "Ball", { 1.05, 1.0, 1.05 }, off(hc, 0, 0.12, 0.08), cloak, { mat = "Fabric" })
	eyes(body, C.violet, nil, 0.16, 0.0, 0.2)
	put(
		b,
		"Block",
		{ 1.1, 1.9, 0.1 },
		{ 0, body.chest - 0.3, body.back + 0.08 },
		{ 34, 26, 50 },
		{ mat = "Fabric", rot = { 8, 0, 0 } }
	)
	hold(body, "R", function(h)
		sword(b, h, 1.7, C.violet, { neon = true })
	end)
	if transp then
		for _, part in b.parts do
			part.transp = math.max(part.transp or 0, transp)
		end
	end
	return done(b, id or "hero_shadow_placeholder")
end

-- set pieces -------------------------------------------------------------------------------------------
local CASTLE_STONE = {
	{ 104, 98, 92 },
	{ 70, 84, 70 },
	{ 150, 170, 190 },
	{ 90, 60, 50 },
	{ 64, 56, 80 },
}

local function castle(chapter: number): Figure
	local b = new()
	local stone = CASTLE_STONE[math.clamp(chapter, 1, 5)]
	local dark = { stone[1] * 0.6, stone[2] * 0.6, stone[3] * 0.6 }
	put(b, "Block", { 3.0, 7.0, 9.0 }, { 0.6, 3.5, 0 }, stone, { mat = "Cobblestone" })
	for _, side in { -1, 1 } do
		put(b, "VCyl", { 3.2, 10.5, 3.2 }, { 0, 5.25, side * 5.3 }, stone, { mat = "Cobblestone" })
		cone(b, { 0, 10.5, side * 5.3 }, 3.8, 2.6, { 120, 40, 60 }, { mat = "Slate" })
		put(b, "Block", { 0.2, 0.9, 0.5 }, { -1.6, 7.6, side * 5.3 }, C.yellow, { neon = true })
		put(
			b,
			"Block",
			{ 0.1, 2.2, 1.3 },
			{ -1.65, 4.6, side * 3.2 },
			{ 120, 30, 50 },
			{ mat = "Fabric" }
		)
	end
	for i = -3, 3 do
		put(b, "Block", { 3.1, 0.9, 0.8 }, { 0.6, 7.45, i * 1.15 }, stone, { mat = "Cobblestone" })
	end
	put(b, "Block", { 0.3, 4.6, 4.2 }, { -0.95, 2.3, 0 }, dark, { mat = "Slate" })
	put(
		b,
		"Block",
		{ 0.2, 4.2, 3.6 },
		{ -1.05, 2.1, 0 },
		{ 182, 68, 140 },
		{ neon = true, transp = 0.25, light = { 14, 1.4 } }
	)
	put(b, "Ball", { 0.3, 1.4, 1.6 }, { -1.1, 5.4, 0 }, C.bone)
	for _, side in { -1, 1 } do
		put(b, "Ball", { 0.2, 0.36, 0.36 }, { -1.25, 5.5, side * 0.35 }, C.violet, { neon = true })
	end
	-- the original castle is drawn facing the player; turn the gate (built facing -X) to face -Z
	for _, part in b.parts do
		local x, z = part.at[1], part.at[3]
		part.at = { -z, part.at[2], x }
		local rot = part.rot or { 0, 0, 0 }
		part.rot = { rot[1], rot[2] - 90, rot[3] }
	end
	return done(b, "castle_placeholder")
end

local function wagon(): Figure
	local b = new()
	put(b, "Block", { 2.2, 1.0, 3.6 }, { 0, 1.5, 0.4 }, C.wood, { mat = "WoodPlanks" })
	put(b, "Block", { 2.3, 0.15, 3.7 }, { 0, 2.05, 0.4 }, C.darkWood, { mat = "Wood" })
	put(b, "ZCyl", { 2.2, 2.2, 3.3 }, { 0, 2.3, 0.4 }, { 236, 226, 196 }, { mat = "Fabric" })
	put(b, "Block", { 2.3, 0.6, 3.4 }, { 0, 2.0, 0.4 }, C.wood, { mat = "WoodPlanks" })
	for _, x in { -1.2, 1.2 } do
		for _, z in { -0.8, 1.6 } do
			put(b, "Cyl", { 0.25, 1.3, 1.3 }, { x, 0.65, z }, C.darkWood, { mat = "Wood" })
			put(b, "Cyl", { 0.3, 0.35, 0.35 }, { x, 0.65, z }, C.iron, { mat = "Metal" })
		end
	end
	put(b, "VCyl", { 0.6, 0.8, 0.6 }, { 0.5, 2.7, 1.85 }, C.wood, { mat = "Wood" })
	put(
		b,
		"Ball",
		{ 0.4, 0.5, 0.4 },
		{ -0.9, 2.9, -1.3 },
		C.gold,
		{ neon = true, light = { 9, 1 } }
	)
	put(b, "Block", { 0.12, 0.12, 1.6 }, { 0, 1.2, -2.1 }, C.darkWood)
	local donkey = new()
	local mule = { 140, 120, 110 }
	local neck =
		quadruped(donkey, { body = { 0.9, 0.9, 1.7 }, color = mule, leg = 0.75, legW = 0.25 })
	put(donkey, "Block", { 0.5, 0.55, 0.75 }, { 0, neck[2] + 0.35, neck[3] - 0.25 }, mule)
	for _, side in SIDES do
		put(
			donkey,
			"Ball",
			{ 0.16, 0.6, 0.14 },
			{ side.s * 0.18, neck[2] + 0.85, neck[3] - 0.1 },
			mule,
			{
				rot = { 0, 0, -side.s * 15 },
			}
		)
	end
	shift(b, donkey.parts, 0, 0, -3.4)
	return done(b, "wagon_placeholder")
end

local function siegeHorse(): Figure
	local b = new()
	local wood = { 150, 104, 60 }
	put(b, "Block", { 3.0, 0.4, 5.4 }, { 0, 0.85, 0 }, C.darkWood, { mat = "WoodPlanks" })
	for _, x in { -1.6, 1.6 } do
		for _, z in { -2.0, 0, 2.0 } do
			put(b, "Cyl", { 0.3, 1.3, 1.3 }, { x, 0.65, z }, C.darkWood, { mat = "Wood" })
		end
	end
	for _, x in { -0.7, 0.7 } do
		for _, z in { -1.6, 1.6 } do
			put(b, "VCyl", { 0.55, 2.0, 0.55 }, { x, 2.0, z }, wood, { mat = "Wood" })
		end
	end
	put(b, "Block", { 2.2, 2.0, 4.6 }, { 0, 4.0, 0 }, wood, { mat = "WoodPlanks" })
	put(
		b,
		"Block",
		{ 1.3, 2.6, 1.3 },
		{ 0, 5.6, -2.2 },
		wood,
		{ mat = "WoodPlanks", rot = { -25, 0, 0 } }
	)
	put(b, "Block", { 1.2, 1.2, 2.2 }, { 0, 6.8, -3.0 }, wood, { mat = "WoodPlanks" })
	put(b, "Block", { 0.3, 1.8, 1.4 }, { 0, 6.3, -1.7 }, C.darkWood, { rot = { -25, 0, 0 } })
	for _, side in SIDES do
		local s = side.s
		put(b, "Ball", { 0.24, 0.24, 0.12 }, { s * 0.6, 7.0, -3.4 }, C.red, { neon = true })
		put(b, "Wedge", { 0.2, 0.6, 0.4 }, { s * 0.4, 7.6, -2.4 }, wood)
	end
	put(b, "Block", { 0.25, 1.4, 0.25 }, { 0, 3.8, 2.5 }, C.darkWood, { rot = { 30, 0, 0 } })
	return done(b, "siege_horse_placeholder")
end

local function frog(): Figure
	local b = new()
	local green = { 90, 190, 80 }
	put(b, "Ball", { 1.1, 0.8, 1.2 }, { 0, 0.5, 0 }, green)
	put(b, "Ball", { 0.8, 0.5, 0.6 }, { 0, 0.5, -0.4 }, { 210, 240, 160 })
	for _, side in SIDES do
		local s = side.s
		put(b, "Ball", { 0.34, 0.34, 0.34 }, { s * 0.3, 0.95, -0.35 }, green)
		put(b, "Ball", { 0.16, 0.16, 0.1 }, { s * 0.3, 1.0, -0.5 }, C.black)
		put(b, "Ball", { 0.35, 0.3, 0.7 }, { s * 0.55, 0.2, 0.15 }, green)
	end
	return done(b, "frog_curse")
end

-- public lookups -------------------------------------------------------------------------------------
local cache: { [string]: Figure } = {}
local function cached(key: string, make: () -> Figure): Figure
	local hit = cache[key]
	if not hit then
		hit = make()
		cache[key] = hit
	end
	return hit
end

-- kind/n of a battle entity -> its figure (unknown numbers fall back to the first design)
function FigureLook.figure(kind: string, n: number?, heroKind: string?, chapter: number?): Figure
	local i = n or 1
	if kind == "Hero" then
		return if heroKind == "shadow"
			then cached("hero-shadow", function()
				return shadowHero()
			end)
			else cached("hero-light", lightHero)
	elseif kind == "Unit" then
		local make = UNITS[i] or UNITS[1]
		return cached("unit-" .. (if UNITS[i] then i else 1), make)
	elseif kind == "Totem" then
		local make = TOTEMS[i] or TOTEMS[1]
		return cached("totem-" .. (if TOTEMS[i] then i else 1), make)
	elseif kind == "Enemy" then
		local make = ENEMIES[i] or ENEMIES[1]
		return cached("enemy-" .. (if ENEMIES[i] then i else 1), make)
	elseif kind == "Boss" or kind == "Runner" then
		if BOSSES[i] then
			return cached("boss-" .. i, BOSSES[i])
		end
		return cached("shadow-boss", function()
			local f = shadowHero("hero_shadow_placeholder", 0.25)
			return {
				id = f.id,
				parts = f.parts,
				height = f.height * 1.6,
				scale = 1.6,
				flying = false,
			}
		end)
	elseif kind == "Castle" then
		local c = math.clamp(chapter or 1, 1, 5)
		return cached("castle-" .. c, function()
			return castle(c)
		end)
	elseif kind == "Wagon" then
		return cached("wagon", wagon)
	elseif kind == "Horse" then
		return cached("horse", siegeHorse)
	elseif kind == "Frog" then
		return cached("frog", frog)
	end
	return cached("unit-1", UNITS[1])
end

-- animation: degrees per group for a state. walk advances while moving, act runs 0..1 over one attack.
function FigureLook.pose(
	state: string?,
	walk: number,
	act: number,
	clock: number
): { [string]: number }
	local swing = math.sin(walk)
	local flap = math.sin(clock * 9) * 32
	local pose: { [string]: number } = {
		legL = swing * 30,
		legR = -swing * 30,
		armL = -swing * 22,
		armR = swing * 22,
		head = 0,
		tail = math.sin(clock * 3) * 14,
		wingL = flap,
		wingR = -flap,
		body = 0,
	}
	if state == "Attack" or state == "Skill" then
		-- raise, strike, recover
		local a = if act < 0.45
			then act / 0.45 * 140
			elseif act < 0.65 then 140 - (act - 0.45) / 0.2 * 115
			else 25 * (1 - (act - 0.65) / 0.35)
		pose.armR = a
		pose.armL = a * 0.25
		pose.legL, pose.legR = 8, -8
		pose.body = if act >= 0.45 and act < 0.8 then -10 else 4
		pose.head = pose.body * -0.5
	elseif state == "Knock" then
		pose.body, pose.armL, pose.armR = 24, -40, -40
		pose.legL, pose.legR = -10, 10
	elseif state == "KnockWait" then
		pose.body = 10
	elseif state == "Ice" then
		for key in pose do
			pose[key] = 0
		end
	end
	return pose
end

-- dungeon maps ---------------------------------------------------------------------------------------
type Theme = {
	name: string,
	ground: { number },
	groundMat: string,
	floor: { number },
	floorMat: string,
	path: { number },
	pathMat: string,
	wall: { number },
	wallMat: string,
	accent: { number },
	lighting: Lighting,
}

local THEMES: { Theme } = {
	{
		name = "ash-fields",
		ground = { 112, 102, 86 },
		groundMat = "Ground",
		floor = { 112, 112, 92 },
		floorMat = "Grass",
		path = { 132, 116, 92 },
		pathMat = "Ground",
		wall = { 120, 116, 108 },
		wallMat = "Cobblestone",
		accent = { 255, 170, 80 },
		lighting = {
			clock = 17.4,
			ambient = { 120, 110, 100 },
			outdoor = { 150, 130, 110 },
			fog = { 190, 160, 130 },
			fogStart = 60,
			fogEnd = 260,
			brightness = 2,
		},
	},
	{
		name = "sunken-swamp",
		ground = { 54, 70, 50 },
		groundMat = "Mud",
		floor = { 70, 84, 58 },
		floorMat = "Mud",
		path = { 96, 76, 52 },
		pathMat = "WoodPlanks",
		wall = { 70, 56, 40 },
		wallMat = "Wood",
		accent = { 150, 255, 120 },
		lighting = {
			clock = 19.2,
			ambient = { 110, 136, 112 },
			outdoor = { 110, 140, 116 },
			fog = { 70, 100, 80 },
			fogStart = 30,
			fogEnd = 180,
			brightness = 1.2,
		},
	},
	{
		name = "ice-canyon",
		ground = { 196, 210, 224 },
		groundMat = "Snow",
		floor = { 186, 202, 220 },
		floorMat = "Snow",
		path = { 140, 180, 214 },
		pathMat = "Ice",
		wall = { 150, 196, 230 },
		wallMat = "Glacier",
		accent = { 130, 220, 255 },
		lighting = {
			clock = 15.5,
			ambient = { 110, 128, 156 },
			outdoor = { 126, 144, 176 },
			fog = { 200, 218, 236 },
			fogStart = 50,
			fogEnd = 240,
			brightness = 0.9,
		},
	},
	{
		name = "burning-mine",
		ground = { 52, 40, 36 },
		groundMat = "Basalt",
		floor = { 68, 54, 46 },
		floorMat = "Basalt",
		path = { 92, 70, 54 },
		pathMat = "Ground",
		wall = { 80, 62, 52 },
		wallMat = "Rock",
		accent = { 255, 120, 40 },
		lighting = {
			clock = 0.5,
			ambient = { 150, 112, 92 },
			outdoor = { 150, 104, 84 },
			fog = { 60, 30, 20 },
			fogStart = 30,
			fogEnd = 200,
			brightness = 1,
		},
	},
	{
		name = "castle-of-the-dead",
		ground = { 48, 44, 58 },
		groundMat = "Slate",
		floor = { 84, 84, 92 },
		floorMat = "Slate",
		path = { 104, 102, 110 },
		pathMat = "Cobblestone",
		wall = { 70, 64, 84 },
		wallMat = "Brick",
		accent = { 190, 120, 255 },
		lighting = {
			clock = 23,
			ambient = { 132, 128, 146 },
			outdoor = { 128, 124, 150 },
			fog = { 50, 40, 70 },
			fogStart = 30,
			fogEnd = 200,
			brightness = 1,
		},
	},
}

-- Park-Miller: the same chapter always gets the same scenery
local function rng(seed: number): () -> number
	local state = seed % 2147483646 + 1
	return function(): number
		state = state * 16807 % 2147483647
		return (state - 1) / 2147483646
	end
end

-- props: each adds parts to the map at (x, z) on the ground
type Prop = (b: Builder, x: number, z: number, r: () -> number, t: Theme) -> ()

local function rock(
	b: Builder,
	x: number,
	z: number,
	r: () -> number,
	color: { number },
	mat: string,
	s: number
)
	local w = s * (0.7 + r() * 0.6)
	put(
		b,
		"Ball",
		{ w * 1.3, w * 0.8, w },
		{ x, w * 0.25, z },
		color,
		{ mat = mat, rot = { 0, r() * 180, 0 } }
	)
end

local function lamp(
	b: Builder,
	x: number,
	z: number,
	color: { number },
	post: { number },
	height: number,
	lit: boolean
)
	put(b, "VCyl", { 0.4, height, 0.4 }, { x, height / 2, z }, post, { mat = "Wood" })
	put(b, "Block", { 0.9, 0.12, 0.9 }, { x, height + 0.05, z }, C.darkSteel, { mat = "Metal" })
	put(b, "Block", { 0.55, 0.75, 0.55 }, { x, height + 0.5, z }, color, {
		neon = true,
		transp = 0.1,
		light = if lit then { 18, 1.6 } else nil,
	})
	put(
		b,
		"Wedge",
		{ 0.9, 0.35, 0.45 },
		{ x, height + 1.05, z - 0.22 },
		C.darkSteel,
		{ rot = { 0, 180, 0 } }
	)
	put(b, "Wedge", { 0.9, 0.35, 0.45 }, { x, height + 1.05, z + 0.22 }, C.darkSteel)
end

local function tree(
	b: Builder,
	x: number,
	z: number,
	r: () -> number,
	trunk: { number },
	leaves: { number }?,
	s: number
)
	local h = s * (3 + r() * 2)
	put(
		b,
		"VCyl",
		{ 0.6 * s, h, 0.6 * s },
		{ x, h / 2, z },
		trunk,
		{ mat = "Wood", rot = { 0, 0, (r() - 0.5) * 10 } }
	)
	for i = 0, 2 do
		local a = r() * math.pi * 2
		put(
			b,
			"Block",
			{ 0.25 * s, 1.6 * s, 0.25 * s },
			{ x + math.cos(a) * 0.5 * s, h * (0.55 + i * 0.12), z + math.sin(a) * 0.5 * s },
			trunk,
			{
				mat = "Wood",
				rot = { math.sin(a) * 40, 0, -math.cos(a) * 40 },
			}
		)
	end
	if leaves then
		put(
			b,
			"Ball",
			{ 3.2 * s, 2.4 * s, 3.2 * s },
			{ x, h + 0.6 * s, z },
			leaves,
			{ mat = "Grass" }
		)
		put(
			b,
			"Ball",
			{ 2.2 * s, 1.8 * s, 2.2 * s },
			{ x + 0.8 * s, h + 1.2 * s, z - 0.4 * s },
			leaves,
			{ mat = "Grass" }
		)
	end
end

local function pine(b: Builder, x: number, z: number, r: () -> number, s: number)
	local h = s * (4 + r() * 2.5)
	put(b, "VCyl", { 0.5 * s, h * 0.4, 0.5 * s }, { x, h * 0.2, z }, C.darkWood, { mat = "Wood" })
	for i = 0, 2 do
		local d = (2.8 - i * 0.8) * s
		put(
			b,
			"VCyl",
			{ d, h * 0.28, d },
			{ x, h * (0.35 + i * 0.22), z },
			{ 50, 90, 70 },
			{ mat = "Grass" }
		)
		put(
			b,
			"VCyl",
			{ d * 0.9, 0.2 * s, d * 0.9 },
			{ x, h * (0.35 + i * 0.22) + h * 0.14, z },
			C.white,
			{ mat = "Snow" }
		)
	end
end

local PROPS: { { inner: { Prop }, outer: { Prop }, edge: Prop } } = {
	-- 1 ash fields: broken stone fences, dead trees, bones, lanterns
	{
		edge = function(b, x, z, r, t)
			local s = if z > 0 then 1 else -1
			if r() < 0.25 then
				return -- a gap in the fence
			end
			local h = 1.2 + r() * 1.2
			put(
				b,
				"Block",
				{ 3.6, h, 0.9 },
				{ x, h / 2, z + s * 0.2 },
				t.wall,
				{ mat = t.wallMat, rot = { 0, (r() - 0.5) * 6, 0 } }
			)
			put(
				b,
				"Block",
				{ 3.8, 0.25, 1.1 },
				{ x, h + 0.1, z + s * 0.2 },
				{ 90, 88, 80 },
				{ mat = "Slate" }
			)
		end,
		inner = {
			function(b, x, z, r, _t)
				rock(b, x, z, r, { 110, 104, 96 }, "Slate", 0.9)
			end,
			function(b, x, z, r, _t)
				put(
					b,
					"Block",
					{ 0.8, 0.25, 0.25 },
					{ x, 0.12, z },
					C.bone,
					{ rot = { 0, r() * 180, 0 } }
				)
				put(b, "Ball", { 0.55, 0.5, 0.55 }, { x + 0.5, 0.25, z + 0.3 }, C.bone)
			end,
			function(b, x, z, r, _t)
				for i = 0, 3 do
					put(
						b,
						"Block",
						{ 0.12, 0.5 + r() * 0.4, 0.12 },
						{ x + i * 0.3, 0.3, z + r() * 0.4 },
						{ 150, 150, 90 },
						{ mat = "Grass" }
					)
				end
			end,
		},
		outer = {
			function(b, x, z, r, _t)
				tree(b, x, z, r, { 72, 62, 56 }, nil, 1.4 + r() * 0.6)
			end,
			function(b, x, z, r, _t)
				rock(b, x, z, r, { 100, 96, 90 }, "Slate", 3 + r() * 2)
			end,
			function(b, x, z, r, _t)
				put(
					b,
					"Block",
					{ 1.0, 1.8, 0.35 },
					{ x, 0.9, z },
					{ 120, 120, 116 },
					{ mat = "Slate", rot = { (r() - 0.5) * 16, r() * 30, 0 } }
				)
				put(
					b,
					"Block",
					{ 0.8, 0.5, 0.36 },
					{ x, 1.9, z },
					{ 120, 120, 116 },
					{ mat = "Slate" }
				)
			end,
		},
	},
	-- 2 sunken swamp: wooden posts, reeds, glowing mushrooms, murky pools, mossy trees
	{
		edge = function(b, x, z, r, t)
			local h = 1.6 + r() * 1.4
			put(
				b,
				"VCyl",
				{ 0.45, h, 0.45 },
				{ x, h / 2 - 0.2, z },
				t.wall,
				{ mat = "Wood", rot = { (r() - 0.5) * 14, 0, (r() - 0.5) * 14 } }
			)
			put(
				b,
				"Block",
				{ 3.4, 0.25, 0.2 },
				{ x + 1.7, 1.0, z },
				t.wall,
				{ mat = "Wood", rot = { 0, 0, (r() - 0.5) * 10 } }
			)
		end,
		inner = {
			function(b, x, z, r, _t)
				put(
					b,
					"VCyl",
					{ 2.5 + r() * 2, 0.05, 2 + r() },
					{ x, 0.03, z },
					{ 50, 80, 70 },
					{ mat = "Glass", transp = 0.25 }
				)
			end,
			function(b, x, z, r, _t)
				for i = 0, 4 do
					local h = 1 + r() * 1.2
					put(
						b,
						"VCyl",
						{ 0.1, h, 0.1 },
						{ x + (r() - 0.5) * 0.8, h / 2, z + (r() - 0.5) * 0.8 },
						{ 110, 140, 70 },
						{
							mat = "Grass",
							rot = { (r() - 0.5) * 20, 0, (r() - 0.5) * 20 },
						}
					)
					if i == 0 then
						put(b, "VCyl", { 0.2, 0.4, 0.2 }, { x, h, z }, { 110, 70, 40 })
					end
				end
			end,
			function(b, x, z, r, _t)
				local h = 0.6 + r() * 0.5
				put(b, "VCyl", { 0.25, h, 0.25 }, { x, h / 2, z }, C.tan)
				put(
					b,
					"Ball",
					{ 0.9, 0.45, 0.9 },
					{ x, h, z },
					{ 120, 255, 160 },
					{ neon = true, transp = 0.15 }
				)
			end,
		},
		outer = {
			function(b, x, z, r, _t)
				tree(b, x, z, r, { 60, 50, 36 }, { 50, 80, 46 }, 1.5 + r() * 0.5)
				put(
					b,
					"Block",
					{ 0.15, 2.2, 0.15 },
					{ x + 1.0, 3.5, z },
					{ 90, 120, 70 },
					{ mat = "Grass" }
				)
			end,
			function(b, x, z, r, _t)
				local h = 2.5 + r() * 2
				put(b, "VCyl", { 0.7, h, 0.7 }, { x, h / 2, z }, C.tan)
				put(
					b,
					"Ball",
					{ 3.2, 1.4, 3.2 },
					{ x, h, z },
					{ 90, 200, 140 },
					{ neon = r() < 0.5, mat = "Fabric" }
				)
			end,
			function(b, x, z, r, _t)
				put(
					b,
					"VCyl",
					{ 6 + r() * 4, 0.06, 5 + r() * 3 },
					{ x, 0.02, z },
					{ 40, 70, 60 },
					{ mat = "Glass", transp = 0.2 }
				)
			end,
		},
	},
	-- 3 ice canyon: ice cliffs, crystals, snowy pines
	{
		edge = function(b, x, z, r, t)
			local s = if z > 0 then 1 else -1
			local h = 4 + r() * 5
			put(b, "Block", { 3.4 + r() * 1.5, h, 2.2 + r() }, { x, h / 2, z + s * 1.2 }, t.wall, {
				mat = t.wallMat,
				rot = { 0, (r() - 0.5) * 25, (r() - 0.5) * 8 },
			})
			put(
				b,
				"Block",
				{ 2.6, 0.5, 2.0 },
				{ x, h + 0.2, z + s * 1.2 },
				C.white,
				{ mat = "Snow" }
			)
		end,
		inner = {
			function(b, x, z, r, t)
				local h = 0.8 + r() * 1.4
				put(
					b,
					"Ball",
					{ 0.5, h, 0.5 },
					{ x, h / 2, z },
					t.accent,
					{ neon = true, transp = 0.3, rot = { (r() - 0.5) * 30, 0, (r() - 0.5) * 30 } }
				)
				put(
					b,
					"Ball",
					{ 0.35, h * 0.6, 0.35 },
					{ x + 0.35, h * 0.3, z + 0.2 },
					t.accent,
					{ neon = true, transp = 0.3, rot = { 0, 0, -25 } }
				)
			end,
			function(b, x, z, r, _t)
				put(b, "Ball", { 2.4 + r(), 0.6, 1.6 }, { x, 0.1, z }, C.white, { mat = "Snow" })
			end,
		},
		outer = {
			function(b, x, z, r, _t)
				pine(b, x, z, r, 1.3 + r() * 0.6)
			end,
			function(b, x, z, r, t)
				local h = 6 + r() * 8
				put(
					b,
					"Block",
					{ 4 + r() * 3, h, 3 + r() * 3 },
					{ x, h / 2, z },
					t.wall,
					{ mat = "Glacier", rot = { 0, r() * 40, 0 } }
				)
			end,
			function(b, x, z, r, t)
				local h = 2.5 + r() * 2.5
				put(
					b,
					"Ball",
					{ 1.0, h, 1.0 },
					{ x, h / 2, z },
					t.accent,
					{ neon = true, transp = 0.25, rot = { 0, 0, (r() - 0.5) * 30 } }
				)
			end,
		},
	},
	-- 4 burning mine: rock walls with timber, lava cracks, ore crystals, mine carts
	{
		edge = function(b, x, z, r, t)
			local s = if z > 0 then 1 else -1
			local h = 3 + r() * 3
			put(
				b,
				"Block",
				{ 3.8, h, 1.8 },
				{ x, h / 2, z + s * 0.9 },
				t.wall,
				{ mat = t.wallMat, rot = { 0, (r() - 0.5) * 12, 0 } }
			)
			if r() < 0.5 then
				put(
					b,
					"Block",
					{ 0.5, 4.2, 0.5 },
					{ x - 1.6, 2.1, z - s * 0.2 },
					C.darkWood,
					{ mat = "Wood" }
				)
			end
		end,
		inner = {
			function(b, x, z, r, t)
				put(
					b,
					"Block",
					{ 2.5 + r() * 2, 0.04, 0.25 },
					{ x, 0.02, z },
					t.accent,
					{ neon = true, rot = { 0, r() * 180, 0 } }
				)
			end,
			function(b, x, z, r, _t)
				rock(b, x, z, r, { 80, 64, 56 }, "Basalt", 0.9)
				put(
					b,
					"Ball",
					{ 0.3, 0.6, 0.3 },
					{ x + 0.3, 0.5, z },
					{ 255, 90, 160 },
					{ neon = true, rot = { 0, 0, 20 } }
				)
			end,
		},
		outer = {
			function(b, x, z, r, t)
				put(
					b,
					"VCyl",
					{ 6 + r() * 4, 0.1, 5 + r() * 3 },
					{ x, 0.05, z },
					t.accent,
					{ neon = true }
				)
				put(
					b,
					"VCyl",
					{ 7 + r() * 4, 0.08, 6 + r() * 3 },
					{ x, 0.03, z },
					{ 40, 24, 20 },
					{ mat = "CrackedLava" }
				)
			end,
			function(b, x, z, _r, _t)
				put(b, "Block", { 1.8, 1.1, 2.6 }, { x, 0.9, z }, C.iron, { mat = "Metal" })
				put(
					b,
					"Block",
					{ 1.6, 0.5, 2.4 },
					{ x, 1.45, z },
					{ 255, 200, 80 },
					{ mat = "Pebble" }
				)
				for _, wz in { -0.8, 0.8 } do
					put(
						b,
						"Cyl",
						{ 2.0, 0.6, 0.6 },
						{ x, 0.3, z + wz },
						C.darkSteel,
						{ mat = "Metal" }
					)
				end
				put(b, "Block", { 0.2, 0.1, 14 }, { x - 0.7, 0.05, z }, C.iron, { mat = "Metal" })
				put(b, "Block", { 0.2, 0.1, 14 }, { x + 0.7, 0.05, z }, C.iron, { mat = "Metal" })
			end,
			function(b, x, z, r, _t)
				rock(b, x, z, r, { 70, 54, 46 }, "Rock", 4 + r() * 3)
			end,
			function(b, x, z, r, _t)
				local h = 2 + r() * 2
				for i = 0, 2 do
					put(
						b,
						"Ball",
						{ 0.6, h * (1 - i * 0.2), 0.6 },
						{ x + i * 0.5, h * 0.4, z + (i - 1) * 0.3 },
						{ 120, 220, 255 },
						{
							neon = true,
							rot = { 0, 0, (i - 1) * 25 },
						}
					)
				end
			end,
		},
	},
	-- 5 castle of the dead: battlements, gravestones, purple braziers, banners
	{
		edge = function(b, x, z, r, t)
			local s = if z > 0 then 1 else -1
			put(b, "Block", { 4.0, 5.0, 1.2 }, { x, 2.5, z + s * 0.6 }, t.wall, { mat = t.wallMat })
			put(
				b,
				"Block",
				{ 1.4, 1.0, 1.3 },
				{ x - 1.0, 5.5, z + s * 0.6 },
				t.wall,
				{ mat = t.wallMat }
			)
			put(
				b,
				"Block",
				{ 1.4, 1.0, 1.3 },
				{ x + 1.0, 5.5, z + s * 0.6 },
				t.wall,
				{ mat = t.wallMat }
			)
			if r() < 0.35 then
				put(
					b,
					"Block",
					{ 1.4, 2.6, 0.08 },
					{ x, 3.2, z - s * 0.05 },
					{ 90, 30, 70 },
					{ mat = "Fabric" }
				)
				put(
					b,
					"Ball",
					{ 0.4, 0.4, 0.1 },
					{ x, 3.6, z - s * 0.1 },
					t.accent,
					{ neon = true }
				)
			end
		end,
		inner = {
			function(b, x, z, r, _t)
				put(
					b,
					"Block",
					{ 1.0, 1.4, 0.3 },
					{ x, 0.6, z },
					{ 110, 108, 120 },
					{ mat = "Slate", rot = { (r() - 0.5) * 20, 0, (r() - 0.5) * 12 } }
				)
				put(
					b,
					"ZCyl",
					{ 1.0, 1.0, 0.3 },
					{ x, 1.3, z },
					{ 110, 108, 120 },
					{ mat = "Slate" }
				)
			end,
			function(b, x, z, r, _t)
				put(b, "Ball", { 0.55, 0.5, 0.55 }, { x, 0.22, z }, C.bone)
				put(
					b,
					"Block",
					{ 0.9, 0.18, 0.18 },
					{ x + 0.4, 0.1, z - 0.3 },
					C.bone,
					{ rot = { 0, r() * 180, 0 } }
				)
			end,
		},
		outer = {
			function(b, x, z, r, t)
				put(b, "VCyl", { 4, 12 + r() * 6, 4 }, { x, 7, z }, t.wall, { mat = t.wallMat })
				cone(b, { x, 13 + r() * 3, z }, 4.8, 4, { 60, 40, 80 }, { mat = "Slate" })
			end,
			function(b, x, z, r, _t)
				put(
					b,
					"Block",
					{ 1.0, 1.5, 0.35 },
					{ x, 0.7, z },
					{ 96, 94, 108 },
					{ mat = "Slate", rot = { (r() - 0.5) * 24, r() * 40, 0 } }
				)
			end,
			function(b, x, z, r, _t)
				tree(b, x, z, r, { 46, 40, 52 }, nil, 1.5 + r() * 0.5)
			end,
		},
	},
}

local function themeOf(chapter: number): (number, Theme)
	local c = math.clamp(math.floor(chapter), 1, #THEMES)
	return c, THEMES[c]
end

-- The dungeon for a chapter between x0 and x1 (studs). The fighting lane is 27 studs wide (|z| <= 13.5).
function FigureLook.map(chapter: number, x0: number, x1: number): Map
	local c, t = themeOf(chapter)
	local b = new()
	local r = rng(c * 7919 + 17)
	local length = x1 - x0
	local mid = (x0 + x1) / 2
	put(b, "Block", { length + 120, 1, 160 }, { mid, -0.62, 0 }, t.ground, { mat = t.groundMat })
	put(b, "Block", { length, 1, 27 }, { mid, -0.5, 0 }, t.floor, { mat = t.floorMat })
	put(b, "Block", { length, 1, 9 }, { mid, -0.47, 0 }, t.path, { mat = t.pathMat })
	-- path edging stones every few studs
	for x = x0 + 2, x1 - 2, 6 do
		for _, z in { -4.7, 4.7 } do
			put(
				b,
				"Block",
				{ 1.6 + r() * 1.2, 0.18, 0.5 },
				{ x + r() * 2, 0.05, z },
				t.wall,
				{ mat = t.wallMat }
			)
		end
	end
	local props = PROPS[c]
	for x = x0, x1, 4 do
		for _, z in { -14.2, 14.2 } do
			props.edge(b, x, z, r, t)
		end
	end
	for x = x0 + 3, x1 - 3, 7 do
		for _, side in { -1, 1 } do
			if r() < 0.55 then
				local pick = props.inner[1 + math.floor(r() * #props.inner)]
				pick(b, x + r() * 4, side * (8 + r() * 4.5), r, t)
			end
		end
	end
	for x = x0 - 20, x1 + 20, 9 do
		for _, side in { -1, 1 } do
			local pick = props.outer[1 + math.floor(r() * #props.outer)]
			pick(b, x + r() * 6, side * (19 + r() * 30), r, t)
		end
	end
	-- lanterns light the lane; only some carry a real light (budget)
	local i = 0
	for x = x0 + 4, x1 - 2, 16 do
		for _, z in { -12, 12 } do
			lamp(b, x, z, t.accent, t.wall, 3.2, i % 2 == 0)
			i += 1
		end
	end
	-- the expedition's entry gate at the left end
	put(b, "Block", { 0.8, 7, 0.8 }, { x0 + 1, 3.5, -3.2 }, t.wall, { mat = t.wallMat })
	put(b, "Block", { 0.8, 7, 0.8 }, { x0 + 1, 3.5, 3.2 }, t.wall, { mat = t.wallMat })
	put(b, "Block", { 1.0, 0.9, 7.4 }, { x0 + 1, 7.2, 0 }, t.wall, { mat = t.wallMat })
	put(
		b,
		"Block",
		{ 0.2, 6.2, 5.6 },
		{ x0 + 1, 3.1, 0 },
		{ 68, 180, 238 },
		{ neon = true, transp = 0.55, light = { 16, 1.2 } }
	)
	return { chapter = c, name = t.name, parts = b.parts, lighting = t.lighting }
end

FigureLook.THEME_COUNT = #THEMES

return table.freeze(FigureLook)
