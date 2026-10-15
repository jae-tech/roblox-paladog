--!strict
-- Roblox binding for RemoteGateway's core: explicit remotes only, FireClient to the owner only.
local RemoteGateway = require("./RemoteGateway")

type Core = RemoteGateway.Core

local REMOTE_EVENTS = { "ClientCommand", "MoveIntent", "ServerMessage", "MatchSnapshot" }

-- Roblox binding. Creates ReplicatedStorage-style Remotes under `parent`; returns a disconnect function.
local function bind(
	core: Core,
	parent: Instance,
	players: Players
): (Folder, (number, string, any) -> (), () -> ())
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	local events: { [string]: RemoteEvent } = {}
	for _, name in REMOTE_EVENTS do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		events[name] = event
	end
	local bootstrap = Instance.new("RemoteFunction")
	bootstrap.Name = "GetBootstrap"
	bootstrap.Parent = folder
	bootstrap.OnServerInvoke = function(player: Player, payload: unknown)
		return core.getBootstrap(player.UserId, payload)
	end
	local connections = {
		events.ClientCommand.OnServerEvent:Connect(function(player: Player, payload: unknown)
			core.clientCommand(player.UserId, payload)
		end),
		events.MoveIntent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			core.moveIntent(player.UserId, payload)
		end),
		players.PlayerAdded:Connect(function(player: Player)
			core.playerAdded(player.UserId)
		end),
		players.PlayerRemoving:Connect(function(player: Player)
			core.playerRemoving(player.UserId)
		end),
	}
	for _, player in players:GetPlayers() do
		core.playerAdded(player.UserId)
	end
	folder.Parent = parent
	local function send(userId: number, channel: string, payload: any)
		local player = players:GetPlayerByUserId(userId)
		if player then
			events[channel]:FireClient(player, payload)
		end
	end
	local function disconnect()
		for _, connection in connections do
			connection:Disconnect()
		end
		folder:Destroy()
	end
	return folder, send, disconnect
end

return table.freeze({ bind = bind })
