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
}

local BATTLE_PHASES = { Running = true, Settling = true, Settled = true }

local function new(playerGui: PlayerGui, catalog: any, handlers: Handlers)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LanternExpedition"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
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
	guideBody.Size = UDim2.new(1, -20, 0, 32)
	guideBody.Position = UDim2.fromOffset(10, 28)
	guideBody.TextXAlignment = Enum.TextXAlignment.Left
	guideBody.TextYAlignment = Enum.TextYAlignment.Top
	local phase = "ProfileLoading"
	local stage = 1

	return {
		gui = gui,
		moveButtons = hud.moveButtons,
		update = function(model: any)
			phase = model.phase
			stage = model.stage or stage
			field.root.Visible = BATTLE_PHASES[phase] == true
			if not field.root.Visible then
				field.clear()
			end
			local walking = model.menuVisible == false and not BATTLE_PHASES[phase]
			guide.Visible = walking
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
				) .. "보라색 던전 입구에서 원정을 시작하세요"
				guide.Size = UDim2.fromOffset(260, if slot then 78 else 64)
			end
			hud.update(model)
			lobby.update(model)
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
		end,
	}
end

return table.freeze({ new = new })
