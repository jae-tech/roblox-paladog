--!strict
-- Production-safe client composition. No mock store/debug endpoint: wait for real server remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ActionRouter = require("./Input/ActionRouter")
local DeviceAdapter = require("./Input/DeviceAdapter")
local ClientController = require("./Net/ClientController")
local Presentation = require("./Presentation/Presentation")

local active: any = nil
local function start(): any
	if active then
		return active
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local protocol = require(ReplicatedStorage.Shared.Protocol)
	local catalog = require(ReplicatedStorage.Shared.PublicCatalog)
	local playableMvp = ReplicatedStorage:GetAttribute("PlayableMvp") == true
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
			catalog = catalog,
			playableMvp = playableMvp,
			send = send,
			requestId = function()
				return HttpService:GenerateGUID(false)
			end,
		})
	end
	local controller = makeController()
	local router: any = nil
	local presentation = Presentation.new(playerGui, function(action)
		if action == "Menu" or action == "CloseMenu" then
			if router then
				router.setBlocked("menu", action == "Menu")
			end
		else
			controller.action(action, os.clock())
		end
	end, playableMvp)
	router = ActionRouter.new({
		onAxis = function(axis)
			controller.move(axis, os.clock())
		end,
		onAction = function(action)
			controller.action(action, os.clock())
		end,
	})
	router.setBlocked("transport", true)
	local adapter = DeviceAdapter.new(router, presentation.buttons)
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
	local function visible(): boolean
		local current: Instance? = presentation.buttons.Left
		while current and current ~= playerGui do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			if current:IsA("ScreenGui") and not current.Enabled then
				return false
			end
			current = current.Parent
		end
		return current == playerGui
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
			router.setBlocked("controls-hidden", model.phase == "Running" and not visible())
			router.step(now)
			if now - hudAt >= 0.1 then
				presentation.update(model)
				hudAt = now
			end
			presentation.render(controller.frame(now), dt)
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
		presentation.destroy()
		active = nil
	end
	active = {
		inspect = function(): any
			return {
				input = router.inspect(),
				controller = controller.inspect(os.clock()),
				model = controller.model(os.clock()),
				presentation = presentation.inspect(),
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
