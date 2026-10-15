--!strict
local Layout = require("./Layout")
local Tokens = require("./Tokens")
local CameraController = require("./CameraController")
local EntityView = require("./EntityView")

local ORDER = { "vanguard", "slinger", "bulwark" }
local TRAITS = { "vitality", "provisions", "focus" }
local REASONS: { [string]: string } = {
	InsufficientFood = "식량이 부족합니다",
	InsufficientMana = "마나가 부족합니다",
	Cooldown = "아직 준비 중입니다",
	Busy = "처리 중입니다",
	UnitCap = "아군이 최대 인원입니다",
	ProjectileCap = "탄이 너무 많습니다",
	NotRunning = "전투 중에만 사용할 수 있습니다",
	RateLimited = "입력이 너무 빠릅니다",
	SessionLost = "세션이 종료되었습니다",
	StageLocked = "이전 원정을 먼저 완료하세요",
	LockedStage = "이전 원정을 먼저 완료하세요",
	WrongPhase = "현재 상태에서는 사용할 수 없습니다",
	NotReady = "서버 준비를 기다립니다",
	StorageUnavailable = "저장소를 사용할 수 없습니다",
	ProtocolMismatch = "버전이 달라 연결할 수 없습니다",
	InvalidPhase = "현재 상태에서는 사용할 수 없습니다",
	InsufficientGold = "골드가 부족합니다",
	NoPoints = "사용할 특성 포인트가 없습니다",
	MaxLevel = "최대 레벨입니다",
	StaleRevision = "최신 보유량으로 갱신했습니다. 다시 선택하세요",
}

local function bounds(gui: GuiObject, rect: Layout.Rect)
	gui.Position = UDim2.fromOffset(rect.x, rect.y)
	gui.Size = UDim2.fromOffset(rect.width, rect.height)
end
local function label(parent: Instance, name: string, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name, item.BackgroundTransparency = name, 1
	item.Font, item.TextSize = Enum.Font.GothamMedium, size
	item.TextColor3, item.TextXAlignment = color, Enum.TextXAlignment.Left
	item.TextWrapped = true
	item.Parent = parent
	return item
end
local function button(parent: Instance, name: string, text: string, accent: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name, item.Text = name, text
	item.BackgroundColor3, item.TextColor3 = Tokens.button, Tokens.text
	item.Font, item.TextSize = Enum.Font.GothamMedium, 14
	item.TextWrapped, item.AutoButtonColor = true, true
	item.Selectable = true
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = accent, 1, Enum.ApplyStrokeMode.Border
	stroke.Parent = item
	local round = Instance.new("UICorner")
	round.CornerRadius, round.Parent = UDim.new(0, 6), item
	item.Parent = parent
	return item
end
local function panel(parent: Instance, name: string): Frame
	local item = Instance.new("Frame")
	item.Name, item.BackgroundColor3 = name, Tokens.panel
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end
local function milli(value: number?): string
	return string.format("%.1f", (value or 0) / 1000)
end
local function cooldown(ready: number?, tick: number): string
	local ticks = math.max(0, (ready or 0) - tick)
	return if ticks > 0 then string.format("%.1f초", ticks / 20) else "준비"
end

local function new(playerGui: PlayerGui, onAction: (string) -> (), stageGameplay: boolean?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LanternExpedition"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local root = Instance.new("Frame")
	root.Name, root.Size, root.BackgroundTransparency = "SafeArea", UDim2.fromScale(1, 1), 1
	root.Parent = gui
	local hud = panel(root, "HUD")
	local title = label(hud, "Title", 18, Tokens.amber)
	local hp = label(hud, "Health", 14, Tokens.text)
	local resources = label(hud, "Resources", 14, Tokens.teal)
	local status = label(hud, "Status", 12, Tokens.muted)
	local message = label(root, "Reason", 14, Tokens.amber)
	message.TextXAlignment = Enum.TextXAlignment.Center
	local rotate = label(root, "RotateHint", 12, Tokens.muted)
	rotate.Text, rotate.TextXAlignment =
		"가로 화면에서 전장이 더 넓게 보입니다", Enum.TextXAlignment.Center
	local menu = button(hud, "Menu", "메뉴", Tokens.border)
	local stage = panel(root, "StageSelect")
	local stageTitle = label(stage, "StageTitle", 18, Tokens.amber)
	local stageNote = label(stage, "StageNote", 12, Tokens.muted)
	local starts: { TextButton } = {}
	local connections: { RBXScriptConnection } = {}
	local model: any =
		{ phase = "Connecting", storage = "Mock/InMemory", network = "연결 대기" }
	local modal = panel(root, "MenuOverlay")
	modal.ZIndex, modal.Visible, modal.Active = 10, false, true
	local modalText = label(modal, "MenuText", 18, Tokens.text)
	modalText.Size, modalText.Position = UDim2.new(1, -32, 1, -100), UDim2.fromOffset(16, 16)
	modalText.Text =
		"원정 메뉴\n메뉴 중에도 서버 전투는 계속됩니다.\n임시 보상은 승리 기록 후 반영됩니다.\nA/D 이동 · 1/2/3 소환 · Q 시전"
	modalText.ZIndex = 11
	local close = button(modal, "CloseMenu", "전투로 돌아가기", Tokens.amber)
	close.ZIndex = 11
	close.Size, close.Position = UDim2.new(1, -32, 0, 48), UDim2.new(0, 16, 1, -64)
	local growth = Instance.new("ScrollingFrame")
	growth.Name, growth.BackgroundTransparency, growth.BorderSizePixel = "Growth", 1, 0
	growth.Position, growth.Size = UDim2.fromOffset(16, 88), UDim2.new(1, -32, 1, -168)
	growth.CanvasSize, growth.ScrollBarThickness = UDim2.fromOffset(0, 384), 4
	growth.ZIndex, growth.Visible, growth.Parent = 11, false, modal
	local growthButtons: { [string]: TextButton } = {}
	for index = 1, 6 do
		local action = if index <= 3
			then "Upgrade_" .. ORDER[index]
			else "Trait_" .. TRAITS[index - 3]
		local item = button(growth, action, "서버 프로필 대기", Tokens.teal)
		item.Position, item.Size = UDim2.fromOffset(0, (index - 1) * 64), UDim2.new(1, -8, 0, 56)
		item.ZIndex, item.TextSize = 12, 13
		growthButtons[action] = item
		table.insert(
			connections,
			item.Activated:Connect(function()
				if item.Active and model.phase == "LobbyReady" then
					onAction(action)
				end
			end)
		)
	end
	table.insert(
		connections,
		menu.Activated:Connect(function()
			modal.Visible = true
			onAction("Menu")
		end)
	)
	table.insert(
		connections,
		close.Activated:Connect(function()
			modal.Visible = false
			onAction("CloseMenu")
		end)
	)
	for slot = 1, 3 do
		local stageId = string.format("s%02d", slot)
		local item = button(stage, stageId, "원정 " .. slot, Tokens.teal)
		starts[slot] = item
		table.insert(
			connections,
			item.Activated:Connect(function()
				if item.Active and model.phase == "LobbyReady" then
					modal.Visible = false
					onAction("CloseMenu")
					onAction("Start_" .. stageId)
				end
			end)
		)
	end
	local retry = button(stage, "Retry", "원정 선택으로 돌아가기", Tokens.teal)
	retry.Visible = false
	table.insert(
		connections,
		retry.Activated:Connect(function()
			onAction("ReturnToLobby")
		end)
	)
	local controls = Instance.new("Frame")
	controls.Name, controls.Size, controls.BackgroundTransparency =
		"Controls", UDim2.fromScale(1, 1), 1
	controls.Parent = root
	local buttons: { [string]: GuiButton } = {
		Left = button(controls, "Left", "◀\nA / ←", Tokens.border),
		Right = button(controls, "Right", "▶\nD / →", Tokens.border),
		Cast = button(controls, "Cast", "등불 파동\nQ · 마나 10", Tokens.amber),
	}
	for slot = 1, 3 do
		buttons["Summon" .. slot] =
			button(controls, "Summon" .. slot, slot .. " · 소환", Tokens.teal)
	end
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "LanternClientVisuals", workspace
	local view, camera = EntityView.new(folder), CameraController.new()
	local floor: Part? = nil
	local layout = Layout.compute(1280, 720)
	local destroyed = false
	local function relayout()
		local size = root.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		layout = Layout.compute(size.X, size.Y)
		bounds(hud, layout.hud)
		bounds(stage, layout.stage)
		bounds(rotate, layout.rotateHint)
		rotate.Visible = layout.portrait and model.phase == "Running"
		for name, rect in layout.buttons do
			bounds(buttons[name], rect)
		end
		local hudWidth = layout.hud.width
		title.Position, title.Size = UDim2.fromOffset(12, 4), UDim2.fromOffset(hudWidth - 84, 26)
		menu.Position, menu.Size = UDim2.fromOffset(hudWidth - 60, 8), UDim2.fromOffset(48, 48)
		hp.Position, hp.Size =
			UDim2.fromOffset(12, 32),
			UDim2.fromOffset(hudWidth - 84, if layout.portrait then 40 else 24)
		resources.Position, resources.Size =
			UDim2.fromOffset(12, if layout.portrait then 74 else 58),
			UDim2.fromOffset(hudWidth - 24, 24)
		status.Position, status.Size =
			UDim2.fromOffset(12, if layout.portrait then 102 else 80),
			UDim2.fromOffset(hudWidth - 24, if layout.portrait then 38 else 22)
		stageTitle.Position, stageTitle.Size = UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 28)
		stageNote.Position, stageNote.Size = UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 28)
		for slot, item in starts do
			if layout.portrait then
				item.Position, item.Size =
					UDim2.fromOffset(12, 64 + (slot - 1) * 56), UDim2.new(1, -24, 0, 48)
			else
				local width = (layout.stage.width - 40) / 3
				item.Position, item.Size =
					UDim2.fromOffset(12 + (slot - 1) * (width + 8), 64), UDim2.fromOffset(width, 48)
			end
		end
		retry.Position, retry.Size = UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 48)
		local messageY = if layout.compact and not layout.portrait
			then layout.hud.y + layout.hud.height
			else if layout.portrait then layout.height - 184 else layout.height - 140
		message.Position, message.Size =
			UDim2.fromOffset(16, messageY),
			UDim2.fromOffset(
				layout.width - 32,
				if layout.compact and not layout.portrait then 20 else 28
			)
		modal.Size = UDim2.fromOffset(
			math.min(360, layout.width - 32),
			math.min(if model.phase == "LobbyReady" then 520 else 240, layout.height - 32)
		)
		modal.Position = UDim2.fromOffset(
			(layout.width - modal.Size.X.Offset) / 2,
			(layout.height - modal.Size.Y.Offset) / 2
		)
	end
	table.insert(connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
	local function update(nextModel: any)
		if destroyed then
			return
		end
		model = nextModel
		local running = model.phase == "Running"
		local lobby = model.phase == "LobbyReady"
		local profile = model.profileSummary or {}
		growth.Visible = lobby
		menu.Text, close.Text =
			if lobby then "성장" else "메뉴",
			if lobby then "닫기" else "전투로 돌아가기"
		modalText.Size, modalText.TextSize =
			if lobby then UDim2.new(1, -32, 0, 68) else UDim2.new(1, -32, 1, -100),
			if lobby then 14 else 18
		modalText.Text = if lobby
			then string.format(
				"성장 · %dG · Lv.%d\n누적 XP %d/%s · 남은 포인트 %d\n%s",
				profile.gold or 0,
				profile.heroLevel or 1,
				profile.totalXp or 0,
				tostring(profile.nextLevelXp or "MAX"),
				profile.unspentPoints or 0,
				if model.profileBusy
					then "서버 처리 중…"
					else "변경은 다음 원정부터 적용 · 서버 메모리"
			)
			else "원정 메뉴\n메뉴 중에도 서버 전투는 계속됩니다.\n임시 보상은 승리 기록 후 반영됩니다.\nA/D 이동 · 1/2/3 소환 · Q 시전"
		for _, id in ORDER do
			local item = growthButtons["Upgrade_" .. id]
			local def = ((model.catalog or {}).units or {})[id] or {}
			local cost = (profile.unitUpgradeCosts or {})[id]
			item.Text = string.format(
				"%s Lv.%d · %s",
				def.displayName or id,
				(profile.unitLevels or {})[id] or 1,
				if cost then string.format("강화 %dG", cost) else "최고 레벨"
			)
			item.Active = lobby
				and not model.profileBusy
				and cost ~= nil
				and (profile.gold or 0) >= cost
			item.Selectable, item.AutoButtonColor = item.Active, item.Active
			item.TextColor3 = if item.Active then Tokens.text else Tokens.muted
		end
		for _, id in TRAITS do
			local item = growthButtons["Trait_" .. id]
			local def = ((model.catalog or {}).traits or {})[id] or {}
			local points = (profile.heroTraits or {})[id] or 0
			item.Text = string.format(
				"%s %d/%d · +1 포인트\n%s",
				def.displayName or id,
				points,
				def.maxPoints or 3,
				def.description or ""
			)
			item.Active = lobby
				and not model.profileBusy
				and (profile.unspentPoints or 0) > 0
				and points < (def.maxPoints or 3)
			item.Selectable, item.AutoButtonColor = item.Active, item.Active
			item.TextColor3 = if item.Active then Tokens.text else Tokens.muted
		end
		local tick = model.tick or 0
		local seconds = math.floor(tick / 20)
		title.Text = if model.tick ~= nil
			then string.format(
				"등불 원정  /  %02d:%02d",
				math.floor(seconds / 60),
				seconds % 60
			)
			else "등불 원정  /  —:—"
		hp.Text = if model.heroHp ~= nil
			then string.format(
				"영웅 HP %d/%d   ·   핵 HP %d/%d",
				model.heroHp,
				model.heroMaxHp or 0,
				model.coreHp or 0,
				model.coreMaxHp or 0
			)
			else "영웅 HP —   ·   핵 HP —"
		resources.Text = if running or model.heroHp ~= nil
			then string.format(
				"식량 %s/%s   ·   마나 %s/%s",
				milli(model.foodMilli),
				milli(model.foodMaxMilli or 40000),
				milli(model.manaMilli),
				milli(model.manaMaxMilli or 100000)
			)
			else "식량 —   ·   마나 —"
		if lobby and model.profileSummary then
			hp.Text = string.format(
				"Lv.%d · 누적 XP %d/%s · 남은 포인트 %d",
				profile.heroLevel or 1,
				profile.totalXp or 0,
				tostring(profile.nextLevelXp or "MAX"),
				profile.unspentPoints or 0
			)
			resources.Text = string.format(
				"보유 골드 %dG · 성장 변경은 다음 원정부터",
				profile.gold or 0
			)
		end
		status.Text = if stageGameplay
			then string.format(
				"%s · %s | 임시 %dG / %dXP",
				model.storage or "서버 메모리",
				model.network or "연결 대기",
				model.pendingKillGold or 0,
				model.pendingKillXp or 0
			)
			else string.format(
				"%s · %s | 잠정 보상 %dG / %dXP",
				model.storage or "Mock/InMemory",
				model.network or "연결 대기",
				model.pendingKillGold or 0,
				model.pendingKillXp or 0
			)
		local outcomeText = ({
			Victory = "승리! 적 핵을 파괴했습니다",
			Defeat = "패배 · 영웅이 쓰러졌습니다",
			Timeout = "패배 · 제한 시간 종료",
		})[model.outcome]
		message.Text = if model.outcome
			then outcomeText or "전투 종료"
			elseif model.reason then (REASONS[model.reason] or tostring(model.reason))
			elseif
				stageGameplay and running
			then "A/D 이동 · 1/2/3 소환 · Q 시전 · 적 핵 파괴 시 승리"
			else ""
		controls.Visible = running
		stage.Visible = not running
		stageTitle.Text = ({
			LobbyReady = "다음 원정을 선택하세요",
			Preparing = "원정을 준비합니다",
			Settling = "전투 종료 · 정산 대기",
			Settled = "서버 결과 확인",
			Unavailable = "원정을 시작할 수 없습니다",
		})[model.phase] or "서버 연결을 기다립니다"
		if model.outcome then
			stageTitle.Text = outcomeText or "전투 종료"
		end
		stageNote.Text = if model.phase == "LobbyReady"
			then (if stageGameplay
				then (if model.profileBusy
					then "서버 처리 중 · 원정 시작 잠금"
					else "우측 상단 성장 · 서버 종료 시 초기화")
				else "Mock/InMemory · 영구 저장 아님")
			else tostring(model.phase or "연결 대기") .. " · " .. tostring(
				model.network or "대기"
			)
		if model.outcome and stageGameplay then
			stageNote.Text = ({
				Pending = "결과 기록 중 · 다음 경기 잠금",
				Committed = if model.rewards
					then string.format(
						"기록 완료 · +%dG / +%dXP · 서버 메모리",
						model.rewards.gold,
						model.rewards.xp
					)
					else "기록 완료 · 서버 메모리",
				Failed = "기록 실패 · 다음 경기 잠금",
			})[model.settlementStatus] or "결과 확인 중"
		end
		local catalog = model.catalog or {}
		local progress = model.stageProgress or {}
		for slot, item in starts do
			local id = string.format("s%02d", slot)
			local previous = string.format("s%02d", slot - 1)
			local previousProgress = progress[previous]
			local unlocked = if profile.unlockedStages
				then profile.unlockedStages[id]
				else slot == 1
					or (type(previousProgress) == "table" and (previousProgress.wins or 0) > 0)
			local def = (catalog.stages or {})[id] or {}
			item.Text = string.format(
				"%02d  %s%s",
				slot,
				def.displayName or "원정",
				if unlocked then "" else " · 잠김"
			)
			item.Active, item.Selectable =
				lobby and unlocked and not model.profileBusy,
				lobby and unlocked and not model.profileBusy
			local record = progress[id]
			if record and record.wins > 0 then
				item.Text ..= string.format(
					"\n승리 %d · 최고 %.1f초",
					record.wins,
					(record.bestTicks or 0) / 20
				)
			end
			item.TextColor3 = if item.Active then Tokens.text else Tokens.muted
			item.Visible = not model.outcome
		end
		retry.Visible = stageGameplay == true and model.phase == "Settled"
		for slot, id in ORDER do
			local def = (catalog.units or {})[id] or {}
			local item = buttons["Summon" .. slot] :: TextButton
			item.TextSize = 12
			local ready = (model.summonReadyTick or {})[slot]
			item.Text = string.format(
				"%d · %s\n식량 %s · %s",
				slot,
				def.displayName or "소환",
				tostring(def.foodCost or "—"),
				cooldown(ready, tick)
			)
		end
		local skill = (catalog.skills or {}).pulse or {}
		local heroAction = model.heroAction or {}
		local castState = if heroAction.endTick and tick < heroAction.endTick
			then "시전 중"
			else cooldown(model.skillReadyTick, tick)
		local castButton = buttons.Cast :: TextButton
		castButton.Text = string.format(
			"Q · %s\n마나 %s · %s",
			skill.displayName or "등불 파동",
			tostring(skill.manaCost or "—"),
			castState
		)
		relayout()
	end
	local function render(frame: any, _dt: number)
		if destroyed then
			return
		end
		if not frame or #(frame.entities or {}) == 0 then
			view.clear()
			if floor then
				floor:Destroy()
				floor = nil
			end
			return
		end
		view.sync(frame.entities or {}, frame.projectiles or {})
		local length = frame.stageLength or 100
		if not floor then
			floor = EntityView.part(
				folder,
				"ExpeditionGround",
				Vector3.new(length, 0.25, 8),
				Tokens.panel
			)
		end
		assert(floor, "floor initialized")
		floor.Size, floor.CFrame =
			Vector3.new(math.max(1, length), 0.25, 8), CFrame.new(length / 2, -0.25, 0)
		camera.update(frame.heroX or 0, length)
	end
	local function inspect(): any
		local function metrics(item: GuiObject): any
			local visible = item.Visible
			local ancestor = item.Parent
			while ancestor and ancestor ~= gui do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then
					visible = false
				end
				ancestor = ancestor.Parent
			end
			return {
				x = item.AbsolutePosition.X,
				y = item.AbsolutePosition.Y,
				width = item.AbsoluteSize.X,
				height = item.AbsoluteSize.Y,
				visible = visible,
			}
		end
		local rects: { [string]: any } = {}
		for name, item in buttons do
			rects[name] = {
				x = item.AbsolutePosition.X,
				y = item.AbsolutePosition.Y,
				width = item.AbsoluteSize.X,
				height = item.AbsoluteSize.Y,
				visible = controls.Visible and item.Visible,
			}
		end
		local stages: { [string]: any } = {}
		for slot, item in starts do
			local entry = metrics(item)
			entry.active = item.Active
			stages[string.format("Start_s%02d", slot)] = entry
		end
		return {
			safeArea = metrics(root),
			stageButtons = stages,
			menuButton = metrics(menu),
			closeMenuButton = metrics(close),
			stageBounds = metrics(stage),
			controlsVisible = controls.Visible,
			width = root.AbsoluteSize.X,
			height = root.AbsoluteSize.Y,
			portrait = layout.portrait,
			buttons = rects,
			phase = model.phase,
			hudText = title.Text
				.. "\n"
				.. hp.Text
				.. "\n"
				.. resources.Text
				.. "\n"
				.. status.Text,
			reasonText = message.Text,
			stageVisible = stage.Visible,
			menuVisible = modal.Visible,
			growthVisible = modal.Visible and growth.Visible,
			rotateHintVisible = rotate.Visible,
			entities = view.inspect(),
			visualCount = #folder:GetDescendants(),
		}
	end
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		view.clear()
		camera.destroy()
		folder:Destroy()
		gui:Destroy()
	end
	update(model)
	return {
		buttons = buttons,
		update = update,
		render = render,
		inspect = inspect,
		destroy = destroy,
	}
end
return table.freeze({ new = new })
