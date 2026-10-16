--!strict
-- Engine events are confined here; ActionRouter remains runnable in pure Luau.
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ActionRouter = require("./ActionRouter")
type Router = typeof(ActionRouter.new({
	onAxis = function(_: number) end,
	onAction = function(_: string) end,
}))
local DeviceAdapter = {}
local KEYS: { [string]: { Enum.KeyCode } } = {
	Left = { Enum.KeyCode.A, Enum.KeyCode.Left },
	Right = { Enum.KeyCode.D, Enum.KeyCode.Right },
	Summon1 = { Enum.KeyCode.One },
	Summon2 = { Enum.KeyCode.Two },
	Summon3 = { Enum.KeyCode.Three },
	Summon4 = { Enum.KeyCode.Four },
	Summon5 = { Enum.KeyCode.Five },
	Summon6 = { Enum.KeyCode.Six },
	Summon7 = { Enum.KeyCode.Seven },
	Summon8 = { Enum.KeyCode.Eight },
	Summon9 = { Enum.KeyCode.Nine },
	Mace1 = { Enum.KeyCode.Q },
	Mace2 = { Enum.KeyCode.W },
	Mace3 = { Enum.KeyCode.E },
	Jump = { Enum.KeyCode.Space },
}

function DeviceAdapter.new(router: Router, buttons: { [string]: any })
	local connections: { RBXScriptConnection } = {}
	local touches: { [InputObject]: RBXScriptConnection } = {}
	local names: { string } = {}
	local destroyed = false
	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(connections, signal:Connect(callback))
	end
	local function finish(input: InputObject)
		router.finish(input)
		local connection = touches[input]
		if connection then
			connection:Disconnect()
			touches[input] = nil
		end
	end
	for action, keys in KEYS do
		local name = "LanternGameplay_" .. action
		table.insert(names, name)
		ContextActionService:BindActionAtPriority(name, function(_, state, input)
			-- End/Cancel always clean up, including while a blocker is active.
			if state == Enum.UserInputState.Cancel then
				-- CAS cancellation may carry Unknown/None instead of the held key.
				for _, key in keys do
					router.finish(key)
				end
			elseif state == Enum.UserInputState.End then
				router.finish(input.KeyCode)
			end
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				router.begin(action, input.KeyCode)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, table.unpack(keys))
	end
	for action, button in buttons do
		if action == "Left" or action == "Right" then
			connect(button.InputBegan, function(input: InputObject)
				if
					input.UserInputType ~= Enum.UserInputType.Touch
					and input.UserInputType ~= Enum.UserInputType.MouseButton1
				then
					return
				end
				if touches[input] then
					return
				end
				router.begin(action, input)
				touches[input] = input.Changed:Connect(function()
					if
						input.UserInputState == Enum.UserInputState.Cancel
						or input.UserInputState == Enum.UserInputState.End
					then
						finish(input)
					end
				end)
			end)
			connect(button.InputEnded, finish)
		else
			-- Activated is the only discrete GUI path: no synthetic mouse duplicate.
			connect(button.Activated, function()
				router.activate(action)
			end)
		end
	end
	connect(UserInputService.InputEnded, finish)
	connect(UserInputService.WindowFocusReleased, function()
		router.setBlocked("focus", true)
	end)
	connect(UserInputService.WindowFocused, function()
		router.setBlocked("focus", false)
	end)
	connect(UserInputService.TextBoxFocused, function()
		router.setBlocked("text", true)
	end)
	connect(UserInputService.TextBoxFocusReleased, function()
		router.setBlocked("text", UserInputService:GetFocusedTextBox() ~= nil)
	end)
	connect(GuiService.MenuOpened, function()
		router.setBlocked("roblox-menu", true)
	end)
	connect(GuiService.MenuClosed, function()
		router.setBlocked("roblox-menu", false)
	end)
	router.setBlocked("text", UserInputService:GetFocusedTextBox() ~= nil)
	router.setBlocked("roblox-menu", GuiService.MenuIsOpen)
	local adapter = {}
	function adapter.setBlocked(reason: string, value: boolean)
		if not destroyed then
			router.setBlocked(reason, value)
		end
	end
	function adapter.inspect()
		return router.inspect()
	end
	function adapter.destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, name in names do
			ContextActionService:UnbindAction(name)
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, connection in touches do
			connection:Disconnect()
		end
		table.clear(touches)
		table.clear(connections)
		router.destroy()
	end
	return adapter
end
return DeviceAdapter
