--!strict
-- Lobby screens: records (3 slots), campaign stage select (5 chapters x 24), units, equipment/shop, skills,
-- achievements. Content is rebuilt only when the profile revision or the selection changes.
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")
local HudLayout = require("./HudLayout")

export type Handlers = {
	lobby: (string, { [string]: any }?) -> (),
	start: (number) -> (),
	close: (() -> ())?,
}

local NAV = {
	{ "Stages", "원정" },
	{ "Units", "용병" },
	{ "Equipment", "장비·상점" },
	{ "Skills", "기술" },
	{ "Achievements", "업적" },
	{ "Records", "기록" },
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
	local header = Widgets.frame(root, "Header", Theme.panel)
	header.Size = UDim2.new(1, 0, 0, 48)
	local title = Widgets.label(header, "Title", "등불 원정", 22, Theme.gold)
	title.Size = UDim2.new(0, 160, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local info = Widgets.label(header, "Info", "", 14)
	info.Size = UDim2.new(1, -320, 1, 0)
	info.Position = UDim2.fromOffset(180, 0)
	-- R8: back to the plaza (the dungeon entrance reopens this menu)
	local close = Widgets.button(header, "ToPlaza", "광장으로", 14)
	close.Size = UDim2.fromOffset(110, 36)
	close.Position = UDim2.new(1, -120, 0, 6)
	close.Activated:Connect(function()
		if handlers.close then
			handlers.close()
		end
	end)
	info.TextXAlignment = Enum.TextXAlignment.Right
	local nav = Widgets.frame(root, "Nav", Theme.panel)
	nav.Size = UDim2.new(0, 132, 1, -56)
	nav.Position = UDim2.fromOffset(0, 52)
	local content = Widgets.frame(root, "Content")
	content.Size = UDim2.new(1, -148, 1, -60)
	content.Position = UDim2.fromOffset(140, 54)
	local toast = Widgets.label(root, "Toast", "", 15, Theme.gold)
	toast.Size = UDim2.new(1, -140, 0, 22)
	toast.Position = UDim2.new(0, 140, 1, -26)
	toast.ZIndex = 35

	local ui: any = {
		screen = "Records",
		chapter = 1,
		stage = 1,
		tab = "Bag",
		item = nil,
		hero = "light",
		difficulty = 1,
		confirmDelete = 0,
	}
	local navButtons: { [string]: TextButton } = {}
	local dirty = true
	local lastKey = ""
	for index, entry in NAV do
		local b = Widgets.button(nav, entry[1], entry[2], 15)
		b.Size = UDim2.new(1, -12, 0, 44)
		b.Position = UDim2.fromOffset(6, 6 + (index - 1) * 50)
		b.Activated:Connect(function()
			ui.screen, ui.item, dirty = entry[1], nil, true
		end)
		navButtons[entry[1]] = b
	end

	local function row(list: Instance, height: number, order: number): Frame
		local item = Widgets.frame(list, "Row" .. order, Theme.panel, 8)
		item.Size = UDim2.new(1, -8, 0, height)
		item.LayoutOrder = order
		return item
	end
	local function place(gui: GuiObject, x: number, y: number, w: number, h: number)
		gui.Position = UDim2.fromOffset(x, y)
		gui.Size = UDim2.fromOffset(w, h)
	end

	-- Records ---------------------------------------------------------------------------------------
	local function records(summary: any)
		local list = Widgets.list(content, "Records", 8)
		list.Size = UDim2.fromScale(1, 1)
		for index = 1, 3 do
			local slot = summary.slots[index]
			local card = row(list, 120, index)
			local head = Widgets.label(
				card,
				"Head",
				"",
				17,
				if index == summary.currentSlot then Theme.gold else Theme.text
			)
			place(head, 12, 6, 400, 26)
			head.TextXAlignment = Enum.TextXAlignment.Left
			if type(slot) == "table" then
				local stars = 0
				for _, star in slot.stars do
					stars += math.max(star, 0)
				end
				head.Text = string.format(
					"기록 %d · %s · %s",
					index,
					catalog.heroNames[slot.heroKind],
					catalog.text.difficulty[slot.difficulty + 1]
				)
				local body = Widgets.label(
					card,
					"Body",
					string.format(
						"Lv.%d · %sG · 별 %d",
						slot.level,
						Text.number(slot.gold),
						stars
					),
					14,
					Theme.muted
				)
				place(body, 12, 34, 400, 22)
				body.TextXAlignment = Enum.TextXAlignment.Left
				local pick = Widgets.button(
					card,
					"Select",
					if index == summary.currentSlot then "선택됨" else "이 기록으로",
					15
				)
				place(pick, 12, 66, 150, 44)
				pick.Activated:Connect(function()
					handlers.lobby("SelectSlot", { slot = index })
					ui.screen, dirty = "Stages", true
				end)
				local delete = Widgets.button(
					card,
					"Delete",
					if ui.confirmDelete == index then "정말 삭제" else "삭제",
					14,
					if ui.confirmDelete == index then Theme.bad else Theme.button
				)
				place(delete, 172, 66, 120, 44)
				delete.Activated:Connect(function()
					if ui.confirmDelete == index then
						handlers.lobby("DeleteSlot", { slot = index })
						ui.confirmDelete = 0
					else
						ui.confirmDelete = index
					end
					dirty = true
				end)
			else
				head.Text = string.format("기록 %d · 비어 있음", index)
				local x = 12
				for _, kind in { "light", "shadow" } do
					local locked = kind == "shadow" and not summary.darkUnlocked
					local b = Widgets.button(
						card,
						"Hero" .. kind,
						catalog.heroNames[kind] .. (if locked then " (잠김)" else ""),
						13,
						if ui.hero == kind then Theme.buttonHot else Theme.button
					)
					place(b, x, 36, 150, 30)
					b.Activated:Connect(function()
						if not locked then
							ui.hero, dirty = kind, true
						end
					end)
					x += 156
				end
				for d = 0, 3 do
					local b = Widgets.button(
						card,
						"Difficulty" .. d,
						catalog.text.difficulty[d + 1],
						13,
						if ui.difficulty == d then Theme.buttonHot else Theme.button
					)
					place(b, 12 + d * 86, 74, 80, 34)
					b.Activated:Connect(function()
						ui.difficulty, dirty = d, true
					end)
				end
				local create = Widgets.button(card, "Create", "새로 시작", 15, Theme.gold)
				create.TextColor3 = Theme.background
				place(create, 372, 74, 120, 34)
				create.Activated:Connect(function()
					handlers.lobby(
						"CreateSlot",
						{ slot = index, heroKind = ui.hero, difficulty = ui.difficulty }
					)
					ui.screen, dirty = "Stages", true
				end)
			end
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
			local label = string.format(
				"%s\n%s",
				Text.stageLabel(stage),
				if star < 0
					then "잠김"
					else string.rep("★", star) .. string.rep("☆", 3 - star)
			)
			local mode = Text.modeName(meta.mode)
			if mode ~= "" then
				label = label .. "\n" .. mode
			end
			local b = Widgets.button(
				grid,
				"Stage" .. stage,
				label,
				12,
				if star < 0
					then Theme.locked
					elseif stage == ui.stage then Theme.buttonHot
					else Theme.button
			)
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if star >= 0 then
					ui.stage, dirty = stage, true
				end
			end)
		end
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
		local before = if slot.heroKind == "shadow"
			then { 0, 1, 2, 3, 4, 5, 6, 7, 8 }
			else { 0, 1, 2, 3, 6, 4, 5, 7, 8 }
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
			local b = Widgets.button(
				card,
				"Upgrade",
				text,
				13,
				if level >= 20 or blocked then Theme.locked else Theme.button
			)
			place(b, 400, 6, 120, 52)
			b.Activated:Connect(function()
				handlers.lobby("UpgradeUnit", { unit = n })
			end)
		end
	end

	-- Equipment / shop ------------------------------------------------------------------------------------
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
				if ui.item == "equip:" .. i then Theme.buttonHot else Theme.panelLight
			)
			b.LayoutOrder = i
			b.Activated:Connect(function()
				if code ~= 0 then
					ui.item, dirty = "equip:" .. i, true
				end
			end)
		end
		for index, tab in { { "Bag", "가방" }, { "Shop", "상점" }, { "Gems", "보석 상점" } } do
			local b = Widgets.button(
				content,
				"Tab" .. tab[1],
				tab[2],
				14,
				if ui.tab == tab[1] then Theme.buttonHot else Theme.button
			)
			place(b, 390 + (index - 1) * 96, 0, 92, 34)
			b.Activated:Connect(function()
				ui.tab, ui.item, dirty = tab[1], nil, true
			end)
		end
		local list = Widgets.list(content, "List", 4)
		place(list, 390, 40, 290, 300)
		if ui.tab == "Bag" then
			local sub = Widgets.label(
				list,
				"Count",
				string.format("가방 %d / 100", #slot.inventory),
				13,
				Theme.muted
			)
			sub.Size = UDim2.new(1, 0, 0, 20)
			for index, code in slot.inventory do
				local b = Widgets.button(
					list,
					"Item" .. index,
					Text.itemName(catalog, code),
					13,
					if ui.item == "inv:" .. index then Theme.buttonHot else Theme.panelLight
				)
				b.Size = UDim2.new(1, -8, 0, 32)
				b.LayoutOrder = index + 1
				b.Activated:Connect(function()
					ui.item, dirty = "inv:" .. index, true
				end)
			end
		elseif ui.tab == "Shop" then
			local categories: { number } = if kind == "shadow"
				then { 6, 7, 8, 9, 10 }
				else { 1, 2, 3, 4, 5 }
			local order = 0
			for _, category in categories do
				local count = ({ 10, 10, 10, 5, 5, 10, 10, 10, 5, 5 })[category]
				for num = 1, count do
					local price, currency = Text.buyPrice(catalog, category, num)
					if price then
						order += 1
						local code = Text.encode(category, num, 0)
						local b = Widgets.button(
							list,
							"Buy" .. code,
							string.format(
								"%s  %s%s",
								Text.itemName(catalog, code),
								Text.number(price),
								if currency == "gold" then "G" else " 보석"
							),
							12
						)
						b.Size = UDim2.new(1, -8, 0, 30)
						b.LayoutOrder = order
						b.Activated:Connect(function()
							handlers.lobby("BuyItem", { category = category, num = num })
						end)
					end
				end
			end
		else
			for order, entry in { { 1, 1000 }, { 2, 1000 }, { 3, 1 }, { 9, 1000 } } do
				local b = Widgets.button(
					list,
					"Gem" .. entry[1],
					string.format(
						"%s  보석 %d",
						catalog.text.gemShop[tostring(entry[1])],
						entry[2]
					),
					13
				)
				b.Size = UDim2.new(1, -8, 0, 36)
				b.LayoutOrder = order
				b.Activated:Connect(function()
					handlers.lobby("GemShop", { item = entry[1] })
				end)
			end
		end
		-- selected item actions
		local detail = Widgets.frame(content, "ItemDetail", Theme.panel, 8)
		place(detail, 0, 200, 380, 140)
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
			local name = Widgets.label(detail, "Name", Text.itemName(catalog, code), 15, Theme.gold)
			place(name, 10, 4, 360, 22)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local desc = Widgets.label(detail, "Desc", Text.itemDescription(catalog, code), 13)
			place(desc, 10, 28, 360, 40)
			desc.TextXAlignment = Enum.TextXAlignment.Left
			local x = 10
			local function action(label: string, fn: () -> ())
				local b = Widgets.button(detail, label, label, 13)
				place(b, x, 84, 112, 44)
				b.Activated:Connect(fn)
				x += 118
			end
			if where == "inv" then
				action("장착", function()
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
					function()
						handlers.lobby("SellItem", { index = idx })
						ui.item = nil
					end
				)
			else
				action("해제", function()
					handlers.lobby("Unequip", { slot = idx })
					ui.item = nil
				end)
			end
			if Text.canEnchant(code) then
				action(string.format("강화 (보석 %d)", Text.enchantCost(code)), function()
					handlers.lobby("Enchant", { where = where, index = idx })
				end)
			end
		else
			local hint = Widgets.label(
				detail,
				"Hint",
				string.format("장비 강화 상한: +%d", slot.gradeLimit or 5),
				14,
				Theme.muted
			)
			place(hint, 10, 10, 360, 24)
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
				local learn = Widgets.button(card, "Learn", "+", 18)
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
		Widgets.clear(content)
		local summary = model.summary
		if not summary then
			local waiting =
				Widgets.label(content, "Waiting", "서버에 연결하는 중...", 18, Theme.muted)
			waiting.Size = UDim2.fromScale(1, 1)
			return
		end
		local slot = model.slot
		if not slot and ui.screen ~= "Records" then
			ui.screen = "Records"
		end
		for name, b in navButtons do
			b.BackgroundColor3 = if name == ui.screen then Theme.buttonHot else Theme.button
			b.Visible = slot ~= nil or name == "Records"
		end
		if ui.screen == "Records" then
			records(summary)
		elseif ui.screen == "Stages" then
			stages(slot)
		elseif ui.screen == "Units" then
			unitsScreen(slot)
		elseif ui.screen == "Equipment" then
			equipment(slot, summary)
		elseif ui.screen == "Skills" then
			skills(slot)
		elseif ui.screen == "Achievements" then
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
		info.Text = string.format(
			"%s · %s%s",
			model.storage or "",
			model.network or "",
			if summary
				then string.format(
					"  ·  보석 %d%s",
					summary.gems,
					if slot
						then string.format(
							"  ·  %s Lv.%d  %sG",
							catalog.heroNames[slot.heroKind],
							slot.level,
							Text.number(slot.gold)
						)
						else ""
				)
				else ""
		)
		toast.Text = if model.phase == "Unavailable"
			then Text.reason(model.reason or "StorageUnavailable")
			else Text.reason(model.reason)
		if not visible then
			return
		end
		local key = string.format(
			"%s|%s|%d|%d|%d|%s|%s|%s|%s|%d",
			tostring(model.profileRevision),
			ui.screen,
			ui.chapter,
			ui.stage,
			ui.difficulty,
			ui.hero,
			ui.tab,
			tostring(ui.item),
			tostring(model.summary ~= nil),
			ui.confirmDelete
		)
		if dirty or key ~= lastKey then
			dirty, lastKey = false, key
			rebuild(model)
		end
	end

	return {
		root = root,
		update = update,
		inspect = function(): any
			return { screen = ui.screen, chapter = ui.chapter, stage = ui.stage, tab = ui.tab }
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return table.freeze({ new = new })
