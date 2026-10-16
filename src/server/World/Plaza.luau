--!strict
-- Shared plaza (R8, D-PLAZA-01): a large code-built square where every player's Roblox avatar meets, with
-- a server leaderboard board and the dungeon entrance (a ProximityPrompt that opens the expedition menu
-- on that client). Battles stay client-rendered far from here, so the plaza never overlaps a battlefield.
local PlazaBoard = require("./PlazaBoard")

local CENTER = Vector3.new(0, 0, -500)
local SIZE = 240
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
	l.Parent = parent
	return l
end

local function new(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "Plaza"
	root:SetAttribute("PresentationId", PRESENTATION_ID)
	local stone = Color3.fromRGB(150, 145, 135)
	local floor = part(
		root,
		"Floor",
		Vector3.new(SIZE, 2, SIZE),
		CFrame.new(CENTER - Vector3.new(0, 1, 0)),
		stone
	)
	floor.Material = Enum.Material.Cobblestone
	for i, offset in { Vector3.new(SIZE / 2, 0, 0), Vector3.new(-SIZE / 2, 0, 0) } do
		part(
			root,
			"WallX" .. i,
			Vector3.new(2, 6, SIZE),
			CFrame.new(CENTER + offset + Vector3.new(0, 3, 0)),
			stone
		)
	end
	for i, offset in { Vector3.new(0, 0, SIZE / 2), Vector3.new(0, 0, -SIZE / 2) } do
		part(
			root,
			"WallZ" .. i,
			Vector3.new(SIZE, 6, 2),
			CFrame.new(CENTER + offset + Vector3.new(0, 3, 0)),
			stone
		)
	end
	-- fountain and lantern ring
	local fountain = part(
		root,
		"Fountain",
		Vector3.new(4, 24, 24),
		CFrame.new(CENTER + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 125, 135)
	)
	fountain.Shape = Enum.PartType.Cylinder
	local water = part(
		root,
		"Water",
		Vector3.new(1, 20, 20),
		CFrame.new(CENTER + Vector3.new(0, 4.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 150, 220)
	)
	water.Shape = Enum.PartType.Cylinder
	water.Material = Enum.Material.Glass
	water.Transparency = 0.3
	for i = 1, 8 do
		local angle = (i - 1) / 8 * math.pi * 2
		local at = CENTER + Vector3.new(math.cos(angle) * 60, 0, math.sin(angle) * 60)
		part(
			root,
			"Post" .. i,
			Vector3.new(1.2, 10, 1.2),
			CFrame.new(at + Vector3.new(0, 5, 0)),
			Color3.fromRGB(60, 55, 50)
		)
		local lamp = part(
			root,
			"Lamp" .. i,
			Vector3.new(2, 2, 2),
			CFrame.new(at + Vector3.new(0, 11, 0)),
			Color3.fromRGB(255, 205, 90)
		)
		lamp.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Range, light.Brightness, light.Color = 18, 1.5, Color3.fromRGB(255, 205, 120)
		light.Parent = lamp
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 50))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(110, 105, 95)
	spawn.Parent = root

	-- dungeon entrance on the far side, facing the spawn
	local gateAt = CENTER + Vector3.new(0, 0, -SIZE / 2 + 12)
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

	-- leaderboard board on the left side, facing the centre
	local boardAt = CENTER + Vector3.new(-SIZE / 2 + 8, 9, 0)
	local board = part(
		root,
		"Leaderboard",
		Vector3.new(1, 16, 26),
		CFrame.new(boardAt),
		Color3.fromRGB(35, 38, 52)
	)
	part(
		root,
		"BoardStand",
		Vector3.new(2, 2, 28),
		CFrame.new(boardAt - Vector3.new(0, 9, 0)),
		dark
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(26, 29, 44)
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
		{ name = "순위", x = 0.02, w = 0.1 },
		{ name = "이름", x = 0.12, w = 0.36 },
		{ name = "스테이지", x = 0.48, w = 0.18 },
		{ name = "서바이벌", x = 0.66, w = 0.18 },
		{ name = "레벨", x = 0.84, w = 0.14 },
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
				cells[3].Text = PlazaBoard.stageLabel(row.stage)
				cells[4].Text = if row.wave > 0 then "W" .. row.wave else "-"
				cells[5].Text = "Lv." .. row.level
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
