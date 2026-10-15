# AGENTS.md — 등불 원정 (Roblox / Luau)

Codex·Claude 등 코딩 에이전트용 작업 안내. 상세 근거는 아래 문서가 정본이고, 이 파일은 시작 순서와 지켜야 할 규칙만 둔다.

## 먼저 읽을 것

1. `docs/HANDOFF.md`: 단계별 현재 상태, 실제로 실행한 검증, 남은 일
2. `docs/DEVELOPMENT.md`: 단계별(P1~P3) 설계 결정과 알려진 한계
3. 다음 단계 범위: `docs/IMPLEMENTATION_PLAN.md`의 해당 P절, 테스트 기준은 `docs/TEST_PLAN.md`, 수치·타입은 `docs/DATA_MODELS.md`, 처리 순서·권한·저장은 `docs/ARCHITECTURE.md`

## 현재 상태 (2026-10-15)

| 단계 | 상태 |
|---|---|
| P0 도구·빌드·테스트 기반 | full gate PASS (Studio 증거 2026-10-15 12:19Z, P3 빌드) |
| P1 연구 수치 → `mvp-proto-001` 밸런스 | gate PASS (T-DATA + 자동 T-ASSET) |
| P2 원격 프로토콜·세션·프로필 골격 | gate PASS (Luau 132 cases, Studio 2-client 격리) |
| P3 헤드리스 전투 시뮬레이션 | gate PASS (Luau 123 cases, Studio suite + 라이브 경기) |
| **다음: P4 탄·영웅 무기 스킬** | 미착수. `Simulation/World.luau`의 `projectileRequests`(tick별 원거리 발사 요청)와 Cast(`NotReady` 반환)가 연결 지점 |

## 환경과 명령 (macOS arm64 전용 bootstrap)

```sh
python3 tools/setup_tools.py               # .tools/에 고정 버전 Luau/StyLua/타입 정의 설치 (rokit: rojo/selene/luau-lsp)
python3 tools/verify_p0.py --local-only    # 분석·lint·format·build·production 격리 (PASS 기대)
python3 tools/verify_p1.py                 # 데이터 golden·재생성 diff0·T-ASSET
.tools/luau-0.742/luau tests/cli_p2.luau   # P2 suite
.tools/luau-0.742/luau tests/cli_p3.luau   # P3 suite
python3 tools/verify_p2.py                 # Studio 증거 없으면 exit 2(BLOCKED)가 정상
python3 tools/verify_p3.py                 # 동일
python3 -m unittest discover -s tools/tests
.tools/stylua-2.6.0/stylua src tests test-support test-support-client   # 커밋 전 포맷
```

변경 후 위 명령을 모두 다시 돌린다. 종료 코드는 0=PASS, 1=FAIL, 2=BLOCKED. BLOCKED를 PASS로 바꾸거나 보고하지 않는다.

## 코드 규칙

- 모든 Luau는 `--!strict`, 탭 들여쓰기, StyLua(열 100)와 selene 통과. 순수 모듈은 CLI `luau-analyze`, Roblox 모듈은 luau-lsp(Roblox 모드)로 검사된다.
- **require 경계**: 같은 트리 안에서는 `require("./X")`·`require("../X")`(CLI와 Studio 모두 동작 확인). `src/server` → `src/shared`는 한 경로로 쓸 수 없다(Studio는 `.luaurc` alias를 무시하고, CLI는 symlink를 따라가지 않음). 그래서 shared 모듈(`Protocol`, `PublicCatalog`)은 server core에 **주입**한다. Roblox API(Instance 등)는 `Net/RemoteBinding.luau`처럼 별도 모듈로 분리해 순수 core가 CLI에서 돌게 한다.
- 시뮬레이션(`src/server/Simulation/*`)은 Instance·Heartbeat·시계·애니 없이 정수 tick만 쓴다. `World.PHASES` 순서를 바꾸지 않는다. 결정론은 `World.digest`로 검사된다.
- 테스트 suite(`tests/unit/P*.luau`)는 모듈을 주입받는 함수다. CLI(`tests/cli_p*.luau`)와 Studio(`test-support/ServerHarness.luau`의 `runSuite`)가 같은 suite를 돌린다. 새 단계 suite도 이 형식을 따른다.
- Python 도구는 표준 라이브러리만 쓴다.

## 하지 말 것

- **생성 파일을 직접 고치지 않는다**: `data/reference/*`, `data/normalized/*`, `data/balance/*`, `src/server/Config/Generated/*`, `src/shared/PublicCatalog.luau`. 수치는 `data/overlay/mvp-proto-001.json`(결정 ID·이유 필수, `approvedBy`는 실제 승인 전까지 null)을 고친 뒤 `python3 tools/build_balance.py --version mvp-proto-001`로 재생성한다.
- 연구 원문 `docs/paladog-*.md` 7개와 설계 문서 6개를 수정하지 않는다(SHA 고정).
- 셸 작업 디렉터리를 `src/`·`tests/`·`test-support*/`·`artifacts/` 안으로 옮기지 않는다. 에이전트 훅이 작업 디렉터리에 상태 파일을 만들면 Rojo가 Studio로 동기화하고 T-ASSET 검사가 실패한다.
- 사용자 승인 없이 하지 않는다: `git push`, 실제 DataStore 접근, Studio API access 토글, place publish, 에셋 업로드·구매, `TestPolicy.luau` allowlist 변경. 테스트 universe는 사용자가 승인한 `10771015944`뿐이다.
- 테스트를 약하게 만들어 통과시키지 않는다. 실패하면 원인을 고치거나 BLOCKED/FAIL로 보고한다.

## Studio 검증 (Roblox Studio MCP가 있는 환경만)

gate는 Studio를 직접 구동하지 못하고, MCP로 수집한 증거 JSON을 검증한다. 증거에는 test 빌드의 스크립트 바이트 길이가 들어 있어 **코드가 바뀌면 이전 증거로는 FAIL**이 정상이다.

1. `rojo serve test.project.json --port 34872`를 띄우고, 승인된 테스트 universe의 place에서 Rojo 플러그인 Connect를 누른다(사람이 해야 함). 저장하거나 publish하지 않는다.
2. 2-client multiplayer playtest에서 (`Script.Source` 바이트 길이는 runtime VM에서 읽을 수 없으니 edit 피어 `execute_luau`로 수집) `ServerHarness.runSuite`(`T-TOOL`, `T-TOOL-INTENTIONAL-FAIL`, `T-P2`, `T-P3`)와 `startNetRig()`/`ClientHarness`로 시나리오를 실행한다. 형식은 `artifacts/P*/studio/`의 기존 증거와 `docs/HANDOFF.md`를 따른다.
3. `verify_p0.py --studio-evidence`, `verify_p2.py --isolation-evidence`, `verify_p3.py --studio-evidence`로 검증한다. `artifacts/`는 gitignore 대상이라 증거가 원격에는 없다.

MCP가 없으면 Studio 단계는 하지 말고 BLOCKED로 남긴 뒤 HANDOFF에 적는다.

## 작업 흐름

- 단계마다 브랜치(`p4-...`)에서 커밋하고 로컬 `main`에 fast-forward 병합한다. push는 사용자가 한다.
- 단계를 마치면 `docs/HANDOFF.md`(상태·검증·남은 일)와 `docs/DEVELOPMENT.md`(결정·한계)를 갱신한다. 실행하지 않은 검증을 완료로 쓰지 않는다.
- 사용자와는 한국어로 소통한다.
