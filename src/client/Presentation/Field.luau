--!strict
-- 2D battlefield renderer: logical 480x320 px scaled to the screen height, original bottom-origin y
-- converted to screen space, camera holding the hero at one third of the view (E04 §6). Visual only.
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Views = require("./ViewDefinitions")

local LOGICAL_HEIGHT = 320
local GROUND_Y = 145 -- screen-space top of the walkable band (320 - 175)
local FIELD_MAX = 1024
local FADE = 0.25

type Sprite = {
	root: Frame,
	parts: { Frame },
	bar: Frame?,
	fill: Frame?,
	view: any,
	seen: number,
	fading: number?,
}

local function viewFor(e: any, heroKind: string?, mode: string?): any
	if e.kind == "Hero" then
		return if mode == "Jump"
			then Views.totems[3]
			elseif heroKind == "shadow" then Views.shadow
			else Views.hero
	elseif e.kind == "Totem" then
		return Views.totems[e.n] or Views.totems[1]
	elseif e.kind == "Runner" then
		return Views.shadow
	elseif e.kind == "Horse" then
		return Views.horse
	elseif e.kind == "Unit" then
		return Views.units[e.n] or Views.units[1]
	elseif e.kind == "Enemy" then
		return Views.enemies[e.n] or Views.enemies[1]
	elseif e.kind == "Boss" then
		return Views.bosses[e.n] or Views.bosses[1]
	elseif e.kind == "Castle" then
		return Views.castle
	elseif e.kind == "Wagon" then
		return Views.wagon
	end
	return Views.units[1]
end

local function new(parent: Instance)
	local root = Widgets.frame(parent, "Field", Theme.background)
	root.Size = UDim2.fromScale(1, 1)
	root.ClipsDescendants = true
	local sky = Widgets.frame(root, "Sky", Theme.chapterSky[1])
	sky.Size = UDim2.fromScale(1, 1)
	local ground = Widgets.frame(root, "Ground", Theme.chapterGround[1])
	local world = Widgets.frame(root, "World")
	world.Size = UDim2.fromScale(1, 1)
	world.ZIndex = 2
	local auraRing = Widgets.frame(world, "Aura", Theme.gold, 999)
	auraRing.BackgroundTransparency = 0.82
	auraRing.ZIndex = 2
	local sprites: { [number]: Sprite } = {}
	local shots: { [number]: Frame } = {}
	local cameraX = 0
	local frameCount = 0

	local function color(part: any, v: any): Color3
		if part.color == "body" then
			return v.body
		elseif part.color == "accent" then
			return v.accent
		end
		return part.color
	end

	local function build(e: any, heroKind: string?, mode: string?): Sprite
		local v = viewFor(e, heroKind, mode)
		local holder = Widgets.frame(world, "E" .. e.id)
		holder.ZIndex = if e.kind == "Castle" then 3 else 5
		local parts: { Frame } = {}
		for _, part in v.parts do
			local box = Widgets.frame(holder, "Part", color(part, v), 0)
			if part.round then
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(part.round, 0)
				round.Parent = box
			end
			box.ZIndex = holder.ZIndex
			table.insert(parts, box)
		end
		local sprite: Sprite = { root = holder, parts = parts, view = v, seen = 0 }
		if e.kind ~= "Castle" then
			local bar = Widgets.frame(holder, "Hp", Color3.fromRGB(20, 20, 20), 2)
			bar.Size = UDim2.new(1, 0, 0, 3)
			bar.Position = UDim2.fromOffset(0, -8)
			bar.ZIndex = 7
			local fill =
				Widgets.frame(bar, "Fill", if e.team == 1 then Theme.hp else Theme.enemyHp, 2)
			fill.ZIndex = 8
			sprite.bar, sprite.fill = bar, fill
		end
		return sprite
	end

	local function place(sprite: Sprite, e: any, scale: number)
		local v = sprite.view
		local size = if e.giant then 1.2 else 1
		local w, h = v.w * size * scale, v.h * size * scale
		local feet = LOGICAL_HEIGHT - e.y
		if e.kind == "Castle" then
			feet = GROUND_Y + 30
		end
		sprite.root.Size = UDim2.fromOffset(w, h)
		sprite.root.Position = UDim2.fromOffset((e.x - cameraX) * scale - w / 2, feet * scale - h)
		local mirrored = e.dir < 0
		for index, part in v.parts do
			local box = sprite.parts[index]
			local x = if mirrored then 1 - part.x - part.w else part.x
			box.Position = UDim2.fromScale(x, part.y)
			box.Size = UDim2.fromScale(part.w, part.h)
			local tint = if e.state == "Ice"
				then Color3.fromRGB(170, 220, 255)
				elseif e.frog then Color3.fromRGB(90, 200, 90)
				elseif e.poisoned then Color3.fromRGB(150, 230, 120)
				elseif e.transformed then Color3.fromRGB(210, 100, 250)
				else nil
			box.BackgroundColor3 = if tint then color(part, v):Lerp(tint, 0.55) else color(part, v)
			box.BackgroundTransparency = if e.state == "Ghost" or e.state == "Blink"
				then 0.65
				else 0
		end
		sprite.root.Rotation = if e.state == "Knock" then -25 * e.dir else 0
		if sprite.bar and sprite.fill then
			local ratio = math.clamp(e.hp / e.maxHp, 0, 1)
			sprite.bar.Visible = ratio < 0.999 or e.kind == "Boss" or e.kind == "Wagon"
			sprite.fill.Size = UDim2.fromScale(ratio, 1)
		end
		sprite.root.ZIndex = 5 + math.floor(e.y) % 3
	end

	local function shot(o: any, scale: number)
		local spec: any = if o.kind == "Coin"
			then { color = Theme.gold, w = 10, h = 10 }
			elseif o.kind == "Spike" then { color = Theme.bad, w = 38, h = 12 }
			else Views.objects[o.row] or { color = Theme.text, w = 6, h = 6 }
		local box = shots[o.id]
		if not box then
			local made = Widgets.frame(world, "O" .. o.id, spec.color, 999)
			made.ZIndex = 9
			shots[o.id] = made
			box = made
		end
		local y = LOGICAL_HEIGHT - 165 - 14
		if o.line and o.line > 0 then
			y = LOGICAL_HEIGHT - ((o.line - 1) * 33 + 75) - 14
		end
		if o.kind == "Lob" then
			y -= math.sin(math.pi * (o.t or 0)) * 40 -- 0.5 s arc (E02 §3.3)
		elseif o.kind == "Drop" then
			y -= (1 - (o.t or 0)) * 50
		end
		box.Size = UDim2.fromOffset(spec.w * scale, spec.h * scale)
		box.Position = UDim2.fromOffset((o.x - cameraX) * scale - spec.w * scale / 2, y * scale)
	end

	local function render(view: any, chapter: number, dt: number)
		frameCount += 1
		local size = root.AbsoluteSize
		local scale = math.max(size.Y / LOGICAL_HEIGHT, 0.5)
		local viewWidth = size.X / scale
		sky.BackgroundColor3 = Theme.chapterSky[chapter] or Theme.chapterSky[1]
		ground.BackgroundColor3 = Theme.chapterGround[chapter] or Theme.chapterGround[1]
		ground.Position = UDim2.fromOffset(0, GROUND_Y * scale)
		ground.Size = UDim2.new(1, 0, 1, -GROUND_Y * scale)
		if not view then
			return
		end
		local hero = nil
		for _, e in view.entities do
			if e.kind == "Hero" then
				hero = e
			end
		end
		local target = 0
		if hero then
			target = hero.x - viewWidth / 3
		end
		local high = math.max(
			(if view.mode == "Jump" then view.heroMaxX else FIELD_MAX) + 40 - viewWidth,
			-40
		)
		target = math.clamp(target, -40, high)
		cameraX += (target - cameraX) * math.min(1, dt * 8)
		local present: { [number]: boolean } = {}
		for _, e in view.entities do
			present[e.id] = true
			local sprite = sprites[e.id]
			if not sprite then
				sprite = build(e, view.heroKind, view.mode)
				sprites[e.id] = sprite
			end
			sprite.fading = nil
			sprite.seen = frameCount
			place(sprite, e, scale)
		end
		for id, sprite in sprites do
			if not present[id] then
				local fading = (sprite.fading or 0) + dt
				sprite.fading = fading
				local alpha = math.clamp(fading / FADE, 0, 1)
				for _, box in sprite.parts do
					box.BackgroundTransparency = alpha
				end
				if alpha >= 1 then
					sprite.root:Destroy()
					sprites[id] = nil
				end
			end
		end
		local live: { [number]: boolean } = {}
		for _, o in view.objects do
			live[o.id] = true
			shot(o, scale)
		end
		for index, trap in view.traps or {} do
			local id = -10000 - index
			live[id] = true
			shot({ id = id, kind = "Trap", row = trap.row, x = trap.x, line = trap.line }, scale)
		end
		for id, box in shots do
			if not live[id] then
				box:Destroy()
				shots[id] = nil
			end
		end
		if hero and view.auraRadius then
			local radius = view.auraRadius * scale
			auraRing.Visible = true
			auraRing.Size = UDim2.fromOffset(radius * 2, 18 * scale)
			auraRing.Position = UDim2.fromOffset(
				(hero.x - cameraX) * scale - radius,
				(LOGICAL_HEIGHT - 150) * scale
			)
		else
			auraRing.Visible = false
		end
	end

	local function clear()
		for id, sprite in sprites do
			sprite.root:Destroy()
			sprites[id] = nil
		end
		for id, box in shots do
			box:Destroy()
			shots[id] = nil
		end
	end

	return {
		root = root,
		render = render,
		clear = clear,
		count = function(): number
			local n = 0
			for _ in sprites do
				n += 1
			end
			return n
		end,
		destroy = function()
			clear()
			root:Destroy()
		end,
	}
end

return table.freeze({ new = new })
