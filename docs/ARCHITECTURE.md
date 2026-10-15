# Architecture — 서버 권한 단일 레인 시뮬레이션

버전1.0 · 2026-10-15 · **설계 계약, 미구현**. 별도 [문서확인] 표기가 없는 선택·상수는 모두 [신규결정]이다. 제품 범위는 [PRD](PRD.md), 데이터는 [DATA_MODELS](DATA_MODELS.md)를 따른다.

## 1. 결정 요약과 대안 (ADR-01)

**원칙**: 서버가 결과를 소유한다 / 로직은 렌더·물리·애니와 독립이다 / 출처 불확실성을 데이터에 남긴다 / 저장 확정을 UI와 일치시킨다 / MVP는 작은 명시 계약으로 시작한다.

**우선 동인**: (1) 조작 방지·저장 무결성, (2) 모바일 병력 다수의 비용, (3) MCP에서 재현할 수 있는 검증.

| 옵션 | 장점 | 비용·반대 근거 |
|---|---|---|
| A. 순수 Luau 숫자 전투 + client-local 뷰 (선택) | 물리 ownership 공격면 축소, 가짜 시계 테스트, 에셋 교체 쉬움 | 기본 Humanoid/캐릭터 이동·복제를 직접 대체, 입력 예측·보간 작업 필요 |
| B. 서버 Humanoid/물리 NPC + 복제 모델 | Studio에서 즉시 보이고 기본 애니·물리·내비게이션 활용 가능 | 다수 NPC·접촉 판정 비용, 물리 소유권/충돌/시각과 판정 결합, 1D 전투에는 과함 |

가장 강한 반론은 B가 초기 플레이어블을 더 빨리 제공한다는 것이다. 대신 A에서도 `PlaceholderRenderer`와 Studio 디버그 표시를 먼저 만들어 관찰성을 확보한다. 이 게임은 높이·점프·충돌이 필요 없으므로 A의 판정 단순성이 비용을 상쇄한다. 3D 플랫폼/다중 레인으로 범위가 바뀌면 ADR을 다시 검토한다. 세 번째 옵션인 클라이언트 권한 전투는 필수 서버 권한 조건에 어긋나 배제한다.

**결과**: 서버에 엔티티별 Instance 불필요, 프로토콜/뷰 구현 필요, 물리·애니 이벤트로 피해 주지 않음. **후속 조치**: P3/P5에서 1경기 프로토타입과 지연 실험 후 A 유지 판단, P9에서 상한 부하 측정. 이 ADR은 원작의 기술 구조를 주장하지 않는다.

## 2. 배포·폴더 경계

```text
default.project.json              # Rojo 매핑의 정본
src/shared/                       -> ReplicatedStorage/Shared
  Types.luau, Protocol.luau, PublicCatalog.luau
src/server/                       -> ServerScriptService/GameServer
  Bootstrap.server.luau
  Net/RemoteGateway.luau
  Services/{Match,Profile,Progression}Service.luau
  Simulation/{World,Resource,Movement,Targeting,Attack,Projectile,Damage,Stage}*.luau
  Config/Generated/               # 승인된 수치만. 클라이언트와 공유하지 않음
src/client/                       -> StarterPlayer/StarterPlayerScripts/GameClient
  Bootstrap.client.luau
  Controllers/{Input,Match,Camera,HUD}Controller.luau
  Rendering/{EntityView,PlaceholderRenderer,SpriteRenderer,ModelRenderer}.luau
assets/original/                  # 직접 제작 원본과 manifest (Rojo 자동 전체 반입 아님)
data/{reference,normalized,balance}/
tools/                            # 데이터 생성·검증 (Python 표준 라이브러리)
tests/{unit,integration,scenarios,fixtures}/
test-support/                     # Studio 전용 ServerHarness / ClientHarness
artifacts/                        # 빌드/로그/증거, 출시 tree에 매핑하지 않음
```

`ReplicatedStorage/Remotes`에는 명시적 RemoteEvent/RemoteFunction만 생성. `Workspace/Environment`는 오리지널 배경과 카메라 기준점만 포함한다. `PlayerGui`는 클라이언트 UI. 렌더 prefab은 승인된 공개 에셋만 `ReplicatedStorage/Presentation`에 둔다.

`Players.CharacterAutoLoads=false`. 기본 Roblox 아바타·Humanoid가 전투 영웅이 아니다. client-local anchored Part/Model로 영웅을 표시하고, 서버 수치 X로만 공격·이동한다. 기본 캐릭터를 생성하지 않아도 조작·카메라·UI가 정상 부팅되어야 한다. 타인 경기·데이터는 플레이어별로 격리한다. 서버는 최대4개의 MatchContext를 가지며 소유자당 하나다.

Rojo는 파일→Studio 동기화/빌드 도구이며 실행 테스트 도구가 아니다. 코드는 파일 정본으로 수정하고 `rojo serve`로 반영한다. MCP로 Rojo 소유 스크립트를 직접 편집해 이중 정본을 만들지 않는다. 예시 빌드: `rojo build default.project.json -o artifacts/mvp.rbxlx`. 실제 도구 버전은 P0에서 고정한다. [Rojo 공식 새 프로젝트 workflow](https://rojo.space/docs/v7/getting-started/new-game/) (조회2026-10-15).

## 3. 시스템 의존성

```text
문서 근거 → 정규화/검증 → 신규 balance overlay → ServerConfig + PublicCatalog
                                                ↓
ProfileService → 성장 snapshot → MatchService → World.step(dt, commands)
      ↑                ↑                          ├ Resource → Summon/Skill 예약
      │                │                          ├ Stage → Enemy 생성
      │            StartStage                     ├ Movement → Aura → Targeting
      │                │                          ├ Attack → Projectile → Damage
      │          RemoteGateway                    └ Death → Outcome
      │                ↑                                  ↓
      └ ProgressionService ← immutable Result ← Settlement transaction
                                                          ↓
Client Input → Intent                  Snapshot/ack → Client WorldView
                                                        ├ HUD/Camera
                                                        └ Animation/VFX/Audio
```

| 시스템 | 입력 의존 | 출력·책임 | 금지 의존 |
|---|---|---|---|
| Config/검증 | 명시 ID·단위·허용 출처 | immutable 런타임 정의 | 게임 중 XML/Markdown 파싱 |
| Profile | StoreAdapter, 시계, 저장 queue | session 소유권, durable profile | 클라이언트 잔액 |
| Progression | profile+서버 결과+성장표 | 원자 보상·강화·포인트 | 개체 사망마다 DataStore 호출 |
| Match | 승인 config/profile snapshot | 생성·종결·정리·소유자 | 렌더 instance/애니 길이 |
| Resource | 고정 dt·성장 snapshot | 상한, 재생, 비용 예약 | 클라이언트 timer |
| Target/Attack/Damage | 서버 위치·상태·timing | 타깃, 피해, 사망 1회 | Touched/애니 marker/클라이언트 hit |
| Stage | stage config·RNG·tick | 스폰/목표/승패 후보 | 미사용 원본 보상 컬럼 |
| View/Input | 공개 catalog+snapshot | intent/표시/로컬 예측 | DataStore·확정 피해·보상 |

실행 시 구성 함수에서 의존성을 주입한다. 서비스의 상호 require 순환을 만들지 않고 Match의 종결 이벤트를 composition root가 Progression으로 전달한다. 초기에는 ECS 프레임워크·범용 이벤트 버스·새 패키지 없이 작은 ModuleScript들로 구현한다.

## 4. 서버/클라이언트 권한

| 항목 | 서버 | 클라이언트 |
|---|---|---|
| 이동 | axis 수용, 속도·X경계·시전/사망 상태 적용 | 버튼 상태, 영웅 시각적 예측·보정 |
| 소환/스킬 | 비용·쿨·슬롯·보유·cap 재검증, 같은 tick 원자 차감 | 요청, pending·쿨다운 예상 표시 |
| 전투 | AI, RNG, 탄 궤적·피해·HP·오오라·사망 | 보간·재생·타격 VFX. 시각 충돌은 무효 |
| 스테이지 | 스폰, 시간, 목표, 승패 1회 | 카메라/HUD/결과 표시 |
| 성장/저장 | EXP·레벨·가격·포인트·해금·저장·세션 lock | 선택 intent와 확정 revision 표시 |

모든 클라이언트 데이터는 조작 가능하다고 취급하고 타입·구조·값·문맥·호출 빈도를 서버에서 검사한다. 이 권한 경계는 Roblox 공식 [보안 지침](https://create.roblox.com/docs/scripting/security/client-server-boundary)과 [security tactics](https://create.roblox.com/docs/scripting/security/security-tactics)에 근거한다(조회2026-10-15). 아래의 구체적 프로토콜·제한값은 프로젝트 설계다.

## 5. 시간과 전투 순서

- 서버 Heartbeat의 실제 dt를 accumulator에 넣고 `step=0.05초`(20Hz)로 처리. 클라이언트 FPS와 무관하다.
- 한 Heartbeat당 catch-up 최대4 step. accumulator 최대0.25초, 초과분은 버리고 `simDroppedSeconds` 관측. 지연을 한 번에 거대한 dt로 통과시키지 않음. 전투 시간·쿨다운은 **처리한 simulation tick** 기준으로만 흐른다. 과부하 시 실시간 대비 느려질 수 있고 이를 숨기지 않는다.
- `secondsToTicks=ceil(seconds/0.05)`. 지연0의 타격도 시작 tick에 중복 실행하지 않도록 최소1tick 뒤 release. 설정 windup/recovery/쿨은 모두 명시한다.
- 정수 tick·고정 소수 자원·서버 지정 seed PRNG, 정렬된 entityId와 command ordinal로 재현성을 확보. 같은 구현/버전/seed에서의 재현성을 검증하며 플랫폼 간 비트 단위 결정론을 무조건 보장하지 않는다.

한 step의 순서는 고정한다.

1. 수신한 bounded queue를 서버 ingress ordinal 순서로 취합한다.
2. 생존 경기의 식량·마나를 재생한다.
3. intent를 최신 상태에서 재검증해 비용·쿨·cap을 예약한다. 비동기 저장을 이 루프 안에서 기다리지 않는다.
4. 스테이지 스폰을 처리한다. 적 cap이면 타이머 잔여를 그대로 동결한다.
5. 이동·경계 재배치 → 오오라 갱신 → 타깃 선택을 순서대로 수행한다.
6. 공격 windup/release, 기존 투사체의 swept segment 충돌을 처리해 **피해 batch**를 만든다. 이번 tick 새 투사체는 다음 tick부터 이동한다.
7. batch 시작 시 살아있는 공격자가 방출한 유효 타격들을 합산 적용한다. 동시 교환타 허용. 각 엔티티의 사망/킬 집계는 한 번만.
8. 영웅 사망 → 핵 파괴 → 12000tick 시간초과 순으로 종결한다. 종결 이후 command·재생·스폰·피해 없음.
9. snapshot/event를 발행하고 visual tombstone 이후 메모리를 정리한다.

AI: `Advancing → Windup → Recovery → Cooldown → Advancing/새 Windup`, 어디서든 `Dead`로 전이. 타깃은 같은 경기·레인·적대 진영·생존·전방 중 `abs(dx) ≤ attackRange+target.hitRadius`인 최근접, 동률은 entityId 작은 값. 적이 왼쪽 경계를 넘은 `breachReturn` 상태만 예외로 영웅을 추적·타깃팅하며 facing을 영웅 방향으로 갱신한다(DATA_MODELS §3.5). windup 완료 시 생존·전방·사거리 재검사, 이탈이면 빗나감으로 recovery 진행(원작은 재검사하지 않았다는 E02 §2.9와의 의도적 차이).

투사체는 이전X→새X의 1D segment와 target hitRadius+탄 radius 교차를 검사한다. 가장 가까운 충돌 순서로 처리, hitEntityIds로 재타격 방지. damage는 발사 시 AP/지원장 배율을 snapshot하고 시각 owner 사망 후에도 유효하다. 적/아군, 같은 레인, 경계·TTL·distance·pierce 검증을 서버가 한다. `.Touched`, raycast의 시각 모델 크기, AnimationTrack marker는 피해 근거가 아니다.

## 6. 네트워크 계약

Roblox의 RemoteEvent는 비동기 전달, RemoteFunction은 응답을 기다리는 호출이다. 동기 callback에 전투·DataStore 대기를 넣지 않고 서버→클라이언트 `InvokeClient`를 사용하지 않는다. [공식 remote 문서](https://create.roblox.com/docs/scripting/events/remote) (조회2026-10-15).

### 6.1 endpoint

| 이름/형식 | 방향 | payload 요약 | 처리 |
|---|---|---|---|
| GetBootstrap / RemoteFunction | C→S | `{protocolVersion=1}` | 메모리만 조회, 상태 Loading/Ready/Unavailable, publicCatalog/version, profile 요약/revision, 현재 snapshot 반환 |
| ClientCommand / RemoteEvent | C→S | requestId, kind, matchId?, slot?, stageId?, expectedRevision?, upgradeId? | 시작·소환·스킬·성장·로비 복귀. 승인·거부는 ServerMessage |
| MoveIntent / RemoteEvent | C→S | protocolVersion, matchId, seq, axis ∈ {-1,0,1} | 최신 seq만 수락, 서버 이동 의도 교체 |
| ServerMessage / RemoteEvent | S→소유자 | requestId, status, reason, serverTick, profileRevision?, result? | Accepted/Rejected/Pending/Committed 상태 명시 |
| MatchSnapshot / RemoteEvent | S→소유자 | matchId, snapshotSeq, tick, inputAckSeq, full state | 10Hz 독립 완전 snapshot. MVP delta 없음 |

`ClientCommand` 공통: protocolVersion1, requestId는 클라이언트 세션 내 유일 ASCII 16~64자. kind별 허용 필드만 받아 모르는 필드·중첩·Instance를 거부. kind와 payload union은 DATA_MODELS. Player는 OnServerEvent의 엔진 인자를 사용하며 payload의 userId는 받지 않는다. matchId는 서버가 발급한 불투명 ID이고 소유권을 대체하는 비밀키가 아니다.

- 소환/시전은 슬롯 정수만 받음. AP/HP/위치/가격/잔액/클라이언트 시간/임의 target은 받지 않음.
- discrete intent: 플레이어별 token bucket 10/s burst20, pending queue32. movement:20/s burst30, 최신 의도만 보관. GetBootstrap:1/s burst2, client에서 동시에1개만; UI 응답 대기3초 후 표시를 중단하되 서버 호출 취소를 가정하지 않음.
- 유효 문자열·유한 수·정수·허용 ID·메시지 깊이를 O(고정 크기)로 검사. 악성 requestId를 key로 무제한 cache 생성하지 않음. 반복 거부는 집계 로그로 제한.
- 전투 requestId는 경기 내 최근128개 ack 캐시. 소환 쿨·식량·cap도 재검증하므로 캐시는 보안 유일 수단이 아님. 매우 오래된 request replay는 별도 commandSeq(경기 내 증가 정수) high-watermark로 거부한다.
- 성장/시작 명령은 expectedRevision을 필수로 받아 profile transaction queue에서 처리. 저장 작업은 Pending→Committed, 실패/충돌은 Rejected. **pcall 성공만으로 committed로 보지 않고 반환 문서의 operation/run 식별자를 확인**한다.
- 클라이언트는 snapshotSeq가 증가하는 현재 matchId만 적용한다. 각 snapshot은 전체 엔티티를 포함하므로 누락분을 제거할 수 있다. 마지막 snapshot 이후 0.5초 이상이면 연결 불안 표시·원격 유닛 extrapolation 중지, 1초 후 rate-limited bootstrap 재동기화. stage/result event 누락도 bootstrap에서 복구한다.

영웅만 최대0.15초 시각 예측, 서버 ack 이후 미처리 입력을 재적용한다. 0.1stud 이하 오차는 0.1초 보정, 2stud 초과·종결·재배치는 즉시 스냅한다. 다른 유닛은 0.1초 늦춘 snapshot 보간, 최신 데이터 밖 extrapolation 최대0.15초. 예측은 HP/식량/마나/히트 확정값을 수정하지 않는다.

## 7. 세션·승패·정산 상태 머신

```text
ProfileLoading → LobbyReady → Preparing(실행 식별자 저장) → Running
                        ↑                              ↓
                        └ Settled ← Settling ← Victory/Defeat/Timeout
ProfileLoading → Unavailable        ↘ Abandoned(이탈/소유권 상실)
```

- `Preparing` 전에 stage 해금/프로필/중복 경기/버전을 검사. activeRun 저장 확정 후에만 Running 시작한다. 전투 동안 성장 snapshot 불변.
- 첫 종결 시 Outcome과 임시 kill 합계를 immutable Result로 고정, 새로운 결과로 덮어쓰지 않는다.
- Settling에서 프로필의 activeRun을 검증하고 보상·EXP·해금·첫승리·closed ordinal을 한 번에 갱신한다. 패배도 보상0으로 run을 닫는다. commit 후에만 Settled/다음 로비 진입.
- 저장 재시도 중 결과 화면에 **저장 대기** 표시, 새로운 경기·강화·포인트는 잠금. PlayerRemoving/BindToClose는 같은 단일 저장 queue에 flush를 요청하며 별도 경쟁 writer가 되지 않는다.
- 재접속 시 lock 확보 후 남은 activeRun은 Abandoned로 닫고 보상0. 이어하기 없음. 이미 committed된 결과라면 진행값은 그대로 보여준다.

## 8. DataStore 프로토콜 (ADR-02)

### 8.1 원칙과 근거

단일 `u:<UserId>` key에 profile을 저장한다. Account/Slot 두 key 분리는 원작(E01 A7)의 구조이지 MVP 요구가 아니다. 하나의 게임 프로필만 지원하므로 원자 갱신 가능한 단일 key를 선택한다. 키 사이 transaction을 가정하지 않는다.

DataStore 네트워크 호출은 실패할 수 있고 `UpdateAsync` transform은 yield 불가·충돌 시 반복 실행 가능하다. Studio에서 API 접근을 켜면 실 데이터에 접근할 수 있으므로 별도 테스트 experience를 사용한다. [Data stores](https://create.roblox.com/docs/cloud-services/data-stores), [GlobalDataStore.UpdateAsync](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore#UpdateAsync) (조회2026-10-15).

공식 [플레이어 데이터 지침](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing)의 단일 profile/세션 locking 문제를 참고한다. 아래 lease·fence·revision 설계는 Roblox가 자동 제공하는 lock이 아니라 **우리 코드가 구현·테스트할 프로토콜**이다.

### 8.2 소유권과 실패 처리

- Store는 environment별 분리, 테스트는 별도 universe. `schemaVersion=1`과 `balanceVersion`은 독립이다.
- sessionId=서버 생성 GUID, ownerJobId=game.JobId, fenceEpoch=profile 최상위에 영속 보존하는 단조 증가 정수. lease 해제 후에도 epoch를 지우지 않는다. 최초 load를 `UpdateAsync`로 읽기+잠금 획득한다. 성공적으로 읽은 nil에서만 신규 profile 생성.
- lease180초, 45초마다 heartbeat/save(±5초 분산). 획득은 잠금 없음 또는 만료 후에만, epoch+1. 갱신/저장/해제는 **sessionId+epoch 일치 및 미만료** 조건. stale writer는 nil 반환하고 로컬 세션 폐기.
- 서버 wall clock(`os.time`)은 lease용, simulation tick은 전투용, 단조 시계는 retry/rate limit용. lease 만료30초 전까지 갱신 확인이 없으면 경기 중지·성장/새 경기 금지. 시계 차이와 네트워크 지연 위험은 fake clock/2writer 테스트로 검증한다. 만료된 세션을 같은 토큰으로 부활시키지 않는다.
- profile별 하나의 비동기 write queue; heartbeat도 이 queue를 사용. 대기시간이 lease 안전 여유를 넘으면 우선 중지한다. DataStore 호출은 전투 step을 막지 않는다.
- pcall+외부 재시도(예: 1,2,4,8초+0~0.5초 jitter, 최대5회·관측 deadline20초). 호출 자체가 yield 중일 때 시간초과 UI를 띄워도 다른 writer를 병렬 발사하지 않는다. 늦게 반환하면 session token·request generation을 다시 확인한다.
- request budget을 확인하고 backpressure 적용. UpdateAsync는 read/write budget을 소비하므로 고정된 전역 quota를 코드에 박지 않는다. [공식 제한 문서](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) (조회2026-10-15).
- load 오류/lock 충돌/손상 profile/미래 schema는 기본값으로 덮어쓰지 않고 Unavailable. 저장 실패를 신규 계정으로 취급하지 않음. 정상 종료 flush도 실패할 수 있으며 강제 종료의 무손실을 약속하지 않는다.

### 8.3 변환 callback과 idempotency

callback은 `(oldValue, operation) -> newValue?` 순수 계산이다. 외부 테이블 수정·랜덤·print·이벤트 전송·HTTP·yield 금지. GUID/시각/결과/보상은 callback 이전에 고정한다. 저장 반환값을 검증한 뒤 메모리 profile 교체·UI ack를 한 번 발생시킨다.

- 매 경제 transaction마다 `revision += 1`; lease heartbeat는 revision을 바꾸지 않음.
- 성장: expectedRevision/현재 레벨·포인트·가격을 검사, spend+grant+recentOperation 영수증을 함께 기록. 최근64개 영수증만 보관. 오래된 request는 expectedRevision 불일치로 재실행 불가. 영수증은 무한 보존하지 않음.
- 실행 시작: `runCounter += 1`, activeRun에 ordinal/matchId/stageId/balanceHash 기록. 중복 시작은 operation 영수증/activeRun으로 기존 결과를 반환한다.
- 정산: activeRun과 결과의 ordinal/matchId가 일치하고 `ordinal > lastClosedRunOrdinal`일 때만 보상 가능. 보상·첫승리 표시·해금·EXP/포인트·lastClosedRunOrdinal 증가·activeRun 제거를 **같은 UpdateAsync**에 기록한다.
- 성공했으나 응답을 잃은 정산은 같은 immutable operation으로 재시도. `lastClosedRunOrdinal==ordinal`이고 저장된 lastRunResult가 일치하면 재지급 없이 기존 성공을 돌려준다. 더 오래된 ordinal은 거부한다.
- lease를 잃은 old server의 정산은 epoch 검사로 거부. 새로운 서버는 중단 activeRun을 닫을 뿐 결과를 추측하지 않는다.
- 외부 datastore와의 exactly-once transaction을 주장하지 않는다. **한 key에 commit된 같은 run이 중복 경제 효과를 내지 않음**이 목표다. commit 이전 손실은 명시된 MVP 한계다.

## 9. 입력 계층

`DeviceAdapter → ActionRouter → IntentBuilder → RemoteGateway`, 표시 갱신은 `MatchController → HUD/EntityView`로 분리한다.

MVP는 `ContextActionService:BindActionAtPriority`로 PC 키를 묶고 `createTouchButton=false`로 둔다. 직접 만든 GuiButton의 터치 Begin/End/Cancel과 Activated를 같은 ActionRouter에 연결한다. InputObject별 홀드 set을 관리해 두 손가락 이동+소환·스킬을 지원한다. API의 바인딩/터치 버튼 지원은 [ContextActionService 문서](https://create.roblox.com/docs/reference/engine/classes/ContextActionService), 대안인 [Input Action System](https://create.roblox.com/docs/input/input-action-system)의 context 개념은 확인했다(조회2026-10-15). 두 시스템을 동시에 바인딩하지 않으며, 새 시스템 전환은 별도 ADR이다.

- axis는 좌측 홀드만=-1, 우측만=1, 모두/없음=0. 포커스/텍스트입력/메뉴가 열리면 홀드 set을 지우고0을 보낸다. End/Cancel은 메뉴 여부와 무관하게 정리한다.
- axis 변경 즉시 + 홀드 중0.1초마다 heartbeat 전송(최대10Hz 정상). key repeat는 discrete command를 만들지 않는다. 서버 이동 intent TTL0.5초.
- `GuiButton.Activated`와 keyboard Begin은 동일 action 함수로 들어가고, 터치에서 mouse 호환 이벤트와 중복 연결하지 않는다.
- 메뉴는 gameplay action을 sink, 채팅/텍스트 입력은 소비하지 않음. 기본 캐릭터 이동/점프와 중복 조작이 없어야 한다.
- 카메라는 Scriptable, X방향 follow/clamp. Z jitter는 entityId 기반 visual seed로만 생성하고 전투 RNG를 소비하지 않는다.

## 10. 관측·테스트 경계

실행 로그는 `buildId/balanceHash/schemaVersion/matchId/runOrdinal/seed/tick/event/reason`을 포함한다. userId 원문·profile 전체·세션 토큰은 일반 클라이언트 로그에 남기지 않는다. metric: tick 비용·catch-up drop·엔티티/탄 수·remote 거부·snapshot 크기·저장 latency/retry/lock loss.

테스트용 seed/자원 주입은 `RunService:IsStudio()`와 테스트 build의 서버 모듈에서만 가능. 테스트 코드는 운영 Rojo tree에서 제외하고, 운영 Remote에는 Debug/GrantCurrency/SetHP가 없다. MCP는 개발 도구이며 출시 게임의 런타임 컴포넌트가 아니다. 구체 실행·증거 계약은 [TEST_PLAN](TEST_PLAN.md).
