--!strict
-- Root of the remake UI: one ScreenGui holding the battlefield, the battle HUD and the lobby.
local Field = require("./Field")
local Hud = require("./Hud")
local Lobby = require("./Lobby")

export type Handlers = {
	battle: (string, { [string]: any }?) -> (),
	lobby: (string, { [string]: any }?) -> (),
	start: (number) -> (),
	returnToLobby: () -> (),
}

local BATTLE_PHASES = { Running = true, Settling = true, Settled = true }

local function new(playerGui: PlayerGui, catalog: any, handlers: Handlers)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LanternExpedition"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local field = Field.new(gui)
	local hud =
		Hud.new(gui, catalog, { battle = handlers.battle, returnToLobby = handlers.returnToLobby })
	local lobby = Lobby.new(gui, catalog, { lobby = handlers.lobby, start = handlers.start })
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
