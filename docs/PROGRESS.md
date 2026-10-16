# 개발 진행

- 현재: P9 수용 suite 작성(실행 보류). 실 DataStore 접근은 승인 전까지 금지.
- 테스트 정책(2026-10-16 변경, `AGENTS.md` "테스트 정책"): 이전의 "테스트 실행 전면 중단"을 대체한다. 구현 중엔 관련 핵심 suite+정적 분석만, Studio는 P0/P5/P6/P8/P9, 전체 회귀·부하는 P9. 저장 무결성·서버 권한·중복 보상 테스트는 생략하지 않는다.

## MVP 연결 기준선(이전 커밋)

- 목표: Rojo 기본 프로젝트에서 부팅 → 이동·식량 → 전위병 소환·자동 근접전 → 승패·재시작.
- 범위: s01 한 곳, 전위병 한 종, 생성 도형과 기존 2.5D 카메라 재사용. 유한 적 조우 후 적 핵 파괴 또는 영웅 사망으로 종료.
- 저장: 서버 메모리만 사용. 영구 저장·보상·성장·추가 스테이지는 제외.
- 구현: `default.project.json`의 PlayableMvp 플래그로 실제 서버 런타임을 시작한다. 기존 테스트 프로젝트는 수동 테스트 rig를 유지한다. s01 적 3마리, 전위병만 허용, 결과 고정·로비 복귀·새 전투를 연결했다.
- 로컬 검증(2026-10-16 KST): MVP 52 / P2 132 / P3 123 / P4 134 / P5 613 cases PASS. `verify_p0.py --local-only` PASS(분석·lint·format·빌드·Python 테스트 포함).
- 수치 조작 없는 통합 실행: 소환으로 1,746 tick(87.3초)에 승리, 무입력 시 2,038 tick(101.9초)에 패배. 권한·중복 차감 방지·저장 fence·결과 1회 종료·재시작 검증.
- 실제 플레이: 승인 universe `10771015944`에서 Rojo 새 모듈·플래그 동기화 확인. 시작 후 실제 실행된 bootstrap/UI는 이전 소스였고 Remotes가 없어 플레이 검증 미완료. 원인은 확정하지 않았다.
- 사용자 요청에 따라 Studio playtest를 중단하고 P6 개발로 전환한다. 이후 테스트 실행은 중단하며, 새 변경은 미검증으로 기록한다.
- 동일 실패는 원인 분석 후 최대 두 번만 수정하고 미해결 사항을 여기에 기록한다.

## P6 핵심 구현(검증 보류)

- 사용자 요청: 테스트 중단, P6 개발로 전환. Studio playtest와 Rojo 서버 종료.
- 범위: 기존 3스테이지 설정 재사용, seed 기반 느림/빠름 반복·가중치·cap 타이머 동결, immutable 결과 1회 생성, 메모리 기록·해금·로비 복귀, 잔존 전투 오브젝트 정리.
- P6 커밋에서는 P7 화폐/XP/성장·P8 영구 저장을 제외했다. 테스트 코드는 준비했으나 실행하지 않았다.
- 구현: `StageSystem`의 정수 PRNG·가중치·느림/빠름 block 반복·cap 동결, 종결 결과와 처치 합계 deep-freeze, 기록 Pending/Committed 표시, stage wins/bestTicks 1회 갱신과 순차 해금, 로비 복귀 시 프로필 갱신, 종료 병력·탄 및 이탈 세션 정리. 3종 소환·Q 시전은 기존 기능을 재사용한다.
- 정적 확인: Luau CLI/Roblox 타입 분석, Selene, StyLua, production/test Rojo 빌드 통과. 테스트 실행·Studio 재호출 없음.
- 미완료: P6 suite 실행, 정상 입력으로 3스테이지 플레이·밸런스 확인, 재연결/반복 경기 GUI·메모리 누수 확인, Studio 실행 소스 불일치 원인 확인. 위 MVP 테스트 수치는 이전 커밋 기준이며 P6의 PASS 증거가 아니다.
- 브랜치: `p6-stage-flow`. 실행 검증 전이므로 P6 gate PASS·main 병합으로 처리하지 않는다.

## P7 핵심 구현(검증 보류)

- 범위: 서버 결과 → 승리 보상·첫 승리 추가·누적 XP/레벨/포인트, 기존 강화·특성 트랜잭션 연결, 로비 성장 UI와 확정 보상 표시.
- 기존 프로필 queue·expectedRevision·operation receipt를 재사용한다. 저장 backend는 서버 메모리 그대로이며 P8/DataStore는 진행하지 않는다.
- 핵심 계약 테스트는 추가하되 사용자 중단 요청에 따라 실행하지 않는다. 타입·lint·format·빌드만 최소 확인한다.
- 구현: 순수 `ResultReducer`로 결과 식별자·처치 합계 검증 후 승리 보상/첫 승리 추가/상한 실제 delta/레벨·포인트/해금을 한 트랜잭션에 반영. 패배·시간초과·Abandoned는 보상 0. 기존 강화·특성 로직을 `ProgressionService`로 재사용한다.
- UI: 로비 우측 상단 성장 메뉴에서 3종 강화·특성 배분, 골드·누적 XP·레벨·포인트·최고 기록 표시. Pending 중 중복 입력 잠금, StaleRevision은 최신 요약으로 갱신하며 자동 재구매하지 않는다. 결과 화면은 commit 후 실제 지급량만 확정 표시한다.
- 정적 확인: CLI/Roblox 타입 분석, Selene, StyLua, production/test Rojo 빌드 PASS. 기록: `artifacts/P7/development/`. 실행 테스트·Studio MCP 호출은 하지 않았다.
- 테스트 준비: T-P7(CLI/Studio 공용)에 첫 보상·중복/경합·상한·레벨/포인트·다음 경기 적용·클라이언트 구매 흐름을 추가했다. T-P6의 보상 기대값은 P7 계약으로 변경했다. **모두 실행 미검증**.
- 미완료: P6/P7 회귀 실행, 실제 승리→보상→강화→재경기 UI/밸런스 확인. 이전 Studio 실행 소스 불일치·재연결/누수 검증도 남아 있다. P8 영구 저장은 미구현.
- 브랜치: `p7-growth-rewards`. 검증 전이므로 P7 full gate PASS·main 병합으로 처리하지 않는다.

## P8 핵심 구현(비활성·검증 보류)

- 범위: 기본 차단된 테스트용 DataStore 어댑터, lease/fence·예산·제한 재시도, 기존 단일 프로필 queue에 갱신/종료 연결, 늦은 응답·중단 경기 복구 처리.
- 실제 DataStore 호출·Studio API access 변경은 승인 없이 하지 않는다. 기본 실행 backend는 서버 메모리로 유지한다.
- 핵심 fault 회귀 코드는 준비하되 실행하지 않고, 타입·lint·format·빌드만 확인한다.
- 구현: `Persistence/`에 기본 비활성 정책·QA 전용 키·DataStore binding/adapter·bounded validator·순차 request runner 추가. 활성화는 `PersistencePolicy.config.enabled=false`가 기본이며 승인된 universe의 Studio만 허용한다. 실제 API/설정 접근은 하지 않았다.
- 기존 profile queue를 유지하며 lease180초·40~50초 갱신·안전여유30초·session/fence 검증을 연결했다. 요청 예산 확인, 최대5회/관측20초 재시도, 응답 유실 시 동일 operation/closed-run 증명으로 중복 지급 차단, 중단 세션의 늦은 응답 무시, 이탈/종료 flush·재접속 대기·Abandoned 복구를 추가했다. 별도 경쟁 writer queue는 만들지 않았다.
- Runtime은 기본 서버 메모리 backend 그대로다. BindToClose는 기존 writer를 최대25초 대기하며 미확정 저장 손실 가능성을 경고한다. 호출 자체가 yield 중이면 deadline이 호출 취소나 rollback을 뜻하지 않는다.
- 테스트 준비: T-P8(CLI/Studio 공용)·offline FakeDataStore로 callback 재실행·API 실패/예산0·손상 profile·응답 유실·receipt 소실·stale fence·빠른 재접속·늦은 갱신·중복 종료를 작성했다. **테스트 실행은 하지 않았다**.
- 정적 확인: CLI/Roblox 타입 분석, Selene, StyLua, production/test Rojo 빌드 PASS. 기록: `artifacts/P8/development/`. 보호 문서·생성 수치·TestPolicy allowlist 변경 없음.
- 참조: [UpdateAsync/콜백·예산 공식 계약](https://create.roblox.com/docs/cloud-services/data-stores), [요청 budget API](https://create.roblox.com/docs/reference/engine/classes/DataStoreService#GetRequestBudgetForRequestType).
- 미완료: P6~P8 실행 회귀, 실제 DataStore 승인·활성화·재시작 복원/두 Studio 경쟁 검증. 장기 API 지연·강제 종료의 미확정 보상 손실은 남는 한계이며 무손실/실서비스 PASS를 주장하지 않는다.
- 브랜치: `p8-persistence-safety`. 실서비스 검증 전이므로 P8 full gate PASS·main 병합으로 처리하지 않는다. P9는 진행하지 않았다.

## P9 수용 suite 작성(실행 보류)

- 사용자 선택(2026-10-16): 테스트 실행 중단 유지, P9 코드만 작성.
- `tests/unit/P9.luau` + `tests/cli_p9.luau`, Studio `ServerHarness.runSuite("T-P9")` 등록. 모든 입력은 `RemoteGateway`(검증·rate limit·ingress 순서)를 거치고 Runtime과 같은 drain→stepAll 순서로 진행한다. 저장은 Mock/InMemory.
- P9.1(E2E Mock): 클라이언트 합법 명령만 쓰는 봇(10tick마다 소환3·시전)으로 s01→s02→s03 각 최대3회 도전. 수치 조작 없음. 매 경기 12000tick 내 종결·Settled·승리 시에만 wins+1/골드 증가·activeRun 닫힘·로비 복귀를 검사하고, s01 정상 플레이 승리를 요구한다. s02 미승리면 s03 잠김 확인. 로비 강화 후 같은 store로 새 세션 재접속해 골드·XP·유닛 레벨·wins·revision 복원과 schema 유효성 검사.
- P9.2(T-SEC): 같은 seed의 공격 서버와 대조 서버를 나란히 돌려, 허용 외 필드(hp/gold)·NaN/inf/음수/소수/범위 밖 slot·NaN seq·긴 matchId·100KB requestId·중첩/순환 table·미지 kind/stage·타인 match(Summon/Cast)·과거/재사용 seq·전투 중 구매·비table 원시값·잘못된 move 5종 뒤 두 플레이어 World digest·골드·revision이 대조군과 동일한지, 예외0·피해자 거부 메시지0·reason별 집계 상한을 검사한다. flood(1000건)는 기존 T-P2가 담당.
- P9.4(T-PERF 축소판): 4경기 s03에 아군30/적40 cap을 주기적으로 채우고 1200tick(60초) step 시간 p95≤10ms·cap 초과0·탄 발생을 검사한다. 헤드리스 fixture이며 10분 Studio 측정·클라이언트 frame·메모리 기준선 복귀를 대체하지 않는다.
- 정적 확인: luau-analyze(tests), luau-lsp Roblox 분석, selene 0경고, StyLua, production/test Rojo 빌드 PASS. **T-P9는 한 번도 실행하지 않았다**(s01 승리·p95 기준은 미측정 가정).
- 미작성: `verify_p9.py` gate, P9.3 실기기/멀티터치, P9.5 production 에셋 audit 확장, 100회 경기 생성/종료 누수 측정. P6~P8 실행 회귀가 선행 미완료다.
- 브랜치: `p9-acceptance-suite`(P8 위). 실행 전이므로 PASS·main 병합으로 처리하지 않는다.

## CLI 실행 결과 (2026-10-16, 새 테스트 정책)

- P6 162 / P7 74 / P8 52 / P9 78 cases PASS (`tests/cli_p6~p9.luau`). 저장 무결성·서버 권한·중복 보상 케이스 포함. 제품 코드 변경 없음.
- P9 수정 2건(테스트 쪽): ① P2용 Mock 어댑터는 lease를 갱신하지 않아 180초 넘는 경기의 결과 저장이 `stale`가 됐다. Runtime 기본값인 `SessionStore`로 교체했다. ② `NotOwner`는 MatchService가 직접 응답하므로 게이트웨이 집계 대신 응답 메시지로 센다.
- 봇 결과(seed 12345): s01 첫 도전 승리, s02 3회 모두 패배 → s03 잠김 유지 확인. 정상 입력 기준 s02 난이도가 봇 전략보다 높다. 밸런스/봇 판단은 미결.
- 부하 축소판(4경기·cap·1200tick) p95≤10ms PASS(CLI 환경 한정).
- NOT_RUN: P6·P8·P9 Studio 검증, 실 DataStore(승인 필요), 10분 부하, 실기기/멀티터치, `verify_p9.py`.

## Studio·부하 검증 (2026-10-16)

- 승인 universe `10771015944`. Rojo가 기존 스크립트 14개에 패치를 적용하지 못해 Studio가 P5 소스로 남아 있었다. 이전의 "Studio 실행 소스 불일치" 원인으로 보인다. 재연결 후에도 같아서, 현재 소스를 `rojo build` rbxm으로 만들어 MCP `import_rbxm`으로 교체했다(저장 안 함). 스크립트 91개 바이트 길이가 로컬 sourcemap과 일치.
- 2-client playtest 서버: T-P6 162 / T-P8 52 / T-P9 78 PASS. CLI와 순서별 assertion 해시 일치.
- 부하(Studio 서버 VM, 헤드리스 World): 4경기 cap 유지, 워밍업 1200 + 측정 12000 tick(게임 10분, 실제 약 15Hz로 14.8분). tick p50 1.46 / p95 1.97 / p99 2.66 / max 5.10ms, cap 초과 0, GC 1517→1479KB. 한계: Remote·snapshot 미포함, 탄 최대 14개라 탄 상한 128은 미달.
- `tools/verify_p9.py`: CLI P6~P9 재실행 + Studio 증거(소스 길이·suite 해시) 검증. 결과 BLOCKED(exit 2): studio-suites·perf PASS, 실 DataStore(사용자 미승인)·실기기/멀티터치(도구 없음) BLOCKED. 위조 해시는 FAIL로 확인.
- 미해결: Rojo 패치 미적용 원인(플러그인 쪽), place 반복 재열림, s02 봇 3연패(밸런스), 탄 상한 부하.

## 밸런스 진단·P9 보강 (2026-10-16)

- 헤드리스 전략 탐색(seed 3~5개, 수치 변경 없음):
  - s01: 모든 소환 전략 승리.
  - s02: 투척 기계 우선이면 3/3 승리, 싼 전위병 반복이면 전패. → P9 봇을 투척 기계 우선으로 바꾸고 s02 정상 플레이 승리를 요구한다.
  - s03: 유닛 L1~L5·특성 최대에서 모든 전략 0승.
- s03 원인: 식량 회복 초당 2 대비 출현 평균 약 2.7초당 1마리(빠른 구간 1~2초). 아군이 수에서 밀려 영웅까지 뚫린다. 출현 간격을 s01 수준으로 늦춰도 L5에서 2/5승이라 brute(공격력 330)·핵 HP 1400도 함께 봐야 한다. 수치는 `DATA_MODELS` §3.4 값 그대로이며, 변경은 overlay 결정이 필요한 **사용자 판단 대기** 상태다.
- P9 부하 축소판에 탄을 상한 128까지 유지하는 조건을 추가했다. CLI p95≤10ms PASS.
- CLI P9 84 PASS. 코드가 바뀌었으므로 이전 Studio T-P9 증거는 무효이고, Studio는 밸런스 결정 뒤 한 번에 다시 돌린다(NOT_RUN).

## s03 밸런스 조정·회귀 수정 (2026-10-16)

- 사용자 선택: overlay로 조정. 결정 `MVP-STAGE-02`(approvedBy null): s03 출현 간격을 s01 수준(100~120 / 40~60 tick)으로, 가중치를 scrapper/spitter/brute 50/30/20 → 60/30/10으로. brute 수치·핵 HP·보상은 그대로. 설계 문서는 수정하지 않았고 P1 golden에 결정 ID와 함께 반영했다.
- 근거(헤드리스, 투척 기계 우선, 8 seed): 조정 전 L5+특성 최대 0승 → 조정 후 L1 0/8, L3+보급2 5/8. brute HP가 결정적 변수였고 공격력·핵 HP는 영향이 미미했다.
- P9 봇이 도전 전에 로비에서 투척 기계 강화·보급 특성을 원격 경로로 구매한다. 결과: s01→s02→s03 모두 첫 도전 승리, 재접속 후 강화 L5·골드·XP·승수 복원.
- 기존 회귀 2건(P6~P8 이후 미실행으로 발견): ① P2 요약 키 기대값을 P7 로비 DTO에 맞춤(owner 전용 파생값만). ② P8 변경으로 클라이언트가 `Unavailable` 이후 부트스트랩을 영구 중단하던 버그 수정: 서버는 재접속 lease 대기 등에서 회복될 수 있으므로 ProtocolMismatch 외에는 1초 간격 재시도.
- CLI: P1 PASS, Python PASS, P2 132 / P3 123 / P4 134 / P5 613 / P6 162 / P7 74 / P8 52 / P9 74 PASS. 정적 분석·lint·format·두 빌드 PASS.
- NOT_RUN: 코드 변경으로 Studio 증거 무효, Studio 재검증 필요. 실 DataStore(미승인)·실기기 터치 BLOCKED.

## P9 Studio 전체 회귀·부하 (2026-10-16, 커밋 e21241a 기준)

- 동기화: rbxm import(저장 안 함). Studio의 이름=길이 해시가 로컬 sourcemap과 일치(스크립트 91개, 410,548바이트).
- 2-client playtest 서버: T-TOOL 10 PASS, 의도적 실패는 그 1건만 FAIL, 미지원 suite 거부. T-P2 132 / P3 123 / P4 134 / P5 613 / P6 162 / P7 74 / P8 52 / P9 74 PASS, 모두 CLI와 assertion 해시 일치. client-1 T-P5 613 PASS(해시 동일).
- 부하: 4경기·아군30/적40·탄 128 유지, 측정 12000 tick(게임 10분). p50 5.10 / p95 6.09 / p99 8.36 / max 13.18ms, cap 초과 0. gcinfo 2651→3221KB(강제 GC 없음, 누수 판정 아님). Remote·snapshot 미포함.
- `verify_p9.py`(P2~P9 CLI + Studio 해시 비교로 확장): **BLOCKED(exit 2)**. CLI 8개·studio-suites·perf PASS. 실 DataStore(미승인)·실기기 멀티터치(도구 없음) BLOCKED.
- 미해결: Rojo 패치 미적용(rbxm import로 우회), place 반복 재열림, 실 DataStore·실기기, 100회 경기 생성/종료 누수 측정, Remote 포함 부하, 밸런스 승인(approvedBy null).

## 수명주기·snapshot 부하 (2026-10-16, 커밋 7f09782 기준)

- T-P9에 경기 100회 생성→종결→정산→로비 반복 추가. 진단용 `MatchService.ownedMatchCount` 추가. 반복 후 활성 경기·소유 맵 0, world/result/snapshot nil, activeRun 닫힘, 영수증 상한 이내, 승리 100회 모두 기록. 처음 실패는 0.1초당 1경기 속도라 gateway rate limit이 StartStage를 정상적으로 버린 것이었고, 반복마다 1초씩 진행하도록 고쳤다.
- 부하 측정에 10Hz owner snapshot 생성(entities/projectiles/heroAction)을 포함했다.
- Studio(소스 91개, 길이 해시 일치): 서버 T-P2~P9 PASS(P9 83), CLI 해시 일치. client T-P5 613 PASS. 10분 부하: p50 5.05 / p95 5.87 / p99 7.16 / max 20.11ms, cap 초과 0, 탄 최대 128. 엔진의 Remote 직렬화는 포함하지 않았다.
- `verify_p9.py` BLOCKED(exit 2): CLI 8개·studio·perf PASS. 실 DataStore(미승인)·실기기 멀티터치(도구 없음)만 남았다.
- 사용자만 처리할 수 있는 항목: 실 DataStore 승인, Android 실기기 터치 검증, overlay 결정 승인(approvedBy), Rojo 플러그인 패치 미적용·place 재열림 확인.

## 실 DataStore 검증 (2026-10-16, 사용자 승인)

- 조건: 사용자가 테스트 universe `10771015944`의 "Studio API 서비스 액세스"를 켜고 QA 키 검증을 승인. namespace `LanternExpedition_P8_QA_v1`, 키 `qa:u:-1792115857`(음수 id라 실제 사용자와 겹치지 않음).
- 실행 방식: MCP playtest 시작이 반복 실패하고 Studio가 한 번 연결 해제돼, Studio **편집 모드**에서 실행했다. `PersistencePolicy.enabled`는 저장하지 않은 Studio 사본에서만 켰다가 원래대로 되돌렸다(저장소는 계속 false). 이 사이 place가 다시 열렸을 때 켜 둔 값이 남아 있어 자동 저장된 것으로 보이며, 되돌린 뒤 길이가 545로 원본과 같은 것을 확인했다.
- 세션 A(실제 binding/어댑터 + Gateway·MatchService·ProfileService): 새 프로필 lock(fence 1) → StartStage Committed → 승리(핵 HP 0 fixture) 정산 Committed → slinger 강화 Committed → 해제. 캐시 없는 원본 읽기: 골드 150 / XP 60 / slinger 2 / 승리 1 / revision 3, lease·activeRun 비어 있음.
- 세션 B(새 서비스): 같은 값으로 복원, fence 2, 스키마 유효. 세션 B가 lease를 잡은 동안 세션 C 획득은 `locked`, 세션 A의 옛 토큰 쓰기(골드 999999)는 `stale`, 원본 골드 150 유지.
- 정리: RemoveAsync 후 값 nil. ListKeysAsync에는 같은 키 이름이 남는다(DataStore 버전 보관으로 추정). 다른 QA 키는 없다.
- 한계: Studio 프로세스 하나 안의 서로 다른 세션이며 Studio 두 개를 쓴 경합이 아니다. 강제 종료(crash) 시험은 하지 않았다.
- `verify_p9.py`: datastore-live PASS. 전체는 **BLOCKED(exit 2)**: device-touch(실기기 멀티터치)만 남음.
- 사용자 조치: 검증이 끝났으므로 "Studio API 서비스 액세스"는 다시 꺼도 된다.

## 밸런스 결정 승인 (2026-10-16)

- 사용자 승인: overlay 결정 14개 전체(MVP-STAGE-02 포함), approvedBy "jaetech". 재생성 결과 바뀐 것은 balance JSON의 overlayFileSha256뿐이고 생성 Luau·balanceHash는 그대로다. P1 gate·Python 테스트 PASS.

## 실기기 터치 (2026-10-16)

- 사용자가 Android 실기기를 확인할 수 없어 device-touch는 **BLOCKED(알려진 제한)**로 둔다. PASS·WAIVED로 바꾸지 않았다. 출시 전에 실기기에서 이동+소환+시전 동시 터치, 버튼 밖 release/취소, safe area를 확인해야 한다.

## 출시 증거 묶음·production 감사·저속 통신 (2026-10-16)

- `verify_p9.py`에 production 출시 빌드 감사(`default.project.json` 빌드: test harness·원격 endpoint·debug grant 0, 외부 asset/HTTP/loadstring/숫자 require 0, 스크립트 수 = 출시 소스 수, T-ASSET manifest 일치, sha256 기록)와 저속 통신 항목을 추가했다. 실행할 때마다 `artifacts/P9/{acceptance,security,performance,asset-audit}.json`·`review.md`를 쓴다. 감사 음성 테스트 `tools/tests/test_p9.py`를 추가했다(Python 100 PASS).
- T-P9 부하 case가 CLI에서 8회 중 1회 p95 10.27ms(평소 약 7.5ms)로 흔들렸다. 호스트 잡음으로 판단했다. 기준 10ms는 그대로 두고, 최대 3회 측정한 p95 중 최솟값을 쓴다(상한 위반은 매 회 합산). CLI 3회 연속 PASS, Studio T-P9 83 PASS(digest 동일).
- 저속 통신: Studio poor 프로필(지연 150ms+지터 100ms 양방향, 손실 0.5%)에서 실제 GUI로 s01 시작·소환·시전이 서버에 반영됐다. 40초 표시 샘플은 "연결됨" 397/400, "연결 불안" 3이다.
- Studio에서 발견: rbxm import에는 `ReplicatedStorage.StageGameplay` 속성이 빠져 클라이언트가 스테이지 모드로 뜨지 않는다. 미저장 편집본에서만 `true`로 맞췄다.
- 결과: `verify_p9.py` **BLOCKED(exit 2)**. device-touch(Android 실기기)만 남았다. P0 local PASS.
- 출시 전 수동 확인: PersistencePolicy 활성화(현재 false, QA universe 고정), 에셋 시각·라이선스 검토, 실기기 터치. reviewer 서명은 없다(테스트 정책상 다중 에이전트 리뷰 생략).

## 원작 재현 확장 R0·R1 (2026-10-16)

사용자 지시로 범위를 원작 재현(시스템·수치 동일, 외형·이름 오리지널, 팔라독·다크독 캠페인 + 서바이벌)으로 넓혔다. 계획·결정은 `docs/REMAKE_PLAN.md`.

- R0: `tools/build_remake.py`가 부록 A1~A14 전체(스테이지 241행 포함)를 파싱한다. golden 30개와 행 수 검사를 거쳐 `data/remake/db.json`, `src/server/Config/Remake/Db.luau`, `src/shared/RemakeCatalog.luau`를 만든다. 연구 원문 이름은 출시 트리에 넣지 않는다(테스트로 확인). Python 3개 PASS.
- R1: `src/server/Battle/`(30Hz 원작 단위 전투)를 만들었다.
  - 식량·마나·HP 재생, 소환 비용·쿨·리더십, 유닛 9종(레벨표 대체, 스킬, 오오라 밖 스킬 불가, 캥거루 주먹, 거북 대기, 곰·용 범위, 원숭이 포물선, 펭귄 빙결)
  - 적 1~40(거대·강화 배수, 원거리 5종, 유령, 벽형, 자폭), 본진·50% 거대 러시, 처치 보상(난이도·재클리어·15분 규칙·스킬 보너스)·드롭 판정
  - 메이스 11종, 레벨업 3지선다(전투 일시정지, 5의 배수 고정 후보), 결정론 digest
  - `tests/cli_r1.luau` 112 PASS, P0 local PASS.
- 미구현(다음 단계): 보스 패턴·운명·목마·타워(R2), 프로필 v2·정산·MatchService 교체(R3), 클라이언트(R4), 다크독(R5), 서바이벌(R6). 기존 MVP 시뮬레이션은 R3에서 교체한다.
- [추정]: 투사체 판정 폭 10px(D-PROJ-01), 메이스 모션 18프레임·효과 8프레임(D-ANIM-02), 유령 이동 속도, 서버 보호 상한 아군 80·적 120(원작 무제한).

## R2 특수 모드·보스 (2026-10-16)

- 모드 판정(`s%12`: 보스/운명/목마/타워/일반)과 모드별 규칙을 `Battle.luau`에 추가했다.
  - 보스 스테이지: 본진 파괴 → 보스 s/12 등장·아군 넉백 ×3 → 보스 처치 승리
  - 운명: 유닛·무기 강제, 3초마다 9칸 박스(50/50, 6번째 U5), 박스만으로 소환, 60킬 승리, 60마리 스폰 상한, 이동 불가
  - 목마 호위: 마차 HP = iECHP_, x>870 승리, 마차 파괴 패배
  - 타워: 5라인, 스케일 0.6, 라인 지정 소환, ±15점, 오오라 없음, 90/90/30 MP 버튼, 고정 중간 보스
- 보스 10종 패턴: 호위 소환, 개구리화(영웅 비대상), 넉백 ×3, 순간이동, 즉사, 영웅만 피해 가능, 브레스 3명·빙결, 독 키스, 즉사 마법. 영웅 독·부활 무적도 넣었다.
- 부활: 제안 시 일시정지, 체력·식량·마나 최대, 10초 무적, 1회. 10초 무응답이면 포기.
- 타이머(스폰·러시·상자·소환 쿨·공격 대기)를 정수 틱으로 바꿔 부동소수 누적 오차를 없앴다.
- `tests/cli_r2.luau` 77 PASS, R1 112 PASS, P0 local PASS. [추정] 결정은 `data/remake/design.json` decisions에 기록했다.

## R3 성장·서버 통합 (2026-10-16, 브랜치 r3-growth-server, main 미병합)

- 프로필 v2(D-SLOT-01): 계정(젬·업적·다크독 해금·반지 3번칸) + 슬롯 3개(영웅·난이도·골드·EXP·스킬·유닛·별·최고기록·인벤토리 100·장착 9). 아이템은 원작처럼 정수로 묶어 저장한다. 저장 검증 한도를 v2 최악 크기에 맞춰 올렸다(D-SAVE-01).
- 경제(로비 트랜잭션): 슬롯 생성·삭제·선택, 유닛 해제/강화(선행 체인 6←4·5←6), 스킬 학습·초기화(젬 1000), 골드 상점·판매·장착·강화(젬 (g+1)×2, 등급 상한 5+5×보스 클리어), 젬 상점. 전투 중에는 모두 거부한다.
- 정산: 골드(획득−황금 무기 지출)·EXP·레벨업 선택(미선택은 자유 포인트)·부활 젬·드롭(D-DROP-01/02)·퀘스트 보상·별·다음 스테이지 해금·업적. 결과 식별자·범위·선택 수를 다시 검사한다.
- 퀘스트: 스테이지마다 3개를 생성한다(D-QUEST-01/02, 1-1이 원작 예시와 일치, 총액 90,000/78,000/136,500·아이템 30개).
- 프로토콜 v2, MatchService(새 전투 엔진, 30Hz, 스냅샷 10Hz), 고정 틱 30Hz를 적용했다. MVP 시뮬레이션·성장 모듈과 suite(P3/P4/P6/P7/P9)·게이트(verify_p3/p4/p9)를 은퇴시켰다. 출시 감사는 `tools/release_audit.py`로 분리했다.
- 보안·저장 검사는 이식했다: P2 133(허용목록·격리·속도 제한·큐/경기 상한·lease·재접속·고아 런), P8 51(어댑터·fence·응답 유실·재정산). R3 167에 공격 매트릭스(대조 서버와 digest·골드·젬·revision 동일)와 100회 생명주기를 넣었다.
- 결과: R1 112, R2 77, R3 167, P2 133, P8 51 PASS, P0 local PASS. **P5(클라이언트) FAIL**: 옛 프로토콜 클라이언트라 R4에서 교체한다. P8에서 클라이언트 오프라인 검사 1개를 R4로 옮겼다(미실행).
- 미구현: 다크독 전투(R5, 시작 시 WrongMode), 서바이벌(R6, stage 0 WrongMode).

## R4 인계 기준선·R5 암영 영웅 (2026-10-16)

- R4 커밋 `bef359d`와 `r5-shadow-hero`의 미커밋 전투 코드를 이어받았다. R4 CLI 63 PASS를 재확인했다. R4 Studio 실제 플레이는 이번 작업에서 NOT_RUN.
- R5: 암영 영웅 수치·장비/부적·스킬 24·크리/회피·적 디버프/가시 오오라, 토템 9(외침·가시·변신), 검 11(독 구름·흡수·빙결·화상·관통·골드), 교체 스테이지 21개, 던전 함정·자동 검, 공성 목마, 결정론 점프 코스 10개를 서버/클라이언트에 연결했다. 전용 퀘스트·별·장비 보상·슬롯 정산도 연결했다. 추가 도형 11개는 manifest에 placeholder로 기록했다.
- 회귀 수정: 종결 후/후퇴와 같은 batch의 입력 거부, 가시 직접 피해의 부식 중복 배율 제거, 변신 준비 중 이동 예측 차단, 변신·함정·화상·코인 상태 digest 포함, 독 구름의 피해 타이머 리셋 방지, 토템/함정 상한과 비용 원자성. 모든 점프 코스가 사망 없이 완주·코인 전부 수집 가능함을 확인했다.
- 검증: **R5 532**, R1 112 / R2 77 / R3 167 / R4 63 / P2 133 / P8 51 PASS. R5에 타인 Jump 거부·결과 식별자 위조 거부·정산 재전송 보상/revision 불변·서버 메모리 재접속 복원을 포함했다. Python 82(생성기 5 포함)·P0 local·재생성 diff0·출시 감사 PASS.
- NOT_RUN: R4/R5 Studio 실제 플레이, v2 실 DataStore, Android 실기기. 실 저장 접근·API 설정·publish·push는 하지 않았다. 연구에 없는 점프 지형/러너/코인 높이·검 애니/구름 등은 design.json의 추정 결정이며 원작 에셋 재현을 주장하지 않는다. 다음 단계 R6(서바이벌), 이후 R7 통합 검증.
