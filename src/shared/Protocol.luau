--!strict
-- Client->server payload validation (remake protocol v2). Every check is O(fixed size): key scans stop after
-- MAX_KEYS, values must be strings/numbers, every field has a closed integer range or string set per kind.
local Types = require("./Types")

local VERSION = 2
local MAX_KEYS = 8
local MAX_INTEGER = 2147483647

local LIMITS = table.freeze({
	discreteRate = 10,
	discreteBurst = 20,
	moveRate = 20,
	moveBurst = 30,
	bootstrapRate = 1,
	bootstrapBurst = 2,
	queueCapacity = 32,
	ackCacheSize = 128,
	moveTtlTicks = 15, -- 0.5 s at 30 Hz
	maxMatches = 4,
	receiptCap = 64,
	profileQueueCap = 4,
	ticksPerSecond = 30,
})

local REASONS = table.freeze({
	"NotReady",
	"InvalidPayload",
	"ProtocolMismatch",
	"NotOwner",
	"WrongPhase",
	"WrongMode",
	"LockedStage",
	"StaleRevision",
	"StaleCommand",
	"RateLimited",
	"InsufficientFood",
	"InsufficientMana",
	"InsufficientGold",
	"InsufficientGems",
	"Cooldown",
	"Busy",
	"UnitCap",
	"MaxLevel",
	"NoPoints",
	"NoSlot",
	"SlotTaken",
	"Locked",
	"InventoryFull",
	"StorageUnavailable",
	"SessionLost",
})

local BATTLE = { "matchId", "commandSeq" }
-- kind -> fields that must all be present (besides protocolVersion/requestId/kind); nothing else is accepted.
local FIELDS: { [string]: { string } } = {
	StartStage = { "stage", "expectedRevision" },
	Summon = { "matchId", "commandSeq", "unit", "lane" },
	Mace = { "matchId", "commandSeq", "slot", "unit", "lane" },
	Box = { "matchId", "commandSeq", "index" },
	PickSkill = { "matchId", "commandSeq", "choice" },
	Revive = BATTLE,
	GiveUp = BATTLE,
	Retreat = BATTLE,
	ReturnToLobby = { "matchId" },
	CreateSlot = { "slot", "heroKind", "difficulty", "expectedRevision" },
	DeleteSlot = { "slot", "expectedRevision" },
	SelectSlot = { "slot", "expectedRevision" },
	UpgradeUnit = { "unit", "expectedRevision" },
	LearnSkill = { "skill", "expectedRevision" },
	ResetSkills = { "expectedRevision" },
	BuyItem = { "category", "num", "expectedRevision" },
	SellItem = { "index", "expectedRevision" },
	Equip = { "index", "slot", "expectedRevision" },
	Unequip = { "slot", "expectedRevision" },
	Enchant = { "where", "index", "expectedRevision" },
	GemShop = { "item", "expectedRevision" },
}

-- Integer ranges; a kind-specific entry overrides the default for that field.
local RANGE: { [string]: { number } } = {
	commandSeq = { 1, MAX_INTEGER },
	expectedRevision = { 0, MAX_INTEGER },
	stage = { 0, 120 }, -- 0 = survival
	unit = { 1, 9 },
	lane = { 0, 5 },
	slot = { 1, 3 },
	index = { 1, 100 },
	choice = { 1, 3 },
	skill = { 1, 24 },
	difficulty = { 0, 3 },
	category = { 1, 10 },
	num = { 1, 11 },
	item = { 1, 9 },
}
local KIND_RANGE: { [string]: { [string]: { number } } } = {
	Mace = { unit = { 0, 9 } }, -- unit/lane only matter for tower buttons
	Box = { index = { 1, 9 } },
	Equip = { slot = { 1, 9 } },
	Unequip = { slot = { 1, 9 } },
	Enchant = { index = { 1, 100 } },
}
local STRINGS: { [string]: { [string]: boolean } } = {
	heroKind = { light = true, shadow = true },
	where = { inv = true, equip = true },
}

local function isInteger(value: unknown, low: number, high: number): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= low
		and value <= high
end

local function isToken(value: unknown, minLength: number, maxLength: number): boolean
	return type(value) == "string"
		and #value >= minLength
		and #value <= maxLength
		and string.find(value, "^[%w_%-]+$") ~= nil
end

-- Bounded shape check: a plain table of at most MAX_KEYS string keys whose values are strings/numbers.
local function flatFields(payload: unknown): { [string]: any }?
	if typeof(payload) ~= "table" then
		return nil
	end
	local count = 0
	for key, value in payload :: { [any]: any } do
		count += 1
		if count > MAX_KEYS or type(key) ~= "string" then
			return nil
		end
		local valueType = typeof(value)
		if valueType ~= "string" and valueType ~= "number" then
			return nil
		end
	end
	return payload :: { [string]: any }
end

local function onlyKeys(fields: { [string]: any }, allowed: { [string]: boolean }): boolean
	for key in fields do
		if not allowed[key] then
			return false
		end
	end
	return true
end

local function versionReason(fields: { [string]: any }): Types.Reason?
	local version = fields.protocolVersion
	if version == VERSION then
		return nil
	end
	return if isInteger(version, 0, MAX_INTEGER) then "ProtocolMismatch" else "InvalidPayload"
end

local function validField(kind: string, name: string, value: any): boolean
	if name == "matchId" then
		return isToken(value, 1, 64)
	end
	local set = STRINGS[name]
	if set then
		return type(value) == "string" and set[value] == true
	end
	local override = KIND_RANGE[kind]
	local range = (override and override[name]) or RANGE[name]
	return range ~= nil and isInteger(value, range[1], range[2])
end

local function validateCommand(payload: unknown): (Types.ClientCommand?, Types.Reason?)
	local fields = flatFields(payload)
	if not fields then
		return nil, "InvalidPayload"
	end
	local reason = versionReason(fields)
	if reason then
		return nil, reason :: Types.Reason
	end
	local kind = fields.kind
	local required = if type(kind) == "string" then FIELDS[kind] else nil
	if not required or not isToken(fields.requestId, 16, 64) then
		return nil, "InvalidPayload"
	end
	local allowed: { [string]: boolean } = { protocolVersion = true, requestId = true, kind = true }
	local command: { [string]: any } =
		{ protocolVersion = VERSION, requestId = fields.requestId, kind = kind }
	for _, name in required do
		allowed[name] = true
		if not validField(kind, name, fields[name]) then
			return nil, "InvalidPayload"
		end
		command[name] = fields[name]
	end
	if not onlyKeys(fields, allowed) then
		return nil, "InvalidPayload"
	end
	return table.freeze(command) :: any, nil
end

local MOVE_KEYS = { protocolVersion = true, matchId = true, seq = true, axis = true }

local function validateMove(payload: unknown): (Types.MoveIntent?, Types.Reason?)
	local fields = flatFields(payload)
	if not fields then
		return nil, "InvalidPayload"
	end
	local reason = versionReason(fields)
	if reason then
		return nil, reason :: Types.Reason
	end
	local axis = fields.axis
	if
		not onlyKeys(fields, MOVE_KEYS)
		or not isToken(fields.matchId, 1, 64)
		or not isInteger(fields.seq, 1, MAX_INTEGER)
		or not (axis == -1 or axis == 0 or axis == 1)
	then
		return nil, "InvalidPayload"
	end
	local intent: Types.MoveIntent =
		{ protocolVersion = VERSION, matchId = fields.matchId, seq = fields.seq, axis = axis }
	return table.freeze(intent) :: Types.MoveIntent, nil
end

local BOOTSTRAP_KEYS = { protocolVersion = true }

local function validateBootstrap(payload: unknown): Types.Reason?
	local fields = flatFields(payload)
	if not fields or not onlyKeys(fields, BOOTSTRAP_KEYS) then
		return "InvalidPayload"
	end
	return versionReason(fields)
end

-- requestId to echo in a rejection; never trusts more than a bounded token.
local function echoRequestId(payload: unknown): string
	if typeof(payload) == "table" then
		local ok, value = pcall(function()
			return (payload :: any).requestId
		end)
		if ok and isToken(value, 1, 64) then
			return value
		end
	end
	return ""
end

local BATTLE_KINDS = table.freeze({
	Summon = true,
	Mace = true,
	Box = true,
	PickSkill = true,
	Revive = true,
	GiveUp = true,
	Retreat = true,
})

return table.freeze({
	VERSION = VERSION,
	LIMITS = LIMITS,
	REASONS = REASONS,
	BATTLE_KINDS = BATTLE_KINDS,
	FIELDS = FIELDS,
	validateCommand = validateCommand,
	validateMove = validateMove,
	validateBootstrap = validateBootstrap,
	echoRequestId = echoRequestId,
})
