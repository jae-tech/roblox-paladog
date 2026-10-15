# Implementation Plan — OMX 단계별 개발·검증

버전1.0 · 2026-10-15 · 범위: **설계에서 MVP 구현으로 넘기기 위한 작업 계약**.
현재 게임 작업 상태는 모두 `NOT_STARTED`이다. 아래 경로·명령은 향후 산출물이며 이번에 존재하거나 실행됐다고 주장하지 않는다. 이번 요청의 종료점은 6개 설계 문서와 문서 정합성 검증이다.

## 1. 선행 입력과 실행 규칙

정본: [PRD](PRD.md)의 R-01~10, [ARCHITECTURE](ARCHITECTURE.md)의 권한·시간·정산, [DATA_MODELS](DATA_MODELS.md)의 수치·DTO, [ASSET_PIPELINE](ASSET_PIPELINE.md)의 근거/에셋 정책, [TEST_PLAN](TEST_PLAN.md)의 T-*.

한 task는 `입력 확인 → 테스트 먼저/fixture 생성 → 좁은 구현 → targeted test → 타입/정적분석·빌드 → 증거 기록 → reviewer 확인`으로 끝낸다. 다음 단계는 선행 게이트가 통과한 뒤 시작한다. MCP 미연결·미실행 테스트를 PASS로 대체하지 않는다. 운영 datastore·자산 업로드·공개 publish·파괴적 데이터 변경은 별도 권한 경계다.

각 task 카드의 필수 필드:

```text
taskId / 상태 / owner / 선행 task / 소유 파일 / 요구 R-* / 테스트 T-*
성공 기준 / 비범위 / 실행 명령·도구 / raw evidence 경로
buildId + balanceHash + seed + Studio/MCP version + 검증 verdict + 미해결 위험
```

설계와 실제 구현이 다르면 암묵적으로 어긋나게 두지 말고 관련 정본·테스트를 같은 변경에서 수정한다. 버그 수정은 회귀 테스트를 추가한 뒤 한 원인만 고친다. 출시 코드는 `--!strict`; 범용 ECS·인벤토리/퀘스트 프레임워크·외부 테스트 패키지는 MVP에 추가하지 않는다.

## 2. 의존성 DAG와 경로

```text
P0 도구·test place·품질 게이트
 ├ P1 출처→수치 생성 ───────┐
 └ P2 DTO·경기/프로필 골격 ─┤
                           P3 식량/소환/이동/근접 전투
                            ├ P4 원거리·영웅 스킬
                            ├ P5 입력·카메라·Placeholder 뷰 (계약 고정 후 P4와 병행 가능)
                            └ P7 성장 순수 계산 (P1/P2 계약 필요)
P4 + P5 ─────────────────── P6 스테이지·종결·정산 연결
P2 + P7 ─────────────────── P8 실제 저장·세션 fencing (P6 결과 연결 검증 포함)
P1~P8 ───────────────────── P9 통합·악성입력·기기·부하·출시 검사
```

P7의 순수 계산은 P6 이전 가능하나 보상 실제 지급 연결은 P6 이후이다. P8의 실제 Store 어댑터 개발은 병행 가능하나 종결 정산 검증은 P6/P7 완료 후다. P9 전에 mock persistence를 실제 저장으로 오인하지 않는다.

## 3. 단계별 작업 목록

### P0 — 재현 가능한 도구·프로젝트·검증 기반

**입력**: 6개 설계 문서, Windows 작업 환경. **소유**: `default.project.json`, `test.project.json`, `toolchain` 기록, `src/*/Bootstrap*`, `tests/Runner.luau`, 테스트용 place 및 `artifacts/` 규칙. **요구** R-10.

- [ ] P0.1 Git/기존 원격 이력 확인, 팀 합의 branch/파일 정책 설정. 연구 원본·개인 키·runtime state는 배포/커밋 제외.
- [ ] P0.2 Luau/Rojo/Studio/MCP 버전 기록·호환성 확인. Luau CLI가 없으면 순수 코드 테스트를 Studio runner에서 우선 실행하고 CLI 설치/사용 가능 여부를 기록.
- [ ] P0.3 Rojo production/test 두 tree 구성. shared/server/client 분리, CharacterAutoLoads=false, 원본 에셋 없는 환경·boot.
- [ ] P0.4 의존성 없는 assert 기반 test runner와 fail 시 nonzero/JSON 보고, fake Clock/RNG, InMemoryProfileStore fixture를 준비.
- [ ] P0.5 typecheck(순수 모듈 `luau-analyze`, Roblox 모듈은 Studio Script Analysis 또는 고정된 Roblox 타입환경), lint/format 검사 기준, Rojo build를 gate로 연결. 실행 도구가 없으면 '검사 생략'을 실패/보류로 구분.
- [ ] P0.6 Studio MCP capability discovery·명시 studio_id 선택, test harness가 운영 tree에 없는지 검사.

**완료 게이트**: T-TOOL. 새 checkout에서 build 후 server/client bootstrap 확인, 의도적 실패 fixture가 FAIL을 보고, production에서 테스트 grant endpoint0. **증거** `artifacts/P0/{toolchain.json,build.log,mcp-capabilities.json,boot.json}`.

### P1 — 연구 수치 변환·신규 밸런스 생성

**선행** P0. **소유** `tools/import_reference.py`, `tools/build_balance.py`, `tools/validate_data.py`, `data/*`, `src/server/Config/Generated/*`, `src/shared/PublicCatalog.luau`. **요구** R-01/R-03/R-04.

- [ ] P1.1 Markdown7개 SHA·절 locator·table namespace 수집, raw↔정규화↔override 출처 schema 작성.
- [ ] P1.2 단위/기본행 대체/다음 레벨 비용/5·6 alias/적ID 매핑 golden부터 작성.
- [ ] P1.3 confirmed/inferred/conflicted/unused quarantine, 누락값과0 구분, 입력 변경 시 fail-fast.
- [ ] P1.4 신규 ID와 DATA_MODELS의 mvp-proto-001 overlay: hero1/ally3/enemy3/stage3/level15 생성.
- [ ] P1.5 동일 입력2회 산출 hash/diff0, PublicCatalog 허용 필드만 추출.

**완료 게이트**: T-DATA/T-ASSET. 쥐L1HP100(300/400 아님), 사거리200px→20stud, regen0.2→2/s, period19→20번째, 캠페인 iCrRwd 제외, overlay 차이 report. **증거** `artifacts/P1/{conversion-report.json,provenance.json,golden.json,regeneration.diff}`.

### P2 — 권한·DTO·상태·프로필 인터페이스 골격

**선행** P0 (P1과 병행). **소유** `src/shared/{Types,Protocol}.luau`, `src/server/Net/RemoteGateway.luau`, `Services/MatchService.luau`, `Services/ProfileService.luau`의 인터페이스, `tests/fixtures/InMemoryProfileStore.luau`. **요구** R-07/R-10.

- [ ] P2.1 GetBootstrap/ClientCommand/MoveIntent/ServerMessage/MatchSnapshot 생성, allowed payload union·finite/int/string 검증부터 테스트.
- [ ] P2.2 player→소유 match 매핑, ingress queue32, token buckets, Move seq/TTL와 command seq/ack128 정의.
- [ ] P2.3 ProfileLoading/LobbyReady/Preparing/Running/Settling/Settled, owner별 하나의 실행, 버전 불일치 차단.
- [ ] P2.4 StoreAdapter의 read-lock/update/flush 계약을 InMemory 구현. 실제 DataStore를 호출하지 않으며 테스트 UI에도 Mock 표시.
- [ ] P2.5 새/오류/nil 구분, expectedRevision과 recent operation 검사. 2client 격리 fixture.

**완료 게이트**: T-SEC 기본/T-ISOLATION/T-TOOL. 임의 target/HP/가격 필드 거부, 타인 match 입력 거부, bootstrap callback에서 yield0. **증거** `artifacts/P2/{protocol-tests.json,isolation.json}`.

### P3 — 순수 시뮬레이션: 자원·소환·근접

**선행** P1+P2. **소유** `src/server/Simulation/{World,Resource,Movement,Targeting,Attack,Damage}*.luau`, `tests/unit/*`, debug view는 별도 lane. **요구** R-02/R-03/R-04.

- [ ] P3.1 step20Hz·정수 tick, milli regen/remainder, cap·cooldown·합성 입력순서 회귀 테스트.
- [ ] P3.2 비용+entity capacity+cooldown을 한 step에서 원자 예약, 시작 ready/식량0, 한도 거부 무차감.
- [ ] P3.3 1D 이동·범위·최근접·동률·전진한계·breachReturn 경계 동작.
- [ ] P3.4 Windup/Recovery/Cooldown/Dead, release 재검증, 피해 batch·사망1회·임시 처치 보상.
- [ ] P3.5 영웅 숫자 이동·HP, 지원장 반경/발사 시 배율 snapshot, 시뮬레이션 순서 고정.
- [ ] P3.6 catch-up 최대4/초과 metric, callback/애니/Instance 없는 headless simulation.

**완료 게이트**: T-RESOURCE/T-COMBAT/T-HERO. 100tick 후 food/mana각10000milli, 동일 seed/commands digest 동일, 모형/FPS 없이도 전투 진행. **증거** `artifacts/P3/{unit.json,seed-replay.json,tick-order.json}`.

### P4 — 탄·영웅 무기 스킬

**선행** P3. **소유** `Simulation/ProjectileSystem.luau`, `Simulation/HeroActionSystem.luau`, 관련 tests. **요구** R-02/R-03.

- [ ] P4.1 allied/enemy/pulse 탄, swept segment·충돌 순서·pierce·TTL·진영·레이스 회귀 테스트.
- [ ] P4.2 pulse 마나/쿨/시전 lock/투사체 slot 예약, 시전 중 이동, 빈공간 발사·환급 없음.
- [ ] P4.3 발사 후 owner 사망·동시타격·target 이탈·오버킬 사망 이벤트 중복 방지.
- [ ] P4.4 cap128 stress, 신규 탄 다음 tick부터 이동, 시각 marker 없이 타격.

**완료 게이트**: T-PROJECTILE/T-HERO/T-SEC. 고속 탄이 얇은 대상 건너뛰지 않음, 같은 대상 중복0, AP/좌표 spoof 효과0. **증거** `artifacts/P4/{projectile.json,cast.json}`.

### P5 — 모바일·PC 입력·뷰·카메라

**선행** P3와 DTO 고정; P4 진행 중 adapter/mock snapshot으로 병행 가능. **소유** `src/client/**`, `PresentationDef`/오리지널 placeholder assets, client tests. **요구** R-02/R-08/R-09.

- [ ] P5.1 DeviceAdapter/ActionRouter, PC A/D/화살표/1~3/Q, touch 홀드+Activated의 단일 경로.
- [ ] P5.2 멀티터치·Begin/End/Cancel·양쪽방향·키 반복·focus/menu/chat 차단 테스트.
- [ ] P5.3 self-contained10Hz snapshot, stale seq/match 차단, interpolation·hero 예측·reconcile·bootstrap resync.
- [ ] P5.4 Scriptable camera, 전진 경계, safe inset·세로/가로 HUD·비용/쿨/거부/임시보상/저장상태.
- [ ] P5.5 EntityView와 PlaceholderRenderer. Sprite/Model은 교체 계약과 stub/fallback 회귀만 준비, 고품질 에셋 제작은 제외.

**완료 게이트**: T-INPUT/T-DEVICE 기능/T-ASSET/T-NET. 실제 키 입력·GUI 클릭으로 서버 상태 변경 확인, focus상실 서버0.5초 이내 정지, 표현 교체 digest동일. **증거** `artifacts/P5/{client-tests.json,input-pc.json,input-touch.json,screens/}`. 모바일 성능 합격은 P9 실기기에서 별도.

### P6 — 3스테이지·승패·결과 연결

**선행** P4+P5, P7 결과 계산 계약. **소유** `Simulation/StageSystem.luau`, MatchService 종결 구간, 결과 UI 연결 변경은 client owner와 조율. **요구** R-05/R-06.

- [ ] P6.1 s01~s03 신규 table·unlock 검사, 느림/빠름 반복·가중치·cap동결·seed.
- [ ] P6.2 hero/core/timeout 우선순위, terminal-once, pending kill 합계 immutable Result 생성.
- [ ] P6.3 InMemory 저장 backend로 Preparing/Settling/Committed/ReturnToLobby 전체 흐름 구현.
- [ ] P6.4 승리 후 잔존 탄/병력 정리, 연결 재설정·반복 경기의 메모리/GUI 누수 검사.

**완료 게이트**: T-STAGE/T-E2E(Mock). stage skip 차단, 핵/영웅 동시0이면 패배, 12000tick 종료, 정산 요청 중복 경제효과0. **증거** `artifacts/P6/{stage.json,scenario-replays.json}`.

### P7 — 성장·가격·보상 순수 계산과 로비 UI

**선행** P1+P2+P3 계약, 실제 결과 연결은 P6 이후. **소유** `Services/ProgressionService.luau`, `Simulation/ResultReducer.luau`, 성장 fixtures. UI는 P5 owner와 공동 인터페이스 합의. **요구** R-06.

- [ ] P7.1 승리만 처치+stage보상, 첫승리 추가1회, 패배/Abandoned0 테스트.
- [ ] P7.2 cumulative XP loop·L10cap·포인트 보존식·traits3개각3·next match snapshot.
- [ ] P7.3 Unit L5cap·다음 레벨 cost·잔액·expectedRevision·동시구매·same op 재시도.
- [ ] P7.4 stageProgress에서 unlock 도출, wins/bestTicks, 서식 요약 DTO.

**완료 게이트**: T-GROWTH/T-SAVE의 순수 reducer. XP400→L3/2points, spent+unspent=level-1, 강화L1→2비용25, 전투중 구매거부, first bonus 1회. **증거** `artifacts/P7/{growth.json,transaction-reducer.json}`.

### P8 — 실제 DataStore·소유권·재접속

**선행** P2+P7; 실전 정산 gate는 P6 필요. **소유** `Services/ProfileService.luau` 구현, `Persistence/{DataStoreAdapter,TransactionQueue,ProfileValidator}.luau`, 테스트 저장 fixture. **요구** R-06/R-07.

- [ ] P8.1 별도 테스트 universe/API access 확인, data store namespace, 테스트 key만. 저장 default 접근은 차단.
- [ ] P8.2 acquire/renew/release lease180초/45초 heartbeat/30초안전여유, sessionId+epoch fence.
- [ ] P8.3 단일 queue·pcall/retry budget/backpressure·늦은 응답·unknown commit 상태를 설계대로 처리.
- [ ] P8.4 Start activeRun 저장 후 Running, immutable result→경제+run close 원자 commit, callback side effect/yield0.
- [ ] P8.5 callback 재실행·이미 commit 후 응답실패·동일 run 재정산·stale writer·빠른 재접속·중단run abandon 테스트.
- [ ] P8.6 load실패/nil/미래schema/손상 구분, overwrite금지, BindToClose·PlayerRemoving 같은 queue flush.
- [ ] P8.7 실 저장 후 Studio 종료/재시작·test2instance 경쟁, 프로필 복원·불변식 검사. API 오류면 mock로 PASS 대체 금지.

**완료 게이트**: T-SAVE(Mock+실서비스)/T-ISOLATION/T-SEC. 같은 run 보상 중복0, 소유권 상실 old writer 저장0, 데이터 로드 실패시 저장0. **증거** `artifacts/P8/{fault-matrix.json,datastore-live.json,rejoin.json}`. 강제 crash 전 미확정 보상 손실은 명시 한계로 기록.

### P9 — 전체 수용·공격·장치·부하·출시 준비

**선행** P1~P8 완료. **소유** `tests/scenarios/*`, release checks, 문서/fixture만 QA owner, 수정은 해당 파일 owner. **요구** R-01~R-10 전체.

- [ ] P9.1 s01→s02→s03 정상 플레이, 각 패배·시간초과·재도전·성장·재접속, 서버 결과와 화면 일치.
- [ ] P9.2 malformed/NaN/inf/거대payload/spam/다른match/과거seq/임의수치·중복보상 공격, queue/로그 상한.
- [ ] P9.3 PC·Studio 모바일 에뮬레이터 + Android 실기기 입력/기능/가로세로·safe area·멀티터치, 저속통신.
- [ ] P9.4 4독립 경기×아군30/적40/탄128에서10분 측정. tick p95≤10ms·장치 frame 목표 확인; 미달 시 상한/표현 최적화 후 회귀.
- [ ] P9.5 원본 에셋/코드·비인가 model script·test harness 없는 production build, manifest/hash 일치.
- [ ] P9.6 모든 T-* 증거, 정적분석/format/lint/build, 재현 명령·환경, 알려진 제한을 reviewer가 확인.

**완료 게이트**: TEST_PLAN의 출시 체크리스트 전부. 보안/저장 핵심 실패는 출시 차단. QA 미연결/실기기 미측정은 '보류'이지 통과 아님. **증거** `artifacts/P9/{acceptance.json,security.json,performance.json,asset-audit.json,review.md}`.

## 4. 추천 작업 분할과 OMX 운용

설치 카탈로그에서 확인한 관련 native role: `explore`, `researcher`, `planner`, `architect`, `critic`, `executor`, `test-engineer`, `verifier`, `code-reviewer`, `designer`, `writer`. 가능한 role이라는 뜻이지 모든 모델이 현재 계정에서 실행됨을 보장하지 않는다. 실제 실행 전 role/model capability를 점검하고 실패를 승인으로 간주하지 않는다. 일반 native child는 executor 등 명시 role, `worker`는 활성 team runtime에만 사용.

| lane / owner | 추천 역할·추론 수준 | 독점 소유 | 병행 시 주의 |
|---|---|---|---|
| leader | 주 agent / high | 요구·정본·통합·최종검증 | 단계 gate·저장/프로토콜 변경 승인 |
| A 데이터 | executor / medium, 최초근거 researcher | tools/data/Generated/PublicCatalog | Protocol과 UI 이름 변경은 interface 변경으로 공유 |
| B 시뮬레이션 | executor / high | server/Simulation, MatchService | P3 이전 DTO 고정, 임의 신규 패키지 금지 |
| C 표현·입력 | executor 또는 designer / medium~high | client/Presentation | 서버 파일 편집 금지, mock snapshot 계약 사용 |
| D 저장·성장 | executor / high | Persistence/Profile/Progression | mock fixture와 정산 계약에 lockstep 변경 |
| Q 검증 | test-engineer + verifier/code-reviewer / high | tests/scenarios/artifacts | 구현한 본인이 유일 승인자가 되지 않음 |

동시에 native child 최대6. 작은 단계는 solo로 끝내고, 분할 가치가 있는 P4/P5/P7만 2~3lane 병행한다. 각 owner는 다른 작업자가 있음을 전제로 다른 변경을 되돌리지 않는다. 타입·프로토콜·Rojo 공용 파일은 leader 한 명이 통합한다.

후속 durable 목표 관리는 `$ultragoal`을 기본 추천하고, 병행 가치가 있으면 **Ultragoal+Team**으로 운영한다. Ultragoal이 leader 소유 완료 ledger를 관리하고 Team은 bounded task와 원시 증거를 반환한다. 외부자료 확인에는 `$best-practice-research`; 측정 후 성능 개선을 별도 목표로 잡을 때만 `$performance-goal`. 이 구현 작업을 연구 프로젝트로 바꾸기 위해 `$autoresearch-goal`을 사용할 필요는 없다.

후속 실행 예시(명령 예시이며 이번 작업에서 실행하지 않음):

```text
$ultragoal docs/IMPLEMENTATION_PLAN.md의 P0부터 순서대로 구현; 각 단계 T-* 증거 필요
$team 3:executor "P4 탄/영웅, P5 입력/뷰, P7 성장; 경계/소유권은 IMPLEMENTATION_PLAN 준수"
omx team 3:executor "docs/IMPLEMENTATION_PLAN.md의 승인된 병행 task만 구현"
```

Team/tmux CLI가 없는 App/native 환경에서는 해당 런타임을 실행했다고 주장하지 않고 bounded native role 작업+leader 통합으로 진행한다. `$ralph`는 사용자가 의도적으로 지속 single-owner 수정/검증 루프를 선택한 경우에만 대안이며 기본 경로가 아니다. 명시 실행 요청 전에는 이 설계 작업에서 게임 개발 루프를 자동 시작하지 않는다.

Team 종료 전 각 task의 targeted tests/type/static/build와 MCP server/client evidence를 leader가 읽고 shared tree를 재빌드한다. Ultragoal checkpoint에는 taskId/파일/commands/raw logs/verdict/남은 위험을 기록한다. task가 claimed/completed라고 표시된 것만으로 검증을 대체하지 않는다.

## 5. 위험·pre-mortem·중단 조건

| 실패 가정 | 조기 징후 | 대응 / 검증 |
|---|---|---|
| 잘못된 원본 행/주석 반입으로 전투·경제 파괴 | 쥐HP300, 거북AP100000, U5를19%로 해석 | P1 namespace+quarantine+golden, 원작 미확정은 새 결정으로 분리 |
| 재접속/저장 오류로 중복·롤백 | Pending인데 재전투 가능, stale server 저장 | P8 fence+revision+runordinal, callback replay/unknown commit 시험, 실패시 잠금 |
| 모바일/네트워크에서 조작 불능·서버 과부하 | 이동 stuck, catchup drop, frame p95초과 | P5 입력TTL·보간, P9 4경기cap·실기기 측정, cap/FX 줄이고 재검증 |

검증은 단위(수치·순수 전투) → 통합(remote·저장 경합) → e2e(Studio의 실제 input) → 관측/부하(metric) 네 층을 모두 사용한다. 자세한 fixture·기대값은 TEST_PLAN.

필수 입력 부족으로 gate가 실패하면 다음 단계 완료를 주장하지 않는다. 안전한 mock/순수 테스트 등 독립 작업은 계속할 수 있다. 공개 배포·데이터 삭제·유료 에셋 같은 범위 변경을 이 계획의 자동 실행 권한으로 해석하지 않는다.

## 6. 설계 작업의 검증 및 handoff 상태

현재 6개 문서는 [확인/추정/신규] 경계를 명시한 구현 기준선이다. 원본 문서7개는 수정하지 않는다. 이번 실행에서는 네이티브 researcher/planner/architect의 설정 모델 gpt-5.4-mini와 critic의 gpt-5.5가 계정 미지원 오류로 실행되지 않았다. 따라서 **독립 역할 검토/ralplan consensus 승인은 미완료**이며, 해당 오류를 검토 통과로 기록하지 않는다. 공식 문서 직접 확인, leader의 정합성 검토, 로컬 문서 검증으로 이번 문서 작성 범위를 확인했다. 원시 검증 기록은 커밋 대상이 아닌 `.omx/plans/`에 보존한다. Architect→Critic 승인은 후속 구현 시작 전 지원 가능한 역할 환경에서 별도로 수행할 수 있으며 문서 작성 완료와 별개다.

게임 코드·변환기·harness·Studio 테스트는 P0 이후 작업이다. 문서 합격과 게임 MVP 합격을 구분한 상태로 다음 구현 담당자에게 넘긴다.
