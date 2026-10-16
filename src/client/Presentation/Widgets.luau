--!strict
-- Small Instance builders shared by the field, battle HUD and lobby. Every widget is a plain GuiObject.
-- Code-only styling (gradients, strokes, tweens); no image assets.
local TweenService = game:GetService("TweenService")
local Theme = require("./Theme")

local Widgets = {}

local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(parent: Instance, radius: number)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, radius)
	round.Parent = parent
end
Widgets.corner = corner

function Widgets.stroke(
	parent: Instance,
	color: Color3?,
	thickness: number?,
	transparency: number?
): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color or Theme.stroke
	line.Thickness = thickness or 1
	line.Transparency = transparency or 0
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = parent
	return line
end

-- Vertical light-to-dark sheen; multiplies whatever BackgroundColor3 the object has.
function Widgets.sheen(parent: Instance, bottom: number?)
	local gradient = Instance.new("UIGradient")
	local low = bottom or 0.78
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(low, low, low))
	gradient.Rotation = 90
	gradient.Parent = parent
end

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

-- Raised card: panel colour, soft stroke and sheen.
function Widgets.card(parent: Instance, name: string, color: Color3?, radius: number?): Frame
	local item = Widgets.frame(parent, name, color or Theme.panel, radius or 10)
	Widgets.stroke(item, Theme.stroke, 1, 0.45)
	Widgets.sheen(item, 0.86)
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
	item.Font = Theme.fontBold
	item.TextSize = size
	item.TextColor3 = color or Theme.text
	item.Text = text
	item.TextWrapped = true
	item.Parent = parent
	return item
end

-- Text that shrinks to fit its box but never grows past `size`.
function Widgets.fit(item: GuiObject, size: number)
	(item :: any).TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.MinTextSize = 8
	limit.Parent = item
end

local function bright(color: Color3): boolean
	return color.R * 0.299 + color.G * 0.587 + color.B * 0.114 > 0.62
end

-- Background colour plus a readable text colour (dark ink on gold/amber buttons).
function Widgets.paint(item: GuiObject, color: Color3)
	item.BackgroundColor3 = color
	if item:IsA("TextButton") or item:IsA("TextLabel") then
		(item :: any).TextColor3 = if bright(color) then Theme.ink else Theme.text
	end
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
	item.Font = Theme.fontBold
	item.TextSize = size or 16
	item.TextWrapped = true
	item.AutoButtonColor = true
	item.BorderSizePixel = 0
	Widgets.paint(item, color or Theme.button)
	corner(item, 8)
	local line = Widgets.stroke(item, Theme.stroke, 1, 0.35)
	Widgets.sheen(item)
	-- press feedback: a quick squash, and a warm outline on hover
	local scale = Instance.new("UIScale")
	scale.Parent = item
	item.MouseButton1Down:Connect(function()
		TweenService:Create(scale, QUICK, { Scale = 0.94 }):Play()
	end)
	local function release()
		TweenService:Create(scale, QUICK, { Scale = 1 }):Play()
	end
	item.MouseButton1Up:Connect(release)
	item.MouseLeave:Connect(function()
		release()
		local base = line:GetAttribute("BaseColor")
		line.Color = if typeof(base) == "Color3" then base else Theme.stroke
		local fade = line:GetAttribute("BaseTransparency")
		line.Transparency = if type(fade) == "number" then fade else 0.35
	end)
	item.MouseEnter:Connect(function()
		line.Color, line.Transparency = Theme.gold, 0.1
	end)
	item.Parent = parent
	return item
end

-- Recolour the outline of a button/card (kept after hover ends).
function Widgets.outline(item: GuiObject, color: Color3, thickness: number, transparency: number?)
	local line = item:FindFirstChildOfClass("UIStroke") or Widgets.stroke(item)
	line.Color, line.Thickness, line.Transparency = color, thickness, transparency or 0
	line:SetAttribute("BaseColor", color)
	line:SetAttribute("BaseTransparency", transparency or 0)
end

-- Small rounded tag (hotkey, AUTO, cost). Returns the pill and its text.
function Widgets.pill(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	color: Color3,
	textColor: Color3?
): (Frame, TextLabel)
	local back = Widgets.frame(parent, name, color, 6)
	local caption = Widgets.label(back, "Text", text, size, textColor or Theme.text)
	caption.Size = UDim2.fromScale(1, 1)
	caption.TextWrapped = false
	return back, caption
end

-- Horizontal fill bar; returns the frame and a setter taking a 0..1 ratio and a caption.
-- The fill eases toward new values so damage and regen read as motion instead of jumps.
function Widgets.bar(
	parent: Instance,
	name: string,
	color: Color3
): (Frame, (number, string?) -> ())
	local back = Widgets.frame(parent, name, Color3.fromRGB(14, 14, 22), 6)
	back.BackgroundTransparency = 0.15
	Widgets.stroke(back, Color3.new(0, 0, 0), 1, 0.4)
	local fill = Widgets.frame(back, "Fill", color, 6)
	fill.Size = UDim2.fromScale(0, 1)
	Widgets.sheen(fill, 0.7)
	local caption = Widgets.label(back, "Caption", "", 12)
	caption.Size = UDim2.fromScale(1, 1)
	caption.TextStrokeTransparency = 0.35
	caption.ZIndex = 3
	fill.ZIndex = 2
	local shown = -1
	return back,
		function(ratio: number, text: string?)
			local target = math.clamp(ratio, 0, 1)
			if math.abs(target - shown) > 0.001 then
				local goal = { Size = UDim2.fromScale(target, 1) }
				if shown < 0 or not back.Visible then
					fill.Size = goal.Size
				else
					TweenService:Create(fill, QUICK, goal):Play()
				end
				shown = target
			end
			caption.Text = text or ""
		end
end

-- Modal entrance: the card pops from 92% and the shade fades in.
function Widgets.pop(shade: GuiObject, card: GuiObject)
	local scale = card:FindFirstChildOfClass("UIScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Parent = card
		scale = created
	end
	local s = scale :: UIScale
	s.Scale = 0.92
	TweenService:Create(s, POP, { Scale = 1 }):Play()
	-- remember the resting transparency so an interrupted fade never becomes the new target
	local saved = shade:GetAttribute("RestTransparency")
	local target = if type(saved) == "number" then saved else shade.BackgroundTransparency
	shade:SetAttribute("RestTransparency", target)
	shade.BackgroundTransparency = 1
	TweenService:Create(shade, FADE, { BackgroundTransparency = target }):Play()
end

-- Toast pill that appears when its message changes and fades after a few seconds.
function Widgets.toast(parent: Instance, name: string, color: Color3?): (Frame, (string) -> ())
	local back = Widgets.frame(parent, name, Theme.shade, 14)
	back.BackgroundTransparency = 1
	back.AutomaticSize = Enum.AutomaticSize.X
	back.AnchorPoint = Vector2.new(0.5, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.Parent = back
	local line = Widgets.stroke(back, color or Theme.gold, 1, 1)
	local caption = Widgets.label(back, "Text", "", 15, color or Theme.gold)
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.Size = UDim2.fromScale(0, 1)
	caption.TextWrapped = false
	caption.TextTransparency = 1
	local current, serial = "", 0
	return back,
		function(text: string)
			if text == current then
				return
			end
			current = text
			serial += 1
			local mine = serial
			if text == "" then
				TweenService:Create(back, FADE, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(caption, FADE, { TextTransparency = 1 }):Play()
				TweenService:Create(line, FADE, { Transparency = 1 }):Play()
				return
			end
			caption.Text = text
			back.BackgroundTransparency, caption.TextTransparency, line.Transparency = 0.25, 0, 0.4
			task.delay(3.2, function()
				if serial == mine then
					TweenService:Create(back, FADE, { BackgroundTransparency = 1 }):Play()
					TweenService:Create(caption, FADE, { TextTransparency = 1 }):Play()
					TweenService:Create(line, FADE, { Transparency = 1 }):Play()
				end
			end)
		end
end

function Widgets.list(parent: Instance, name: string, padding: number?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Theme.border
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
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Theme.border
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
