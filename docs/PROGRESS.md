# 개발 진행

- 현재: P9 수용 suite 작성(실행 보류). 단일 에이전트, 실행 테스트·Studio·실 DataStore 접근 중단 유지.

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
