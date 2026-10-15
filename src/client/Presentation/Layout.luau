--!strict
-- Offsets are measured inside ScreenGui's safe inset, never physical screen bounds.
export type Rect = { x: number, y: number, width: number, height: number }
export type Result = {
	width: number,
	height: number,
	portrait: boolean,
	compact: boolean,
	buttons: { [string]: Rect },
	hud: Rect,
	stage: Rect,
	rotateHint: Rect,
}

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

local function compute(width: number, height: number): Result
	width = math.max(320, math.floor(width))
	height = math.max(280, math.floor(height))
	local portrait = height > width
	local compact = width < 580
	local margin, gap = 16, 8
	local buttons: { [string]: Rect } = {}
	if portrait or compact then
		local unitWidth = (width - margin * 2 - gap * 2) / 3
		for slot = 1, 3 do
			buttons["Summon" .. slot] =
				rect(margin + (slot - 1) * (unitWidth + gap), height - 144, unitWidth, 56)
		end
		buttons.Left = rect(margin, height - 80, 64, 64)
		buttons.Right = rect(margin + 72, height - 80, 64, 64)
		buttons.Cast = rect(width - margin - 112, height - 80, 112, 64)
	else
		buttons.Left = rect(margin, height - 80, 64, 64)
		buttons.Right = rect(margin + 72, height - 80, 64, 64)
		local castWidth, unitWidth = 104, 84
		buttons.Cast = rect(width - margin - castWidth, height - 104, castWidth, 88)
		for slot = 1, 3 do
			buttons["Summon" .. slot] = rect(
				width - margin - castWidth - gap - (4 - slot) * (unitWidth + gap) + gap,
				height - 88,
				unitWidth,
				72
			)
		end
	end
	local hudHeight = if portrait then 144 else 104
	local stageWidth = math.min(width - 32, 600)
	local stageHeight = if portrait then 240 else 120
	local lower = if portrait then height - 152 else height - 112
	return {
		width = width,
		height = height,
		portrait = portrait,
		compact = compact,
		buttons = buttons,
		hud = rect(16, 8, width - 32, hudHeight),
		stage = rect(
			(width - stageWidth) / 2,
			hudHeight + 16 + math.max(0, (lower - hudHeight - 16 - stageHeight) / 2),
			stageWidth,
			stageHeight
		),
		rotateHint = rect(16, hudHeight + 12, width - 32, 24),
	}
end

return table.freeze({ compute = compute })
