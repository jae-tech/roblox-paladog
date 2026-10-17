--!strict
-- Root of the remake UI: one ScreenGui holding the battlefield, the battle HUD and the lobby.
local Field = require("./WorldView")
local Hud = require("./Hud")
local Lobby = require("./Lobby")
local Theme = require("./Theme")
local Widgets = require("./Widgets")
local Text = require("./Text")

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
	{ "Units", "용병" },
	{ "Equipment", "장비·상점" },
	{ "Skills", "기술" },
	{ "Achievements", "업적" },
	{ "Records", "기록" },
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
	-- plaza guide: who you are and where the dungeon entrance is, shown while walking around
	local guide = Widgets.card(gui, "PlazaGuide", Theme.panelDeep, 12)
	guide.BackgroundTransparency = 0.2
	guide.Size = UDim2.fromOffset(260, 64)
	guide.Position = UDim2.fromOffset(10, 10)
	guide.Visible = false
	local guideTitle = Widgets.label(guide, "Title", "등불 원정 · 광장", 16, Theme.gold)
	guideTitle.Font = Theme.fontHeavy
	guideTitle.Size = UDim2.new(1, -20, 0, 22)
	guideTitle.Position = UDim2.fromOffset(10, 6)
	guideTitle.TextXAlignment = Enum.TextXAlignment.Left
	local guideBody = Widgets.label(guide, "Body", "", 13, Theme.text)
	guideBody.Font = Theme.fontBody
	guideBody.Size = UDim2.new(1, -20, 1, -34)
	guideBody.Position = UDim2.fromOffset(10, 28)
	guideBody.TextXAlignment = Enum.TextXAlignment.Left
	guideBody.TextYAlignment = Enum.TextYAlignment.Top
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
	for i, entry in PLAZA_MENU do
		local b = Widgets.button(menuBar, entry[1], entry[2], 15)
		b.Size = UDim2.new(1, -12, 0, 36)
		b.Position = UDim2.fromOffset(6, 6 + (i - 1) * 42)
		b.Activated:Connect(function()
			openTown(entry[1])
		end)
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
			if walking then
				local slot = model.slot
				guideBody.Text = (
					if slot
						then string.format(
							"%s Lv.%d · %sG\n",
							catalog.heroNames[slot.heroKind],
							slot.level,
							Text.number(slot.gold)
						)
						else ""
				)
					.. "원정은 보라색 던전 입구에서,\n용병·장비·기술은 오른쪽 메뉴에서"
				guide.Size = UDim2.fromOffset(260, if slot then 96 else 80)
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
		end,
	}
end

return table.freeze({ new = new })
