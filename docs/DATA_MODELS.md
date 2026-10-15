# Data Models — 정의·전투 상태·프로필·통신

버전1.0 · 2026-10-15 · **설계 명세, 아래 Luau는 구현 전 타입 계약 예시**.
숫자 정본은 이 문서, 처리 순서·권한·저장 트랜잭션은 [ARCHITECTURE](ARCHITECTURE.md). 별도 출처가 없는 값은 [신규결정]이며 출시 전 밸런스 조정 대상이다.

## 1. 공통 단위·ID·버전

| 항목 | 계약 |
|---|---|
| 좌표 | 서버 전투 X는 stud, laneId=1 고정. Roblox Y는 높이, Z는 연출 깊이로 판정에 미사용 |
| 시간 | 1tick=0.05초, cooldown/release/TTL은 정수 tick. 변환 시 ceil, 공격 release 최소1tick |
| HP/AP/피해 | 음수 아닌 정수. HP는 [0,maxHP], maxHP≥1. 신규 피해는 `floor(AP*supportNumerator/100+0.5)` |
| 자원 | milli 단위 정수(1000=식량/마나1). cost도 ×1000, HUD만 floor(value/1000) 표시 |
| 재생 | milli/sec 정수. 매 tick `n=rate+remainder; plus=floor(n/20); remainder=n%20`. 상한 도달 시 remainder=0 |
| ID | original name과 무관한 string ID. 참조 DB 행·id____·UI순서를 구분하고 런타임에서는 행 번호를 ID로 쓰지 않음 |
| 수치 버전 | `configSchemaVersion=1`, `balanceVersion="mvp-proto-001"`, 생성기 SHA-256 content hash. 아직 실제 hash 산출물 없음 |
| 저장/통신 버전 | profile.schemaVersion=1, protocolVersion=1. balanceVersion과 분리 |

entityId는 경기 내 단조 증가 정수, key는 `(matchId,entityId)`. 재사용하지 않는다. 양 진영과 영웅·핵은 같은 ID 공간. 시간·위치·확률 필드는 finite 검사. `NaN/±inf`는 정상값이 아니다.

## 2. 정적 정의 타입

```luau
--!strict
export type CombatStats = {
    maxHp: number, attackPower: number, moveSpeed: number,
    attackRange: number, hitRadius: number,
}
export type AttackDef = {
    kind: "Melee" | "Projectile",
    windupTicks: number, recoveryTicks: number, cooldownTicks: number,
    projectileId: string?,
}
export type UnitLevelDef = {
    level: number, maxHp: number, attackPower: number,
    purchaseCostGold: number, -- 이 레벨에 도달하는 비용. L1 시작 보유는 무료 예외
}
export type UnitDef = {
    id: string, presentationId: string,
    foodCostMilli: number, summonCooldownTicks: number,
    moveSpeed: number, attackRange: number, hitRadius: number,
    attack: AttackDef, levels: {UnitLevelDef},
}
export type EnemyDef = {
    id: string, presentationId: string, stats: CombatStats, attack: AttackDef,
    killGold: number, killXp: number,
}
export type ProjectileDef = {
    id: string, speed: number, radius: number,
    ttlTicks: number, maxDistance: number, pierce: number,
}
export type SkillDef = {
    id: string, manaCostMilli: number, cooldownTicks: number,
    windupTicks: number, recoveryTicks: number,
    damage: number, projectileId: string,
}
export type HeroDef = {
    id: string, presentationId: string, baseMaxHp: number,
    moveSpeed: number, hitRadius: number,
    supportRadius: number, supportDamageNumerator: number,
    weaponSkillId: string,
}
export type SpawnChoice = {enemyId: string, weight: number}
export type StageDef = {
    id: string, prerequisiteId: string?, length: number,
    heroStartX: number, allySpawnX: number, enemySpawnX: number,
    coreX: number, coreMaxHp: number, coreHitRadius: number,
    slowMinTicks: number, slowMaxTicks: number,
    fastMinTicks: number, fastMaxTicks: number, blockCount: number,
    choices: {SpawnChoice}, timeLimitTicks: number,
    winGold: number, winXp: number, firstWinGold: number,
}
```

모든 정의는 로드 시 검증·freeze. 타입의 number는 Luau 표현이고, 정수/범위/참조 유효성은 runtime validator가 보장한다. 원시 참조와 provenance는 런타임 타입에 무작정 넣지 않고 생성 report에 field별 보존한다.

## 3. MVP 정적 수치

### 3.1 영웅·자원·무기

| 정의 | 값 | 근거/판단 |
|---|---|---|
| wayfinder | HP2000, 이동6stud/s, hitRadius1.5, 시작X10 | HP/속도는 E03 §1.3/1.6의 참고값60px/s×0.1. 반경1.5는 신규 |
| 지원장 | 반경7.5, 아군 공격×1.10, 영웅 자신/핵 제외 | 반경만 E03 §5의75px 참고. 효과는 신규; 유닛 스킬 게이트 아님 |
| 식량 | 시작0, 최대40000milli, 재생2000milli/s | E04 §1-2~1-4 수치 참고·채택 |
| 마나 | 시작0, 최대100000milli, 재생2000milli/s | 동일. 새 성장에 의한 재생 증가만 적용 |
| pulse | 피해100, 마나10000milli, 쿨30tick, windup4tick, recovery6tick | 피해만 E03 §3.1 80+20×등급1 참고. 등급 시스템·원작 이름은 반입 안 함; 쿨/타이밍 신규 |
| pulse_bolt | 속도25stud/s, 반경0.3, TTL20tick, 최대거리25, 관통1 | 신규. 부록 A5의 유사 숫자와 같아도 원작 메이스 매핑 확정을 뜻하지 않음 |

시전 시작 tick에 마나 차감·nextSkillTick 설정. windup 이후 오른쪽(+X) 탄을 hero.x에서 발사한다. 이동 가능하지만 windup/recovery 중 재시전 불가. 빈 공간 시전 가능·환급 없음. 영웅 사망으로 release 이전 취소 시 탄 없음, 이미 발사된 탄은 TTL까지 유효. 서버 고정 피해값이며 영웅 지원장 배율은 자신에게 적용하지 않는다.

### 3.2 아군 3종

참고: E02 §5 표/E05 B3, EA A2/A13. 새 ID·외형은 모두 오리지널. 일반 공격만 MVP 구현. 기본 행의 HP를 그대로 사용하지 않는다.

| ID / 역할 | 식량 | 소환 쿨 | 속도 stud/s | range / hitRadius | 공격 방식 | windup / recovery / cooldown (tick) |
|---|---:|---:|---:|---|---|---|
| vanguard / 저가 선봉 기계 | 10 | 20 | 3.0 | 3.5 / 1.2 | 근접 단일 | 3 / 7 / 66 |
| slinger / 원거리 발사 기계 | 20 | 40 | 2.2 | 20 / 1.2 | bolt 단일 | 5 / 7 / 100 |
| bulwark / 고내구 방호 기계 | 30 | 80 | 2.3 | 5 / 1.6 | 근접 단일 | 7 / 9 / 40 |

수치 중 비용/소환쿨/이동/사거리/cooldown은 각 쥐/토끼/곰의 참조 수치에서 의미를 변환했다. windup/recovery는 원작 애니 길이가 아니라 **새 timing**이다. cooldown은 recovery **종료 후** 대기이므로 총 공격 주기는 windup+recovery+cooldown. 최초 공격은 타깃 획득 시 즉시 windup 진입한다. 소환 쿨은 처음 ready이지만 식량은0이다.

| ID | L1~L5 HP | L1~L5 AP | L2/L3/L4/L5 도달 골드 |
|---|---|---|---|
| vanguard | 100,105,110,115,120 | 20,21,22,23,24 | 25,50,75,100 |
| slinger | 100,105,110,115,120 | 40,42,44,46,48 | 50,100,150,200 |
| bulwark | 1200,1260,1320,1380,1440 | 40,42,44,46,48 | 100,200,300,400 |

HP/AP는 EA A13 N1/2/3의 L1~5를 참고한 exact 값. 강화 비용은 그 표의 다음 레벨 비용×0.1이라는 **신규 경제 overlay**. L1은 전원 무료 지급, 원작 언락 비용2000/10000과 선행 체인은 사용하지 않는다. 공격 탄 `ally_bolt`: 속도60, 반경0.2, TTL40tick, 최대거리120stud, 관통1. 배율을 포함한 피해는 release 때 확정한다.

### 3.3 적 3종·목표

| ID / 역할 | HP/AP | 속도 | range / radius | windup/recovery/cooldown | kill G/XP | 참조 |
|---|---|---:|---|---|---|---|
| scrapper / 기본 근접 | 130/20 | 3.0 | 2 / 1.2 | 5/5/30 | 18/12 | enemy논리1, DB225, EA A4 id____10 |
| spitter / 원거리 | 80/30 | 2.0 | 10 / 1.2 | 9/5/54 | 20/13 | enemy논리2, DB226, EA A4 id____11 |
| brute / 느린 고공격 | 830/330 | 1.9 | 5 / 1.5 | 6/8/40 | 45/19 | enemy논리8, DB232, EA A4 id____17 |

수치 HP/AP/속도/범위/처치 보상은 위 행 참고. 공격 타이밍은 신규(2.67초 대기는 ceil→54tick). spitter는 `enemy_bolt`: 속도15, 반경0.2, TTL60tick, 최대거리45, 관통1. 다른 둘은 근접 단일. 보스·거대화·강화판·챕터 배수·난이도 배수 없음.

적 핵 `enemy_core`는 이동/공격/킬 보상 없는 Objective entity. 아군·영웅 탄의 표적이며 마지막 적 병력이 남아 있어도 핵 파괴 시 승리 후보다.

### 3.4 스테이지 3개 [모두 신규]

공통: 길이102.4, 영웅X10, 아군 소환X0, 적 소환X102.4, 핵X90.4/반경2.5, 시간12000tick, 영웅·아군 전진 상한86.4. 원작1024px 전장·904px 본진(E04 §6)을 스케일 참고했지만 모드/난이도/스폰표는 새로 만든다.

| ID | 선행 | 핵 HP | 느림 간격(포함 정수tick) | 빠름 간격 | 각 block마리 | scrapper/spitter/brute 가중치 | 승리 G/XP | 첫 승리 추가 G |
|---|---|---:|---|---|---:|---|---|---:|
| s01 | 없음 | 600 | 100~120 | 40~60 | 3 | 100/0/0 | 100/60 | 100 |
| s02 | s01 승리 | 900 | 80~100 | 30~50 | 5 | 70/30/0 | 150/100 | 100 |
| s03 | s02 승리 | 1400 | 70~90 | 20~40 | 6 | 50/30/20 | 220/160 | 100 |

첫 적은 느림 간격 뒤 생성. successfulSpawnCount 기준 0~blockCount-1 느림, 다음 blockCount 빠름, modulo(2*blockCount)로 반복. 명시 가중치 합100, 정수 RNG0~99. 원작의 P3=100 remainder/주기 U5/0초 interval을 이 필드로 혼용하지 않는다. 적 cap 도달 시 남은 spawnTicks를 동결, 빈자리 생긴 다음 tick부터 계속 감소; 밀린 몹을 한꺼번에 소환하지 않음. 적 스폰은 tick당 최대1.

### 3.5 경계·상한

- 영웅 X는 [0,86.4], 아군 X는 [0,86.4]. 전진 한계에서도 사거리 내 핵 타깃팅은 가능해야 한다.
- 적이 `x<=0`이면 `x=max(0,hero.x-1)`로 한 번 재배치하고 방향+1로 영웅을 향한다. 재배치한 적은 영웅 X에 도달하면 정지하고 hero만을 공격 대상으로 삼는 `breachReturn=true` 상태가 된다. hero가 왼쪽으로 지나치면 방향을 hero 방향으로 갱신한다. 매 tick 재배치 루프를 만들지 않는다. 일반 적과 다른 이 경계 동작은 신규 규칙이다.
- 엔티티 cap: 살아있는 아군30/적40, hero/core 별도. dead visual TTL은 cap 계산에서 제외하되 서버 dead record는 즉시 정리한다.
- 탄 cap128(양 진영 합). 소환은 한도 시 무차감 거부. 시전은 탄 슬롯을 reserve한 뒤 차감, windup 중 hero 사망 시 reserve 해제. 자동 원거리 공격은 슬롯 부족 시 release를 빗나감 처리, recovery로 진행. 사용자 시전 실패와 달리 별도 자원 없음.

## 4. 런타임 모델

```luau
export type EntityState = {
    entityId: number, definitionId: string,
    kind: "Hero" | "Ally" | "Enemy" | "Objective",
    team: "Ally" | "Enemy", laneId: number,
    x: number, facing: number, hp: number, maxHp: number,
    attackPower: number, moveSpeed: number, attackRange: number, hitRadius: number,
    state: "Idle" | "Advancing" | "Windup" | "Recovery" | "Cooldown" | "Dead",
    stateUntilTick: number, nextAttackTick: number, targetId: number?,
    inSupport: boolean, attackSerial: number, breachReturn: boolean,
}
export type ProjectileState = {
    entityId: number, definitionId: string, ownerEntityId: number,
    team: "Ally" | "Enemy", laneId: number,
    x: number, previousX: number, direction: number,
    damage: number, expireTick: number, distanceRemaining: number,
    remainingPierce: number, hitEntityIds: {[number]: boolean},
}
export type ResourceState = {
    foodMilli: number, manaMilli: number,
    foodRemainder: number, manaRemainder: number,
    foodRateMilli: number, manaRateMilli: number,
    summonReadyTickBySlot: {number}, skillReadyTick: number,
}
export type MatchContext = {
    matchId: string, ownerUserId: number, runOrdinal: number,
    stageId: string, balanceHash: string, seed: number, rngState: number,
    phase: string, tick: number, entities: {[number]: EntityState},
    projectiles: {[number]: ProjectileState}, resources: ResourceState,
    nextEntityId: number, lastMoveSeq: number, lastCommandSeq: number,
    moveAxis: number, moveIntentReceivedAt: number,
    successfulSpawnCount: number, nextSpawnTicks: number,
    pendingKillGold: number, pendingKillXp: number, killCounts: {[string]: number},
}
```

hero 전용 cast 상태는 `heroAction={skillId?,releaseTick?,endTick?,reservedProjectileSlot?}`로 MatchContext에 추가한다. 영웅 이동 상태와 독립이라 이동 중 시전이 가능하다. match.phase는 ARCHITECTURE의 상태 union으로 제한하고 범용 string을 그대로 외부에서 수용하지 않는다. 위 타입은 필수 관계를 보이기 위한 축약이며 `clock/config/queues`는 서비스 의존성으로 주입한다.

`attackSerial+entityId+releaseTick`으로 같은 공격 release 중복을 방지한다. 한 tick batch에서 죽은 개체는 reward eligible death를 한 번만 발생시킨다. 렌더 좌표·AnimationTrack·Instance 참조·UI timer·클라이언트 target은 상태에 넣지 않는다.

## 5. 영속 프로필·성장

```luau
export type ProfileV1 = {
    schemaVersion: number, revision: number,
    gold: number, totalXp: number, heroLevel: number, unspentPoints: number,
    heroTraits: {vitality: number, provisions: number, focus: number},
    unitLevels: {vanguard: number, slinger: number, bulwark: number},
    stageProgress: {[string]: {wins: number, bestTicks: number?}},
    runCounter: number, lastClosedRunOrdinal: number,
    fenceEpoch: number, -- lock 해제 후에도 보존. 새 소유권 획득 때만 +1
    activeRun: {ordinal: number, matchId: string, stageId: string,
        balanceHash: string, startOperationId: string}?,
    lastRunResult: {ordinal: number, matchId: string, outcome: string,
        awardedGold: number, awardedXp: number}?,
    recentOperations: {{id: string, kind: string, revision: number}},
    lease: {sessionId: string, ownerJobId: string, expiresAt: number}?,
}
```

초기값: schemaVersion1, revision0, gold/xp/points=0, heroLevel1, traits전부0, unitLevels전부1, stageProgress3개 wins0/bestTicks없음, runCounter/closedOrdinal/fenceEpoch0, recentOperations빈 배열. 최초 lock 획득 시 fenceEpoch1. ID 해금은 `s01 항상; s02는 s01.wins>0; s03는 s02.wins>0`에서 도출한다. 중복 unlockedStages 필드는 저장하지 않는다.

| 특성 | 최대 | 매 포인트 효과 | 적용 시점 |
|---|---:|---|---|
| vitality | 3 | 영웅 maxHP +200 | 다음 경기 시작 |
| provisions | 3 | 식량 재생 +250milli/sec | 다음 경기 |
| focus | 3 | 마나 재생 +250milli/sec | 다음 경기 |

누적 경험치 갱신: `while heroLevel<10 and totalXp>=100*heroLevel^2 do heroLevel+=1; unspentPoints+=1 end`. XP는 차감하지 않는다. 레벨 자체 HP 증가 없음. 예: totalXp400이면 L3/총2포인트, 8100이면 L10/총9포인트.

영속 불변식:

1. gold 정수0~999999999, totalXp 정수0~1000000000(신규 저장 상한), unit level1~5, trait0~3.
2. `heroLevel = min(10, floor(sqrt(totalXp/100))+1)`이며 `sum(traits)+unspentPoints=heroLevel-1`. 다른 초기 보상 포인트 없음.
3. `0<=lastClosedRunOrdinal<=runCounter`; activeRun이 있으면 ordinal=runCounter>closedOrdinal. 한 번에 activeRun 하나.
4. lastRunResult.ordinal≤lastClosedRunOrdinal; lastRunResult는 마지막 종료만 보관. 이력 전체를 무한 배열로 쌓지 않음.
5. bestTicks는 승리일 때만 최소값, [1,12000]. wins는 nonnegative 정수. s03승리면 s02/s01에 wins>0이어야 함.
6. `revision`과 fenceEpoch는 감소하지 않는다. lock 해제는 lease만 제거하고 top-level fenceEpoch를 보존한다. 저장할 수 있는 primitive/table만 사용; Instance/CFrame/function·NaN 금지. 직렬화 크기 MVP64KiB 이하 목표.

깨진 불변식을 임의 clamp해서 기존 profile을 덮어쓰지 않는다. 읽기 실패와 정상 nil을 구분하고, 손상·미래 schema는 차단+운영 진단. 현재는 신규 v1만 지원하고, 향후 migration은 `migrate(oldVersion)` 순수 함수+fixture+백업/rollback 계획을 추가한 뒤 허용한다. APK 세이브 가져오기는 범위 밖.

### 5.1 결과·경제 operation

`MatchResult`는 서버에서만 만든다: `{matchId,runOrdinal,stageId,balanceHash,seed,outcome,elapsedTicks,killCounts,pendingKillGold,pendingKillXp}`. 서버가 stage 보상과 첫승리 여부를 읽어 최종 delta를 계산한다. 클라이언트가 결과나 delta를 전송하는 endpoint는 없다.

- Victory: `goldDelta=pendingKillGold+stage.winGold+(이전 wins==0 ? firstWinGold : 0)`, xpDelta=pendingKillXp+stage.winXp. overflow는 상한에 포화시키되 ledger는 실제 delta 기록.
- Defeat/Timeout/Abandoned: 두 delta0, 승리 기록/해금 변경 없음. 실행 ordinal은 닫는다.
- UpgradeUnit: LobbyReady, activeRun없음, L<5, 가격은 다음 row, 잔액 확인 후 차감+L+1. expectedRevision 충돌 시 재조회. 한 tick/동일 잔액을 경합하는 구매도 profile queue로 직렬화.
- AllocatePoint: LobbyReady, 남은 포인트≥1, trait<3, 차감+trait증가 동시 처리.
- Commit 결과는 gold/xp/level/traits/stageProgress/run closure/revision을 한 key에 넣는다. 미확정 임시 보상은 profile.gold에 미리 합하지 않음.

## 6. 통신 DTO

`GetBootstrap` 결과: `{protocolVersion, status, retryAfterSeconds?, publicCatalog, balanceHash, profileRevision?, profileSummary?, currentMatch?}`. lease/session token, 서버 RNG state, 타인 profile은 전송하지 않는다. ProfileSummary에는 gold/xp/level/points/traits/unitLevels/stageProgress만 포함.

`ClientCommand` 공통: `{protocolVersion=1,requestId,kind,...}`. 다음 union 외 필드는 거부한다.

| kind | 추가 필드 | 선행 상태 |
|---|---|---|
| StartStage | stageId, expectedRevision | LobbyReady, 활성run 없음 |
| Summon | matchId, commandSeq, slot1~3 | Running |
| Cast | matchId, commandSeq, slot=1 | Running |
| UpgradeUnit | unitId, expectedRevision | LobbyReady |
| AllocatePoint | traitId, expectedRevision | LobbyReady |
| ReturnToLobby | matchId | Settled |

`commandSeq`는 경기 내 증가 정수이며 Summon/Cast가 공유한다. 동일 seq/requestId 재전송은 기존 ack만 회신하고 효과0; seq가 더 작고 캐시에 없으면 StaleCommand. requestId 캐시는 소유자·경기 경계 안에서만 유효하다. `MoveIntent`는 별도 seq 공간, 0.5초 TTL과 연동한다.

`MatchSnapshot` 필수값: `{matchId,snapshotSeq,tick,phase,stageId,balanceHash,inputAckSeq,heroAction,resources,entities,projectiles,outcome?}`. entities는 공개 위치·HP·facing·state/stateUntilTick·definitionId·지원장 bool, projectiles는 시각 궤적+만료tick만. attackPower·seed·reward ledger는 숨겨도 되지만 숨김 자체를 보안으로 믿지 않는다. 종료 snapshot에는 결과+저장 상태 포함.

`ServerMessage` reason enum: `NotReady,InvalidPayload,ProtocolMismatch,NotOwner,WrongPhase,LockedStage,StaleRevision,StaleCommand,RateLimited,InsufficientFood,InsufficientMana,Cooldown,Busy,UnitCap,ProjectileCap,MaxLevel,NoPoints,StorageUnavailable,SessionLost`. 거부는 자원·cooldown·level 변화0. 메시지 UI를 구체화하되 내부 datastore 오류/키는 노출하지 않는다.

## 7. 출처 데이터 모델 (런타임과 별개)

`ReferenceValue`는 `{sourceDocument,section,lineRange,sourceFileHash,tableNamespace,rawIdentifier,dbRow?,field,rawValue,rawUnit,evidenceLevel,usageStatus,conflictId?}`.

`NormalizedValue`는 위 출처를 참조하며 `{canonicalId,field,value,unit,transformId,status}`를 더한다. `BalanceOverride`는 `{canonicalId,field,newValue,reason,decisionId,approvedBy}`. 마지막 승인이 실제 있기 전 approvedBy를 허위로 기입하지 않는다.

문서의 [확인] 태그를 데이터 전체에 전염시키지 않는다. raw값이 확인되어도 실행 중 사용 여부는 별개다. 예: 거북이 rawAP100000/레벨AP0, #353 raw속도2/실행미사용. 이 차이와 ID alias 문제를 [ASSET_PIPELINE](ASSET_PIPELINE.md)의 quarantine/테스트로 유지한다.
