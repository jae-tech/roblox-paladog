# Design

## Source of truth

**Active · 2026-10-16 · 3D 동행 전투**: 최신 사용자 지시와 `docs/3D_PLAN.md`가 아래 MVP 표현 계약보다 우선한다. 전장은 Workspace의 client-only 오리지널 도형 던전/영웅/용병/적/투사체이며 후방 추적 카메라를 쓴다. 식량 소환/별도 마나 마법·서버 확정 상태만 HUD에 표시한다. WASD 두 축, 1~9 소환, Q/E/R·좌클릭 시전, 터치 4방향을 지원한다. 작은 화면은 228px 하단 영역에서 소환 스크롤 행과 이동/마법 행을 나누고 이동 hit target은 48px 이상이다. 좁은 통로/단위 변환은 D-3D-01/02, 새 도형은 manifest의 dungeon_3d_placeholder다. 물리·피해 권한은 서버만 갖고, 카메라/인스턴스는 로비 복귀 시 복원/정리한다. 고품질 아트·자유 카메라 회전·협동은 이번 범위 아님. 엔진 smoke는 통과했으나 새 화면과 실제 조작은 Studio no-frame으로 BLOCKED다.

### 이전 MVP 계약 (역사 기록)
Active · 2026-10-15 · P5 전투 HUD/로비 선택/2.5D placeholder. 근거: `docs/PRD.md` §4, `docs/ARCHITECTURE.md` §6/9, `docs/TEST_PLAN.md` T-INPUT/T-NET/T-ASSET/T-DEVICE, 기존 PublicCatalog와 asset manifest. 기존 UI·이미지·스크린샷 기준선은 없다. 연구/설계 정본13개는 수정하지 않는다.

## Brand
등불로 폐허를 탐사하는 오리지널 기계 원정대. 차분한 산업적 형태, 영웅의 호박색 신호, 아군 청록/적 산호색에 문자·형태를 함께 쓴다. 원작 이미지·코드·음악, 외부 에셋, 과장된 저장 성공 표시를 피한다.

## Product goals
PC/터치가 같은 intent를 만들고 서버 확정 상태를 읽기 쉽게 보여준다. 시전 중 이동, 자원/쿨/거부/통신 상태를 관찰한다. 비목표: 고품질 아트, P6 스폰/정산, P7 성장 UI, P8 실제 저장, P9 성능 합격.

## Personas and jobs
짧은 횡스크롤 전투를 조작하는 PC/모바일 사용자. 한 손으로 이동을 유지하며 다른 손으로 소환/시전한다. 개발자는 서버 상태와 표현을 분리해 전투를 검증한다.

## Information architecture
연결 대기 → 로비(서버 해금 기준 스테이지 선택) → 전투 → 종결/저장 대기. HUD: HP/핵·자원·시간·통신/저장 → 전장 → 방향/소환/스킬. 메뉴는 게임 입력을 중립화한다. 미구현 정산을 완료로 보이지 않는다.

## Design principles
서버가 진실, 클라이언트는 표현. 조작 취소는 즉시 중립. 전체 snapshot으로 누락 view를 제거한다. 기다림·Mock·잠정 보상·미검증 상태를 숨기지 않는다. 최소한의 코드 생성 도형으로 교체 가능한 view 경계를 만든다.

## Visual language
어두운 navy/graphite 바탕, amber 영웅/강조, teal 아군, coral 적. Roblox 내장 글꼴, 14~24 기본 텍스트, 8px 간격, 48px 이상 hit target. 단순 사각·원형·기둥과 이름/HP 라벨. 번쩍임·화면 흔들림·음악·외부 이미지 없음. 엔티티 ID 기반 Z jitter만 허용하고 전투 RNG는 사용하지 않는다.

## Components
Presentation/Layout가 safe-area 내부 배치 소유. HUD: HP/자원·비용/쿨·거부·잠정 보상·Mock 저장·연결 경고. Left/Right hold, Summon1~3, Cast Activated, Start_s01~s03. EntityView가 renderer 생명주기·fallback 소유, CameraController가 Scriptable camera와 복원을 소유한다.

## Accessibility
진영을 색만으로 구분하지 않는다. 최소48px/간격8px, 키보드 A/D/방향키/1~3/Q 지원, GUI 선택 가능. 입력 focus/chat/menu에서 액션 중단. 기본 텍스트 대비를 확보하고 불필요한 모션/점멸을 만들지 않는다. 정식 접근성 표준 인증을 주장하지 않는다.

## Responsive behavior
1280×720/1920×1080 PC, 844×390/740×360 가로, 390×844 세로. CoreUISafeInsets를 존중한다. 가로는 좌측 이동/우측 액션, 세로는 행 분리와 가로 전환 안내. 작은 화면에서도 비용/쿨/저장 상태와 조작 버튼이 겹치지 않게 한다.

## Interaction states
서버 없음/로딩/버전 불일치/거부/잠정 보상/저장 대기를 구분한다. snapshot 0.5초 지연 시 경고·게임 입력 중단, 1초 이후 bootstrap 재동기화. bootstrap 동시1개, 3초 UI timeout은 호출 취소가 아니다. 종결 이후 경기 조작은 비활성이다.

## Content voice
짧은 한국어. 식량/마나/등불 파동, `Mock/InMemory`와 잠정 보상을 명시한다. 서버 확인 전 “저장 완료”·“보상 지급”을 쓰지 않는다. 미착수 기능은 숨기거나 미구현으로 표시한다.

## Implementation constraints
strict Luau, 외부 의존성/업로드/production remote 추가 없음. 순수 router·snapshot·레이아웃을 CLI/Studio 같은 suite로 검사한다. 렌더는 client-only, 물리/애니 marker에 피해 권한이 없다. PC 실제 입력·GUI·장치별 스크린샷과 내부 state를 함께 검증한다. 공식 API 근거: Roblox Creator Hub ContextActionService/GuiButton/UserInputService/ScreenGui/Camera (2026-10-15 조회).

## Open questions
- [ ] 실제 Android 동시 터치/취소 검증 — 장치 검증 담당; 현재 MCP는 keyboard/mouse만 지원하므로 에뮬레이터 화면을 실제 multi-touch PASS로 대체하지 않는다.
- [ ] 최종 에셋/밸런스 승인 — 사용자; P5는 오리지널 placeholder와 기존 미승인 prototype 수치만 사용한다.
