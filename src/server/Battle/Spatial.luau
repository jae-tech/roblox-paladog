--!strict
-- Optional ground-plane geometry for the 3D companion mode. Legacy battles keep one-dimensional rules.
local function direction(x: number, z: number): (number, number)
	local length = math.sqrt(x * x + z * z)
	if length == 0 then
		return 0, 0
	end
	return x / length, z / length
end
local function distanceAt(b: any, source: any, x: number, target: any): number
	local dx = target.x - x
	local dz = if b.spatial then (target.z or 0) - (source.z or 0) else 0
	return math.sqrt(dx * dx + dz * dz)
end
return table.freeze({ direction = direction, distanceAt = distanceAt, HALF_WIDTH = 90 })
