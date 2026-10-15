--!strict
-- Headless simulation state (DATA_MODELS §4). Plain data only: no Instances, callbacks or render state.

export type Team = "Ally" | "Enemy"
export type EntityKind = "Hero" | "Ally" | "Enemy" | "Objective"
export type EntityStateName = "Idle" | "Advancing" | "Windup" | "Recovery" | "Cooldown" | "Dead"

export type AttackDef = {
	kind: string,
	windupTicks: number,
	recoveryTicks: number,
	cooldownTicks: number,
	projectileId: string?,
}

export type Entity = {
	entityId: number,
	definitionId: string,
	kind: EntityKind,
	team: Team,
	laneId: number,
	x: number,
	facing: number,
	hp: number,
	maxHp: number,
	attackPower: number,
	moveSpeed: number,
	attackRange: number,
	hitRadius: number,
	state: EntityStateName,
	stateUntilTick: number,
	targetId: number?,
	inSupport: boolean,
	attackSerial: number,
	breachReturn: boolean,
	attack: AttackDef?,
	killGold: number,
	killXp: number,
}

export type Resources = {
	foodMilli: number,
	manaMilli: number,
	foodRemainder: number,
	manaRemainder: number,
	foodRateMilli: number,
	manaRateMilli: number,
	foodMaxMilli: number,
	manaMaxMilli: number,
	summonReadyTick: { number },
	skillReadyTick: number,
}

export type Hit = {
	attackerId: number,
	targetId: number,
	damage: number,
	releaseTick: number,
	attackSerial: number,
}

-- Ranged releases of the current tick, handed to the projectile system.
-- Cleared at the start of every step, so the list never grows across a match.
export type ProjectileRequest = {
	ownerId: number,
	targetId: number?,
	projectileId: string,
	damage: number,
	releaseTick: number,
	x: number,
	direction: number,
	attackSerial: number?,
}

export type Projectile = {
	entityId: number,
	definitionId: string,
	ownerEntityId: number,
	team: Team,
	laneId: number,
	x: number,
	previousX: number,
	direction: number,
	damage: number,
	attackSerial: number,
	spawnTick: number,
	expireTick: number,
	distanceRemaining: number,
	remainingPierce: number,
	hitEntityIds: { [number]: boolean },
}

export type HeroAction = {
	skillId: string?,
	releaseTick: number?,
	endTick: number?,
	reservedProjectileSlot: boolean,
}

export type Death = { entityId: number, definitionId: string, kind: EntityKind, tick: number }

export type CommandResult = {
	requestId: string?,
	commandSeq: number?,
	status: string,
	reason: string?,
}

export type World = {
	tick: number,
	stageId: string,
	stage: { [string]: any },
	entities: { [number]: Entity },
	order: { number },
	nextEntityId: number,
	heroId: number,
	coreId: number,
	resources: Resources,
	supportRadius: number,
	supportDamageNumerator: number,
	unitLevels: { [string]: number },
	limits: { allyCap: number, enemyCap: number, projectileCap: number },
	outcome: string?,
	outcomeTick: number?,
	pendingKillGold: number,
	pendingKillXp: number,
	killCounts: { [string]: number },
	projectileRequests: { ProjectileRequest },
	projectiles: { [number]: Projectile },
	projectileOrder: { number },
	projectileCount: number,
	heroAction: HeroAction,
	trace: { string }?,
}

return {}
