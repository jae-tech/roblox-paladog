--!strict
-- Equipment worn on the player's real Roblox avatar (D-GEAR-01). The server welds the code-built pieces from
-- shared GearLook onto the character, so every player sees them in the plaza and the arena. Mounts walk
-- beside the player as a companion. Rebuilt only when the equipped codes change (character GearKey).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GearLook = require(ReplicatedStorage.Shared.GearLook)

local PRESENTATION_ID = "avatar_gear_placeholder"
local REF_TORSO_Y = 1.9 -- default R15 UpperTorso height; non-relative parts scale with the body

local function rad(v: { number }?, i: number): number
	return math.rad(v and v[i] or 0)
end

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

-- One gear part placed in `base` space (already the anchor frame).
local function buildPart(
	spec: GearLook.Part,
	anchorSize: Vector3,
	base: CFrame,
	scale: number
): BasePart
	local size = if spec.rel then vec(spec.size) * anchorSize else vec(spec.size) * scale
	local at = if spec.rel then vec(spec.at) * anchorSize else vec(spec.at) * scale
	local part: BasePart
	local turn = CFrame.identity
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
		part.Size = size
	elseif spec.shape == "Ball" then
		-- an ellipsoid: a block with a sphere mesh fills any size
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
	part.Name = "Gear" .. spec.shape
	part.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	part.Material = if spec.neon then Enum.Material.Neon else material(spec.mat)
	part.Transparency = spec.transp or 0
	part.Anchored = false
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.CFrame = base
		* CFrame.new(at)
		* CFrame.Angles(rad(spec.rot, 1), rad(spec.rot, 2), rad(spec.rot, 3))
		* turn
	return part
end

-- enchant grade: a light from +1, sparkles from +3
local function glow(part: BasePart, grade: number)
	if grade <= 0 then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 4 + grade
	light.Brightness = 0.6 + grade * 0.25
	light.Parent = part
	if grade >= 3 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(part.Color)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.18, 0)
		sparkle.Lifetime = NumberRange.new(0.5, 0.9)
		sparkle.Rate = 2 + grade
		sparkle.Speed = NumberRange.new(0.4, 1)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = part
	end
end

local function new()
	local companions = Workspace:FindFirstChild("GearCompanions") or Instance.new("Folder")
	companions.Name = "GearCompanions"
	companions:SetAttribute("PresentationId", PRESENTATION_ID)
	companions.Parent = Workspace

	-- hats and hair hide under a helmet and come back without one
	local function setHair(character: Model, hidden: boolean)
		for _, item in character:GetChildren() do
			if
				item:IsA("Accessory")
				and (
					item.AccessoryType == Enum.AccessoryType.Hat
					or item.AccessoryType == Enum.AccessoryType.Hair
				)
			then
				local handle = item:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					local saved = handle:GetAttribute("GearHairTransparency")
					if hidden and saved == nil then
						handle:SetAttribute("GearHairTransparency", handle.Transparency)
						handle.Transparency = 1
					elseif not hidden and type(saved) == "number" then
						handle.Transparency = saved
						handle:SetAttribute("GearHairTransparency", nil)
					end
				end
			end
		end
	end

	local function clear(character: Model, userId: number)
		local old = character:FindFirstChild("Gear")
		if old then
			old:Destroy()
		end
		local companion = companions:FindFirstChild(tostring(userId))
		if companion then
			companion:Destroy()
		end
	end

	local function companionFor(
		player: Player,
		piece: GearLook.Piece,
		rootPart: BasePart,
		scale: number
	)
		local frame = piece.frame or { 0, 0, 0, 0, 0, 0 }
		local offset = Vector3.new(frame[1], frame[2], frame[3]) * scale
		local model = Instance.new("Model")
		model.Name = tostring(player.UserId)
		model:SetAttribute("GearId", piece.id)
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(1, 1, 1)
		root.Transparency = 1
		root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
		root.CFrame = rootPart.CFrame * CFrame.new(offset)
		root.Parent = model
		model.PrimaryPart = root
		for _, spec in piece.parts do
			local part = buildPart(spec, root.Size, root.CFrame, scale)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, part
			weld.Parent = part
			part.Parent = model
			if spec.core then
				glow(part, piece.grade)
			end
		end
		-- follows the player's root a little behind on the right
		local own = Instance.new("Attachment")
		own.Parent = root
		local target = Instance.new("Attachment")
		target.Name = "GearCompanionTarget"
		target.Position = offset
		target.Parent = rootPart
		local align = Instance.new("AlignPosition")
		align.Attachment0, align.Attachment1 = own, target
		align.Responsiveness = 18
		align.MaxForce = 1e6
		align.Parent = root
		local turn = Instance.new("AlignOrientation")
		turn.Attachment0, turn.Attachment1 = own, target
		turn.Responsiveness = 14
		turn.MaxTorque = 1e6
		turn.Parent = root
		model.Parent = companions
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end

	local function apply(player: Player, character: Model, equip: { number }, key: string)
		clear(character, player.UserId)
		local old = character:FindFirstChild("GearCompanionTarget", true)
		if old then
			old:Destroy()
		end
		local torso = character:FindFirstChild("UpperTorso")
		local scale = if torso and torso:IsA("BasePart") then torso.Size.Y / REF_TORSO_Y else 1
		local folder = Instance.new("Model")
		folder.Name = "Gear"
		local hidesHair = false
		local pieces = GearLook.look(equip)
		for _, piece in pieces do
			local anchor = character:FindFirstChild(piece.anchor)
			if anchor and anchor:IsA("BasePart") then
				if piece.companion then
					companionFor(player, piece, anchor, scale)
				else
					hidesHair = hidesHair or piece.hidesHair == true
					local frame = piece.frame or { 0, 0, 0, 0, 0, 0 }
					local base = anchor.CFrame
						* CFrame.new(Vector3.new(frame[1], frame[2], frame[3]) * scale)
						* CFrame.Angles(math.rad(frame[4]), math.rad(frame[5]), math.rad(frame[6]))
					for _, spec in piece.parts do
						local part = buildPart(spec, anchor.Size, base, scale)
						local weld = Instance.new("WeldConstraint")
						weld.Part0, weld.Part1 = anchor, part
						weld.Parent = part
						part:SetAttribute("GearId", piece.id)
						part:SetAttribute("GearSlot", piece.slot)
						part.Parent = folder
						if spec.core then
							glow(part, piece.grade)
						end
					end
				end
			end
		end
		folder.Parent = character
		setHair(character, hidesHair)
		character:SetAttribute("GearKey", key)
	end

	-- a companion left far behind (arena teleport, respawn) jumps back next to its player
	local function keepUp(player: Player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local companion = companions:FindFirstChild(tostring(player.UserId))
		local target = root and root:FindFirstChild("GearCompanionTarget")
		if
			companion
			and companion:IsA("Model")
			and root
			and root:IsA("BasePart")
			and target
			and target:IsA("Attachment")
		then
			local at = root.CFrame * CFrame.new(target.Position)
			if (companion:GetPivot().Position - at.Position).Magnitude > 40 then
				companion:PivotTo(at)
			end
		end
	end

	return {
		apply = apply,
		keepUp = keepUp,
		release = function(userId: number)
			local companion = companions:FindFirstChild(tostring(userId))
			if companion then
				companion:Destroy()
			end
		end,
		companions = companions,
	}
end

return table.freeze({ new = new, PRESENTATION_ID = PRESENTATION_ID })
