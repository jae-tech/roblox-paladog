# AGENTS.md — 등불 원정 (Roblox / Luau)

Codex·Claude 등 코딩 에이전트용 작업 안내. 상세 근거는 아래 문서가 정본이고, 이 파일은 시작 순서와 지켜야 할 규칙만 둔다.

## 먼저 읽을 것

1. `docs/HANDOFF.md`: 단계별 현재 상태, 실제로 실행한 검증, 남은 일
2. `docs/DEVELOPMENT.md`: 단계별 설계 결정과 알려진 한계
3. 다음 단계 범위: `docs/IMPLEMENTATION_PLAN.md`의 해당 P절, 테스트 기준은 `docs/TEST_PLAN.md`, 수치·타입은 `docs/DATA_MODELS.md`, 처리 순서·권한·저장은 `docs/ARCHITECTURE.md`

## 현재 상태 (2026-10-16)

| 단계 | 상태 |
|---|---|
| P0 도구·빌드·테스트 기반 | full gate PASS (Studio 증거 2026-10-15 12:32Z, P4 빌드) |
| P1 연구 수치 → `mvp-proto-001` 밸런스 | gate PASS (T-DATA + 자동 T-ASSET) |
| P2 원격 프로토콜·세션·프로필 골격 | gate PASS (Luau 132 cases, Studio 2-client 격리) |
| P3 헤드리스 전투 시뮬레이션 | gate PASS (Luau 123 cases, Studio suite + 라이브 경기) |
| P4 탄·영웅 무기 스킬 | gate PASS (Luau 134 cases, Studio 동일 suite + 실제 Remote 시전·이동·피해) |
| P5 입력·뷰·카메라 | PC 입력·장치 화면·renderer·Studio suite PASS. 실기기 멀티터치만 BLOCKED |
| P6 3스테이지·결과 | CLI/Studio T-P6 162 PASS |
| P7 성장·보상 | CLI/Studio T-P7 74 PASS |
| P8 저장·lease | CLI/Studio T-P8 52 PASS, 실 QA DataStore 복원·경합 PASS(2026-10-16, 사용자 승인) |
| P9 통합·보안·부하 | `verify_p9.py` BLOCKED: CLI/Studio P2~P9 회귀·production 출시 빌드 감사·10분 부하·저속 통신·실 DataStore PASS, **Android 실기기 멀티터치는 알려진 제한(출시 전 실기기 확인 필요)** |

**2026-10-16부터 원작 재현 확장(REMAKE) 진행 중**: 사용자 지시로 시스템·수치를 원작과 같게, 외형·이름은 오리지널로 하여 팔라독·다크독 캠페인과 서바이벌 전체를 만든다. 범위·단계(R0~R7)·설계 결정은 `docs/REMAKE_PLAN.md`가 정본이고 MVP 설계 문서보다 우선한다. 원작 데이터는 `python tools/build_remake.py`(`--check`로 diff0 확인)로 `data/remake/db.json`, `src/server/Config/Remake/*`, `src/shared/RemakeCatalog.luau`를 만든다. 이 셋은 생성 파일이라 직접 고치지 않는다. 오리지널 이름·설계값은 `data/remake/design.json`에서 고친다. 원작 캐릭터명(연구 문서 이름, paladog/darkdog 같은 원작 영문명)은 `src/`에 넣지 않는다.

진행 상세와 미해결 사항은 `docs/PROGRESS.md`가 최신이다. HANDOFF 상단에 현재 상태와 출시 전 남은 일을 둔다. 밸런스 overlay 결정 14개는 2026-10-16 "jaetech"가 승인했다. Studio 동기화는 Rojo가 기존 스크립트를 갱신하지 못하는 문제가 있어, `rojo build`로 만든 rbxm을 MCP `import_rbxm`으로 넣고 이름=길이 해시로 일치를 확인한다(저장 안 함).

## 환경과 명령 (macOS arm64 / Windows AMD64 bootstrap)

Windows는 Python만 선행 설치하고 아래 `python3` 대신 `python`을 써도 된다. bootstrap은 같은 고정 버전 Windows 도구를 `.tools/`에 설치하며 전역 PATH·rokit을 바꾸지 않는다. 직접 CLI 실행 시 Windows 실행파일에는 `.exe`를 붙인다. macOS는 기존 rokit 선행 설치를 유지한다. `.gitattributes`의 LF 정책을 유지한다(연구 원문 SHA·생성물 바이트 비교에 필요).

```sh
python3 tools/setup_tools.py               # 호스트별 SHA 고정 도구 설치 (macOS의 rojo/selene/luau-lsp는 rokit)
python3 tools/verify_p0.py --local-only    # 분석·lint·format·build·production 격리 (PASS 기대)
python3 tools/verify_p1.py                 # 데이터 golden·재생성 diff0·T-ASSET
.tools/luau-0.742/luau tests/cli_r1.luau   # REMAKE 전투 코어
.tools/luau-0.742/luau tests/cli_r2.luau   # REMAKE 모드·보스
.tools/luau-0.742/luau tests/cli_r3.luau   # REMAKE 성장·서버 흐름·공격 매트릭스·생명주기
.tools/luau-0.742/luau tests/cli_r6.luau   # REMAKE 서바이벌 웨이브·보석·해금 이벤트·정산
.tools/luau-0.742/luau tests/cli_p2.luau   # 프로토콜 v2 허용목록·격리·세션·lease (P2 이식)
.tools/luau-0.742/luau tests/cli_p8.luau   # 저장 어댑터·lease·장애 주입 (P8 이식)
python3 tools/build_remake.py --check      # 원작 데이터·퀘스트 재생성 diff0
python3 tools/release_audit.py             # production 출시 빌드 감사
python3 -m unittest discover -s tools/tests
.tools/stylua-2.6.0/stylua src tests test-support test-support-client   # 커밋 전 포맷
```

종료 코드는 0=PASS, 1=FAIL, 2=BLOCKED. BLOCKED를 PASS로 바꾸거나 보고하지 않는다.

## 테스트 정책 (2026-10-16, 토큰 최소화)

P0~P9 순서(`IMPLEMENTATION_PLAN.md`)는 그대로다. 위 명령 전체는 매 변경이 아니라 P9 전체 회귀에서 돌린다.

- 구현 중에는 바뀐 기능의 핵심 단위 suite(`tests/cli_pN.luau`)와 정적 분석(analyze·selene·StyLua·build)만 돌린다.
- 이미 PASS한 기능은 관련 코드가 바뀌지 않았으면 다시 검증하지 않는다.
- Studio MCP 테스트는 P0·P5·P6·P8·P9에서만 한다. P1~P4·P7은 로컬 테스트·정적 분석 우선. 실제 Studio 확인이 필요한 오류가 생기면 예외로 한다.
- 같은 실패는 원인 분석 후 최대 2회만 수정하고, 그래도 안 되면 FAIL/BLOCKED로 기록하고 넘어간다.
- 생략 금지: 저장 데이터 무결성, 서버 권한, 보상 중복 지급 테스트.
- 실행하지 않은 항목은 PASS로 쓰지 않는다(NOT_RUN).
- 전체 회귀·부하 테스트는 P9에서 한다.
- 다중 에이전트 리뷰·상세 테스트 보고서는 생략한다. 단계 완료 시 `docs/PROGRESS.md`에 구현 내용·핵심 테스트 결과·미해결 문제만 짧게 적는다.

## 코드 규칙

- 모든 Luau는 `--!strict`, 탭 들여쓰기, StyLua(열 100)와 selene 통과. 순수 모듈은 CLI `luau-analyze`, Roblox 모듈은 luau-lsp(Roblox 모드)로 검사된다.
- **require 경계**: 같은 트리 안에서는 `require("./X")`·`require("../X")`(CLI와 Studio 모두 동작 확인). `src/server` → `src/shared`는 한 경로로 쓸 수 없다(Studio는 `.luaurc` alias를 무시하고, CLI는 symlink를 따라가지 않음). 그래서 shared 모듈(`Protocol`, `PublicCatalog`)은 server core에 **주입**한다. Roblox API(Instance 등)는 `Net/RemoteBinding.luau`처럼 별도 모듈로 분리해 순수 core가 CLI에서 돌게 한다.
- 시뮬레이션(`src/server/Simulation/*`)은 Instance·Heartbeat·시계·애니 없이 정수 tick만 쓴다. `World.PHASES` 순서를 바꾸지 않는다. 결정론은 `World.digest`로 검사된다.
- 테스트 suite(`tests/unit/P*.luau`)는 모듈을 주입받는 함수다. CLI(`tests/cli_p*.luau`)와 Studio(`test-support/ServerHarness.luau`의 `runSuite`)가 같은 suite를 돌린다. 새 단계 suite도 이 형식을 따른다.
- Python 도구는 표준 라이브러리만 쓴다.

## 하지 말 것

- **생성 파일을 직접 고치지 않는다**: `data/reference/*`, `data/normalized/*`, `data/balance/*`, `src/server/Config/Generated/*`, `src/shared/PublicCatalog.luau`. 수치는 `data/overlay/mvp-proto-001.json`(결정 ID·이유 필수, `approvedBy`는 실제 승인 전까지 null)을 고친 뒤 `python3 tools/build_balance.py --version mvp-proto-001`로 재생성한다. 표현 계약은 `DESIGN.md`, 추가 코드 생성 도형도 `data/assets/asset-manifest.json`에 기록한다.
- 연구 원문 `docs/paladog-*.md` 7개와 설계 문서 6개를 수정하지 않는다(SHA 고정).
- 셸 작업 디렉터리를 `src/`·`tests/`·`test-support*/`·`artifacts/` 안으로 옮기지 않는다. 에이전트 훅이 작업 디렉터리에 상태 파일을 만들면 Rojo가 Studio로 동기화하고 T-ASSET 검사가 실패한다.
- 사용자 승인 없이 하지 않는다: `git push`, 실제 DataStore 접근, Studio API access 토글, place publish, 에셋 업로드·구매, `TestPolicy.luau` allowlist 변경. 테스트 universe는 사용자가 승인한 `10771015944`뿐이다.
- 테스트를 약하게 만들어 통과시키지 않는다. 실패하면 원인을 고치거나 BLOCKED/FAIL로 보고한다.

## Studio 검증 (Roblox Studio MCP가 있는 환경만)

gate는 Studio를 직접 구동하지 못하고, MCP로 수집한 증거 JSON을 검증한다. 증거에는 test 빌드의 스크립트 바이트 길이가 들어 있어 **코드가 바뀌면 이전 증거로는 FAIL**이 정상이다.

1. `rojo serve test.project.json --port 34872`를 띄우고, 승인된 테스트 universe의 place에서 Rojo 플러그인 Connect를 누른다(사람이 해야 함). 저장하거나 publish하지 않는다.
2. 2-client multiplayer playtest에서 (`Script.Source` 바이트 길이는 runtime VM에서 읽을 수 없으니 edit 피어 `execute_luau`로 수집) `ServerHarness.runSuite`(`T-TOOL`, `T-TOOL-INTENTIONAL-FAIL`, `T-P2`, `T-P3`, `T-P4`, `T-P5`)와 `startNetRig()`/`ClientHarness`로 시나리오를 실행한다. P5는 `ClientHarness.runSuite('T-P5',12345)`도 실행한다. 형식은 `artifacts/P*/studio/`의 기존 증거와 `docs/HANDOFF.md`를 따른다.
3. `verify_p0.py --studio-evidence`, `verify_p2.py --isolation-evidence`, `verify_p3.py --studio-evidence`, `verify_p4.py --studio-evidence`, `verify_p5.py --studio-evidence`로 검증한다. P4/P5는 raw Studio suite의 seed·전체 assertion을 최신 CLI와 비교한다. `artifacts/`는 gitignore 대상이라 증거가 원격에는 없다. 화면 캡처 실패나 실제 touch 도구 부재를 mock PASS로 바꾸지 않는다.

MCP가 없으면 Studio 단계는 하지 말고 BLOCKED로 남긴 뒤 HANDOFF에 적는다.

## 작업 흐름

- 단계마다 브랜치(`p4-...`)에서 커밋하고 로컬 `main`에 fast-forward 병합한다. push는 사용자가 한다.
- 단계를 마치면 `docs/PROGRESS.md`에 구현·핵심 테스트 결과·미해결 문제만 간결하게 기록한다(위 테스트 정책). 실행하지 않은 검증을 완료로 쓰지 않는다.
- 사용자와는 한국어로 소통한다.
