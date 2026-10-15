# P0 개발 및 검증

## 현재 상태

P1 데이터 파이프라인 구현(`tools/verify_p1.py`: T-DATA + 자동 T-ASSET 검사 PASS; 시각·라이선스 검토는 수동이며 미실시). P0 로컬 기반 구현 + Studio runtime 검증(2026-10-15, 테스트 universe 10771015944). full gate는 `--studio-evidence`로 PASS/P0Complete=true다. production Studio 내 TestSupport require 실패는 런타임 미실행이며 사용자 결정으로 정적 XML audit으로 대체(WAIVED)했다. P0.1(팀 합의 Git 정책)은 BLOCKED로 남는다. P4~P9는 시작하지 않는다. 기존 설계 6개는 기준선이며 REA Markdown 7개는 수정하지 않는다. `tools/reference-hashes.json`으로 원본 보존을 검사한다. P0 gate 보고서의 balanceHash/schema/protocol은 null이다(밸런스 hash는 P1 산출물 `data/balance/mvp-proto-001.json`에 있다).

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

## P1 데이터 파이프라인 (T-DATA)

```sh
python3 tools/import_reference.py --source docs --manifest data/reference/manifest.json
python3 tools/build_balance.py --version mvp-proto-001
python3 tools/validate_data.py --strict
python3 tools/verify_p1.py   # golden + --check + validate + 재생성 diff0 → artifacts/P1/<runId>/
```

- 입력: `tools/reference-hashes.json`으로 고정한 REA 7개. 해시가 바뀌면 import가 실패한다(검토 전 자동 승격 금지). 표는 문서+절 경로+정확한 헤더 서명으로 찾고, 열 개수·헤더 변경·필수 빈 칸은 실패, `\|`는 셀 내부 파이프로 처리한다.
- MVP allowlist만 반입: A2 #1~3, A4 id____ 10/11/17, A13 N1~3(참조 레벨행 60), A14 #0~2(연구용 의미 모델만), A1 #0/#255, A6 #4/#353, E03 §3.1/§5.1, E04 §1-3/§6. 중복 id____(99879)는 quarantine.
- 기록 상태: confirmed/inferred/conflicted/unused. 현재 allowlist에는 [추정] 태그 값이 없어 importer는 evidenceLevel을 모두 DocumentConfirmed로 기록한다(inferred는 아직 생성되지 않는다; [추정] 값을 반입하려면 태그 파싱을 먼저 추가한다). production은 confirmed 참조나 overlay 결정만 사용한다. U01(음식 메이스)은 conflicted로 남고, iCrRwd/iCrSec/#353/iTgDst/iCLine/기본행 HP·AP는 unused다.
- 신규 결정은 `data/overlay/mvp-proto-001.json`에만 둔다(`approvedBy`는 실제 승인 전 null). 참조값을 바꾸는 overlay는 `data/balance/mvp-proto-001.diff.md`에 필드 단위로 나온다.
- 생성물(직접 수정 금지): `data/reference/*`, `data/normalized/reference.json`, `data/balance/mvp-proto-001.{json,provenance.json,diff.md}`, `src/server/Config/Generated/*.luau`, `src/shared/PublicCatalog.luau`. Luau는 고정 StyLua로 포맷하며 모든 table은 `table.freeze`된다.
- 검증: 닫힌 필드 집합(DATA_MODELS §2/§5 타입, 누락·미지정 필드 FAIL), 모든 tick/HP/속도 >0, 참조 무결성, 가중치 합100, provenance 양방향 일치, PublicCatalog 텍스트 필드 allowlist(특성 설명 수치는 밸런스에서 생성), overlay 같은 필드 중복 지정 금지, 관리 디렉터리의 orphan 파일 FAIL. T-ASSET 자동 검사는 `data/assets/asset-manifest.json` 커버리지·asset ID/승인 허위 기재 금지·release tree는 `.luau`만·금지 확장자0이다.
- 증거 위치는 IMPLEMENTATION_PLAN의 `artifacts/P1/<runId>/`를 따른다(ASSET_PIPELINE §2의 `artifacts/data/` 표기와 다름).
- `src/`가 바뀌면 P0 Studio 증거의 소스 길이가 달라져 full gate가 FAIL한다. 이때 Studio 증거를 다시 수집한다.

## P2 권한·DTO·세션·프로필 골격 (T-SEC 기본 / T-ISOLATION)

```sh
.tools/luau-0.742/luau tests/cli_p2.luau          # P2 suite (Luau CLI)
python3 tools/verify_p2.py --isolation-evidence artifacts/P2/studio/<file>.json   # 증거 없으면 exit 2
```

- 모듈: `src/shared/{Types,Protocol}.luau`, `src/server/ServerTypes.luau`, `src/server/Net/{TokenBucket,RemoteGateway,RemoteBinding}.luau`, `src/server/Services/{ProfileSchema,ProfileService,MatchService}.luau`. 순수 core는 CLI와 Studio에서 같은 코드로 테스트한다.
- require 경계: 같은 트리 안은 `./`·`../` 문자열 require(Studio 0.743과 CLI 모두 확인). server→shared는 DataModel 경로가 달라 한 경로로 쓸 수 없고(Studio는 `.luaurc` alias 미지원, CLI는 symlink 미추적을 확인) 구성 함수에서 주입한다.
- `Protocol.validateCommand`: kind별 허용 필드만, 키 8개 상한, 값은 문자열/수만, 정수·유한·범위·ID 집합 검사. `InsufficientGold` reason을 추가했다(설계 enum에 골드 부족이 없음).
- 게이트웨이: 토큰 버킷(명령 10/s·20, 이동 20/s·30, bootstrap 1/s·2), 플레이어별 대기열 32, 버킷 초과는 응답 없이 집계만. GetBootstrap은 메모리만 읽고 yield하지 않는다.
- MatchService: 소유자당 경기 1개·서버 4개, phase 검사, commandSeq high-watermark + 최근 128 ack 캐시, 이동 seq·TTL 10tick, 소유자에게만 snapshot.
- ProfileService: StoreAdapter 계약(loadAndLock/update/release), 사용자별 직렬 큐, expectedRevision·최근 64 영수증, 반환 문서의 영수증으로 commit 확인. 오류≠신규 계정, 손상·미래 schema는 덮어쓰지 않음, stale writer는 SessionLost.
- **production Bootstrap은 아직 게이트웨이를 켜지 않는다**: 실제 저장소(P8)와 시뮬레이션(P3)이 없다. Studio T-ISOLATION은 test 빌드 전용 `ServerHarness.startNetRig()`(Mock/InMemory store, 같은 guard)로 실행한다.
- 세션 안전: 같은 플레이어 중복 join은 무시. lease 해제는 sessionId+fenceEpoch가 맞을 때만, 진행 중 write가 끝난 뒤에만 실행. stale writer는 대기 중 작업까지 모두 `SessionLost`로 끝내고 경기 phase를 `Unavailable`로 바꾼다. 손상·미래 schema 문서는 load 단계에서 잠그거나 쓰지 않는다. 남은 activeRun은 재접속 load 때 `Abandoned`(보상0)로 닫는다. StartStage는 반환 문서의 activeRun.startOperationId가 요청과 같을 때만 Running.
- 저장 예산: expectedRevision 불일치는 메모리에서 바로 거부, 프로필별 대기 작업 4개 상한(`Busy`).
- 의도적 선택: 버킷 초과 명령은 응답 없이 버리고 집계만 한다(flood 증폭 방지). 클라이언트는 응답 대기 3초 후 표시를 멈춘다(ARCH §6.1).
- 범위 밖/알려진 한계: Summon/Cast는 대기열에 `Pending`으로만 쌓인다(P3가 처리). 정산·Settled 진입·T-SEC-04 '종결 후' 입력은 P7/P8. lease heartbeat가 아직 없어 Mock rig에서 180초 뒤 write가 `SessionLost`가 된다(P8). 응답 유실 뒤 메모리 profile은 다음 commit까지 이전 값이며, 같은 requestId 재시도는 변경 없는 문서를 한 번 더 쓴다(P8 DataStore 어댑터에서 재검토).
- 증거: `verify_p2.py`는 Studio 기록의 스크립트 바이트 길이가 현재 test 빌드와 같아야 PASS한다(코드가 바뀌면 다시 수집).

## P3 헤드리스 시뮬레이션 (T-RESOURCE / T-COMBAT / T-HERO-01)

```sh
.tools/luau-0.742/luau tests/cli_p3.luau        # P3 suite (Luau CLI)
python3 tools/verify_p3.py --studio-evidence artifacts/P3/studio/<file>.json   # 증거 없으면 exit 2
```

- 모듈: `src/server/Simulation/{SimTypes,Resource,Targeting,Movement,Attack,Damage,World,FixedStep}.luau`. Instance·Heartbeat·애니·시계 없이 정수 tick으로만 진행한다.
- 한 tick 순서(`World.PHASES`): regen → commands → spawn → move → support → target → attack → damage → outcome → cleanup. 처리 이후 같은 tick 안의 다음 단계가 앞 단계 결과를 쓰는지(이동→타깃, 이동→지원장→공격)를 행동 테스트로 확인한다.
- 자원은 milli·tick당 `n=rate+remainder; plus=n//20`, 상한에서 remainder=0. 소환은 쿨다운→식량→아군 30 상한 순으로 검사한 뒤에만 한 번에 차감·생성한다.
- 공격 주기는 windup+recovery+cooldown 정확히(vanguard 76tick). 발사 시 표적 재검사(빗나가도 주기 소모), 지원장 배율은 발사 시 snapshot, 피해 `(AP*num+50)//100`, 한 tick 피해를 모아 적용해 사망·처치 보상은 한 번만.
- `FixedStep`: 누적 경과 시간으로 due tick을 계산해 프레임률과 무관, 프레임당 최대 4tick, 0.25초 초과 backlog는 버리고 `droppedSeconds`로 보고.
- `MatchService`: Running 진입 시 프로필의 유닛 레벨·특성을 복사해 World 생성, 매 tick `stepAll`로 대기 명령·이동축을 적용하고 최종 Accepted/Rejected(InsufficientFood/Cooldown/UnitCap)를 회신. snapshot에 엔티티(공격력 제외)·자원·outcome 포함.
- 범위 밖/알려진 한계: 원거리 공격은 해당 tick의 `projectileRequests`로만 남고 피해는 P4. Cast는 `NotReady`(P4). 적 스폰은 P6. 경기 종료 후 세션은 `Settling`에 머물러 서버 경기 슬롯을 차지한다(정산 P7/P8). `ServerMessage.serverTick`은 서버 rig tick, snapshot `tick`은 World tick이다. 0인 recovery/cooldown은 주기가 1tick 늘지만 P1 검증이 0을 금지한다.

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
