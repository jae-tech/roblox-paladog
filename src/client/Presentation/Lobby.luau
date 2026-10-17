--!strict
-- Lobby screens: records (3 slots), campaign stage select (5 chapters x 24), units, equipment/shop, skills,
-- achievements. Content is rebuilt only when the profile revision or the selection changes.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")
local HudLayout = require("./HudLayout")
local PlazaState = require("./PlazaState")
local ItemPreview = require("./ItemPreview")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Robux store (D-PAY-01): item index -> name, short description, owned-pass attribute
local ROBUX_ITEMS: { { item: number, name: string, desc: string, pass: string? } } = {
	{ item = 1, name = "보석 50", desc = "보석 50개" },
	{ item = 2, name = "보석 120", desc = "보석 120개" },
	{ item = 3, name = "보석 300", desc = "보석 300개" },
	{ item = 4, name = "보석 800", desc = "보석 800개" },
	{
		item = 5,
		name = "첫 구매 패키지",
		desc = "보석 100 + 골드 50,000 + 황금 무기 (1회)",
	},
	{
		item = 7,
		name = "골드·경험치 2배",
		desc = "전투 처치 골드·경험치 영구 2배",
		pass = "PassGoldExp",
	},
	{
		item = 8,
		name = "전투 2배속",
		desc = "전투 중 1x/2x 전환 버튼",
		pass = "PassSpeed",
	},
	{
		item = 9,
		name = "VIP",
		desc = "매일 보석 15개, 머리 위 VIP 표시",
		pass = "PassVip",
	},
}

export type Handlers = {
	lobby: (string, { [string]: any }?) -> (),
	start: (number) -> (),
	close: (() -> ())?,
	purchase: ((number) -> ())?, -- Robux store (D-PAY-01)
}

local NAV = {
	{ "Stages", "원정" },
	{ "Units", "용병" },
	{ "Equipment", "장비" },
	{ "Shop", "상점" },
	{ "Skills", "기술" },
	{ "Achievements", "업적" },
	{ "Heroes", "영웅" },
}

local function new(parent: Instance, catalog: any, handlers: Handlers)
	local root = Widgets.frame(parent, "Lobby", Theme.background)
	root.Size = UDim2.fromScale(1, 1)
	-- phones: shrink the 912x544 layout to the screen; the frame grows by 1/scale so it still fills it
	local scaler = Instance.new("UIScale")
	scaler.Parent = root
	if parent:IsA("GuiBase2d") then
		local screen = parent :: GuiBase2d
		local function fit()
			local size = screen.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				local scale = HudLayout.lobbyScale(size.X, size.Y)
				scaler.Scale = scale
				root.Size = UDim2.fromScale(1 / scale, 1 / scale)
			end
		end
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end
	root.ZIndex = 30
	-- the gradient multiplies BackgroundColor3, so the base colour is white
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	local backdrop = Instance.new("UIGradient")
	backdrop.Color = ColorSequence.new(Theme.backgroundTop, Theme.background)
	backdrop.Rotation = 90
	backdrop.Parent = root
	local header = Widgets.frame(root, "Header", Theme.panelDeep)
	header.Size = UDim2.new(1, 0, 0, 48)
	Widgets.sheen(header, 0.8)
	local headerLine = Widgets.frame(header, "Accent", Theme.gold)
	headerLine.Size = UDim2.new(1, 0, 0, 2)
	headerLine.Position = UDim2.new(0, 0, 1, -2)
	headerLine.BackgroundTransparency = 0.5
	local title = Widgets.label(header, "Title", "등불 원정", 24, Theme.gold)
	title.Font = Theme.fontHeavy
	title.Size = UDim2.new(0, 150, 1, 0)
	title.Position = UDim2.fromOffset(14, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextStrokeColor3, title.TextStrokeTransparency = Color3.fromRGB(90, 50, 10), 0.4
	-- currency / hero chips, then connection status in small text
	local chips = Widgets.frame(header, "Chips")
	chips.Size = UDim2.new(1, -300, 0, 28)
	chips.Position = UDim2.fromOffset(170, 10)
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips
	local function chip(name: string, color: Color3, order: number): (Frame, TextLabel)
		local back, text = Widgets.pill(chips, name, "", 14, Theme.panel, color)
		back.Size = UDim2.fromOffset(0, 26)
		back.AutomaticSize = Enum.AutomaticSize.X
		back.LayoutOrder = order
		Widgets.stroke(back, color, 1, 0.55)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		pad.Parent = back
		text.AutomaticSize = Enum.AutomaticSize.X
		text.Size = UDim2.fromScale(0, 1)
		return back, text
	end
	local _, statusChip = chip("Status", Theme.muted, 1)
	statusChip.Font = Theme.fontBody
	statusChip.TextSize = 12
	local heroBack, heroChip = chip("Hero", Theme.text, 2)
	local goldBack, goldChip = chip("Gold", Theme.gold, 3)
	local gemBack, gemChip = chip("Gems", Theme.gem, 4)
	-- R8: back to the plaza (the dungeon entrance reopens this menu)
	local close = Widgets.button(header, "ToPlaza", "광장으로", 14)
	close.Size = UDim2.fromOffset(110, 36)
	close.Position = UDim2.new(1, -120, 0, 6)
	close.Activated:Connect(function()
		if handlers.close then
			handlers.close()
		end
	end)
	local nav = Widgets.frame(root, "Nav", Theme.panelDeep)
	nav.BackgroundTransparency = 0.2
	nav.Size = UDim2.new(0, 132, 1, -56)
	nav.Position = UDim2.fromOffset(0, 52)
	-- visible tabs stack from the top (only "기록" shows before a record is chosen)
	local navLayout = Instance.new("UIListLayout")
	navLayout.Padding = UDim.new(0, 6)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navLayout.Parent = nav
	local navPad = Instance.new("UIPadding")
	navPad.PaddingTop = UDim.new(0, 6)
	navPad.Parent = nav
	local content = Widgets.frame(root, "Content")
	content.Size = UDim2.new(1, -148, 1, -60)
	content.Position = UDim2.fromOffset(140, 54)
	local toast, setToast = Widgets.toast(root, "Toast")
	toast.Size = UDim2.fromOffset(0, 28)
	toast.Position = UDim2.new(0.5, 66, 1, -36)
	toast.ZIndex = 35

	local ui: any = {
		screen = "Units",
		mode = "town", -- "dungeon": the entrance menu (expeditions only); "town": the plaza menu
		chapter = 1,
		stage = 1,
		tab = "Bag",
		item = nil,
	}
	local navButtons: { [string]: TextButton } = {}
	local dirty = true
	-- pass ownership and prices arrive as attributes; redraw when they change
	Players.LocalPlayer.AttributeChanged:Connect(function()
		dirty = true
	end)
	task.spawn(function()
		local store = ReplicatedStorage:WaitForChild("Store", 30)
		if store then
			store.AttributeChanged:Connect(function()
				dirty = true
			end)
			dirty = true
		end
	end)
	local lastKey = ""
	for index, entry in NAV do
		local b = Widgets.button(nav, entry[1], entry[2], 15)
		b.Size = UDim2.new(1, -12, 0, 44)
		b.LayoutOrder = index
		-- gold marker on the open tab
		local marker = Widgets.frame(b, "Marker", Theme.gold, 2)
		marker.Size = UDim2.new(0, 4, 1, -14)
		marker.Position = UDim2.fromOffset(4, 7)
		marker.Visible = false
		b.Activated:Connect(function()
			ui.screen, ui.item, dirty = entry[1], nil, true
		end)
		navButtons[entry[1]] = b
	end

	local function row(list: Instance, height: number, order: number): Frame
		local item = Widgets.card(list, "Row" .. order, Theme.panel, 10)
		item.Size = UDim2.new(1, -8, 0, height)
		item.LayoutOrder = order
		return item
	end
	-- money on hand decides whether a buy/upgrade button looks available
	local function affordColor(enough: boolean): Color3
		return if enough then Theme.button else Theme.locked
	end
	local function place(gui: GuiObject, x: number, y: number, w: number, h: number)
		gui.Position = UDim2.fromOffset(x, y)
		gui.Size = UDim2.fromOffset(w, h)
	end

	-- Heroes (D-DIFF-01: no record screen) ---------------------------------------------------------
	-- highest cleared stage and how many of the 120 are cleared on the slot's current difficulty
	local function progressOf(slot: any): (number, number)
		local best, count = 0, 0
		for index, star in slot.stars do
			if star >= 1 then
				count += 1
				best = math.max(best, index)
			end
		end
		return best, count
	end
	local function heroes(summary: any)
		local free = 0
		for index = 1, 3 do
			if summary.slots[index] == false and free == 0 then
				free = index
			end
		end
		for column, kind in { "light", "shadow" } do
			-- the hero's record: the current one, else its highest level
			local found, foundLevel = 0, -1
			for index = 1, 3 do
				local slot = summary.slots[index]
				if type(slot) == "table" and slot.heroKind == kind then
					local score = if index == summary.currentSlot then math.huge else slot.level
					if score > foundLevel then
						found, foundLevel = index, score
					end
				end
			end
			local slot = if found > 0 then summary.slots[found] else nil
			local current = found > 0 and found == summary.currentSlot
			local color = if kind == "shadow" then Color3.fromRGB(160, 110, 255) else Theme.gold
			local card = Widgets.card(content, "Hero" .. kind, Theme.panel, 14)
			place(card, (column - 1) * 378, 0, 368, 300)
			Widgets.outline(
				card,
				if current then color else Theme.stroke,
				if current then 2 else 1,
				0.2
			)
			local band = Widgets.frame(card, "Band", color, 12)
			band.Size = UDim2.new(1, -16, 0, 6)
			band.Position = UDim2.fromOffset(8, 8)
			local name = Widgets.label(card, "Name", catalog.heroNames[kind], 22, color)
			name.Font = Theme.fontHeavy
			place(name, 18, 24, 330, 32)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local locked = kind == "shadow" and not summary.darkUnlocked
			local lines: { string } = {}
			if slot then
				local best, count = progressOf(slot)
				local difficulty = catalog.text.difficulty[slot.difficulty + 1]
				table.insert(
					lines,
					string.format("Lv.%d · %sG", slot.level, Text.number(slot.gold))
				)
				table.insert(
					lines,
					string.format(
						"난이도 %s · 최고 %s",
						difficulty,
						if best > 0 then Text.stageLabel(best) else "-"
					)
				)
				table.insert(lines, string.format("스테이지 %d / 120 클리어", count))
				local nextDifficulty = catalog.text.difficulty[slot.difficulty + 2]
				table.insert(
					lines,
					if nextDifficulty
						then "모두 깨면 " .. nextDifficulty .. " 난이도로"
						else "최고 난이도"
				)
			elseif locked then
				table.insert(lines, "아직 잠겨 있습니다")
				table.insert(lines, "서바이벌 특별 이벤트나")
				table.insert(lines, "보석 상점에서 해금")
			else
				table.insert(lines, "새 원정을 쉬움 난이도로")
				table.insert(lines, "시작합니다")
			end
			for i, line in lines do
				local l = Widgets.label(
					card,
					"Line" .. i,
					line,
					15,
					if i == 1 then Theme.text else Theme.muted
				)
				l.Font = Theme.fontBody
				place(l, 18, 64 + (i - 1) * 26, 330, 24)
				l.TextXAlignment = Enum.TextXAlignment.Left
			end
			local label = if current
				then "함께하는 중"
				elseif slot then "이 영웅으로"
				elseif locked then "잠김"
				elseif free == 0 then "자리 없음"
				else "시작하기"
			local enabled = not current and not locked and (slot ~= nil or free > 0)
			local pick = Widgets.button(
				card,
				"Pick",
				label,
				17,
				if current then Theme.panelLight elseif enabled then Theme.gold else Theme.locked
			)
			if enabled then
				pick.TextColor3 = Theme.background
			end
			place(pick, 18, 232, 332, 52)
			pick.Activated:Connect(function()
				if not enabled then
					return
				end
				if slot then
					handlers.lobby("SelectSlot", { slot = found })
				else
					handlers.lobby("CreateSlot", { slot = free, heroKind = kind, difficulty = 0 })
				end
				ui.screen, dirty = if ui.mode == "dungeon" then "Stages" else "Units", true
			end)
		end
	end

	-- Stages ----------------------------------------------------------------------------------------
	-- Survival (stage 0): waves until the hero falls; opens with stage 12 cleared (D-UNLOCK-01).
	local function survivalPanel(slot: any)
		local open = slot.stars[12] >= 1
		local detail = Widgets.frame(content, "Survival", Theme.panel, 8)
		place(detail, 0, 42, 540, 200)
		local head = Widgets.label(
			detail,
			"Head",
			string.format("서바이벌 · 최고 웨이브 %d", slot.survivalBest),
			16,
			Theme.gold
		)
		place(head, 10, 6, 400, 24)
		head.TextXAlignment = Enum.TextXAlignment.Left
		local lines = {
			"끝없이 몰려오는 웨이브를 버티세요. 웨이브마다 적이 강해집니다.",
			"보스를 쓰러뜨리면 보석을 얻습니다. 쓰러지면 원정이 끝납니다.",
			if open
				then "난이도는 항상 보통입니다."
				else "1-12 스테이지를 클리어하면 열립니다.",
		}
		for i, text in lines do
			local line = Widgets.label(detail, "Line" .. i, text, 13)
			place(line, 10, 36 + (i - 1) * 24, 400, 22)
			line.TextXAlignment = Enum.TextXAlignment.Left
		end
		local go = Widgets.button(
			detail,
			"Start",
			if open then "출전" else "잠김",
			18,
			if open then Theme.gold else Theme.locked
		)
		go.TextColor3 = Theme.background
		place(go, 420, 60, 110, 70)
		go.Activated:Connect(function()
			if open then
				handlers.start(0)
			end
		end)
	end

	local function stages(slot: any)
		for c = 1, 6 do
			local b = Widgets.button(
				content,
				"Chapter" .. c,
				if c == 6 then "서바이벌" else c .. ". " .. catalog.chapters[c],
				13,
				if ui.chapter == c then Theme.buttonHot else Theme.button
			)
			place(b, (c - 1) * 128, 0, 122, 34)
			b.Activated:Connect(function()
				ui.chapter, dirty = c, true
			end)
		end
		if ui.chapter == 6 then
			survivalPanel(slot)
			return
		end
		local grid = Widgets.grid(content, "Grid", UDim2.fromOffset(84, 58), 6)
		place(grid, 0, 42, 540, 260)
		for i = 1, 24 do
			local stage = (ui.chapter - 1) * 24 + i
			local meta = Text.stageMeta(catalog, slot.heroKind, stage)
			local star = slot.stars[stage]
			local selected = stage == ui.stage and star >= 0
			local b = Widgets.button(
				grid,
				"Stage" .. stage,
				"",
				12,
				if star < 0
					then Theme.locked
					elseif selected then Theme.buttonHot
					elseif star > 0 then Theme.panelLight
					else Theme.button
			)
			local ink = if selected then Theme.ink elseif star < 0 then Theme.muted else Theme.text
			local number = Widgets.label(b, "Number", Text.stageLabel(stage), 15, ink)
			number.Font = Theme.fontHeavy
			number.Size = UDim2.new(1, 0, 0, 20)
			number.Position = UDim2.fromOffset(0, 5)
			local stars = Widgets.label(
				b,
				"Stars",
				if star < 0
					then "잠김"
					else string.rep("★", star) .. string.rep("☆", 3 - star),
				if star < 0 then 11 else 14,
				if selected then Theme.ink elseif star < 0 then Theme.muted else Theme.gold
			)
			stars.Size = UDim2.new(1, 0, 0, 16)
			stars.Position = UDim2.fromOffset(0, 24)
			local mode = Text.modeName(meta.mode)
			if mode ~= "" then
				local tag =
					Widgets.label(b, "Mode", mode, 10, if selected then Theme.ink else Theme.gem)
				tag.Size = UDim2.new(1, -4, 0, 14)
				tag.Position = UDim2.fromOffset(2, 41)
				Widgets.fit(tag, 10)
			end
			if selected then
				Widgets.outline(b, Theme.text, 2, 0)
			end
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if star >= 0 then
					ui.stage, dirty = stage, true
				end
			end)
		end
		-- D-DIFF-01: where this difficulty stands and what clearing it unlocks
		local _, cleared = progressOf(slot)
		local tier = Widgets.card(content, "Difficulty", Theme.panel, 12)
		place(tier, 552, 42, 208, 150)
		Widgets.outline(tier, Theme.gold, 1, 0.5)
		local tierHead = Widgets.label(tier, "Head", "현재 난이도", 13, Theme.muted)
		place(tierHead, 14, 10, 180, 18)
		tierHead.TextXAlignment = Enum.TextXAlignment.Left
		local tierName = Widgets.label(
			tier,
			"Name",
			catalog.text.difficulty[slot.difficulty + 1],
			26,
			Theme.gold
		)
		tierName.Font = Theme.fontHeavy
		place(tierName, 14, 28, 180, 32)
		tierName.TextXAlignment = Enum.TextXAlignment.Left
		local barBack, setBar = Widgets.bar(tier, "Progress", Theme.gold)
		place(barBack, 14, 70, 180, 10)
		setBar(cleared / 120)
		local count = Widgets.label(
			tier,
			"Count",
			string.format("%d / 120 클리어", cleared),
			13,
			Theme.text
		)
		place(count, 14, 84, 180, 20)
		count.TextXAlignment = Enum.TextXAlignment.Left
		local nextName = catalog.text.difficulty[slot.difficulty + 2]
		local hint = Widgets.label(
			tier,
			"Hint",
			if nextName
				then "모두 깨면 " .. nextName .. " 난이도로 넘어갑니다"
				else "최고 난이도입니다",
			12,
			Theme.muted
		)
		hint.TextWrapped = true
		place(hint, 14, 106, 180, 36)
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top
		local detail = Widgets.frame(content, "Detail", Theme.panel, 8)
		place(detail, 0, 310, 540, 150)
		local meta = Text.stageMeta(catalog, slot.heroKind, ui.stage)
		local headText = string.format("%s %s", Text.stageLabel(ui.stage), Text.modeName(meta.mode))
		if slot.bestSec[ui.stage] > 0 then
			headText ..= string.format(
				" · 최고 %d:%02d",
				slot.bestSec[ui.stage] // 60,
				slot.bestSec[ui.stage] % 60
			)
		end
		local head = Widgets.label(detail, "Head", headText, 16, Theme.gold)
		place(head, 10, 4, 380, 24)
		head.TextXAlignment = Enum.TextXAlignment.Left
		for i, quest in meta.quests do
			local line = Widgets.label(
				detail,
				"Quest" .. i,
				string.format(
					"%s %s  →  %s",
					if i == 1 then "주" else "부",
					Text.questText(catalog, slot.heroKind, quest),
					Text.questReward(catalog, quest)
				),
				13
			)
			place(line, 10, 30 + (i - 1) * 24, 400, 22)
			line.TextXAlignment = Enum.TextXAlignment.Left
		end
		local go = Widgets.button(detail, "Start", "출전", 18, Theme.gold)
		go.TextColor3 = Theme.background
		place(go, 420, 40, 110, 70)
		go.Activated:Connect(function()
			handlers.start(ui.stage)
		end)
	end

	-- Units -----------------------------------------------------------------------------------------
	local function unitsScreen(slot: any)
		local list = Widgets.list(content, "Units", 6)
		list.Size = UDim2.fromScale(1, 1)
		local rows = if slot.heroKind == "shadow" then catalog.totems else catalog.units
		local before = Text.UNIT_BEFORE[slot.heroKind] or Text.UNIT_BEFORE.light
		for n = 1, 9 do
			local r = rows[n]
			local level = slot.units[n]
			local card = row(list, 64, n)
			local name = Widgets.label(
				card,
				"Name",
				string.format("%s  Lv.%d", r.name, level),
				15,
				if level > 0 then Theme.text else Theme.muted
			)
			place(name, 10, 4, 260, 24)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local stats = if level > 0
				then string.format(
					"체력 %d · 공격 %d · 식량 %d · 대기 %d초",
					r.levels.hp[level],
					r.levels.ap[level],
					r.cost,
					r.cooldown
				)
				else string.format("식량 %d · 대기 %d초", r.cost, r.cooldown)
			local line = Widgets.label(card, "Stats", stats, 13, Theme.muted)
			place(line, 10, 30, 360, 22)
			line.TextXAlignment = Enum.TextXAlignment.Left
			local need = before[n]
			local blocked = level == 0 and need > 0 and slot.units[need] < 1
			local text = if level >= 20
				then "최대"
				elseif blocked then rows[need].name .. " 먼저"
				else string.format(
					"%s\n%sG",
					if level == 0 then "고용" else "강화",
					Text.number(r.levels.cost[level + 1])
				)
			local price = if level < 20 then r.levels.cost[level + 1] else 0
			local b = Widgets.button(
				card,
				"Upgrade",
				text,
				13,
				if level >= 20 or blocked or slot.gold < price then Theme.locked else Theme.gold
			)
			b.Position = UDim2.new(1, -130, 0, 6)
			b.Size = UDim2.fromOffset(120, 52)
			b.Activated:Connect(function()
				handlers.lobby("UpgradeUnit", { unit = n })
			end)
		end
	end

	-- Avatar preview: a copy of the player's real character with the gear the server put on it (D-GEAR-01).
	-- It refreshes when the server finishes re-dressing the character (GearKey attribute).
	local previewConn: RBXScriptConnection? = nil
	local itemSpin: RBXScriptConnection? = nil
	local itemShown: ItemPreview.Preview? = nil
	local function stopPreview()
		if previewConn then
			previewConn:Disconnect()
			previewConn = nil
		end
		if itemSpin then
			itemSpin:Disconnect()
			itemSpin = nil
		end
		if itemShown then
			itemShown.destroy()
			itemShown = nil
		end
	end
	local function avatarPreview(panel: Frame)
		stopPreview()
		local view = Instance.new("ViewportFrame")
		view.Name = "Avatar"
		view.Size = UDim2.new(1, -8, 1, -30)
		view.Position = UDim2.fromOffset(4, 4)
		view.BackgroundColor3 = Theme.panelDeep
		view.Ambient = Color3.fromRGB(160, 160, 170)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-0.5, -1, 0.6)
		Widgets.corner(view, 8)
		view.Parent = panel
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = view
		view.CurrentCamera = camera
		local world = Instance.new("WorldModel")
		world.Parent = view
		local caption = Widgets.label(panel, "Caption", "착용 모습", 13, Theme.muted)
		caption.Size = UDim2.new(1, 0, 0, 22)
		caption.Position = UDim2.new(0, 0, 1, -24)
		local function still(copy: Instance)
			for _, item in copy:GetDescendants() do
				if item:IsA("LuaSourceContainer") or item:IsA("ForceField") then
					item:Destroy()
				elseif item:IsA("BasePart") then
					item.Anchored = true
				end
			end
		end
		local function refresh()
			if not view.Parent then
				return
			end
			world:ClearAllChildren()
			local player = Players.LocalPlayer
			local character = player.Character
			local body = character and character:FindFirstChild("HumanoidRootPart")
			if not character or not body or not body:IsA("BasePart") then
				caption.Text = "캐릭터를 불러오는 중..."
				return
			end
			local archivable = character.Archivable
			character.Archivable = true
			local copy = character:Clone()
			character.Archivable = archivable
			if not copy then
				return
			end
			still(copy)
			copy.Parent = world
			local folder = Workspace:FindFirstChild("GearCompanions")
			local companion = folder and folder:FindFirstChild(tostring(player.UserId))
			if companion then
				local pet = companion:Clone()
				still(pet)
				pet.Parent = world
			end
			caption.Text = if companion then "착용 모습 · 탈것 동행" else "착용 모습"
			local focus = body.CFrame
			local side = if companion then 1.8 else 0
			local target = (focus * CFrame.new(side, 0.3, 0)).Position
			local eye = (focus * CFrame.new(side + 3, 1.2, if companion then -17 else -12.5)).Position
			camera.CFrame = CFrame.lookAt(eye, target)
		end
		refresh()
		local character = Players.LocalPlayer.Character
		if character then
			previewConn = character:GetAttributeChangedSignal("GearKey"):Connect(function()
				-- let the replicated gear parts arrive before copying
				task.delay(0.25, refresh)
			end)
		end
	end

	-- Equipment / shop ------------------------------------------------------------------------------------
	-- Item look and numbers (D-GEAR-01): the 3D piece turning in a viewport, what it does now, what the
	-- next enchant gives, and (in the shop) what the same kind of equipped item does.
	local CATEGORY_NAMES = {
		light = { "무기", "반지", "투구", "갑옷", "탈것" },
		shadow = { "검", "부적", "투구", "갑옷", "신발" },
	}
	local function categoryName(kind: string, category: number): string
		return CATEGORY_NAMES[kind][((category - 1) % 5) + 1] or "?"
	end
	local function itemView(
		panel: Instance,
		code: number,
		x: number,
		y: number,
		w: number,
		h: number
	)
		local frame = Widgets.card(panel, "ItemLook", Theme.panelDeep, 10)
		place(frame, x, y, w, h)
		local view = Instance.new("ViewportFrame")
		view.Name = "View"
		view.Size = UDim2.new(1, -8, 1, -8)
		view.Position = UDim2.fromOffset(4, 4)
		view.BackgroundTransparency = 1
		view.Ambient = Color3.fromRGB(170, 170, 185)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-0.4, -1, -0.6)
		view.Parent = frame
		local grade = code % 1000
		if grade > 0 then
			local badge, _ = Widgets.pill(frame, "Grade", "+" .. grade, 13, Theme.gold, Theme.ink)
			badge.Size = UDim2.fromOffset(44, 22)
			badge.Position = UDim2.new(1, -52, 0, 8)
		end
		if itemSpin then
			itemSpin:Disconnect()
		end
		if itemShown then
			itemShown.destroy()
		end
		local shown = ItemPreview.show(view, code)
		itemShown = shown
		itemSpin = RunService.RenderStepped:Connect(function(dt)
			shown.step(dt)
		end)
	end
	-- name, kind, effect and enchant lines for an item; returns the next free y
	local function itemLines(
		panel: Instance,
		kind: string,
		code: number,
		x: number,
		y: number,
		w: number
	): number
		local category = code // 100000
		local name = Widgets.label(panel, "Name", Text.itemName(catalog, code), 17, Theme.gold)
		name.Font = Theme.fontHeavy
		place(name, x, y, w, 24)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local kindText = Widgets.label(panel, "Kind", categoryName(kind, category), 12, Theme.muted)
		place(kindText, x, y + 24, w, 18)
		kindText.TextXAlignment = Enum.TextXAlignment.Left
		local effect =
			Widgets.label(panel, "Effect", Text.itemDescription(catalog, code), 14, Theme.text)
		effect.Font = Theme.fontBody
		effect.TextWrapped = true
		place(effect, x, y + 44, w, 36)
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.TextYAlignment = Enum.TextYAlignment.Top
		local nextY = y + 82
		if Text.canEnchant(code) then
			local upgrade = Widgets.label(
				panel,
				"Next",
				"다음 강화(+"
					.. (code % 1000 + 1)
					.. "): "
					.. Text.itemDescription(catalog, code + 1),
				12,
				Theme.good
			)
			upgrade.Font = Theme.fontBody
			upgrade.TextWrapped = true
			place(upgrade, x, nextY, w, 32)
			upgrade.TextXAlignment = Enum.TextXAlignment.Left
			upgrade.TextYAlignment = Enum.TextYAlignment.Top
			nextY += 34
		end
		return nextY
	end
	-- the equipped item of the same category (first matching slot), for comparison in the shop
	local function equippedOfCategory(slot: any, category: number): number
		for i = 1, 9 do
			local code = slot.equip[i]
			if code ~= 0 and code // 100000 == category then
				return code
			end
		end
		return 0
	end

	-- Equipment: equipped slots, the bag, the avatar wearing it, and the selected item
	local function equipment(slot: any, summary: any)
		local kind = slot.heroKind
		local eq = Widgets.grid(content, "Equipped", UDim2.fromOffset(118, 54), 6)
		place(eq, 0, 0, 380, 190)
		for i = 1, 9 do
			local code = slot.equip[i]
			local locked = i == 6 and not summary.ringSlotUnlocked
			local text = Text.slotName(kind, i)
				.. "\n"
				.. (
					if locked
						then "잠김"
						elseif code ~= 0 then Text.itemName(catalog, code)
						else "-"
				)
			local b = Widgets.button(
				eq,
				"Slot" .. i,
				text,
				12,
				if ui.item == "equip:" .. i
					then Theme.buttonHot
					elseif locked or code == 0 then Theme.panelDeep
					else Theme.button
			)
			if locked or code == 0 then
				b.TextColor3 = Theme.muted
			end
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if code ~= 0 then
					ui.item, dirty = "equip:" .. i, true
				end
			end)
		end
		local bagHead = Widgets.label(
			content,
			"BagHead",
			string.format("가방 %d / 100", #slot.inventory),
			14,
			Theme.muted
		)
		place(bagHead, 0, 196, 380, 22)
		bagHead.TextXAlignment = Enum.TextXAlignment.Left
		local bag = Widgets.grid(content, "Bag", UDim2.fromOffset(186, 40), 6)
		place(bag, 0, 220, 380, 250)
		if #slot.inventory == 0 then
			local none = Widgets.label(
				bag,
				"Empty",
				"가방이 비었습니다. 상점에서 장비를 사 보세요.",
				13,
				Theme.muted
			)
			none.Size = UDim2.fromOffset(370, 40)
		end
		for index, code in slot.inventory do
			local b = Widgets.button(
				bag,
				"Item" .. index,
				Text.itemName(catalog, code),
				13,
				if ui.item == "inv:" .. index then Theme.buttonHot else Theme.panelLight
			)
			b.LayoutOrder = index
			b.Activated:Connect(function()
				ui.item, dirty = "inv:" .. index, true
			end)
		end
		local preview = Widgets.card(content, "Preview", Theme.panel, 10)
		place(preview, 390, 0, 168, 230)
		avatarPreview(preview)
		-- selected item: look, numbers and actions
		local detail = Widgets.card(content, "ItemDetail", Theme.panel, 10)
		place(detail, 390, 238, 372, 232)
		local where, index = nil, nil
		if ui.item then
			where, index = string.match(ui.item, "^(%a+):(%d+)$")
		end
		local idx = tonumber(index)
		local code = if where == "equip" and idx
			then slot.equip[idx]
			elseif where == "inv" and idx then slot.inventory[idx]
			else nil
		if code and code ~= 0 and idx then
			itemView(content, code, 566, 0, 196, 230)
			local y = itemLines(detail, kind, code, 12, 8, 348)
			local x = 12
			local function action(label: string, color: Color3?, fn: () -> ())
				local b = Widgets.button(detail, label, label, 13, color)
				place(b, x, math.max(y + 4, 176), 110, 44)
				b.Activated:Connect(fn)
				x += 116
			end
			if where == "inv" then
				action("장착", Theme.gold, function()
					local category = code // 100000
					local targets = {}
					for slotIndex = 1, 9 do
						local wanted = ({ 1, 1, 1, 2, 2, 2, 3, 4, 5 })[slotIndex]
							+ (if kind == "shadow" then 5 else 0)
						if
							wanted == category
							and not (slotIndex == 6 and not summary.ringSlotUnlocked)
						then
							table.insert(targets, slotIndex)
						end
					end
					local target = targets[1]
					for _, t in targets do
						if slot.equip[t] == 0 then
							target = t
							break
						end
					end
					if target then
						handlers.lobby("Equip", { index = idx, slot = target })
						ui.item = nil
					end
				end)
				action(
					string.format("판매 %sG", Text.number(Text.saleValue(catalog, code))),
					nil,
					function()
						handlers.lobby("SellItem", { index = idx })
						ui.item = nil
					end
				)
			else
				action("해제", nil, function()
					handlers.lobby("Unequip", { slot = idx })
					ui.item = nil
				end)
			end
			if Text.canEnchant(code) then
				action(
					string.format("강화 (보석 %d)", Text.enchantCost(code)),
					affordColor(summary.gems >= Text.enchantCost(code)),
					function()
						handlers.lobby("Enchant", { where = where, index = idx })
					end
				)
			end
		else
			local empty = Widgets.card(content, "ItemLook", Theme.panelDeep, 10)
			place(empty, 566, 0, 196, 230)
			local pick = Widgets.label(
				empty,
				"Pick",
				"아이템을 고르면\n모습이 보입니다",
				13,
				Theme.muted
			)
			pick.Size = UDim2.fromScale(1, 1)
			local hint = Widgets.label(
				detail,
				"Hint",
				string.format("장비 강화 상한: +%d", slot.gradeLimit or 5),
				14,
				Theme.muted
			)
			place(hint, 12, 10, 348, 24)
			hint.TextXAlignment = Enum.TextXAlignment.Left
			local tip = Widgets.label(
				detail,
				"Tip",
				"장비 칸이나 가방의 아이템을 누르면 모습과 능력치를 보고 장착·판매·강화할 수 있습니다. 새 장비는 상점에서 삽니다.",
				13,
				Theme.muted
			)
			tip.TextWrapped = true
			place(tip, 12, 40, 348, 60)
			tip.TextXAlignment = Enum.TextXAlignment.Left
			tip.TextYAlignment = Enum.TextYAlignment.Top
			tip.Font = Theme.fontBody
		end
	end

	-- Shop: categories, items with price, and the selected item's look, numbers and comparison
	local GEM_SHOP = { { 1, 1000 }, { 2, 1000 }, { 3, 1 }, { 9, 1000 } }
	local function shop(slot: any, summary: any)
		local kind = slot.heroKind
		local base = if kind == "shadow" then 5 else 0
		ui.shopCategory = ui.shopCategory or 1
		for c = 1, 6 do
			local label = if c == 6 then "보석 상점" else categoryName(kind, base + c)
			local b = Widgets.button(
				content,
				"Category" .. c,
				label,
				14,
				if ui.shopCategory == c then Theme.buttonHot else Theme.button
			)
			place(b, (c - 1) * 127, 0, 121, 34)
			b.Activated:Connect(function()
				ui.shopCategory, ui.item, dirty = c, nil, true
			end)
		end
		local list = Widgets.list(content, "List", 4)
		place(list, 0, 42, 380, 428)
		local detail = Widgets.card(content, "ItemDetail", Theme.panel, 10)
		place(detail, 390, 250, 372, 220)
		if ui.shopCategory == 6 then
			for order, entry in GEM_SHOP do
				local b = Widgets.button(
					list,
					"Gem" .. entry[1],
					string.format(
						"%s  ·  보석 %d",
						catalog.text.gemShop[tostring(entry[1])],
						entry[2]
					),
					14,
					affordColor(summary.gems >= entry[2])
				)
				b.Size = UDim2.new(1, -8, 0, 44)
				b.LayoutOrder = order
				b.Activated:Connect(function()
					handlers.lobby("GemShop", { item = entry[1] })
				end)
			end
			-- Robux: gem packs, the one-time pack and game passes (D-PAY-01)
			local robuxHeader = Widgets.label(list, "RobuxHeader", "Robux 상점", 15, Theme.gold)
			robuxHeader.Font = Theme.fontHeavy
			robuxHeader.Size = UDim2.new(1, -8, 0, 30)
			robuxHeader.LayoutOrder = 100
			local store = ReplicatedStorage:FindFirstChild("Store")
			for order, entry in ROBUX_ITEMS do
				local price = if store then store:GetAttribute("Price" .. entry.item) else nil
				local ready = type(price) == "number" and price > 0
				local owned = entry.pass ~= nil
					and Players.LocalPlayer:GetAttribute(entry.pass) == true
				local done = owned or (entry.item == 5 and summary.starterBought == true)
				local tag = if done
					then (if owned then "보유 중" else "구매 완료")
					elseif ready then string.format("R$ %d", price :: number)
					else "준비 중"
				local b = Widgets.button(
					list,
					"Robux" .. entry.item,
					string.format("%s  ·  %s\n%s", entry.name, tag, entry.desc),
					13,
					if ready and not done then Theme.gold else Theme.locked
				)
				b.Size = UDim2.new(1, -8, 0, 52)
				b.LayoutOrder = 100 + order
				b.Activated:Connect(function()
					if ready and not done and handlers.purchase then
						handlers.purchase(entry.item)
					end
				end)
			end
			local look = Widgets.card(content, "ItemLook", Theme.panelDeep, 10)
			place(look, 390, 42, 372, 200)
			local gems =
				Widgets.label(look, "Gems", "◆ " .. Text.number(summary.gems), 30, Theme.gem)
			gems.Font = Theme.fontHeavy
			gems.Size = UDim2.fromScale(1, 1)
			local tip = Widgets.label(
				detail,
				"Tip",
				"보석은 업적과 서바이벌에서 얻거나 아래 Robux 상점에서 삽니다. 반지 3번 칸, 골드, 황금 무기, 기술 초기화, 부활에 씁니다.",
				13,
				Theme.muted
			)
			tip.TextWrapped = true
			place(tip, 12, 12, 348, 80)
			tip.TextXAlignment = Enum.TextXAlignment.Left
			tip.TextYAlignment = Enum.TextYAlignment.Top
			return
		end
		local category = base + ui.shopCategory
		local count = ({ 11, 10, 10, 5, 5, 11, 10, 10, 5, 5 })[category]
		local order = 0
		for num = 1, count do
			local price, currency = Text.buyPrice(catalog, category, num)
			if price then
				order += 1
				local code = Text.encode(category, num, 0)
				local enough = if currency == "gold"
					then slot.gold >= price
					else summary.gems >= price
				local selected = ui.item == "shop:" .. code
				local card = Widgets.button(
					list,
					"Buy" .. code,
					"",
					12,
					if selected then Theme.buttonHot else Theme.panelLight
				)
				card.Size = UDim2.new(1, -8, 0, 52)
				card.LayoutOrder = order
				local ink = if selected then Theme.ink else Theme.text
				local name = Widgets.label(card, "Name", Text.itemName(catalog, code), 14, ink)
				place(name, 10, 4, 240, 22)
				name.TextXAlignment = Enum.TextXAlignment.Left
				local effect = Widgets.label(
					card,
					"Effect",
					Text.itemDescription(catalog, code),
					11,
					if selected then Theme.ink else Theme.muted
				)
				effect.Font = Theme.fontBody
				place(effect, 10, 26, 250, 20)
				effect.TextXAlignment = Enum.TextXAlignment.Left
				effect.TextTruncate = Enum.TextTruncate.AtEnd
				local cost = Widgets.label(
					card,
					"Price",
					Text.number(price) .. (if currency == "gold" then " G" else " ◆"),
					14,
					if selected
						then Theme.ink
						elseif not enough then Theme.bad
						elseif currency == "gold" then Theme.gold
						else Theme.gem
				)
				place(cost, 262, 0, 98, 52)
				cost.TextXAlignment = Enum.TextXAlignment.Right
				card.Activated:Connect(function()
					ui.item, dirty = "shop:" .. code, true
				end)
			end
		end
		local chosen = if ui.item then tonumber(string.match(ui.item, "^shop:(%d+)$")) else nil
		if chosen and chosen // 100000 == category then
			itemView(content, chosen, 390, 42, 372, 200)
			local y = itemLines(detail, kind, chosen, 12, 8, 348)
			local worn = equippedOfCategory(slot, category)
			local compare = Widgets.label(
				detail,
				"Compare",
				if worn ~= 0
					then "지금 장착: "
						.. Text.itemName(catalog, worn)
						.. " — "
						.. Text.itemDescription(catalog, worn)
					else "지금 장착한 같은 종류 장비가 없습니다",
				12,
				Theme.muted
			)
			compare.Font = Theme.fontBody
			compare.TextWrapped = true
			place(compare, 12, y, 348, 32)
			compare.TextXAlignment = Enum.TextXAlignment.Left
			compare.TextYAlignment = Enum.TextYAlignment.Top
			local _, num = Text.decode(chosen)
			local price, currency = Text.buyPrice(catalog, category, num)
			local enough = price ~= nil
				and (if currency == "gold" then slot.gold >= price else summary.gems >= price)
			local buy = Widgets.button(
				detail,
				"Buy",
				if price
					then string.format(
						"구매  %s%s",
						Text.number(price),
						if currency == "gold" then " G" else " ◆"
					)
					else "-",
				15,
				if enough then Theme.gold else Theme.locked
			)
			if enough then
				buy.TextColor3 = Theme.background
			end
			place(buy, 12, 166, 348, 44)
			buy.Activated:Connect(function()
				if enough then
					handlers.lobby("BuyItem", { category = category, num = num })
				end
			end)
		else
			local look = Widgets.card(content, "ItemLook", Theme.panelDeep, 10)
			place(look, 390, 42, 372, 200)
			local pick = Widgets.label(
				look,
				"Pick",
				"왼쪽에서 아이템을 고르면\n모습과 능력치가 보입니다",
				14,
				Theme.muted
			)
			pick.Size = UDim2.fromScale(1, 1)
			local money = Widgets.label(
				detail,
				"Money",
				string.format(
					"보유  %s G   ◆ %s",
					Text.number(slot.gold),
					Text.number(summary.gems)
				),
				15,
				Theme.gold
			)
			place(money, 12, 12, 348, 24)
			money.TextXAlignment = Enum.TextXAlignment.Left
			local tip = Widgets.label(
				detail,
				"Tip",
				"무기·반지는 골드, 투구·갑옷·탈것은 보석으로 삽니다. 산 장비는 장비 화면의 가방에 들어갑니다.",
				13,
				Theme.muted
			)
			tip.TextWrapped = true
			place(tip, 12, 44, 348, 60)
			tip.TextXAlignment = Enum.TextXAlignment.Left
			tip.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	-- Skills ----------------------------------------------------------------------------------------
	local function skills(slot: any)
		local head = Widgets.label(
			content,
			"Points",
			string.format("남은 기술 포인트 %d", slot.freePoints),
			16,
			Theme.gold
		)
		place(head, 0, 0, 300, 28)
		head.TextXAlignment = Enum.TextXAlignment.Left
		local reset = Widgets.button(content, "Reset", "초기화 (보석 1000)", 13)
		place(reset, 400, 0, 160, 30)
		reset.Activated:Connect(function()
			handlers.lobby("ResetSkills", nil)
		end)
		local list = Widgets.list(content, "Skills", 4)
		place(list, 0, 36, 640, 380)
		local names = catalog.skillNames[slot.heroKind]
		local maxes = catalog.skillMax[slot.heroKind]
		for i, name in names do
			local card = row(list, 40, i)
			local label = Widgets.label(
				card,
				"Name",
				string.format("%s  %d/%d", name, slot.skills[i], maxes[i]),
				14
			)
			place(label, 8, 0, 200, 40)
			label.TextXAlignment = Enum.TextXAlignment.Left
			local desc = Widgets.label(
				card,
				"Desc",
				Text.skillDescription(catalog, slot.heroKind, i),
				12,
				Theme.muted
			)
			place(desc, 210, 0, 300, 40)
			desc.TextXAlignment = Enum.TextXAlignment.Left
			if slot.freePoints > 0 and slot.skills[i] < maxes[i] then
				local learn = Widgets.button(card, "Learn", "+", 18, Theme.gold)
				place(learn, 560, 4, 40, 32)
				learn.Activated:Connect(function()
					handlers.lobby("LearnSkill", { skill = i })
				end)
			end
		end
	end

	-- Achievements ----------------------------------------------------------------------------------
	local function achievements(summary: any)
		local list = Widgets.list(content, "Achievements", 4)
		list.Size = UDim2.fromScale(1, 1)
		local order = 0
		local function add(code: number, name: string, desc: string, gems: number)
			order += 1
			local done = table.find(summary.achievements, code) ~= nil
			local card = row(list, 40, order)
			local label = Widgets.label(
				card,
				"Name",
				(if done then "✓ " else "") .. name,
				14,
				if done then Theme.good else Theme.text
			)
			place(label, 8, 0, 200, 40)
			label.TextXAlignment = Enum.TextXAlignment.Left
			local d = Widgets.label(
				card,
				"Desc",
				desc .. string.format("  ·  보석 %d", gems),
				12,
				Theme.muted
			)
			place(d, 210, 0, 380, 40)
			d.TextXAlignment = Enum.TextXAlignment.Left
		end
		for _, code in { 0, 1, 2 } do
			local e = catalog.text.achievements[tostring(code)]
			add(code, e.name, e.desc, e.gems)
		end
		for k = 1, 10 do
			add(
				2 + k,
				catalog.bosses[k] .. " 토벌",
				string.format("%s 보스 스테이지 승리", Text.stageLabel(k * 12)),
				({ 10, 10, 10, 10, 15, 15, 15, 15, 20, 30 })[k]
			)
		end
		for _, code in { 13, 15 } do
			local e = catalog.text.achievements[tostring(code)]
			add(code, e.name, e.desc, e.gems)
		end
		for code, n in
			{
				[16] = 1,
				[17] = 2,
				[18] = 3,
				[19] = 4,
				[20] = 6,
				[21] = 5,
				[22] = 7,
				[23] = 8,
				[24] = 9,
			}
		do
			add(code, catalog.units[n].name .. " 달인", "Lv.20 달성", 10)
		end
		for _, code in { 25, 26, 27, 28, 39 } do
			local e = catalog.text.achievements[tostring(code)]
			add(code, e.name, e.desc, e.gems)
		end
	end

	local function rebuild(model: any)
		stopPreview()
		Widgets.clear(content)
		local summary = model.summary
		if not summary then
			local waiting =
				Widgets.label(content, "Waiting", "서버에 연결하는 중...", 18, Theme.muted)
			waiting.Size = UDim2.fromScale(1, 1)
			return
		end
		local slot = model.slot
		-- without a record only "기록" works; keep the chosen tab so creating a record lands on it
		local screen = PlazaState.landing(ui.mode, slot ~= nil, ui.screen)
		local allowed = PlazaState.tabs(ui.mode, slot ~= nil)
		title.Text = if ui.mode == "dungeon" then "던전 입구" else "광장 메뉴"
		for name, b in navButtons do
			local open = name == screen
			b.BackgroundColor3 = if open then Theme.panelLight else Theme.button
			b.TextColor3 = if open then Theme.gold else Theme.text
			local marker = b:FindFirstChild("Marker")
			if marker and marker:IsA("GuiObject") then
				marker.Visible = open
			end
			b.Visible = table.find(allowed, name) ~= nil
		end
		if screen == "Heroes" then
			heroes(summary)
		elseif screen == "Stages" then
			stages(slot)
		elseif screen == "Units" then
			unitsScreen(slot)
		elseif screen == "Equipment" then
			equipment(slot, summary)
		elseif screen == "Shop" then
			shop(slot, summary)
		elseif screen == "Skills" then
			skills(slot)
		elseif screen == "Achievements" then
			achievements(summary)
		end
	end

	local function update(model: any)
		local visible = if model.menuVisible ~= nil
			then model.menuVisible
			else model.phase == "LobbyReady"
				or model.phase == "Preparing"
				or model.phase == "ProfileLoading"
				or model.phase == "Unavailable"
		root.Visible = visible
		local summary = model.summary
		local slot = model.slot
		statusChip.Text = string.format("● %s · %s", model.storage or "", model.network or "")
		statusChip.TextColor3 = if model.network == "연결됨" then Theme.good else Theme.bad
		gemChip.Text = if summary then "◆ " .. Text.number(summary.gems) else ""
		gemBack.Visible = summary ~= nil
		goldChip.Text = if slot then Text.number(slot.gold) .. " G" else ""
		goldBack.Visible = slot ~= nil
		heroChip.Text = if slot
			then string.format("%s  Lv.%d", catalog.heroNames[slot.heroKind], slot.level)
			else ""
		heroBack.Visible = slot ~= nil
		setToast(
			if model.phase == "Unavailable"
				then Text.reason(model.reason or "StorageUnavailable")
				else Text.reason(model.reason)
		)
		if not visible then
			return
		end
		local key = string.format(
			"%s|%s|%s|%d|%d|%s|%s|%s",
			tostring(model.profileRevision),
			ui.mode,
			ui.screen,
			ui.chapter,
			ui.stage,
			ui.tab,
			tostring(ui.item),
			tostring(model.summary ~= nil)
		)
		if dirty or key ~= lastKey then
			dirty, lastKey = false, key
			rebuild(model)
		end
	end

	return {
		root = root,
		update = update,
		-- which menu opens: the dungeon entrance or a plaza menu button (with its tab)
		open = function(mode: string, screen: string?)
			ui.mode, ui.item, dirty = mode, nil, true
			ui.screen = screen or (if mode == "dungeon" then "Stages" else "Units")
		end,
		inspect = function(): any
			return {
				screen = ui.screen,
				mode = ui.mode,
				chapter = ui.chapter,
				stage = ui.stage,
				tab = ui.tab,
			}
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return table.freeze({ new = new })
