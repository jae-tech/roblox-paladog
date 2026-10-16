--!strict
-- Network DTO and session-phase contracts shared by server and client (remake protocol v2).

export type Phase =
	"ProfileLoading"
	| "LobbyReady"
	| "Preparing"
	| "Running"
	| "Settling"
	| "Settled"
	| "Unavailable"

export type CommandKind =
	"StartStage"
	| "Summon"
	| "Mace"
	| "Box"
	| "PickSkill"
	| "Revive"
	| "GiveUp"
	| "Retreat"
	| "Jump"
	| "ReturnToLobby"
	| "CreateSlot"
	| "DeleteSlot"
	| "SelectSlot"
	| "UpgradeUnit"
	| "LearnSkill"
	| "ResetSkills"
	| "BuyItem"
	| "SellItem"
	| "Equip"
	| "Unequip"
	| "Enchant"
	| "GemShop"

export type Reason =
	"NotReady"
	| "InvalidPayload"
	| "ProtocolMismatch"
	| "NotOwner"
	| "WrongPhase"
	| "WrongMode"
	| "LockedStage"
	| "StaleRevision"
	| "StaleCommand"
	| "RateLimited"
	| "InsufficientFood"
	| "InsufficientMana"
	| "InsufficientGold"
	| "InsufficientGems"
	| "Cooldown"
	| "Busy"
	| "UnitCap"
	| "MaxLevel"
	| "NoPoints"
	| "NoSlot"
	| "SlotTaken"
	| "Locked"
	| "InventoryFull"
	| "StorageUnavailable"
	| "SessionLost"

export type MessageStatus = "Accepted" | "Rejected" | "Pending" | "Committed"

-- Validated command: only the fields allowed for `kind` are present (Protocol.validateCommand).
export type ClientCommand = {
	protocolVersion: number,
	requestId: string,
	kind: CommandKind,
	matchId: string?,
	commandSeq: number?,
	expectedRevision: number?,
	stage: number?,
	unit: number?,
	lane: number?,
	slot: number?,
	index: number?,
	choice: number?,
	skill: number?,
	heroKind: string?,
	difficulty: number?,
	category: number?,
	num: number?,
	where: string?,
	item: number?,
}

export type MoveIntent = {
	protocolVersion: number,
	matchId: string,
	seq: number,
	axis: number,
	strafe: number?,
}

export type ProfileSummary = { [string]: any }

export type ServerMessage = {
	requestId: string,
	status: MessageStatus,
	reason: Reason?,
	serverTick: number,
	profileRevision: number?,
	matchId: string?,
	profileSummary: ProfileSummary?,
}

return {}
