--!strict
-- Network DTO and session-phase contracts shared by server and client (DATA_MODELS §6, ARCHITECTURE §6-7).

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
	| "Cast"
	| "UpgradeUnit"
	| "AllocatePoint"
	| "ReturnToLobby"

-- DATA_MODELS §6 enum + InsufficientGold (UpgradeUnit needs it; the design enum has no gold reason).
export type Reason =
	"NotReady"
	| "InvalidPayload"
	| "ProtocolMismatch"
	| "NotOwner"
	| "WrongPhase"
	| "LockedStage"
	| "StaleRevision"
	| "StaleCommand"
	| "RateLimited"
	| "InsufficientFood"
	| "InsufficientMana"
	| "InsufficientGold"
	| "Cooldown"
	| "Busy"
	| "UnitCap"
	| "ProjectileCap"
	| "MaxLevel"
	| "NoPoints"
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
	slot: number?,
	stageId: string?,
	unitId: string?,
	traitId: string?,
	expectedRevision: number?,
}

export type MoveIntent = {
	protocolVersion: number,
	matchId: string,
	seq: number,
	axis: number,
}

export type ServerMessage = {
	requestId: string,
	status: MessageStatus,
	reason: Reason?,
	serverTick: number,
	profileRevision: number?,
	matchId: string?,
	profileSummary: ProfileSummary?,
}

export type StageProgress = { wins: number, bestTicks: number? }

export type ProfileSummary = {
	gold: number,
	totalXp: number,
	heroLevel: number,
	unspentPoints: number,
	heroTraits: { vitality: number, provisions: number, focus: number },
	unitLevels: { vanguard: number, slinger: number, bulwark: number },
	stageProgress: { [string]: StageProgress },
}

-- Complete owner-facing simulation snapshot. Projectile damage/reservations stay server-only.
export type MatchSnapshot = {
	matchId: string,
	snapshotSeq: number,
	tick: number,
	phase: Phase,
	stageId: string,
	balanceHash: string,
	inputAckSeq: number,
	commandAckSeq: number,
	stageLength: number?,
	advanceLimitX: number?,
	heroMoveSpeed: number?,
	pendingKillGold: number,
	pendingKillXp: number,
	resources: {
		foodMilli: number,
		manaMilli: number,
		foodMaxMilli: number,
		manaMaxMilli: number,
		summonReadyTick: { number },
		skillReadyTick: number,
	}?,
	heroAction: { skillId: string?, releaseTick: number?, endTick: number? },
	entities: { any },
	projectiles: { any },
	outcome: string?,
	result: {
		matchId: string,
		runOrdinal: number,
		stageId: string,
		balanceHash: string,
		seed: number,
		outcome: string,
		elapsedTicks: number,
		killCounts: { [string]: number },
		pendingKillGold: number,
		pendingKillXp: number,
	}?,
	settlementStatus: ("Pending" | "Committed" | "Failed")?,
}

export type BootstrapStatus =
	"Loading"
	| "Ready"
	| "Unavailable"
	| "RateLimited"
	| "ProtocolMismatch"

export type BootstrapResult = {
	protocolVersion: number,
	status: BootstrapStatus,
	retryAfterSeconds: number?,
	storage: string,
	balanceHash: string,
	publicCatalog: { [string]: any }?,
	phase: Phase?,
	profileRevision: number?,
	profileSummary: ProfileSummary?,
	currentMatch: MatchSnapshot?,
}

return {}
