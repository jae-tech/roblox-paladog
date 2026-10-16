--!strict
-- Client-only 3D dungeon and army. Models never decide movement, hits, costs or rewards.
local Workspace = game:GetService("Workspace")
local Views = require("./ViewDefinitions")
local Widgets = require("./Widgets")

local SCALE = 0.12
type Figure = {
	model: Model,
	root: Part,
	fill: Frame?,
	label: TextLabel?,
	lastX: number,
	lastZ: number,
}

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
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
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

local function new(parent: Instance, catalog: any)
	local root = Widgets.frame(parent, "Field3D")
	root.Size = UDim2.fromScale(1, 1)
	local folder: Folder? = nil
	local mapLength = 0
	local figures: { [number]: Figure } = {}
	local shots: { [number]: Part } = {}
	local aura: Part? = nil
	local saved: any = nil
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

	local function clear()
		if folder then
			folder:Destroy()
			folder = nil
		end
		table.clear(figures)
		table.clear(shots)
		aura = nil
		mapLength = 0
		restoreCamera()
	end

	local function makeMap(length: number)
		local arena = Instance.new("Folder")
		arena.Name = "LanternExpedition3D"
		arena:SetAttribute("ClientVisualOnly", true)
		arena:SetAttribute("PresentationId", Views.world3d.presentationId)
		folder = arena
		mapLength = length
		local stone = Color3.fromRGB(48, 54, 67)
		local width = 27
		local extent = (length + 160) * SCALE
		part(
			arena,
			"DungeonFloor",
			Vector3.new(extent, 1, width),
			CFrame.new((length - 80) * SCALE / 2, -0.5, 0),
			stone,
			Enum.Material.Slate
		)
		for _, side in { -1, 1 } do
			part(
				arena,
				"DungeonWall",
				Vector3.new(extent, 4, 0.8),
				CFrame.new((length - 80) * SCALE / 2, 2, side * (width / 2)),
				Color3.fromRGB(35, 39, 50),
				Enum.Material.Slate
			)
			for x = 0, math.min(length, 1200), 128 do
				part(
					arena,
					"Pillar",
					Vector3.new(1.4, 6, 1.4),
					CFrame.new(x * SCALE, 3, side * 12.5),
					Color3.fromRGB(72, 76, 88),
					Enum.Material.Cobblestone
				)
				local flame = part(
					arena,
					"Lantern",
					Vector3.new(0.55, 1, 0.55),
					CFrame.new(x * SCALE, 4.2, side * 11.6),
					Color3.fromRGB(255, 173, 67),
					Enum.Material.Neon
				)
				local light = Instance.new("PointLight")
				light.Color = flame.Color
				light.Range = 14
				light.Brightness = 1.3
				light.Parent = flame
			end
		end
		for x = 0, math.min(length, 1200), 96 do
			part(
				arena,
				"FloorSeam",
				Vector3.new(0.15, 0.02, width - 1),
				CFrame.new(x * SCALE, 0.01, 0),
				Color3.fromRGB(78, 84, 95),
				Enum.Material.Slate
			)
		end
		part(
			arena,
			"EntryPortal",
			Vector3.new(0.2, 4, 4),
			CFrame.new(0, 2, 0),
			Color3.fromRGB(68, 180, 238),
			Enum.Material.Neon
		).Transparency =
			0.5
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

	local function build(e: any, view: any): Figure
		local v = specOf(e, view)
		local m = Instance.new("Model")
		m.Name = "Entity_" .. e.id
		m:SetAttribute("EntityId", e.id)
		m:SetAttribute("Kind", e.kind)
		m:SetAttribute("Team", e.team)
		m:SetAttribute("PresentationId", v.presentationId)
		local pivot = part(m, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), v.body)
		pivot.Transparency = 1
		m.PrimaryPart = pivot
		local tall = 1
		if e.kind == "Castle" then
			tall = 7
			for _, z in { -3, 3 } do
				part(
					m,
					"GateTower",
					Vector3.new(2, 7, 2),
					CFrame.new(z, 3.5, 0),
					Color3.fromRGB(80, 68, 100),
					Enum.Material.Slate
				)
			end
			part(
				m,
				"Arch",
				Vector3.new(8, 1.5, 2.2),
				CFrame.new(0, 6, 0),
				v.body,
				Enum.Material.Slate
			)
			part(
				m,
				"Gate",
				Vector3.new(4, 4.5, 0.4),
				CFrame.new(0, 2.25, 0),
				Color3.fromRGB(182, 68, 120),
				Enum.Material.Neon
			)
		elseif e.kind == "Wagon" or e.kind == "Horse" then
			tall = 3
			part(
				m,
				"Hull",
				Vector3.new(3, 2, 5),
				CFrame.new(0, 2, 0),
				Color3.fromRGB(115, 77, 51),
				Enum.Material.WoodPlanks
			)
			for _, x in { -1.5, 1.5 } do
				for _, z in { -1.7, 1.7 } do
					local wheel = part(
						m,
						"Wheel",
						Vector3.new(0.5, 1.3, 1.3),
						CFrame.new(x, 0.7, z),
						Color3.fromRGB(37, 32, 29)
					)
					wheel.Shape = Enum.PartType.Cylinder
				end
			end
		else
			local size = if e.kind == "Boss"
				then 1.6
				elseif e.giant then 1.3
				elseif e.kind == "Totem" then 0.8
				else 1
			tall = 4.2 * size
			local function limb(name: string, sz: Vector3, at: Vector3, c: Color3): Part
				return part(m, name, sz * size, CFrame.new(at * size), c)
			end
			limb("Torso", Vector3.new(1.5, 1.6, 0.9), Vector3.new(0, 2.1, 0), v.body)
			limb("Head", Vector3.new(1.25, 1.1, 1), Vector3.new(0, 3.45, 0), v.accent)
			for _, side in { -1, 1 } do
				limb(
					"Leg",
					Vector3.new(0.55, 1.3, 0.6),
					Vector3.new(side * 0.45, 0.65, 0),
					Color3.fromRGB(35, 37, 47)
				)
				limb("Arm", Vector3.new(0.42, 1.3, 0.5), Vector3.new(side, 2.1, 0), v.body)
				limb(
					"Eye",
					Vector3.new(0.15, 0.15, 0.06),
					Vector3.new(side * 0.25, 3.55, -0.52),
					Color3.new(1, 1, 1)
				)
			end
			if e.kind == "Hero" then
				limb(
					"Staff",
					Vector3.new(0.18, 3.7, 0.18),
					Vector3.new(1.15, 2, -0.45),
					Color3.fromRGB(164, 107, 60)
				)
				local orb = limb(
					"Magic",
					Vector3.new(0.65, 0.65, 0.65),
					Vector3.new(1.15, 4, -0.45),
					if view.heroKind == "shadow"
						then Color3.fromRGB(185, 105, 255)
						else Color3.fromRGB(90, 201, 255)
				)
				orb.Material = Enum.Material.Neon
				orb.Shape = Enum.PartType.Ball
			elseif e.n == 2 or e.n == 8 then
				limb(
					"RangedWeapon",
					Vector3.new(0.22, 2.5, 0.3),
					Vector3.new(1.15, 2.4, -0.5),
					v.accent
				)
			elseif e.n == 6 then
				limb("Shield", Vector3.new(2.2, 2.4, 0.5), Vector3.new(0, 2, -0.9), v.accent)
			else
				limb("Weapon", Vector3.new(0.2, 2.1, 0.4), Vector3.new(1.1, 2.6, -0.55), v.accent)
			end
		end
		local tag = Instance.new("BillboardGui")
		tag.Name = "Health"
		tag.Size = UDim2.fromOffset(110, 32)
		tag.StudsOffset = Vector3.new(0, tall + 0.5, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 95
		tag.Adornee = pivot
		tag.Parent = pivot
		local label = Widgets.label(
			tag,
			"Name",
			entityName(e, view),
			12,
			if e.kind == "Hero" then Color3.fromRGB(255, 225, 95) else Color3.fromRGB(235, 235, 245)
		)
		label.Size = UDim2.new(1, 0, 0, 18)
		label.TextStrokeTransparency = 0.3
		local bar = Widgets.frame(tag, "Hp", Color3.fromRGB(30, 30, 40), 2)
		bar.Size = UDim2.new(1, 0, 0, 5)
		bar.Position = UDim2.fromOffset(0, 21)
		local fill = Widgets.frame(
			bar,
			"Fill",
			if e.team == 1 then Color3.fromRGB(90, 218, 110) else Color3.fromRGB(238, 83, 95),
			2
		)
		m.Parent = folder
		return { model = m, root = pivot, fill = fill, label = label, lastX = e.x, lastZ = e.z or 0 }
	end

	local function render(view: any, _chapter: number, dt: number)
		if not view then
			return
		end
		local length = if view.mode == "Jump" then view.heroMaxX else 1100
		if not folder or mapLength ~= length then
			clear()
			makeMap(length)
		end
		local live: { [number]: boolean } = {}
		local hero: any = nil
		for _, e in view.entities do
			live[e.id] = true
			if e.kind == "Hero" then
				hero = e
			end
			local figure = figures[e.id]
			if not figure then
				figure = build(e, view)
				figures[e.id] = figure
			end
			local z = if view.spatial
				then e.z or 0
				elseif e.line and e.line > 0 then (e.line - 3) * 40
				else (e.y - 165) * 1.4
			local moving = math.abs(e.x - figure.lastX) + math.abs(z - figure.lastZ) > 0.05
			local y = if view.mode == "Jump" then math.max(0, (e.y - 165) * SCALE) else 0
			if moving then
				y += math.sin(os.clock() * 10 + e.id) * 0.07
			end
			local pos = Vector3.new(e.x * SCALE, y, z * SCALE)
			figure.model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(e.dir or 1, 0, 0)))
			figure.root:SetAttribute("Hp", e.hp)
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
				f.model:Destroy()
				figures[id] = nil
			end
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
			shot.Position = Vector3.new(o.x * SCALE, y, (o.z or 0) * SCALE)
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
			if camera then
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
				ring.CFrame = CFrame.new(hero.x * SCALE, 0.04, (hero.z or 0) * SCALE)
					* CFrame.Angles(0, 0, math.pi / 2)
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
