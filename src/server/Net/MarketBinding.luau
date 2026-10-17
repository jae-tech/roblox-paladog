--!strict
-- MarketplaceService binding for the Robux store (D-PAY-01). Prompts are opened by the server, receipts are
-- granted inside a profile transaction and acknowledged only after the committed document carries the
-- receipt id, so a retried receipt never pays twice. Pass ownership is read on join and on purchase.
-- Client-facing state: ReplicatedStorage.Store attributes Price<i> (0 = 준비 중) and player attributes
-- PassGoldExp / PassSpeed / PassVip (true when owned).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Store = require("../Services/Store")
local StoreIds = require("./StoreIds")

local RECEIPT_TIMEOUT = 20 -- seconds to wait for the profile commit inside ProcessReceipt

local function itemOfProduct(productId: number): number?
	for item, id in StoreIds.products do
		if id ~= 0 and id == productId then
			return item
		end
	end
	return nil
end

local function itemOfPass(passId: number): number?
	for item, id in StoreIds.passes do
		if id ~= 0 and id == passId then
			return item
		end
	end
	return nil
end

local NONE: { [string]: boolean } = {}

local function bind(profiles: any, match: any)
	local folder = ReplicatedStorage:FindFirstChild("Store") or Instance.new("Folder")
	folder.Name = "Store"
	folder.Parent = ReplicatedStorage
	-- prices for the shop (fetched once; an item without an id stays 0)
	for item = 1, 9 do
		folder:SetAttribute("Price" .. item, 0)
	end
	task.spawn(function()
		local function price(item: number, id: number, infoType: Enum.InfoType)
			if id == 0 then
				return
			end
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				folder:SetAttribute("Price" .. item, info.PriceInRobux)
			end
		end
		for item, id in StoreIds.products do
			price(item, id, Enum.InfoType.Product)
		end
		for item, id in StoreIds.passes do
			price(item, id, Enum.InfoType.GamePass)
		end
	end)

	local owned: { [number]: { [string]: boolean } } = {}
	local function publish(player: Player)
		local passes = owned[player.UserId] or NONE
		for _, key in Store.PASSES do
			local name = "Pass" .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
			player:SetAttribute(name, passes[key] == true)
		end
		match.setPasses(player.UserId, passes)
	end

	-- VIP name tag over the avatar's head
	local function tag(player: Player)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local vip = (owned[player.UserId] or NONE).vip == true
		local old = head and head:FindFirstChild("VipTag")
		if old and not vip then
			old:Destroy()
		elseif head and vip and not old then
			local gui = Instance.new("BillboardGui")
			gui.Name = "VipTag"
			gui.Size = UDim2.fromOffset(60, 22)
			gui.StudsOffset = Vector3.new(0, 2.6, 0)
			gui.AlwaysOnTop = true
			gui.MaxDistance = 80
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(240, 190, 60)
			label.TextColor3 = Color3.fromRGB(40, 28, 10)
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.Text = "VIP"
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = label
			label.Parent = gui
			gui.Parent = head
		end
	end

	local function joined(player: Player)
		local passes: { [string]: boolean } = {}
		owned[player.UserId] = passes
		for item, id in StoreIds.passes do
			if id ~= 0 then
				local ok, has = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
				end)
				if ok and has then
					passes[Store.PASSES[item]] = true
				end
			end
		end
		publish(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			tag(player)
		end)
		tag(player)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player.UserId] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local item = itemOfPass(passId)
		-- the event updates the ownership cache; ownership is still confirmed before the pass applies
		local ok, has = pcall(function()
			return purchased and MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if item and ok and has then
			local passes: { [string]: boolean } = owned[player.UserId] or {}
			owned[player.UserId] = passes
			passes[Store.PASSES[item]] = true
			publish(player)
			tag(player)
		end
		match.purchaseClosed(player.UserId, purchased == true)
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		match.purchaseClosed(userId, purchased == true)
	end)

	-- Receipts: granted once, acknowledged only after the commit carries the receipt id.
	MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		local item = itemOfProduct(info.ProductId)
		local purchaseId = tostring(info.PurchaseId)
		local userId = info.PlayerId
		if not item or not Players:GetPlayerByUserId(userId) then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when the player is back
		end
		local profile = profiles.profileOf(userId)
		if not profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		elseif Store.remembered(profile, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local result: any = nil
		local finished = false
		profiles.grant(userId, {
			kind = "Purchase",
			requestId = "buy-" .. string.sub(purchaseId, 1, 60),
			mutate = function(current)
				return Store.grant(current, item, purchaseId)
			end,
		}, function(saved, _reason)
			result, finished = saved, true
		end)
		local deadline = os.clock() + RECEIPT_TIMEOUT
		while not finished and os.clock() < deadline do
			task.wait(0.1)
		end
		if result and Store.remembered(result, purchaseId) then
			match.granted(userId, item, result)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- VIP daily gems: checked every few seconds for players whose profile is ready
	task.spawn(function()
		while true do
			local day = os.time() // 86400
			for _, player in Players:GetPlayers() do
				local profile = profiles.profileOf(player.UserId)
				if
					(owned[player.UserId] or NONE).vip
					and profile
					and (profile :: any).vipDay ~= day
					and match.phaseOf(player.UserId) == "LobbyReady"
				then
					profiles.grant(player.UserId, {
						kind = "VipDaily",
						requestId = "vip-" .. day,
						mutate = function(current)
							return Store.vipDaily(current, day)
						end,
					}, function(saved)
						if saved then
							match.granted(player.UserId, 0, saved)
						end
					end)
				end
			end
			task.wait(5)
		end
	end)

	-- MatchService.prompt: opens the Roblox prompt, or says why it cannot
	return function(userId: number, item: number): string?
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			return "NotReady"
		end
		local productId = StoreIds.products[item]
		local passId = StoreIds.passes[item]
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
			return nil
		elseif passId and passId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, passId)
			return nil
		end
		return "Locked" -- not created yet
	end
end

return table.freeze({
	bind = bind,
	reviveForSale = function(): boolean
		return StoreIds.products[Store.REVIVE] ~= 0
	end,
})
