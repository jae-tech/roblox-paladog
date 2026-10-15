# P0 개발 및 검증

## 현재 상태

P0 로컬 기반 구현 + Studio runtime 검증(2026-10-15, 테스트 universe 10771015944). full gate는 `--studio-evidence`로 PASS/P0Complete=true다. production Studio 내 TestSupport require 실패는 런타임 미실행이며 사용자 결정으로 정적 XML audit으로 대체(WAIVED)했다. P0.1(Git 정책)은 BLOCKED로 남는다. P1~P9는 시작하지 않는다. 기존 설계 6개는 기준선이며 REA Markdown 7개는 수정하지 않는다. `tools/reference-hashes.json`으로 원본 보존을 검사한다. P0는 밸런스를 생성하지 않아 balanceHash/schema/protocol은 null이다.

실행 호스트는 계획의 Windows가 아니라 **macOS Darwin ARM64**다. 이 호스트용 로컬 도구 다운로드만 고정했다. Windows 지원/테스트를 주장하지 않는다. Git 기준선은 `f36bf2a`, origin/main과 동일한 이력이며 확인한 원격은 README의 공개 저장소다. 현재 main의 로컬 미커밋 변경으로 작업하며 팀 branch 합의는 없다. 제안 정책: 후속 변경은 `implementation/p0-foundation` 같은 로컬 feature branch, 소스/문서/도구만 커밋; `.omx/`, `artifacts/`, `.tools/`, 연구 바이너리와 키는 제외. 이번 작업은 commit/push/publish하지 않는다.

## 새 checkout 재현 (macOS ARM64)

Python3, curl, rokit 1.2.0이 선행 도구다. Python 표준 라이브러리 외 패키지를 추가하지 않는다.

```sh
python3 tools/setup_tools.py
python3 tools/verify_p0.py --local-only  # 로컬 검사만; P0 완료를 뜻하지 않음
python3 tools/verify_p0.py --studio-evidence artifacts/P0/studio/<file>.json  # 증거 없으면 exit 2/BLOCKED
```

`rokit.toml`: Rojo7.7.1, selene0.32.0, luau-lsp1.70.1. `tools/toolchain-lock.json`: Luau0.742, StyLua2.6.0, 고정 Roblox 타입 정의 다운로드 URL/SHA256. 설치 위치는 무시되는 `.tools/`뿐이다. LSP 내장 Luau는 CLI0.742와 다른 버전(c0e346edd89066b44dca174c9f54ce84c746a540)이므로 두 분석을 분리한다. 캐시/도구 누락은 BLOCKED, 검사 오류는 FAIL; 조용히 skip하지 않는다. Luau/LSP `--formatter=plain`은 오류에도 exit0인 버전 특성이 있어 사용하지 않는다. 의도적 타입 오류의 nonzero도 매번 검사한다.

2026-10-15 commit `dea9708`(branch `p0-foundation`)을 새로 clone해 `setup_tools.py`로 도구를 처음부터 받은 뒤 `--local-only` PASS, `--studio-evidence` PASS/P0Complete=true를 재현했다(gate 자체의 `cleanCheckoutReproduction` 필드는 자동 판별하지 않아 NOT_RUN으로 남는다). 이전 기록: 별도로 로컬 fresh clone + 미커밋 P0 소스 snapshot overlay + 공유 pinned tool cache로 로컬 gate PASS를 검증했고 `artifacts/P0/snapshot-reproduction/`에 로그/보고서를 남겼다. 이는 실제 Studio 테스트나 커밋된 checkout 검증을 대신하지 않는다.

실행별 `artifacts/P0/<UTC runId>/`에 report/toolchain/environment, CLI JSON/raw log, 분석/lint/format/build 로그와 `production.rbxlx`, `test.rbxlx`를 남긴다. CLI intentional failure는 JSON FAIL + process exit1이 **기대 동작**이며 상위 gate는 이 둘을 확인한다. 종료코드0=해당 scope 검증 통과, 1=FAIL, 2=BLOCKED. 테스트 개수0은 실패다. gate는 Studio를 직접 구동하지 못한다. MCP로 수집한 `p0-studio-evidence/1` JSON을 `--studio-evidence`로 넘기면 TestPolicy allowlist(GameId≠0), sourcemap 기준 소스 바이트 길이 일치, server/client boot marker, 캐릭터 미생성, `ServerHarness` 정상 PASS·의도적 FAIL·미지원 suite 거부, client oracle을 검사한다. 하나라도 어긋나면 FAIL(exit1)이다.

## production / test 경계

- `default.project.json`: Shared/GameServer/GameClient와 직접 만든 빈 Environment만. 테스트 모듈·fixture·Remote endpoint가 없다.
- `test.project.json`: 같은 소스 + TestSupport와 명시 `P0TestBuild` marker. 외부 에셋/스크립트는 없다.
- `Players.CharacterAutoLoads=false`를 프로젝트와 서버 bootstrap에 명시. boot script는 realm별 marker를 기록할 뿐 플레이 가능한 게임은 아니다.
- 빌드 XML에서 test 노드/의존성과 Remote endpoint0을 검사한다. Studio production place 안의 TestSupport require 실패 런타임 확인은 2026-10-15 사용자 결정으로 이 정적 audit으로 대체(WAIVED)했다.
- fake Clock/RNG와 `Mock/InMemory` numeric store는 P0 fixture일 뿐이다. P2 lease/revision/store 계약이나 Roblox MemoryStore/DataStore 구현이 아니다.

## Studio/MCP T-TOOL 재개

실제 발견한 MCP 도구/schema만 사용한다. 2026-10-15 `robloxstudio` MCP(get_connected_instances, execute_luau, solo_playtest, eval_server_runtime, eval_client_runtime, get_runtime_logs)로 검증했다. 절차: `rojo serve test.project.json` → 테스트 universe place에서 Rojo plugin Connect(저장·publish 안 함) → GameId/marker/소스 확인 → solo play → ServerHarness.runSuite(T-TOOL, T-TOOL-INTENTIONAL-FAIL)·ClientHarness.inspectBoot → 시작한 playtest 종료 → 증거 JSON 작성. 설치된 Studio와 MCP 연결을 구분한다. 다른 Studio 창/운영 place를 조작하지 않는다. 실제 test build를 연 뒤 발견한 명시 studio_id를 선택하고 build marker와 build hash를 확인한다.

`test-support/TestPolicy.luau` allowlist에는 사용자가 승인한 테스트 universe `10771015944`만 있다. **승인된 테스트 universe만** 명시 추가한다. 로컬 unpublished GameId0을 자동 허용하지 않는다. 허용 universe 확보를 위해 자동 publish하지 않는다. Studio + test marker + allowlist 3개 조건을 ServerHarness가 검사하고 client oracle은 server authorization marker도 요구한다. 어느 것도 저장/보상 remote를 노출하지 않는다.

Server realm에서 승인/guard 통과 후:

```luau
local h = require(game.ServerScriptService.TestSupport.ServerHarness)
local report = h.runSuite("T-TOOL", 12345)
return game:GetService("HttpService"):JSONEncode(report)
```

`T-TOOL-INTENTIONAL-FAIL`도 실행하여 JSON FAIL 전달을 확인한다. 이어 실제 Server bootstrap BootReady, CharacterAutoLoads=false, 캐릭터 자동 생성0과 client `PlayerScripts.GameClient.Bootstrap` BootReady를 확인한다. client TestSupport.ClientHarness.inspectBoot는 조회 전용 oracle이다. raw server/client output과 결과를 저장하고 본인이 시작한 play 세션만 종료한다. 아직 P2 scenario/loadScenario/getReport/inspectMatch나 client gameplay suite는 구현하지 않았다.

## 권한 경계

실제 DataStore 접근, Studio API access toggle, 자산 upload/구매, 공개 배포, 운영 데이터 변경은 별도 승인 없이 금지한다. 이 P0 소스에는 DataStore 호출/서비스나 디버그 보상 endpoint가 없다. 로컬 build/test는 배포가 아니다.

## 공식 도구 근거

- [Rojo 프로젝트](https://rojo.space/docs/v7/project-format/), [build](https://rojo.space/docs/v7/getting-started/new-game/#building-your-place)
- [Luau0.742](https://github.com/luau-lang/luau/releases/tag/0.742), [StyLua2.6.0](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0)
- [luau-lsp1.70.1](https://github.com/JohnnyMorganz/luau-lsp/releases/tag/1.70.1)
- [Studio MCP](https://create.roblox.com/docs/studio/mcp), [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes)
