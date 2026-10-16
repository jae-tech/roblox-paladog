--!strict
-- Lobby transactions on a caller-owned profile copy (remake R3). Each returns a rejection reason or nil.
-- Rules: unit unlock/upgrade (E05 B2-B5), skills and reset (E05 B7), shop/sell/equip/enchant (E03 §2,
-- E05 B8), gem shop (E05 B9). Every operation refuses while a battle run is open.
local ServerTypes = require("../ServerTypes")
local Schema = require("./ProfileSchema")
local Achievements = require("./Achievements")
local Db = require("../Config/Remake/Db")

type Profile = ServerTypes.ProfileV1
type Slot = ServerTypes.Slot

local C = Schema.CATEGORY
local RESET_GEMS = 1000 -- E05 B9 kind 9
local RING_SLOT_GEMS = 1000 -- E05 B9 kind 1
local GOLD_PACK_GEMS, GOLD_PACK = 1000, 100000 -- E05 B9 kind 2
local GOLDEN_WEAPON_GEMS = 1 -- E05 B9 kinds 3 and 7

local function weaponRows(category: number): { any }?
	if category == C.mace then
		return Db.maces
	elseif category == C.sword then
		return Db.swords
	elseif category == C.ring then
		return Db.rings
	elseif category == C.amulet then
		return Db.amulets
	end
	return nil
end

-- D-SHOP-01: helmets/armor/mounts sell for gems at a hard-coded base of 100..500 (E03 §2.4 gives only the range).
local function gearBase(num: number): number
	return 100 * (1 + (num - 1) % 5)
end

-- Gold price of a weapon/ring at `grade`: base + multi * grade^2 (E05 B8).
local function goldPrice(category: number, num: number, grade: number): number?
	local rows = weaponRows(category)
	local row = rows and rows[num]
	if not row or row.priceBase <= 0 then
		return nil -- the gold weapon is not sold for gold (E03 §2.4)
	end
	return row.priceBase + row.priceMulti * grade * grade
end

-- Sell value: weapons/rings half the buy price; gear base + base*0.1*grade^2 (E03 §2.4).
local function saleValue(code: number): number
	local category, num, grade = Schema.decodeItem(code)
	local rows = weaponRows(category)
	if rows then
		local row = rows[num]
		return (row.priceBase + row.priceMulti * grade * grade) // 2
	end
	local base = gearBase(num)
	return math.floor(base + base * 0.1 * grade * grade)
end

local function slotOf(profile: Profile): (Slot?, string?)
	if profile.activeRun then
		return nil, "WrongPhase"
	end
	local slot = Schema.currentSlot(profile)
	if not slot then
		return nil, "NoSlot"
	end
	return slot, nil
end

local function addGold(slot: Slot, amount: number)
	slot.gold = math.clamp(slot.gold + amount, 0, Schema.GOLD_MAX)
end

local function createSlot(
	profile: Profile,
	index: number,
	heroKind: string,
	difficulty: number
): string?
	if profile.activeRun then
		return "WrongPhase"
	elseif profile.slots[index] ~= false then
		return "SlotTaken"
	elseif heroKind == "shadow" and not profile.darkUnlocked then
		return "Locked"
	end
	profile.slots[index] = Schema.newSlot(heroKind, difficulty)
	profile.currentSlot = index
	return nil
end

local function deleteSlot(profile: Profile, index: number): string?
	if profile.activeRun then
		return "WrongPhase"
	elseif profile.slots[index] == false then
		return "NoSlot"
	end
	profile.slots[index] = false
	if profile.currentSlot == index then
		profile.currentSlot = 0
	end
	return nil
end

local function selectSlot(profile: Profile, index: number): string?
	if profile.activeRun then
		return "WrongPhase"
	elseif profile.slots[index] == false then
		return "NoSlot"
	end
	profile.currentSlot = index
	return nil
end

-- Unlock (level 0 -> 1) and upgrades cost the next level row's iCost_ (E05 B2); max level 20.
local function upgradeUnit(profile: Profile, n: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local level = slot.units[n]
	local rows = if slot.heroKind == "light" then Db.units else Db.totems
	if level >= 20 then
		return "MaxLevel"
	end
	local before = Schema.PREREQUISITE[slot.heroKind][n]
	if level == 0 and before > 0 and slot.units[before] < 1 then
		return "Locked"
	end
	local cost = rows[n].levels.cost[level + 1]
	if slot.gold < cost then
		return "InsufficientGold"
	end
	slot.gold -= cost
	slot.units[n] = level + 1
	Achievements.evaluate(profile, slot, nil)
	return nil
end

local function learnSkill(profile: Profile, index: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local cap = Schema.SKILL_MAX[slot.heroKind][index]
	if not cap then
		return "InvalidPayload"
	elseif slot.freePoints < 1 then
		return "NoPoints"
	elseif slot.skills[index] >= cap then
		return "MaxLevel"
	end
	slot.freePoints -= 1
	slot.skills[index] += 1
	return nil
end

-- Skill reset: 1000 gems, every learned level returns as a free point (E05 B7).
local function resetSkills(profile: Profile): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	elseif profile.gems < RESET_GEMS then
		return "InsufficientGems"
	end
	profile.gems -= RESET_GEMS
	for i, value in slot.skills do
		slot.freePoints += value
		slot.skills[i] = 0
	end
	return nil
end

local function categoryAllowed(slot: Slot, category: number): boolean
	return table.find(Schema.SLOT_CATEGORY[slot.heroKind], category) ~= nil
end

-- Gold shop sells grade-0 weapons/rings; gear costs gems (D-SHOP-01).
local function buyItem(profile: Profile, category: number, num: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	elseif
		not categoryAllowed(slot, category)
		or num < 1
		or num > Schema.CATEGORY_COUNT[category]
	then
		return "InvalidPayload"
	elseif #slot.inventory >= Schema.INVENTORY_MAX then
		return "InventoryFull"
	end
	if weaponRows(category) then
		local price = goldPrice(category, num, 0)
		if not price then
			return "InvalidPayload"
		elseif slot.gold < price then
			return "InsufficientGold"
		end
		slot.gold -= price
	else
		local gems = gearBase(num)
		if profile.gems < gems then
			return "InsufficientGems"
		end
		profile.gems -= gems
	end
	table.insert(slot.inventory, Schema.encodeItem(category, num, 0))
	return nil
end

local function sellItem(profile: Profile, index: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local code = slot.inventory[index]
	if not code then
		return "InvalidPayload"
	end
	table.remove(slot.inventory, index)
	addGold(slot, saleValue(code))
	Achievements.evaluate(profile, slot, nil)
	return nil
end

-- Equip moves an inventory item into its slot (swapping out any occupant); slot 6 needs the gem unlock
-- (E03 §2.1: the third ring slot; the second is free since the original forces it open).
local function equip(profile: Profile, index: number, equipSlot: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local code = slot.inventory[index]
	if not code or equipSlot < 1 or equipSlot > 9 then
		return "InvalidPayload"
	end
	if Schema.decodeItem(code) ~= Schema.SLOT_CATEGORY[slot.heroKind][equipSlot] then
		return "InvalidPayload"
	elseif equipSlot == 6 and not profile.ringSlotUnlocked then
		return "Locked"
	end
	table.remove(slot.inventory, index)
	local previous = slot.equip[equipSlot]
	slot.equip[equipSlot] = code
	if previous ~= 0 then
		table.insert(slot.inventory, previous)
	end
	return nil
end

local function unequip(profile: Profile, equipSlot: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local code = slot.equip[equipSlot]
	if not code or code == 0 then
		return "InvalidPayload"
	elseif #slot.inventory >= Schema.INVENTORY_MAX then
		return "InventoryFull"
	end
	slot.equip[equipSlot] = 0
	table.insert(slot.inventory, code)
	return nil
end

-- Enchant: weapons and rings/amulets only, (grade + 1) * 2 gems, always succeeds, capped by grade limit
-- (E03 §2.3, E05 B8).
local function enchant(profile: Profile, where: string, index: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	local list = if where == "equip" then slot.equip else slot.inventory
	local code = list[index]
	if where ~= "equip" and where ~= "inv" or not code or code == 0 then
		return "InvalidPayload"
	end
	local category, num, grade = Schema.decodeItem(code)
	if not weaponRows(category) then
		return "InvalidPayload"
	elseif grade >= Schema.gradeLimit(slot) then
		return "MaxLevel"
	end
	local gems = (grade + 1) * 2
	if profile.gems < gems then
		return "InsufficientGems"
	end
	profile.gems -= gems
	list[index] = Schema.encodeItem(category, num, grade + 1)
	return nil
end

local function gemShop(profile: Profile, item: number): string?
	local slot, problem = slotOf(profile)
	if not slot then
		return problem
	end
	if item == 1 then
		if profile.ringSlotUnlocked then
			return "MaxLevel"
		elseif profile.gems < RING_SLOT_GEMS then
			return "InsufficientGems"
		end
		profile.gems -= RING_SLOT_GEMS
		profile.ringSlotUnlocked = true
	elseif item == 2 then
		if profile.gems < GOLD_PACK_GEMS then
			return "InsufficientGems"
		end
		profile.gems -= GOLD_PACK_GEMS
		addGold(slot, GOLD_PACK)
		Achievements.evaluate(profile, slot, nil)
	elseif item == 3 then
		if #slot.inventory >= Schema.INVENTORY_MAX then
			return "InventoryFull"
		elseif profile.gems < GOLDEN_WEAPON_GEMS then
			return "InsufficientGems"
		end
		profile.gems -= GOLDEN_WEAPON_GEMS
		local category = if slot.heroKind == "light" then C.mace else C.sword
		table.insert(slot.inventory, Schema.encodeItem(category, 11, 0))
	elseif item == 9 then
		return resetSkills(profile)
	else
		return "InvalidPayload"
	end
	return nil
end

return table.freeze({
	createSlot = createSlot,
	deleteSlot = deleteSlot,
	selectSlot = selectSlot,
	upgradeUnit = upgradeUnit,
	learnSkill = learnSkill,
	resetSkills = resetSkills,
	buyItem = buyItem,
	sellItem = sellItem,
	equip = equip,
	unequip = unequip,
	enchant = enchant,
	gemShop = gemShop,
	goldPrice = goldPrice,
	saleValue = saleValue,
	gearBase = gearBase,
})
