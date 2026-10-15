# 등불 원정 — Roblox 게임 설계 (가칭)

Paladog의 메커니즘을 참고하는 **오리지널 2.5D 횡스크롤 전략 액션** 프로젝트입니다.
P0~P4 도구·데이터·서버 전투 게이트는 P4 기준선에서 PASS입니다. **P5 입력·네트워크 예측·HUD·Placeholder·카메라는 구현 중이며 CLI/Studio 서버/클라이언트 동일613개 테스트가 PASS입니다.** 실제 키/GUI 입력, 장치별 화면, renderer 런타임 교체와 실제 멀티터치 검증은 남아 있어 P5 full gate는 BLOCKED입니다. 현재 환경은 화면 캡처에도 실패했고 권한/API 설정을 변경하지 않았습니다. **게임/MVP 완성이 아닙니다.** production 서버는 boot만 수행하고 클라이언트 UI는 서버 remote를 기다립니다. 테스트 저장은 Mock/InMemory뿐이며 P6~P9·밸런스 승인·실기기 검증은 미완료입니다. 기존 P0.1 Git 정책 보류와 production 런타임 require 검사의 정적 audit 대체도 유지합니다.

재현 명령·도구 버전·승인 경계·미검증 항목은 [개발 안내](docs/DEVELOPMENT.md)를 확인하세요. `python3 tools/verify_p0.py --local-only`는 로컬 검사이며, `python3 tools/verify_p0.py --studio-evidence <json>`은 MCP로 수집한 Studio 증거를 검증하며, 증거가 없으면 exit2/BLOCKED입니다.

2026-10-16 Windows AMD64에서 도구 설치·줄바꿈/UTF-8 재현 문제를 해결하고 P0 로컬/P1 및 P5 CLI613개를 다시 통과했습니다. Windows에서는 `python tools/setup_tools.py`로 같은 고정 버전을 설치합니다. 현재 세션에는 Studio MCP가 없어 P5 실제 입력·화면 검증은 여전히 BLOCKED입니다.

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
