--!strict
-- Production client composition (remake): server remotes, controller, input and the remake UI.
-- No mock store or debug endpoint: the client waits for real server remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ActionRouter = require("./Input/ActionRouter")
local AutoAssist = require("./Input/AutoAssist")
local DeviceAdapter = require("./Input/DeviceAdapter")
local ClientController = require("./Net/ClientController")
local Ui = require("./Presentation/Ui")
local PlazaState = require("./Presentation/PlazaState")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")

local active: any = nil
local function start(): any
	if active then
		return active
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local protocol = require(ReplicatedStorage.Shared.Protocol)
	local catalog = require(ReplicatedStorage.Shared.RemakeCatalog)
	local folder: Instance? = nil
	local connections: { RBXScriptConnection } = {}
	local remoteConnections: { RBXScriptConnection } = {}
	local destroyed = false
	local function send(channel: string, payload: any)
		local event = if folder then folder:FindFirstChild(channel) else nil
		if event and event:IsA("RemoteEvent") then
			event:FireServer(payload)
		end
	end
	local function makeController(): any
		return ClientController.new({
			protocol = protocol,
			send = send,
			requestId = function()
				return HttpService:GenerateGUID(false)
			end,
		})
	end
	local controller = makeController()
	local lastUnit = 1
	local menuOpen = false -- R8: the dungeon entrance (expeditions) or a plaza menu button (the rest)
	-- Avatar movement: locked (0) while the menu or a non-avatar battle owns input; inside an arena the
	-- server-chosen ArenaWalkSpeed matches the hero; otherwise the place defaults. The client owns its
	-- character physics, so the local Humanoid values are what count (the server leashes the result).
	local StarterPlayer = game:GetService("StarterPlayer")
	local function setControls(enabled: boolean)
		-- the touch thumbstick/jump button would sit on top of the menu and battle buttons
		if GuiService.TouchControlsEnabled ~= enabled then
			GuiService.TouchControlsEnabled = enabled
		end
		local player = Players.LocalPlayer
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local arenaSpeed = player:GetAttribute("ArenaWalkSpeed")
		local walk = if not enabled
			then 0
			elseif type(arenaSpeed) == "number" then arenaSpeed
			else StarterPlayer.CharacterWalkSpeed
		local jump = if enabled then StarterPlayer.CharacterJumpHeight else 0
		local power = if enabled then StarterPlayer.CharacterJumpPower else 0
		if humanoid.WalkSpeed ~= walk then
			humanoid.WalkSpeed = walk
		end
		if humanoid.JumpHeight ~= jump then
			humanoid.JumpHeight = jump
		end
		if humanoid.JumpPower ~= power then
			humanoid.JumpPower = power
		end
	end
	local auto = AutoAssist.new(catalog)
	-- Summon/weapon presses toggle that slot's auto (D-AUTO-01) in plain battle modes; others pass through.
	local function press(kind: string, fields: any, now: number)
		local model = controller.model(now)
		local mode = model.battle and model.battle.mode
		if
			(kind == "Summon" or kind == "Mace")
			and fields
			and model.phase == "Running"
			and auto.eligible(mode)
		then
			auto.toggle(kind, if kind == "Summon" then fields.unit else fields.slot)
			return
		end
		controller.battle(kind, fields, now)
	end
	local ui = Ui.new(playerGui, catalog, {
		battle = function(kind, fields)
			if fields and kind == "Summon" then
				lastUnit = fields.unit or lastUnit
			end
			press(kind, fields, os.clock())
		end,
		lobby = function(kind, fields)
			controller.lobby(kind, fields, os.clock())
		end,
		purchase = function(item)
			controller.purchase(item, os.clock())
		end,
		speed = function(speed)
			controller.setSpeed(speed, os.clock())
		end,
		start = function(stage)
			controller.start(stage, os.clock())
		end,
		returnToLobby = function()
			controller.returnToLobby(os.clock())
		end,
		closeMenu = function()
			menuOpen = false
		end,
		openMenu = function()
			menuOpen = true
		end,
	})
	local router = ActionRouter.new({
		onAxis = function(_axis) end,
		onMove = function(axis, strafe)
			controller.move(axis, os.clock(), strafe)
		end,
		onAction = function(action)
			local now = os.clock()
			local summon = tonumber(string.match(action, "^Summon(%d)$"))
			local mace = tonumber(string.match(action, "^Mace(%d)$"))
			local model = controller.model(now)
			local tower = model.battle and model.battle.mode == "Tower"
			if action == "Jump" then
				if model.battle and model.battle.mode == "Jump" then
					controller.battle("Jump", nil, now)
				end
			elseif summon and model.battle and model.battle.mode == "Destiny" then
				-- destiny has no summon buttons: number keys open the matching fate box
				controller.battle("Box", { index = summon }, now)
			elseif summon then
				lastUnit = summon
				-- Keyboard summons in the tower use the middle lane; the lane picker covers touch.
				press("Summon", { unit = summon, lane = if tower then 3 else 0 }, now)
			elseif mace then
				press("Mace", { slot = mace, unit = lastUnit, lane = if tower then 3 else 0 }, now)
			end
		end,
	})
	router.setBlocked("transport", true)
	local adapter = DeviceAdapter.new(router, ui.moveButtons)
	local function detach()
		router.setBlocked("transport", true)
		for _, connection in remoteConnections do
			connection:Disconnect()
		end
		table.clear(remoteConnections)
		folder = nil
		controller.destroy()
		controller = makeController()
	end
	local function attach(candidate: Instance)
		if candidate.Name ~= "Remotes" or folder then
			return
		end
		local snapshot = candidate:FindFirstChild("MatchSnapshot")
		local message = candidate:FindFirstChild("ServerMessage")
		local bootstrap = candidate:FindFirstChild("GetBootstrap")
		if
			not snapshot
			or not snapshot:IsA("RemoteEvent")
			or not message
			or not message:IsA("RemoteEvent")
			or not bootstrap
			or not bootstrap:IsA("RemoteFunction")
		then
			return
		end
		folder = candidate
		table.insert(
			remoteConnections,
			snapshot.OnClientEvent:Connect(function(payload)
				controller.receiveSnapshot(payload, os.clock())
			end)
		)
		table.insert(
			remoteConnections,
			message.OnClientEvent:Connect(function(payload)
				controller.receiveMessage(payload, os.clock())
			end)
		)
		table.insert(
			remoteConnections,
			candidate.AncestryChanged:Connect(function()
				if candidate.Parent ~= ReplicatedStorage then
					detach()
				end
			end)
		)
		router.setBlocked("transport", false)
	end
	local hudAt = -math.huge
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			local now = os.clock()
			controller.step(now)
			if folder and controller.needsBootstrap(now) then
				local token = controller.beginBootstrap(now)
				local bootstrap = folder:FindFirstChild("GetBootstrap")
				if token and bootstrap and bootstrap:IsA("RemoteFunction") then
					local requesting = controller
					task.spawn(function()
						local ok, payload = pcall(function()
							return bootstrap:InvokeServer({ protocolVersion = protocol.VERSION })
						end)
						if not destroyed and controller == requesting then
							requesting.finishBootstrap(
								token,
								if ok then payload else nil,
								os.clock()
							)
						end
					end)
				end
			end
			local model = controller.model(now)
			router.setBlocked("phase", model.phase ~= "Running")
			router.setBlocked("network", model.network ~= "연결됨")
			router.setBlocked(
				"modal",
				model.battle ~= nil
					and (model.battle.offer ~= nil or model.battle.reviveOffer == true)
			)
			router.step(now)
			local avatarCombat = Players.LocalPlayer:GetAttribute("ArenaOrigin") ~= nil
			local plaza = PlazaState.view(model.phase, menuOpen, avatarCombat)
			model.menuVisible = plaza.menuVisible
			model.avatarCombat = avatarCombat and plaza.inBattle
			setControls(plaza.controlsEnabled)
			-- outside battles every key is Roblox's; in avatar combat only the movement keys are
			adapter.setPassive(
				if not plaza.inBattle then "all" elseif avatarCombat then "movement" else "none"
			)
			if model.battle and model.phase == "Running" and not router.inspect().blocked then
				for _, d in auto.decide(model.battle, model.slot, now) do
					if d.kind == "Summon" then
						controller.battle("Summon", { unit = d.unit, lane = 0 }, now)
					else
						controller.battle("Mace", { slot = d.slot, unit = lastUnit, lane = 0 }, now)
					end
				end
			end
			-- D-DIFF-01: no record screen; the first record is picked or made (쉬움) automatically
			if model.phase == "LobbyReady" and model.summary and not model.slot then
				local pick = 0
				for index, slot in model.summary.slots do
					if slot and pick == 0 then
						pick = index
					end
				end
				if pick > 0 then
					controller.lobby("SelectSlot", { slot = pick }, now)
				else
					controller.lobby(
						"CreateSlot",
						{ slot = 1, heroKind = "light", difficulty = 0 },
						now
					)
				end
			end
			if now - hudAt >= 0.1 then
				model.auto = auto.state()
				ui.update(model)
				hudAt = now
			end
			ui.render(controller.frame(now), dt)
		end)
	)
	-- Entering an arena: start the Roblox camera behind the character, looking down the dungeon (+X).
	table.insert(
		connections,
		Players.LocalPlayer:GetAttributeChangedSignal("ArenaOrigin"):Connect(function()
			local origin = Players.LocalPlayer:GetAttribute("ArenaOrigin")
			if typeof(origin) ~= "Vector3" then
				return
			end
			task.spawn(function()
				local character = Players.LocalPlayer.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local camera = workspace.CurrentCamera
				-- the server's teleport can land a few frames after the attribute
				for _ = 1, 40 do
					if
						not rootPart
						or not rootPart:IsA("BasePart")
						or (rootPart.Position - origin).Magnitude < 250
					then
						break
					end
					task.wait(0.05)
				end
				if rootPart and rootPart:IsA("BasePart") and camera then
					local at = rootPart.Position
					camera.CFrame =
						CFrame.lookAt(at + Vector3.new(-14, 7, 0), at + Vector3.new(12, 0, 0))
				end
			end)
		end)
	)
	table.insert(
		connections,
		ProximityPromptService.PromptTriggered:Connect(function(prompt)
			if prompt:GetAttribute("DungeonEntrance") == true then
				ui.openDungeon()
				menuOpen = true
			end
		end)
	)
	table.insert(connections, ReplicatedStorage.ChildAdded:Connect(attach))
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		attach(existing)
	end
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		GuiService.TouchControlsEnabled = true
		adapter.destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, connection in remoteConnections do
			connection:Disconnect()
		end
		controller.destroy()
		ui.destroy()
		active = nil
	end
	active = {
		inspect = function(): any
			return {
				input = router.inspect(),
				controller = controller.inspect(os.clock()),
				model = controller.model(os.clock()),
				ui = ui.inspect(),
			}
		end,
		destroy = destroy,
	}
	return active
end

return table.freeze({
	start = start,
	inspect = function(): any
		return if active then active.inspect() else nil
	end,
	destroy = function()
		if active then
			active.destroy()
		end
	end,
})
