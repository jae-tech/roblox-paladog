--!strict
-- Server-only persistence contracts (DATA_MODELS §5, ARCHITECTURE §8). P8 supplies the DataStore adapter.

export type ActiveRun = {
	ordinal: number,
	matchId: string,
	stageId: string,
	balanceHash: string,
	startOperationId: string,
}

export type Receipt = { id: string, kind: string, revision: number }

export type ProfileV1 = {
	schemaVersion: number,
	revision: number,
	gold: number,
	totalXp: number,
	heroLevel: number,
	unspentPoints: number,
	heroTraits: { [string]: number },
	unitLevels: { [string]: number },
	stageProgress: { [string]: { wins: number, bestTicks: number? } },
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
	}?,
	recentOperations: { Receipt },
	lease: { sessionId: string, ownerJobId: string, expiresAt: number }?,
}

export type SessionKey = { sessionId: string, jobId: string }
export type Session = { sessionId: string, jobId: string, fenceEpoch: number }

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
