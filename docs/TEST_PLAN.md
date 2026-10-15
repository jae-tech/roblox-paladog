# Test Plan — Luau·Studio·MCP 검증 계약

버전1.0 · 2026-10-15 · 상태: **테스트 설계 완료 / 게임 테스트 미실행**.
이 문서는 [PRD](PRD.md) R-01~10, [구현 단계](IMPLEMENTATION_PLAN.md) P0~P9의 완료 판정 기준이다. 실제 코드·fixture·harness는 아직 없다. '예정 테스트'를 '통과 테스트'로 보고하지 않는다.

## 1. 계층·실행 환경·증거

| 계층 | 대상 | 실행 방식 | 한계 |
|---|---|---|---|
| 문서/정적 | 링크·필수 요구·형식·원본 보존 | 파일 검사·정본 cross-check | 게임이 돌아감을 증명하지 못함 |
| 데이터 | 추출/ID/단위/신규 overlay | Python 표준 라이브러리 unit tests/validator | 원본 APK 실행 동등성 증명 아님 |
| 순수 Luau | resource/AI/damage/stage/growth/reducer | 의존성 없는 assert runner, fake clock/RNG/store | remote·GUI·실 DataStore 검증 아님 |
| Studio 통합 | 실제 remotes·소유권·복제·save adapter | server/client 테스트 + MCP execute_luau | mock Store만 통과하면 실 persistence는 미검증 |
| 실제 입력/e2e | 키/포인터/터치→client→server→HUD | MCP input tools + 화면/서버 상태, touch는 지원 capability 확인 | ActionRouter 직접 호출은 hardware 입력 증거 아님 |
| 실서비스/실기기 | DataStore 지속성·재접속·기기 성능 | 별도 테스트 experience, Android/PC | device emulator는 실기기 성능 대체 불가 |

운영/개발 universe를 분리하고 **테스트 universe**에서만 API access를 켠다. datastore 테스트 키는 `qa:<runId>:<caseId>` namespace를 쓰고 production `u:<id>`와 섞지 않는다. `InMemoryProfileStore`는 테스트 fake이며 Roblox MemoryStoreService가 아니다. Studio API 권한/네트워크가 없으면 실 저장 test는 BLOCKED로 남긴다. [DataStore Studio 주의사항](https://create.roblox.com/docs/cloud-services/data-stores) (조회2026-10-15).

모든 실행 evidence는 `artifacts/<P>/<runId>/` 아래 `environment.json`, `report.json`, `server-output.txt`, `client-output.txt`, `screens/`, 필요 시 replay로 기록. environment에는 UTC·git commit/build hash·balance hash·schema/protocol·Studio build·MCP 도구 schema hash·device·seed·clock policy 포함. 문서 작성 시 없는 hash/장치/통과 건수를 꾸며 넣지 않는다.

report schema:

```json
{
  "runId": "실행시생성",
  "suite": "T-RESOURCE",
  "environment": "StudioServer 또는 PureLuau 등 실제환경",
  "seed": 12345,
  "status": "PASS | FAIL | BLOCKED | NOT_RUN",
  "cases": [{"id": "T-RESOURCE-01", "expected": "...", "actual": "...", "status": "..."}],
  "failures": [],
  "evidencePaths": []
}
```

실제 report의 status는 위 문자열 설명이 아닌 enum값 하나를 사용한다. 각 assertion은 expected/actual과 tick을 남긴다. screenshot만 있는 테스트와 내부 상태 assertion이 있는 테스트를 구분한다. raw tool result를 보존하고 서술형 '잘 됨'으로 대체하지 않는다.

## 2. Studio MCP 연결·능력 발견

2026-10-15 공식 자료에는 Studio 내장 MCP와 `list_roblox_studios`, `get_studio_state`, `execute_luau`, `start_stop_play`, `get_console_output`, `screen_capture`, `user_keyboard_input`, `user_mouse_input` 등이 문서화돼 있다. 호출마다 studio_id를 지정한다. **실제 연결의 tools/list와 schema가 최종 기준**이며 아래 이름·인자는 현재 세션에 실제 존재한다는 뜻이 아니다. [공식 Studio MCP 문서](https://create.roblox.com/docs/studio/mcp).

이번 문서 작업에서 노출 도구 목록에는 Roblox Studio MCP 도구가 없었다. 따라서 Studio를 제어하거나 실제 playtest를 실행하지 않았다. REA MCP는 APK 분석 도구이며 Roblox Studio 검증 도구를 대체하지 않는다.

### 2.1 preflight 순서 (T-TOOL)

1. 운영 place가 아닌 테스트 place를 연다. Studio Assistant의 MCP 서버 활성화/클라이언트 연결 상태 확인. 설치·권한 변경이 필요한 경우 원인을 기록하고 credentials를 로그에 남기지 않음.
2. MCP capability 목록·schema·버전을 저장한다. 문서 예시를 그대로 추측 호출하지 않는다.
3. `list_roblox_studios` 등 실제 지원 도구로 대상 이름/placeId/studio_id 확인. 여러 창일 때 명시적으로 하나 선택. 대상이 불분명하면 테스트 중단.
4. `get_studio_state`로 Edit/Server/Client realm과 play 상태 확인. Rojo sync hash와 테스트 build marker를 inspect한다.
5. `execute_luau` Edit realm에서 조회 전용 smoke 수행, 이어 play 시작. server와 client realm이 준비된 후 각각 harness marker 확인.
6. T-TOOL failing assertion 1개를 고의 실행해 report FAIL 전달 확인. 오류를 성공 문자열로 삼키지 않는지 확인.
7. 정상 suite 실행 후 output/error·상태·화면 수집. 시작한 play 세션은 종료, 만든 QA key/instance는 runId로 범위를 검증한 뒤 정책대로 정리. 다른 Studio 세션/실데이터 삭제 금지.

| 필요한 capability | 용도 | 없을 때 |
|---|---|---|
| 인스턴스 조회/스크립트 읽기 | 경로·운영/test tree 확인 | Rojo build manifest+Studio Explorer 검사로 보완, 자동화 한계 기록 |
| Server realm Luau 실행 | 순수 suite·실서버 state oracle | CLI pure test만 실행, Studio 통합은 BLOCKED |
| Client realm 실행 | client snapshot/HUD/report | 서버 검증만 PASS, client 검증은 보류 |
| play start/stop·console | e2e 실행·오류수집 | 설치된 Studio의 로컬 test UI로 보완 가능하나 MCP 자동화 통과로 표기하지 않음 |
| 키보드/포인터 입력·screen capture | 실제 input→HUD 경로 | ActionRouter 테스트만 유지, hardware e2e는 미실행 |
| 멀티클라이언트/장치 에뮬레이션 | 격리/모바일 입력 | Studio Server & Clients/Device Emulator 또는 실기기로 수행. 없는 MCP tool 이름을 만들어내지 않음 |
| 실제 touch/multi-touch | 두 손가락/취소·drag-out | 마우스 클릭으로 대체 합격 금지, Android 실기기 증거 필요 |

Studio는 Server & Clients/Device Emulator 같은 테스트 모드를 제공하지만 MCP가 모두 자동화한다고 가정하지 않는다. [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes) (조회2026-10-15).

## 3. 테스트 harness 계약

향후 `test.project.json`에만 매핑:

```text
ServerScriptService/TestSupport/ServerHarness (ModuleScript)
Players.LocalPlayer.PlayerScripts/TestSupport/ClientHarness (ModuleScript)
tests/fixtures + scenarios (server/client별 필요한 것만 배포)
```

server API: `runSuite(suiteId, seed) -> Report`, `loadScenario(caseId, ownerPlayer, seed) -> runId`, `getReport(runId) -> Report`, `inspectMatch(runId) -> sanitisedState`. pure world의 `stepTicks(n)`는 headless fixture에만 쓴다. 실제 live remote/input e2e는 Heartbeat 시간으로 진행하며 직접 fast-forward하지 않는다.

client API: `runSuite(suiteId, seed) -> Report`, `inspectHUD()`, `inspectInputState()`. 단위 입력 테스트는 ActionRouter에 주입할 수 있으나 T-E2E는 MCP keyboard/mouse 또는 실제 touch를 통과해야 한다. ordinary remote에 `Debug/SetFood/WinStage/GrantGold`를 만들지 않는다.

MCP Server realm 코드 예시(향후 구현될 함수 계약, 현재 실행 불가):

```luau
local h = require(game.ServerScriptService.TestSupport.ServerHarness)
local report = h.runSuite("T-RESOURCE", 12345)
return game:GetService("HttpService"):JSONEncode(report)
```

test build marker + `RunService:IsStudio()` + 허용 test universe 검사를 모두 요구한다. fake fixtures는 별도 pure runner에서도 사용 가능. production Rojo mapping에 TestSupport/fixtures가 없는지 정적 검사하고, production build에서 test path require가 실패해야 합격한다. CLI pure runner가 `game`/Instance 없이 돌아가도록 전투·저장 reducer에 의존성을 주입한다.

## 4. 데이터·전투 테스트 행렬

아래 초기 상태·기대값은 DATA_MODELS 기준이며 별도 명시가 없으면 성장0·seed12345·고정20Hz다.

| ID / 관련 단계·요구 | fixture·조작 | 기대값/실패 판정 |
|---|---|---|
| T-DOC / 설계 / R-01,R-10 | 분석7개 SHA before/after, 산출6개 UTF-8·링크·요구/작업/테스트 연결 검사 | 원본 변경0, 깨진 로컬링크0, 미구현을 완료라 쓰지 않음 |
| T-DATA-01 / P1 / R-01,R-03 | ally 논리1의 baseHP300/L1HP100 import | runtime100, 더한400/기본300이면 FAIL |
| T-DATA-02 | A2 #1, A4 #10, stage enemy1 join | DB207 / DB225 / enemy논리1로 분리, global #join 금지 |
| T-DATA-03 | A13 N5/N6, 코뿔소 L8 fixture | N5→논리6HP4000/AP0, N6→논리5HP320/AP60, L8AP172 유지 |
| T-DATA-04 | 200px,30px/s,3frame,regen0.2 | 20stud,3stud/s,0.1초=2tick,2/s |
| T-DATA-05 | 원본 P=[15,30,100], P5=19, interval5/5 | 각각15/30/55, 매20번째 특수,5.0~5.9; MVP가중치와 혼동0 |
| T-DATA-06 | campaign iCrRwd500, iCrSec203, #353speed2 import | 보상/별/속도에 미적용; 사용 report=unused/contextual |
| T-DATA-07 | U01충돌/빈required/중복ID/헤더변경 | quarantine 또는 build FAIL. silent0/fallback 금지 |
| T-DATA-08 | 같은 입력 생성2회, overlay 검증 | hash·byte diff0, hero1/ally3/enemy3/stage3/level15, reflevel60 |
| T-RESOURCE-01 / P3 / R-04 | 초기0에서 무소모100tick | food/mana각10000milli. cap까지 진행해 각40000/100000 초과0 |
| T-RESOURCE-02 | food10000, 같은tick slot1소환2회 | 첫1회만 성공, food0,1개생성, readyTick설정1회 |
| T-RESOURCE-03 | 9999milli로 slot1, 쿨미완료, cap30 | 모두거부·잔액/쿨/state변화0. food10000으로 경계 재시험 |
| T-RESOURCE-04 | provisions1로200tick 무소모 | 재생2250/s×10초=22500milli, remainder 누수0 |
| T-COMBAT-01 / P3 / R-03 | 전/후방·다른lane·동률entity 배치 | 앞/동일lane/최근접 선택, 동률작은ID, 죽은target제외 |
| T-COMBAT-02 | vanguardAP20, 지원장 on/off, HP130 | 피해22/20. windup3/recovery7/cool66, cycle76tick |
| T-COMBAT-03 | windup target 사망·이탈·방향반전 | release0damage, recovery 진입, 주기중복0 |
| T-COMBAT-04 | 같은tick lethal2회/상호lethal | death1회/처치보상1회, batch 동시 교환타 가능 |
| T-COMBAT-05 | 60fps/30fps/불균일 Heartbeat, 동일 처리tick | 같은 논리결과. catchup>4이면 drop metric·과대dt피해 없음 |
| T-COMBAT-06 | X전진 한계·적X0 도달·heroX0 | hero/ally[0,86.4], breachReturn은 재배치1회 후 hero추적, core는 공격받음 |
| T-PROJECTILE-01 / P4 / R-03 | 고속탄의 이전X/새X 사이 얇은적 | swept hit1, 지나쳐도 누락0, 같은target재피격0 |
| T-PROJECTILE-02 | 같은lane2target·다른team·owner사망 | 관통1은 최근접1만, 아군피해0, 발사후owner사망은 탄유지 |
| T-PROJECTILE-03 | TTL/거리/맵밖·cap128·시전예약 | 조건도달제거, cap거부무차감, 죽은cast예약해제·누수0 |
| T-HERO-01 / P3,P4 / R-02 | X10에서axis1,2tick마다keepalive하며20tick;이후keepalive중단 | heroX16. 마지막intent후0.5초면axis0, 경계이탈0 |
| T-HERO-02 | mana10000에서pulse, 이동홀드 | mana0, release4tick, cooldown30tick, 이동지속. 연속cast거부 |
| T-HERO-03 | 마나9999/바쁜상태/시전자사망 | 조건별거부 또는release취소, 이미소모한마나환급없음 |

range 경계는 `range+targetRadius` 바로 안/밖과 정확히 같은 값을 함께 시험한다. 실수 위치 비교 tolerance1e-6, integer HP/resource/tick은 exact equality. unknown 애니 길이나 원작의 미확정 규칙을 golden 기대값으로 넣지 않는다.

## 5. 스테이지·성장·저장·보안 테스트

| ID / 관련 단계·요구 | fixture·조작 | 기대값 |
|---|---|---|
| T-STAGE-01 / P6 / R-05 | s01첫spawn, block3회 후 fast3회 | 첫spawn100~120tick, fast40~60tick, 정확한 count 반복 |
| T-STAGE-02 | 적40에서남은timer 저장,kill1 | cap동안timer동결, 빈자리후재개, backlog폭발0 |
| T-STAGE-03 | hero/core동시HP0, core만0, 시간12000tick | 각각Defeat/Victory/Timeout, terminal1회, 이후피해·스폰0 |
| T-STAGE-04 | 새profile s03Start, s01승리후s02 | skip거부, s02해금, s03는s02승리후만 |
| T-GROWTH-01 / P7 / R-06 | XP0→400→8100+ | L3/2포인트→L10/9포인트, XP차감없음, cap이후포인트추가0 |
| T-GROWTH-02 | gold25, vanguardL1강화,동시중복operation | L2/gold0,한번만. L5·잔액부족·전투중은거부 |
| T-GROWTH-03 | unspent1/vitality2→분배,추가요청 | vitality3/points0, 다음matchHP2600; 현재match변경0 |
| T-GROWTH-04 | s01scrapper1킬 후승리,재승리 | 첫deltaGold218/XP72, 두번째Gold118/XP72. 첫승리bonus중복0 |
| T-GROWTH-05 | 위킬 후패배/이탈/timeout | delta0/승리기록변화0,activeRun은닫힘 |
| T-SAVE-01 / P8 / R-06 | 정상nil과API load오류를각각주입 | nil만신규생성;오류/미래schema/손상은쓰기0 |
| T-SAVE-02 | 같은Update transform3회호출 | 부작용0,원자 delta1회,반환commit 확인뒤ack1회 |
| T-SAVE-03 | write는성공했으나응답실패,같은run재시도 | closedOrdinal/lastResult로중복효과0,Committed확인 |
| T-SAVE-04 | A lock갱신·B획득·A지연저장,시간이동·정상해제후재획득 | B는미만료lock획득불가,만료/정상해제후새획득epoch증가,stale A write0 |
| T-SAVE-05 | heartbeat실패→lease안전여유30초 | 경기/성장/신규시작중지,expired토큰재사용0 |
| T-SAVE-06 | 오래된request영수증evict후재전송 | expectedRevision으로거부,spend/grant2회없음 |
| T-SAVE-07 | PlayerRemoving/BindToClose동시flush,run취소 | 단일queue,중복write경쟁없음,동일결과1회 |
| T-SAVE-08 | 미완료activeRun으로재접속 | lock확보후Abandoned보상0,run닫힘; 확정진행은복원 |
| T-SAVE-09 실서비스 | test키실저장→Studio재시작/새session load | gold/xp/units/traits/wins/bestTicks동일,불변식통과 |
| T-SAVE-10 실서비스 | Studio2instance에서같은QA key lock경쟁 | simultaneous owner0,stale overwrite0. 정확한realm/key기록 |
| T-SEC-01 / P2,P8,P9 / R-07 | 임의HP/AP/gold/target/X/userId/unknownfield | allowlist거부,상태변화0 |
| T-SEC-02 | NaN/inf/음수/소수slot/긴문자열/중첩table/Instance | 타입·구조·값검사에서거부,예외로서버중단0 |
| T-SEC-03 | 1초1000event, requestId다양화 | bucket·queue상한유지,다른match정상,로그폭증0 |
| T-SEC-04 | 과거seq/다른matchId/종결후/다른플레이어 | 비용/이동/피해/보상변화0,구체거부reason |
| T-ISOLATION / P2,P8 / R-07 | Studio Server&Clients2명,서로다른경기 | A입력/승패/저장이B에영향0,타인profile·snapshot수신0 |

fault store는 실패 전/후 commit, 지연 반환, callback 충돌 재실행, quota0, 조기/늦은 wall clock, lock release실패를 각각 주입한다. 단순 '저장 성공' 한 건으로 세션·경제 무결성 테스트를 대체하지 않는다. 미확정 결과 저장 전 강제 crash는 보상 손실이 가능하다는 명시 한계와 일치해야 하며 무손실 요구로 오판하지 않는다.

## 6. 입력·네트워크·시각 테스트

| ID | 시나리오 | 기대값/증거 |
|---|---|---|
| T-INPUT-01 | A/D·←/→ Begin/End,양쪽동시,keyrepeat | axis-1/1/0, discrete중복0, server/client axis 비교 |
| T-INPUT-02 | 터치이동+소환+스킬2손가락,버튼밖release/Cancel | 홀드독립,stuck0,소환/스킬각1회. 실제touch증거 |
| T-INPUT-03 | 채팅/성장메뉴/창포커스상실,컨트롤숨김 | local axis즉시0,server0.5초내정지,채팅문자처리정상 |
| T-NET-01 | RTT200ms 모의,일시snapshot미수신/옛matchsnapshot | ackp95≤350ms 목표,현재match최신seq만,회복후≤1초동기화 |
| T-NET-02 | snapshot0.5초/1초단절,bootstrap중복 | 상태경고·보간중지,read조회rate제한·inflight1,전투권한서버유지 |
| T-ASSET-01 | Placeholder↔Sprite/Model테스트adapter,애니길이변경 | 동일 seed/commands 서버digest·피해·승패·자원 exact동일 |
| T-ASSET-02 | asset누락/로드실패/긴애니/미승인manifest | fallback,로직불변,미승인은출시build차단 |
| T-DEVICE | 1280×720PC,1920×1080PC,844×390/740×360/390×844 touchlayout | 최소48표적/8간격,safeinset,세로도조작가능,핵심HUD가림0 |

Roblox의 reliable RemoteEvent를 실제 packet 재정렬 transport처럼 거짓 설명하지 않는다. 오래된 snapshot/match 테스트는 controller fixture에서 stale message를 주입하는 검사다. 네트워크 지연 simulation은 Studio의 실제 지원 설정을 확인하고 환경에 기록한다. 기능이 없으면 지연 fixture와 실환경 측정을 별도로 표시한다.

## 7. MCP e2e 실행 runbook (T-E2E)

각 시나리오는 같은 build/balance/seed로 재현한다. 서버 fixture를 빠르게 승리시키는 테스트와 정상 조작으로 스테이지를 깨는 테스트를 분리한다.

### E2E-A: 신규 계정 첫 승리

1. T-TOOL preflight 후 qa profile 신규 상태 load, server에서 L1/units3/자원0/s01만해금 확인.
2. MCP keyboard로 A/D를 눌렀다 떼고 서버 X변화/경계/멈춤 확인, screen capture로 hero/HUD 확인.
3. 실제 simulation 5초 뒤 food/mana≥10 확인(다른소모없음). 키1 또는 GUI 버튼 클릭→vanguard1생성·식량10차감 확인.
4. Q로 pulse 시전→마나10차감·서버탄/피해 확인. 이동키를 유지하며 재시험하여 이동+시전 병행 확인.
5. 소환3종·지원장 위치를 활용해 s01을 정상 플레이로 클리어. 조건을 만족할 때까지 bounded scenario deadline10분. 실패는 seed/commands 재현 기록, fixture 강제승리로 바꿔 PASS하지 않음.
6. server outcome/result와 client화면 일치, Pending→Committed revision 확인. s02해금·gold/xp·firstbonus 검증.
7. 로비 유닛 강화/포인트 분배 후 테스트 세션 종료·재접속, 실제 Store profile 동등성 확인. mock로만 수행하면 E2E-A(Mock)로 이름 구분.

### E2E-B: 종결·저장 장애

server-only fixture로 hero/core 동시lethal을 준비하고 실제 server tick으로 해소→패배 우선. 이후 client 소환·cast spam해 변화0. Store fault로 commit응답실패를 주입→저장대기에서 재전투 차단→같은결과 재시도→중복지급0. player disconnect/새 세션의 Abandoned 경로도 별도 실행.

### E2E-C: 진행·기기·격리

정상 입력으로 s02/s03 승리와 각 스테이지 패배/재도전. 2client 다른 경기 동시 조작. touch Emulator의 GUI 클릭은 1차 기능 확인으로만 기록하고, Android 실기기에서 이동+소환+시전/포커스·터치취소/safe area를 다시 확인한다.

### E2E-D: 발매 tree 점검

production Rojo build를 새 Studio에서 열어 boot. TestSupport·Debug remote·reference원본·미승인asset0, toolchain/balanceHash·catalog일치, 서버/클라이언트오류0. MCP 편집으로 소스와 Studio를 다르게 만든 경우 hash 불일치로 중단한다.

## 8. 부하·관측 시험 (T-PERF)

목표는 PRD §6의 **측정 전 기준**이다.

- 서버: 4독립 경기, 각 ally30/enemy40/hero/core와 탄128. 60초 warm-up 후10분, tick duration p50/p95/p99·catchup drop·GC/메모리·queue·snapshot byte수 수집. p95≤10ms, 정상 cap범위, 무제한 객체/로그증가0.
- 클라이언트: 지정 Android 장치의 모델/OS/RAM/화질/주사율을 고정하고10분; frame p95≤33.3ms 목표. PC p95≤16.7ms. Emulator 성능을 실측 대신 제출하지 않음.
- 100회 경기 생성/종료를 반복해 같은 scene상태로 돌아왔을 때 connection/Instance/queue 수가 기준선으로 복귀하는지 검사. 최종 warm GC 후 메모리 순증가가 계속되는 경우 FAIL.
- remote flood 동안 정상 소유자 입력의 p95 ack와 tick시간을 함께 측정, 저장 budget0에서 queue가 무한 증가하지 않음.
- 결과가 미달이면 신규 프레임워크부터 도입하지 않고 FX/뷰빈도/스냅샷빈도/cap을 조정하고 같은 fixture 회귀. 수치/요구 변경은 정본도 갱신.

## 9. 단계·출시 완료 판정

단계 report는 PASS/FAIL/BLOCKED/NOT_RUN을 구분하고 담당자가 raw evidence를 읽은 뒤 확정한다. reviewer가 구현 author와 다른 검증 관점을 제공한다. 도구 미연결은 BLOCKED이고 테스트 개수0은 PASS가 아니다.

- [ ] P0 T-TOOL + 테스트 실패 감지 + production/test tree 분리
- [ ] P1 T-DATA + provenance/overlay + deterministic generation
- [ ] P2 T-SEC/T-ISOLATION 기본 + DTO/RF 비차단
- [ ] P3 T-RESOURCE/T-COMBAT/T-HERO + simulation replay
- [ ] P4 T-PROJECTILE/T-HERO + cap/중복타격
- [ ] P5 T-INPUT/T-NET/T-ASSET + 실제 PC/기본 touch 기능
- [ ] P6 T-STAGE/T-E2E(Mock) + 종결1회
- [ ] P7 T-GROWTH + 포인트/잔액/첫보상
- [ ] P8 T-SAVE mock+실서비스 + 재접속/소유권 경합
- [ ] P9 T-E2E/T-DEVICE/T-PERF/T-ASSET/T-SEC 전체 + 정적분석/lint/build

**차단 결함**: 임의 클라이언트 피해/골드, 중복정산/구매, stale overwrite, load오류의 기본값덮어쓰기, 다른플레이어데이터노출, 원본에셋출시, production debug grant. 하나라도 재현되면 발매 불가.

이번 문서 작업의 실제 수행 결과는 문서 검증 기록에만 남긴다. 위 checkbox는 구현 후 증거가 생길 때만 체크한다.
