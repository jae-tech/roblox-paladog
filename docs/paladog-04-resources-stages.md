# Paladog 명세 04 — 자원 생산·소모, 스테이지와 적 생성 규칙

> 근거 표기: Java 경로는 JADX 1.5.1 디컴파일 출력 `sources/` 기준 `파일:줄`(줄 번호는 디컴파일 결과 기준), `db.txt [n]` / `stage.txt [n]` = `assets/pdw_db.xml` / `assets/pdw_db_stage.xml`의 n번째 `<Data>` 레코드(0부터, `GetDBInfo(n)` / `GetDBInfoS(n)`와 동일). **[확인]** = 코드·데이터에서 직접 확인, **[추정]** = 정황 기반 해석. 전체 원본 값은 [부록 A](paladog-appendix-data.md), 분석 방법·종합 미해결 목록은 [인덱스](paladog-00-index.md) 참조.

## 0. 게임 모드(m_iGamePlayKind) 매핑 [확인]

스테이지 번호 `s`(1~120)의 `s % 12`로 결정된다 (`com/my/Layer/GameLayer.java:99-121`).

| s % 12 | 팔라독 (hk=0) | 다크독 (hk=2) | DB 접미사 |
|---|---|---|---|
| 0 (12,24,…) | 4 = 보스(B) | 4 = 보스(B) | B |
| 3 (3,15,…) | 1 = 운명(Destiny, D) | 7 = 멧돼지점프(J) | D / J |
| 6 (6,18,…) | 2 = 목마(W, 호위) | 2 = 목마(W, 파괴) | W |
| 9 (9,21,…) | 3 = 타워(T) | 6 = 던전(DG) | T / DG |
| 그 외 | 0 = 일반 | 0 = 일반 | (없음) |
| 서바이벌 | 5 (gkGameKind==2일 때 덮어씀, `GameLayer.java:131-137`) | 5 | 서바이벌 n |

- 모드별 전역 스케일: T=0.6, DG=0.7, 그 외 1.0 (`GameLayer.java:139-145`). [확인]
- 보스 스테이지(s%12==0)는 BGM 2, 나머지 BGM 1 (`GameLayer.java:122-129`). [확인]

### 0-1. 스테이지 → DB 행(row) 선택 (`com/my/Game/StageManager.java:95-176`) [확인]

```java
// 다크독 목마(W)
lc_iS = ((m_iCurStage - 6) / 12) + 120 + 20 + 50;            // 190~199
// 던전(DG, kind 6)
lc_iS = ((m_iCurStage - 9) / 12) + 120 + 20 + 50 + 10;       // 200~209
// 점프(J, kind 7)
lc_iS = ((m_iCurStage - 3) / 12) + 120 + 20 + 50 + 10 + 10;  // 210~219
// 다크독 전용 교체 스테이지: 1,2,4,5,7,8,10,11,36,65,67,72,82,84,108,113,115,116,118,119,120 → 220~240
// 그 외
m_pDBIS = GetDBInfoS(m_iCurStage - 1);                        // 0~119
```
- 운명(D) 보조행: `lc_iDStage = ((s-3)/12)*2 + 120` → `[120+2k]` = `-mace`행, `[121+2k]` = `-unit`행 (`StageManager.java:209-216`).
- 서바이벌: `GetDBInfoS(GetWaveDBPos(wave) + 140)` → 140~189 (`StageManager.java:177-187`).

---

## 1. 전투 중 자원

### 1-1. 자원 종류와 용도 [확인]

| 자원 | 필드 | 소비처 | 근거 |
|---|---|---|---|
| 식량(Food, "고기") | `m_fFoodCur/m_fFoodMax` | **유닛 소환**. 유닛 DB의 `iMana_` 값을 식량에서 차감 | `common/AppDelegate.java:1318` (`m_fFoodCur -= lc_pDBI.m_iMana`), 버튼 활성 판정 `com/my/Game/GameManager.java:586` |
| 마나(MP, 다크독은 AP) | `m_fManaCur/m_fManaMax` | **메이스(다크독=검) 스킬** 사용 | `GameManager.java:3983-3993` (`UseManaForMace`) |
| 골드 | `g_GI.iCurGold` | 11번 "돈 메이스"는 마나 대신 골드 소모 | `GameManager.java:3987-3989` |

- 즉 DB 컬럼명이 `iMana_(마나)`지만 유닛 소환 비용은 실제로 **식량**에서 빠진다. [확인]
- 유닛 소환 조건: `식량 >= iMana_` AND `쿨타임 누적 >= iCltm_ × 쿨타임배수` AND `유닛레벨 > 0` (`GameManager.java:579-594`). 팔라독 유닛 DB = `[207+n]`, 다크독 토템 = `[216+n]` (`GameManager.java:579`). [확인]
- 쿨타임 누적은 전투 시작 시 100초로 초기화되어 시작 직후 즉시 소환 가능 (`GameManager.java:180-183`). [확인]
- 다크독 던전(kind 6)에서 버튼 1/4/8은 함정(바나나 껍질/지뢰/화염 지뢰)이며 **마나**(DB `[292..294]` iMana_ = 20/50/100) 소모 (`GameManager.java:556-578`, db.txt [292]-[294]). [확인]
- 타워 모드(kind 3)에서는 장착 메이스가 아니라 고정 비용: 0·1번 버튼 90 MP, 2번 30 MP (`GameManager.java:1021-1025`). 1번은 "5유닛 일괄 소환"에 사용 (`com/my/Layer/GameUILayer.java:2262-2270`). [확인]

유닛 식량 비용/쿨타임 (db.txt [207]-[224]) [확인]:

| 팔라독 유닛 | 쥐 | 토끼 | 곰 | 캥거루 | 원숭이 | 거북이 | 코뿔소 | 펭귄 | 용 |
|---|---|---|---|---|---|---|---|---|---|
| 식량 | 10 | 20 | 30 | 40 | 70 | 50 | 100 | 150 | 200 |
| 쿨타임(초) | 1 | 2 | 4 | 7 | 15 | 10 | 20 | 30 | 45 |

| 다크독 토템 | 닭 | 2 | 멧돼지 | 고래 | 5 | 소 | 이글 | 불도마뱀 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| 식량 | 10 | 20 | 30 | 40 | 50 | 70 | 100 | 150 | 200 |
| 쿨타임 | 1 | 2 | 4 | 12 | 15 | 30 | 35 | 50 | 70 |

### 1-2. 초기값 [확인]

```java
// GameManager.Reset()  (com/my/Game/GameManager.java:153-158)
this.m_fManaMax = GetMaxMP();
this.m_fManaCur = 0.0f;
this.m_fFoodMax = GetMaxFood();
this.m_fFoodCur = 0.0f;
```
- 매 스테이지 시작 시 마나/식량 0에서 시작. 서바이벌은 웨이브 간 마나·식량·킬수를 백업/복원하여 이어간다 (`StageManager.java:76-87,183-186`). [확인]
- 부활(rebirth) 시 식량·마나를 최대치로 채운다 (`GameManager.java:2442-2443, 2585-2586`). [확인]

### 1-3. 최대치 공식 [확인] (스킬 이름은 [추정])

`iSkillLevelCur[k]`: k=0은 히어로 레벨, 나머지는 스킬 레벨.

| 항목 | 팔라독 | 다크독 | 근거 |
|---|---|---|---|
| HP 최대 | `2000 + sk[4]*1000` (+반지/갑옷) | `DB[2].iMaxHP(3000) + DB[6].iMaxHP(1500)*sk[4]` | `GameManager.java:901-933` |
| 마나 최대 | `100 + sk[8]*50` (+반지/갑옷) | `DB[2].iMana_(200) + sk[9]*DB[2].iCltm_(50)` | `GameManager.java:935-969`, 다크독 값 출처 `GameManager.java:2793-2795` |
| 식량 최대 | `40 + sk[12]*40` (+반지/투구) | `40 + sk[11]*40` | `GameManager.java:971-1002` |

### 1-4. 리젠 공식 ("리젠 수치들", db.txt [4] 팔라독 / [5] 다크독) [확인]

DB 스키마 주석: `HP : 0(A) + [재생] * 100(B)` (pdw_db.xml 해당 레코드 주석). 실제 계수 매핑은 `LoadMaceRingValueFromDB` (`GameManager.java:2719-2727` 팔라독, `2770-2778` 다크독):

| regen[] | DB 필드 | 팔라독 [4] | 다크독 [5] | 의미 |
|---|---|---|---|---|
| 0 | fAtDly | 0 | 240 | HP 기본(A) |
| 1 | fSkDmg | 60 | 100 | HP 스킬당(B) |
| 2 | fSkPct | 0.2 | 0.7 | MP 기본(A) |
| 3 | fSkKnd | 0 | 0 | MP 레벨당(B) |
| 4 | fSdwSc | 0.05 | 0.12 | MP 스킬당(C) |
| 5 | fBigSc | 0.2 | 0.15 | 식량 기본(A) |
| 6 | fBigSt | 0 | 0 | 식량 레벨당(B) |
| 7 | fZmESt | 0.05 | 0.05 | 식량 스킬당(C) |

```java
// HP: 5초마다 1회 (GameManager.java:619-666)
if (m_ctHPRegenTime >= 5.0f) {
  팔라독: plus = regen[0]*Lv + sk[5]*regen[1];      // = 0*Lv + sk5*60
  다크독: plus = regen[0]   + sk[5]*regen[1];      // = 240 + sk5*100
}
// MP: 0.1초 누적마다 (GameManager.java:668-727)
calc = regen[2] + Lv*regen[3] + sk[9 or 10]*regen[4];   // 팔라독 sk9, 다크독 sk10
if (다크독) calc *= GetMulVal_AuraAPFast();
m_fManaCur += calc * m_ctMPRegenTime * 10.0f;              // → 초당 calc*10
// 식량: 0.1초 누적마다 (GameManager.java:729-780)
calc = regen[5] + Lv*regen[6] + sk[11 or 12]*regen[7];  // 팔라독 sk11, 다크독 sk12
m_fFoodCur += calc * m_ctFoodRegenTime * 10.0f;
```
초당 환산 (장비 보너스 제외):
- 팔라독: MP **2.0/s + 0.5/s × sk9**, 식량 **2.0/s + 0.5/s × sk11**, HP **+60 × sk5 / 5초** (기본 재생 0). [확인]
- 다크독: AP **7.0/s + 1.2/s × sk10** (× 오라 배수), 식량 **1.5/s + 0.5/s × sk12**, HP **(240 + 100×sk5) / 5초**. [확인]
- MP/HP 리젠은 플레이어 HP>0일 때만, 식량 리젠은 플레이어 존재만 조건 (`GameManager.java:621,670,731`). [확인]
- 반지(기도/식량/재생), 투구(마법사/요리사/팔), 갑옷(팔) 장비가 가산 (`GameManager.java:633-661, 685-715, 739-770`). [확인]

### 1-5. 메이스(스킬) 마나 비용 [확인]

```java
// GameManager.GetNeedMPForMace (GameManager.java:1018-1049)
lc_fBase = m_fMaceValue[itemNum-1][4];   // DB fSdwSc
lc_fMul2 = m_fMaceValue[itemNum-1][5];   // DB fBigSc
if (itemNum == 11) return (int) lc_fBase;              // 돈 메이스: 고정(골드)
val = lc_fBase + lc_fMul2 * grade;
mul = 1 - sk[10]*0.1 (팔라독) / 1 - sk[8]*0.1 (다크독);
return (int)(val * mul);
```
- 메이스 DB는 팔라독 `[7..26]`, 다크독 검 `[47..66]` (`GameManager.java:2701-2710, 2752-2761`). 예: 01 신의주먹 base 10, 02 힐 30, 07 메테오 55, 11 돈 메이스 1000(골드) (db.txt [7]-[17] fSdwSc). [확인]
- 09 음식 메이스: 식량 즉시 보충 (`com/my/Char/CharInfo.java:5180` `m_fFoodCur = m_fFoodMax`) [확인, 발동 조건 세부는 분석 범위 밖].

---

## 2. 전투 외 자원

### 2-1. 초기 골드/EXP [확인]
- 새 게임: `iCurGold = 0`, `iCurExp = 0`, 스테이지 1만 개방 (`common/AppDelegate.java:4943-4944, 4960-4963`).
- db.txt [3] "초기 수치들"(EXP=id____, GOLD=iPlusX)은 값 99999/0이며 골드/EXP 초기화에 쓰는 코드는 찾지 못함 → **미사용** [추정]. (`CharInfo.InitializeExt`가 `GetDBInfo(3)`을 쓰지만 이는 더미 DB 참조 용도, `CharInfo.java:292-295`.)
- 상한: GOLD_MAX 999,999,999 / GEM_MAX 99,999 (`common/CM.java:110-111`). [확인]

### 2-2. 처치 보상 iRwGld / iRwExp (`com/my/Char/CharInfo.java:2893-3010`) [확인]

```java
lc_fMulCleared = (이미 별>0로 클리어한 스테이지 && 서바이벌 아님) ? 0.5f : 1.0f;   // :2899-2901
if (서바이벌 아님 && m_fPlayTime >= 900.0f) lc_bForceOne = true;                   // :2905-2906
if (lc_bForceOne) AddGold(1);           // 15분 초과 시 골드 1, EXP 0
gold = iRwGld * m_fStatMulVal * GetMulVal_Gold_Dfct() * lc_fMulCleared;            // :2941-2943
gold += 0.2 * sk[2] * gold  (+반지 Rich, 투구 Gold)                                 // :2946
exp  = iRwExp * m_fStatMulVal * GetMulVal_Exp_Dfct() * lc_fMulCleared;             // :2979-2981
exp  += 0.2 * sk[1] * exp   (+반지 Exp, 투구 Scholar, 플랫폼 VIP 5~10%)             // :2983-2995
```
- 서바이벌: 골드는 `iRwGld × 1.0 × 난이도(보통 고정)`, EXP는 `iRwExp × 1 × 1 × fSVVExpMulVal` (`CharInfo.java:2939,2977`). 보스가 소환한 졸개는 골드 1/EXP 0 (`CharInfo.java:2893-2895`). [확인]
- 난이도 배수 (`GameManager.java:2839-2885`) [확인]:

| 난이도 | 적 HP(유닛·본진) | 골드 | EXP | 점프 속도 |
|---|---|---|---|---|
| 0 | ×0.7 | ×2.0 | ×1.5 | ×0.95 |
| 1 | ×1.0 | ×1.0 | ×1.0 | ×1.0 |
| 2 | ×1.4 | ×0.8 | ×0.5 | ×1.05 |
| 3 | ×1.0 (switch default — 지옥에서 HP 배수 없음) | ×0.6 | ×0.4 | ×1.1 |

- 적 보상 DB 예 (db.txt [225]-[254]): 좀비 18G/12EXP … 갑옷방패 162G/43EXP, 보스 좀비킹 200G/50EXP … 데쓰나이트 1200G/300EXP. [확인]

### 2-3. 히어로 레벨업 [확인]
```java
// GameManager.LevelUpProc (GameManager.java:782-795)
int lc_iNeedExp = lc_iLv * lc_iLv * 100;   // 누적 EXP 기준
if (iCurExp >= lc_iNeedExp) { iSkillLevelCur[0]++; HP/MP/식량 최대치 재계산; 스킬포인트 플래그 }
```
- 레벨 상한 200 (iLevel2Allow 시 999) (`common/AppDelegate.java:4863,4888,4902,4928`). [확인]

### 2-4. 스테이지 클리어 보상과 별(★) [확인]
- **iCrRwd(스테이지 클리어보상)는 코드에서 읽히지 않는다.** `m_iClearReward`는 XML 리더에서만 대입 (`com/my/DB/MyXMLReaderS.java:141`) — 다른 참조 없음. [확인]
- 클리어 시 `m_iRewardTemp = 0` 후 별 수에 따라 ×0.5/×1/×2 해서 AddGold → 항상 0 (`GameManager.java:1975-1987`). [확인]
- 실제 클리어 골드/아이템은 **퀘스트 DB(DBInfoQ)** 의 3개 퀘스트(메인·서브1·서브2) 보상: 성공한 퀘스트마다 `GetRewardGold` 또는 보상 아이템 지급 (`GameManager.java:1991-2001`, `com/my/Game/QuestManager.java:89-103`). [확인]
- 별 = 성공한 퀘스트 수(0~3) (`GameManager.java:1966-1971`). 최고 기록만 저장 (`GameManager.java:2037-2039`). [확인]
- **iCrSec / iCrS2_(클리어 시간)도 별 계산에 쓰이지 않는다.** `m_iClearSecond`는 저장/로드만 됨 (`StageManager.java:189-190`, `common/AppDelegate.java:6194-6195, 6271-6272`). 시간 조건 별은 퀘스트 타입 10 (`VarA*60 + VarB` 초 이내) (`QuestManager.java:643-650`). [확인]
- 따라서 리메이크 시 별 기준·클리어 골드는 퀘스트 DB(`assets/quest.xml` 팔라독, `assets/quest_d.xml` 다크독)에서 가져와야 한다 — 구조·보상 총액·퀘스트 타입 17종은 [명세 05 B10](paladog-05-growth.md) 참조. iCrSec은 기획 참고치로만 쓸 수 있음 [추정].

### 2-5. 보석(Gem)/기타 [확인]
- 드랍: 일반 적 처치 시 `rand%1000 < (1 + 0.5*sk[3] + 반지/투구 Luck)*10` → 약 (1+0.5×sk3)% 확률 아이템 드랍, 보스는 100% (`GameManager.java:1470-1517`).
- 서바이벌 보스 처치: 보석 `wave/30 + 1`(최대 15) 지급 (`GameManager.java:1518-1540`).
- 서바이벌 부활: 보석 20 소모 (`com/my/Layer/GameLayer.java:1152-1157`). 일반 모드 사망 시에도 보석 20 이상이면 부활창 자동 표시 플래그 (`GameManager.java:1863-1867`, step 6) [확인].
- 업적 보상 보석 (`GameManager.java:4285, 4516`), IAP (`common/AppDelegate.java:7554-7594`). [확인]

---

## 3. 적 스폰 알고리즘 (`com/my/Game/StageManager.java`)

### 3-1. 다음 스폰까지의 간격 CalcNextTime (`StageManager.java:230-261`) [확인]

```java
if (kind == 1 /*D*/ || kind == 6 /*DG*/) {
    if (Total < 10 || (Total >= 20 && Total <= 30)) { 전반(iCSp11~12) } else { 후반(iCSp21~22) }
} else if (m_iCreatedEnemyCount < m_pDBIS.m_iUnitCount) {   // iUCnt_
    iRange = iCSp12 - iCSp11 + 1;  iStart = iCSp11;           // 전반
} else {
    iRange = iCSp22 - iCSp21 + 1;  iStart = iCSp21;           // 후반
}
m_ctNeedTickForCreateEnemy = ((rand%10000) % (iRange*10)) / 10.0f + iStart;
// D/DG: Total이 10/20/30이면 간격 강제 5.0초, 10/30에서 경고음+진동
```
- 간격 = **[min, max+0.9] 초, 0.1초 단위 균등 난수**. 예: iCSp11=5, iCSp12=5 → 5.0~5.9초; iCSp21=0, iCSp22=1 → 0.0~1.9초. [확인]
- 첫 적은 `StartStage` 끝의 `CalcNextTime()`으로 전반 간격 후 등장 (`StageManager.java:226`). [확인]
- 서바이벌(kind 5)은 `m_iSVVMode == 4`일 때만 계산·스폰 (`StageManager.java:233, 267-281`). [확인]

### 3-2. 전반/후반 사이클 (iUCnt_ 분기점) [확인]

```java
// CreateEnemyProc (StageManager.java:332-355)
CreateEnemy(lc_iIndex, 100, 0.0f);
m_iCreatedEnemyCount++; m_iCreatedEnemyCountTotal++; m_iEnemyCountForFifth++;
if (kind != 5 && kind != 6 && m_iCreatedEnemyCount >= iUnitCount * 2) m_iCreatedEnemyCount = 0;
CalcNextTime();
```
- 일반/W/T/B: **iUCnt_ 마리는 느린 간격(전반), 다음 iUCnt_ 마리는 빠른 간격(후반, 사실상 러시), 다시 반복**하는 무한 웨이브. 승리 조건이 충족될 때까지 끝나지 않는다. [확인]
- D/DG: 카운트 대신 누적 Total 기준 고정 패턴(0-9 느림, 10-19 빠름, 20-30 느림, 31-59 빠름), **총 60마리에서 스폰 정지** (`StageManager.java:282`). [확인]
- 서바이벌: 웨이브당 `iUCnt_ × 2`마리 생성 후 종료 (`StageManager.java:673-675`), 필드 적이 0이 되면 다음 웨이브 (`StageManager.java:269-276`, `CharInfo.java:2870-2887`). [확인]
- 다크독 점프(kind 7)는 적 스폰 없음 (`StageManager.java:266`). 다크 이벤트 중(`m_iDarkEventCharID >= 0`) 스폰 정지 (`StageManager.java:264`). [확인]

### 3-3. 어떤 적을 뽑는가 (iEU0n / iEU0nP) [확인]

```java
int lc_iVal = ((rand%10000) % 1000) / 10;        // 0..99
if (iEU05P <= 0 || m_iEnemyCountForFifth < iEU05P) {
    check = P1;           if (val < check)               → U1
    check += P2;          if (미선택 && val < check)       → U2
    check += P3;          ...                            → U3
    check += P4;          ...                            → U4
} else {
    → U5;  m_iEnemyCountForFifth = -1;              // 이후 ++로 0
}
if (lc_iEnemy > 0) { 생성; CalcNextTime(); }      // 미선택(-1)이면 다음 프레임 재추첨
```
- **iEU01P~04P는 누적 임계치에 더해지는 "구간 폭"** 이다. P1=15, P2=30, P3=100이면 U1 15%, U2 30%, U3 55%(나머지). 합이 100 미만이면 빈 구간은 "스폰 안 함 → 다음 프레임 재시도"이므로 사실상 정규화된다. [확인]
- **iEU05P는 확률이 아니라 주기**: 일반 스폰이 iEU05P회 누적되면 다음 1회는 반드시 U5. 즉 U5는 **(iEU05P+1)번째마다 1마리** 출현. 예: 1-1 (U5=21, P5=19) → 20마리마다 강화 좀비 1. [확인]
- 적 ID 해석 (`StageManager.java:628-634`, `common/AppDelegate.java:896-902`):
  - 1~20: 일반 적, DB `[224+id]` (좀비, 해골, 마녀, 악마, 링, 화살해골, 미이라, 프랑켄슈타인, 유령, 빨간좀비, 해적좀비, 돌탱이, 광부좀비, 호박, 외눈거인, 갑옷도끼, 폭탄, 비홀더, 해골긴창, 갑옷방패).
  - 21~40: **같은 DB `[224+(id-20)]`를 쓰되 스탯 ×fZmESt(1.3)** 인 강화판, 스프라이트는 `e21~e40` 별도. [확인]
  - 101~110: 보스 `id-100`번, DB `[244+(id-100)]` (좀비킹, 백발마녀, 사커좀비, 미이라킹, 텔레포트고스트, 냠냠이, 도플갱어 팔라독, 스켈드래곤, 서큐버스, 데쓰나이트). [확인]
  - 0: 비어 있음.

### 3-4. 적 스탯 스케일링 [확인]

```java
// StageManager.CreateEnemy (StageManager.java:635-648)
float lc_fStatMul = 1.0f;
if (p_iIndex == 3 && rand%1000 <= 100) {           // U3 슬롯에서 약 10.1%
    lc_fScale *= DB[0].fBigSc;  /* 1.2 */  lc_fStatMul = DB[0].fBigSt; /* 3.3 */
}
if (kind in ZOMBI_21..ZOMBI_40) lc_fStatMul *= DB[0].fZmESt;   /* 1.3 */
if (서바이벌) { scale *= GetMulVal_SVVScale(); statMul *= GetMulVal_SVVStat(); }
// AppDelegate.CreateZombi (common/AppDelegate.java:926-929)
HPMax  = DB.iMaxHP * statMul * GetMulVal_HP_Dfct() * (서바이벌 보스 HP배수);
Attack = DB.iAtPwr * statMul * (서바이벌 보스8 공격배수);
MoveSpeed = DB.iMvSpd * scale;
```
- **챕터/스테이지별 배수는 없다.** 난이도 상승은 오로지 (1) DB의 적 ID 구성(후반 챕터일수록 상위 ID·21~40 강화판·보스 ID 혼입), (2) 스폰 간격, (3) 본진 HP로 표현된다. [확인]
- 처치 보상도 `m_fStatMulVal`에 비례 → 거대(×3.3)는 보상 3.3배, 강화판은 1.3배. [확인]
- 이동속도는 스케일 배수만 받으므로 거대(1.2)는 20% 빠르다 [확인]; T 모드(0.6)·DG(0.7)는 모든 캐릭터가 느리다 [확인].

### 3-5. 본진 50% 이벤트 (일반·보스 스테이지) [확인]
`CreateEnemyForCastle50Proc` (`StageManager.java:394-422`, `362-392`):
- 본진 HP < 50% 순간: 경고음·진동, 본진 이펙트, 그 후 **1초 간격으로 총 10마리의 거대 적**(scale×1.2, stat×3.3; 21~40이면 추가 ×1.3) 추가 생성. 처음 5마리 = U3, 다음 5마리 = U2. 위치 x = iScrollMax(1024). [확인]

### 3-6. 타워 모드 추가 러시 [확인]
- 생성 카운트가 iUCnt_ 또는 iUCnt_×2에 도달하는 순간 5마리 추가 러시: 50% 확률로 1~5번 라인에 한 마리씩, 아니면 무작위 라인에 x 간격 40px로 (`StageManager.java:337-351`). 러시 적 종류는 `TowerGetZombieIndex`(U4→U3→U2→U1 순으로 50% 동전) (`StageManager.java:584-599`). [확인]

### 3-7. 보스 등장 [확인]
- **B 스테이지(kind 4)**: 일반 스폰 + 본진. 본진 HP 0 → 본진 파괴 연출, 보스 `m_iCurStage/12`번(12→1 좀비킹 … 120→10 데쓰나이트)을 x=iScrollMax-80에 생성, 아군 전원 넉백(knockdown ×3) (`GameManager.java:321-360`). 보스 HP 0 → 승리 (`GameManager.java:316-320`).
- **T 스테이지(kind 3)**: 시작 시 보스 `s/12 + 1`번을 x=420에 고정(m_bHoldPosition) 배치 (`StageManager.java:217-225`). 역할은 장애물/중간 보스 [추정].
- 스폰표에 101~110이 들어간 경우 일반 스폰으로도 보스가 나온다 (예: 4-12B U5=103, 5-24B 등). [확인]
- 서바이벌 다크독 이벤트: 팔라독으로 웨이브 4 도달 & 다크독 미해금 시 다크독(BOSS_13) 이벤트 → 해금(iDarkdogAllow=1) (`GameManager.java:2952-2954, 3598`). [확인]

---

## 4. 스테이지 타입별 규칙과 승패 조건

공통 패배: 플레이어(히어로) HP ≤ 0 → step 6(패배) → 보석 ≥20이면 부활 제안 (`GameManager.java:215-222, 1819-1870`). **아군 본진은 없다** — 팔라독 자신이 기지 역할 [확인].
승리 후 흐름: step 7/8/9/25 → 10(레벨업 체크) → 12 → 13(별·보상) (`GameManager.java:1871-2005, 2190-2196`). [확인]

| 타입 | kind | 승리 | 패배 | 비고 / 근거 |
|---|---|---|---|---|
| 일반 | 0 | 적 본진 HP 0 | 히어로 사망 | 본진 HP = iECHP_ × 난이도HP (`StageManager.java:191-199`, `GameManager.java:223-245`) |
| B 보스 | 4 | 본진 파괴 후 등장한 보스 처치 | 히어로 사망 | 3-7 참조 |
| D 운명(팔라독) | 1 | **킬 60** | 히어로 사망 | 스폰 총 60마리 상한 (`GameManager.java:244-257`). 아래 4-1 |
| W 목마(팔라독) | 2 | 아군 마차가 x > iScrollMax-154(=870) 도달 | 마차 HP 0 또는 히어로 사망 | 마차 HP = iECHP_ (`StageManager.java:200-204`, `GameManager.java:262-273`), 시작 x=-100 (`GameLayer.java:470`) |
| W 목마(다크독) | 2 | 적 목마(BOSS_12) HP 0 | 목마가 x ≤ 140 도달 | 목마 HP = iECHP_, 공격력 = fVer__(목마 공격력) (`StageManager.java:205-207`, `GameManager.java:274-286`), 시작 x=1024 (`GameLayer.java:477`). 적은 목마 위치에서 스폰 (`StageManager.java:659-660`) |
| T 타워(팔라독) | 3 | 타워포인트 ≥ +15 | 포인트 ≤ -15 | 아래 4-2 (`GameManager.java:289-305`) |
| DG 던전(다크독) | 6 | 킬 60 | 히어로 사망 | 적은 3번 라인 고정, x=480에서 스폰 (`StageManager.java:656-658`), 스폰 규칙은 D와 동일 (`GameManager.java:306-313`) |
| J 멧돼지점프(다크독) | 7 | 보스(다크독) 추월 후 x ≥ 맵끝+100 | 장애물 충돌/낙사 → 사망 | 아래 4-3 (`GameManager.java:362-390`) |
| 서바이벌 | 5 | 없음(무한) — 웨이브/킬/시간 랭킹 | 히어로 사망(step 26) | 아래 4-4 |

### 4-1. D 운명 스테이지 (팔라독) [확인]
- 진입 시 장비/유닛레벨을 백업 후 **강제 세팅**: 메이스 3슬롯 = `-mace`행의 U1, U2, U5 (등급은 스테이지 구간별), 모든 유닛 레벨 = `DestinyGetUnitLevel(s)` (s≤12:1, ≤24:3, …, ≤120:19) (`GameLayer.java:270-295`, `StageManager.java:519-582`).
- 9칸 "운명 박스": `-mace`행 iCSp11(=3초, 난이도3이면 ×2/3)마다 빈 칸 하나를 채움. 50%로 유닛(`-unit`행 U1/U2 누적확률, 매 6번째 U5), 50%로 메이스(`-mace`행) (`StageManager.java:424-517`).
- 박스를 누르면 **무료**로 유닛 소환 또는 메이스 발동 (`GameUILayer.java:2189-2215`, CreateUnit `p_bNoUseMP=false`이지만 박스 경유 [추정: 식량 차감 여부는 CreateUnit 내부 확인 필요]).
- 적 스폰은 본 스테이지 행(예: 1-3D `[2]`) 사용, 3-1의 D 패턴, 60마리.

### 4-2. T 타워 (팔라독) [확인]
- 5개 라인(y = (line-1)*33 + 75), 플레이어 x=32 라인0 고정 (`common/AppDelegate.java:941-945`, `GameLayer.java:527-528`).
- 유닛 버튼 → 라인 선택(y 54~224, 34px 간격) → 해당 라인에 소환 (`GameUILayer.java:2387-2402`).
- 아군 유닛이 x ≥ 480 도달: 포인트 +1(최대 15), 적이 x ≤ 0 도달: 포인트 −1(최소 −15) (`CharInfo.java:2631-2660`).
- 적은 x=480, 무작위 라인 1~5에서 스폰 (`StageManager.java:653-655`).

### 4-3. J 멧돼지점프 (다크독) [확인]
- 맵은 `dpj%02d.mje` 타일맵(번호 = s/12+1) (`GameLayer.java:212-221`), 플레이어는 멧돼지 토템(TTM_03) (`GameLayer.java:546-551`).
- DB 컬럼 재정의 (stage.txt:226 스키마):
  - iCSp11 = 멧돼지 이동속도 (×난이도 점프배수) (`CharInfo.java:6532`)
  - iCSp12 = 코인당 골드 (`CharInfo.java:6608`)
  - iECHP_, iEU01_, iEU01P, iEU02_, iEU02P = 1~5번 안전지대(타일 인덱스). 사망 후 재시작 x = `50 + 지나친 최대 안전지대 × iBaseW` (`GameManager.java:4778-4806`)
  - iUCnt_/iCSp21(별3/별2 코인 수): **코드 참조 없음** — 코인 별 조건은 퀘스트 타입 4(`m_iCoinCount >= VarA`) (`QuestManager.java:766-773`). [확인]
- 위험물(kind 4) 충돌 시 사망 상태 42 (`CharInfo.java:6590-6596`). 보스와 거리 0~100이면 자동 점프 (`GameManager.java:362-366`).

### 4-4. 서바이벌 [확인]
- 웨이브 1~30은 DB `[140..169]` 1회, 31 이후는 `[170..189]` 20개 루프 (`iSVVWavePreCnt=30`, `iSVVWaveLoopCnt=20`, `common/AppDelegate.java:5137-5138`; `GameManager.java:4524-4535`).
```java
GetWaveRepeatNum(w) = (w-1 < 30) ? 0 : ((w-1-30)/20) + 1;
SVVScale = 1 + fSVVScaleMulVal * repeat;                                  // fSVVScaleMulVal = [140].fVer = 0.1
SVVStat  = (1 + fSVVStatMulVal * repeat * (wave - 31)) * fSVVStatBaseVal;   // GameManager.java:3814-3818
// fSVVStatBaseVal = [140].iCrSec/100 = 1.10 (기본), repeat>0이면 해당 웨이브행 iCrSec/100 (예: [170]=2.70, [171]=32.0)
// fSVVStatMulVal  = [140].iCrS2_/100 = 0.07
```
  (`GameManager.java:3970-3981`, `StartStage` 덮어쓰기 `StageManager.java:180-182`)
- 기타 서바이벌 상수: EXP 배수 `[141].fVer=27`, 아군 유닛 업그레이드 배수 `[142].fVer=0.2`(유닛 HP/공격 += 기본×0.2×(레벨-1), `common/AppDelegate.java:783-784`), 보스 HP `[144]=0.2`, 보스10 HP `[145]=0.5`, 보스8 공격 `[146]=0.5`. [확인 값] / 각 행의 fVer를 상수 저장소로 재활용 [확인].
- 웨이브 진행: 스폰 iUCnt_×2마리 완료 & 적 전멸 → 결과 연출 → AddWave(1), 카운터 초기화 (`GameManager.java:3468-3476`).

---

## 5. 해금/진행 구조 [확인]

- 5챕터 × 24스테이지 = 120 (StageSelect 페이지 5, 페이지당 6×4 그리드) (`com/my/Layer/StageSelectLayer.java:153-154, 479-485`).
- `iStageStar[i]`: -1 잠김, 0 개방(미클리어), 1~3 별. 새 게임은 [0]만 0 (`common/AppDelegate.java:4960-4963`).
- 클리어(step 13)하면 다음 스테이지 `iStageStar[cur+1]`을 0으로 개방 (`GameManager.java:1988-1990`). 별 0개로 끝나도 개방됨 [확인].
- 챕터 내부 고정 순서(12스테이지 주기): 일반×2 → D/J(3) → 일반×2 → W(6) → 일반×2 → T/DG(9) → 일반×2 → B(12). 챕터 = 2주기.
- 12의 배수 스테이지 첫 클리어 시 "레벨캡 해제" 메시지 플래그 (`GameManager.java:2034-2036`) — 실제 레벨캡 로직은 분석 범위 밖 [추정].
- 120 클리어 → 엔딩(팔라독 scene 7 / 다크독 scene 11) (`GameManager.java:2216-2221`).
- 다크독 캠페인: 동일 120스테이지를 다크독으로 플레이, D→J, T→DG로 치환되고 21개 스테이지는 전용 DB행 220~240 사용. 해금 = 서바이벌 다크독 이벤트(=1) 또는 상점 구매(=2) (`GameManager.java:3598`, `com/my/Layer/ShopEquipLayer.java:2894`). `IsAllowDarkStage`는 항상 true (`common/AppDelegate.java:7408-7410`). [확인]
- 서바이벌 해금 조건: 분석 불가 항목 참조.

---

## 6. 맵/카메라 [확인]

- 논리 해상도 480×320, 전장 폭 `iScrollMax = 1024` (`common/AppDelegate.java:7415-7418`).
- 일반 모드는 **1레인**. 적 y = `GetCreateCharY(iCLine)` = 145~185 랜덤(깊이감용 지터) (`common/AppDelegate.java:1392-1414`).
- 위치:
  - 히어로 시작 x: 일반/W/B 100, D 45, T·DG 32, J 50 (`GameLayer.java:522-534`).
  - 적 본진(BOSS_11) x = 1024-120 = 904, 본진 스프라이트 x=791 (`GameLayer.java:484-498`).
  - 적 스폰 x = 1024 (일반/W/B/서바이벌), 480 (D/T/DG) (`StageManager.java:650-661`).
  - 아군 전진 한계: 본진 생존 시 x ≤ 864, 보스전 x ≤ 984 (`CharInfo.java:2615-2620`).
- 레인 수: 일반 1, 타워 5 (y=(l-1)*33+75), 던전 다수 라인 y=(l-1)*80+68 (적은 3번 라인) (`common/AppDelegate.java:939-946`).
- 카메라: 히어로를 화면 1/3 지점에 두는 자동 스크롤, 드래그로 수동 스크롤, 범위 [0, 1024-480] (J는 맵 끝까지) (`GameUILayer.java:1724-1762`). 보스 등장 시 맵 끝으로 강제 이동 (`GameManager.java:4741-4744`).

---

## 7. 챕터 1 스테이지 표 (팔라독, DB `[0]..[23]`) [확인 — stage.txt]

- 전반/후반 간격 = 초 단위 [min, max+0.9]. 혼합% = 3-3의 누적 규칙 적용 결과. "+"는 21~40 강화판(×1.3).
- 특수 = U5와 주기((P5+1)마리마다 1).
- 보상 iCrRwd·클리어시간 iCrSec는 **코드 미사용**(참고치).
- D/T/W 행은 4장의 모드 규칙이 우선 (D: 60킬, T: 포인트, W: iECHP_=마차 HP).

| 스테이지 | 전반 간격 | iUCnt_ | 후반 간격 | 본진HP(iECHP_) | 일반 혼합 | 특수(U5) | iCrRwd | iCrSec |
|---|---|---|---|---|---|---|---|---|
| 1-1 | 5~5.9 | 3 | 0~1.9 | 3000 | 좀비(1) 100% | 좀비+(21) /20회 | 500 | 203 |
| 1-2 | 6~6.9 | 3 | 0~1.9 | 6000 | 좀비+(21) 15%, 좀비(1) 85% | 프랑켄(8) /30회 | 500 | 217 |
| 1-3D | 4~6.9 | 15 | 0~1.9 | 8000 | 좀비+(21) 15%, 좀비(1) 85% | 악마(4) /25회 | 500 | 201 |
| 1-4 | 4~6.9 | 3 | 0~1.9 | 8000 | 해골(2) 15%, 좀비(1) 85% | 화살해골(6) /15회 | 500 | 259 |
| 1-5 | 5~6.9 | 3 | 0~1.9 | 8000 | 좀비+(21) 15%, 해골(2) 85% | 유령(9) /30회 | 500 | 242 |
| 1-6W | 1~2.9 | 10 | 0~1.9 | 40000(마차HP) | 좀비(1) 100% | 해적좀비(11) /50회 | 500 | 239 |
| 1-7 | 3~6.9 | 15 | 0~1.9 | 8000 | 해골+(22) 15%, 좀비+(21) 30%, 좀비(1) 55% | 유령(9) /40회 | 500 | 184 |
| 1-8 | 3~5.9 | 15 | 0~1.9 | 8000 | 좀비+(21) 45%, 좀비(1) 55% | 링(5) /30회 | 500 | 201 |
| 1-9T | 1~3.9 | 17 | 1~2.9 | 8000 | 좀비(1) 100% | 좀비(1) /23회 | 500 | 188 |
| 1-10 | 1~5.9 | 15 | 0~1.9 | 8000 | 좀비+(21) 45%, 해골(2) 55% | 빨간좀비(10) /25회 | 500 | 210 |
| 1-11 | 2~5.9 | 15 | 0~1.9 | 8000 | 링(5) 8%, 해골+(22) 30%, 좀비+(21) 62% | 링(5) /25회 | 500 | 249 |
| 1-12B | 1~2.9 | 15 | 0~1.9 | 13000 | 해골+(22) 100% | 해적좀비(11) /100회 | 750 | 523 |
| 1-13 | 2~5.9 | 15 | 0~1.9 | 18000 | 마녀+(23) 15%, 악마(4) 30%, 마녀(3) 55% | 미이라(7) /15회 | 750 | 303 |
| 1-14 | 5~6.9 | 15 | 0~1.9 | 18000 | 미이라(7) 15%, 마녀+(23) 30%, 마녀(3) 55% | 빨간좀비(10) /15회 | 750 | 284 |
| 1-15D | 4~7.9 | 15 | 0~1.9 | 18000 | 미이라(7) 15%, 마녀+(23) 30%, 마녀(3) 55% | 빨간좀비(10) /15회 | 750 | 190 |
| 1-16 | 1~5.9 | 15 | 0~1.9 | 18000 | 악마+(24) 15%, 악마(4) 30%, 마녀(3) 55% | 프랑켄(8) /15회 | 750 | 214 |
| 1-17 | 3~6.9 | 15 | 0~1.9 | 18000 | 미이라(7) 15%, 마녀+(23) 30%, 악마(4) 55% | 해적좀비(11) /15회 | 750 | 242 |
| 1-18W | 1~2.9 | 15 | 0~1.9 | 36000(마차HP) | 마녀(3) 100% | 광부좀비(13) /30회 | 750 | 170 |
| 1-19 | 4~6.9 | 15 | 0~1.9 | 18000 | 프랑켄(8) 15%, 악마+(24) 30%, 마녀(3) 55% | 해적좀비(11) /15회 | 750 | 234 |
| 1-20 | 1~4.9 | 15 | 0~1.9 | 18000 | 미이라(7) 15%, 마녀+(23) 30%, 마녀(3) 55% | 유령(9) /15회 | 750 | 246 |
| 1-21T | 1~2.9 | 13 | 1~1.9 | 18000 | 해골(2) 100% | 해골(2) /23회 | 750 | 264 |
| 1-22 | 3~6.9 | 15 | 0~1.9 | 18000 | 프랑켄(8) 15%, 마녀+(23) 30%, 악마(4) 55% | 돌탱이(12) /15회 | 750 | 250 |
| 1-23 | 1~4.9 | 15 | 0~1.9 | 18000 | 미이라(7) 15%, 악마+(24) 30%, 악마(4) 55% | 빨간좀비(10) /15회 | 750 | 199 |
| 1-24B | 1~3.9 | 15 | 0~1.9 | 12000 | 악마+(24) 100% | 광부좀비(13) /30회 | 1000 | 383 |

- 1-12B 보스 = 좀비킹(1), 1-24B 보스 = 백발마녀(2). T 스테이지 고정 보스: 1-9T → 보스1, 1-21T → 보스2.
- 운명 보조행 1-3D: `-mace`[120] (메이스 6/4/3번 = 파이어/아이스/턴언데드, 박스 간격 3초), `-unit`[121] (유닛 2=토끼 30%, 1=쥐 70%, 6번째마다 3=곰). [확인 값, 아이템 번호→이름은 db.txt [7]-[26] 기준]

### 7-1. 이후 챕터 스케일 요약 [확인 — stage.txt]

| 지표 | 챕터1 | 챕터2 | 챕터3 | 챕터4 | 챕터5 |
|---|---|---|---|---|---|
| 일반 본진 HP | 3k→18k | 32k~70k | 100k 내외 | 120k~150k | 200k~400k (5-24B 1.6M) |
| 주력 적 ID | 1~4, 21~24 | 5~8, 25~28 | 9~14, 29~34 | 13~18, 31~36 | 17~20, 36~40 + 보스 ID 혼입 |
| 특수(U5) 주기 | 15~50 | 20~30 | 20~30 | 20~50(보스 103/105 등) | 20~80 |
| iCrRwd(미사용) | 500/750/1000 | 1000~1500 | 1500~2000 | 2000~2500 | 2500~3000 |
| W 목마(다크독) HP/공격 | 7k/250, 20k/600 | 30k/1000, 60k/1300 | 80k/2000, 100k/2600 | 125k/3300, 150k/4100 | 180k/5000, 250k/7000 |
| DG 던전 본진HP값 | 8k, 18k | 32k, 70k | 100k, 100k | 200k, 150k | 350k, 400k |
| J 멧돼지 속도/코인골드 | 280/2, 285/3 | 290/4, 295/5 | 300/6, 310/7 | 320/9, 330/9 | 340/10, 350/11 |

- 스폰 간격은 챕터와 무관하게 전반 1~7초 / 후반 0~1.9초 범위에서 스테이지마다 손으로 조정됨. iUCnt_ 대부분 15 (초반 3, 일부 10/20). [확인]
- 결론: 리메이크는 "챕터 배수"를 만들 필요 없이 **스테이지 행 데이터를 그대로 이식**하면 원작 난이도 곡선이 재현된다. [추정]

---

## 8. Roblox 이식용 의사코드 (요약)

```lua
-- 매 프레임 dt(초, 배속 반영)
mana  = math.min(manaMax,  mana  + (A_mp + skMp*C_mp) * 10 * dt)
food  = math.min(foodMax,  food  + (A_fd + skFd*C_fd) * 10 * dt)
hpTick += dt; if hpTick >= 5 then hpTick = 0; heroHP += regenHP end

-- 스폰
spawnTimer += dt
if spawnTimer >= need then
  local idx
  if row.P5 > 0 and fifthCnt >= row.P5 then idx = 5; fifthCnt = -1
  else local v = math.random(0,99); local c = 0
       for i=1,4 do c += row["P"..i]; if v < c and row["U"..i] > 0 then idx = i break end end end
  if idx then spawn(row["U"..idx], idx); cnt += 1; total += 1; fifthCnt += 1
    if cnt >= row.UCnt*2 then cnt = 0 end
    local lo, hi = row.S21, row.S22
    if cnt < row.UCnt then lo, hi = row.S11, row.S12 end
    need = lo + math.random(0, (hi-lo+1)*10 - 1)/10; spawnTimer = 0
  end -- idx 없으면 다음 프레임 재시도
end
```

---

## 분석 불가 / 미확정

1. **퀘스트 DB(별 3개 조건·클리어 골드)**: 파일은 `assets/quest.xml`/`quest_d.xml`(구조·보상은 [명세 05 B10](paladog-05-growth.md)에서 확인). 미해결로 남는 부분은 아래 판정 코드의 디컴파일 실패 구간뿐이다. 퀘스트 타입 번호별 의미(1=본진파괴, 3/4=D, 5/6=W, 7/8=T, 10=시간, 11=골드 등)는 `QuestManager.CalcResultPala/Dark`에 있으나 디컴파일 일부 실패("Code decompiled incorrectly", `QuestManager.java:385-389, 562-566`).
2. `CreateUnit`(운명 박스 경유) 시 식량 차감 여부: `p_bNoUseMP` 인자 의미 미검증 (`common/AppDelegate.java:1300-1320` 상세 미독).
3. (해결) 스킬 인덱스(sk[1..24]) 정식 이름 — [명세 03 §4](paladog-03-hero.md) (문자열 `string_skill_ko_01.xml` 순서와 코드 사용처 대조로 확인).
4. 일반 모드 부활 비용(서바이벌은 보석 20 확인), 부활 횟수 제한 미확인.
5. 서바이벌 모드 해금 조건(별 수/스테이지 클리어 등) 미확인.
6. W(팔라독) 마차의 이동 규칙(히어로 근접 시 전진 등)과 마차 DB `[1]`(HP 1000, 속도 8)과 iECHP_ 덮어쓰기의 관계: HP는 iECHP_로 덮어씀 확인, 이동 조건은 `CreateWagon`/CharInfo 미독.
7. 점프 맵(.mje) 실제 길이(iBaseMax×iBaseW)와 코인 배치는 에셋 파일 파싱 필요.
8. 지옥 난이도(3)에서 적 HP 배수가 1.0인 것이 의도인지 버그인지 불명 (`GameManager.java:2839-2849`).
9. 서바이벌 `[141].fVer = 27`(EXP 배수)·`[143].fVer = 30`(미사용) 등 값의 기획 의도 불명.
