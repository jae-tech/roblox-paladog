--!strict
-- Client-only 3D dungeon and army. Models never decide movement, hits, costs or rewards.
-- Figures and chapter maps come from shared FigureLook (D-FIG-01); limbs are posed every frame and all
-- parts move in one BulkMoveTo.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FigureLook = require(ReplicatedStorage.Shared.FigureLook)
local Views = require("./ViewDefinitions")
local Widgets = require("./Widgets")

local SCALE = 0.12
local DYING_SECONDS = 0.45
local ATTACK_SECONDS = 0.42
local NAMED = { Hero = true, Boss = true, Runner = true, Castle = true, Wagon = true, Horse = true }

type Figure = {
	model: Model,
	root: Part,
	parts: { BasePart },
	locals: { CFrame },
	groups: { string? },
	pivots: { Vector3? },
	baseTransp: { number },
	flying: boolean,
	frog: { BasePart }?,
	frogLocals: { CFrame }?,
	ice: Part?,
	look: string,
	fill: Frame?,
	bar: Frame?,
	label: TextLabel?,
	lastX: number,
	lastZ: number,
	lastHp: number,
	walk: number,
	state: string?,
	actStart: number,
	hitAt: number,
	cf: CFrame,
}
type Dying = { figure: Figure, at: number }

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function material(name: string?): Enum.Material
	if name then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and value then
			return value
		end
	end
	return Enum.Material.SmoothPlastic
end

local function vec(v: { number }, k: number): Vector3
	return Vector3.new(v[1] * k, v[2] * k, v[3] * k)
end

-- one FigureLook part at its local frame (scaled); the caller positions it
local function makePart(parent: Instance, spec: FigureLook.Part, k: number): (BasePart, CFrame)
	local size = vec(spec.size, k)
	local turn = CFrame.identity
	local p: BasePart
	if spec.shape == "Wedge" then
		p = Instance.new("WedgePart")
		p.Size = size
	elseif spec.shape == "Ball" then
		p = Instance.new("Part")
		p.Size = size
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif spec.shape == "Cyl" or spec.shape == "VCyl" or spec.shape == "ZCyl" then
		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		if spec.shape == "VCyl" then
			cylinder.Size = Vector3.new(size.Y, size.X, size.Z)
			turn = CFrame.Angles(0, 0, math.rad(90))
		elseif spec.shape == "ZCyl" then
			cylinder.Size = Vector3.new(size.Z, size.Y, size.X)
			turn = CFrame.Angles(0, math.rad(90), 0)
		else
			cylinder.Size = size
		end
		p = cylinder
	else
		p = Instance.new("Part")
		p.Size = size
	end
	p.Name = spec.shape
	p.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	p.Material = if spec.neon then Enum.Material.Neon else material(spec.mat)
	p.Transparency = spec.transp or 0
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if spec.light then
		local light = Instance.new("PointLight")
		light.Color = p.Color
		light.Range = spec.light[1] * math.max(k, 1)
		light.Brightness = spec.light[2]
		light.Shadows = false
		light.Parent = p
	end
	local rot = spec.rot
	local cf = CFrame.new(vec(spec.at, k))
		* (if rot
			then CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
			else CFrame.identity)
		* turn
	p.CFrame = cf
	p.Parent = parent
	return p, cf
end

local function specOf(e: any, view: any): any
	if e.kind == "Hero" then
		return if view.mode == "Jump"
			then Views.totems[3]
			elseif view.heroKind == "shadow" then Views.shadow
			else Views.hero
	end
	if e.kind == "Unit" then
		return Views.units[e.n] or Views.units[1]
	end
	if e.kind == "Totem" then
		return Views.totems[e.n] or Views.totems[1]
	end
	if e.kind == "Enemy" then
		return Views.enemies[e.n] or Views.enemies[1]
	end
	if e.kind == "Boss" or e.kind == "Runner" then
		return Views.bosses[e.n] or Views.shadow
	end
	return Views.castle
end

local function lookOf(e: any, view: any): (string, number?, string?)
	if e.kind == "Hero" and view.mode == "Jump" then
		return "Totem", 3, nil
	end
	return e.kind, e.n, view.heroKind
end

local LIGHTING_KEYS =
	{ "Ambient", "OutdoorAmbient", "ClockTime", "FogColor", "FogStart", "FogEnd", "Brightness" }

local function rgb(v: { number }): Color3
	return Color3.fromRGB(v[1], v[2], v[3])
end

local function new(parent: Instance, catalog: any)
	local root = Widgets.frame(parent, "Field3D")
	root.Size = UDim2.fromScale(1, 1)
	local folder: Folder? = nil
	local mapLength = 0
	local mapChapter = 0
	local mapOrigin = Vector3.zero
	local figures: { [number]: Figure } = {}
	local dying: { Dying } = {}
	local shots: { [number]: Part } = {}
	local aura: Part? = nil
	local saved: any = nil
	local savedLighting: { [string]: any }? = nil
	local savedAtmosphere: { [string]: any }? = nil
	local cameraPosition: Vector3? = nil
	local lastHero: Vector3? = nil

	local function restoreCamera()
		if saved then
			local c = saved.camera :: Camera
			if c.Parent then
				c.CameraType = saved.kind
				c.CameraSubject = saved.subject
				c.FieldOfView = saved.fov
				c.CFrame = saved.cf
				c.Focus = saved.focus
			end
		end
		saved, cameraPosition, lastHero = nil, nil, nil
	end

	local function restoreLighting()
		if savedLighting then
			for key, value in savedLighting do
				(Lighting :: any)[key] = value
			end
			savedLighting = nil
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if savedAtmosphere and atmosphere then
			for key, value in savedAtmosphere do
				(atmosphere :: any)[key] = value
			end
		end
		savedAtmosphere = nil
	end

	-- chapter mood on this client only; the plaza look comes back when the battle view closes
	local function applyLighting(look: FigureLook.Lighting)
		if not savedLighting then
			local keep = {}
			for _, key in LIGHTING_KEYS do
				keep[key] = (Lighting :: any)[key]
			end
			savedLighting = keep
		end
		Lighting.Ambient = rgb(look.ambient)
		Lighting.OutdoorAmbient = rgb(look.outdoor)
		Lighting.ClockTime = look.clock
		Lighting.FogColor = rgb(look.fog)
		Lighting.FogStart = look.fogStart
		Lighting.FogEnd = look.fogEnd
		Lighting.Brightness = look.brightness
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			if not savedAtmosphere then
				savedAtmosphere = {
					Density = atmosphere.Density,
					Color = atmosphere.Color,
					Decay = atmosphere.Decay,
					Haze = atmosphere.Haze,
				}
			end
			atmosphere.Density = 0.22
			atmosphere.Color = rgb(look.fog)
			atmosphere.Decay = rgb(look.fog):Lerp(Color3.new(), 0.4)
			atmosphere.Haze = 1
		end
	end

	local function clear()
		if folder then
			folder:Destroy()
			folder = nil
		end
		table.clear(figures)
		table.clear(dying)
		table.clear(shots)
		aura = nil
		mapLength, mapChapter = 0, 0
		restoreCamera()
		restoreLighting()
	end

	local function makeMap(length: number, origin: Vector3, chapter: number)
		local arena = Instance.new("Folder")
		arena.Name = "LanternExpedition3D"
		arena:SetAttribute("ClientVisualOnly", true)
		arena:SetAttribute("PresentationId", Views.world3d.presentationId)
		folder = arena
		mapLength, mapChapter = length, chapter
		local look = FigureLook.map(chapter, -120 * SCALE, (length + 40) * SCALE)
		arena:SetAttribute("Theme", look.name)
		local scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = arena
		for _, spec in look.parts do
			makePart(scenery, spec, 1)
		end
		applyLighting(look.lighting)
		-- R8: the dungeon is drawn at the player's arena slot, over the server's collision floor
		mapOrigin = origin
		if origin ~= Vector3.zero then
			for _, d in arena:GetDescendants() do
				if d:IsA("BasePart") then
					d.CFrame += origin
				end
			end
		end
		arena.Parent = Workspace
	end

	local function entityName(e: any, view: any): string
		if e.kind == "Hero" then
			return "나 · " .. (catalog.heroNames[view.heroKind] or "원정대")
		end
		if e.kind == "Unit" then
			return catalog.units[e.n].name
		end
		if e.kind == "Totem" then
			return catalog.totems[e.n].name
		end
		if e.kind == "Castle" then
			return "던전 관문"
		end
		if e.kind == "Wagon" then
			return "보급 수레"
		end
		if e.kind == "Horse" then
			return "공성 목마"
		end
		if e.kind == "Boss" then
			return "보스"
		end
		return if e.team == 1 then "아군" else "적"
	end

	local function build(e: any, view: any, chapter: number): Figure
		local v = specOf(e, view)
		local kind, n, heroKind = lookOf(e, view)
		local look = FigureLook.figure(kind, n, heroKind, chapter)
		local grow = if e.giant then 1.3 elseif e.enhanced then 1.12 else 1
		local k = look.scale * grow
		local m = Instance.new("Model")
		m.Name = "Entity_" .. e.id
		m:SetAttribute("EntityId", e.id)
		m:SetAttribute("Kind", e.kind)
		m:SetAttribute("Team", e.team)
		m:SetAttribute("PresentationId", v.presentationId)
		m:SetAttribute("Figure", look.id)
		local pivot = part(m, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), v.body)
		pivot.Transparency = 1
		m.PrimaryPart = pivot
		local parts: { BasePart } = {}
		local locals: { CFrame } = {}
		local groups: { string? } = {}
		local pivots: { Vector3? } = {}
		local baseTransp: { number } = {}
		local function add(spec: FigureLook.Part, scale: number)
			local p, cf = makePart(m, spec, scale)
			table.insert(parts, p)
			table.insert(locals, cf)
			table.insert(baseTransp, p.Transparency)
			groups[#parts] = spec.g
			pivots[#parts] = if spec.pv then vec(spec.pv, scale) else nil
		end
		for _, spec in look.parts do
			add(spec, k)
		end
		if e.enhanced then
			add({
				shape = "VCyl",
				size = { 2.4, 0.05, 2.4 },
				at = { 0, 0.04, 0 },
				color = { 220, 40, 70 },
				neon = true,
				transp = 0.35,
			}, k / look.scale)
		end
		local tall = look.height * grow
		local tag = Instance.new("BillboardGui")
		tag.Name = "Health"
		tag.Size =
			UDim2.fromOffset(if NAMED[e.kind] then 120 else 64, if NAMED[e.kind] then 30 else 8)
		tag.StudsOffset = Vector3.new(0, tall + 0.6, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 95
		tag.Adornee = pivot
		tag.Parent = pivot
		local label: TextLabel? = nil
		if NAMED[e.kind] then
			local named = Widgets.label(
				tag,
				"Name",
				entityName(e, view),
				12,
				if e.kind == "Hero"
					then Color3.fromRGB(255, 225, 95)
					else Color3.fromRGB(235, 235, 245)
			)
			named.Size = UDim2.new(1, 0, 0, 18)
			named.TextStrokeTransparency = 0.3
			label = named
		end
		local bar = Widgets.frame(tag, "Hp", Color3.fromRGB(30, 30, 40), 2)
		bar.Size = UDim2.new(1, 0, 0, 5)
		bar.Position = UDim2.fromOffset(0, if label then 21 else 1)
		bar.Visible = NAMED[e.kind] == true
		local fill = Widgets.frame(
			bar,
			"Fill",
			if e.team == 1 then Color3.fromRGB(90, 218, 110) else Color3.fromRGB(238, 83, 95),
			2
		)
		m.Parent = folder
		return {
			model = m,
			root = pivot,
			parts = parts,
			locals = locals,
			groups = groups,
			pivots = pivots,
			baseTransp = baseTransp,
			flying = look.flying,
			frog = nil,
			frogLocals = nil,
			ice = nil,
			look = "normal",
			fill = fill,
			bar = bar,
			label = label,
			lastX = e.x,
			lastZ = e.z or 0,
			lastHp = e.hp,
			walk = 0,
			state = e.state,
			actStart = -math.huge,
			hitAt = -math.huge,
			cf = CFrame.new(),
		}
	end

	-- curse/ghost/ice change how the whole figure looks, only on a change of state
	local function setLook(figure: Figure, look: string)
		if figure.look == look then
			return
		end
		figure.look = look
		for i, p in figure.parts do
			p.Transparency = if look == "frog"
				then 1
				elseif look == "ghost" then math.max(figure.baseTransp[i], 0.7)
				else figure.baseTransp[i]
		end
		if look == "frog" and not figure.frog then
			local frogParts: { BasePart } = {}
			local frogLocals: { CFrame } = {}
			for _, spec in FigureLook.figure("Frog").parts do
				local p, cf = makePart(figure.model, spec, 1)
				table.insert(frogParts, p)
				table.insert(frogLocals, cf)
			end
			figure.frog, figure.frogLocals = frogParts, frogLocals
		end
		local frog = figure.frog
		if frog then
			for _, p in frog do
				p.Transparency = if look == "frog" then 0 else 1
			end
		end
		if look == "ice" and not figure.ice then
			local height = figure.root:FindFirstChild("Health") :: BillboardGui?
			local tall = if height then height.StudsOffset.Y else 3
			local shell = part(
				figure.model,
				"Ice",
				Vector3.new(2.4, tall, 2.4),
				CFrame.new(),
				Color3.fromRGB(170, 225, 255),
				Enum.Material.Ice
			)
			figure.ice = shell
		end
		if figure.ice then
			figure.ice.Transparency = if look == "ice" then 0.45 else 1
		end
	end

	local function render(view: any, chapter: number, dt: number)
		if not view then
			return
		end
		local length = if view.mode == "Jump" then view.heroMaxX else 1100
		-- R8 avatar combat: the server put the real character in an arena; it is the hero on screen
		local arenaOrigin = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("ArenaOrigin")
		local origin = if typeof(arenaOrigin) == "Vector3" then arenaOrigin else Vector3.zero
		local avatarHero = origin ~= Vector3.zero
		if not folder or mapLength ~= length or mapOrigin ~= origin or mapChapter ~= chapter then
			clear()
			makeMap(length, origin, chapter)
		end
		local now = os.clock()
		local moveParts: { BasePart } = {}
		local moveFrames: { CFrame } = {}
		local live: { [number]: boolean } = {}
		local hero: any = nil
		for _, e in view.entities do
			live[e.id] = true
			if e.kind == "Hero" then
				hero = e
				if avatarHero then
					live[e.id] = nil -- the player's own character stands here instead of a figure
					continue
				end
			end
			local figure = figures[e.id]
			if not figure then
				figure = build(e, view, chapter)
				figures[e.id] = figure
			end
			local z = if view.spatial
				then e.z or 0
				elseif e.line and e.line > 0 then (e.line - 3) * 40
				else (e.y - 165) * 1.4
			local moving = math.abs(e.x - figure.lastX) + math.abs(z - figure.lastZ) > 0.05
			if moving then
				figure.walk += dt * 10
			else
				figure.walk = math.round(figure.walk / math.pi) * math.pi -- feet together at rest
			end
			if e.state ~= figure.state then
				if e.state == "Attack" or e.state == "Skill" then
					figure.actStart = now
				end
				figure.state = e.state
			end
			if e.hp < figure.lastHp then
				figure.hitAt = now
			end
			figure.lastHp = e.hp
			setLook(
				figure,
				if e.frog
					then "frog"
					elseif e.state == "Ghost" or e.state == "Blink" then "ghost"
					elseif e.state == "Ice" then "ice"
					else "normal"
			)
			local y = if view.mode == "Jump" then math.max(0, (e.y - 165) * SCALE) else 0
			local pos = origin + Vector3.new(e.x * SCALE, y, z * SCALE)
			local base = CFrame.lookAt(pos, pos + Vector3.new(e.dir or 1, 0, 0))
			table.insert(moveParts, figure.root)
			table.insert(moveFrames, base)
			local lift = if moving then math.abs(math.sin(figure.walk)) * 0.12 else 0
			if figure.flying then
				lift = 0.7 + math.sin(now * 2.2 + e.id) * 0.25
			end
			local act = math.clamp((now - figure.actStart) / ATTACK_SECONDS, 0, 1)
			local pose = FigureLook.pose(e.state, figure.walk, act, now + e.id * 0.37)
			if now - figure.hitAt < 0.12 then
				pose.body += 9
			end
			local body = base * CFrame.new(0, lift, 0) * CFrame.Angles(math.rad(pose.body), 0, 0)
			figure.cf = body
			if figure.look == "frog" then
				local frog, frogLocals = figure.frog, figure.frogLocals
				if frog and frogLocals then
					for i, p in frog do
						table.insert(moveParts, p)
						table.insert(moveFrames, base * frogLocals[i])
					end
				end
			else
				for i, p in figure.parts do
					local cf = figure.locals[i]
					local group = figure.groups[i]
					local joint = figure.pivots[i]
					if group and joint then
						local angle = math.rad(pose[group] or 0)
						local axis = FigureLook.AXIS[group]
						local turn = if axis == "Y"
							then CFrame.Angles(0, angle, 0)
							elseif axis == "Z" then CFrame.Angles(0, 0, angle)
							else CFrame.Angles(angle, 0, 0)
						cf = CFrame.new(joint) * turn * CFrame.new(-joint) * cf
					end
					table.insert(moveParts, p)
					table.insert(moveFrames, body * cf)
				end
			end
			if figure.ice and figure.look == "ice" then
				table.insert(moveParts, figure.ice)
				table.insert(moveFrames, base * CFrame.new(0, figure.ice.Size.Y / 2, 0))
			end
			figure.root:SetAttribute("Hp", e.hp)
			local damaged = e.hp < e.maxHp
			if figure.bar then
				figure.bar.Visible = damaged or NAMED[e.kind] == true
			end
			if figure.fill then
				figure.fill.Size = UDim2.fromScale(math.clamp(e.hp / e.maxHp, 0, 1), 1)
			end
			if figure.label then
				figure.label.TextColor3 = if e.transformed
					then Color3.fromRGB(225, 120, 255)
					elseif e.kind == "Hero" then Color3.fromRGB(255, 225, 95)
					else Color3.fromRGB(235, 235, 245)
			end
			figure.lastX, figure.lastZ = e.x, z
		end
		for id, f in figures do
			if not live[id] then
				figures[id] = nil
				local tag = f.root:FindFirstChild("Health")
				if tag then
					tag:Destroy()
				end
				table.insert(dying, { figure = f, at = now })
			end
		end
		-- the fallen topple and sink, then disappear
		for i = #dying, 1, -1 do
			local d = dying[i]
			local t = (now - d.at) / DYING_SECONDS
			if t >= 1 then
				d.figure.model:Destroy()
				table.remove(dying, i)
			else
				local f = d.figure
				local fall = f.cf
					* CFrame.new(0, -t * 1.4, 0)
					* CFrame.Angles(math.rad(t * 70), 0, 0)
				for j, p in f.parts do
					p.Transparency = f.baseTransp[j] + (1 - f.baseTransp[j]) * t
					table.insert(moveParts, p)
					table.insert(moveFrames, fall * f.locals[j])
				end
			end
		end
		if #moveParts > 0 then
			Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local seen: { [number]: boolean } = {}
		local function draw(o: any)
			seen[o.id] = true
			local shot = shots[o.id]
			if not shot then
				local spec = Views.objects[o.row]
				local color = if o.kind == "Coin"
					then Color3.fromRGB(255, 217, 57)
					elseif o.kind == "Spike" then Color3.fromRGB(235, 65, 85)
					elseif spec then spec.color
					else Color3.fromRGB(86, 193, 255)
				local created = part(
					folder :: Folder,
					"Spell_" .. o.id,
					if o.kind == "Spike"
						then Vector3.new(3, 0.6, 3)
						else Vector3.new(0.65, 0.65, 0.65),
					CFrame.new(),
					color,
					Enum.Material.Neon
				)
				if o.kind ~= "Spike" then
					created.Shape = Enum.PartType.Ball
				end
				shot = created
				shots[o.id] = created
			end
			local y = if o.kind == "Trap" then 0.2 else 1.9
			if o.kind == "Lob" then
				y += math.sin(math.pi * (o.t or 0)) * 4
			elseif o.kind == "Drop" then
				y += (1 - (o.t or 0)) * 5
			end
			shot.Position = origin + Vector3.new(o.x * SCALE, y, (o.z or 0) * SCALE)
		end
		for _, o in view.objects do
			draw(o)
		end
		for i, t in view.traps or {} do
			draw({ id = -i, row = t.row, x = t.x, z = t.z, kind = "Trap" })
		end
		for id, p in shots do
			if not seen[id] then
				p:Destroy()
				shots[id] = nil
			end
		end
		if hero then
			local focus = Vector3.new(hero.x * SCALE, 1.8, (hero.z or 0) * SCALE)
			local camera = Workspace.CurrentCamera
			if avatarHero then
				restoreCamera() -- the Roblox camera follows the real character
			elseif camera then
				if not saved or saved.camera ~= camera then
					restoreCamera()
					saved = {
						camera = camera,
						kind = camera.CameraType,
						subject = camera.CameraSubject,
						fov = camera.FieldOfView,
						cf = camera.CFrame,
						focus = camera.Focus,
					}
				end
				local desired = focus + Vector3.new(-22, 14, 0)
				local prior = cameraPosition
				cameraPosition = if prior
						and lastHero
						and (focus - lastHero).Magnitude < 10
					then prior:Lerp(desired, math.min(1, dt * 10))
					else desired
				camera.CameraType = Enum.CameraType.Scriptable
				camera.FieldOfView = 65
				camera.CFrame =
					CFrame.lookAt(cameraPosition :: Vector3, focus + Vector3.new(9, 0, 0))
				camera.Focus = CFrame.new(focus)
				lastHero = focus
			end
			if view.auraRadius then
				if not aura then
					local created = part(
						folder :: Folder,
						"Aura",
						Vector3.one,
						CFrame.new(),
						Color3.fromRGB(237, 194, 74),
						Enum.Material.Neon
					)
					created.Shape = Enum.PartType.Cylinder
					created.Transparency = 0.9
					aura = created
				end
				local ring = aura :: Part
				local diameter = view.auraRadius * SCALE * 2
				ring.Size = Vector3.new(0.04, diameter, diameter)
				ring.CFrame = CFrame.new(
					origin + Vector3.new(hero.x * SCALE, 0.04, (hero.z or 0) * SCALE)
				) * CFrame.Angles(0, 0, math.pi / 2)
			elseif aura then
				aura:Destroy()
				aura = nil
			end
		end
	end

	return {
		root = root,
		render = render,
		clear = clear,
		count = function(): number
			local n = 0
			for _ in figures do
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

return table.freeze({ new = new, SCALE = SCALE })
