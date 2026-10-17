--!strict
-- Robux store (D-PAY-01): what each developer product and game pass gives. Pure profile transforms; the
-- Roblox binding (Net/MarketBinding) prompts, receives receipts and runs these inside a profile transaction.
-- Every receipt id is remembered in `purchases`, so a replayed receipt never grants twice.
local ServerTypes = require("../ServerTypes")
local Schema = require("./ProfileSchema")

type Profile = ServerTypes.ProfileV1

local PURCHASE_MEMORY = 50 -- newest receipt ids kept per profile
local REVIVE_GEMS = 20 -- one revive's gem price (D-REVIVE-01)
local VIP_DAILY_GEMS = 15
local GOLDEN_WEAPON = 11 -- item num of the golden mace/sword

-- Purchase item index (Protocol `Purchase.item`) -> contents. 1..6 are products, 7..9 game passes.
local PRODUCTS: { [number]: { key: string, gems: number, gold: number?, weapon: boolean? } } = {
	[1] = { key = "gems50", gems = 50 },
	[2] = { key = "gems120", gems = 120 },
	[3] = { key = "gems300", gems = 300 },
	[4] = { key = "gems800", gems = 800 },
	[5] = { key = "starter", gems = 100, gold = 50000, weapon = true },
	[6] = { key = "revive", gems = REVIVE_GEMS },
}
local PASSES: { [number]: string } = { [7] = "goldExp", [8] = "speed", [9] = "vip" }
local STARTER = 5
local REVIVE = 6

local function remembered(profile: Profile, purchaseId: string): boolean
	for _, id in (profile :: any).purchases or {} do
		if id == purchaseId then
			return true
		end
	end
	return false
end

-- Applies product `item` for receipt `purchaseId`; a known receipt changes nothing.
local function grant(profile: Profile, item: number, purchaseId: string): string?
	local product = PRODUCTS[item]
	if not product or type(purchaseId) ~= "string" or #purchaseId < 1 or #purchaseId > 64 then
		return "InvalidPayload"
	end
	if remembered(profile, purchaseId) then
		return nil
	end
	local view = profile :: any
	view.purchases = view.purchases or {}
	table.insert(view.purchases, purchaseId)
	while #view.purchases > PURCHASE_MEMORY do
		table.remove(view.purchases, 1)
	end
	profile.gems = math.min(profile.gems + product.gems, Schema.GEM_MAX)
	if item == STARTER then
		view.starterBought = true
	end
	-- gold and the weapon go to the current record; without one the pack still gives its gems
	local slot = Schema.currentSlot(profile)
	if slot then
		if product.gold then
			slot.gold = math.min(slot.gold + product.gold, Schema.GOLD_MAX)
		end
		if product.weapon then
			local category = if slot.heroKind == "light"
				then Schema.CATEGORY.mace
				else Schema.CATEGORY.sword
			local code = Schema.encodeItem(category, GOLDEN_WEAPON, 0)
			if #slot.inventory < Schema.INVENTORY_MAX then
				table.insert(slot.inventory, code)
			else
				slot.gold = math.min(slot.gold + 100000, Schema.GOLD_MAX) -- a full bag gets gold instead
			end
		end
	end
	return nil
end

-- VIP daily gems: once per UTC day number.
local function vipDaily(profile: Profile, day: number): string?
	local view = profile :: any
	if view.vipDay == day then
		return "MaxLevel"
	end
	view.vipDay = day
	profile.gems = math.min(profile.gems + VIP_DAILY_GEMS, Schema.GEM_MAX)
	return nil
end

-- Whether item may be offered now (prompt gate); the receipt grant itself never refuses a paid product.
local function canOffer(profile: Profile?, item: number, owned: { [string]: boolean }): string?
	if PASSES[item] then
		return if owned[PASSES[item]] then "MaxLevel" else nil
	elseif not PRODUCTS[item] then
		return "InvalidPayload"
	elseif not profile then
		return "NotReady"
	elseif
		item == STARTER and ((profile :: any).starterBought or not Schema.currentSlot(profile))
	then
		return if Schema.currentSlot(profile) then "MaxLevel" else "NoSlot"
	end
	return nil
end

return table.freeze({
	PRODUCTS = PRODUCTS,
	PASSES = PASSES,
	STARTER = STARTER,
	REVIVE = REVIVE,
	REVIVE_GEMS = REVIVE_GEMS,
	VIP_DAILY_GEMS = VIP_DAILY_GEMS,
	PURCHASE_MEMORY = PURCHASE_MEMORY,
	remembered = remembered,
	grant = grant,
	vipDaily = vipDaily,
	canOffer = canOffer,
})
