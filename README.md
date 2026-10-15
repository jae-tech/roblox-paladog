# 등불 원정 — Roblox 게임 설계 (가칭)

Paladog의 메커니즘을 참고하는 **오리지널 2.5D 횡스크롤 전략 액션** 프로젝트입니다.
현재 P0 로컬 기반(Rojo production/test tree, strict bootstrap, assert runner·mock fixtures·품질 gate)을 구현했습니다. Studio MCP로 승인된 테스트 universe에서 실제 server/client boot와 harness 실행을 검증해 full gate가 PASS입니다(P0.1 Git 정책 미확정, production 런타임 require 확인은 정적 audit으로 대체). **게임/MVP가 완성된 상태가 아닙니다.** P1 데이터 변환(연구 수치 → `mvp-proto-001` 밸런스·생성 Luau)은 P1 gate(T-DATA + 자동 T-ASSET 검사) PASS입니다. overlay 신규 결정은 아직 승인 전입니다. P2(원격 프로토콜 검증·세션/프로필 골격)는 Luau 테스트와 Studio 2-client 격리 검증을 통과했습니다(production에는 아직 연결 전). P3~P9는 아직 시작하지 않았습니다.

재현 명령·도구 버전·승인 경계·미검증 항목은 [개발 안내](docs/DEVELOPMENT.md)를 확인하세요. `python3 tools/verify_p0.py --local-only`는 로컬 검사이며, `python3 tools/verify_p0.py --studio-evidence <json>`은 MCP로 수집한 Studio 증거를 검증하며, 증거가 없으면 exit2/BLOCKED입니다.

## 설계 문서

1. [PRD](docs/PRD.md) — MVP, 원작 확인/추정/충돌, 제품 수용 기준
2. [ARCHITECTURE](docs/ARCHITECTURE.md) — 서버 권한 전투, 클라이언트 표현, Remote, 저장
3. [DATA_MODELS](docs/DATA_MODELS.md) — 유닛·영웅·전투·스테이지·성장·프로필·DTO
4. [ASSET_PIPELINE](docs/ASSET_PIPELINE.md) — 수치 정규화·출처 추적·오리지널 에셋
5. [IMPLEMENTATION_PLAN](docs/IMPLEMENTATION_PLAN.md) — OMX P0~P9 작업·선행 조건·검증 게이트
6. [TEST_PLAN](docs/TEST_PLAN.md) — Luau/Studio/MCP·보안·저장·기기 테스트

기존 분석 문서 7개는 [분석 인덱스](docs/paladog-00-index.md)에서 확인할 수 있습니다.
분석은 패치 APK의 정적 증거를 대상으로 하며 정품 런타임 동작이나 밸런스의 재현을 보장하지 않습니다.

## MVP 및 기술

영웅1 · 아군3 · 적3 · 스테이지3 · 식량/마나 · 소환/자동전투 · 영웅 이동/무기 스킬 · 승패 · 성장/저장.
Luau, Roblox Studio, Rojo, Roblox Studio MCP, DataStoreService, RemoteEvent/RemoteFunction을 사용하도록 설계했습니다.

APK의 캐릭터·이미지·음악·코드는 출시 게임에 복제하지 않습니다. 초기 에셋은 Placeholder이며 애니메이션·렌더링은 전투 로직과 분리합니다.
