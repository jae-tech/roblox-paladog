--!strict
-- Roblox ids for the store (D-PAY-01), keyed by Store item index. 0 = not created yet: that item shows as
-- "준비 중" and is never prompted. Fill these in only after the products/passes exist on the approved
-- experience (creating them is an asset/purchase action that needs the owner's approval).
return table.freeze({
	products = table.freeze({
		[1] = 0, -- 보석 50
		[2] = 0, -- 보석 120
		[3] = 0, -- 보석 300
		[4] = 0, -- 보석 800
		[5] = 0, -- 첫 구매 패키지
		[6] = 0, -- 바로 부활
	}),
	passes = table.freeze({
		[7] = 0, -- 골드·경험치 2배
		[8] = 0, -- 전투 2배속
		[9] = 0, -- VIP
	}),
})
