--!strict
-- Shared battle <-> world mapping (R8, D-PLAZA-03). The player's real Roblox character walks in a physical
-- arena; one arena slot per running match, far from the plaza. Plain numbers so the CLI can load it.
local SCALE = 0.12 -- studs per battle unit (also the client renderer scale)
local BASE_X = 3000
local SPACING_Z = 400
local SLOTS = 8

local function origin(slot: number): (number, number)
	return BASE_X, (slot - 1) * SPACING_Z
end

-- battle (x, z) -> world (X, Z) for an arena whose origin is (ox, oz)
local function toWorld(ox: number, oz: number, x: number, z: number): (number, number)
	return ox + x * SCALE, oz + z * SCALE
end

local function toBattle(ox: number, oz: number, worldX: number, worldZ: number): (number, number)
	return (worldX - ox) / SCALE, (worldZ - oz) / SCALE
end

return table.freeze({
	SCALE = SCALE,
	SLOTS = SLOTS,
	origin = origin,
	toWorld = toWorld,
	toBattle = toBattle,
})
