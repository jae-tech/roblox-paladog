--!strict
-- Pure text and number views for the remake UI (no Instances). Formulas mirror the server rules only for
-- display; the server stays authoritative for every purchase and battle effect.
local Text = {}

local CATEGORY_KEY = {
	"maces",
	"rings",
	"helmets",
	"armors",
	"horses",
	"swords",
	"amulets",
	"darkHelmets",
	"darkArmors",
	"darkFeet",
}
local WEAPON_CATEGORY = { [1] = true, [6] = true }
local RING_CATEGORY = { [2] = true, [7] = true }
local SLOT_NAMES = {
	"무기 1",
	"무기 2",
	"무기 3",
	"반지 1",
	"반지 2",
	"반지 3",
	"투구",
	"갑옷",
	"탈것",
}
local SHADOW_SLOT_NAMES =
	{ "검 1", "검 2", "검 3", "부적 1", "부적 2", "부적 3", "투구", "갑옷", "신발" }

function Text.decode(code: number): (number, number, number)
	return code // 100000, (code // 1000) % 100, code % 1000
end

function Text.encode(category: number, num: number, grade: number): number
	return category * 100000 + num * 1000 + grade
end

function Text.slotName(heroKind: string, index: number): string
	return (if heroKind == "shadow" then SHADOW_SLOT_NAMES else SLOT_NAMES)[index] or "?"
end

local function rows(catalog: any, category: number): { any }
	local key = CATEGORY_KEY[category]
	if category == 1 or category == 6 then
		return catalog[key]
	end
	return catalog.gear[key]
end

local function nameOf(catalog: any, category: number, num: number): string
	local key = CATEGORY_KEY[category]
	if category == 1 or category == 6 then
		local row = catalog[key][num]
		return if row then row.name else "?"
	end
	local names = catalog.gearNames[key]
	return names and names[num] or "?"
end

function Text.itemName(catalog: any, code: number): string
	local category, num, grade = Text.decode(code)
	local name = nameOf(catalog, category, num)
	return if grade > 0 then string.format("%s +%d", name, grade) else name
end

local function trim(value: number): string
	if value % 1 == 0 then
		return tostring(value)
	end
	return (string.gsub(string.format("%.3f", value), "%.?0+$", ""))
end

-- Weapon main/sub values at a grade (A + B*g), matching E03 §3.1 / §3.2.
local WEAPON_TEXT = {
	"전방 관통 탄 %s 피해",
	"주변 아군 체력 %s 회복",
	"전방 300 안 적에게 %s 피해, 낮은 확률 즉사",
	"빙결 탄 %s 피해",
	"낙뢰 %s 피해",
	"전방 불꽃 %s 피해",
	"유성 %s 피해",
	"주변 적을 %s 밀쳐냄",
	"식량 %s 회복",
	"맞힌 적 초당 %s 중독",
	"골드 1000 소모, %s 피해",
}
local SWORD_TEXT = {
	"%s 피해",
	"관통 바람 %s 피해",
	"%s 피해, 체력 흡수",
	"독 안개 초당 %s",
	"%s 피해, 넘어뜨림",
	"%s 피해, 식량 흡수",
	"%s 피해, 적을 순간이동",
	"%s 피해, 빙결",
	"%s 피해, 화상",
	"번개 %s 피해",
	"골드 1000 소모, %s 피해",
}
local RING_TEXT = {
	"처치 EXP +%s%%",
	"처치 골드 +%s%%",
	"아이템 발견 +%s",
	"최대 체력 +%s",
	"5초마다 체력 +%s",
	"이동 속도 +%s",
	"최대 마나 +%s",
	"마나 재생 +%s/0.1초",
	"식량 재생 +%s/0.1초",
	"최대 식량 +%s",
}
local GEAR_TEXT: { [number]: { string } } = {
	[3] = {
		"빛 안 아군 수만큼 식량 재생 +%s",
		"5초마다 체력 +%s",
		"마나 재생 +%s/0.1초",
		"맞을 때마다 마나 +%s",
		"아군이 쓰러질 때 마나 +%s",
		"아이템 발견 +%s%%p",
		"처치 골드 +%s%%",
		"최대 식량 +%s",
		"식량 재생 +%s/0.1초",
		"처치 EXP +%s%%",
	},
	[4] = {
		"빛 안 아군 수만큼 마나 재생 +%s",
		"최대 체력 +%s",
		"최대 마나 +%s",
		"맞을 때마다 식량 +%s",
		"아군이 쓰러질 때 식량 +%s",
	},
	[5] = {
		"빛 안 아군 수만큼 아군 공격 x(1+%s)",
		"받는 피해 x%s",
		"빛 회복 때 최대 체력의 %s 추가",
		"받은 피해의 %s 반사",
		"아군이 쓰러질 때 체력 +%s",
	},
}

function Text.itemDescription(catalog: any, code: number): string
	local category, num, grade = Text.decode(code)
	local row = rows(catalog, category)[num]
	if not row then
		return ""
	end
	if WEAPON_CATEGORY[category] then
		local value = if category == 1 and num == 10
			then row.a2 + row.b2 * grade
			else row.a1 + row.b1 * grade
		local template = (if category == 1 then WEAPON_TEXT else SWORD_TEXT)[num] or "%s"
		local cost = if num == 11
			then "골드 1000"
			else "마나 " .. trim(row.manaA + row.manaB * grade)
		return string.format(template, trim(value)) .. " · " .. cost
	end
	local value = if category == 5 and num == 2
		then row.a - row.b * grade
		else row.a + row.b * grade
	local list = if RING_CATEGORY[category]
		then RING_TEXT
		else (GEAR_TEXT[category] or GEAR_TEXT[category - 5])
	local template = list and list[num] or "%s"
	return string.format(template, trim(value))
end

-- Gold price of a grade-0 weapon/ring; gems for gear (D-SHOP-01). Returns (amount, currency).
function Text.buyPrice(catalog: any, category: number, num: number): (number?, string)
	local row = rows(catalog, category)[num]
	if not row then
		return nil, "gold"
	end
	if WEAPON_CATEGORY[category] or RING_CATEGORY[category] then
		if row.priceBase <= 0 then
			return nil, "gold"
		end
		return row.priceBase, "gold"
	end
	return 100 * (1 + (num - 1) % 5), "gems"
end

function Text.saleValue(catalog: any, code: number): number
	local category, num, grade = Text.decode(code)
	local row = rows(catalog, category)[num]
	if WEAPON_CATEGORY[category] or RING_CATEGORY[category] then
		return (row.priceBase + row.priceMulti * grade * grade) // 2
	end
	local base = 100 * (1 + (num - 1) % 5)
	return math.floor(base + base * 0.1 * grade * grade)
end

function Text.canEnchant(code: number): boolean
	local category = code // 100000
	return WEAPON_CATEGORY[category] == true or RING_CATEGORY[category] == true
end

function Text.enchantCost(code: number): number
	return (code % 1000 + 1) * 2
end

function Text.weaponCost(catalog: any, slot: any, code: number): string
	local category, num, grade = Text.decode(code)
	local row = rows(catalog, category)[num]
	if num == 11 then
		return "1000G"
	end
	local master = if category == 1 then slot.skills[10] else slot.skills[8]
	local effective = grade + (if category == 1 then slot.skills[22] else slot.skills[23])
	return tostring(math.floor((row.manaA + row.manaB * effective) * (1 - 0.1 * master)))
end

function Text.number(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

function Text.stageLabel(stage: number): string
	return string.format("%d-%d", (stage - 1) // 24 + 1, (stage - 1) % 24 + 1)
end

local MODE_NAME =
	{ Normal = "", Boss = "보스", Destiny = "운명", Wagon = "호위", Tower = "점령" }
function Text.modeName(mode: string): string
	return MODE_NAME[mode] or ""
end

function Text.unitName(catalog: any, heroKind: string, n: number): string
	local list = if heroKind == "shadow" then catalog.totems else catalog.units
	return list[n] and list[n].name or "?"
end

function Text.questText(catalog: any, heroKind: string, quest: any): string
	local template = catalog.text.quest[tostring(quest.type)] or "?"
	local unit = if quest.type == 13 or quest.type == 14
		then Text.unitName(catalog, heroKind, quest.a)
		else ""
	local text = string.gsub(template, "{a}", tostring(quest.a))
	text = string.gsub(text, "{b}", tostring(quest.b))
	text = string.gsub(text, "{unit}", unit)
	return text
end

function Text.questReward(catalog: any, quest: any): string
	if quest.gold > 0 then
		return Text.number(quest.gold) .. "G"
	end
	if quest.item and quest.item.num > 0 then
		local category = if quest.item.category == "mace" then 1 else 2
		return Text.itemName(catalog, Text.encode(category, quest.item.num, quest.item.grade))
	end
	return ""
end

-- Seconds left on a unit button (E02 §5: cooldown x (6 - leadership)/6), from the snapshot tick counter.
function Text.cooldownLeft(
	catalog: any,
	heroKind: string,
	n: number,
	leadership: number,
	past: number
): number
	local list = if heroKind == "shadow" then catalog.totems else catalog.units
	local need = list[n].cooldown * (if heroKind == "light" then (6 - leadership) / 6 else 1)
	return math.max(0, need - past / 30)
end

local REASONS: { [string]: string } = {
	InsufficientFood = "식량이 부족합니다",
	InsufficientMana = "마나가 부족합니다",
	InsufficientGold = "골드가 부족합니다",
	InsufficientGems = "보석이 부족합니다",
	Cooldown = "아직 준비 중입니다",
	Busy = "처리 중입니다",
	UnitCap = "아군이 너무 많습니다",
	MaxLevel = "더 올릴 수 없습니다",
	NoPoints = "남은 포인트가 없습니다",
	NoSlot = "기록을 먼저 고르세요",
	SlotTaken = "이미 사용 중인 기록입니다",
	Locked = "아직 잠겨 있습니다",
	InventoryFull = "가방이 가득 찼습니다",
	LockedStage = "이전 스테이지를 먼저 깨세요",
	WrongMode = "지금은 쓸 수 없는 명령입니다",
	WrongPhase = "지금은 쓸 수 없습니다",
	StaleRevision = "최신 정보로 갱신했습니다. 다시 시도하세요",
	NotReady = "서버 준비를 기다립니다",
	StorageUnavailable = "저장소를 쓸 수 없습니다",
	SessionLost = "다른 곳에서 접속해 세션이 끝났습니다",
	ProtocolMismatch = "버전이 달라 연결할 수 없습니다",
	RateLimited = "입력이 너무 빠릅니다",
	InvalidPayload = "잘못된 요청입니다",
}
function Text.reason(reason: string?): string
	if not reason then
		return ""
	end
	return REASONS[reason] or reason
end

return table.freeze(Text)
