--!strict
-- One item's look in a ViewportFrame (D-GEAR-01 shop/bag detail): the same GearLook pieces the server
-- welds onto avatars, laid out on a default R15 body frame, auto-framed and turning slowly. Visual only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearLook = require(ReplicatedStorage.Shared.GearLook)

-- default R15 part centres (relative to the root) and sizes; rel parts scale with these
local RIG: { [string]: { at: Vector3, size: Vector3 } } = {
	HumanoidRootPart = { at = Vector3.zero, size = Vector3.new(2, 2, 1) },
	UpperTorso = { at = Vector3.new(0, 0.55, 0), size = Vector3.new(2, 1.6, 1) },
	LowerTorso = { at = Vector3.new(0, -0.45, 0), size = Vector3.new(2, 0.4, 1) },
	Head = { at = Vector3.new(0, 1.95, 0), size = Vector3.new(1.2, 1.2, 1.2) },
	LeftUpperArm = { at = Vector3.new(-1.5, 0.75, 0), size = Vector3.new(1, 1.2, 1) },
	RightUpperArm = { at = Vector3.new(1.5, 0.75, 0), size = Vector3.new(1, 1.2, 1) },
	LeftHand = { at = Vector3.new(-1.5, -0.55, 0), size = Vector3.new(1, 0.3, 1) },
	RightHand = { at = Vector3.new(1.5, -0.55, 0), size = Vector3.new(1, 0.3, 1) },
	LeftLowerLeg = { at = Vector3.new(-0.5, -1.75, 0), size = Vector3.new(1, 1.2, 1) },
	RightLowerLeg = { at = Vector3.new(0.5, -1.75, 0), size = Vector3.new(1, 1.2, 1) },
	LeftFoot = { at = Vector3.new(-0.5, -2.6, 0), size = Vector3.new(1, 0.3, 1) },
	RightFoot = { at = Vector3.new(0.5, -2.6, 0), size = Vector3.new(1, 0.3, 1) },
}
-- the equipment slot each category is shown in (weapons in the hand)
local SLOT_OF = { 1, 4, 7, 8, 9, 1, 4, 7, 8, 9 }

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function material(name: string?): Enum.Material
	if name then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and value then
			return value
		end
	end
	return Enum.Material.SmoothPlastic
end

local function buildPart(spec: GearLook.Part, anchorSize: Vector3, base: CFrame): BasePart
	local size = if spec.rel then vec(spec.size) * anchorSize else vec(spec.size)
	local at = if spec.rel then vec(spec.at) * anchorSize else vec(spec.at)
	local turn = CFrame.identity
	local part: BasePart
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
		part.Size = size
	elseif spec.shape == "Ball" then
		part = Instance.new("Part")
		part.Size = size
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif spec.shape == "Cyl" or spec.shape == "VCyl" or spec.shape == "ZCyl" then
		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		if spec.shape == "VCyl" then
			cylinder.Size = Vector3.new(size.Y, size.X, size.Z)
			turn = CFrame.Angles(0, 0, math.rad(90))
		elseif spec.shape == "ZCyl" then
			cylinder.Size = Vector3.new(size.Z, size.Y, size.X)
			turn = CFrame.Angles(0, math.rad(90), 0)
		else
			cylinder.Size = size
		end
		part = cylinder
	else
		part = Instance.new("Part")
		part.Size = size
	end
	part.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	part.Material = if spec.neon then Enum.Material.Neon else material(spec.mat)
	part.Transparency = spec.transp or 0
	part.Anchored = true
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	local rot = spec.rot
	part.CFrame = base
		* CFrame.new(at)
		* (if rot
			then CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
			else CFrame.identity)
		* turn
	return part
end

-- A model of the item at the origin; nil for an empty or unknown code.
local function modelOf(code: number): Model?
	local category = code // 100000
	local slot = SLOT_OF[category]
	if not slot then
		return nil
	end
	local pieces = GearLook.pieces(slot, code)
	if #pieces == 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Item"
	for _, piece in pieces do
		local rig = RIG[piece.anchor] or RIG.HumanoidRootPart
		local frame = piece.frame or { 0, 0, 0, 0, 0, 0 }
		-- a mount stands on its own; worn pieces keep their place on the body
		local base = if piece.companion
			then CFrame.identity
			else CFrame.new(rig.at) * CFrame.new(frame[1], frame[2], frame[3]) * CFrame.Angles(
				math.rad(frame[4]),
				math.rad(frame[5]),
				math.rad(frame[6])
			)
		for _, spec in piece.parts do
			buildPart(spec, rig.size, base).Parent = model
		end
	end
	return model
end

export type Preview = { step: (dt: number) -> (), destroy: () -> () }

-- Shows `code` inside `view` (a ViewportFrame); step(dt) turns it.
local function show(view: ViewportFrame, code: number): Preview
	view:ClearAllChildren()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = view
	view.CurrentCamera = camera
	local model = modelOf(code)
	if not model then
		return { step = function(_dt: number) end, destroy = function() end }
	end
	local world = Instance.new("WorldModel")
	world.Parent = view
	model.Parent = world
	local box, size = model:GetBoundingBox()
	local centre = box.Position
	model:PivotTo(model:GetPivot() - centre)
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.1
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.35, distance), Vector3.zero)
	local angle = 0
	local pivot = model:GetPivot()
	return {
		step = function(dt: number)
			angle += dt * 0.8
			model:PivotTo(CFrame.Angles(0, angle, 0) * pivot)
		end,
		destroy = function()
			world:Destroy()
		end,
	}
end

return table.freeze({ show = show, modelOf = modelOf, SLOT_OF = SLOT_OF })
