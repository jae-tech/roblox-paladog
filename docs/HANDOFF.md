# 개발 인수인계

## 현재 상태 (2026-10-17)

### 최신: 맵·용병·몬스터 디자인 (브랜치 r11-world-figures, D-FIG-01)

- 용병·토템·몬스터·보스 48종과 세트 피스를 이름에 맞게 새로 디자인하고(관절 애니메이션), 5개 챕터 던전을 테마별 지형·장식·조명으로 만들었다. 상세는 `docs/PROGRESS.md` 마지막 절.
- 로컬 검사 PASS, Studio에서 전 종·전 챕터 화면과 실제 출전 전투를 확인. 실기기 프레임은 NOT_RUN.

### 이전: 장비가 아바타에 보이게 (브랜치 r10-avatar-gear, D-GEAR-01)

- 아이템 82종 외형을 코드 도형으로 디자인했고, 장착하면 서버가 실제 로블록스 캐릭터에 붙인다(무기 손·등·허리, 반지·부적, 투구, 갑옷, 장화, 군마는 옆 동행, 강화 발광). 로비 장비 화면에 착용 미리보기. 상세는 `docs/PROGRESS.md` 마지막 절.
- 로컬 검사 PASS, Studio에서 구매→장착→아바타 반영과 던전 안 표시를 확인. 2인 시점과 탈것 탑승 자세는 하지 않았다.

### 이전: UI/UX 다듬기 (브랜치 r9-ui-polish)

- 전투 HUD 카드형 버튼(비용·단축키·AUTO·쿨타임 막), 영웅·목표 패널, 모달 애니메이션, 사라지는 토스트, 로비 헤더 칩·스테이지 칸·구매 가능 표시, 광장 리더보드 표·안내 카드. 상세는 `docs/PROGRESS.md` 마지막 절.
- 로컬 검사 PASS, Studio에서 PC·iPhone 13 가로 화면으로 광장·로비·전투·결과·리더보드를 실제 입력으로 확인하고 찾은 문제 10건을 고쳤다. 레벨업·부활 창 화면과 실기기 터치는 NOT_RUN.

### 이전: 버튼별 오토 + R8 광장·아바타 전투

- 소환/무기 버튼(키)을 누를 때마다 그 칸 오토가 켜지고 꺼진다(D-AUTO-01, 클라이언트가 같은 명령을 보냄, 보상 그대로).
- 접속 시 로블록스 아바타로 광장에 나오고, 던전 입구(E)로 원정 메뉴를 열며, 경기가 시작되면 실제 캐릭터가 던전 아레나로 이동해 로블록스 조작·카메라로 싸운다(서버 영웅이 캐릭터를 따라가고 이탈 시 되돌림). 리더보드는 서버 단위(leaderstats + 게시판). 상세는 `docs/PROGRESS.md` 마지막 두 절.
- `verify_r7.py` 로컬 항목 전부 PASS(R8 포함). studio 항목은 이 변경 전 증거라 재캡처 필요. 2인 동시 접속 확인은 아직 안 했다.

### 이전: R7 통합 검증 (브랜치 r7-integration)

- `python3 tools/verify_r7.py --studio-evidence artifacts/R7/studio/r7-studio-evidence.json`은 **BLOCKED(exit 2)**. CLI 10개 suite·P0 local·diff0·출시 감사·Python·Studio(suite 해시 동일·10분 4경기 부하 p95 11.9ms·실제 입력 플레이 3종)·실 QA DataStore v2(사용자 승인, 저장·복원·lease 경합·옛 토큰 거절·정리)는 PASS. 남은 BLOCKED: Android 실기기 멀티터치(알려진 제한).
- 사용자 조치: 실 DataStore 검증이 끝났으니 테스트 universe의 "Studio API 서비스 액세스"는 다시 꺼도 된다. 출시 전 남은 일: Android 실기기 터치, 에셋 시각·라이선스 검토, 출시 universe에서 `PersistencePolicy` 활성화(승인 필요), place publish.
- 휴대폰 로비 잘림을 고쳤다(912×544 기준 UIScale). 상세·미해결은 `docs/PROGRESS.md` 마지막 절.
- Studio 실제 입력 팁: 클릭 좌표 = GUI AbsolutePosition + 상단 inset(58). Studio 창이 포커스를 잃으면 입력 라우터가 막히니 `osascript -e 'tell application "RobloxStudio" to activate'`로 활성화한다. 결과는 eval 사이에 사라질 수 있어 ServerStorage StringValue에 남긴다.

### 이전: R6 서바이벌 구현 + 3D 실제 플레이 재검증 (브랜치 r6-survival)

- 3D 동행 전투 화면/물리 입력 검증은 **PASS로 해소**: 원인은 macOS 화면 잠금(displaysleep 2분)이었다. 실제 W/D/Q·GUI 소환·교전·자연 패배·결과·로비 복귀 확인. 숫자 키와 일시정지 버튼은 MCP 입력 오류로 NOT_RUN.
- R6 서바이벌: 전투·서버 입장/정산·로비/HUD/결과 구현. CLI R6 118 + 기존 회귀 전부 PASS, Studio T-R6/T-R3가 CLI와 assertion 해시 동일, 실제 GUI로 입장·웨이브 HUD·해금 이벤트·해금 반영 확인(일부 상태는 메모리 fixture). 상세·미해결은 `docs/PROGRESS.md` 마지막 절.
- 다음: R7 통합 검증(전체 회귀·부하·실 저장 v2·실기기). 서바이벌 EXP×27의 잦은 레벨업 일시정지는 원작대로 유지(2026-10-16 사용자 결정).

### 최신: 3D 동행 전투 전환 — 구현/엔진 검증 완료, 화면 플레이 BLOCKED

- 최신 사용자 요구는 **식량으로 용병 소환 + 3D 영웅 직접 이동/마나 마법 + 함께 전진/전투**다. `docs/3D_PLAN.md`가 2D 화면 재현보다 우선한다. R6보다 먼저 이 조작감을 확인한다.
- 구현: Workspace 3D 던전/영웅/용병/적/탄, 후방 추적 카메라, WASD 두 축 이동, Q/E/R·좌클릭 마법, 1~9 소환·터치 4방향 버튼. 서버 X/Z 거리/탄/오오라·AI 추적·영웅 근처 소환. Roblox 기본 아바타 물리 대신 서버 snapshot으로 움직이는 자체 모델이다. 카메라 회전/자유 탐험/협동은 이번 범위 아님.
- 검증: CLI T-3D **57**, R1 112/R2 77/R3 167/R4 106/R5 532/P2 133/P8 51 PASS(권한·저장 무결성·중복 정산 포함). P0 local(타입/lint/format/build/Python82), 생성 diff0, 출시 감사 PASS. 로컬 증거 `artifacts/3D/`, P0 `20261016T064326416793Z`.
- Studio 승인 universe에서 소스 **85개 길이 일치**, 서버 T-3D 57·클라이언트 R4 106은 CLI ordered assertion과 동일. 3D 모델52종/탄/좌표/카메라/cleanup 엔진 smoke **17 PASS**. 실제 Remote 전송(물리 키 입력 아님)으로 X/Z 100/0→121.213/21.213, 식량40→30, 마나100→90, 용병/마법 각1회, 표적 HP1000→760 관측. 자원·정지 표적은 서버 메모리 fixture다.
- **화면/물리 WASD·GUI 클릭 검증 BLOCKED**: Studio native viewport·리본/Explorer가 흰 화면이고 RenderStepped가 진행하지 않았다. 창 복원·위치 복구·새 프로세스에서도 MCP가 `no frame`으로 캡처를 거부했다. 원인 미확정이며 제품 플레이 PASS로 기록하지 않는다. 정상 그래픽 환경에서 `docs/3D_PLAN.md` §검증의 실제 출전→동행 전투→결과/로비를 재개해야 한다. 화면 상태를 우회한 모듈 호출은 실제 플레이 증거가 아니다.
- 플레이테스트 종료, 원래 poor 통신(양방향150ms/지터100ms/손실0.5%)과 장치 시뮬레이터 해제 상태 복원. 실 DataStore/API 설정·publish·업로드·구매 없음. 에셋 placeholder/Android 멀티터치/v2 실 저장/3D 특수 모드 전체 QA는 미완료. R6 서바이벌은 계속 stage0 WrongMode.

### 이전 REMAKE 인계: R5 로컬 검증 완료 (아래 최신 3D 전환 이전 기록)

- R0~R4 커밋을 이어받아 R5 암영 영웅 캠페인을 연결했다. 토템 9종(외침·가시·변신), 검 11종, 장비·스킬 24개·크리/회피·적 디버프 오오라, 교체 스테이지 21개, 던전 함정, 공성 목마, 오리지널 점프 코스 10개와 클라이언트 입력/HUD/표시를 구현했다.
- CLI: R5 **532 PASS**, R1 112 / R2 77 / R3 167 / R4 63 / P2 133 / P8 51 PASS. 서버 권한·저장 무결성·보상 중복 방지 포함. P0 local(타입·lint·format·production/test build·Python), 재생성 diff0, 출시 감사 PASS.
- **Studio R4/R5 실제 플레이·실 DataStore v2·실기기 터치는 이번 작업에서 NOT_RUN**. 아래 MVP Studio 증거는 REMAKE 완료 증거가 아니다. 점프 맵/장애물·러너 속도·코인 높이, 검 애니·독 구름 수명 등 연구에 없는 값은 `data/remake/design.json`의 결정 ID로 명시했다. 에셋은 계속 placeholder다.
- 다음 구현: `docs/REMAKE_PLAN.md` **R6 서바이벌**. stage 0은 아직 `WrongMode`; 30웨이브+반복 스케일·보스 젬·부활·암영 영웅 해금 이벤트를 구현한다. 이후 R7에서 전체 회귀·Studio 실제 플레이·저장·부하 검증이 필요하다.

### 이전 MVP 출시 상태 (역사 기록)

P0~P9 구현과 검증을 마쳤다. `python tools/verify_p9.py --studio-evidence artifacts/P9/studio/p9-studio-evidence.json`은 **BLOCKED(exit 2)**다. CLI P2~P9, Studio suite 해시, production 출시 빌드 감사, 실 QA DataStore, 10분 부하, 저속 통신(poor 프로필)은 PASS다. **Android 실기기 멀티터치(device-touch)만 알려진 제한으로 BLOCKED**다. 단계별 결과는 `docs/PROGRESS.md`, 출시 증거 묶음은 `artifacts/P9/{acceptance,security,performance,asset-audit}.json`·`review.md`(gitignore)에 있다.

출시 전 남은 일(사용자 승인 필요):

1. Android 실기기에서 이동+소환+시전 동시 터치, 버튼 밖 release/취소, safe area를 확인한다.
2. `PersistencePolicy`는 `enabled = false`이고 QA universe로 고정돼 있다. 출시 universe에서 켜지 않으면 진행이 저장되지 않는다.
3. 에셋은 모두 코드 생성 placeholder다. 시각·라이선스 검토는 사람이 한다.
4. place publish와 API 서비스 액세스 설정은 사용자가 한다.

Studio 동기화: Rojo 플러그인이 기존 스크립트를 갱신하지 못한다. `rojo build`로 하위 트리별 rbxm을 만들어 MCP `import_rbxm`으로 넣고, 이름=길이로 sourcemap과 맞춘다(저장 안 함). rbxm import는 `ReplicatedStorage`의 `StageGameplay` 속성을 넣지 않는다. 직접 `true`로 설정하지 않으면 클라이언트가 스테이지 모드로 뜨지 않는다.

아래는 P5 체크포인트까지의 기록이다(역사 기록, 최신 아님).


## Studio 실행 검증 (2026-10-15)

| 항목 | 결과 |
|---|---|
| 환경 | Studio 0.743.0.7431133, `robloxstudio` MCP, `studio_id instance:ffj-1ij`, GameId `10771015944`(사용자 승인 테스트 universe), PlaceId `86482422738722` |
| 동기화 | `rojo serve test.project.json` → Rojo plugin Connect. 저장·publish 안 함 |
| 빌드 일치 | test marker, 스크립트 43개 바이트 길이 = 로컬 sourcemap(edit 피어에서 읽음. runtime VM은 `Source`를 읽지 못함) |
| boot | server/client `BootReady`, marker `lantern-p0-foundation-v1`, 캐릭터 nil, Environment 비어 있음 |
| ServerHarness | `T-TOOL` PASS(10 cases), `T-TOOL-INTENTIONAL-FAIL` FAIL(`intentional-failure`만), 미지원 suite 거부 |
| ClientHarness | `inspectBoot` 성공 |
| guard 음성 대조 | GameId 0 place(`instance:l96-gww`)에서 server/client harness 모두 universe 미승인으로 거부. **1052Z 수집분을 이월**: 사용자가 별도 미게시 place를 열어야 해서 재실행하지 않았다. Guard·TestPolicy·ClientHarness는 그때와 바이트 동일, ServerHarness는 바뀜(4479→5093) |
| production 격리 | 빌드 XML 정적 audit PASS. Studio 런타임 require 실패는 WAIVED |

증거: `artifacts/P0/studio/20261015T1219Z-harness.json`(P3 빌드에서 2-client 플레이테스트로 재수집, multiplayerGroup `48b43ba4-…`; 이전 증거는 소스 길이 불일치로 FAIL하는 것이 정상). `artifacts/`는 gitignore 대상이라 **이 증거는 원격에 없다**; 다른 checkout에서는 위 절차로 Studio 증거를 새로 수집해야 PASS를 재현할 수 있다. 증거 JSON은 MCP 출력을 옮겨 적은 자기 기록(서명 없음)이며 소스 일치는 바이트 길이 비교다. gate report의 `openTasks`에 P0.1이 남는다. 조작 증거(GameId 0, 빈 player 목록, 개별 case FAIL 등)는 FAIL exit 1.

## 실제 실행한 검증

| 명령 / 확인 | 결과 |
|---|---|
| `python3 tools/setup_tools.py` | 고정된 로컬 도구 준비 성공 |
| `python3 tools/verify_p0.py --local-only` | PASS: Luau assertions 23개, Python tests 8개, 순수/Roblox 타입 분석, lint, format, production/test 실제 Rojo build |
| 위 gate의 의도적 assertion 실패 / 타입 오류 negative control | JSON FAIL + nonzero / 분석 nonzero를 실제 확인 |
| `python3 tools/verify_p0.py` | **exit 2 / BLOCKED**: Studio runtime 미검증을 PASS로 처리하지 않음 |
| fresh local clone + 정확한 미커밋 P0 소스 snapshot overlay + 공유 pinned tool cache | 로컬 gate PASS. **커밋된 clean checkout 재현이나 Studio 테스트가 아님** |
| `git diff --check` | PASS |

최종 구현 검증 당시 로컬 증거:

- 로컬 PASS: `artifacts/P0/20261015T090127197407Z/report.json`
- 전체 BLOCKED: `artifacts/P0/20261015T090131371308Z/report.json`
- snapshot 재현: `artifacts/P0/snapshot-reproduction/`

각 실행 디렉터리에 raw logs, JSON reports, toolchain/environment, 실제 `.rbxlx` 빌드, MCP 기록, boot 상태, P0 task cards가 있다. 이 경로들은 **로컬에서만 존재하는 무시 파일**이다. `artifacts/`, `.omx/`, `.tools/`는 Git 원격에 포함하지 않는다. 다른 checkout에서는 아래 명령으로 로컬 증거를 새로 생성해야 한다. 이 인수인계 문서는 실행한 결과의 요약이지 raw evidence의 원격 제공을 뜻하지 않는다.

## (이전) Studio/MCP 차단점 — 해소됨

설치된 Studio는 `0.742.0.7421053`, StudioMCP는 `1.0.0 (efc7c57)`로 확인했으나 설치와 연결 성공은 다르다. 당시 native Roblox MCP 도구는 없었고 직접 stdio handshake의 `tools/list`는 도구 준비 timeout 뒤 `tools: []`를 반환했다. 선택한 `studio_id`는 없다.

실제 Studio server/client boot, Studio runner 정상/의도적 실패, production에서 TestSupport require 실패는 **NOT_RUN**이다. CLI/build 통과로 대체하지 않는다. full gate는 아직 Studio runtime 자동 실행을 구현하지 않았으므로 실제 증거 없이 P0 완료를 선언할 수 없다.

## macOS ARM64 재현

현재 도구 bootstrap은 계획의 Windows가 아닌 **macOS ARM64만 지원**한다. Python3, curl, rokit 1.2.0이 선행 조건이다.

```sh
python3 tools/setup_tools.py
python3 tools/verify_p0.py --local-only
python3 tools/verify_p0.py  # 현재 runtime 미검증은 exit 2
```

고정 버전: Rojo 7.7.1, selene 0.32.0, luau-lsp 1.70.1 (`rokit.toml`), Luau CLI 0.742, StyLua 2.6.0, 고정 Roblox 타입 정의 (`tools/toolchain-lock.json`, URL/SHA256 포함). 설치는 `.tools/`와 기존 rokit 도구 사용 범위다. Python 외부 패키지/테스트 패키지를 추가하지 않았다. 자세한 정책은 [DEVELOPMENT](DEVELOPMENT.md)를 읽는다.

clean checkout 재현: commit `dea9708`을 새로 clone해 도구 설치부터 local PASS, full gate PASS/P0Complete=true 확인.

## P1 데이터 파이프라인 (2026-10-15)

- `tools/balance_lib.py` + CLI 3개(`import_reference`, `build_balance`, `validate_data`) + `tools/verify_p1.py`. 표준 라이브러리만 사용.
- 산출: hero1/ally3/enemy3/stage3/level15, 참조 레벨행 60, 기록 389개(confirmed 349 / unused 39 / conflicted 1), quarantine 1(id____ 99879).
- `tools/tests/test_p1.py` 33개 PASS: T-DATA-01~08, DATA_MODELS §3 전체 수치 독립 golden, 리뷰 회귀(스키마·범위·catalog·중복·빈 칸), T-ASSET. 별도로 규칙을 수동으로 깨 보는 mutation 실행(N5/N6 alias, 기본 HP 미사용)에서 테스트가 실패하는 것을 확인했다(저장소에서 자동 재현되지는 않음).
- 의도적 차이(diff.md): 강화비 ×0.1, 영웅 hitRadius 5→1.5. 나머지 신규값은 overlay 결정 ID로 추적.
- Studio(테스트 universe) spot check: 생성 모듈 6개 require 성공, vanguard L1 maxHp와 balanceHash 일치, 중첩 freeze 쓰기 거부. 증거 JSON의 `generatedConfigInStudio`에 자기 기록했으며 gate가 검증하는 항목은 아니다.
- T-ASSET: 자동 검사만(manifest 커버리지·금지 파일). 7개 presentation 모두 `placeholder`이고 asset ID·승인자는 비어 있다. 시각·라이선스 검토는 미실시.
- 남은 판단: overlay 결정의 실제 승인(`approvedBy`)은 비어 있다. 밸런스는 플레이 검증 전 기준선이다.

## P2 권한·DTO·세션·프로필 골격 (2026-10-15)

- 원격 입력 검증(`Protocol`), 게이트웨이(토큰 버킷·대기열·no-yield bootstrap), MatchService(소유권·phase·seq/ack·이동 TTL), ProfileService(StoreAdapter 계약·영수증·fenced lease), InMemory 어댑터. production Bootstrap에는 아직 연결하지 않음(저장소 P8, 시뮬레이션 P3).
- Luau P2 suite 132개 PASS(CLI와 Studio 서버 VM 동일). 리뷰에서 나온 lease 경쟁(늦은 release가 새 세션 lease 삭제), stale writer 후 Preparing 고착, run 식별 미검증, 남은 activeRun 영구 차단, 손상 문서 선기록 등을 고치고 각각 회귀 테스트를 추가했다. 규칙을 수동으로 깨 보는 mutation 실행(허용 필드·소유권·영수증·fence·중복 join)에서 테스트가 실패하는 것을 확인했다(저장소에서 자동 재현되지는 않음).
- Studio 2-client(테스트 universe, 실제 RemoteEvent, Mock store): 타인 경기 명령 `NotOwner`, 임의 hp 필드·Instance·NaN `InvalidPayload`, 피해자 대기열·이동축·revision 불변, 각자 자기 snapshot만 수신, 1000건 flood에서 20건만 수용·980건 무응답 집계·다른 플레이어 정상. 증거 `artifacts/P2/studio/20261015T1219Z-isolation.json`(P3 빌드에서 재수집: T-P2 132 PASS, 980건 RateLimited 무응답, 20건 NotOwner, 피해자 명령 Pending→Accepted), gate `tools/verify_p2.py`.
- 설계 대비 변경: reason에 `InsufficientGold` 추가. server→shared require는 주입으로 해결(Studio alias·CLI symlink 불가를 실측).

## P3 헤드리스 시뮬레이션 (2026-10-15)

- `src/server/Simulation/*` 8개 모듈 + MatchService 연결. Luau P3 suite 123개 PASS(CLI), seed 재현(600tick 체크포인트 6개 동일), tick 순서 증거는 `tools/verify_p3.py`가 생성한다.
- 리뷰 반영: 실패할 수 없던 테스트 3개 수정(죽은 표적 → 발사 hit 0 확인, breach 1회 재배치 → 추적·순간이동 금지 확인), MatchService `stepAll` 통합 테스트와 실제 TTL로 T-HERO-01, 행동 기반 tick 순서 테스트, 프레임 1초 급증 시 4tick·피해 상한 추가. 원거리 요청 목록은 tick마다 비움, 피해식 정수화, digest에 facing·maxHp·공격력·처치수·재생률 포함.
- 수동 mutation 확인(저장소에서 자동 재현되지 않음): 지원장 배율, 공격 주기, breach 처리, 사망 1회 guard, 매 tick 재배치를 각각 깨면 테스트가 실패한다.
- **Studio 검증 (2026-10-15 12:19Z, 2-client 플레이테스트)**: Studio 서버 VM에서 T-P3 123/123 PASS. `startNetRig` 라이브 경기에서 client-1 Summon `Accepted`, 식량 40000→30700 차감, vanguard x 1.2(tick 423)→10.5(tick 485) `Advancing`, snapshot 키에 `attackPower` 없음, rig 전후 workspace 자손 수 8→8(렌더 인스턴스 생성 0). 증거 `artifacts/P3/studio/20261015T1219Z-studio.json`, `verify_p3.py --studio-evidence` PASS. 증거 JSON은 MCP 출력을 옮겨 적은 자기 기록이다.

## P4 투사체·영웅 스킬 (2026-10-15)

- `ProjectileSystem`은 아군/적/pulse 탄을 서버 수치로 생성한다. 이전X→새X swept 충돌, 접촉 거리→동률 ID 순서, 진영·레인·생존 필터, 중복 타격 방지, pierce/TTL/거리/맵 경계를 처리한다. 발사 후 owner 사망에도 탄은 유지되고 피해는 근접과 같은 batch에 들어간다.
- `HeroActionSystem`은 이동과 독립인 windup/recovery를 관리한다. mana10000·쿨30tick·탄 cap128 예약을 원자 처리하고, 시전+4tick에 이동 후 hero.x에서 +X로 피해100 탄을 발사한다. 취소/빗나감은 환급 없고 사망·종결 즉시 예약을 해제한다. 자동 원거리 공격은 예약 슬롯을 빼앗지 못한다.
- `World.PHASES`는 유지했다. 새 탄은 다음 tick부터 이동하며, 마지막 TTL tick의 잘린 segment까지 판정 후 제거한다. 시전 release와 같은 tick에 영웅이 lethal 피해를 받으면 batch 전 발사까지 성립하지만 종결 후 추가 피해는 없다. 탄/시전/스킬 쿨과 hit ID를 digest에 포함했다.
- snapshot에는 복사된 탄 궤적·시전 타이밍·스킬 쿨만 추가했다. `damage`·`attackPower`·`hitEntityIds`·예약 여부는 비공개다. 생성 밸런스·13개 연구/설계 정본·TestPolicy는 수정하지 않았다.
- **독립 회귀 suite 134개 PASS(CLI/Studio 동일)**: sweep·접촉 순서·pierce·TTL·cap128·예약 경쟁, 이동/마나/쿨 경계, 자동 아군/적 발사, owner 사망, 표적 이탈, release tick lethal, 탄+근접 동시 사망/오버킬 보상1회, 중복 Cast·spoof 무효, DTO 분리·digest 재현. 독립 코드 리뷰 지적(Studio assertion identity 비교 부족)은 fresh CLI seed와 전체 순서별 assertion exact 비교 및 Python 음성 대조로 수정했다.
- **Studio 실제 Remote 검증**: universe `10771015944`, Studio `0.743.0.7431133`, 2client. 서버 fixture로 마나/정지 표적만 준비하고 ClientHarness의 실제 `FireServer`로 Cast·이동 keepalive를 전송했다. Heartbeat로 tick1958 수락/마나10000→0, tick1962 발사, tick1968 표적HP130→30, 영웅X10→13.3, `workspace.DescendantAdded` 생성0을 확인했다. 직접 fast-forward/화면 marker는 사용하지 않았다. playtest·rig·관측 연결은 종료했다.
- P2 재검증: 각자 자신의 snapshot만 수신(1442/1443건, foreign0). 외부 경기 Cast `NotOwner`, hp/Instance/NaN `InvalidPayload`, 피해자 revision1/axis0/pending0. 1000건 flood에서20건 응답·980건 무응답 rate drop, 다른 client 명령 Pending→Accepted. 첫9건 flood ID가 짧아 InvalidPayload, 다음11건 NotOwner였음을 raw에 기록했다.
- P3 재검증: 실제 Summon Accepted·food40000→30000·아군X0.15→77.7, workspace 자손8→8. 이 P3 지표는 기존과 같은 **순증가량**이고, P4는 별도의 실제 생성 이벤트 카운터를 썼다. 첫 P4 시도의 순증가량 -1은 관계없는 Studio 자손 제거 때문에 부적합하여, raw를 남기고 생성 이벤트 관측으로 재실행했다.

증거/보고서(모두 로컬 gitignore 대상):

| 항목 | 경로 / 결과 |
|---|---|
| raw MCP 입력·출력, Studio evidence 4종 | `artifacts/P4/studio/20261015T123227Z/` |
| P4 full gate | `artifacts/P4/20261015T123618836662Z/report.json` PASS |
| P0 full gate | `artifacts/P0/20261015T123619191107Z/report.json` PASS / P0Complete=true |
| P2 full gate | `artifacts/P2/20261015T123618953367Z/report.json` PASS |
| P3 full gate | `artifacts/P3/20261015T123619043957Z/report.json` PASS |
| P1 generation/data/asset gate | `artifacts/P1/20261015T122954439204Z/report.json` PASS |
| 독립 verifier 재실행 | `artifacts/P4/20261015T123652111038Z/report.json` PASS / 커밋 차단 이슈0 |

전체 Python 도구 테스트73개, 순수/Roblox 타입 분석, selene, StyLua, production/test 빌드, production 격리도 통과했다. P4의 실제 키/GUI 입력·표현 검증은 P5 범위로 미실시다.

P0의 GameId0 guard 음성 대조는 **1052Z 결과를 이월**했다. Guard/TestPolicy/ClientHarness는 그대로이고 바뀐 ServerHarness를 GameId0에서 다시 실행한 것은 아니다. production runtime require의 WAIVED도 새 승인이 아니라 기존 승인 이월이다. 소스 일치 검사는 서명/전체 해시가 아닌 스크립트47개의 바이트 길이 비교다. P4 로컬 environment에는 별도 SHA256 sourceHash와 balanceHash가 있다. 무시 파일은 원격에서 복원되지 않으므로 다른 checkout은 증거 재수집이 필요하다.

## P5 체크포인트 (2026-10-15, 완료 아님)

- `DESIGN.md`에 오리지널 산업적 등불 원정 표현·반응형·접근성·검증 경계를 정리했다. 아군/영웅/적7종과 핵/탄/지면5종은 code-built placeholder이며 manifest12개 모두 assetId/승인자 null이다. 생성 밸런스·13개 정본·TestPolicy는 바꾸지 않았다.
- `Input/ActionRouter`는 입력 객체별 hold, 양방향 중립, key repeat 차단, 0.1초 keepalive, focus/text/menu/숨김 취소를 처리한다. `DeviceAdapter`는 CAS + GuiButton의 movement hold / discrete Activated 경로만 연결하고 End/Cancel과 외부 release도 정리한다.
- `Net/SnapshotBuffer`/`ClientController`는 현재 match/seq/balance 검증, 완전 snapshot 제거, 보간·0.15초 예측·ack 재적용·경계/종결 snap, 단일 in-flight bootstrap과 지연/재동기화를 담당한다. 자원/HP는 예측으로 바꾸지 않는다.
- 서버 snapshot에 안전한 bounds/heroSpeed/자원 상한/잠정 보상과 `commandAckSeq`를 추가했다. 후자는 명령 ingress high-watermark이며 최종 비용 수락 ack의 대체가 아니다. 재연결한 클라이언트는 두 seq를 서버 high-watermark 이상으로 복구한다.
- `Presentation/**`는 safe inset·48px/8px 조작부·세로/좁은 가로 대응, 한국어 HUD/로비·메뉴, Client-only 물리 비활성 도형, renderer 교체/fallback 수명과 오류 진단, Scriptable camera 복원을 구현한다. `Runtime`/client bootstrap은 기존 server remote에만 연결하고 production debug/Mock remote는 만들지 않는다.
- 독립 테스트: 입력31 + 네트워크163 + 뷰419 = **613 PASS**. 독립 리뷰의 재연결 seq 초기화, 늦은 bootstrap/StartStage 승인에 의한 terminal 역행, 시작 ack 누락 후 Preparing 고착, renderer 예외 은폐/부분 생성 누수, 좁은 가로 버튼 겹침을 수정하고 회귀를 추가했다. 순수 finite 검사의 HP NaN/마나∞/previousX NaN 결함도 회귀로 고쳤다.
- 승인 universe `10771015944`, Studio `0.743.0.7431133`의 2-client 실행에서 서버·클라이언트 각각 동일613개 PASS를 확인했다. P0 정상10/의도적 실패1, P2 132, P3 123, P4 134도 서버 suite PASS다. 실제 gameplay 키/GUI 조작은 아직 실행하지 않았다.
- Studio screenshot은 `EditableImage` texture 로드 실패와 host capture60초 timeout으로 실패했고 OS `screencapture`도 실패했다. Security/API/OS 설정은 바꾸지 않았다. MCP에는 실제 독립 multi-touch injection이 없어 Android/touch 검증도 BLOCKED다. screenshot/에뮬레이터·순수 fixture를 실제 입력 PASS로 대체하지 않았다.
- raw/부분 증거: `artifacts/P5/studio/20261015T125703Z/`의 `edit-meta-final.json`, `studio-suites-final.json`, `client-suite-final.json`, `screenshot-failure.json`, `p5-partial.json`. 첫 exploratory609개 실행은 추가 ack 회귀 수정 전이므로 final613개 결과로 대체했다. 실행한 rig/2-client playtest는 종료했다. 이 파일들은 gitignore이며 원격에 없다.
- 커밋 직전 재검증: P0 local `artifacts/P0/20261015T130301851163Z/report.json` PASS, P1 `artifacts/P1/20261015T130306888928Z/report.json` PASS, P5 `artifacts/P5/20261015T130308027697Z/report.json` **BLOCKED(exit2)** — unit/input/network/view/Studio suite PASS, pcInput/device/render/touch BLOCKED. Python86개·타입/lint/format/build·diff 검사 PASS. 독립 reviewer는 남은 late StartStage HIGH 수정과 네트워크163개 PASS를 확인하여 **체크포인트 커밋만 승인**했고 full P5 승인은 하지 않았다.

## Windows 재개 체크포인트 (2026-10-16 KST / 2026-10-15 22:12Z)

- `p5-windows-verification`에서 P5 남은 검증을 재개했다. 이번 세션 도구 목록에는 Roblox/Studio MCP가 없으며 과거 `artifacts/`도 이 checkout에는 없었다. Studio 실행·키/GUI·화면·renderer·touch는 **NOT_RUN/BLOCKED**다. 설치 여부로 연결 성공을 추정하거나 다른 경로로 Studio 권한을 우회하지 않았다.
- 최초 `setup_tools.py`는 macOS 전용으로 BLOCKED였다. Python suite도 `core.autocrlf=true`에 의한 고정 원문 SHA 불일치로 실패했다. `.gitattributes` LF 정책과 기존 Git blob 바이트 복원으로 해결했고 원문 SHA·생성값·검사 기준은 변경하지 않았다.
- Windows AMD64용 같은 고정 버전 공식 ZIP/SHA와 명시적 `.exe` 경로, UTF-8 파일/프로세스 경계를 추가했다. Windows는 `.tools/`만 사용하고 전역 PATH·도구 설치나 새 Python 패키지는 없다. macOS 기존 pin/rokit 경로는 보존했지만 macOS 재실행 검증은 하지 않았다.
- 도구/checkout 회귀10개를 추가해 Python **96개 PASS**. P2/P3/P4/P5 CLI는 **132/123/134/613개 PASS**(P5 입력31/네트워크163/뷰419). 순수/Roblox 타입 분석·두 analyzer 음성 대조·selene·StyLua·production/test build·production 정적 격리 PASS. `.exe` StyLua 실제 포맷 후 Luau 내용 diff0이다.
- 네이티브 researcher/reviewer 위임도 시도했으나 설치된 역할 모델이 계정에서 미지원으로 시작 실패했다. 독립 리뷰 완료로 기록하지 않고 단독 검토와 실제 gate로 검증했다.

| 명령 | 결과 / 새 로컬 증거 |
|---|---|
| `python tools/setup_tools.py` | PASS, 실제 다운로드와 host별 SHA 일치 / 재실행 캐시 검증 PASS |
| `python tools/verify_p0.py --local-only` | PASS(exit0), `artifacts/P0/20261015T221157047911Z/report.json` |
| `python tools/verify_p0.py` | BLOCKED(exit2), `artifacts/P0/20261015T221208229252Z/report.json`, Studio 미실행 |
| `python tools/verify_p1.py` | PASS(exit0), `artifacts/P1/20261015T221217406150Z/report.json`, 원문 SHA·생성물 byte diff0·T-ASSET |
| `python tools/verify_p2.py` | CLI132 PASS / full BLOCKED(exit2), `artifacts/P2/20261015T221219757756Z/report.json` |
| `python tools/verify_p3.py` | CLI123·seed replay·tick 순서 PASS / full BLOCKED(exit2), `artifacts/P3/20261015T221220157640Z/report.json` |
| `python tools/verify_p4.py` | CLI134 PASS / full BLOCKED(exit2), `artifacts/P4/20261015T221220642840Z/report.json` |
| `python tools/verify_p5.py` | CLI613 PASS / full BLOCKED(exit2), `artifacts/P5/20261015T221221289985Z/report.json` |
| `python -m unittest discover -s tools/tests` | 96개 PASS |

위 증거는 현재 Windows checkout의 무시 파일이며 원격에 포함되지 않는다. 이전 macOS Studio 증거를 재사용한 것이 아니다. P5 full gate 전에는 P6로 진행하지 않는다.

**커밋된 clean checkout 재현**: `e48f7b2`를 `git clone --no-hardlinks --config core.autocrlf=true --branch p5-windows-verification`으로 `.tools/windows-reproduction/`에 새로 복제했다. SHA 고정 다운로드 캐시만 복사하고 bootstrap으로 실행파일을 다시 추출했다. 원문7개 SHA 일치, P0 local PASS(`artifacts/P0/20261015T221319853335Z/report.json`), P1 PASS(`artifacts/P1/20261015T221330421003Z/report.json`), P5 CLI613 PASS/full BLOCKED(`artifacts/P5/20261015T221333404814Z/report.json`), 검증 후 `git status --short` 빈 출력을 확인했다. 이 세 증거 경로는 재현 checkout 내부 기준이다. 새 네트워크 다운로드·Studio·macOS 재현을 뜻하지 않으며 P0 report의 자동 `cleanCheckoutReproduction` 필드는 여전히 NOT_RUN이다.

## Windows Studio 재검증 (2026-10-16 KST / 22:20Z~22:47Z)

- 설치와 연결을 구분해 실제 `@chrrxs/robloxstudio-mcp` 3.2.1 도구·연결을 확인했다. 승인 GameId `10771015944`, PlaceId `86482422738722`, Studio `0.743.0.7431133`. edit 피어에서 수집한 스크립트72개의 바이트 길이가 로컬 sourcemap과 전부 일치했고 최종 edit 재수집도 동일했다. 코드·생성물·TestPolicy는 변경하지 않았다.
- **2-client suite**: server T-TOOL10 PASS, 의도적 실패는 `intentional-failure`1건만 FAIL, 미지원 suite 거부, P2/P3/P4/P5는132/123/134/613 PASS. client-1 P5도613 PASS이며 gate가 fresh CLI seed12345와 전체 ordered assertion을 비교했다. boot marker·캐릭터 nil·Mock rig 종료도 관측했다. P0 guard GameId0와 P2/P3/P4 full scenario 재수집은 아직 아니다.
- **화면/장치 PASS**: solo 실제 Running HUD를 1280×720, 1920×1080, 844×390, 740×360, 390×844에서 PNG로 캡처했다. 이 검증의 경기 시작은 서버 Mock fixture + 정상 client bootstrap 재연결이며 실제 입력 증거로 세지 않는다. `ActualResolution`과 `GuiService:GetInsetArea(None/CoreUISafeInsets)` 원시값을 기록해 notch·상단 inset 및 안전 영역 상대 버튼 좌표를 검증했다. portrait·48px/8px 조건도 gate PASS다. iPhone portrait의 resolution 인수는 preset 기본 가로 순서844×390으로 전달해야 실제390×844가 된다. 앞선 잘못된 방향/scale 시도는 raw로 남기고 최종5종만 사용했다.
- **renderer PASS**: 실제 client VM에서 EntityView Placeholder→등록된 Model fixture→Placeholder 교체, 미등록 Sprite fallback, 부분 생성 후 오류를 내는 adapter fallback, 비어 있는 snapshot 뒤 자손0을 확인했다. CameraController는 Scriptable 적용 뒤 type/subject/CFrame/Focus/FOV/mode 전부 복원했다. 별도 서버 World fixture는 step하지 않고 같은 snapshot만 사용했으며 digest `e093cbce`→`e093cbce`다. 고품질 Model/Sprite 에셋이나 live 경기 tick 진행의 검증을 뜻하지 않는다.
- **PC 실제 입력 PASS**: 실제 GUI 시작 클릭으로 Running/snapshot 수신을 확인했다. 최종 입력 시나리오는 Mock Running fixture + 정상 client bootstrap 뒤 실제 D/Q press/release와 GUI 클릭을 썼다. D hold 동안 서버 영웅X10→14.8·axis1·client held1을 관측했고, releaseX18.4→stopped18.4→추가 대기18.4로 정지했다. Q는 commandSeq1, Pending→Accepted와 마나10000→0, GUI Summon은 별도 requestId의 Pending→Accepted와 식량40000→30000이다. 비용 측정 중 서버 Mock World 재생률만0으로 고정했다. 실제 OS foreground를 Studio→영속 VS Code 창으로 전환한 UTC1792104371076ms부터 서버 Heartbeat가 axis0을 관측한1792104371153ms까지 **77ms**다. 초기 Q tap/짧은 hold·focus 실패 raw도 보존했다. foreground 전환 뒤 focus 이벤트가 안정되길 기다리고, 이미 사라진 임시 콘솔 HWND가 아닌 VS Code HWND66992를 쓰는 최종 절차로 해소했다. 제품 코드는 바꾸지 않았다.
- **환경 경계**: place가 반복 재열리며 instance id가 바뀌었다. 사용자는 Rojo 연결 팝업만 승인했고 검증 계속을 요청했다. 소유한 Rojo serve를 중지한 뒤에도 재열림을 관측했으므로 Rojo 탓으로 단정하지 않는다. multiplayer 임시 client의 screenshot/device matrix는 MCP가 명시적으로 지원하지 않아 solo로 대체했고 solo CaptureService 캡처는 성공했다. 독립 touch injection은 도구에 없어 touch BLOCKED다.
- 최종 renderer/device/PC playtest는 직접 stop했고 각 rig와 focus 관측 연결을 종료했다. device simulator는 reset했다. 최종 연결 목록은 edit만 남고 multiplayer group0이다. 소유한 Rojo 서버도 종료했다. 저장/publish·실제 DataStore·API/security toggle·allowlist 변경은 하지 않았다.

원시/부분 증거(모두 gitignore): `artifacts/P5/studio/20261015T222057Z-windows/`. `server-suites{,-raw}.json`, `client-suite.json`, `edit-meta.json`, `final-edit-meta.json`, `render-engine.json`, `render-digest.json`, `device-final-observations.json`, `device-final-{0..4}-1.png`, `pc-attempt-trace.json`, `pc-final-attempt-trace.json`, `p5-partial.json`을 보존했다. 최종 gate `artifacts/P5/20261015T224658673634Z/report.json`은 **BLOCKED(exit2)**: CLI/input/network/view/Studio suite/pcInput/device/render PASS, touch만 BLOCKED다. 과거 macOS 증거를 재사용하지 않았다.

최신 로컬 재검증: P0 local `artifacts/P0/20261015T224343489427Z/report.json` PASS, P1 `artifacts/P1/20261015T224354286360Z/report.json` PASS, Python96 PASS, 타입/lint/format/build/production 정적 격리 PASS. P2/P3/P4 gate는 CLI132/123/134 PASS지만 full scenario 증거를 전달하지 않아 BLOCKED다. 독립 touch injection 도구는 없고 공식 VirtualInput 문서도 touch pointer ID 입력을 제공하지 않는다. mouse나 simulator의 pinch를 멀티터치로 대체하지 않는다.

## 승인 경계

실제 DataStore 작업, Studio API access 토글, 에셋 업로드, 공개 publish, 운영 데이터 변경은 매번 사용자 승인이 필요하다. 2026-10-16 QA DataStore 검증 승인은 그 검증에만 해당한다.
