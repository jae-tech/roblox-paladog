--!strict
-- Root of the remake UI: one ScreenGui holding the battlefield, the battle HUD and the lobby.
local Field = require("./WorldView")
local Hud = require("./Hud")
local Lobby = require("./Lobby")
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type Handlers = {
	battle: (string, { [string]: any }?) -> (),
	lobby: (string, { [string]: any }?) -> (),
	start: (number) -> (),
	returnToLobby: () -> (),
	closeMenu: (() -> ())?,
	openMenu: (() -> ())?,
}

local BATTLE_PHASES = { Running = true, Settling = true, Settled = true }
-- plaza menu buttons: everything except expeditions, which start at the dungeon entrance
local PLAZA_MENU = {
	{ "Units", "용병", "⚔" },
	{ "Equipment", "장비·상점", "🛡" },
	{ "Skills", "기술", "📜" },
	{ "Achievements", "업적", "🏆" },
	{ "Heroes", "영웅", "👤" },
}

local function new(playerGui: PlayerGui, catalog: any, handlers: Handlers)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LanternExpedition"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	-- the menu also covers the Roblox top bar strip, which the safe-inset gui above cannot reach
	local backdropGui = Instance.new("ScreenGui")
	backdropGui.Name = "LanternBackdrop"
	backdropGui.ResetOnSpawn = false
	backdropGui.ScreenInsets = Enum.ScreenInsets.None
	backdropGui.DisplayOrder = -1
	backdropGui.Parent = playerGui
	local backdrop = Widgets.frame(backdropGui, "Backdrop", Theme.backgroundTop)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Visible = false
	local field = Field.new(gui, catalog)
	local hud =
		Hud.new(gui, catalog, { battle = handlers.battle, returnToLobby = handlers.returnToLobby })
	local lobby = Lobby.new(
		gui,
		catalog,
		{ lobby = handlers.lobby, start = handlers.start, close = handlers.closeMenu }
	)
	-- plaza player card: hero, level, difficulty and progress, money, EXP
	local guide = Widgets.card(gui, "PlazaGuide", Theme.panelDeep, 14)
	guide.BackgroundTransparency = 0.12
	guide.Size = UDim2.fromOffset(300, 128)
	guide.Position = UDim2.fromOffset(10, 10)
	guide.Visible = false
	Widgets.outline(guide, Theme.gold, 1, 0.55)
	local levelBadge = Widgets.frame(guide, "Level", Theme.gold, 12)
	levelBadge.Size = UDim2.fromOffset(52, 52)
	levelBadge.Position = UDim2.fromOffset(12, 12)
	Widgets.sheen(levelBadge, 0.6)
	local levelText = Widgets.label(levelBadge, "Text", "", 18, Theme.ink)
	levelText.Font = Theme.fontHeavy
	levelText.Size = UDim2.fromScale(1, 1)
	local guideTitle = Widgets.label(guide, "Title", "", 17, Theme.text)
	guideTitle.Font = Theme.fontHeavy
	guideTitle.Size = UDim2.fromOffset(160, 24)
	guideTitle.Position = UDim2.fromOffset(74, 10)
	guideTitle.TextXAlignment = Enum.TextXAlignment.Left
	local tierBack, tierText = Widgets.pill(guide, "Tier", "", 12, Theme.panelLight, Theme.gold)
	tierBack.Size = UDim2.fromOffset(62, 22)
	tierBack.Position = UDim2.new(1, -74, 0, 12)
	local guideBody = Widgets.label(guide, "Body", "", 13, Theme.muted)
	guideBody.Font = Theme.fontBody
	guideBody.Size = UDim2.fromOffset(214, 20)
	guideBody.Position = UDim2.fromOffset(74, 36)
	guideBody.TextXAlignment = Enum.TextXAlignment.Left
	local expBack, setExp = Widgets.bar(guide, "Exp", Theme.good)
	expBack.Size = UDim2.fromOffset(214, 10)
	expBack.Position = UDim2.fromOffset(74, 60)
	local money = Widgets.label(guide, "Money", "", 14, Theme.gold)
	money.Size = UDim2.fromOffset(276, 20)
	money.Position = UDim2.fromOffset(12, 76)
	money.TextXAlignment = Enum.TextXAlignment.Left
	local hint = Widgets.label(guide, "Hint", "", 12, Theme.muted)
	hint.Font = Theme.fontBody
	hint.Size = UDim2.fromOffset(276, 20)
	hint.Position = UDim2.fromOffset(12, 100)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	-- marker over the dungeon entrance with the walking distance
	local marker = Instance.new("BillboardGui")
	marker.Name = "DungeonMarker"
	marker.Size = UDim2.fromOffset(150, 46)
	marker.StudsOffset = Vector3.new(0, 13, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 400
	marker.Enabled = false
	marker.ResetOnSpawn = false
	marker.Parent = playerGui -- billboards do not render inside a ScreenGui
	local markerCard = Widgets.card(marker, "Card", Theme.panelDeep, 12)
	markerCard.Size = UDim2.fromScale(1, 1)
	markerCard.BackgroundTransparency = 0.15
	Widgets.outline(markerCard, Color3.fromRGB(170, 120, 255), 2, 0.1)
	local markerTitle = Widgets.label(markerCard, "Title", "⚔ 원정 출발", 15, Theme.gold)
	markerTitle.Font = Theme.fontHeavy
	markerTitle.Size = UDim2.new(1, 0, 0, 24)
	markerTitle.Position = UDim2.fromOffset(0, 3)
	local markerDistance = Widgets.label(markerCard, "Distance", "", 12, Theme.text)
	markerDistance.Font = Theme.fontBody
	markerDistance.Size = UDim2.new(1, 0, 0, 16)
	markerDistance.Position = UDim2.fromOffset(0, 26)
	-- plaza menu: a column on the right, clear of the touch jump button at the bottom
	local menuBar = Widgets.card(gui, "PlazaMenu", Theme.panelDeep, 12)
	menuBar.BackgroundTransparency = 0.2
	menuBar.Size = UDim2.fromOffset(124, 12 + #PLAZA_MENU * 42)
	menuBar.Position = UDim2.new(1, -134, 0, 10)
	menuBar.Visible = false
	local function openTown(screen: string)
		lobby.open("town", screen)
		if handlers.openMenu then
			handlers.openMenu()
		end
	end
	local badges: { [string]: TextLabel } = {}
	for i, entry in PLAZA_MENU do
		local b = Widgets.button(menuBar, entry[1], "", 15)
		b.Size = UDim2.new(1, -12, 0, 36)
		b.Position = UDim2.fromOffset(6, 6 + (i - 1) * 42)
		local icon = Widgets.label(b, "Icon", entry[3], 16, Theme.gold)
		icon.Size = UDim2.fromOffset(30, 36)
		icon.Position = UDim2.fromOffset(4, 0)
		local text = Widgets.label(b, "Label", entry[2], 15, Theme.text)
		text.Size = UDim2.new(1, -38, 1, 0)
		text.Position = UDim2.fromOffset(34, 0)
		text.TextXAlignment = Enum.TextXAlignment.Left
		-- red count: something to do on that screen (free skill points, affordable upgrades)
		local badge = Widgets.label(b, "Badge", "", 12, Color3.new(1, 1, 1))
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Theme.bad
		badge.Size = UDim2.fromOffset(20, 20)
		badge.Position = UDim2.new(1, -14, 0, -6)
		badge.Visible = false
		badge.ZIndex = 5
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = badge
		badges[entry[1]] = badge
		b.Activated:Connect(function()
			openTown(entry[1])
		end)
	end
	local function setBadge(name: string, count: number)
		local badge = badges[name]
		badge.Visible = count > 0
		badge.Text = if count > 9 then "9+" else tostring(count)
	end
	local phase = "ProfileLoading"
	local stage = 1

	return {
		gui = gui,
		moveButtons = hud.moveButtons,
		-- the dungeon entrance opens the expedition menu only
		openDungeon = function()
			lobby.open("dungeon", "Stages")
		end,
		update = function(model: any)
			phase = model.phase
			stage = model.stage or stage
			field.root.Visible = BATTLE_PHASES[phase] == true
			if not field.root.Visible then
				field.clear()
			end
			local walking = model.menuVisible == false and not BATTLE_PHASES[phase]
			guide.Visible = walking
			menuBar.Visible = walking
			local plaza = Workspace:FindFirstChild("Plaza")
			local found = plaza and plaza:FindFirstChild("DungeonPortal")
			local portal: BasePart? = if found and found:IsA("BasePart") then found else nil
			marker.Adornee = portal :: any
			marker.Enabled = walking and portal ~= nil
			if walking then
				local slot = model.slot
				local summary = model.summary
				if slot then
					local best, cleared = 0, 0
					for index, star in slot.stars do
						if star >= 1 then
							cleared += 1
							best = math.max(best, index)
						end
					end
					levelText.Text = "Lv." .. slot.level
					guideTitle.Text = catalog.heroNames[slot.heroKind] or ""
					tierText.Text = catalog.text.difficulty[slot.difficulty + 1] or ""
					guideBody.Text = if best > 0
						then string.format(
							"최고 %s · %d/120 클리어",
							Text.stageLabel(best),
							cleared
						)
						else "첫 원정: 1-1에 도전하세요"
					local need = slot.nextLevelExp
					local floor = (slot.level - 1) * (slot.level - 1) * 100
					setExp(
						if need then (slot.exp - floor) / math.max(1, need - floor) else 1,
						if need then "EXP " .. Text.number(slot.exp - floor) else "MAX"
					)
					money.Text = string.format(
						"%s G   ◆ %s",
						Text.number(slot.gold),
						Text.number(summary and summary.gems or 0)
					)
					hint.Text = "원정: 던전 입구(E) · 강화·장비: 오른쪽 메뉴"
					-- badges: unspent skill points; mercenaries the gold already pays for
					setBadge("Skills", slot.freePoints or 0)
					setBadge("Units", Text.affordableUnits(catalog, slot))
				else
					levelText.Text = "…"
					guideTitle.Text = "원정 준비 중"
					tierText.Text = ""
					guideBody.Text = "첫 원정을 준비하고 있습니다"
					setExp(0, "")
					money.Text = ""
					hint.Text = ""
				end
				local character = Players.LocalPlayer and Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and portal then
					local distance = (root.Position - portal.Position).Magnitude
					markerDistance.Text = if distance < 14
						then "E를 눌러 입장"
						else string.format("%dm", math.floor(distance))
				end
			end
			hud.update(model)
			lobby.update(model)
			backdrop.Visible = lobby.root.Visible
		end,
		render = function(view: any, dt: number)
			if BATTLE_PHASES[phase] then
				field.render(view, (math.max(stage, 1) - 1) // 24 + 1, dt)
			end
		end,
		inspect = function(): any
			return {
				phase = phase,
				renderer = "3D",
				fieldEntities = field.count(),
				hud = hud.inspect(),
				lobby = lobby.inspect(),
			}
		end,
		destroy = function()
			field.destroy()
			hud.destroy()
			lobby.destroy()
			gui:Destroy()
			backdropGui:Destroy()
			marker:Destroy()
		end,
	}
end

return table.freeze({ new = new })
