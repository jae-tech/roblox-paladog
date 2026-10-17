--!strict
-- Physical dungeon arenas for avatar combat (R8, D-PLAZA-03). Each running match borrows one slot far from
-- the plaza: an invisible collision floor/walls (the client draws the dungeon over it), the player's real
-- character is moved in, walks with normal Roblox controls, and the hero follows it at the hero's own speed
-- (MatchService.follow). The server leashes the character to the hero, so moving faster gains nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Space = require(ReplicatedStorage.Shared.ArenaSpace)

local LEASH_STUDS = 10 -- character farther than this from the hero is put back on it
local FLOOR_LENGTH = 1300 -- battle units, covers x -40..1100 plus margin
local HALF_WIDTH_STUDS = 13.5 -- matches the client dungeon walls

export type Entry = { slot: number, ox: number, oz: number, movable: boolean }

local function new(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "Arenas"
	root.Parent = parent
	local used: { [number]: number } = {} -- slot -> userId
	local entries: { [number]: Entry } = {}

	local function block(name: string, size: Vector3, cf: CFrame, slotFolder: Instance)
		local p = Instance.new("Part")
		p.Name = name
		p.Size, p.CFrame = size, cf
		p.Anchored, p.CanCollide = true, true
		p.Transparency = 1
		p.Parent = slotFolder
	end

	local function floorFor(slot: number): Instance
		local name = "Slot" .. slot
		local existing = root:FindFirstChild(name)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = name
		local ox, oz = Space.origin(slot)
		local length = FLOOR_LENGTH * Space.SCALE
		local centerX = ox + (FLOOR_LENGTH / 2 - 80) * Space.SCALE
		block(
			"Floor",
			Vector3.new(length, 1, HALF_WIDTH_STUDS * 2),
			CFrame.new(centerX, -0.5, oz),
			folder
		)
		for _, side in { -1, 1 } do
			block(
				"Wall",
				Vector3.new(length, 12, 1),
				CFrame.new(centerX, 6, oz + side * HALF_WIDTH_STUDS),
				folder
			)
		end
		for _, endX in { ox - 6, ox + (FLOOR_LENGTH - 120) * Space.SCALE } do
			block("End", Vector3.new(1, 12, HALF_WIDTH_STUDS * 2), CFrame.new(endX, 6, oz), folder)
		end
		folder.Parent = root
		return folder
	end

	local function rootPart(player: Player): BasePart?
		local character = player.Character
		local part = character and character:FindFirstChild("HumanoidRootPart")
		return if part and part:IsA("BasePart") then part else nil
	end

	local function heroWorld(entry: Entry, battle: any): Vector3?
		local hero = battle and battle.entities and battle.entities[battle.heroId]
		if not hero then
			return nil
		end
		local x, z = Space.toWorld(entry.ox, entry.oz, hero.x, hero.z or 0)
		return Vector3.new(x, 3, z)
	end

	-- speed in studs/s that matches the hero. Where the hero stands still (destiny/tower/dungeon) the
	-- character still walks around it inside the leash; the battle hero does not follow it there.
	local function walkSpeed(battle: any, _movable: boolean): number
		local stats = battle.stats or {}
		return ((stats.moveSpeed or 60) + (stats.moveSpeedRing or 0)) * Space.SCALE
	end

	local function enter(player: Player, battle: any, movable: boolean): boolean
		if entries[player.UserId] then
			return true
		end
		local slot = nil
		for i = 1, Space.SLOTS do
			if not used[i] then
				slot = i
				break
			end
		end
		local part = rootPart(player)
		if not slot or not part then
			return false
		end
		used[slot] = player.UserId
		floorFor(slot)
		local ox, oz = Space.origin(slot)
		local entry = { slot = slot, ox = ox, oz = oz, movable = movable }
		entries[player.UserId] = entry
		player:SetAttribute("ArenaOrigin", Vector3.new(ox, 0, oz))
		player:SetAttribute("ArenaWalkSpeed", walkSpeed(battle, movable))
		local at = heroWorld(entry, battle)
		if at and player.Character then
			player.Character:PivotTo(CFrame.lookAt(at, at + Vector3.new(1, 0, 0)))
		end
		return true
	end

	-- battle-unit position of the character, or nil when it is not in an arena / the hero cannot move
	local function follow(player: Player): (number?, number?)
		local entry = entries[player.UserId]
		local part = rootPart(player)
		if not entry or not entry.movable or not part then
			return nil, nil
		end
		return Space.toBattle(entry.ox, entry.oz, part.Position.X, part.Position.Z)
	end

	local function leash(player: Player, battle: any)
		local entry = entries[player.UserId]
		local part = rootPart(player)
		local at = entry and heroWorld(entry, battle)
		if not entry or not part or not at then
			return
		end
		player:SetAttribute("ArenaWalkSpeed", walkSpeed(battle, entry.movable))
		local flat = Vector3.new(part.Position.X, at.Y, part.Position.Z)
		local offset = flat - at
		local character = player.Character
		if part.Position.Y < -20 then
			if character then
				character:PivotTo(CFrame.new(at) * part.CFrame.Rotation)
			end
		elseif offset.Magnitude > LEASH_STUDS and character then
			-- a soft leash: back onto the circle edge, not a jump onto the hero
			local edge = at + offset.Unit * (LEASH_STUDS - 0.5)
			character:PivotTo(CFrame.new(edge) * part.CFrame.Rotation)
		end
	end

	-- result screen: keep the character still in the arena until the player leaves the result
	local function hold(player: Player)
		if entries[player.UserId] then
			player:SetAttribute("ArenaWalkSpeed", 0)
		end
	end

	local function leave(player: Player, back: CFrame)
		local entry = entries[player.UserId]
		if not entry then
			return
		end
		entries[player.UserId] = nil
		used[entry.slot] = nil
		player:SetAttribute("ArenaOrigin", nil)
		player:SetAttribute("ArenaWalkSpeed", nil)
		if player.Character then
			player.Character:PivotTo(back)
		end
	end

	local function release(userId: number)
		local entry = entries[userId]
		if entry then
			entries[userId] = nil
			used[entry.slot] = nil
		end
	end

	return {
		root = root,
		enter = enter,
		follow = follow,
		leash = leash,
		hold = hold,
		leave = leave,
		release = release,
		entryOf = function(userId: number): Entry?
			return entries[userId]
		end,
	}
end

return table.freeze({ new = new })
