# Asset & Data Pipeline — 근거 보존과 오리지널 제작

버전1.0 · 2026-10-15 · **변환기·에셋 미구현**. 이 문서는 수치 파이프라인과 시각/음향 파이프라인을 따로 설계한다. 수치 참조는 [DATA_MODELS](DATA_MODELS.md), 원작 확인/충돌 등록은 [PRD](PRD.md)를 따른다.

## 1. 출시 경계

- APK의 Java/DEX/독자 애니 파일/캐릭터/스프라이트/텍스처/UI/효과음/음악/로고를 출시 tree에 넣지 않는다. 소스 코드를 번역하거나 독자 바이너리를 Roblox 애니메이션으로 변환하는 작업도 하지 않는다.
- `reference/`가 향후 확보되어도 연구용으로 격리하고 Rojo 매핑·배포 allowlist 밖에 둔다. APK/XML 원본은 GitHub에 업로드하지 않는다.
- 문서에 기록된 숫자는 **출처와 의미를 검증한 뒤 필요한 값만** 설계 참고치로 사용할 수 있게 한다. 수치를 읽었다는 사실만으로 출시 사용 승인·권리 검토가 끝났다고 간주하지 않는다.
- MVP는 직접 만든 기하학 Placeholder, 새 색·이름·실루엣, 무음 또는 직접 만든 사운드로 시작한다. 외부 에셋은 출처·권리·실행 스크립트 검사 후 명시 승인하며 이번 작업에서 설치/구매/업로드하지 않는다.

현재 확보물은 Markdown7개뿐이다. 원본 APK/XML/JADX 산출물은 이 작업 트리에 없다. 따라서 **지금 XML을 파싱했다거나 714행을 완전 복원했다고 보고할 수 없다**. E01 A6의 DB714/스테이지241행은 분석 문서가 보고한 수치다. EA 부록은 효과/빈 행 일부가 생략된 요약이고 전체 원본의 대체물이 아니다.

## 2. 수치 변환 흐름

```text
연구용 Markdown7개 (read-only, SHA-256)
    ↓ 명시적 table locator + 사람이 검토한 field allowlist
data/reference/manifest.json + records.json + conflicts.json
    ↓ namespace/의미/단위 정규화 (불명확하면 quarantine)
data/normalized/reference.json
    ↓ 신규 ID 매핑 + mvp-proto-001 balance overlay + 콘텐츠 범위 선택
data/balance/mvp-proto-001.json
    ↓ 스키마·상호참조·상한·수치 golden 검증
src/server/Config/Generated/{Units,Enemies,Hero,Stages,Progression}.luau
src/shared/PublicCatalog.luau
artifacts/data/{conversion-report.json,provenance.json,balance-diff.md}
```

Python 표준 라이브러리(`json`, `hashlib`, `decimal`, `xml.etree.ElementTree`)로 미래 변환기를 구현한다. 새 dependency는 필요 없다. Markdown 전체를 한 regex로 긁지 않고 **문서+절 제목+헤더 서명**으로 테이블을 특정한 뒤 셀을 파싱한다. 추출기는 표 안의 escaped pipe(`\|`)와 빈 셀을 구분하고 열 개수·헤더 변경 시 실패해야 한다. 공식 XML을 나중에 확보하면 별도 입력 어댑터를 붙이되 같은 normalized schema/golden을 사용한다.

### 2.1 소스 인벤토리와 표 선택

| 입력 | 추출 범위 | 정규화 출력 |
|---|---|---|
| E00/E01 | 분석 대상/hash/정적 분석/DB 순서/버전 | source metadata. 코드·SDK·세이브 내용은 runtime 반입 안 함 |
| E02 §0/1.4/5 | 단위·유닛 논리ID→DB행·레벨덮어쓰기·소환 | 규칙 metadata와 assertion |
| E03 §1.3/1.6/1.8/3.1/4.1 | 영웅·자원·EXP·무기 참고값 | 확인 가능한 선택 field. 무기 속도 추정 안 함 |
| E04 §2-4/3/6 | 스폰 의미·미사용필드·좌표 | reference stage semantic model |
| E05 B2~B5/B6/B10 | 레벨행/다음 비용/5·6 alias/보상 경로 | upgrade/level reference, conflict metadata |
| EA A2/A13 | 아군3종 기본·전체20레벨 | reference60개 level row; runtime은15개(L1~5)만 |
| EA A4/A5 | scrapper/spitter/brute의 참조3종, 아군/적 탄 | enemy3종·투사체 선택필드 |
| EA A14 | 스테이지0~240 인벤토리 + 필요 샘플 | 연구 참조만. 신규 s01~s03에 원본 mode/reward 강제매핑 안 함 |

첫 구현은 MVP allowlist만 production으로 생성한다. 9아군/20적/10보스/241스테이지 전체를 미리 구현하지 않는다. 전체 분석을 읽는 일과 전체 콘텐츠를 가져오는 일은 다르다.

### 2.2 식별자 충돌 해결

**`#` 열을 전역 기본키로 쓰지 않는다.** EA 머리말 설명보다 표별 정의와 E02의 코드 접근 규칙을 우선 근거로 삼고 둘 다 기록한다.

| tableNamespace | raw 식별자 | 해석/검증 |
|---|---|---|
| db.allyBase(A2) | #1,2,3 | ally논리1,2,3; dbRow207,208,209. #1을 DB1 마차와 join 금지 |
| db.enemyBase(A4) | #10,11,17 (`id____`) | 적논리1,2,8; dbRow225,226,232. stage enemyId10과 혼동 금지 |
| db.unitLevel(A13) | N,L | N은 표 재정렬/구입순서 표기를 포함. N5=거북이(논리6, db454~473), N6=원숭이(논리5, db434~453) |
| stage.campaign(A14) | #0~119 | 실제 stage DB행. 논리스테이지번호=# +1, mode는 본문 규칙 별도 |
| db.projectile(A5) | #260 등 | DB행으로 사용할 수 있으나 `iMaxHP`는 생명력이 아닌 관통 횟수 |

EA A13 설명의 '번호순'을 유닛 kind 순으로 오해하지 않는다. E02 §1.4/E05 B2의 위치 기반 접근과 HP/AP 쌍을 cross-check한다. A4의 더미 등 반복 id____99879는 unique ID가 아니므로 필요 시 행 위치 근거 없이는 quarantine. MVP에는 반입하지 않음.

### 2.3 필드 의미·단위 변환

변환 비율 `sourcePxToStud=0.1`은 신규 선택이며 서버의 모든 길이/속도 field에 한 번만 적용한다. 시간·HP/AP·비용을 거리 비율로 바꾸지 않는다.

| 원시 필드/규칙 | 정규화 | 예시/주의 |
|---|---|---|
| allyBase.iMana_ | foodCost | 10→10, 이후 runtime milli10000. manaCost로 오역 금지 |
| iMvSpd, iAtDst, iHtDst | stud/s, stud, stud | 30→3, 200→20, 12→1.2 |
| iCltm_, fAtDly | seconds→ceil/0.05 ticks | 1→20, 2.67→54. fAtDly는 전체 attack cycle 아님 |
| iAt1Fr/iAt2Fr | syncSeconds=frame/30 | 3→0.1sec→2tick. MVP 새 windup과 자동 동일시 안 함 |
| unit base HP/AP + level row | level iNewHP/AP로 대체 | 쥐 baseHP300+L1HP100 → **100**, 400 아님 |
| level cost(L+1) | 다음 레벨 도달 비용 | 쥐 L1→2는 row355 cost250. MVP overlay×0.1→25 |
| regen 0.1초당 값 | perSecond=value×10 | 0.2→2/s→2000milli/s |
| 확률 % / permille | unit 이름 명시 후 [0,1] 또는 정수분모 | 30%=0.3. 충돌한 보물탐지 단위는 변환 금지 |
| projectile.iMaxHP | pierceCount | 화살 기본1/스킬3. 탄 damage는 owner AP 사용 경로(E02 §3.1) |
| stage P1~4 | raw segmentWidth[] | 15,30,100은 실제15,30,55. 145로 나누어 정규화하면 틀림 |
| stage P5 | regularSpawnsBetweenSpecial | 19이면 20번째 U5. 19%가 아님 |
| stage min/max | reference interval 0.1초 lattice | 5/5→5.0~5.9, max+0.9 유지. MVP stage tick 범위는 별도 신규 |
| iCrRwd/iCrSec, #353, iTgDst | usageStatus=unused/contextual | campaign reward/별/속도에 자동 적용 금지 |

레벨표 관찰식을 생성 공식으로 대체하지 않는다. 코뿔소 L8 AP172(E05 B5/EA A13)처럼 불규칙한 값은 연구층에 그대로 보존하고 신규 overlay로 바꿀 때 이유를 남긴다. 미확인 애니 길이는0이나 fAtDly로 채우지 않는다.

### 2.4 provenance 예시 (형식 예시, hash는 실행 시 생성)

```json
{
  "canonicalId": "vanguard",
  "field": "levels[1].maxHp",
  "value": 100,
  "unit": "hp",
  "source": {
    "document": "docs/paladog-appendix-data.md",
    "section": "A13/유닛",
    "locator": "N=1;항목=HP;L1",
    "tableNamespace": "db.unitLevel",
    "dbRow": 354,
    "rawValue": 100,
    "evidenceLevel": "DocumentConfirmed"
  },
  "transformId": "campaign-level-replaces-base-v1",
  "decisionId": "MVP-UNIT-01"
}
```

manifest는 source file SHA-256, generator version, schema version, overlay hash, sorted output hash, 선택/제외/충돌 건수를 기록한다. build timestamp는 별도 report에만 두어 결정론 출력 hash를 흔들지 않는다. JSON number는 Decimal로 계산해 명시 반올림 후 Luau로 출력한다. 생성파일 직접 수정 금지, normalized/overlay를 수정해 재생성한다.

### 2.5 quarantine와 생성 게이트

- source section/헤더 없음, 셀 개수 불일치, duplicate canonical ID, 미확정 mapping, raw/comment/runtime 충돌이면 오류 또는 quarantine.
- optional값 누락과 실제0 구분. 빈 칸을 통째로0으로 채우지 않음. required값 누락은 build 실패.
- status는 `confirmed/inferred/conflicted/unused`로 관리. production allowlist는 confirmed 값 또는 출처와 별도로 명시된 신규결정만 허용. inferred/conflicted를 silent fallback하지 않음.
- 원작과 신규 밸런스 diff를 필드 단위 출력. 비용×0.1, 모두 기본 해금, 핵HP600/900/1400, 새 타이밍/스킬쿨/지원장 효과를 의도적 차이로 표기한다.
- generator → validator → golden tests → deterministic regeneration(diff0) → Luau parse/type check → Rojo build 순서. source SHA 또는 헤더가 바뀌면 검토 전 자동 승격 금지.
- PublicCatalog에는 UI 이름/아이콘/비용/쿨/설명만. 서버 설정·원문 캐릭터명·연구 경로·프로필·lease는 출시 catalog에 싣지 않음.

향후 CLI 계약(아직 없음):

```powershell
python tools/import_reference.py --source docs --manifest data/reference/manifest.json
python tools/build_balance.py --version mvp-proto-001
python tools/validate_data.py --strict
python tools/build_balance.py --version mvp-proto-001 --check
```

게이트는 [TEST_PLAN](TEST_PLAN.md)의 T-DATA. '명령 예시가 문서에 있다'는 실행 성공 증거가 아니다.

## 3. 시각·애니·음향 제작 파이프라인

```text
신규 디자인 brief → 원본 제작 파일 → 권리/출처 manifest → Placeholder 실장
 → 실루엣·스케일·pivot 검증 → sprite 또는 model adapter
 → 테스트 experience 업로드/권한 검증 → manifest ID 확정 → 릴리스 allowlist
```

### 3.1 PresentationDef

```luau
export type PresentationDef = {
    id: string,
    renderer: "Placeholder" | "Sprite" | "Model",
    assetId: string?, -- 승인된 rbxassetid 참조, 미확보는 nil
    visualHeight: number, pivotOffset: Vector3,
    animations: {[string]: string}, -- Idle/Move/Attack/Cast/Hit/Death
    fallbackId: string,
}
```

별도 `asset-manifest.json`: presentationId, author/source/licenseRecord, originalFileHash, provenanceKind(Original/ApprovedExternal), Roblox assetId/owner, 승인 기록, scale/pivot, 상태 `placeholder/reviewed/uploaded/blocked`. 실제 없는 ID나 승인자를 채워 넣지 않는다. 외부 모델의 Script/LocalScript/require/외부 호출은 삭제·검사하고 꼭 필요한 오리지널 표현만 사용한다.

### 3.2 렌더러 교체 계약

`EntityView`는 `create(definitionId,presentationId)`, `update(snapshot,alpha)`, `play(eventId,state,startTick,durationTicks)`, `destroy(entityId)` 인터페이스를 호출한다.

- Placeholder: anchored Part, CanCollide/CanTouch/CanQuery=false, 진영색+기호. 모델 크기로 서버 hitRadius를 역산하지 않음.
- Sprite: 직접 제작 이미지 atlas를 BillboardGui/ImageLabel로 표시. facing·프레임 선택은 시각값이며 서버 공격 release tick에 맞춰 재생 속도/프레임을 조정한다.
- Model: 직접 제작 mesh/rig/AnimationController. Humanoid 이동·물리 피격과 분리. animation marker는 VFX용만 사용한다.
- 애니가 없거나 로드 실패하면 Placeholder/기본 pose로 fallback. 서버 공격 타이밍·피해는 그대로다. 긴 애니를 넣어도 주기·DPS가 변하면 안 된다.
- hit/cast/death eventId로 중복 VFX를 억제하고 snapshot 재수신으로 사운드를 반복하지 않는다. visual jitter RNG는 combat RNG와 분리.
- 화면 밖 unit·사망 연출·먼지·trail은 풀링/생략 가능. 소유자 화면에만 보이는 visual은 서버에 Instance로 생성하지 않는다.

### 3.3 MVP 산출 에셋 수

영웅1, 아군3, 적3, 핵1, 발사체 공용3종(ally/enemy/pulse), 배경1개 재색상3버전, 버튼/자원/성장 아이콘 직접제작. 초기 애니는 이동 bob/공격 pulse/사망 fade 같은 코드 기반 Placeholder여도 된다. 음악·전용 스켈레톤·고품질 sprite/model 제작은 MVP 기능 완료와 분리한다.

## 4. 반입/출시 검증

| 게이트 | 합격 기준 |
|---|---|
| T-DATA | 레벨 대체·ID alias·단위·미사용 컬럼 golden 통과, 신규 overlay diff 승인, 출력 재생성 diff0 |
| T-ASSET | 모든 runtime presentation이 manifest에 존재, 금지 APK 확장자·텍스처·음원0, 승인 없는 외부 스크립트0 |
| 교체 회귀 | 같은 seed/commands에서 Placeholder/Sprite/Model 전투 digest·승패·HP·소모 동일 |
| 실패 주입 | 누락 atlas/권한 없는 asset/로드지연에도 전투 지속, fallback 표시, 오류 로그 상한 |
| 성능 | 표현 adapter별 frame time·메모리·Instance 수, cap 스트레스 보고 |

단순 확장자 검색만으로 오리지널리티를 보장하지 않는다. 소스 manifest 검토와 시각/음원 검토가 필요하다. 이번에는 설계 및 문서만 존재하므로 에셋 업로드·라이선스·실행 성능 검증을 완료했다고 표시하지 않는다.
