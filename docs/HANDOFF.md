# Claude 개발 인수인계 — P0 로컬 기반

## 현재 상태

**P0 full gate PASS (`P0Complete: true`), P1 gate(T-DATA + 자동 T-ASSET) PASS, P2 gate(T-SEC 기본 + T-ISOLATION) PASS (2026-10-15). P3~P9는 시작하지 않았다.** P0.1(팀 합의 Git 정책)은 BLOCKED이고(로컬 main에 병합, push 안 함), production place 안의 런타임 TestSupport require 실패는 사용자 결정으로 정적 audit으로 대체(WAIVED)했다. P0/P1 증거와 overlay 결정은 검토자 확인 전이다.

기준 문서는 기존 설계 6개(`PRD`, `ARCHITECTURE`, `DATA_MODELS`, `ASSET_PIPELINE`, `IMPLEMENTATION_PLAN`, `TEST_PLAN`)와 REA Markdown 7개다. 이 13개 원문은 변경하지 않았다. REA 원본 SHA256은 `tools/reference-hashes.json`으로 검사한다.

구현: production/test Rojo tree 분리, strict shared/server/client bootstrap, `CharacterAutoLoads=false`, 빈 오리지널 Environment, assert runner, fake Clock/RNG, 명시적 Mock/InMemory fixture, test marker + Studio + 허용 universe guard, 고정 도구와 분석/lint/format/build gate, MCP 수집 Studio 증거 검증(`--studio-evidence`). 게임 플레이·실제 저장 기능은 없다.

## Studio 실행 검증 (2026-10-15)

| 항목 | 결과 |
|---|---|
| 환경 | Studio 0.743.0.7431133, `robloxstudio` MCP, `studio_id instance:ffj-1ij`, GameId `10771015944`(사용자 승인 테스트 universe), PlaceId `86482422738722` |
| 동기화 | `rojo serve test.project.json` → Rojo plugin Connect. 저장·publish 안 함 |
| 빌드 일치 | test marker, 스크립트 14개 바이트 길이 = 로컬 sourcemap |
| boot | server/client `BootReady`, marker `lantern-p0-foundation-v1`, 캐릭터 nil, Environment 비어 있음 |
| ServerHarness | `T-TOOL` PASS(10 cases), `T-TOOL-INTENTIONAL-FAIL` FAIL(`intentional-failure`만), 미지원 suite 거부 |
| ClientHarness | `inspectBoot` 성공 |
| guard 음성 대조 | GameId 0 place(`instance:l96-gww`)에서 server/client harness 모두 universe 미승인으로 거부 |
| production 격리 | 빌드 XML 정적 audit PASS. Studio 런타임 require 실패는 WAIVED |

증거: `artifacts/P0/studio/20261015T1052Z-harness.json`(P2 코드 포함 빌드에서 2-client 플레이테스트로 재수집; 이전 증거는 소스 길이 불일치로 FAIL하는 것이 정상). `artifacts/`는 gitignore 대상이라 **이 증거는 원격에 없다**; 다른 checkout에서는 위 절차로 Studio 증거를 새로 수집해야 PASS를 재현할 수 있다. 증거 JSON은 MCP 출력을 옮겨 적은 자기 기록(서명 없음)이며 소스 일치는 바이트 길이 비교다. gate report의 `openTasks`에 P0.1이 남는다. 조작 증거(GameId 0, 빈 player 목록, 개별 case FAIL 등)는 FAIL exit 1.

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
- Studio 2-client(테스트 universe, 실제 RemoteEvent, Mock store): 타인 경기 명령 `NotOwner`, 임의 hp 필드·Instance·NaN `InvalidPayload`, 피해자 대기열·이동축·revision 불변, 각자 자기 snapshot만 수신, 1000건 flood에서 20건만 수용·980건 무응답 집계·다른 플레이어 정상. 증거 `artifacts/P2/studio/20261015T1052Z-isolation.json`, gate `tools/verify_p2.py`.
- 설계 대비 변경: reason에 `InsufficientGold` 추가. server→shared require는 주입으로 해결(Studio alias·CLI symlink 불가를 실측).

## 다음 작업

1. 검토자가 P0/P1 증거와 overlay 결정(`data/overlay/mvp-proto-001.json`)을 확인한다.
2. P3(순수 시뮬레이션: 자원·소환·근접)부터 `docs/IMPLEMENTATION_PLAN.md` 순서대로 진행한다.

Studio 재검증 절차는 [DEVELOPMENT](DEVELOPMENT.md)의 "Studio/MCP T-TOOL 재개"를 따른다.

## 승인 경계

사용자는 이번 Claude 전환 인수인계를 위한 **Git commit/push를 명시 요청했다**. 이 요청은 게임 공개 배포 승인이 아니다. 실제 DataStore 작업, Studio API access toggle, 자산 upload, 공개 publish, 운영 데이터 변경에는 별도 승인이 필요하며 **그 승인은 부여되지 않았다**. 이 문서는 commit/push가 이미 성공했다고 주장하지 않는다.
