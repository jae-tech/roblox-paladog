--!strict
-- Battle HUD (original screen flow: move buttons bottom-left, unit buttons along the bottom, three weapon
-- buttons bottom-right, food/mana bars, objective on top). Buttons only raise intents; the server decides.
-- Summon/weapon buttons are cards: name, cost tag, hotkey, AUTO tag and a cooldown curtain.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")
local HudLayout = require("./HudLayout")

export type Handlers = {
	battle: (string, { [string]: any }?) -> (),
	returnToLobby: () -> (),
	purchase: ((number) -> ())?, -- Robux store (D-PAY-01): 6 = revive
	speed: ((number) -> ())?, -- battle speed pass
}

type SlotCard = {
	button: TextButton,
	title: TextLabel,
	key: Frame,
	auto: Frame,
	cost: Frame,
	costText: TextLabel,
	curtain: Frame,
	wait: TextLabel,
}

local WEAPON_KEYS = { "Q", "E", "R" }

-- Card button used for summons, destiny boxes and weapons. Children draw over the button (Sibling ZIndex).
local function slotCard(parent: Instance, name: string, hotkey: string, color: Color3): SlotCard
	local button = Widgets.button(parent, name, "", 12, color)
	button.ClipsDescendants = true
	local title = Widgets.label(button, "Title", "", 14)
	title.Size = UDim2.new(1, -8, 0.5, -10)
	title.Position = UDim2.fromOffset(4, 16)
	Widgets.fit(title, 14)
	local key, keyText = Widgets.pill(button, "Key", hotkey, 10, Theme.shade, Theme.muted)
	key.Size = UDim2.fromOffset(16, 14)
	key.Position = UDim2.fromOffset(3, 3)
	key.BackgroundTransparency = 0.35
	keyText.Font = Theme.fontHeavy
	local auto, autoText = Widgets.pill(button, "Auto", "AUTO", 10, Theme.auto, Theme.ink)
	auto.Size = UDim2.fromOffset(34, 14)
	auto.Position = UDim2.new(1, -37, 0, 3)
	autoText.Font = Theme.fontHeavy
	auto.Visible = false
	local cost, costText = Widgets.pill(button, "Cost", "", 12, Theme.shade, Theme.food)
	cost.Size = UDim2.new(1, -8, 0, 18)
	cost.Position = UDim2.new(0, 4, 1, -22)
	cost.BackgroundTransparency = 0.4
	local curtain = Widgets.frame(button, "Cooldown", Theme.shade, 8)
	curtain.BackgroundTransparency = 0.3
	curtain.AnchorPoint = Vector2.new(0, 1)
	curtain.Position = UDim2.fromScale(0, 1)
	curtain.Size = UDim2.fromScale(1, 0)
	curtain.ZIndex = 4
	local wait = Widgets.label(button, "Wait", "", 20)
	wait.Size = UDim2.fromScale(1, 1)
	wait.Font = Theme.fontHeavy
	wait.TextStrokeTransparency = 0.3
	wait.ZIndex = 5
	return {
		button = button,
		title = title,
		key = key,
		auto = auto,
		cost = cost,
		costText = costText,
		curtain = curtain,
		wait = wait,
	}
end

local function new(parent: Instance, catalog: any, handlers: Handlers)
	local root = Widgets.frame(parent, "Hud")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 20
	-- keyboard hints only where a keyboard exists
	local showKeys = UserInputService.KeyboardEnabled or not UserInputService.TouchEnabled

	-- top bar ------------------------------------------------------------------------------------
	local top = Widgets.frame(root, "Top")
	top.Size = UDim2.new(1, -16, 0, 52)
	top.Position = UDim2.fromOffset(8, 6)
	local heroPanel = Widgets.card(top, "HeroPanel", Theme.panelDeep, 10)
	heroPanel.Size = UDim2.new(0.32, 0, 0, 52)
	heroPanel.BackgroundTransparency = 0.2
	local levelBadge, levelBadgeText =
		Widgets.pill(heroPanel, "LevelBadge", "", 14, Theme.gold, Theme.ink)
	levelBadge.Size = UDim2.fromOffset(52, 22)
	levelBadge.Position = UDim2.fromOffset(6, 6)
	levelBadgeText.Font = Theme.fontHeavy
	local heroBar, setHero = Widgets.bar(heroPanel, "HeroHp", Theme.hp)
	heroBar.Size = UDim2.new(1, -70, 0, 20)
	heroBar.Position = UDim2.fromOffset(64, 7)
	local expBar, setExp = Widgets.bar(heroPanel, "Exp", Theme.gold)
	expBar.Size = UDim2.new(1, -70, 0, 5)
	expBar.Position = UDim2.fromOffset(64, 31)
	local levelLabel = Widgets.label(heroPanel, "Level", "", 12, Theme.muted)
	levelLabel.Size = UDim2.new(1, -12, 0, 14)
	levelLabel.Position = UDim2.fromOffset(6, 36)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Font = Theme.fontBody

	local goalPanel = Widgets.card(top, "GoalPanel", Theme.panelDeep, 10)
	goalPanel.AnchorPoint = Vector2.new(0.5, 0)
	goalPanel.Size = UDim2.new(0.34, 0, 0, 52)
	goalPanel.Position = UDim2.fromScale(0.5, 0)
	goalPanel.BackgroundTransparency = 0.2
	local goalLabel = Widgets.label(goalPanel, "GoalText", "", 14, Theme.gold)
	goalLabel.Size = UDim2.new(1, -12, 0, 18)
	goalLabel.Position = UDim2.fromOffset(6, 4)
	goalLabel.Font = Theme.fontHeavy
	local goalBar, setGoal = Widgets.bar(goalPanel, "Goal", Theme.enemyHp)
	goalBar.Size = UDim2.new(1, -16, 0, 20)
	goalBar.Position = UDim2.fromOffset(8, 25)

	-- rules of special stages, shown for the first seconds of a battle (destiny boxes, lanes, ...)
	local MODE_RULES: { [string]: { string } } = {
		Destiny = {
			"운명 스테이지",
			"몇 초마다 운명 상자가 생깁니다. 상자를 눌러 무작위 용병이나 주문을 식량·마나 없이 쓰세요. 영웅은 제자리에서 싸웁니다.",
		},
		Tower = {
			"점령 스테이지",
			"다섯 줄로 오는 적을 막으세요. 용병 버튼을 누른 뒤 보낼 줄을 고릅니다. 영웅은 제자리에서 싸웁니다.",
		},
		Wagon = {
			"호위 스테이지",
			"보급 마차가 끝까지 가도록 지키세요. 마차가 부서지면 패배합니다.",
		},
		Boss = { "보스 스테이지", "보스를 쓰러뜨리면 승리합니다." },
		Horse = { "공성 목마", "목마가 성문에 도착하기 전에 파괴하세요." },
		Dungeon = {
			"던전 스테이지",
			"적 60마리를 처치하면 승리합니다. 영웅은 제자리에서 싸웁니다.",
		},
		Jump = { "달리기 스테이지", "코인을 모으며 결승선까지 달리세요." },
		Survival = {
			"서바이벌",
			"끝없이 오는 웨이브를 최대한 오래 버티세요.",
		},
	}
	local rules = Widgets.card(root, "ModeRules", Theme.panelDeep, 12)
	rules.AnchorPoint = Vector2.new(0.5, 0)
	rules.Size = UDim2.fromOffset(420, 74)
	rules.Position = UDim2.new(0.5, 0, 0, 62)
	rules.BackgroundTransparency = 0.1
	rules.Visible = false
	Widgets.outline(rules, Theme.gold, 1, 0.3)
	local rulesTitle = Widgets.label(rules, "Title", "", 16, Theme.gold)
	rulesTitle.Font = Theme.fontHeavy
	rulesTitle.Size = UDim2.new(1, -20, 0, 22)
	rulesTitle.Position = UDim2.fromOffset(10, 6)
	local rulesBody = Widgets.label(rules, "Body", "", 13, Theme.text)
	rulesBody.Font = Theme.fontBody
	rulesBody.TextWrapped = true
	rulesBody.Size = UDim2.new(1, -20, 0, 40)
	rulesBody.Position = UDim2.fromOffset(10, 28)

	local pause = Widgets.button(top, "Pause", "II", 18, Theme.panelDeep)
	pause.Font = Theme.fontHeavy
	pause.Size = UDim2.fromOffset(46, 46)
	pause.Position = UDim2.new(1, -46, 0, 0)
	Widgets.corner(pause, 23)
	-- battle speed pass (D-PAY-01): 1x / 2x toggle next to pause, shown only to owners
	local speedButton = Widgets.button(top, "Speed", "1x", 16, Theme.panelDeep)
	speedButton.Font = Theme.fontHeavy
	speedButton.Size = UDim2.fromOffset(46, 46)
	speedButton.Position = UDim2.new(1, -98, 0, 0)
	speedButton.Visible = false
	Widgets.corner(speedButton, 23)
	local currentSpeed = 1
	speedButton.Activated:Connect(function()
		if handlers.speed then
			handlers.speed(if currentSpeed == 2 then 1 else 2)
		end
	end)

	-- bottom controls --------------------------------------------------------------------------------
	local bottom = Widgets.frame(root, "Bottom")
	bottom.Size = UDim2.new(1, -16, 0, 128)
	bottom.Position = UDim2.new(0, 8, 1, -134)
	local function moveButton(name: string, text: string, size: number): TextButton
		local b = Widgets.button(bottom, name, text, size, Theme.panelDeep)
		b.BackgroundTransparency = 0.15
		Widgets.corner(b, 24)
		return b
	end
	local left = moveButton("Left", "◀\n후퇴", 14)
	left.Size = UDim2.fromOffset(64, 64)
	left.Position = UDim2.new(0, 0, 1, -64)
	local right = moveButton("Right", "전진\n▶", 14)
	right.Size = UDim2.fromOffset(64, 64)
	right.Position = UDim2.new(0, 70, 1, -64)
	local strafeLeft = moveButton("StrafeLeft", "▲", 20)
	local strafeRight = moveButton("StrafeRight", "▼", 20)
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
	units.ScrollBarImageColor3 = Theme.border
	units.ClipsDescendants = true
	units.Parent = bottom
	units.Size = UDim2.new(1, -380, 0, 100)
	units.Position = UDim2.fromOffset(142, 22)
	local unitLayout = Instance.new("UIListLayout")
	unitLayout.FillDirection = Enum.FillDirection.Horizontal
	unitLayout.Padding = UDim.new(0, 4)
	unitLayout.SortOrder = Enum.SortOrder.LayoutOrder
	unitLayout.Parent = units
	local weapons: { SlotCard } = {}
	for slot = 1, 3 do
		local c = slotCard(bottom, "Mace" .. slot, WEAPON_KEYS[slot], Theme.panelLight)
		c.button.Size = UDim2.fromOffset(74, 100)
		c.button.Position = UDim2.new(1, -230 + (slot - 1) * 78, 0, 22)
		c.costText.TextColor3 = Theme.mana
		c.key.Visible = showKeys
		weapons[slot] = c
	end

	-- tower lane picker, toast, modals -------------------------------------------------------------
	local lanePicker = Widgets.card(root, "Lanes", Theme.panelDeep, 10)
	lanePicker.Size = UDim2.fromOffset(110, 230)
	lanePicker.Position = UDim2.new(0, 8, 0.5, -130)
	lanePicker.BackgroundTransparency = 0.15
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
	local toast, setToast = Widgets.toast(root, "Toast")
	toast.Size = UDim2.fromOffset(0, 28)
	toast.Position = UDim2.new(0.5, 0, 0, 64)
	toast.ZIndex = 30

	local function modal(name: string): Frame
		local shade = Widgets.frame(root, name, Theme.shade)
		shade.BackgroundTransparency = 0.4
		shade.Size = UDim2.fromScale(1, 1)
		shade.ZIndex = 40
		shade.Active = true
		shade.Visible = false
		return shade
	end
	local function card(shade: Frame, width: number, height: number): Frame
		local box = Widgets.card(shade, "Card", Theme.panel, 14)
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Size = UDim2.fromOffset(width, height)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.ZIndex = 41
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(width, height)
		limit.Parent = box
		box.Size = UDim2.new(0.94, 0, 0, height)
		return box
	end
	local function heading(box: Frame, text: string, color: Color3?): TextLabel
		local t = Widgets.label(box, "Title", text, 20, color or Theme.gold)
		t.Font = Theme.fontHeavy
		t.Size = UDim2.new(1, -24, 0, 34)
		t.Position = UDim2.fromOffset(12, 8)
		t.ZIndex = 42
		return t
	end
	-- show a modal with its entrance animation the first time it becomes visible
	local function showModal(shade: Frame, box: Frame, visible: boolean)
		if visible and not shade.Visible then
			shade.Visible = true
			Widgets.pop(shade, box)
		elseif not visible then
			shade.Visible = false
		end
	end

	local levelUp = modal("LevelUp")
	local levelCard = card(levelUp, 560, 250)
	heading(levelCard, "레벨 업!  기술 하나를 고르세요")
	local choices: { { button: TextButton, name: TextLabel, rank: TextLabel, desc: TextLabel } } =
		{}
	for i = 1, 3 do
		local b = Widgets.button(levelCard, "Choice" .. i, "", 14, Theme.panelLight)
		b.Size = UDim2.new(1 / 3, -12, 1, -64)
		b.Position = UDim2.new((i - 1) / 3, 6, 0, 52)
		b.ZIndex = 42
		local name = Widgets.label(b, "Name", "", 16, Theme.gold)
		name.Size = UDim2.new(1, -12, 0, 40)
		name.Position = UDim2.fromOffset(6, 8)
		name.ZIndex = 43
		Widgets.fit(name, 16)
		local rank = Widgets.label(b, "Rank", "", 13, Theme.good)
		rank.Size = UDim2.new(1, -12, 0, 18)
		rank.Position = UDim2.fromOffset(6, 48)
		rank.ZIndex = 43
		local desc = Widgets.label(b, "Desc", "", 12, Theme.muted)
		desc.Font = Theme.fontBody
		desc.Size = UDim2.new(1, -12, 1, -76)
		desc.Position = UDim2.fromOffset(6, 70)
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.ZIndex = 43
		Widgets.fit(desc, 13)
		b.Activated:Connect(function()
			handlers.battle("PickSkill", { choice = i })
		end)
		choices[i] = { button = b, name = name, rank = rank, desc = desc }
	end

	local revive = modal("Revive")
	local reviveCard = card(revive, 400, 190)
	heading(reviveCard, "영웅이 쓰러졌습니다", Theme.bad)
	local reviveText =
		Widgets.label(reviveCard, "Text", "보석 20개로 다시 일어날까요?", 16, Theme.text)
	reviveText.Size = UDim2.new(1, -24, 0, 50)
	reviveText.Position = UDim2.fromOffset(12, 46)
	reviveText.Font = Theme.fontBody
	reviveText.ZIndex = 42
	local reviveYes = Widgets.button(reviveCard, "Yes", "부활 (보석 20)", 15, Theme.gold)
	reviveYes.Size = UDim2.new(0.5, -12, 0, 48)
	reviveYes.Position = UDim2.new(0, 8, 1, -58)
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
	-- without 20 gems the revive can be bought with Robux (D-PAY-01, item 6)
	local reviveBuy = Widgets.button(reviveCard, "Buy", "R$ 부활", 15, Theme.gold)
	reviveBuy.Size = UDim2.new(0.5, -12, 0, 48)
	reviveBuy.Position = UDim2.new(0, 8, 1, -58)
	reviveBuy.ZIndex = 42
	reviveBuy.Visible = false
	reviveBuy.Activated:Connect(function()
		if handlers.purchase then
			handlers.purchase(6)
		end
	end)

	local retreated = false -- the server reports a retreat as Defeat; the title says what the player did
	local pauseShade = modal("PauseMenu")
	local pauseCard = card(pauseShade, 380, 200)
	heading(pauseCard, "일시정지")
	local pauseText = Widgets.label(
		pauseCard,
		"Text",
		"메뉴를 보는 동안에도 서버 전투는 계속 진행됩니다.",
		14,
		Theme.muted
	)
	pauseText.Size = UDim2.new(1, -24, 0, 50)
	pauseText.Position = UDim2.fromOffset(12, 46)
	pauseText.Font = Theme.fontBody
	pauseText.ZIndex = 42
	local resume = Widgets.button(pauseCard, "Resume", "계속하기", 15, Theme.gold)
	resume.Size = UDim2.new(0.5, -12, 0, 48)
	resume.Position = UDim2.new(0, 8, 1, -58)
	resume.ZIndex = 42
	local retreat = Widgets.button(pauseCard, "Retreat", "후퇴 (획득분 유지)", 15, Theme.bad)
	retreat.Size = UDim2.new(0.5, -12, 0, 48)
	retreat.Position = UDim2.new(0.5, 4, 1, -58)
	retreat.ZIndex = 42
	pause.Activated:Connect(function()
		showModal(pauseShade, pauseCard, true)
	end)
	resume.Activated:Connect(function()
		showModal(pauseShade, pauseCard, false)
	end)
	retreat.Activated:Connect(function()
		retreated = true
		showModal(pauseShade, pauseCard, false)
		handlers.battle("Retreat", nil)
	end)

	local result = modal("Result")
	local resultCard = card(result, 460, 330)
	local resultTitle = heading(resultCard, "")
	resultTitle.TextSize = 30
	resultTitle.Size = UDim2.new(1, -24, 0, 40)
	local resultStars = Widgets.label(resultCard, "Stars", "", 30, Theme.gold)
	resultStars.Size = UDim2.new(1, -24, 0, 34)
	resultStars.Position = UDim2.fromOffset(12, 50)
	resultStars.ZIndex = 42
	local resultBody = Widgets.list(resultCard, "Body", 4)
	resultBody.Size = UDim2.new(1, -40, 1, -156)
	resultBody.Position = UDim2.fromOffset(20, 90)
	resultBody.ZIndex = 42
	local back = Widgets.button(resultCard, "ReturnToLobby", "돌아가기", 16, Theme.gold)
	back.Size = UDim2.new(1, -24, 0, 48)
	back.Position = UDim2.new(0, 12, 1, -58)
	back.ZIndex = 42
	back.Activated:Connect(function()
		handlers.returnToLobby()
	end)
	local resultKey = ""
	-- one reward line: caption on the left, value on the right
	local function rewardLine(order: number, caption: string, value: string, color: Color3?)
		local line = Widgets.frame(resultBody, "Line" .. order, Theme.panelDeep, 6)
		line.Size = UDim2.new(1, -6, 0, 26)
		line.LayoutOrder = order
		line.ZIndex = 42
		local c = Widgets.label(line, "Caption", caption, 14, Theme.muted)
		c.Size = UDim2.new(0.5, -10, 1, 0)
		c.Position = UDim2.fromOffset(10, 0)
		c.TextXAlignment = Enum.TextXAlignment.Left
		c.ZIndex = 43
		local v = Widgets.label(line, "Value", value, 15, color or Theme.text)
		v.Size = UDim2.new(0.5, -10, 1, 0)
		v.Position = UDim2.fromScale(0.5, 0)
		v.TextXAlignment = Enum.TextXAlignment.Right
		v.ZIndex = 43
	end

	local unitCards: { [number]: SlotCard } = {}
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
		table.clear(unitCards)
		if battleView.mode == "Jump" then
			return
		end
		if battleView.mode == "Destiny" then
			for index = 1, 9 do
				local c = slotCard(units, "Box" .. index, tostring(index), Theme.panelLight)
				c.key.Visible = showKeys
				c.button.LayoutOrder = index
				c.button.Activated:Connect(function()
					handlers.battle("Box", { index = index })
				end)
				unitCards[index] = c
				unitButtons[index] = c.button
			end
			return
		end
		for n = 1, 9 do
			if slot.units[n] >= 1 then
				local c = slotCard(units, "Summon" .. n, tostring(n), Theme.button)
				c.key.Visible = showKeys
				c.button.LayoutOrder = n
				c.button.Activated:Connect(function()
					lastUnit = n
					if battleView.mode == "Tower" then
						pick = { kind = "Summon", unit = n }
						lanePicker.Visible = true
					else
						handlers.battle("Summon", { unit = n })
					end
				end)
				unitCards[n] = c
				unitButtons[n] = c.button
			end
		end
	end

	local currentView: any = nil
	local layoutWidth, layoutKey = -1, ""
	local reserveRight = 0
	local function applyLayout()
		local width = root.AbsoluteSize.X
		local key = unitKey .. reserveRight
		if width == layoutWidth and layoutKey == key then
			return
		end
		layoutWidth, layoutKey = width, key
		local p = HudLayout.plan(width, reserveRight)
		bottom.Size = UDim2.new(1, -16, 0, p.bottomHeight)
		bottom.Position = UDim2.new(0, 8, 1, -p.bottomHeight - 6)
		left.Size, right.Size =
			UDim2.fromOffset(p.moveSize, p.moveSize), UDim2.fromOffset(p.moveSize, p.moveSize)
		left.Position, right.Position =
			UDim2.fromOffset(0, p.moveY), UDim2.fromOffset(p.moveSize + 8, p.moveY)
		strafeLeft.Size, strafeRight.Size = left.Size, right.Size
		strafeLeft.Position, strafeRight.Position =
			UDim2.fromOffset(0, p.strafeY), UDim2.fromOffset(p.moveSize + 8, p.strafeY)
		units.Size = UDim2.fromOffset(p.unitWidth, p.unitHeight)
		units.Position = UDim2.fromOffset(p.unitX, p.unitY)
		foodBar.Size, foodBar.Position =
			UDim2.fromOffset(p.foodWidth, 16), UDim2.fromOffset(p.foodX, 0)
		manaBar.Size = UDim2.fromOffset(p.manaWidth, 16)
		manaBar.Position = UDim2.new(1, -p.manaWidth, 0, 0)
		for _, button in unitButtons do
			button.Size = UDim2.fromOffset(p.unitButtonWidth, p.unitHeight - 4)
		end
		for index, c in weapons do
			c.button.Size = UDim2.fromOffset(p.weaponWidth, p.weaponHeight)
			c.button.Position =
				UDim2.fromOffset(p.weaponX + (index - 1) * (p.weaponWidth + 4), p.weaponY)
		end
	end
	-- Tower: button 1 needs a lane for its five units (D-TOWER-01); others fire directly.
	for slot = 1, 3 do
		weapons[slot].button.Activated:Connect(function()
			if currentView and currentView.mode == "Tower" and slot == 2 then
				pick = { kind = "Mace", slot = 2, unit = lastUnit }
				lanePicker.Visible = true
			else
				handlers.battle("Mace", { slot = slot, unit = lastUnit })
			end
		end)
	end

	local function setCard(
		c: SlotCard,
		ready: boolean,
		on: boolean,
		ratio: number,
		waitText: string
	)
		c.auto.Visible = on
		Widgets.paint(
			c.button,
			if on then Theme.buttonHot elseif ready then Theme.button else Theme.locked
		)
		c.title.TextColor3 = if on then Theme.ink elseif ready then Theme.text else Theme.muted
		c.curtain.Size = UDim2.fromScale(1, math.clamp(ratio, 0, 1))
		c.wait.Text = waitText
	end

	local function update(model: any)
		local view = model.battle
		local slot = model.slot
		root.Visible = model.phase == "Running"
			or model.phase == "Settling"
			or model.phase == "Settled"
		if not root.Visible then
			retreated = false
		end
		if not view or not slot then
			return
		end
		currentView = view
		local rule = MODE_RULES[view.mode]
		rules.Visible = rule ~= nil and model.phase == "Running" and (view.tick or 0) < 8 * 30
		if rule then
			rulesTitle.Text, rulesBody.Text = rule[1], rule[2]
		end
		local jumping = view.mode == "Jump"
		jump.Visible = jumping
		units.Visible, foodBar.Visible, manaBar.Visible = not jumping, not jumping, not jumping
		-- R8 avatar combat: the Roblox thumbstick / WASD moves the real character instead
		left.Visible = not jumping
			and not model.avatarCombat
			and view.mode ~= "Dungeon"
			and view.mode ~= "Tower"
			and view.mode ~= "Destiny"
		right.Visible = left.Visible
		strafeLeft.Visible = left.Visible and view.spatial == true
		strafeRight.Visible = strafeLeft.Visible
		for _, c in weapons do
			c.button.Visible = not jumping
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
		local prevExp = (view.level - 1) * (view.level - 1) * 100
		levelBadgeText.Text = "Lv." .. view.level
		setExp((view.exp - prevExp) / math.max(nextExp - prevExp, 1), nil)
		levelLabel.Text = string.format(
			"EXP %s / %s   ·   획득 %sG",
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
		elseif view.mode == "Survival" then
			setGoal(
				if (view.waveRest or 0) > 0 then 1 else 0,
				string.format("웨이브 %d · 보석 +%d", view.wave or 1, view.gems or 0)
			)
			goalLabel.Text = if view.darkEvent
				then "검은 그림자를 쓰러뜨리세요"
				elseif (view.waveRest or 0) > 0 then "다음 웨이브 준비 중"
				else "끝까지 버티세요"
		elseif goal then
			setGoal(
				goal.hp / goal.maxHp,
				string.format("%d / %d", math.max(0, math.floor(goal.hp)), math.floor(goal.maxHp))
			)
			goalLabel.Text = if goal.kind == "Wagon"
				then "마차를 지켜 끝까지 보내세요"
				elseif goal.kind == "Horse" then "목마가 도착하기 전에 파괴하세요"
				elseif goal.kind == "Boss" then "보스를 쓰러뜨리세요"
				else "적 성채를 무너뜨리세요"
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
		-- avatar combat on touch shows Roblox's jump button in the bottom-right corner
		reserveRight = if model.avatarCombat and UserInputService.TouchEnabled then 110 else 0
		applyLayout()
		if view.mode == "Destiny" then
			-- one shared timer fills the first empty box
			local firstEmpty = table.find(view.boxes, "")
			for index, c in unitCards do
				local box = view.boxes[index]
				c.cost.Visible = false
				if box == "" then
					c.title.Text = if view.boxNext and index == firstEmpty
						then string.format("다음 상자\n%d초", view.boxNext)
						else "빈 상자"
					setCard(c, false, false, 0, "")
					Widgets.paint(c.button, Theme.locked)
				else
					local kind, id = string.match(box, "^(%a+):(%d+)$")
					local n = tonumber(id) or 1
					c.title.Text = if kind == "Unit"
						then Text.unitName(catalog, slot.heroKind, n)
						else catalog.maces[n].name
					setCard(c, true, false, 0, "")
					Widgets.paint(c.button, if kind == "Unit" then Theme.button else Theme.mana)
				end
			end
		else
			for n, c in unitCards do
				local buttonView = Text.summonView(catalog, slot, view, n)
				local wait = buttonView.wait
				local total = if buttonView.resource == "식량"
					then Text.cooldownLeft(catalog, slot.heroKind, n, slot.skills[13] or 0, 0)
					else 0
				local on = model.auto ~= nil and model.auto.summon[n] == true
				local short = buttonView.resource == "식량" and view.food < buttonView.cost
					or buttonView.resource == "마나" and view.mana < buttonView.cost
				c.title.Text = buttonView.name
				c.costText.Text = string.format("%s %d", buttonView.resource, buttonView.cost)
				c.costText.TextColor3 = if short
					then Theme.bad
					elseif buttonView.resource == "마나" then Theme.mana
					else Theme.food
				setCard(
					c,
					buttonView.ready,
					on,
					if total > 0 then wait / total else 0,
					if wait > 0 then string.format("%.1f", wait) else ""
				)
			end
		end
		for index, c in weapons do
			if view.mode == "Tower" then
				c.title.Text = ({ "전 길 소환", "한 길 5명", "전체 회복" })[index]
				c.costText.Text = ({ "마나 90", "마나 90", "마나 30" })[index]
				c.cost.Visible = true
				c.auto.Visible = false
				Widgets.paint(c.button, Theme.panelLight)
			else
				local code = slot.equip[index]
				local on = model.auto ~= nil and model.auto.weapon[index] == true
				c.auto.Visible = on
				if code and code ~= 0 then
					local cost = Text.weaponCost(catalog, slot, code)
					local need = tonumber(cost)
					c.title.Text = Text.itemName(catalog, code)
					c.cost.Visible = true
					c.costText.Text = if need then "마나 " .. cost else cost
					c.costText.TextColor3 = if need == nil
						then Theme.gold
						elseif view.mana < need then Theme.bad
						else Theme.mana
					c.title.TextColor3 = if on then Theme.ink else Theme.text
				else
					c.title.Text = "비어 있음"
					c.title.TextColor3 = Theme.muted
					c.cost.Visible = false
				end
				Widgets.paint(c.button, if on then Theme.buttonHot else Theme.panelLight)
			end
		end
		showModal(levelUp, levelCard, model.phase == "Running" and view.offer ~= nil)
		if view.offer then
			for i, choice in choices do
				local index = view.offer[i]
				choice.button.Visible = index ~= nil
				if index then
					local names = catalog.skillNames[slot.heroKind]
					local level = slot.skills[index]
					choice.name.Text = names[index]
					choice.rank.Text = string.format("Lv.%d  →  Lv.%d", level, level + 1)
					choice.desc.Text = Text.skillDescription(catalog, slot.heroKind, index)
				end
			end
		end
		showModal(revive, reviveCard, model.phase == "Running" and view.reviveOffer == true)
		local gems = if model.summary then model.summary.gems or 0 else 0
		local store = ReplicatedStorage:FindFirstChild("Store")
		local revivePrice = if store then store:GetAttribute("Price6") else nil
		local canBuy = gems < 20 and type(revivePrice) == "number" and revivePrice > 0
		reviveYes.Visible = not canBuy
		reviveBuy.Visible = canBuy
		if canBuy then
			reviveBuy.Text = string.format("부활 (R$ %d)", revivePrice :: number)
			reviveText.Text = "보석이 모자랍니다. Robux로 바로 다시 일어날까요?"
		else
			reviveText.Text = "보석 20개로 다시 일어날까요?"
		end
		currentSpeed = model.speed or 1
		speedButton.Visible = Players.LocalPlayer:GetAttribute("PassSpeed") == true
			and model.phase == "Running"
		speedButton.Text = currentSpeed .. "x"
		speedButton.BackgroundColor3 = if currentSpeed == 2 then Theme.gold else Theme.panelDeep
		local settled = model.phase == "Settled" or model.phase == "Settling"
		showModal(result, resultCard, settled)
		if settled then
			local outcome = view.outcome or (model.result and model.result.outcome)
			resultTitle.Text = if outcome == "Victory"
				then "승리!"
				elseif view.mode == "Survival" then "원정 종료"
				elseif retreated then "후퇴"
				else "패배"
			resultTitle.TextColor3 = if outcome == "Victory"
				then Theme.gold
				elseif view.mode == "Survival" or retreated then Theme.text
				else Theme.bad
			local rewards = model.rewards
			local committed = model.settlementStatus == "Committed" and rewards ~= nil
			local key = tostring(committed) .. tostring(outcome) .. tostring(model.profileRevision)
			if key ~= resultKey then
				resultKey = key
				Widgets.clear(resultBody)
				resultStars.Text = ""
				if not committed then
					rewardLine(1, "결과를 저장하는 중...", "")
				else
					if rewards.wave then
						resultStars.Text = "웨이브 " .. rewards.wave
						resultStars.TextColor3 = Theme.gem
					else
						local stars = rewards.stars or 0
						resultStars.Text = string.rep("★", stars) .. string.rep("☆", 3 - stars)
						resultStars.TextColor3 = Theme.gold
					end
					local order = 1
					if rewards.darkUnlock then
						rewardLine(order, "새 영웅 해금", catalog.heroNames.shadow, Theme.good)
						order += 1
					end
					if rewards.difficultyUp then
						-- D-DIFF-01: every stage cleared, the next difficulty starts from 1-1
						rewardLine(
							order,
							"난이도 상승",
							catalog.text.difficulty[rewards.difficultyUp + 1] or "",
							Theme.good
						)
						order += 1
					end
					rewardLine(order, "골드", Text.number(rewards.awardedGold) .. "G", Theme.gold)
					rewardLine(order + 1, "경험치", Text.number(rewards.awardedXp), Theme.good)
					order += 2
					if rewards.gems and rewards.gems > 0 then
						rewardLine(order, "보석", tostring(rewards.gems), Theme.gem)
						order += 1
					end
					for _, code in rewards.items or {} do
						rewardLine(order, "획득", Text.itemName(catalog, code), Theme.text)
						order += 1
					end
					-- the card grows with its reward lines (two lines minimum, scrolls past eight)
					local height = 156 + math.clamp(order - 1, 2, 8) * 30
					local limit = resultCard:FindFirstChildOfClass("UISizeConstraint")
					if limit then
						limit.MaxSize = Vector2.new(460, height)
					end
					resultCard.Size = UDim2.new(0.94, 0, 0, height)
				end
			end
			back.Visible = model.settlementStatus == "Committed"
		else
			resultKey = ""
		end
		setToast(Text.reason(model.reason))
	end

	return {
		root = root,
		moveButtons = {
			Left = left,
			Right = right,
			StrafeLeft = strafeLeft,
			StrafeRight = strafeRight,
		},
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
