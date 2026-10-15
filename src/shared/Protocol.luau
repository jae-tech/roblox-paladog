--!strict
-- Client->server payload validation (ARCHITECTURE §6.1, DATA_MODELS §6). Every check is O(fixed size):
-- key scans stop after MAX_KEYS, values must be strings/numbers, ids come from closed sets.
local Types = require("./Types")
local Catalog = require("./PublicCatalog")

local VERSION = 1
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
	moveTtlTicks = 10,
	maxMatches = 4,
	receiptCap = 64,
	profileQueueCap = 4,
})

local REASONS = table.freeze({
	"NotReady",
	"InvalidPayload",
	"ProtocolMismatch",
	"NotOwner",
	"WrongPhase",
	"LockedStage",
	"StaleRevision",
	"StaleCommand",
	"RateLimited",
	"InsufficientFood",
	"InsufficientMana",
	"InsufficientGold",
	"Cooldown",
	"Busy",
	"UnitCap",
	"ProjectileCap",
	"MaxLevel",
	"NoPoints",
	"StorageUnavailable",
	"SessionLost",
})

-- kind -> fields that must all be present (besides protocolVersion/requestId/kind); nothing else is accepted.
local FIELDS: { [string]: { string } } = {
	StartStage = { "stageId", "expectedRevision" },
	Summon = { "matchId", "commandSeq", "slot" },
	Cast = { "matchId", "commandSeq", "slot" },
	UpgradeUnit = { "unitId", "expectedRevision" },
	AllocatePoint = { "traitId", "expectedRevision" },
	ReturnToLobby = { "matchId" },
}
local SLOT_MAX: { [string]: number } = { Summon = 3, Cast = 1 }

local function idSet(entries: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for id in entries do
		set[id] = true
	end
	return table.freeze(set)
end
local STAGE_IDS = idSet(Catalog.stages)
local UNIT_IDS = idSet(Catalog.units)
local TRAIT_IDS = idSet(Catalog.traits)

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
	elseif name == "commandSeq" then
		return isInteger(value, 1, MAX_INTEGER)
	elseif name == "slot" then
		return isInteger(value, 1, SLOT_MAX[kind])
	elseif name == "expectedRevision" then
		return isInteger(value, 0, MAX_INTEGER)
	elseif name == "stageId" then
		return type(value) == "string" and STAGE_IDS[value] == true
	elseif name == "unitId" then
		return type(value) == "string" and UNIT_IDS[value] == true
	elseif name == "traitId" then
		return type(value) == "string" and TRAIT_IDS[value] == true
	end
	return false
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
	for _, name in required do
		allowed[name] = true
		if not validField(kind, name, fields[name]) then
			return nil, "InvalidPayload"
		end
	end
	if not onlyKeys(fields, allowed) then
		return nil, "InvalidPayload"
	end
	local command: Types.ClientCommand = {
		protocolVersion = VERSION,
		requestId = fields.requestId,
		kind = kind,
		matchId = fields.matchId,
		commandSeq = fields.commandSeq,
		slot = fields.slot,
		stageId = fields.stageId,
		unitId = fields.unitId,
		traitId = fields.traitId,
		expectedRevision = fields.expectedRevision,
	}
	return table.freeze(command) :: Types.ClientCommand, nil
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

return table.freeze({
	VERSION = VERSION,
	LIMITS = LIMITS,
	REASONS = REASONS,
	validateCommand = validateCommand,
	validateMove = validateMove,
	validateBootstrap = validateBootstrap,
	echoRequestId = echoRequestId,
})
