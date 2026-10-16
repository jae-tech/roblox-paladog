--!strict
-- Server-only persistence contracts. Remake schema v2 (docs/REMAKE_PLAN.md R3, D-SLOT-01): account data plus
-- three save slots. ProfileService only relies on the run/receipt/lease fields declared here.

export type ActiveRun = {
	ordinal: number,
	matchId: string,
	slot: number,
	stage: number,
	balanceHash: string,
	startOperationId: string,
}

export type Receipt = { id: string, kind: string, revision: number }

-- Frozen by MatchService on the first terminal tick; never accepted from a client payload.
export type MatchResult = {
	matchId: string,
	runOrdinal: number,
	slot: number,
	stage: number,
	balanceHash: string,
	seed: number,
	outcome: string, -- "Victory" | "Defeat" | "Abandoned"
	elapsedTicks: number,
	gold: number,
	goldSpent: number,
	exp: number,
	levelUps: number,
	picks: { number },
	drops: number,
	revives: number,
	killTotal: number,
	quests: { boolean },
	wave: number?, -- survival: wave reached
	gems: number?, -- survival: boss gems earned
	darkUnlock: boolean?, -- survival: shadow unlock event won
}

export type Slot = {
	heroKind: string, -- "light" | "shadow"
	difficulty: number,
	gold: number,
	exp: number,
	level: number,
	skills: { number },
	freePoints: number,
	units: { number },
	stars: { number }, -- -1 locked, 0 open, 1..3 best stars
	bestSec: { number }, -- 0 = never cleared
	inventory: { number }, -- packed item codes
	equip: { number }, -- 9 packed item codes, 0 = empty
	survivalBest: number,
}

export type ProfileV1 = {
	schemaVersion: number,
	revision: number,
	gems: number,
	achievements: { number },
	darkUnlocked: boolean,
	ringSlotUnlocked: boolean,
	currentSlot: number, -- 0 = none selected
	slots: { Slot | boolean }, -- false = empty
	runCounter: number,
	lastClosedRunOrdinal: number,
	fenceEpoch: number,
	activeRun: ActiveRun?,
	lastRunResult: {
		ordinal: number,
		matchId: string,
		outcome: string,
		awardedGold: number,
		awardedXp: number,
		stars: number?,
		items: { number }?,
		gems: number?,
		wave: number?,
		darkUnlock: boolean?,
	}?,
	recentOperations: { Receipt },
	lease: { sessionId: string, ownerJobId: string, expiresAt: number }?,
}

export type SessionKey = { sessionId: string, jobId: string }
export type Session = {
	sessionId: string,
	jobId: string,
	fenceEpoch: number,
	leaseExpiresAt: number?,
}

-- `created` is true only when the store successfully read nil and wrote a new profile under the lock.
-- "invalid": an existing document failed validation; the store must NOT lock or write it (left untouched).
export type LoadResult = {
	kind: "ok" | "locked" | "invalid" | "error",
	profile: ProfileV1?,
	created: boolean?,
	message: string?,
}

export type UpdateResult = {
	kind: "ok" | "rejected" | "stale" | "error",
	profile: ProfileV1?,
	reason: string?,
	message: string?,
}

-- Transform must be pure (no yield, no outside mutation); a real store may call it more than once.
export type Transform = (ProfileV1) -> (ProfileV1?, string?)

export type StoreAdapter = {
	backend: string,
	leaseSeconds: number?, -- absent for process-local stores
	renew: ((userId: number, session: Session, now: number) -> UpdateResult)?,
	loadAndLock: (
		userId: number,
		key: SessionKey,
		now: number,
		makeNew: () -> ProfileV1,
		validate: (any) -> (boolean, string?)
	) -> LoadResult,
	update: (userId: number, session: Session, now: number, transform: Transform) -> UpdateResult,
	-- Fenced: only clears the lease when sessionId AND fenceEpoch match; fenceEpoch is never cleared.
	release: (userId: number, session: Session) -> boolean,
}

return {}
