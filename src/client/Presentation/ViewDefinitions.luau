--!strict
-- Code-built original silhouettes for every battle entity (no asset files; data/assets/asset-manifest.json
-- lists each presentationId as a placeholder). Sizes are logical px of the 480x320 field; parts are boxes
-- relative to the entity box (x, y from the top-left, w, h) with a color role or a Color3.
export type Part = { x: number, y: number, w: number, h: number, color: any, round: number? }
export type View = {
	presentationId: string,
	w: number,
	h: number,
	body: Color3,
	accent: Color3,
	parts: { Part },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local WHITE, BLACK, GOLD = rgb(245, 245, 240), rgb(30, 30, 36), rgb(255, 205, 80)

local function view(
	id: string,
	w: number,
	h: number,
	body: Color3,
	accent: Color3,
	parts: { Part }
): View
	return table.freeze({
		presentationId = id,
		w = w,
		h = h,
		body = body,
		accent = accent,
		parts = parts,
	})
end
local function p(x: number, y: number, w: number, h: number, color: any, round: number?): Part
	return { x = x, y = y, w = w, h = h, color = color, round = round }
end
-- A standing creature: head on a body, two eyes facing right.
local function creature(extra: { Part }): { Part }
	local parts = {
		p(0.1, 0.38, 0.8, 0.62, "body", 0.4),
		p(0.25, 0.08, 0.6, 0.45, "body", 1),
		p(0.62, 0.2, 0.1, 0.1, WHITE, 1),
		p(0.66, 0.23, 0.05, 0.05, BLACK, 1),
	}
	for _, part in extra do
		table.insert(parts, part)
	end
	return parts
end

local hero = view("hero_light_placeholder", 34, 46, rgb(196, 206, 226), GOLD, {
	p(0.05, 0.62, 0.9, 0.3, rgb(140, 96, 60), 0.5), -- mount
	p(0.05, 0.85, 0.15, 0.15, rgb(90, 60, 40), 0.3),
	p(0.8, 0.85, 0.15, 0.15, rgb(90, 60, 40), 0.3),
	p(0.25, 0.22, 0.45, 0.45, "body", 0.4), -- rider
	p(0.28, 0.02, 0.4, 0.28, rgb(160, 170, 196), 1), -- helmet
	p(0.72, 0.28, 0.22, 0.22, "accent", 1), -- lantern
})

local UNITS = {
	view(
		"unit_1_placeholder",
		18,
		22,
		rgb(150, 150, 160),
		rgb(200, 180, 130),
		creature({
			p(0.15, 0, 0.25, 0.25, "body", 1),
			p(0.55, 0, 0.25, 0.25, "body", 1),
			p(0.85, 0.1, 0.1, 0.8, "accent"),
		})
	),
	view(
		"unit_2_placeholder",
		18,
		28,
		rgb(236, 236, 236),
		rgb(150, 110, 70),
		creature({
			p(0.3, -0.25, 0.14, 0.4, "body", 0.5),
			p(0.55, -0.25, 0.14, 0.4, "body", 0.5),
			p(0.85, 0.3, 0.12, 0.5, "accent", 0.5),
		})
	),
	view(
		"unit_3_placeholder",
		28,
		30,
		rgb(130, 86, 54),
		rgb(230, 200, 150),
		creature({
			p(0.22, 0.02, 0.18, 0.18, "body", 1),
			p(0.62, 0.02, 0.18, 0.18, "body", 1),
			p(0.3, 0.6, 0.4, 0.3, "accent", 1),
		})
	),
	view(
		"unit_4_placeholder",
		24,
		32,
		rgb(200, 160, 110),
		rgb(220, 60, 60),
		creature({ p(-0.2, 0.6, 0.35, 0.15, "body", 0.5), p(0.8, 0.45, 0.25, 0.2, "accent", 1) })
	),
	view(
		"unit_5_placeholder",
		22,
		26,
		rgb(150, 100, 60),
		BLACK,
		creature({ p(-0.25, 0.4, 0.35, 0.1, "body", 0.5), p(0.75, 0.0, 0.3, 0.3, "accent", 1) })
	),
	view("unit_6_placeholder", 34, 26, rgb(80, 150, 90), rgb(200, 180, 110), {
		p(0, 0.25, 0.85, 0.75, "body", 0.6),
		p(0.75, 0.35, 0.25, 0.3, "accent", 1),
		p(0.88, 0.42, 0.06, 0.08, BLACK, 1),
	}),
	view(
		"unit_7_placeholder",
		38,
		30,
		rgb(140, 140, 150),
		WHITE,
		creature({ p(0.85, 0.15, 0.2, 0.12, "accent", 0.5) })
	),
	view(
		"unit_8_placeholder",
		18,
		26,
		rgb(40, 44, 60),
		rgb(120, 200, 255),
		creature({ p(0.3, 0.45, 0.45, 0.5, WHITE, 1), p(0.8, 0.3, 0.15, 0.08, rgb(250, 170, 60)) })
	),
	view(
		"unit_9_placeholder",
		40,
		40,
		rgb(210, 70, 60),
		rgb(250, 210, 80),
		creature({
			p(0.05, -0.1, 0.45, 0.35, rgb(160, 40, 40), 0.3),
			p(0.35, 0.55, 0.35, 0.3, "accent", 1),
		})
	),
}

local ENEMY_COLORS = {
	rgb(120, 170, 100),
	rgb(230, 230, 220),
	rgb(150, 90, 180),
	rgb(210, 70, 60),
	rgb(80, 190, 190),
	rgb(210, 210, 200),
	rgb(220, 200, 150),
	rgb(150, 190, 140),
	rgb(230, 240, 255),
	rgb(80, 140, 70),
	rgb(90, 130, 200),
	rgb(130, 130, 130),
	rgb(140, 140, 110),
	rgb(240, 150, 50),
	rgb(150, 90, 170),
	rgb(170, 180, 190),
	rgb(50, 50, 60),
	rgb(240, 150, 190),
	rgb(220, 220, 210),
	rgb(160, 170, 180),
}
local ENEMY_SIZE = {
	{ 18, 26 },
	{ 16, 26 },
	{ 18, 30 },
	{ 16, 22 },
	{ 22, 26 },
	{ 16, 26 },
	{ 18, 28 },
	{ 28, 38 },
	{ 20, 26 },
	{ 18, 26 },
	{ 20, 28 },
	{ 36, 34 },
	{ 20, 28 },
	{ 22, 26 },
	{ 34, 44 },
	{ 30, 38 },
	{ 22, 22 },
	{ 24, 24 },
	{ 20, 30 },
	{ 36, 40 },
}
local ENEMY_EXTRA: { [number]: { Part } } = {
	[3] = { p(0.2, -0.25, 0.6, 0.35, rgb(60, 30, 80), 0.2) },
	[4] = { p(0.2, -0.1, 0.15, 0.2, rgb(60, 20, 20)), p(0.65, -0.1, 0.15, 0.2, rgb(60, 20, 20)) },
	[5] = { p(-0.1, 0.3, 1.2, 0.15, rgb(40, 120, 120), 1) },
	[6] = { p(-0.15, 0.3, 0.12, 0.5, rgb(120, 90, 60), 0.5) },
	[7] = { p(0.1, 0.5, 0.8, 0.08, rgb(170, 150, 110)), p(0.1, 0.7, 0.8, 0.08, rgb(170, 150, 110)) },
	[13] = { p(0.2, 0, 0.6, 0.2, rgb(240, 200, 60), 0.5) },
	[14] = { p(0.15, -0.05, 0.75, 0.55, rgb(240, 130, 30), 1) },
	[15] = { p(0.45, 0.15, 0.25, 0.25, WHITE, 1), p(0.52, 0.2, 0.1, 0.12, rgb(200, 40, 40), 1) },
	[16] = { p(-0.25, 0.2, 0.3, 0.12, rgb(120, 120, 130)) },
	[17] = { p(0.4, -0.2, 0.08, 0.25, rgb(250, 150, 60)) },
	[18] = { p(0.2, 0.15, 0.6, 0.6, WHITE, 1), p(0.38, 0.32, 0.25, 0.25, rgb(60, 40, 120), 1) },
	[19] = { p(-0.4, 0.35, 0.5, 0.06, rgb(120, 90, 60)) },
	[20] = { p(-0.15, 0.25, 0.3, 0.7, rgb(110, 120, 140), 0.3) },
}
-- Literal ids: tools/balance_lib.asset_audit reads them from this file.
local ENEMY_IDS = {
	"enemy_1_placeholder",
	"enemy_2_placeholder",
	"enemy_3_placeholder",
	"enemy_4_placeholder",
	"enemy_5_placeholder",
	"enemy_6_placeholder",
	"enemy_7_placeholder",
	"enemy_8_placeholder",
	"enemy_9_placeholder",
	"enemy_10_placeholder",
	"enemy_11_placeholder",
	"enemy_12_placeholder",
	"enemy_13_placeholder",
	"enemy_14_placeholder",
	"enemy_15_placeholder",
	"enemy_16_placeholder",
	"enemy_17_placeholder",
	"enemy_18_placeholder",
	"enemy_19_placeholder",
	"enemy_20_placeholder",
}
local BOSS_IDS = {
	"boss_1_placeholder",
	"boss_2_placeholder",
	"boss_3_placeholder",
	"boss_4_placeholder",
	"boss_5_placeholder",
	"boss_6_placeholder",
	"boss_7_placeholder",
	"boss_8_placeholder",
	"boss_9_placeholder",
	"boss_10_placeholder",
}
local ENEMIES: { View } = {}
for n = 1, 20 do
	local size = ENEMY_SIZE[n]
	ENEMIES[n] = view(
		ENEMY_IDS[n],
		size[1],
		size[2],
		ENEMY_COLORS[n],
		rgb(60, 30, 30),
		creature(ENEMY_EXTRA[n] or {})
	)
end

local BOSS_COLORS = {
	rgb(110, 160, 90),
	rgb(220, 230, 250),
	rgb(90, 170, 90),
	rgb(210, 190, 140),
	rgb(200, 220, 255),
	rgb(200, 100, 160),
	rgb(170, 180, 210),
	rgb(220, 220, 200),
	rgb(220, 90, 150),
	rgb(60, 60, 80),
}
local BOSSES: { View } = {}
for n = 1, 10 do
	BOSSES[n] = view(
		BOSS_IDS[n],
		48 + n * 2,
		58 + n * 2,
		BOSS_COLORS[n],
		GOLD,
		creature({
			p(0.3, -0.12, 0.4, 0.18, "accent", 0.1), -- crown
			p(0.32, -0.2, 0.08, 0.1, "accent"),
			p(0.46, -0.24, 0.08, 0.14, "accent"),
			p(0.6, -0.2, 0.08, 0.1, "accent"),
		})
	)
end

local SHADOW = view("hero_shadow_placeholder", 28, 46, rgb(75, 65, 110), rgb(170, 120, 245), {
	p(0.2, 0.3, 0.6, 0.55, "body", 0.2),
	p(0.25, 0, 0.5, 0.35, "accent", 0.3),
	p(0.65, 0.18, 0.12, 0.08, WHITE),
	p(0.85, 0.25, 0.08, 0.55, WHITE),
	p(0.1, 0.82, 0.3, 0.18, BLACK),
	p(0.6, 0.82, 0.3, 0.18, BLACK),
})
local TOTEM_IDS = {
	"totem_1_placeholder",
	"totem_2_placeholder",
	"totem_3_placeholder",
	"totem_4_placeholder",
	"totem_5_placeholder",
	"totem_6_placeholder",
	"totem_7_placeholder",
	"totem_8_placeholder",
	"totem_9_placeholder",
}
local TOTEMS: { View } = {}
for n, id in TOTEM_IDS do
	TOTEMS[n] = view(
		id,
		22 + n * 2,
		24 + n,
		rgb(90 + n * 8, 75, 110 + n * 7),
		GOLD,
		creature({ p(0.05, 0.5, 0.9, 0.12, "accent"), p(0.4, 0, 0.2, 0.2, "accent") })
	)
end

return table.freeze({
	world3d = table.freeze({ presentationId = "dungeon_3d_placeholder" }),
	hero = hero,
	shadow = SHADOW,
	totems = table.freeze(TOTEMS),
	horse = view("siege_horse_placeholder", 85, 70, rgb(90, 65, 55), rgb(190, 110, 65), {
		p(0.05, 0.15, 0.7, 0.55, "body"),
		p(0.65, 0, 0.3, 0.35, "accent"),
		p(0.05, 0.7, 0.25, 0.3, BLACK, 1),
		p(0.65, 0.7, 0.25, 0.3, BLACK, 1),
	}),
	units = table.freeze(UNITS),
	enemies = table.freeze(ENEMIES),
	bosses = table.freeze(BOSSES),
	castle = view("castle_placeholder", 90, 140, rgb(70, 60, 80), rgb(200, 60, 60), {
		p(0, 0.15, 1, 0.85, "body", 0.05),
		p(0.05, 0, 0.18, 0.2, "body"),
		p(0.41, 0, 0.18, 0.2, "body"),
		p(0.77, 0, 0.18, 0.2, "body"),
		p(0.35, 0.6, 0.3, 0.4, BLACK, 0.4),
		p(0.42, 0.3, 0.16, 0.12, "accent", 1),
	}),
	wagon = view("wagon_placeholder", 60, 40, rgb(160, 110, 60), rgb(240, 220, 160), {
		p(0, 0.15, 1, 0.55, "body", 0.1),
		p(0.05, 0, 0.9, 0.2, "accent", 0.5),
		p(0.1, 0.6, 0.25, 0.4, BLACK, 1),
		p(0.65, 0.6, 0.25, 0.4, BLACK, 1),
	}),
	field = table.freeze({ presentationId = "field_placeholder" }),
	projectile = table.freeze({ presentationId = "projectile_placeholder" }),
	-- Object rows -> color, length and height in logical px (E02 §3 object table rows).
	objects = table.freeze({
		[275] = { color = rgb(240, 100, 40), w = 14, h = 12 },
		[278] = { color = WHITE, w = 8, h = 10 },
		[282] = { color = rgb(180, 150, 250), w = 24, h = 5 },
		[283] = { color = rgb(120, 210, 80), w = 12, h = 12 },
		[292] = { color = GOLD, w = 20, h = 4 },
		[293] = { color = rgb(150, 110, 100), w = 18, h = 6 },
		[294] = { color = rgb(240, 90, 40), w = 18, h = 6 },
		[260] = { color = rgb(150, 110, 70), w = 14, h = 2 },
		[261] = { color = rgb(250, 220, 120), w = 16, h = 3 },
		[262] = { color = BLACK, w = 6, h = 6 },
		[263] = { color = rgb(80, 40, 40), w = 8, h = 8 },
		[264] = { color = rgb(170, 220, 255), w = 8, h = 4 },
		[265] = { color = rgb(120, 200, 255), w = 10, h = 6 },
		[266] = { color = rgb(220, 60, 60), w = 6, h = 6 },
		[268] = { color = GOLD, w = 12, h = 10 },
		[269] = { color = rgb(150, 220, 255), w = 10, h = 10 },
		[273] = { color = rgb(120, 220, 90), w = 10, h = 10 },
		[295] = { color = WHITE, w = 8, h = 4 },
		[296] = { color = rgb(200, 200, 190), w = 12, h = 2 },
		[297] = { color = rgb(120, 200, 80), w = 6, h = 6 },
		[298] = { color = rgb(240, 130, 30), w = 14, h = 12 },
		[299] = { color = rgb(250, 120, 200), w = 22, h = 3 },
		[301] = { color = rgb(220, 220, 240), w = 14, h = 6 },
		[302] = { color = rgb(250, 120, 170), w = 8, h = 8 },
		[303] = { color = rgb(150, 70, 220), w = 20, h = 20 },
	}),
})
