--!strict
-- Battle HUD (original screen flow: move buttons bottom-left, unit buttons along the bottom, three weapon
-- buttons bottom-right, food/mana bars, objective on top). Buttons only raise intents; the server decides.
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")
local HudLayout = require("./HudLayout")

export type Handlers = {
	battle: (string, { [string]: any }?) -> (),
	returnToLobby: () -> (),
}

local function new(parent: Instance, catalog: any, handlers: Handlers)
	local root = Widgets.frame(parent, "Hud")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 20

	-- top bar ------------------------------------------------------------------------------------
	local top = Widgets.frame(root, "Top")
	top.Size = UDim2.new(1, -16, 0, 44)
	top.Position = UDim2.fromOffset(8, 6)
	local heroBar, setHero = Widgets.bar(top, "HeroHp", Theme.hp)
	heroBar.Size = UDim2.new(0.32, 0, 0, 18)
	local levelLabel = Widgets.label(top, "Level", "", 13, Theme.gold)
	levelLabel.Size = UDim2.new(0.32, 0, 0, 18)
	levelLabel.Position = UDim2.fromOffset(0, 22)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	local goalBar, setGoal = Widgets.bar(top, "Goal", Theme.enemyHp)
	goalBar.Size = UDim2.new(0.34, 0, 0, 18)
	goalBar.Position = UDim2.fromScale(0.36, 0)
	local goalLabel = Widgets.label(top, "GoalText", "", 13)
	goalLabel.Size = UDim2.new(0.34, 0, 0, 18)
	goalLabel.Position = UDim2.new(0.36, 0, 0, 22)
	local pause = Widgets.button(top, "Pause", "II", 16)
	pause.Size = UDim2.fromOffset(44, 40)
	pause.Position = UDim2.new(1, -44, 0, 0)

	-- bottom controls --------------------------------------------------------------------------------
	local bottom = Widgets.frame(root, "Bottom")
	bottom.Size = UDim2.new(1, -16, 0, 128)
	bottom.Position = UDim2.new(0, 8, 1, -134)
	local left = Widgets.button(bottom, "Left", "◀", 26)
	left.Size = UDim2.fromOffset(64, 64)
	left.Position = UDim2.new(0, 0, 1, -64)
	local right = Widgets.button(bottom, "Right", "▶", 26)
	right.Size = UDim2.fromOffset(64, 64)
	right.Position = UDim2.new(0, 70, 1, -64)
	local foodBar, setFood = Widgets.bar(bottom, "Food", Theme.food)
	foodBar.Size = UDim2.new(1, -380, 0, 16)
	foodBar.Position = UDim2.fromOffset(142, 0)
	local manaBar, setMana = Widgets.bar(bottom, "Mana", Theme.mana)
	manaBar.Size = UDim2.fromOffset(230, 16)
	manaBar.Position = UDim2.new(1, -230, 0, 0)
	local units = Instance.new("ScrollingFrame")
	units.Name = "Units"
	units.BackgroundTransparency, units.BorderSizePixel = 1, 0
	units.ScrollingDirection = Enum.ScrollingDirection.X
	units.AutomaticCanvasSize = Enum.AutomaticSize.X
	units.CanvasSize = UDim2.fromOffset(0, 0)
	units.ScrollBarThickness = 4
	units.ClipsDescendants = true
	units.Parent = bottom
	units.Size = UDim2.new(1, -380, 0, 100)
	units.Position = UDim2.fromOffset(142, 22)
	local unitLayout = Instance.new("UIListLayout")
	unitLayout.FillDirection = Enum.FillDirection.Horizontal
	unitLayout.Padding = UDim.new(0, 4)
	unitLayout.SortOrder = Enum.SortOrder.LayoutOrder
	unitLayout.Parent = units
	local weapons: { TextButton } = {}
	for slot = 1, 3 do
		local b = Widgets.button(bottom, "Mace" .. slot, "", 12, Theme.panelLight)
		b.Size = UDim2.fromOffset(74, 100)
		b.Position = UDim2.new(1, -230 + (slot - 1) * 78, 0, 22)
		weapons[slot] = b
	end

	-- tower lane picker, toast, modals -------------------------------------------------------------
	local lanePicker = Widgets.frame(root, "Lanes", Theme.panel, 8)
	lanePicker.Size = UDim2.fromOffset(110, 230)
	lanePicker.Position = UDim2.new(0, 8, 0.5, -130)
	lanePicker.BackgroundTransparency = 0.25
	lanePicker.Visible = false
	local pick: { [string]: any }? = nil
	local lastUnit = 1 -- tower weapon buttons reuse the last unit chosen
	for lane = 1, 5 do
		local b = Widgets.button(lanePicker, "Lane" .. lane, lane .. "번 길", 14)
		b.Size = UDim2.new(1, -12, 0, 38)
		b.Position = UDim2.fromOffset(6, 6 + (5 - lane) * 44)
		b.Activated:Connect(function()
			if pick then
				local fields = table.clone(pick)
				fields.lane = lane
				handlers.battle(fields.kind, fields)
			end
			pick = nil
			lanePicker.Visible = false
		end)
	end
	local toast = Widgets.label(root, "Toast", "", 16, Theme.gold)
	toast.Size = UDim2.new(1, 0, 0, 24)
	toast.Position = UDim2.fromOffset(0, 56)
	toast.TextStrokeTransparency = 0.3

	local function modal(name: string): Frame
		local shade = Widgets.frame(root, name, Color3.new(0, 0, 0))
		shade.BackgroundTransparency = 0.45
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 40
		shade.Active = true
		shade.Visible = false
		return shade
	end
	local function card(shade: Frame, width: number, height: number): Frame
		local box = Widgets.frame(shade, "Card", Theme.panel, 12)
		box.Size = UDim2.fromOffset(width, height)
		box.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
		box.ZIndex = 41
		return box
	end
	local levelUp = modal("LevelUp")
	local levelCard = card(levelUp, 520, 220)
	local levelTitle = Widgets.label(
		levelCard,
		"Title",
		"레벨 업! 기술 하나를 고르세요",
		18,
		Theme.gold
	)
	levelTitle.Size = UDim2.new(1, 0, 0, 36)
	local choices: { TextButton } = {}
	for i = 1, 3 do
		local b = Widgets.button(levelCard, "Choice" .. i, "", 14)
		b.Size = UDim2.new(1 / 3, -12, 1, -56)
		b.Position = UDim2.new((i - 1) / 3, 6, 0, 46)
		b.ZIndex = 42
		b.Activated:Connect(function()
			handlers.battle("PickSkill", { choice = i })
		end)
		choices[i] = b
	end
	local revive = modal("Revive")
	local reviveCard = card(revive, 380, 170)
	local reviveText = Widgets.label(
		reviveCard,
		"Text",
		"영웅이 쓰러졌습니다.\n보석 20개로 다시 일어날까요?",
		17
	)
	reviveText.Size = UDim2.new(1, 0, 0, 80)
	reviveText.ZIndex = 42
	local reviveYes = Widgets.button(reviveCard, "Yes", "부활 (보석 20)", 15, Theme.gold)
	reviveYes.Size = UDim2.new(0.5, -12, 0, 48)
	reviveYes.Position = UDim2.new(0, 8, 1, -58)
	reviveYes.TextColor3 = Theme.background
	reviveYes.ZIndex = 42
	reviveYes.Activated:Connect(function()
		handlers.battle("Revive", nil)
	end)
	local reviveNo = Widgets.button(reviveCard, "No", "포기", 15)
	reviveNo.Size = UDim2.new(0.5, -12, 0, 48)
	reviveNo.Position = UDim2.new(0.5, 4, 1, -58)
	reviveNo.ZIndex = 42
	reviveNo.Activated:Connect(function()
		handlers.battle("GiveUp", nil)
	end)
	local pauseShade = modal("PauseMenu")
	local pauseCard = card(pauseShade, 360, 200)
	local pauseText = Widgets.label(
		pauseCard,
		"Text",
		"일시정지 화면입니다.\n서버 전투는 계속 진행됩니다.",
		16
	)
	pauseText.Size = UDim2.new(1, 0, 0, 80)
	pauseText.ZIndex = 42
	local resume = Widgets.button(pauseCard, "Resume", "계속하기", 15)
	resume.Size = UDim2.new(0.5, -12, 0, 48)
	resume.Position = UDim2.new(0, 8, 1, -58)
	resume.ZIndex = 42
	local retreat = Widgets.button(pauseCard, "Retreat", "후퇴 (획득분 유지)", 15, Theme.bad)
	retreat.Size = UDim2.new(0.5, -12, 0, 48)
	retreat.Position = UDim2.new(0.5, 4, 1, -58)
	retreat.ZIndex = 42
	pause.Activated:Connect(function()
		pauseShade.Visible = true
	end)
	resume.Activated:Connect(function()
		pauseShade.Visible = false
	end)
	retreat.Activated:Connect(function()
		pauseShade.Visible = false
		handlers.battle("Retreat", nil)
	end)
	local result = modal("Result")
	local resultCard = card(result, 460, 300)
	local resultTitle = Widgets.label(resultCard, "Title", "", 26, Theme.gold)
	resultTitle.Size = UDim2.new(1, 0, 0, 44)
	resultTitle.ZIndex = 42
	local resultBody = Widgets.label(resultCard, "Body", "", 15)
	resultBody.Size = UDim2.new(1, -24, 1, -110)
	resultBody.Position = UDim2.fromOffset(12, 48)
	resultBody.TextXAlignment = Enum.TextXAlignment.Left
	resultBody.TextYAlignment = Enum.TextYAlignment.Top
	resultBody.ZIndex = 42
	local back = Widgets.button(resultCard, "ReturnToLobby", "돌아가기", 16, Theme.gold)
	back.Size = UDim2.new(1, -24, 0, 48)
	back.Position = UDim2.new(0, 12, 1, -58)
	back.TextColor3 = Theme.background
	back.ZIndex = 42
	back.Activated:Connect(function()
		handlers.returnToLobby()
	end)

	local unitButtons: { TextButton } = {}
	local jump = Widgets.button(bottom, "Jump", "도약 (Space)", 22, Theme.mana)
	jump.Size = UDim2.fromOffset(220, 76)
	jump.Position = UDim2.new(0.5, -110, 0, 26)
	jump.Visible = false
	jump.Activated:Connect(function()
		handlers.battle("Jump", nil)
	end)
	local unitKey = ""
	local function rebuildUnits(slot: any, battleView: any)
		local key = slot.heroKind
			.. battleView.mode
			.. (if battleView.mode == "Destiny" then "destiny" else table.concat(slot.units, ","))
		if key == unitKey then
			return
		end
		unitKey = key
		for _, b in unitButtons do
			b:Destroy()
		end
		table.clear(unitButtons)
		if battleView.mode == "Jump" then
			return
		end
		if battleView.mode == "Destiny" then
			for index = 1, 9 do
				local b = Widgets.button(units, "Box" .. index, "", 12, Theme.panelLight)
				b.Size = UDim2.new(1 / 9, -4, 1, 0)
				b.LayoutOrder = index
				b.Activated:Connect(function()
					handlers.battle("Box", { index = index })
				end)
				unitButtons[index] = b
			end
			return
		end
		for n = 1, 9 do
			if slot.units[n] >= 1 then
				local b = Widgets.button(units, "Summon" .. n, "", 12)
				b.Size = UDim2.new(1 / 9, -4, 1, 0)
				b.LayoutOrder = n
				b.Activated:Connect(function()
					lastUnit = n
					if battleView.mode == "Tower" then
						pick = { kind = "Summon", unit = n }
						lanePicker.Visible = true
					else
						handlers.battle("Summon", { unit = n })
					end
				end)
				unitButtons[n] = b
			end
		end
	end

	local currentView: any = nil
	local layoutWidth, layoutKey = -1, ""
	local function applyLayout()
		local width = root.AbsoluteSize.X
		if width == layoutWidth and layoutKey == unitKey then
			return
		end
		layoutWidth, layoutKey = width, unitKey
		local p = HudLayout.plan(width)
		bottom.Size = UDim2.new(1, -16, 0, p.bottomHeight)
		bottom.Position = UDim2.new(0, 8, 1, -p.bottomHeight - 6)
		left.Size, right.Size =
			UDim2.fromOffset(p.moveSize, p.moveSize), UDim2.fromOffset(p.moveSize, p.moveSize)
		left.Position, right.Position =
			UDim2.fromOffset(0, p.moveY), UDim2.fromOffset(p.moveSize + 8, p.moveY)
		units.Size = UDim2.fromOffset(p.unitWidth, p.unitHeight)
		units.Position = UDim2.fromOffset(p.unitX, p.unitY)
		foodBar.Size, foodBar.Position =
			UDim2.fromOffset(p.foodWidth, 16), UDim2.fromOffset(p.foodX, 0)
		manaBar.Size = UDim2.fromOffset(p.manaWidth, 16)
		manaBar.Position = UDim2.new(1, -p.manaWidth, 0, 0)
		for _, button in unitButtons do
			button.Size = UDim2.fromOffset(p.unitButtonWidth, p.unitHeight - 4)
		end
		for index, button in weapons do
			button.Size = UDim2.fromOffset(p.weaponWidth, p.weaponHeight)
			button.Position =
				UDim2.fromOffset(p.weaponX + (index - 1) * (p.weaponWidth + 4), p.weaponY)
		end
	end
	-- Tower: button 1 needs a lane for its five units (D-TOWER-01); others fire directly.
	for slot = 1, 3 do
		weapons[slot].Activated:Connect(function()
			if currentView and currentView.mode == "Tower" and slot == 2 then
				pick = { kind = "Mace", slot = 2, unit = lastUnit }
				lanePicker.Visible = true
			else
				handlers.battle("Mace", { slot = slot, unit = lastUnit })
			end
		end)
	end

	local function update(model: any)
		local view = model.battle
		local slot = model.slot
		root.Visible = model.phase == "Running"
			or model.phase == "Settling"
			or model.phase == "Settled"
		if not view or not slot then
			return
		end
		currentView = view
		local jumping = view.mode == "Jump"
		jump.Visible = jumping
		units.Visible, foodBar.Visible, manaBar.Visible = not jumping, not jumping, not jumping
		left.Visible = not jumping
			and view.mode ~= "Dungeon"
			and view.mode ~= "Tower"
			and view.mode ~= "Destiny"
		right.Visible = left.Visible
		for _, button in weapons do
			button.Visible = not jumping
		end
		local hero = nil
		local goal = nil
		for _, e in view.entities do
			if e.kind == "Hero" then
				hero = e
			elseif
				e.kind == "Castle"
				or e.kind == "Wagon"
				or e.kind == "Horse"
				or (e.kind == "Boss" and view.mode == "Boss")
			then
				goal = e
			end
		end
		if hero then
			setHero(
				hero.hp / hero.maxHp,
				string.format("%d / %d", math.max(0, hero.hp), hero.maxHp)
			)
		end
		local nextExp = view.level * view.level * 100
		levelLabel.Text = string.format(
			"Lv.%d  EXP %s/%s  획득 %sG",
			view.level,
			Text.number(view.exp),
			Text.number(nextExp),
			Text.number(view.gold)
		)
		if jumping then
			setGoal(
				math.min((hero and hero.x or 0) / math.max(view.finish, 1), 1),
				string.format("코인 %d / %d", view.coins, view.coinTotal)
			)
			goalLabel.Text =
				string.format("가시를 뛰어넘으세요 · 재시작 %d회", view.deaths)
		elseif view.mode == "Destiny" or view.mode == "Dungeon" then
			setGoal(view.kills / 60, string.format("처치 %d / 60", view.kills))
			goalLabel.Text = if view.mode == "Dungeon"
				then "함정으로 적을 막으세요"
				else "운명 상자를 열어 싸우세요"
		elseif view.mode == "Tower" then
			setGoal((view.points + 15) / 30, string.format("점수 %+d", view.points))
			goalLabel.Text = "+15 승리 · -15 패배"
		elseif goal then
			setGoal(
				goal.hp / goal.maxHp,
				string.format("%d / %d", math.max(0, math.floor(goal.hp)), math.floor(goal.maxHp))
			)
			goalLabel.Text = if goal.kind == "Wagon"
				then "마차를 지켜 끝까지 보내세요"
				elseif goal.kind == "Horse" then "목마가 도착하기 전에 파괴하세요"
				elseif goal.kind == "Boss" then "보스를 쓰러뜨리세요"
				else "적 성채"
		end
		setFood(
			view.food / view.maxFood,
			string.format("식량 %d / %d", math.floor(view.food), view.maxFood)
		)
		setMana(
			view.mana / view.maxMana,
			string.format("마나 %d / %d", math.floor(view.mana), view.maxMana)
		)
		rebuildUnits(slot, view)
		applyLayout()
		if view.mode == "Destiny" then
			for index, b in unitButtons do
				local box = view.boxes[index]
				if box == "" then
					b.Text, b.BackgroundColor3 = "빈 상자", Theme.locked
				else
					local kind, id = string.match(box, "^(%a+):(%d+)$")
					local n = tonumber(id) or 1
					b.Text = if kind == "Unit"
						then Text.unitName(catalog, slot.heroKind, n)
						else catalog.maces[n].name
					b.BackgroundColor3 = if kind == "Unit" then Theme.button else Theme.mana
				end
			end
		else
			for n, b in unitButtons do
				local buttonView = Text.summonView(catalog, slot, view, n)
				local wait = buttonView.wait
				b.Text = string.format(
					"%s\n%s %d%s",
					buttonView.name,
					buttonView.resource,
					buttonView.cost,
					if wait > 0 then string.format("\n%.1f초", wait) else ""
				)
				b.BackgroundColor3 = if buttonView.ready then Theme.button else Theme.locked
			end
		end
		for index, b in weapons do
			if view.mode == "Tower" then
				b.Text = ({
					"전 길 소환\n마나 90",
					"한 길 5명\n마나 90",
					"전체 회복\n마나 30",
				})[index]
			else
				local code = slot.equip[index]
				if code and code ~= 0 then
					b.Text = Text.itemName(catalog, code)
						.. "\n마나 "
						.. Text.weaponCost(catalog, slot, code)
				else
					b.Text = "비어 있음"
				end
			end
		end
		levelUp.Visible = model.phase == "Running" and view.offer ~= nil
		if view.offer then
			for i, b in choices do
				local index = view.offer[i]
				b.Visible = index ~= nil
				if index then
					local names = catalog.skillNames[slot.heroKind]
					local desc = Text.skillDescription(catalog, slot.heroKind, index)
					b.Text =
						string.format("%s\n(Lv.%d)\n%s", names[index], slot.skills[index], desc)
				end
			end
		end
		revive.Visible = model.phase == "Running" and view.reviveOffer == true
		local settled = model.phase == "Settled" or model.phase == "Settling"
		result.Visible = settled
		if settled then
			local outcome = view.outcome or (model.result and model.result.outcome)
			resultTitle.Text = if outcome == "Victory" then "승리!" else "패배"
			local lines = {}
			local rewards = model.rewards
			if model.settlementStatus ~= "Committed" or not rewards then
				table.insert(lines, "결과를 저장하는 중...")
			else
				local stars = rewards.stars or 0
				table.insert(
					lines,
					"별: " .. string.rep("★", stars) .. string.rep("☆", 3 - stars)
				)
				table.insert(lines, "골드: " .. Text.number(rewards.awardedGold) .. "G")
				table.insert(lines, "경험치: " .. Text.number(rewards.awardedXp))
				if rewards.gems and rewards.gems > 0 then
					table.insert(lines, "업적 보석: " .. rewards.gems)
				end
				for _, code in rewards.items or {} do
					table.insert(lines, "획득: " .. Text.itemName(catalog, code))
				end
			end
			resultBody.Text = table.concat(lines, "\n")
			back.Visible = model.settlementStatus == "Committed"
		end
		toast.Text = Text.reason(model.reason)
	end

	return {
		root = root,
		moveButtons = { Left = left, Right = right },
		update = update,
		inspect = function(): any
			return { units = #unitButtons, lanePicker = lanePicker.Visible, result = result.Visible }
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return table.freeze({ new = new })
