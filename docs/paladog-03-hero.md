# Paladog 명세 03 — 영웅 이동, 장비, 스킬, 오오라

> 근거 표기: Java 경로는 JADX 1.5.1 디컴파일 출력 `sources/` 기준 `파일:줄`(줄 번호는 디컴파일 결과 기준), `db.txt [n]` / `stage.txt [n]` = `assets/pdw_db.xml` / `assets/pdw_db_stage.xml`의 n번째 `<Data>` 레코드(0부터, `GetDBInfo(n)` / `GetDBInfoS(n)`와 동일). **[확인]** = 코드·데이터에서 직접 확인, **[추정]** = 정황 기반 해석. 전체 원본 값은 [부록 A](paladog-appendix-data.md), 분석 방법·종합 미해결 목록은 [인덱스](paladog-00-index.md) 참조.

## 0. 공통 식별자

| 항목 | 값 | 근거 |
|---|---|---|
| 영웅 종류 `hkHeroKind` | 0 = 팔라독, 2 = 다크독 | com/common/CM.java:2651-2653 [확인] |
| 캐릭터 kind | HERO_01=16842753(팔라독), HERO_02=16842755(다크독) | com/common/CM.java:1142-1143 [확인] |
| 영웅 DB 행 | HERO_01 → `[0]`, HERO_02 → `[2]` (`kind - HERO_01`) | com/common/AppDelegate.java:465-466 [확인] |
| kind 비트 | ALLY=16777216, ENEMY=33554432, HERO=65536, NPC(아군 유닛)=131072, ZOMBI=262144, BOSS=524288 | com/common/CM.java:1062-1223 [확인] |
| 레벨/스킬 배열 | `GI.iSkillLevelCur[0]` = **영웅 레벨**, `[1..23]`(팔라독) / `[1..24]`(다크독) = 스킬 레벨 | com/my/Game/GameManager.java:783-795, com/my/Layer/GameSkLvLayer.java:410-415 [확인] |

스킬 슬롯 번호 = (string_skill_ko_01.xml 인덱스) + 1 (팔라독), (인덱스 − 22) (다크독). 아래 4장 표 참조. 검증: 골드 보너스가 `iSkillLevelCur[2]`(상술), EXP 보너스가 `[1]`(보고배우기) — com/my/Char/CharInfo.java:2946, 2993 [확인].

---

## 1. 영웅 이동 / 공격 / HP / 사망 / 재생

### 1.1 입력 (좌/우 버튼)
- 화면(480×320 기준 좌표, y는 위에서 아래)에서 **왼쪽 버튼 x 7–125, 오른쪽 버튼 x 130–243, y 271–321** 터치 시 방향 결정. com/my/Layer/GameUILayer.java:1103-1104 (오른쪽, `lc_iDir = 1`), 1186 (두 버튼 범위) [확인]
- 터치 다운 처리 (com/my/Layer/GameUILayer.java:1114-1126) [확인]:
  ```java
  if (hkHeroKind == 0) {            // 팔라독
      if (lc_pCI.m_iState == 0 || lc_pCI.m_iState == 1) { lc_pCI.m_fDir = lc_iDir; lc_pCI.ChangeState(1); }
  } else { m_pPlayer.MoveStart(lc_iDir); }   // 다크독
  ```
- 손을 떼면 정지: 팔라독 `ChangeState(0)`, 다크독 `MoveStop()` (GameUILayer.java:1186-1232) [확인]
- 누른 채 다른 버튼으로 미끄러지면 방향 전환 (ccTouchesMoved, GameUILayer.java:1258-1295) [확인]
- 게임 모드 1(Destiny)/3(Tower)/6(Dungeon)/7 에서는 이동 버튼 비활성 (GameUILayer.java:1186) [확인]

### 1.2 팔라독 vs 다크독 이동 차이
- **팔라독**: 상태머신의 MOVE 상태(1)에서만 이동. 즉 **이동 중 메이스를 쓰면 이동 상태가 끊김**, 메이스 상태(2~23) 동안은 이동 버튼 무시(상태 0/1일 때만 수락). CharInfo.StateProcMove (com/my/Char/CharInfo.java:2416, 2530-2570) [확인]
- **다크독**: 상태와 독립된 `MoveProc`로 이동(`m_bMoving` 플래그). 공격 상태 중에도 이동 가능, 단 변신 상태(39) 제외. com/my/Char/CharInfo.java:6370-6455 [확인]
  ```java
  if (this.m_dwKind != HERO_02 || this.m_fHPCur <= 0.0f || this.m_iState == 39 || !this.m_bMoving) return false;
  ```
  다크독은 StateProcMove에서 즉시 return (CharInfo.java:2418) [확인]

### 1.3 이동 속도
- 기본 속도는 DB가 아니라 **하드코딩** (com/my/Game/GameManager.java:1004-1011) [확인]:
  ```java
  팔라독: (iSkillLevelCur[6] * 20) + 60   // [6] = 승마술
  다크독: (iSkillLevelCur[6] * 20) + 80   // [6] = 달리기
  ```
- 생성 시 `m_fMoveSpeed = GetMoveSpeed() * p_fScale` (com/common/AppDelegate.java:473), 스킬 습득 시 갱신 (GameManager.java:3908) [확인]
- 이동 시 가산: 반지(부적) "속도"(아이템번호 6)가 장착된 각 슬롯 3/4/5마다 `+GetRingSpeed(slot)` (= 10 + 5×등급) — 팔라독 CharInfo.java:2541-2551, 다크독 6395-6411 [확인]
- 다크독 변신 시 ×1.2 (`GetMulVal_TransformedSpeed`, GameManager.java:1324-1326) [확인]
- 팔라독/다크독은 오오라 이동 배율을 받지 않음(아군 유닛만 `m_bAura` 시 적용, CharInfo.java:2565-2567) [확인]
- 위치 갱신: `x += dir * speed * dt` (단위: 픽셀/초) [확인]

### 1.4 이동 범위 (X 경계)
- 좌측: `x <= -40` → -40 고정 (CharInfo.java:2572-2578, 6416-6418) [확인]
- 우측 (게임모드별, CharInfo.java:2598-2617, 6419-6436) [확인]:
  - 모드 0/4(일반 스테이지): 적 성(Castle) 존재 시 `iScrollMax - 160`, 보스 존재 시 `iScrollMax - 40`
  - 모드 2: `iScrollMax - 40`, 모드 5(서바이벌): `iScrollMax - 40`
  - 모드 1: `fScreenW - 40`
- 이동 사운드는 0.4초 주기 (CharInfo.java:6443-6450) [확인]

### 1.5 공격 방식
- **두 영웅 모두 자동 평타 없음**. 공격은 오직 하단 무기 버튼 3개(장착 슬롯 0/1/2)로 발동 [확인]
  - 팔라독 StateProcIdle은 공격 판정 없음; 다크독도 던전 모드(6)에서만 0.5초마다 근접 적 있으면 다크소드 상태(24) 자동 진입 (CharInfo.java:2387-2414) [확인]
  - DB `[0]` iAtPwr=200/iAtDst=250, `[2]` iAtPwr=200/iAtDst=80 은 영웅 평타용으로는 사실상 미사용 [추정] (메이스/검 데미지는 모두 별도 함수가 덮어씀, com/my/Char/ObjInfo.java:175-235)
- 버튼 → `UseMace(i)` (com/my/Layer/GameUILayer.java:1775-1900) [확인]:
  - 팔라독(아이템 kind MACE): 아이템번호 1..11 → 상태 2,3,4,14,15,16,17,18,19,20,23
  - 다크독(SWORD): 아이템번호 1..11 → 상태 24..34 + 즉시 `StateProcSwordXxx(0.1f)` 호출
- 사용 가능 조건 `CanUseMace` (GameManager.java:1051-1062) [확인]: 마나 ≥ 필요마나 (돈 메이스/돈 검=번호11은 골드 ≥ 필요량), 변신 중(39) 불가.
- **쿨타임 없음** — 마나만 게이트 (GameManager.java:3981-3992에서 마나/골드 차감만) [확인]
  ```java
  if (lc_iItemNum == 11 && m_iGamePlayKind != 3) { AD.AddGold(-lc_iNeedMP); return true; }
  m_fManaCur -= lc_iNeedMP;
  ```
- 메이스 사용 시 팔라독은 항상 오른쪽(`m_fDir = 1`)을 봄 (예: CharInfo.java:2692) [확인]
- 다크독 검 공격은 **영웅 x보다 오른쪽**(`target.x > obj.x`)이면서 `거리 ≤ 대상 HitDist + 검 사거리(iAtDst)` 인 같은 라인의 모든 적 (ObjInfo.java:671-703) [확인]

### 1.6 영웅 HP
- 팔라독 최대HP (하드코딩, GameManager.java:901-916) [확인]:
  ```java
  2000 + iSkillLevelCur[4]*1000 (+ 체력의 반지 각 슬롯 500+250g) (+ 기사 갑옷 500+250g)
  ```
  레벨 항은 `iSkillLevelCur[0] * 0` → **레벨업으로 HP 증가 없음** [확인]
- 다크독 최대HP (GameManager.java:917-931) [확인]:
  ```java
  DB[2].iMaxHP(3000) + DB[6].iMaxHP(1500) * iSkillLevelCur[4] (+ 체력부적 750+375g) (+ 다크독 기사 갑옷 500+250g)
  ```
- 레벨업/스킬 습득 시 HPMax 재계산 (GameManager.java:791, 3905) [확인]
- 영웅이 받는 피해 배율: `GetMulVal_Damage() = 1 - 0.1 × iSkillLevelCur[7]` (방어 스킬, 최대 5 → 50%) (GameManager.java:2690-2697, CharInfo.java:1178-1179, ObjInfo.java:252-253) [확인]
- 부활 후 10초 무적: `fRebirthSuperTick` 0~10초 동안 팔라독에 대한 피해 0 (CharInfo.java:1253-1255, GameManager.java:2627) [확인] (부활 아이템 흐름 자체는 범위 외)

### 1.7 사망 조건
- 매 프레임 `m_iGameStep == 5`(전투중)에서 `m_pPlayer.m_fHPCur <= 0` 이면 → 게임스텝 6(패배) (서바이벌 gkGameKind==2면 26) (GameManager.java:214-221) [확인]
- 영웅 사망 = 즉시 스테이지 패배 [확인]

### 1.8 영웅 재생 (HP / 마나 / 식량)
DB `[4]`(팔라독) / `[5]`(다크독) "리젠 수치들" (pdw_db.xml 해당 레코드 주석), 로드: GameManager.java:2719-2727, 2770-2778 [확인]

| 인덱스 | DB필드 | 의미 | 팔라독 `[4]` | 다크독 `[5]` |
|---|---|---|---|---|
| R0 | fAtDly | HP 재생 A | 0 | 240 |
| R1 | fSkDmg | HP 재생 B (×재생 스킬) | 60 | 100 |
| R2 | fSkPct | 마나 재생 기본 (0.1초당) | 0.2 | 0.7 |
| R3 | fSkKnd | 마나 재생 ×레벨 | 0 | 0 |
| R4 | fSdwSc | 마나 재생 ×기도 스킬 | 0.05 | 0.12 |
| R5 | fBigSc | 식량 재생 기본 (0.1초당) | 0.2 | 0.15 |
| R6 | fBigSt | 식량 재생 ×레벨 | 0 | 0 |
| R7 | fZmESt | 식량 재생 ×농업 스킬 | 0.05 | 0.05 |

- **HP 재생**: 5초마다 (GameManager.java:615-665) [확인]
  ```java
  팔라독: plus = R0 * iSkillLevelCur[0] + iSkillLevelCur[5] * R1;   // = 60 × 재생Lv
  다크독: plus = R0 + iSkillLevelCur[5] * R1;                       // = 240 + 100 × 재생Lv
  + 재생의 반지/재생부적(번호5) 슬롯마다 (30+15g)/(50+25g)
  + 기사 투구(헬멧 번호2) 30+15g
  ```
- **마나 재생**: 0.1초 누적마다 `m_fManaCur += calc * elapsed * 10` → calc는 "0.1초당 양" (GameManager.java:667-725) [확인]
  ```java
  팔라독: calc = R2 + Lv*R3 + iSkillLevelCur[9]*R4    // 0.2 + 0.05×기도 → 초당 2 + 0.5×기도
  다크독: calc = (R2 + Lv*R3 + iSkillLevelCur[10]*R4) * GetMulVal_AuraAPFast()   // 생기 오오라 배율
  + 기도의 반지/마나회복부적(번호8), 마법사 모자/마검사 써클릿, 무장 갑옷×오오라 내 유닛수
  ```
- **식량 재생**: 마나와 동일 구조, 농업 = 팔라독 `[11]`, 다크독 `[12]` (GameManager.java:727-777) [확인]
- 최대 마나: 팔라독 `100 + 50×[8]신앙심`, 다크독 `DB[2].iMana_(200) + DB[2].iCltm_(50)×[9]신앙심` (GameManager.java:935-967) [확인]
- 최대 식량: `40 + 40×식량창고` (팔라독 [12], 다크독 [11]) (GameManager.java:971-1000) [확인]
- 스테이지 시작 시 마나 0, 식량 0 (GameManager.java:153-157) [확인]

---

## 2. 장비 (Equipment)

### 2.1 슬롯 구조 (9칸)
com/common/CM.java:2795-2803 [확인]

| 슬롯 | 팔라독 | 다크독 | 아이템 kind 비트 |
|---|---|---|---|
| 0,1,2 | 메이스 (무기 버튼 1~3) | 검(Sword) | MACE 0x01000000 / SWORD 0x08000000 |
| 3,4,5 | 반지 | 부적(Amulet) | RING 0x02000000 / AMULET 0x10000000 |
| 6 | 투구 | 다크독 투구 | HELMET 0x40000000 / D_HELMET 0x90000000 |
| 7 | 갑옷 | 다크독 갑옷 | ARMOR 0x20000000 / D_ARMOR 0xA0000000 |
| 8 | 말 | 다크독 신발 | HORSE 0x80000000 / D_FOOT 0xB0000000 |

- 장착 제약 (ShopEquipLayer.java:1211-1230) [확인]: 무기는 0~2만, 반지/부적은 3~5만, 투구=6, 갑옷=7, 말/신발=8.
- **슬롯 5 잠금**: `iUnlockEquipSlot(Dark)` 필요, **슬롯 4 잠금**: `iUnlockEquipSlot02(Dark)` 필요 (ShopEquipLayer.java:1215-1230). 젬 상점 판매아이템 번호1(슬롯5, `GetGemItemPrice(1)=1000`젬), 번호8(슬롯4, 200젬) (ShopEquipLayer.java:1606-1612, 1664-1670; ItemManager.java:770-790) [확인]
- 아이템 ID 비트구조 (ItemManager.java:35-58, CM.java:2749-2774) [확인]:
  ```
  ID = kind(상위 8bit) | grade<<16 (8bit) | levelcap<<8 (미사용) | num (하위 8bit)
  ```

### 2.2 "(A)+(B)*등급" 공식의 적용
- DB 스키마 주석: `데미지 = 80(A) + 8(B) * 등급` (pdw_db.xml 해당 레코드 주석), `획득 경험치 + 10%(A) + 3(B) * 등급 %` (pdw_db.xml 해당 레코드 주석). 실제 수치는 각 행의 필드 쌍.
- 메이스/검 로드 (GameManager.java:2700-2709, 2750-2760) [확인]:
  ```
  V[n][0]=fAtDly(A1)  V[n][1]=fSkDmg(B1)    → 주효과 = A1 + B1*등급
  V[n][2]=fSkPct(A2)  V[n][3]=fSkKnd(B2)    → 부효과 (형태는 함수별 상이: +B*g 또는 +g/B)
  V[n][4]=fSdwSc(A3)  V[n][5]=fBigSc(B3)    → 필요 마나 = A3 + B3*등급 (B3은 전부 0)
  V[n][6]=iAtDst                              → 검 사거리 (다크독만)
  가격: fBigSt(=기본가), fZmESt(=등급² 계수)
  ```
- 반지/부적: `V[n][0..1]` 만 사용, 투구/갑옷/말: `[0]=fAtDly, [1]=fSkDmg, [2]=fBigSt, [3]=fZmESt` (GameManager.java:2728-2748) [확인]
- **실효 등급** (GameManager.java:1064-1082, 1268-1284) [확인]:
  ```java
  메이스: grade + iSkillLevelCur[22](메이스 마스터)   // 단 게임모드 1(Destiny)에서는 마스터리 미적용
  반지:   grade + iSkillLevelCur[23](링 마스터)
  검:     grade + iSkillLevelCur[23](웨폰 마스터리)
  부적:   grade + iSkillLevelCur[24](부적 마스터리)
  투구/갑옷/말: grade 그대로 (마스터리 없음)   (GameManager.java:4809-4831)
  ```

### 2.3 등급 범위 / 강화
- 강화 상한 `GetItemGradeLimit()` (ItemManager.java:811-822) [확인]:
  ```java
  if (gkGameKind == 2) return 100;          // 서바이벌
  int lc_iGradeMax = 5;
  for (i = 1..9) if (iStageStar[i*12 - 1] > 0) lc_iGradeMax += 5;   // 각 챕터(12스테이지) 마지막 클리어마다 +5 → 최대 50
  ```
- 강화 비용: **(현재등급+1)×2 젬** (GameManager.java:5882-5885), 강화는 등급 +1 (ShopEquipLayer.java:4170-4231) [확인]
- 장착 상태 강화는 슬롯 <6 (무기/반지)만 허용 (ShopEquipLayer.java:4176) [확인]; 인벤토리에서 투구 등을 강화할 수 있는지는 [추정: UI상 무기/반지 전용]
- 메이스 이펙트 텍스처 단계 = 등급/20 (AppDelegate.java:2307-2309) [확인] (시각효과만)

### 2.4 가격 필드 fBigSt / fZmESt
- **구매가(골드) = fBigSt + fZmESt × 등급²** — 메이스/반지(팔라독), 검/부적(다크독) (ItemManager.java:744-768, 60-262) [확인]
  ```java
  return (int) ((lc_iGrade * lc_iMulti * lc_iGrade) + lc_iBase);   // Base=fBigSt, Multi=fZmESt
  ```
- 판매가 = 구매가/2 (ItemManager.java:428-429) [확인]
- 투구/갑옷/말(신발)은 **젬으로 구매**, 가격은 하드코딩 Base(100~500), Multi=0 (ItemManager.java:73-258, ShopEquipLayer.java:1450-1458) [확인]. DB의 fBigSt=300(투구 등)은 미사용 [추정]
  - 판매가(골드) = Base + Base×0.1×등급² (ItemManager.java:264-330) [확인]
- 돈 메이스/돈 검(번호11): fBigSt=0 → 골드 상점 미판매, 젬 상점 판매아이템 번호3/7로 1젬 판매 (ShopEquipLayer.java:1622-1660, ItemManager.java:770-790) [확인]

### 2.5 반지(팔라독) / 부적(다크독) 효과
코드 함수 GameManager.java:1137-1236, 사용처 별도 표기. 등급 g = 실효등급. "슬롯마다"=장착 슬롯 3/4/5 각각 독립 합산 → **같은 반지 중복 장착 시 효과 중첩** [확인] (`IsRingItemNum(3..5, n)` 각각 더함)

| # | 반지 (db `[27..36]`) | 부적 (db `[67..76]`) | 공식 | 실제 적용 | 근거 |
|---|---|---|---|---|---|
| 1 | 경험의 반지 10+5g | 경험의부적 10+5g | (A+Bg)/100 | 처치 EXP × 비율 추가 | CharInfo.java:2997-3021 |
| 2 | 부자의 반지 10+5g | 부자부적 10+5g | (A+Bg)/100 | 처치 골드 × 비율 추가 | CharInfo.java:2947-2971 |
| 3 | 행운의 반지 0.5+0.25g | 행운부적 동일 | (A+Bg)/100 → 단위 %p | 아이템 드랍 확률 가산 | GameManager.java:1478-1506 |
| 4 | 체력의 반지 500+250g | 체력부적 750+375g | int | 최대HP 가산 | GameManager.java:904-912 |
| 5 | 재생의 반지 30+15g | 재생부적 50+25g | float | 5초마다 HP 회복 가산 | GameManager.java:633-656 |
| 6 | 속도의 반지 10+5g | 속도부적 10+5g | int | 영웅 이동속도 가산 | CharInfo.java:2541-2561 |
| 7 | 마나의 반지 30+15g | 마나부적 30+15g | float | 최대 마나 가산 | GameManager.java:938-963 |
| 8 | 기도의 반지 0.01+0.005g | 마나회복부적 0.024+0.012g | 0.1초당 | 마나 재생 가산 | GameManager.java:684-708 |
| 9 | 음식의 반지 0.01+0.005g | 음식회복부적 0.01+0.005g | 0.1초당 | 식량 재생 가산 | GameManager.java:738-764 |
| 10 | 곡간의 반지 20+10g | 음식부적 20+10g | int | 최대 식량 가산 | GameManager.java:974-996 |

- 주의: 행운 `GetRingLuck`은 /100 후 `lc_fAllow`(%)에 더해지므로 실제로는 +0.005%p 수준 — 코드상 그대로 [확인, 의도는 % 단위였을 것으로 추정]
- 드랍 판정: `rand%1000 < lc_fAllow*10`, `lc_fAllow = 1 + 0.5×보물탐지Lv + 행운…` (보스는 100) (GameManager.java:1470-1515) [확인]
- 반지 11~20번, 메이스 12~20번(db `[18..26]`, `[37..46]`, `[57..66]`, `[77..86]`)은 이름 없는 예비 행. 코드상 아이템번호 1..11만 상태/함수 매핑 → **미사용** [추정]

### 2.6 투구 / 갑옷 / 말(신발) 효과 (등급 g, 마스터리 없음)
**팔라독** — db `[87..96]`, `[107..111]`, `[127..131]`; 함수 GameManager.java:4833-4931

| 슬롯 | 번호/이름 | 값 | 효과 (적용 위치) |
|---|---|---|---|
| 투구 | 1 무장 투구 | 0.002+0.0005g | 식량 재생 += 값 × 오오라 내 아군 수 (GameManager.java:748-749) |
| 투구 | 2 기사 투구 | 30+15g | 5초마다 HP 재생 가산 (644-645) |
| 투구 | 3 마법사 모자 | 0.01+0.005g | 마나 재생(0.1초당) 가산 (694-695) |
| 투구 | 4 전사 투구 | 1+0.5g | 영웅이 피격될 때마다 마나 + 값 (피해량 무관) (GameManager.java:4933-4946, CharInfo.java:1268-1270) |
| 투구 | 5 네크로맨서 투구 | 1+0.5g | **아군 유닛이 죽을 때마다** 마나 + 값 (CharInfo.java:1322-1326, GameManager.java:4948-4961) |
| 투구 | 6 프로펠러 모자 | 0.5+0.25g | 드랍확률 %p 가산 (GameManager.java:1489-1490) |
| 투구 | 7 황금투구 | (10+5g)/100 | 처치 골드 추가비율 (CharInfo.java:2956-2957) |
| 투구 | 8 털모자 | 20+10g | 최대 식량 가산 (GameManager.java:983-984) |
| 투구 | 9 요리사 모자 | 0.01+0.005g | 식량 재생 가산 (751-752) |
| 투구 | 10 학사모 | (10+5g)/100 | 처치 EXP 추가비율 (CharInfo.java:3007-3008) |
| 갑옷 | 1 무장 갑옷 | 0.002+0.0005g | 마나 재생 += 값 × 오오라 내 아군 수 (697-698) |
| 갑옷 | 2 기사 갑옷 | 500+250g | 최대 HP 가산 (913-914) |
| 갑옷 | 3 마법사 의복 | 30+15g | 최대 마나 가산 (947-948) |
| 갑옷 | 4 전사 갑옷 | 1+0.5g | 피격 시마다 식량 + 값 (4963-4975) |
| 갑옷 | 5 네크로맨서 갑옷 | 1+0.25g | 아군 사망 시 식량 + 값 (4977-4985) |
| 말 | 1 무장 말 | 0.02+0.005g | 아군(영웅 제외) 공격력 × (1 + 값 × 오오라 내 아군 수) (CharInfo.java:1244-1246, ObjInfo.java:334-336) |
| 말 | 2 기사 말 | 0.9 − 0.008g | 영웅이 받는 피해 × 값 (**감산식**, `[1][0] - [1][1]*g`) (GameManager.java:4913-4916, CharInfo.java:1247-1249) |
| 말 | 3 유니콘 | 0.03+0.005g | 오오라 재생 틱(5초)마다 아군 HPMax × 값 추가 회복 (CharInfo.java:1089-1091) |
| 말 | 4 철갑마 | 0.1+0.01g | 피격 시 공격자에게 반사 피해 = 받은피해 × 값 (GameManager.java:4997-5013) |
| 말 | 5 백골마 | 30+15g | 아군 사망 시 영웅 HP + 값 (GameManager.java:4987-4995) |

**다크독** — db `[147..156]`, `[167..171]`, `[187..191]`; 함수 GameManager.java:5652-5800

| 슬롯 | 번호/이름 | 값 | 효과 |
|---|---|---|---|
| 투구 | 1 무장 | 0.002+0.001g | 식량 재생 += 값 × 오오라 내 적 수 (GameManager.java:765-766) |
| 투구 | 2 기사 | 30+15g | 5초마다 HP 재생 가산 (657-658) |
| 투구 | 3 전사 | 2+1g | 피격 시 마나 + 값 (5754-5763) |
| 투구 | 4 마검사 써클릿 | 0.01+0.005g | 마나 재생 가산 (710-711) |
| 투구 | 5 어쎄신 | 0.5+0.25g | 크리티컬 확률 +값(%) (CharInfo.java:1224-1225) |
| 투구 | 6~10 | 팔라독과 동일 값 | 프로펠러/황금/털모자/요리사/학사모 동일 효과 |
| 갑옷 | 1 무장 | 0.002+0.001g | 마나 재생 += 값 × 오오라 내 적 수 (713-714) |
| 갑옷 | 2 기사 | 500+250g | 최대 HP 가산 (929-930) |
| 갑옷 | 3 전사 | 2+1g | 피격 시 식량 + 값 (5765-5775) |
| 갑옷 | 4 마검사 로브 | 30+15g | 최대 마나 가산 (965-966) |
| 갑옷 | 5 어쎄신 | 5+0.4g | 회피 확률 +값(%) (CharInfo.java:1211-1212) |
| 신발 | 1 무장 | 0.02+0.005g | 다크독 공격력 × (1 + 값 × 오오라 내 적 수) (CharInfo.java:1240-1241) |
| 신발 | 2 기사 | 0.9 − 0.008g | 받는 피해 × 값 (CharInfo.java:1250-1251) |
| 신발 | 3 전사 | 0.01+0.001g | 반사 피해 = 받은피해 × 값 (GameManager.java:5777-5795) |
| 신발 | 4 마검사 | 5+3g | 가시 오오라 초당 피해 가산 (CharInfo.java:1098-1100) |
| 신발 | 5 어쎄신 | 1+0.5g | 크리티컬 시 데미지 × 값 추가 (CharInfo.java:1229-1230) |

### 2.7 세트 보너스 / 코스튬
- 투구/갑옷/말 동시 착용 조건을 검사하는 코드 없음 → **세트 보너스 없음** [확인: `IsEquipItemNum(6,x) && IsEquipItemNum(7,x)` 패턴 검색 결과 0건]
- 코스튬 = 장착 투구/갑옷/말 번호로 파츠 텍스처 교체(`paladog_head_%02d.plist`, `paladog_body_%02d`, `paladog_horse_%02d`), 메이스 텍스처 `mace_texture_%02d`, 메이스 이펙트 `mace_eff_texture_%02d` (등급/20) (com/common/AppDelegate.java:2293-2330; 다크독 2523-2525) [확인]
- 세이브 필드 `dwCostume`, `iCostumeCur` (CM.java:5494, 5500)는 정의만 있고 사용처 없음 [확인]

---

## 3. 무기 액티브 효과

### 3.1 팔라독 메이스 (db `[7..17]`, g = 메이스 실효등급)
필요마나 = `(A3 + B3*g) × (1 − 0.1 × 매직마스터Lv[10])`, 정수 절사 (GameManager.java:1018-1049). 돈 메이스는 골드 1000 고정(마스터 감소 없음) [확인]

| # | 이름 | 주효과 (A1+B1·g) | 부효과 | 마나 | 범위/동작 | 근거 |
|---|---|---|---|---|---|---|
| 1 | 신의주먹 | 데미지 80+20g | 관통 수 = 3 + g/20 (정수나눗셈) | 10 | 전방 투사체(OBJ_HERO_FIST), 적중마다 obj HP−1 | GameManager.java:1084-1092, CharInfo.java:2681-2721, ObjInfo.java:175-176, 557 |
| 2 | 힐 | 회복 600+40g | – | 30 | 같은 라인 아군 유닛+영웅, \|dx\| ≤ 150+HitDist | GameManager.java:1094-1097, CharInfo.java:2735-2778 |
| 3 | 턴언데드 | 데미지 60+15g | 즉사확률 (10×10 + 0.5×10×g)/1000 = (10+0.5g)% (보스 제외) | 50 | 영웅 앞 0 ≤ dx ≤ 300+HitDist 같은 라인 모든 적, BOSS_11 제외 | GameManager.java:1099-1105, ObjInfo.java:1137-1170 |
| 4 | 아이스 | 데미지 80+20g | 빙결 초 = 3 + g/5 (정수) (영웅/보스 면역) | 10 | 전방 투사체(OBJ_HERO_ICE) | GameManager.java:1107-1115, ObjInfo.java:508-519 |
| 5 | 라이트닝 | 데미지 240+60g | – | 30 | 250 이내 랜덤 근접 적 위치(없으면 x+250)에 낙뢰, 반경 35+HitDist | CharInfo.java:5007-5045, ObjInfo.java:662 |
| 6 | 파이어 | 데미지 80+20g | – | 15 | 영웅 기준 (적x − 영웅x) ≤ HitDist+180 인 같은 라인 모든 적 (`AttackArea`, state 16) | CharInfo.java:1159-1160, 1520-1524, ObjInfo.java:1179-1185 |
| 7 | 메테오 | 데미지 250+63g | – | 55 | 300 이내 최근접 적 위치+40(최대 300) 낙하, 반경 60+HitDist | CharInfo.java:5078-5119, ObjInfo.java:665 |
| 8 | 윈드 | 넉백거리 150+15g (`m_fKnockDownMul = dist/96`) | 넉다운 최대 수 = 3 + g/20 | 20 | 데미지 0, 150+HitDist 내 적을 넉다운(상태9), 보스 제외 | GameManager.java:1123-1131, ObjInfo.java:190-197, 724-727 |
| 9 | 음식 | 식량 + int(4 + 0.3g) | – | 20 | 즉시 식량 회복 | GameManager.java:1133-1136, CharInfo.java:5156-5185 |
| 10 | 독 (CHARM) | 초당 독 데미지 80+12g (fSkPct/fSkKnd 사용) | 최대 10초, HP 1 미만으로는 못 내림 | 5 | 전방 투사체(OBJ_HERO_CHARM) 적중 시 PoisonStart | GameManager.java:1138-1141, ObjInfo.java:462-466, CharInfo.java:5614-5634 |
| 11 | 돈 | 데미지 500+125g | 이 메이스로 죽인 적은 골드 1만 드랍(`m_bOneGoldForce`) | **골드 1000** | 메테오와 동일 낙하, 반경 60+HitDist | GameManager.java:1143-1146, ObjInfo.java:544-546, CharInfo.java:2930 |

- 공식 예 (GameManager.java:1084-1092) [확인]:
  ```java
  GetMaceFistAtk = (int)(V[0][0] + V[0][1]*g);
  GetMaceFistHP  = (int)(V[0][2] + (g / (int)V[0][3]));   // 3 + g/20
  GetMaceTurnUndeadDeadPercent = (int)(V[2][2]*10 + V[2][3]*10*g);   // 천분율
  ```
- 메이스 피해에도 오오라(전쟁/방어) 배율과 영웅 피해 감소 등이 곱해짐: obj가 생성자 `m_bAura`를 복사 (CharInfo.java:1778) — 다만 메이스 오브젝트는 영웅이 만든 것이고 영웅 `m_bAura`는 AuraProc 대상이 아니므로 false [추정]
- 메이스 사용은 퀘스트 카운트(16/17) 증가 (GameUILayer.java:1843-1844) [확인]

### 3.2 다크독 검 (db `[47..57]`, g = 검 실효등급)
필요마나 = `(A3 + B3*g) × (1 − 0.1 × 손재주Lv[8])` (GameManager.java:1043-1048) [확인]. 사거리 = iAtDst (GameManager.java:1318-1322). 공격판정: 영웅 오른쪽, `dx ≤ HitDist + 사거리` 같은 라인 전체 (ObjInfo.java:671-703) [확인]

| # | 이름 | 데미지 (A1+B1·g) | 부효과 | 마나 | 사거리 | 근거 |
|---|---|---|---|---|---|---|
| 1 | 다크 소드 | 12+3g | 피격 적 4프레임 미세 밀림(DarkSlide) | 4 | 105 | ObjInfo.java:352-354, CharInfo.java:6870-6887 |
| 2 | 윈드 레이피어 | 120+30g | 화살(OBJ_SWD02_ARROW), 관통 = 3 + g/20 | 40 | 500 | GameManager.java:1345-1353, CharInfo.java:5774 |
| 3 | 뱀파이어 소드 | 100+10g | 첫 적중 1회 데미지×1.12 만큼 영웅 HP 회복 | 50 | 105 | ObjInfo.java:355-362, GameManager.java:1355-1361 |
| 4 | 독 대거 | 40+10g | 화살(데미지0)→가스(반경 25+HitDist), 초당 40+10g 독, 최대 10초 | 40 | 250 | ObjInfo.java:216, 402-407, 487-492 |
| 5 | 자이언트 소드 | 150+38g | 20% 확률 넉다운(하드코딩 200/1000, DB fSkPct=50 미사용) | 50 | 125 | ObjInfo.java:408-413 |
| 6 | 영혼의 낫 | 100+5g | 첫 적중 1회 데미지×0.03 만큼 식량 회복 | 70 | 105 | ObjInfo.java:363-370 |
| 7 | 차원의 해머 | 120+30g | 적을 x ∈ [0, iScrollMax−160) 랜덤 위치로 순간이동(보스 제외) | 100 | 100 | ObjInfo.java:371-374 |
| 8 | 아이스 소드 | 120+30g | 빙결 1초 (fSkPct) | 60 | 105 | ObjInfo.java:375-385 |
| 9 | 화염의 검 | 60+15g | 화상 0.3초 간격 4회, 각 = 적중 데미지 | 80 | 150 | ObjInfo.java:386-396, CharInfo.java:6845-6868 |
| 10 | 토르의 해머 | 440+110g | 영웅 위치에 번개 이펙트(EFF_SWD10_A) 생성 후 범위 공격 | 150 | 180 | ObjInfo.java:931-944 |
| 11 | 돈 검 (`[57]` "11_ Sword") | 500+125g | 처치 시 골드 1 | **골드 1000** | 150 | ObjInfo.java:234-235, 544-546 |

- 다크독 검 공격에는 크리티컬/광폭/신발 배율이 적용 (ObjInfo.java:284-302) [확인]:
  ```java
  int lc_iCriticalPercent = GetCriticalPercent() * 10;               // 천분율
  if (IsEquipItemNum(6, 5)) lc_iCriticalPercent += (int)(10 * GetValue_DarkHelmetAssassin());
  if (lc_pCI4.m_iCritical <= lc_iCriticalPercent) { atk *= GetMulVal_CriticalPlus(); if (IsEquipItemNum(8,5)) atk *= GetValue_DarkFootAssassin(); }
  atk *= GetMulVal_AuraPlusAtk();   // 광폭 오오라
  ```
- 검 공격 시 다크독 애니 58(변신 시 115) (CharInfo.java:2372-2385) [확인]

---

## 4. 스킬 트리

### 4.1 레벨업 / 스킬포인트 / EXP 곡선
- **필요 누적 EXP = 현재레벨² × 100** (iCurExp는 누적, 차감 없음) (GameManager.java:782-796) [확인]:
  ```java
  int lc_iLv = iSkillLevelCur[0];
  int lc_iNeedExp = lc_iLv * lc_iLv * 100;
  if (iCurExp >= lc_iNeedExp) { cNeedSkillUp[lc_iLv] = 1; iSkillLevelCur[0]++; ...HPMax/ManaMax/FoodMax 재계산 }
  ```
  → Lv1→2: 100, Lv2→3: 400, Lv10→11: 10,000, Lv199→200: 3,960,100 (누적)
- 시작 레벨 1, 모든 스킬 0 (com/common/AppDelegate.java:4949-4953) [확인]
- 최대 레벨 200 (`iLevel2Allow` 시 999) (AppDelegate.java:4863, 4887) [확인]
- **레벨업 1회 = 스킬 1개 +1**: 레벨업 창(GameSkLvLayer)에서 3개 후보 중 하나를 선택(같은 칸 두 번 터치로 확정) (com/my/Layer/GameSkLvLayer.java:336-376) [확인]
- 후보 선정 규칙 (GameSkLvLayer.java:410-510) [확인]:
  - 미만렙 스킬이 3개 이하이면 그 전부
  - 레벨이 5의 배수일 때: 팔라독 [11]농업, [9]기도 + 순환 (`(Lv/5−1)%3` = 0→[19]오오라파워, 1→[12]식량창고, 2→[20]재생오오라). 다크독 [12]농업, [10]기도 + 순환(0→[17]약화오오라, 1→[11]식량창고, 2→[22]오오라파워)
  - 나머지 칸은 미만렙 스킬 중 중복 없이 랜덤
- 선택 후 `ApplySkill()`로 HPMax/이속/마나/식량/오오라 스프라이트 크기 즉시 반영 (GameManager.java:3895-3930) [확인]
- 스킬 초기화: 젬 1000 (`GetGemItemPrice(9)`), 모든 스킬레벨을 `iNhskpt`(자유 포인트)로 환급 → 스킬 화면에서 수동 분배 (com/my/Layer/SkillLayer.java:346-392, SkillScrollLayer.java:153-161, ShopEquipLayer.java:4900-4905) [확인]

### 4.2 팔라독 스킬 목록 (슬롯 = 문자열 인덱스 + 1)
최대레벨: com/common/AppDelegate.java:4863-4886 (괄호 = iLevel2Allow 시) [확인]. 효과는 하드코딩.

| 슬롯 | 이름 | Max | 레벨당 효과 (코드) | 근거 |
|---|---|---|---|---|
| 1 | 보고 배우기 | 9 (99) | 처치 EXP +20%/Lv (`0.2*Lv*exp`) | CharInfo.java:2993 |
| 2 | 상술 | 9 (99) | 처치 골드 +20%/Lv | CharInfo.java:2946 |
| 3 | 보물탐지 | 5 | 드랍확률 기본 1% + 0.5%p/Lv | GameManager.java:1479 |
| 4 | 체력 | 20 (99) | 최대HP +1000/Lv (기본 2000) | GameManager.java:903 |
| 5 | 재생 | 20 (99) | 5초마다 HP +60/Lv | GameManager.java:629 |
| 6 | 승마술 | 5 | 이속 +20/Lv (기본 60) | GameManager.java:1006 |
| 7 | 방어 | 5 | 받는 피해 −10%/Lv | GameManager.java:2690-2693 |
| 8 | 신앙심 | 10 (99) | 최대마나 +50/Lv (기본 100) | GameManager.java:937 |
| 9 | 기도 | 20 (99) | 마나재생 +0.05/0.1초 (=+0.5/초)/Lv (기본 2/초) | GameManager.java:677 |
| 10 | 매직 마스터 | 5 | 메이스 마나소모 −10%/Lv | GameManager.java:1044 |
| 11 | 농업 | 20 (99) | 식량재생 +0.5/초/Lv (기본 2/초) | GameManager.java:738 |
| 12 | 식량창고 | 10 (99) | 최대식량 +40/Lv (기본 40) | GameManager.java:973 |
| 13 | 리더쉽 | 3 | 유닛 생산 쿨타임 × (6−Lv)/6 | GameManager.java:2667-2669, 584 |
| 14 | 행진 오오라 | 5 | 오오라 내 아군 이속 × (1.5 + 0.5·Lv) | GameManager.java:827-830 |
| 15 | 전쟁 오오라 | 20 (99) | 오오라 내 아군 공격력 × (1 + 0.3·Lv) | GameManager.java:836-839 |
| 16 | 방어 오오라 | 5 | 오오라 내 아군 받는피해 × (1 − 0.1·Lv) | GameManager.java:854-857 |
| 17 | 활력 오오라 | 3 | 오오라 내 아군 공격딜레이 × (5 − Lv)/5 | GameManager.java:863-869, CharInfo.java:4393-4396 |
| 18 | 스킬 오오라 | 5 | 오오라 내 아군 스킬발동률 × (1 + 0.4·Lv) | GameManager.java:871-877, CharInfo.java:1637-1640 |
| 19 | 오오라 파워 | 3 | 오오라 반경 75 + 25·Lv | GameManager.java:2671-2676 |
| 20 | 재생 오오라 | 5 | 오오라 내 아군 5초마다 HPMax × 4% × Lv 회복 | GameManager.java:879-883, CharInfo.java:1086-1088 |
| 21 | 버서커 오오라 | 2 | HP≤30%일 때 공격 × (1+0.3·전쟁Lv) × (1 + 1.0·Lv) | GameManager.java:845-849, ObjInfo.java:162-167 |
| 22 | 메이스 마스터 | 5 | 메이스 실효등급 +Lv | GameManager.java:1070-1071 |
| 23 | 링 마스터 | 5 | 반지 실효등급 +Lv | GameManager.java:1080-1081 |

- 레벨 자체는 HP/마나/식량에 `*0` 계수로 기여 없음 [확인]

### 4.3 다크독 스킬 목록 (슬롯 = 문자열 인덱스 − 22)
최대레벨: AppDelegate.java:4900-4938. 수치는 DB `[6]` "스킬 수치들 (다크독)" (pdw_db.xml 해당 레코드 주석), 로드 GameManager.java:2779-2796 [확인]

DB `[6]` → `m_fSkillValue[]` 매핑:
```
S0=iMaxHP 1500 [체력/Lv]      S1=iMvSpd 10 [회피%/Lv]       S15=iCltm_ 5 [크리 기본%]
S2=iAtDst 1 [급소 크리%/Lv]   S3=fAtDly 5 [해부학 크리배율 기본] S4=fSkDmg 2 [해부학 배율/Lv]
S5=fSkPct 0.3 [부식]         S6=fSkKnd 0.08 [약화]          S7=fSdwSc 0.95 [방해 기본]  S8=fBigSc 0.09 [방해/Lv]
S9=iHtDst 2 [광폭]           S10=iTgDst 2 [생기]            S11=fZmESt 15 [가시/Lv]     S12=iAtPwr 10 [가시 기본]
S13=DB[2].iMana_ 200 [기본마나] S14=DB[2].iCltm_ 50 [신앙심/Lv]
```

| 슬롯 | 이름 | Max | 레벨당 효과 | 근거 |
|---|---|---|---|---|
| 1 | 보고배우기 | 9 (99) | EXP +20%/Lv | CharInfo.java:2995 |
| 2 | 상술 | 9 (99) | 골드 +20%/Lv | CharInfo.java:2960 |
| 3 | 보물탐지 | 5 | 드랍 1% + 0.5%p/Lv | GameManager.java:1493 |
| 4 | 체력 | 20 (99) | 최대HP +1500/Lv (기본 3000) | GameManager.java:919 |
| 5 | 재생 | 20 (99) | 5초마다 HP 240 + 100/Lv | GameManager.java:631 |
| 6 | 달리기 | 5 | 이속 +20/Lv (기본 80) | GameManager.java:1009 |
| 7 | 방어 | 5 | 받는 피해 −10%/Lv | GameManager.java:2695 |
| 8 | 손재주 | 3 | 검 마나소모 −10%/Lv | GameManager.java:1046 |
| 9 | 신앙심 | 10 | 최대마나 200 + 50/Lv | GameManager.java:952 |
| 10 | 기도 | 20 (99) | 마나재생 0.7 + 0.12/Lv (0.1초당 → 7 + 1.2/초) | GameManager.java:679 |
| 11 | 식량창고 | 10 (99) | 최대식량 40 + 40/Lv | GameManager.java:988 |
| 12 | 농업 | 20 (99) | 식량재생 0.15 + 0.05/Lv (0.1초당) | GameManager.java:755 |
| 13 | 회피 | 5 | 영웅 피격 회피 10%/Lv (`S1*Lv`%, 천분율 판정) | GameManager.java:1431-1433, CharInfo.java:1209-1220 |
| 14 | 급소 | 5 | 크리확률 5% + 1%/Lv | GameManager.java:1435-1437 |
| 15 | 해부학 | 10 (99) | 크리 데미지 배율 5 + 2·Lv (배) | GameManager.java:1439-1442 |
| 16 | 부식 오오라 | 5 | 오오라 내 적 받는피해 × (1 + 0.3·Lv) | GameManager.java:859-860 |
| 17 | 약화 오오라 | 5 | 오오라 내 적 공격력 × (1 − 0.08·Lv) | GameManager.java:841-842 |
| 18 | 방해 오오라 | 5 | 오오라 내 적 이속 × (0.95 − 0.09·Lv) | GameManager.java:831-832 |
| 19 | 광폭 오오라 | 5 | 다크독 공격 × (100 + 2·적수·Lv)/100 | GameManager.java:1421-1424 |
| 20 | 생기 오오라 | 5 | 마나재생 × (100 + 2·적수·Lv)/100 | GameManager.java:1426-1429, 681-683 |
| 21 | 가시 오오라 | 5 | 오오라 내 적 매초 (10 + 15·Lv) 피해 (+마검사 신발) | GameManager.java:884, CharInfo.java:1094-1111 |
| 22 | 오오라 파워 | 3 | 오오라 반경 110 + 33·Lv | GameManager.java:2675-2677 |
| 23 | 웨폰 마스터리 | 5 | 검 실효등급 +Lv | GameManager.java:1274-1275 |
| 24 | 부적 마스터리 | 5 | 부적 실효등급 +Lv | GameManager.java:1282-1283 |

- 회피/크리 판정은 천분율: `rand%1000 <= 회피% × 10` (CharInfo.java:1209-1213), 크리는 영웅의 `m_iCritical`(매 Process 프레임마다 `rand%1000` 갱신, CharInfo.java:460) ≤ 크리% × 10 (CharInfo.java:1222-1226) [확인]
- 해부학 Lv0에서도 크리 시 ×5 (S3=5) [확인 — 데이터 그대로]

---

## 5. 오오라 (Aura)

### 5.1 판정 (CharInfo.AuraProc, com/my/Char/CharInfo.java:1048-1113) [확인]
```java
if (hkHeroKind == 0 && !CheckKind(131072L)) return false;                    // 팔라독: 아군 NPC 유닛만
if ((hkHeroKind == 2 && !CheckKind(262144L) && !CheckKind(524288L)) ...) return false;   // 다크독: 좀비/보스(적)만
float lc_fDist = Math.abs(lc_pPlayer.m_vPos.x - this.m_vPos.x);
if (lc_fDist <= GetAuraDistance()) lc_bAura = true;
if (lc_pPlayer.m_iLine != this.m_iLine) lc_bAura = false;                   // 같은 라인만
```
- **반경**: 1차원 X거리. 팔라독 `75 + 25×오오라파워Lv` (최대 150), 다크독 `110 + 33×오오라파워Lv` (최대 209) (GameManager.java:2671-2679) [확인]
- 오오라 스프라이트 스케일: 팔라독 `(1.5 + 0.5·Lv)×0.5`, 다크독 `(1 + 0.3·Lv)×0.5` (GameManager.java:2681-2688) [확인]
- 진입/이탈 시 `GM.m_iAuraCount` ++/-- → **오오라 안에 있는 대상 수** (팔라독=아군 수, 다크독=적 수) (CharInfo.java:1066-1081) [확인]
- 오오라는 스킬 레벨 0이어도 항상 존재(스프라이트는 유닛 생성 시 부착, com/common/AppDelegate.java:506-511). 모드 3(타워)/6(던전)/7 일부 및 BOSS_11/12/13은 제외 [확인]
- 제외 상태: 사망(5)/제거대기(11) [확인]

### 5.2 효과 적용 대상과 중첩
- 플래그 `m_bAura`는 대상 개체별 bool 1개 → **오오라 중첩 개념 없음**(영웅 1명). 모든 오오라 스킬은 같은 반경 하나를 공유하고 동시에 적용 [확인]
- 배율은 곱연산으로 순차 적용: 예) 아군 공격 `atk × AuraWar(공격자 m_bAura)` × `AuraDefense(피격자 m_bAura)` (CharInfo.java:1168-1174) [확인]
- 투사체(ObjInfo)는 생성 시 생성자의 `m_bAura` 를 복사 (CharInfo.java:1778) → 원거리 유닛 탄도 오오라 보정 받음 [확인]
- **팔라독 오오라 특이점**: 아군 NPC 유닛은 **오오라 밖에서 스킬 발동 불가** (CharInfo.java:1641-1643) [확인]
  ```java
  if (CheckKind(131072L) && !this.m_bAura) lc_iVal = (int)(lc_fSkillP * 10.0f);   // 판정값을 임계값과 같게 → 발동 실패
  ```
- **팔라독 행진 오오라 Lv0 기본 ×1.5 이속** (공식 1.5 + 0.5·Lv) → 오오라 내 아군은 기본적으로 1.5배 빠름 [확인]
- 버서커(21)는 `ObjInfo.AttackProc`(투사체)에서만 체크되고, 체크 대상 HP가 투사체 자신의 HP(DB 값)임 → 근접 유닛에는 사실상 미적용 [추정: 원본 버그 가능성]

### 5.3 주기 효과
- 팔라독 재생 오오라: 오오라 진입 후 5초마다 `HP += HPMax × 0.04 × 재생오오라Lv` (+유니콘) (CharInfo.java:1084-1094) [확인]
- 다크독 가시 오오라: 1초마다 `HP -= 10 + 15×Lv (+ 마검사 신발 5+3g)`, 사망 처리 포함, 영웅이 살아있을 때만 (CharInfo.java:1094-1111) [확인] (Lv0이어도 10 피해 [확인])

### 5.4 다크독 오오라는 적 디버프
| 오오라 | 적용 지점 | 근거 |
|---|---|---|
| 부식 | 피격 적 `m_bAura` → `atk × (1+0.3Lv)` (GetMulVal_AuraDefense를 적용하는 같은 코드 경로) | CharInfo.java:1172-1174 |
| 약화 | 공격하는 적 `m_bAura` → `atk × (1−0.08Lv)` | CharInfo.java:1168-1170 |
| 방해 | [추정] 적 이동에 GetMulVal_AuraMove 적용 — 단 StateProcMove의 `else if (m_bAura)` 분기(2565)는 영웅이 아닌 모든 개체 대상이므로 적에게도 적용됨 → 기본값 0.95 (Lv0에서도 5% 감속) | CharInfo.java:2565-2567 |
| 광폭/생기 | 오오라 내 적 수(`m_iAuraCount`) 비례 | GameManager.java:1421-1429 |

---

## 6. 영웅 레벨 / EXP 요약
- 곡선: 누적 EXP ≥ Lv²×100 → 레벨업 (GameManager.java:784-786) [확인]
- 처치 EXP = `DB.iRewardExp × m_fStatMulVal × 난이도배율 × lc_fMulCleared` (+보고배우기 20%/Lv, 경험의 반지, 학사모) (CharInfo.java:2977-3021) [확인]
- 초기 EXP/GOLD = 0 (`[3]` 초기 수치들, pdw_db.xml 해당 레코드 주석; AppDelegate.ResetForNewGame 4942-4953) [확인]
- 레벨업 보상 = 스킬 선택 1회뿐 (HP 등 레벨 직접 보너스 없음) [확인]
- 900초(15분) 이상 경과 시 모드≠5에서 처치 골드 1 고정, EXP 0 (CharInfo.java:2905-2906, 2929, 2973) [확인]

---

## 7. 핵심 수치 요약 (Roblox 구현용)

| 항목 | 팔라독 | 다크독 |
|---|---|---|
| 기본 HP | 2000 (+1000/체력Lv) | 3000 (+1500/체력Lv) |
| 기본 이속 (px/s) | 60 (+20/승마Lv) | 80 (+20/달리기Lv) |
| 기본 최대마나 | 100 (+50/신앙Lv) | 200 (+50/신앙Lv) |
| 마나 재생/초 | 2 (+0.5/기도Lv) | 7 (+1.2/기도Lv) |
| 최대 식량 | 40 (+40/Lv) | 40 (+40/Lv) |
| 식량 재생/초 | 2 (+0.5/농업Lv) | 1.5 (+0.5/농업Lv) |
| HP 재생 (5초) | 60×재생Lv | 240 + 100×재생Lv |
| 오오라 반경 | 75 + 25×Lv | 110 + 33×Lv |
| 무기 | 메이스 3슬롯 (원거리/광역 마법) | 검 3슬롯 (근접~중거리) |
| 이동 중 공격 | 불가 (상태머신) | 가능 (MoveProc 분리) |

---

## 분석 불가 / 미확인
1. (해결) `m_iCritical`은 CharInfo.Process에서 매 프레임 0~999 난수 (CharInfo.java:460).
2. 영웅 Y좌표/라인 결정(다중 라인 모드에서 영웅 라인 변경 여부) — 이번 범위에서 미추적.
3. (부분 해결) 다크독 변신·함성·가시의 레벨별 수치는 [명세 05 B5](paladog-05-growth.md) 토템 표(`GameManager.java:1291-1344`)에서 확인. 애니메이션 타이밍 등 연출 세부는 미추적.
4. 부활(Rebirth) 아이템 사용 흐름(`AddRebirth`, GameManager.java:2600-2650 주변) 세부.
5. 인벤토리에서 투구/갑옷/말 강화가 UI상 가능한지 (TryEnchant는 kind 검사 없음) — ShopEquipLayer `ToEnchant` 진입 조건 미확인.
6. 메이스 투사체(신의주먹/아이스/독)의 이동 속도·최대 사거리 — ObjInfo.StateProcMove의 DB 행(투사체용 DB 레코드) 미매핑.
7. 게임 모드 3(타워)에서 메이스 버튼이 유닛 생성/전체 회복으로 바뀌는 대체 동작 (GameUILayer.java:1776-1801)은 영웅 범위 밖으로 간주.
8. `GetSwordPoisonTime`(fSkPct=5), `GetSwordGiantKnockDownPercent`(50) 등 DB 값은 호출처 없음 → 실제 미사용으로 판단했으나 다른 경로 사용 가능성 배제 못함.
9. 방해 오오라가 적에게 적용되는 경로는 StateProcMove 공통 분기에 의존 [추정] — 적이 별도 이동 함수를 쓰는 경우(보스 등) 적용 여부 미확인.
