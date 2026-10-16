# 등불 원정 — Roblox 게임 설계 (가칭)

Paladog의 소환 전투를 바탕으로 하는 **오리지널 3D 동행 전투** 프로젝트입니다. 식량으로 용병을 소환하고, 직접 영웅을 움직여 마나 마법을 쏘며 함께 전진합니다.

- 광장: 로블록스 아바타로 다른 유저와 만나고, 리더보드를 보고, 던전 입구(E)로 원정에 들어갑니다. 던전 안에서도 내 아바타가 영웅으로 싸웁니다.
- 조작: **W/S 전진·후퇴, A/D 횡이동, 1~9 용병 소환, Q/E/R 또는 좌클릭 마법**. 소환·마법 버튼을 누르면 그 칸 오토가 켜지고 다시 누르면 꺼집니다. 터치 버튼도 제공합니다.
- 현재: 3D 전장·모델·추적 카메라와 서버 공간 전투, 서바이벌(R6) 구현. CLI/Studio 검증과 Studio 실제 키·GUI 플레이 PASS(숫자 키·일시정지 버튼 입력은 미확인). 실 저장은 기본 비활성, 아트는 코드 placeholder입니다.
- 최신 범위/남은 일: [3D 계획](docs/3D_PLAN.md), [인수인계](docs/HANDOFF.md).

## 이전 MVP 검증 기록

P0~P9 구현과 CLI/Studio 회귀(P2~P9), 10분 부하, 실 QA DataStore 복원·경합 검증을 마쳤습니다. **Android 실기기 멀티터치 검증은 하지 못해 P9 gate는 BLOCKED이며, 출시 전 실기기 확인이 필요합니다.** 진행 상세는 [진행 기록](docs/PROGRESS.md)을 보세요. 운영 저장은 기본 비활성(서버 메모리)이고 공개 publish는 하지 않았습니다.

재현 명령·도구 버전·승인 경계·미검증 항목은 [개발 안내](docs/DEVELOPMENT.md)를 확인하세요. `python3 tools/verify_p0.py --local-only`는 로컬 검사이며, `python3 tools/verify_p0.py --studio-evidence <json>`은 MCP로 수집한 Studio 증거를 검증하며, 증거가 없으면 exit2/BLOCKED입니다.

2026-10-16 Windows AMD64에서 도구 설치·줄바꿈/UTF-8 재현 문제를 해결하고 P0 로컬/P1 및 P5 CLI613개를 다시 통과했습니다. Windows에서는 `python tools/setup_tools.py`로 같은 고정 버전을 설치합니다. 이후 Studio MCP 연결로 서버·클라이언트 동일613개, PC 입력/Q/GUI 소환/focus77ms 정지, 장치 화면5종과 renderer 교체/cleanup/카메라 복원도 통과했습니다. 독립 멀티터치 증거가 남아 P5 full gate는 여전히 BLOCKED입니다.

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
