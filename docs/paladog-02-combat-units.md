# Paladog 명세 02 — 전투·데미지 계산, 유닛 스탯·소환·AI

> 근거 표기: Java 경로는 JADX 1.5.1 디컴파일 출력 `sources/` 기준 `파일:줄`(줄 번호는 디컴파일 결과 기준), `db.txt [n]` / `stage.txt [n]` = `assets/pdw_db.xml` / `assets/pdw_db_stage.xml`의 n번째 `<Data>` 레코드(0부터, `GetDBInfo(n)` / `GetDBInfoS(n)`와 동일). **[확인]** = 코드·데이터에서 직접 확인, **[추정]** = 정황 기반 해석. 전체 원본 값은 [부록 A](paladog-appendix-data.md), 분석 방법·종합 미해결 목록은 [인덱스](paladog-00-index.md) 참조.

## 0. 시간 단위 / 틱

| 항목 | 값 | 근거 |
|---|---|---|
| 로직 프레임 | 60 FPS (`setAnimationInterval(1/60)`) | [확인] `com/Paladog/KorGG/Paladog.java:123` |
| 로직 갱신 | 가변 dt(초) 기반. `GameProc(t)` → `t2 = t * fTimeMul` 를 모든 매니저에 전달 | [확인] `com/my/Layer/GameLayer.java:1017-1018, 1059-1062` |
| 배속 | `fTimeMul` (기본 1.0, `PlayFast(p_fMulti)` 로 변경, 애니 delay도 1/배속) | [확인] GM:4561-4563, AD:5146 |
| 스프라이트 애니 | 프레임당 0.0333초 = **30fps** (일부 걷기 0.0667) | [확인] AD:1421, AD:2414-2416 (`CacheAni(..., 0.033333335f)`) |
| `iAt1Fr`/`iAt2Fr`/사운드 프레임 | **애니 프레임 번호 × 1/30초** 후 타격 판정 | [확인] CI:3720 `m_iAttack1Frame * 0.033333335f`, CI:4268 |
| `iMvSpd` | **px/초** (`m_vPos.x += dir * speed * t`) | [확인] CI:2569-2570 |
| `fAtDly` | **초** (`m_fAttackPastTick += t` 와 비교) | [확인] CI:459, CI:4393-4398 |
| `iCltm_` (소환 쿨타임) | **초** | [확인] AD:1310-1321 |
| 화면/맵 | 논리 해상도 480×320, `iScrollMax` 기본 1024 (맵 타일로 재설정 가능) | [확인] AD:7416-7418, GM:382 |

Roblox 변환: 1 px(원작) → 원하는 stud 비율 하나로 통일하면 iMvSpd/iAtDst/iHtDst/투사체 속도가 모두 같은 스케일로 변환됨. 시간 값은 그대로 초 단위 사용 가능.

---

## 1. DB 로딩과 레코드 → 유닛 매핑

### 1.1 로딩 방식 [확인]
- XML `<Data>` 하나당 `DBInfo` 1개를 만들어 **등장 순서대로 ArrayList에 append** → 레코드 인덱스 `[n]` = `GetDBInfo(n)` (`com/my/DB/MyXMLReader.java:49-61`, `com/my/DB/DBManager.java:28-34`).
- 태그→필드 매핑: `com/my/DB/MyXMLReader.java:66-219` (예: `iMvSpd→m_iMoveSpeed`, `iAtDst→m_iAttackDist`, `iHtDst→m_iHitDist`, `iTgDst→m_iTargetDist`, `fAtDly→m_fAttackDelay`, `iSkDst→m_iSkillDist`, `fSkDmg→m_fSkillDamage`, `fSkPct→m_fSkillPercent`, `fSkKnd→m_fSkillKnockdownPercent`, `iCLine→m_iCreateLine`, `fBigSc→m_fBigScale`, `fBigSt→m_fBigStatMul`, `fZmESt→m_fZombieExtStatMul`, `iCost_/iNewHP/iNewAP→m_iLvUp*`).
- 스키마 주석은 레코드 그룹마다 컬럼 의미가 다름(같은 필드명을 재활용). 예: 장비 행에서 `fAtDly`=(A) 기본값, `fSkDmg`=(B) 등급당 증가 (db.txt 스키마 주석).

### 1.2 인덱스 매핑표 [확인]

| DB 인덱스 | 내용 | 코드 근거 |
|---|---|---|
| 0 | 주인공(팔라독) + **거대화/좀비 배수 저장소**(fBigSc 1.2, fBigSt 3.3, fZmESt 1.3) | AD:466 (`HERO_01 - HERO_01 + 0`), SM:637-643 |
| 1 | 마차(WAGON_01) | AD:670 |
| 2 | 다크독 | GM:918, GM:2794 |
| 3 | 초기 수치(EXP/GOLD) | CI:294 |
| 4 / 5 | 리젠 수치(팔라독 / 다크독) | GM:2719, GM:2770 |
| 6 | 다크독 스킬 수치(크리/회피/오오라) | GM:2779-2793 |
| 7–26 | 메이스 20종 (데미지 = A + B×등급) | GM:2702, `m_fMaceValue` |
| 27–46 / 47–66 / 67–86 | 반지 / 다크독 검 / 부적 | GM:2711, 2752, 2762 |
| 87–146 | 팔라독 투구/갑옷/말 | GM:2729-2746 |
| 147–206 | 다크독 투구/갑옷/신발 | GM:2798-2815 |
| **207–215** | 아군 유닛 NPC_01..09 = 쥐,토끼,곰,캥거루,원숭이,거북이,코뿔소,펭귄,용 | AD:764 `(kind - NPC_01) + 207`, AD:1305 `p_iNum + 207` |
| **216–224** | 토템 TTM_01..09 (다크독 소환물) | AD:1307 `p_iNum + 216` |
| **225–244** | 적 ZOMBI_01..20 (좀비…갑옷방패) | AD:896-897 |
| (225–244 재사용) | 적 ZOMBI_21..40 → **같은 행(kind-20)** + fZmESt 배수 | AD:898-899 |
| **245–254** | 보스 BOSS_01..10 | AD:900-901 `(kind - BOSS_01) + 245` |
| 255 | 적 본진 = BOSS_11 (같은 공식: 245+10) | GameLayer:497 CreateZombi(BOSS_11) |
| 256 | 목마 = BOSS_12 (다크독 모드 마차 대응) | GameLayer:476 |
| 257 | 다크독(서바이벌 적) = BOSS_13 | AD:462-463 |
| 258 / 259 | 튜토리얼 더미 / 깃발 (BOSS_DUMMY/FLAG) | CMc:1078-1079 [추정 매핑] |
| **260–294** | 아군 측 투사체/오브젝트 `(kind - OBJ_ARROW_N) + 260` (화살N/S, 폭탄N/S, 얼음N/S, 캥거루 주먹, …, 바나나/지뢰/화염지뢰) | CI:1721 |
| **295–306** | 적 측 투사체 `(kind - OBJ_BONE) + 295` (뼈다귀, 해골화살, 가래침, 호박, 레이저, 보스02/07/09/10 스킬, Mace01-03) | CI:1748 |
| 307–352 | 이펙트 | CI:1768 |
| **353** | "수치 배수" (`CM.eDB_ROW_MULTI_VAL = 353`) | CMc:2098 |
| **354–533** | 유닛 레벨표 9유닛×20레벨 `(unit-1)*20 + 354 + (lv-1)` | AD:779, `com/my/Layer/UnitUpgradeLayer.java:1347-1349` |
| **534–713** | 토템 레벨표 `(unit-1)*20 + 534 + (lv-1)` | GM:1453, UnitUpgradeLayer:1351 |

kind 비트 플래그 [확인] CMc:1062-1244: `ALLY=0x1000000`, `ENEMY=0x2000000`, `HERO=0x10000`, `NPC=0x20000`(유닛+토템), `ZOMBI=0x40000`, `BOSS=0x80000`, `OBJ=0x100000`, `EFF=0x200000`.
JADX가 일부 `switch` case 상수를 `android.R.id.*` 로 잘못 표시함: `R.id.content`=NPC_02(토끼), `edit`=NPC_03(곰), `hint`=NPC_05(원숭이), `icon2`=NPC_08(펭귄), `input`=NPC_09(용), `list`=TTM_01, `progress`=TTM_04, `summary`=TTM_07, `tabcontent`=TTM_08 (CI:3724-3787, CI:4272-4295). [확인: 값 0x0102000x 일치]

### 1.3 "수치 배수"(353) [확인]
- 상수 `eDB_ROW_MULTI_VAL=353`만 정의되어 있고 `GetDBInfo(353)` 등 **참조 코드가 없음** (grep 결과 0건). → **런타임 미사용**. 값도 대부분 1(iMvSpd만 2).

### 1.4 레벨표(iNewHP/iNewAP)가 유닛 기본 스탯을 **덮어씀** [확인]
```java
// AD:779-785 (CreateNpc)
DBInfo lc_pDBI = GetDBInfo(lc_iDBRow + ((lc_iUnitNum - 1) * 20) + 354);
lc_pCI.m_fAttackPower = lc_pDBI.m_iLvUpNewAP;
lc_pCI.m_fHPMax       = lc_pDBI.m_iLvUpNewHP;
if (gkGameKind == 2) { // 서바이벌
    m_fAttackPower += m_fAttackPower * fSVVUnitUpgradeMulVal * (lv - 1);
    m_fHPMax       += m_fHPMax       * fSVVUnitUpgradeMulVal * (lv - 1); }
```
- 따라서 행 207–215의 `iMaxHP`/`iAtPwr`는 전투에서 **사용되지 않음** (예: 거북이 `iAtPwr=100000` → 실제 공격력은 레벨표 AP=0). 이동속도/사거리/딜레이/스킬값은 207–215 행 사용.
- 레벨 행 오프셋: **[확인 — 바이트코드 검증]** JADX 일반 출력은 `lc_iDBRow = 0`으로 보이지만(디컴파일 손실), JADX `-m fallback`(원시 바이트코드) 출력에서 `row = (gkGameKind != 2) ? max(L-1, 0) : 0` 임을 확인함 — `GameManager.GetTTMAttackPower/GetTTMHPMax`, `AppDelegate`의 유닛 생성부(`+354`, `+534` 두 곳). 즉 **캠페인 = 레벨 L 행을 그대로 사용, 서바이벌 = L1 행 × (1 + 0.2×(L−1))**.
- 레벨표 행 라벨 주의: 434–453은 desc가 "유닛 레벨 6-x"지만 위치상 **유닛5(원숭이)** (HP320/AP60 = 원숭이 기본값과 일치), 454–473 "5-x"는 **유닛6(거북이)** (HP4000/AP0). 코드는 위치로만 접근 [확인].

레벨1 / 레벨20 값 (db.txt [354..533]):
| 유닛 | Lv1 HP/AP | Lv20 HP/AP |
|---|---|---|
| 쥐 | 100/20 | 200/40 |
| 토끼 | 100/40 | 200/80 |
| 곰 | 1200/40 | 2400/80 |
| 캥거루 | 1600/20 | 3200/40 |
| 원숭이 | 320/60 | 640/120 |
| 거북이 | 4000/0 | 8000/0 |
| 코뿔소 | 7000/120 | 14000/240 |
| 펭귄 | 1000/150 | 2000/300 |
| 용 | 5700/200 | 11400/400 |

### 1.5 적 스탯 배수 (fBigSt / fZmESt / 난이도) [확인]
```java
// SM:637-649 (CreateEnemy)
DBInfo lc_pDBI = GetDBInfo(0);                         // 주인공 행에 배수 저장
if (p_iIndex == 3 && rand%1000 <= 100) {               // 스테이지의 3번 슬롯 적만, 약 10.1%
    lc_fScale *= lc_pDBI.m_fBigScale;                  // 1.2배 크기
    lc_fStatMul = 1.0f * lc_pDBI.m_fBigStatMul; }      // 3.3배 스탯
if (kind >= ZOMBI_21 && kind <= ZOMBI_40)
    lc_fStatMul *= lc_pDBI.m_fZombieExtStatMul;        // 1.3배
// AD:926-929 (CreateZombi)
m_fHPMax       = iMaxHP * m_fStatMulVal * GetMulVal_HP_Dfct() * (서바이벌 보스 배수);
m_fAttackPower = iAtPwr * m_fStatMulVal * (서바이벌 보스8 공격 배수);
```
- 난이도 HP 배수 `GetMulVal_HP_Dfct`: 0→0.7, 1→1.0, 2→1.4 (GM:2839-2848). **적 HP에만** 적용, 공격력엔 미적용.
- 보상 골드/경험치도 `m_fStatMulVal` 곱 → 거대 적은 3.3배 보상 (CI:2941, 2979).
- 본진 HP 50% 이하가 되면 3번 슬롯(모드<5) 또는 2번 슬롯 적을 **항상 거대화(scale 1.2, stat 3.3)** 로 1초마다 소환, 최대 10회 (SM:378-421).
- 적 ID 규칙(스테이지 DB): 1–40 → `ZOMBI_(id)`, 100 초과 → `BOSS_(id-100)` (SM:620-627).
- 적 투사체(OBJ_BONE_22 등 21–40용 변종)는 `m_fStatMulVal=1.5`를 세팅하지만 AttackProc에서 사용 안 함 (CI:1727-1746, OI 미참조) → 실효 없음 [확인].

---

## 2. 데미지 공식

### 2.1 근접/직접 타격 `AttackToTarget()` [확인] CI:1148-1336
```
dmg = attacker.m_fAttackPower                       // 유닛=레벨표 AP, 적=iAtPwr×statMul
if (attacker.m_bAura)  dmg *= AuraWar               // 팔라독: 1 + 0.3×Lv[15]
if (target.m_bAura)    dmg *= AuraDefense           // 팔라독: 1 - 0.1×Lv[16]
if (state==16 화염메이스) dmg = GetMaceFireAtk()
if (target 영웅)        dmg *= GetMulVal_Damage      // 1 - 0.1×Lv[7]
if (target==거북이 && target.m_bAura) dmg *= 0.5
if (target==TTM_06)    dmg *= 0.5
if (target==TTM_07 이글) dmg = 0 (던전모드 이동중 제외)
if (target.state==39 변신중) dmg = 0
(변신 보정, 다크독 전용 크리/회피 — 2.4 참조)
(장비 보정 — 2.5 참조)
if (target==HERO_01 && 부활무적 0~10초) dmg = 0
target.HP -= dmg
```
- **방어력/고정 감산 개념 없음**. 순수 곱연산.
- 매 타격마다 `NeedToSlideBack`이면 피격자를 진행 반대방향으로 **5px 밀어냄** (CI:1260-1267; 영웅·보스·거북이·돌탱이·갑옷방패·폭탄적·TTM_06·넉다운중 제외 GM:2820-2836).
- 아군 유닛(NPC 플래그) 피격 시 HP가 **최대치의 20% 경계를 넘어 내려가는 순간** 넉다운(state 9) (CI:1166-1167, 1296-1301). 적은 이 규칙 없음.
- 사망: HP ≤ 0 → state 5. 본진(BOSS_11)/마차는 살아있으면 피격연출 state 21 (CI:1303-1316).

### 2.2 스킬 타격 `SkillAttackToTarget()` [확인] CI:1338-1491
- 2.1과 동일 + 공격자가 **쥐/토끼/곰/원숭이/코뿔소/용**이면 `dmg *= fSkDmg` (CI:1357-1359).
- 타격 후 `KnockdownFromSkill`: `rand%1000 < fSkKnd*10` 이면 넉다운 (영웅·보스 면역) (CI:1139-1146). → **fSkKnd 는 % 단위**.
- 캥거루 스킬 주먹: 생성 시 `projectile AP = owner AP × fSkDmg(0.6)` (CI:1798-1800).

### 2.3 스킬 발동 판정 `AttackOrSkill()` [확인] CI:1628-1660
```java
float p = m_pDBI.m_fSkillPercent;            // % 단위
if (m_bAura) p *= GetMulVal_AuraAbility();   // 1 + 0.4×Lv[18]
int roll = rand % 1000;
if (CheckKind(NPC) && !m_bAura) roll = (int)(p*10);   // ← 오오라 밖 아군 유닛은 스킬 불가
if (BOSS_08 || BOSS_10)          roll = (int)(p*10);   // 스킬 상태(8) 사용 안 함
if (roll < p*10) ChangeState(8 /*Attack2=스킬*/); else ChangeState(6 /*Attack1*/);
```
- **핵심**: 팔라독 유닛은 **영웅 오오라 범위 안에서만 스킬 발동**. 펭귄 fSkPct=100 → 오오라 안에선 항상 스킬.

### 2.4 크리티컬 / 회피 [확인] — **다크독 모드 전용**
- 조건 `hkHeroKind == 2` 일 때만 (CI:1209-1243). 팔라독 모드엔 크리/회피 없음.
- 회피(피격자가 영웅): `rand%1000 <= GetAttackMissPercent()*10` → dmg 0, "MISS". `Miss% = row6.iMvSpd(10) × Lv[13]` (GM:1431) (+어쌔신 갑옷).
- 크리(공격자가 영웅): `m_iCritical(매 프레임 rand%1000) <= CritPct*10`, `CritPct = row6.iCltm_(5) + row6.iAtDst(1)×Lv[14]` (GM:1435). 배수 `row6.fAtDly(5) + row6.fSkDmg(2)×Lv[15]` (GM:1439) (+어쌔신 신발).
- 영웅 공격엔 추가로 `AuraPlusAtk = (row6.iHtDst(2)×오오라중인적수×Lv[19] + 100)/100` (GM:1421).

### 2.5 오오라 (팔라독) [확인] CI:1048-1113, GM:827-886, GM:2671
- 대상: NPC 플래그(유닛·토템) 중 `|영웅x - 유닛x| <= AuraDist` **그리고 같은 m_iLine**.
- `AuraDist = 75 + 25×Lv[19]` px (다크독: 110 + 33×Lv[22]).
| 효과 | 공식(팔라독) | 근거 |
|---|---|---|
| 공격력 | ×(1 + 0.3×Lv15) | GM:836 |
| 받는 피해 | ×(1 − 0.1×Lv16) | GM:854 |
| 공격 딜레이 | ×(5 − Lv17)/5 | GM:863, CI:4394-4396 |
| 이동속도 | ×(1.5 + 0.5×Lv14) (레벨0도 1.5배) | GM:827, CI:2566-2567 |
| 스킬 발동률 | ×(1 + 0.4×Lv18), 오오라 밖은 스킬 0% | GM:871, CI:1638-1644 |
| HP 회복 | 5초마다 HPMax×0.04×Lv20 | CI:1086-1094 |
| 투사체 | 생성 시 소유자 `m_bAura` 복사, HP≤30%면 Aura30War 사용 | CI:1778, OI:162-168 |
- 다크독 모드에선 오오라가 **주변 적**에 걸리는 디버프: 적 공격 ×(1 − row6.fSkKnd×Lv17), 적이 받는 피해 ×(1 + row6.fSkPct×Lv16), 적 이속 ×(row6.fSdwSc − row6.fBigSc×Lv18), 1초마다 가시 데미지 `row6.iAtPwr + row6.fZmESt×Lv21` (GM:836-886, CI:1096-1110).
- Lv[n] = `g_GI.iSkillLevelCur[n]` (영웅 스킬 트리 레벨). 인덱스→스킬명은 [명세 03 §4](paladog-03-hero.md) 참조.

### 2.6 장비 보정 (전투 관련만) [확인]
- 말(8,1) 무장: 아군 유닛 공격 ×(1 + HorseArm×오오라유닛수) (CI:1244-1246, OI:334-336)
- 말(8,2) 기사: 영웅 피격 ×HorseKnight (CI:1247-1249)
- 말(8,3) 유니콘: 오오라 회복 시 +HPMax×값 (CI:1089-1091)
- 투구/갑옷 전사·네크로: 피격/사망 시 마나·식량 획득 (CI:1268-1277, 1323-1327)
- 반지(이속/HP/재생 등): GM `GetRing*` 계열. 수치 = (A) + (B)×등급 (db.txt 스키마).
- 메이스 데미지: `m_fMaceValue[i][0] + m_fMaceValue[i][1] × grade` (GM:1084-1087, 2702-2709) = db 7–26 의 `fAtDly + fSkDmg×등급`.

### 2.7 본진(적 성) 데미지 [확인]
- 본진 = 적 진영 캐릭터 BOSS_11, DB 255 (HP 3000, iHtDst 25), 위치 `iScrollMax − 120` (GameLayer:497). HP = 3000×난이도배수 (AD:926).
- 일반 캐릭터와 동일하게 타깃팅/데미지 계산. 피격 시 state 21 → 다음 프레임 `bCastleDamage` 플래그 후 state 0 (CI:461-469, CI:1304-1306). 본진은 이동·공격 안 함 (CI:2418).
- HP ≤ 0 → 승리(gameStep 7) (GM:224-233). 영웅 HP ≤ 0 → 패배(gameStep 6) (GM:215-221).
- 아군 본진은 **없음**. 적이 x ≤ 0 도달 시 일반 모드에선 **iScrollMax로 순간이동(루프)** (CI:2590-2602). 별도 페널티 코드 없음 [확인]. (타워모드(kind 3)에서만 골인 점수 CI:2631-2672)

### 2.8 히트 판정 / 사거리 의미 [확인]
| 필드 | 의미 | 사용처 |
|---|---|---|
| `iAtDst` | 공격 사거리(px). 타깃 탐색 반경 | CI:2471-2477, CI:918, CI:1630 |
| `iHtDst` | 피격 반경(몸 크기). 공격자 사거리에 **더해짐** | CI:794-796, CI:4381 |
| `iTgDst` | **전투에서 미사용** (다크독 스킬행 6에서만 다른 의미로 사용) | GM:2790 (유일 참조) |
| `iSkDst` | 범위 스킬 반경(곰 105, 용 200) / BOSS_13 변신 HP% / 목마 공격 주기(초) | CI:1563, CI:6113, CI:6488 |
| `iCLine` | **세로 그리기 위치 밴드**(Y 랜덤) — 레인 아님 | AD:803, AD:1392-1414 |

- 타깃 획득: `|dx| <= iAtDst(공격자) + iHtDst(대상)`, **같은 m_iLine**, **앞쪽만**(아군은 x가 큰 쪽, 적은 작은 쪽), 사망/제거/유령상태 제외, 가장 가까운 것 (CI:744-807). 검사 주기 0.025초(기기별 0.05초) (CI:2434-2446).
- 공격 대기(state 7) 중 매 프레임 `|dx| > iAtDst + iHtDst` 이면 타깃 해제 → 이동 재개 (CI:4380-4391).
- 근접 범위공격 `AttackArea(false)`: `|dx| <= iAtDst + 대상.iHtDst + 30` (방향 무관) (CI:1518). 스킬 범위: `|dx| <= iSkDst + 대상.iHtDst` (CI:1563).
- 빠른 거부용: CharManager가 아군 최대 x(=x+iHtDst), 적 최소 x(=x−iHtDst)를 매 프레임 갱신 (CMgr:67-107).
- **레인**: 일반 모드는 영웅·유닛·적·본진 모두 `m_iLine = -1` → **단일 레인** (GameLayer:526-540, GameUILayer:1434, SM:651-670 `p_iLine=100 → -1`). 타워모드(kind 3) 5레인, 던전(kind 6) 층 구조.
- Y 위치: `GetCreateCharY(iCLine)`: 1→165~184, 2→155~174, 3→145~164, 기타→145~184 (AD:1392-1414). 순수 연출용 깊이.

### 2.9 공격 타이밍 [확인]
```
상태 7(Attack1Delay) 진입 → 매 프레임:
  if (m_fAttackPastTick >= fAtDly × (오오라? AuraEnergy : 1)) AttackOrSkill()   // CI:4393-4401
상태 6/8(공격 애니) : ctPastTick >= iAt1Fr(또는 iAt2Fr)/30 초에 1회 타격     // CI:3720-4037, 4268-4297
공격 애니 종료(AniEnd) → m_fAttackPastTick = 0, 타깃 유효하면 상태7, 아니면 이동(1)  // CI:901-927
```
- **공격 주기 = 공격 애니 길이(프레임수/30초) + fAtDly**. `m_fAttackPastTick`은 생성 시부터 누적(CI:459)되므로 첫 공격은 대개 즉시.
- 공격 애니 프레임 수 예: npc01 att1 10f/att2 16f, npc02 20f, npc05 20f, npc08 20f, ene01 10f, ene17(폭탄) 75f (AD CacheAni 목록).
- 타격 시점엔 사거리 재검사 없음(대상 생존·방향만 검사) (CI:1159-1165).

---

## 3. 투사체 [확인]

### 3.1 생성 `CharInfo.CreateObj` CI:1707-1952
- DB: 아군 투사체 `260 + (kind − OBJ_ARROW_N)`, 적 투사체 `295 + (kind − OBJ_BONE)`.
- `m_fMoveSpeed = iMvSpd`(px/초), `m_fHPMax = iMaxHP` = **관통 가능 타격 수**, `m_fAttackPower = 소유자 공격력` (DB의 iAtPwr는 대부분 **미사용**), `m_bAura = 소유자`, `m_iLine = 소유자` (CI:1774-1779).
- 예외: 지뢰/화염지뢰 AP = `iAtPwr + fZmESt × ((stage−9)/12 + 1)` (CI:1785-1788); 서큐버스 키스 독뎀 = DB302 `iAtPwr`(2000) (OI:467-468).

### 3.2 직선 투사체 (화살, 얼음, 뼈다귀, 해골화살, 레이저, 캥거루 주먹, 달걀…) OI:1229-1262
- 0.05초마다 `GetNearChar()`: 같은 레인, **아직 맞지 않은** 대상 중 `|dx| <= 스프라이트폭/2 + 대상.iHtDst` (OI:579-628).
- 맞으면 `AttackProc` → 맞은 대상 리스트 추가, `m_fHPCur--`, 0이면 소멸 아니면 계속 비행 (OI:566-576) → **iMaxHP = 관통 수** (화살N 1, 화살S 3, 보스07 스킬 3, 신의주먹 2).
- 화면 밖(x < −폭 또는 x > iScrollMax+폭) 소멸. **최대 사거리 없음**.
- 투사체 `iAtDst`(=10)는 직선 투사체 판정에 **미사용**.

### 3.3 포물선형 (원숭이 폭탄 N/S, 적 가래침) OI:1188-1206, 1404-1441
- 발사 시 `m_iNeedDist = 타깃x − 자기x (+30, 폭탄)` (CI:3737-3741, 1610-1614).
- 비행 애니(0.5초 기준) 동안 `x += NeedDist × t / 0.5` → **정확히 0.5초에 타깃 위치 도달**.
- 애니 종료 → 공격 상태: 폭탄은 `|dx| <= iAtDst(N 40 / S 60) + 대상.iHtDst` 의 **모든 적**에 AoE, 가래침은 근처 1명 (OI:1409-1441).
- 폭탄S 데미지 = AP × fSkDmg(1.2) (OI:169-171).

### 3.4 투사체 추가 효과 (OI:153-577)
- 얼음S / 영웅얼음: 비영웅·비보스 대상 **빙결 state 12, 3초** (메이스는 GetMaceIceSec) (OI:508-519, CI:4814-4833). 얼음N은 빙결 없음.
- 투사체 DB `fSkKnd` 확률 넉다운(데이터상 전부 0) (OI:502-507).
- 아군 유닛 20% 경계 넉다운은 투사체 피격에도 적용 (OI:496-501).
- 독(서큐버스 키스/독메이스): 1초마다 dmg, **HP 1 미만으로는 안 내려감**, 10초 지속 (CI:5575-5636).

---

## 4. 유닛 AI 상태머신

### 4.1 상태 번호 [확인] CI:476-615
0 Idle, 1 Move, 5 Dead, 6 Attack1, 7 Attack1Delay(공격대기), 8 Attack2(스킬), 9 KnockDown, 10 KnockDownWait(스턴), 11 WaitForRemove, 12 Ice(빙결), 13 Ghost(무적 이동), 21 Damage(본진/마차 피격연출), 22 JustWait(벽형 대기), 39 Transform, 40 Appear, 2~4/14~20/23~36 영웅 메이스/검 스킬.

### 4.2 기본 흐름 (유닛·적 공통) [확인]
```
Move(1): 0.025s마다 GetNearChar(iAtDst) → 있으면 targetID 저장, ChangeState(7)    // CI:2471-2483
         없으면 x += dir × speed × t (아군 dir=+1, 적 dir=-1)                      // CI:2540-2630
Attack1Delay(7): 타깃 사거리 이탈/사망 → Move. 딜레이 충족 → AttackOrSkill → 6 또는 8  // CI:4355-4402
Attack1(6)/Attack2(8): 동기 프레임에 타격/투사체 → 애니 끝 → 7 또는 1               // CI:3476-4353, 901-927
KnockDown(9): 180 px/s × KnockDownMul 로 뒤로 밀림, 애니(16f≈0.53s → 약 96px) 끝 → 10  // CI:4770-4780, 946-948
KnockDownWait(10): 스턴 이펙트, 3초(또는 m_fKnockDownTickForce) 후 → Move          // CI:4783-4809
Dead(5): 보상 지급/사망 연출 후 제거                                                // CI:2815~
```
- **타깃 선택 = 같은 레인·전방·사거리 내 가장 가까운 적** (`lc_fDist < lc_fDistSave`) (CI:788-805). 랜덤 옵션은 이 경로에서 false.
- **정지 조건 = 타깃 존재뿐**. 몸 충돌/밀어내기 없음 → 유닛끼리 겹침 [확인: 충돌 코드 없음].
- 아군 이동 한계: 본진 있는 모드에서 `x <= iScrollMax − 160`, 보스 스테이지는 `iScrollMax − 40` (CI:2614-2621). 즉 본진 앞에서 멈추고 본진(iHtDst 25)을 타깃으로 공격.
- 영웅(팔라독) 자체는 자동공격 없음 (Move 타깃 스캔이 `!CheckKind(HERO)` 조건, CI:2430; Attack1 처리도 HERO_01 제외 CI:3693). 영웅 공격은 메이스 버튼.
- 넉다운 슬라이드 기준 96px: 윈드 메이스가 `KnockDownMul = 거리/96` 사용 (OI:194-195) → 180×16/30 = 96 일치 [확인].

### 4.3 특수 유닛 (아군) [확인]
| 유닛 | 동작 | 근거 |
|---|---|---|
| 쥐 NPC_01 | 근접. 스킬: 단일 ×fSkDmg(3) + 넉다운 10% | CI:1357, 4282 |
| 토끼 NPC_02 | 원거리(iAtDst 200). 평타 화살N(600px/s, 관통1), 스킬 화살S(관통3) | CI:3724-3731, 1493-1500 |
| 곰 NPC_03 | 근접. 스킬 = **범위**(iSkDst 105) ×fSkDmg | CI:4275-4276, 1563 |
| 캥거루 NPC_04 | fAtDly 0. 스킬: 0.133~0.4초에 걸쳐 주먹 투사체 5발(각 AP×0.6). **스킬 중엔 적 타격이 무효**(공격자가 타깃을 놓침) | CI:4298-4337, 1162-1164 |
| 원숭이 NPC_05 | 포물선 폭탄N(AoE 40), 스킬 폭탄S(AoE 60, ×1.2) | CI:3732-3744, 1601-1617 |
| 거북이 NPC_06 | **공격 안 함**: 사거리 내 적 발견 → 대기(state 22) 5초 → 다시 이동/재발견 반복. 오오라 안에서 받는 피해 ×0.5, 밀림 없음. 레벨표 AP=0이라 iAtPwr 100000은 무의미 | CI:3477-3480, 4356-4358, 5328-5487, 1181-1183 |
| 코뿔소 NPC_07 | 근접. 스킬 ×3, 넉다운 100% | CI:1357, db[213] |
| 펭귄 NPC_08 | 얼음N(400px/s). 스킬(오오라 안 100%) 얼음S → 빙결 3초 | CI:3745-3752, 1619-1626 |
| 용 NPC_09 | 평타 = 근접 **범위공격**(iAtDst+HtDst+30) + 화염 이펙트, 스킬 범위 iSkDst 200 ×1.2 | CI:3753-3755, 4293-4294 |

### 4.4 특수 적 / 보스 [확인]
| 적 | 동작 | 근거 |
|---|---|---|
| 해골 ZOMBI_02 / 화살해골 06 / 빨간좀비 10 / 호박 14 / 비홀더 18 (+22/26/30/34/38) | 각각 뼈다귀·해골화살·가래침(포물선)·호박(타깃 위치에 생성, 프레임7에 타격)·레이저 투사체 | CI:3788-3913, OI:1076-1083 |
| 유령 ZOMBI_09/29 | **첫 교전 시 1회** 유령화(state 13): 0.5초 페이드 → 타깃 불가 상태로 150px 전진 → 0.5초 복귀 | CI:4362-4367, 4835-4965, 745 |
| 돌탱이 ZOMBI_12 / 갑옷방패 ZOMBI_20 (+32/40) | AP 0 벽형: 공격 대신 5초 대기 반복, 밀림 없음 | CI:3477, 4356, 5487 |
| 폭탄 ZOMBI_17/37 | 이속 100. 공격 애니 75f, 프레임 72(2.4초)에 자폭: 범위(iAtDst 10+HtDst+30) AP 3000, 자신 즉시 제거(사망 보상 루트 아님, 킬 카운트+1) | CI:3829-3856 |
| 보스01 좀비킹 | 공격마다 ZOMBI_01 2마리 소환 (AP 0) | CI:3914-3946 |
| 보스02 백발마녀 | 사거리 내 첫 대상(영웅 제외) **개구리화 8초**(공격·스킬 불가 상태) + 타격 / 영웅 타깃 안 함 | CI:3947-3951, 1577-1596, 1688-1705, 760 |
| 보스03 사커좀비 | 매 타격 넉다운 + 밀림 ×3(≈288px) | CI:1292-1295 |
| 보스04 미이라킹 | 공격마다 ZOMBI_27 2마리 소환 | CI:3952-3982 |
| 보스05 텔레포트고스트 | 스킬(15%) 시 1초 페이드아웃 → 랜덤 x(≥400) 순간이동 → 1초 페이드인 | CI:4075-4079, 4852-4895 |
| 보스06 냠냠이 | 타깃 **즉사**(영웅 HP=0, 유닛 즉시 제거) | CI:3983-3999 |
| 보스07 도플갱어 | **영웅 공격만 받음**(유닛 타깃 불가). 공격 시 스킬 이펙트/투사체(관통3) | CI:751-753, 4000-4005, 4043-4048 |
| 보스08 스켈드래곤 | 브레스 범위 최대 3명, 25% 확률 빙결 3초 | CI:1514, 1541-1553, 4006-4013 |
| 보스09 서큐버스 | 키스 투사체 → 독 2000/초(최소 HP1까지, 10초) | CI:4014-4021, OI:467-468 |
| 보스10 데쓰나이트 | 범위 내 각 대상에 마법 오브젝트, 프레임15에 타격, **20%(DB303 fSkPct) 즉사**(영웅은 HP 1 남김) | CI:1554-1561, OI:304-313 |
| 보스 변신(iSkDst %) | **BOSS_13(다크독 서바이벌)만** HP ≤ iSkDst%(40%)에서 변신, 이후 공격 ×fSkDmg(5). 보스01~10은 iSkDst=0이라 미사용 | CI:6113-6116, 1202-1204 |
- 보스/영웅은 넉다운·빙결·개구리 등 대부분 CC 면역(`CheckKind(HERO|BOSS)` 검사) (CI:1140, OI:508).

### 4.5 토템(다크독 모드) [확인]
- 수명: 매초 `HP -= HPMax / fBigSt` → fBigSt = 자동소멸 시간(초) (닭 60, 고래 80, 소 150, 이글 35, 불도마뱀 70) (CI:6078-6091).
- 고래 TTM_04: fAtDly마다 강제 공격 (CI:6093-6099). 이글 TTM_07: 영웅 뒤 20px 따라다니며 fAtDly마다 돌진, 타깃 불가 (CI:2447-2469, 754-759).

---

## 5. 소환 [확인] AD:1300-1375, GM:555-589

- 비용: **`iMana_` 를 "식량"(m_fFoodCur)에서 차감** (마나는 메이스용) (AD:1314-1317).
- 쿨타임: `need = iCltm_ × (6 − Lv[13]) / 6` 초 (팔라독만 배수) (AD:1310-1313, GM:2667-2669). 소환 시 누적 0으로 리셋, UI 쿨타임 애니(`need / fTimeMul` 초) 종료 시 1000으로 세팅해 사용가능 (GM:469-501). 전투 시작 시 모두 사용가능(100) (GM:182-186).
- 조건: 식량 ≥ iMana_, 쿨 완료, 해당 유닛 레벨 ≥ 1 (GM:586).
- 스폰 위치: 일반 모드 x = 0 (+PlusX), y = `GetCreateCharY(iCLine)` 랜덤 밴드, line −1 (AD:1330, 803). 다크독 토템은 영웅 x 기준 (GameUILayer:1420-1421).
- **최대 유닛 수 제한 코드 없음** (grep `GetCount(true) >` 0건). 버튼 디바운스 0.1초 (GameUILayer:1407-1408).
- 식량 회복(팔라독): 0.1초마다 `(row4.fBigSc 0.2 + row4.fZmESt 0.05 × Lv[11]) × 경과초 × 10` → 기본 **2/초** (+0.5/Lv) (GM:728-775). 최대 식량 `40 + 40×Lv[12]` (+장비) (GM GetMaxFood).

| 유닛 | 식량 | 쿨(초) | 이속 | 사거리 iAtDst | iHtDst | fAtDly | fSkPct | fSkDmg | fSkKnd | iAt1Fr/iAt2Fr |
|---|---|---|---|---|---|---|---|---|---|---|
| 쥐 | 10 | 1 | 30 | 35 | 12 | 3.3 | 30 | 3 | 10 | 3/6 |
| 토끼 | 20 | 2 | 22 | 200 | 12 | 5 | 10 | 1 | 10 | 18/18 |
| 곰 | 30 | 4 | 23 | 50 | 16 | 2 | 10 | 1 (iSkDst105) | 10 | 8/12 |
| 캥거루 | 40 | 7 | 27 | 60 | 24 | 0 | 10 | 0.6 | 3 | 6/0 |
| 원숭이 | 70 | 15 | 21 | 120 | 12 | 6 | 5 | 1.2 | 10 | 5/5 |
| 거북이 | 50 | 10 | 24 | 30 | 30 | 0 | 0 | 0 | 0 | 0/0 |
| 코뿔소 | 100 | 20 | 28 | 70 | 25 | 1 | 20 | 3 | 100 | 7/10 |
| 펭귄 | 150 | 30 | 21 | 200 | 8 | 0.2 | 100 | 1 | 0 | 13/13 |
| 용 | 200 | 45 | 22 | 110 | 20 | 1 | 10 | 1.2 (iSkDst200) | 10 | 6/6 |
(db.txt [207]-[215]. 이속은 오오라 시 ×1.5 이상)

---

## 6. 기타 수치 요약 [확인]
- 영웅(팔라독) HP = 2000 + 1000×Lv[4] (+반지/갑옷) (GM:901-916); 이속 = 60 + 20×Lv[6] (GM:1004-1011); 5초마다 HP 재생 `row4.fAtDly×Lv0 + row4.fSkDmg(60)×Lv[5]` (GM:620-633).
- 영웅 피해 감소: ×(1 − 0.1×Lv[7]) (GM:2690).
- 적 스폰 간격: 스테이지 DB `iCreateSpeed11~12`(초기 UnitCount마리) / `21~22`(이후) 범위에서 0.1초 단위 랜덤 (SM CalcNextTime). 적 스폰 x = iScrollMax (SM:651).
- 사망 보상: `iRwGld/iRwExp × m_fStatMulVal × 난이도배수` (+스킬/반지) (CI:2941-2979 부근).

---

## 분석 불가 / 미확정
1. (해결) `iSkillLevelCur[n]` 인덱스별 스킬 이름 — [명세 03 §4](paladog-03-hero.md) 표 참조.
2. (해결) 유닛/토템 레벨표 행 오프셋 — 1.4 참조, 바이트코드로 `max(L-1,0)` 확인.
3. 보스05 순간이동 x 범위 식의 `Kakao.STATUS_INVALID_GRANT` 상수값 미확인 (CI:4871).
4. 영웅 메이스/다크독 검 개별 스킬(StateProcFist~SwordGold) 세부 타이밍·범위는 본 범위(유닛 전투)에서 일부만 확인(LIGHTNING 35, METEO/GOLD 60, WIND 150 px 범위 OI:662-727).
5. 애니 길이 기반 공격 주기 — MJA(파츠 애니) 사용 캐릭터(영웅, 보스01~10)는 `.mja` 파일 프레임 수를 확인하지 않음.
6. 튜토리얼 더미/깃발(258/259) 실제 kind 매핑은 상수 순서로만 추정.
