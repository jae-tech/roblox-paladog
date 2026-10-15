--!strict
-- Camera-only framing. No simulation position or hit geometry is changed.
local function compute(
	heroX: number,
	stageLength: number,
	aspect: number,
	fieldOfView: number
): { [string]: number }
	local distance = 42
	local halfWidth = math.sqrt(distance * distance + 100)
		* math.tan(math.rad(fieldOfView) / 2)
		* math.max(0.1, aspect)
	local length = math.max(0, stageLength)
	local centre = if length <= halfWidth * 2
		then length / 2
		else math.clamp(heroX, halfWidth, length - halfWidth)
	return { centre = centre, halfWidth = halfWidth, distance = distance }
end
return table.freeze({ compute = compute })
