--!strict
-- Small Instance builders shared by the field, battle HUD and lobby. Every widget is a plain GuiObject.
local Theme = require("./Theme")

local Widgets = {}

local function corner(parent: Instance, radius: number)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, radius)
	round.Parent = parent
end
Widgets.corner = corner

function Widgets.frame(parent: Instance, name: string, color: Color3?, radius: number?): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.BorderSizePixel = 0
	item.BackgroundColor3 = color or Theme.panel
	item.BackgroundTransparency = if color then 0 else 1
	if radius then
		corner(item, radius)
	end
	item.Parent = parent
	return item
end

function Widgets.label(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	color: Color3?
): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamBold
	item.TextSize = size
	item.TextColor3 = color or Theme.text
	item.Text = text
	item.TextWrapped = true
	item.Parent = parent
	return item
end

function Widgets.button(
	parent: Instance,
	name: string,
	text: string,
	size: number?,
	color: Color3?
): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Text = text
	item.Font = Enum.Font.GothamBold
	item.TextSize = size or 16
	item.TextColor3 = Theme.text
	item.TextWrapped = true
	item.AutoButtonColor = true
	item.BackgroundColor3 = color or Theme.button
	item.BorderSizePixel = 0
	corner(item, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = item
	item.Parent = parent
	return item
end

-- Horizontal fill bar; returns the frame and a setter taking a 0..1 ratio and a caption.
function Widgets.bar(
	parent: Instance,
	name: string,
	color: Color3
): (Frame, (number, string?) -> ())
	local back = Widgets.frame(parent, name, Color3.fromRGB(16, 16, 24), 4)
	back.BackgroundTransparency = 0.2
	local fill = Widgets.frame(back, "Fill", color, 4)
	fill.Size = UDim2.fromScale(0, 1)
	local caption = Widgets.label(back, "Caption", "", 12)
	caption.Size = UDim2.fromScale(1, 1)
	caption.TextStrokeTransparency = 0.4
	caption.ZIndex = 3
	fill.ZIndex = 2
	return back,
		function(ratio: number, text: string?)
			fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
			caption.Text = text or ""
		end
end

function Widgets.list(parent: Instance, name: string, padding: number?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

function Widgets.grid(parent: Instance, name: string, cell: UDim2, gap: number): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = cell
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

function Widgets.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return table.freeze(Widgets)
