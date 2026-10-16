--!strict
-- Plaza / expedition menu / battle presentation state (R8, D-PLAZA-01). Pure: Runtime applies it.
-- Players walk their avatar in the plaza; the dungeon entrance opens the expedition menu (lobby); a match
-- takes over the screen. Avatar controls are off whenever the menu or a battle owns the input.
local BATTLE: { [string]: boolean } = { Running = true, Settling = true, Settled = true }
local MENU: { [string]: boolean } =
	{ LobbyReady = true, Preparing = true, ProfileLoading = true, Unavailable = true }

export type View = { inBattle: boolean, menuVisible: boolean, controlsEnabled: boolean }

local function view(phase: string?, menuOpen: boolean): View
	local inBattle = phase ~= nil and BATTLE[phase] == true
	-- storage failures stay visible so the player knows progress is not loading
	local menuVisible = not inBattle
		and phase ~= nil
		and MENU[phase] == true
		and (menuOpen or phase == "Unavailable")
	return {
		inBattle = inBattle,
		menuVisible = menuVisible,
		controlsEnabled = not inBattle and not menuVisible,
	}
end

return table.freeze({ view = view })
