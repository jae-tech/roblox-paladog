--!strict
-- Plaza / expedition menu / battle presentation state (R8, D-PLAZA-01). Pure: Runtime applies it.
-- Players walk their avatar in the plaza; the dungeon entrance opens the expedition menu (lobby); a match
-- takes over the screen. Avatar controls are off whenever the menu or a battle owns the input.
local BATTLE: { [string]: boolean } = { Running = true, Settling = true, Settled = true }
local MENU: { [string]: boolean } =
	{ LobbyReady = true, Preparing = true, ProfileLoading = true, Unavailable = true }

export type View = { inBattle: boolean, menuVisible: boolean, controlsEnabled: boolean }

-- avatarCombat: the real character is in a battle arena and walks with Roblox controls (D-PLAZA-03).
local function view(phase: string?, menuOpen: boolean, avatarCombat: boolean?): View
	local inBattle = phase ~= nil and BATTLE[phase] == true
	-- storage failures stay visible so the player knows progress is not loading
	local menuVisible = not inBattle
		and phase ~= nil
		and MENU[phase] == true
		and (menuOpen or phase == "Unavailable")
	return {
		inBattle = inBattle,
		menuVisible = menuVisible,
		controlsEnabled = (not inBattle and not menuVisible)
			or (avatarCombat == true and phase == "Running"),
	}
end

-- The dungeon entrance only starts expeditions; upgrades, gear, skills, achievements and heroes open
-- from the plaza menu. Without a record (made automatically, D-DIFF-01) either menu shows only "Heroes".
local TOWN = table.freeze({ "Units", "Equipment", "Skills", "Achievements", "Heroes" })
local DUNGEON = table.freeze({ "Stages" })
local NO_RECORD = table.freeze({ "Heroes" })

local function tabs(mode: string?, hasSlot: boolean): { string }
	if not hasSlot then
		return NO_RECORD
	end
	return if mode == "dungeon" then DUNGEON else TOWN
end

-- the tab to show: the wanted one when that menu has it, else the menu's first tab
local function landing(mode: string?, hasSlot: boolean, wanted: string?): string
	local list = tabs(mode, hasSlot)
	if wanted and table.find(list, wanted) then
		return wanted
	end
	return list[1]
end

return table.freeze({ view = view, tabs = tabs, landing = landing })
