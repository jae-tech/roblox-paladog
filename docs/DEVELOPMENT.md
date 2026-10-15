# P0~P5 개발 및 검증

## 현재 상태

P0~P4 gate PASS는 P4 기준선 기록이다. 현재 P5는 입력·네트워크·뷰 구현과 CLI/Studio 서버/클라이언트613개 PASS 체크포인트이며, 실제 입력/장치 화면/renderer 교체/멀티터치 증거가 부족하여 full gate BLOCKED다. production 서버는 boot만 하고 client UI는 server remote를 기다린다. 테스트 저장은 Mock/InMemory이며 P6~P9는 미착수다. 기존 production runtime WAIVED·P0.1 보류·overlay 미승인은 유지한다. 연구/설계 정본13개는 수정하지 않는다.

최초 검증 호스트는 **macOS Darwin ARM64**였으며 2026-10-16 재개 호스트는 **Windows AMD64 / Python 3.14.2**다. 두 호스트의 같은 도구 버전을 고정했고 Windows 로컬 gate를 새로 검증했다(아래 참조). macOS에서 변경된 bootstrap을 재실행한 것은 아니다. 초기 P0 Git 기준선은 `f36bf2a`였고 당시 팀 branch 정책은 미합의였다. 현재는 AGENTS.md에 따라 단계별 로컬 feature branch에서 소스/문서/도구만 커밋하고 main에 fast-forward 병합한다(P4: `p4-projectiles-and-hero-skill`). `.omx/`, `artifacts/`, `.tools/`, 연구 바이너리와 키는 제외한다. push/publish는 하지 않는다.

## Windows AMD64 재개 (2026-10-16)

```powershell
python tools/setup_tools.py
python tools/verify_p0.py --local-only
python tools/verify_p1.py
python tools/verify_p5.py  # Studio 증거 없으면 exit 2/BLOCKED
```

- 추가 Python 패키지나 전역 도구 설치 없이 기존 Luau0.742/StyLua2.6.0/Rojo7.7.1/selene0.32.0/luau-lsp1.70.1의 Windows ZIP을 `.tools/`에 설치한다. 플랫폼별 URL/SHA256은 `toolchain-lock.json`, 경로 선택은 `toolchain.py`다. ZIP은 `.tools/<platform>/`, 실행파일은 기존 버전 디렉터리에 두며 macOS의 rokit 사용은 유지했다. Windows ARM64/Linux는 고정 자산이 없어 bootstrap exit2다.
- Windows ZIP SHA256은 각 공식 release의 GitHub API digest와 실제 다운로드를 비교했다: [Luau](https://github.com/luau-lang/luau/releases/tag/0.742), [StyLua](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0), [Rojo](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1), [selene](https://github.com/Kampfkarren/selene/releases/tag/0.32.0), [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp/releases/tag/1.70.1). macOS 자산/타입 정의 URL·SHA는 보존했다.
- 최초 checkout의 `core.autocrlf=true`가 원문 2개의 SHA와 생성물 바이트 비교를 깨뜨렸다. `.gitattributes`에 LF checkout 정책을 추가하고, 줄바꿈만 달라진 파일을 기존 Git blob의 정확한 바이트로 복원했다. 원문/생성물/밸런스 값은 바꾸지 않았다. 검사에서 CRLF를 정규화해 허용하거나 SHA를 갱신하지 않는다.
- 검증 도구의 파일·subprocess 텍스트는 UTF-8을 명시해 Windows CP949에 의존하지 않는다. 실행파일 경로 선택을 공유하며 검사 assertion/Studio 증거 요구사항은 유지했다.
- 호스트 선택/기존 버전 보존/명시적 `.exe`/미지원 BLOCKED/체크섬 선검증/경로 탈출 거부/캐시·타입 정의 설치/실제 Git autocrlf clone 회귀10개를 추가했다. 전체 Python96개, P0 local/P1, P2/P3/P4/P5 CLI132/123/134/613개, 타입/lint/format/build PASS다. full gates는 Studio MCP가 이 세션에 노출되지 않아 BLOCKED다. Windows Studio 실행·화면·touch 또는 macOS 재실행 PASS를 뜻하지 않는다.
- 커밋 `e48f7b2`의 새 Windows clone(`core.autocrlf=true`, 다운로드 캐시만 공유)에서도 bootstrap·원문 SHA·P0 local/P1 PASS, P5 CLI613 PASS/full BLOCKED와 clean 작업 트리를 확인했다. 상세 증거 경로는 HANDOFF에 있다. 로컬 gate 재현이지 Studio 완료 재현이 아니다.

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
- P3 당시 경계: 원거리 요청/`Cast`는 후속 P4에서 아래와 같이 연결했다. 남은 한계: 적 스폰은 P6. 경기 종료 후 세션은 `Settling`에 머물러 서버 경기 슬롯을 차지한다(정산 P7/P8). `ServerMessage.serverTick`은 서버 rig tick, snapshot `tick`은 World tick이다. 0인 recovery/cooldown은 주기가 1tick 늘지만 P1 검증이 0을 금지한다.

## P4 투사체·영웅 시전 (T-PROJECTILE / T-HERO / T-SEC)

```sh
.tools/luau-0.742/luau tests/cli_p4.luau
python3 tools/verify_p4.py  # CLI PASS여도 Studio 증거 없으면 exit2/BLOCKED
python3 tools/verify_p4.py --studio-evidence artifacts/P4/studio/20261015T123227Z/p4-studio.json
python3 -m unittest discover -s tools/tests
```

- `ProjectileSystem.launch`는 living owner의 진영/레인과 발사 시 피해를 복사한다. 이후 owner 존재 여부와 무관하게 `advance`가 sweep을 수행한다. 충돌은 segment 진입 거리, 정확한 동률은 entityId 순서다. pierce1은 한 표적만 때린다는 뜻이다. target ID를 추적하지 않으며 살아 있는 적대·같은 레인 대상만 판정한다.
- 탄 ID도 `nextEntityId`를 공유한다. active 탄과 영웅 예약 합계가 cap128이고, 자동 공격은 cap 실패 시 recovery로 넘어간다. `heroAction.reservedProjectileSlot`은 예약1개를 뜻하는 boolean이다. release 직전에 예약 해제→일반 launch를 동기 수행하므로 자동 발사가 시전 슬롯을 빼앗지 못한다.
- `HeroActionSystem.cast`의 검사 순서: slot→생존→Busy→Cooldown→InsufficientMana→ProjectileCap. 모든 검사 뒤에만 자원/쿨/예약을 변경한다. 재생이 commands보다 먼저이므로 경계 테스트는 재생을 끄거나 그 tick 재생량을 포함한다. release=cast+4, end=release+6, ready=cast+30. end tick부터 Busy가 아니며 별도 cooldown은 남을 수 있다.
- 영웅 이동은 시전과 독립이다. 탄은 이동 후 hero.x에서 +X로 나가고 지원장 배율을 자신에게 적용하지 않는다. 발사 tick에는 이동/충돌0, 다음 tick부터 이동한다. expireTick의 마지막 segment는 collision 후 제거한다. 맵/남은거리까지 자른 segment로만 판정해 그 너머는 맞지 않는다.
- 피해 batch는 기존 근접+기존 탄이 공유한다. 같은 tick에 발사자 사망이 발생해도 batch 전 release는 성립한다. 그 전 tick에 사망했으면 release 취소·예약해제, 환급없음. 종결 이후 World는 완전히 정지하고 잔존 탄/병력의 최종 정리는 P6이다.
- snapshot에는 별도 복사한 궤적·시전 timing·`resources.skillReadyTick`만 추가한다. damage/attackPower/hit set/예약은 숨긴다. `World.digest`에는 모든 새 projectile 필드·시전·스킬 쿨을 포함한다. `World.PHASES`와 생성 수치는 그대로다.
- `ServerHarness.runSuite('T-P4',12345)`가 CLI와 같은 suite를 실행한다. harness suite 선택은 분기별로 호출한다(luau-lsp는 두 require 함수의 union을 직접 호출하면 동일 서명이어도 거부했다). gate는 raw Studio seed·전체 ordered assertion을 fresh CLI와 exact 비교하고, 같은 tick 발사/명중·소스 길이 불일치·비공개 DTO·빈 suite·위조 PASS·미종료 rig를 거부한다.
- 검증 범위는 CLI/Studio 서버 시뮬레이션과 실제 RemoteEvent까지다. PC/touch 입력, 화면 표시, 실제 저장, 4경기10분 성능은 P5/P8/P9에서 별도 검증한다. 이번 Studio fixture 마나/표적은 서버 테스트 전용이며 production에 grant endpoint를 만들지 않았다. raw 경로·수치는 [HANDOFF](HANDOFF.md)에 있다.

## P5 클라이언트 기반 (진행 중 / full gate BLOCKED)

```sh
.tools/luau-0.742/luau tests/cli_p5.luau  # 입력31 + 네트워크163 + 뷰419 = 613
python3 tools/verify_p5.py              # runtime 증거 없으면 exit2
python3 tools/verify_p5.py --studio-evidence artifacts/P5/studio/20261015T125703Z/p5-partial.json
```

- 표현 정본은 `DESIGN.md`다. `Presentation/Layout`는 safe-area 내부 offset을 사용하고 실제 세로 여부와 좁은 가로 compact 배치를 분리한다. 10개 viewport의 최소48px·간격8px·HUD 비중첩을 순수 테스트했다. P5 추가 핵/탄/지면5개도 Original placeholder로 manifest에 선언하고 `asset_audit`가 ViewDefinitions의 literal presentationId를 함께 검사한다.
- `ActionRouter`는 순수 입력 상태, `DeviceAdapter`는 CAS/GUI/UIS 경계다. CAS Cancel은 KeyCode.Unknown일 수 있어 action의 모든 alias를 정리한다. movement는 InputObject별 hold/global release, GUI discrete는 Activated 하나만 사용한다. 숨김·focus·text·menu blockers는 서로 독립이고 재활성 시 키를 자동 복원하지 않는다.
- snapshot은 현재 match·증가 seq·비감소 tick·동일 balance와 유한값을 검증해 복사한다. 비영웅은0.1초 지연 보간/최신 밖 최대0.15초 시각 외삽, 영웅만 최대0.15초 입력 예측과 clamp를 한다. 0.1stud 이하 오차는0.1초 보정, 큰 오차와 종결은 snap한다. HP/자원/피해를 로컬에서 확정하지 않는다.
- 완전 snapshot에 표시용 bounds/속도/상한/잠정 보상과 `commandAckSeq`를 추가했다. `inputAckSeq`/`commandAckSeq`는 재연결 후 서버 high-watermark 이하 seq를 재사용하지 않기 위한 값이고 최종 Accepted/Rejected는 기존 ServerMessage를 따른다. bootstrap은 동시1개·최소1초 간격이며3초 UI timeout도 호출 취소로 취급하지 않는다. Preparing의 승인 누락과1초 stale snapshot은 bootstrap으로 복구한다. 오래된 bootstrap/StartStage ack는 최신 terminal phase를 덮지 못한다.
- EntityView의 renderer 시도는 각자 Folder를 소유한다. 미지원 Sprite/Model은 예상된 Placeholder fallback이고, 등록된 factory/update/play/destroy 결함은 원래 문맥을 경고한다. 부분 생성물과 실패한 handle은 정리하며 Placeholder 자체 결함은 다시 던진다. renderer 생명주기/카메라 실제 복원과 digest 동일성의 엔진 검증은 아직 남아 있다.
- Runtime은 production remote를 새로 만들지 않고 서버가 제공할 때만 구독한다. remote 제거/재연결 시 controller/입력 상태를 정리한다. production 서버 bootstrap은 boot만 하므로 실제 플레이 서버 연결은 이후 단계 범위다. 로비에 Mock으로 위장한 진행을 만들지 않는다.
- 공식 API는 Context7 `/websites/create_roblox`와 Roblox docs(ContextActionService, GuiButton, UserInputService, GuiService, ScreenGui, Camera)를2026-10-15 확인했다. ScreenInsets=CoreUISafeInsets와 IgnoreGuiInset을 섞지 않으며 Scriptable camera는 Focus도 갱신한다.
- 검증: P0 local/P1 gate PASS, P2/P3/P4 CLI132/123/134 PASS, 전체 Python86 PASS, 타입 분석·lint·format·production/test build PASS. Studio 서버/클라이언트613개도 PASS이나 실제 키/GUI·장치 화면·renderer 교체·실제 touch는 BLOCKED다. 캡처 실패/터치 도구 부재 및 raw 경로는 [HANDOFF](HANDOFF.md)에 있다. P5 partial gate는 의도적으로 exit2이며 P6 선행 PASS로 쓰지 않는다.

## production / test 경계

- `default.project.json`: Shared/GameServer/GameClient와 직접 만든 빈 Environment만. 테스트 모듈·fixture·Remote endpoint가 없다.
- `test.project.json`: 같은 소스 + TestSupport와 명시 `P0TestBuild` marker. P5 client에는 Runner와 P5 pure suite4개만 추가로 매핑한다(서버 저장 fixture는 client에 배포하지 않음). 외부 에셋/스크립트는 없다.
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
