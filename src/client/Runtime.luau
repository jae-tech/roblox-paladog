--!strict
-- Production client composition (remake): server remotes, controller, input and the remake UI.
-- No mock store or debug endpoint: the client waits for real server remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ActionRouter = require("./Input/ActionRouter")
local DeviceAdapter = require("./Input/DeviceAdapter")
local ClientController = require("./Net/ClientController")
local Ui = require("./Presentation/Ui")

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
	local ui = Ui.new(playerGui, catalog, {
		battle = function(kind, fields)
			if fields and kind == "Summon" then
				lastUnit = fields.unit or lastUnit
			end
			controller.battle(kind, fields, os.clock())
		end,
		lobby = function(kind, fields)
			controller.lobby(kind, fields, os.clock())
		end,
		start = function(stage)
			controller.start(stage, os.clock())
		end,
		returnToLobby = function()
			controller.returnToLobby(os.clock())
		end,
	})
	local router = ActionRouter.new({
		onAxis = function(axis)
			controller.move(axis, os.clock())
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
			elseif summon then
				lastUnit = summon
				-- Keyboard summons in the tower use the middle lane; the lane picker covers touch.
				controller.battle("Summon", { unit = summon, lane = if tower then 3 else 0 }, now)
			elseif mace then
				controller.battle(
					"Mace",
					{ slot = mace, unit = lastUnit, lane = if tower then 3 else 0 },
					now
				)
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
			if now - hudAt >= 0.1 then
				ui.update(model)
				hudAt = now
			end
			ui.render(controller.frame(now), dt)
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
