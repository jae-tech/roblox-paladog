# 등불 원정 — Roblox 게임 설계 (가칭)

Paladog의 메커니즘을 참고하는 **오리지널 2.5D 횡스크롤 전략 액션** 프로젝트입니다.
현재는 설계·구현 계획 단계이며 Luau 게임, Rojo 프로젝트, 데이터 변환기와 실행 테스트는 아직 구현되지 않았습니다.

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
