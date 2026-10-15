# Paladog 명세 01 — 게임 엔진 및 APK 구조

> 근거 표기: Java 경로는 JADX 1.5.1 디컴파일 출력 `sources/` 기준 `파일:줄`(줄 번호는 디컴파일 결과 기준), `db.txt [n]` / `stage.txt [n]` = `assets/pdw_db.xml` / `assets/pdw_db_stage.xml`의 n번째 `<Data>` 레코드(0부터, `GetDBInfo(n)` / `GetDBInfoS(n)`와 동일). **[확인]** = 코드·데이터에서 직접 확인, **[추정]** = 정황 기반 해석. 전체 원본 값은 [부록 A](paladog-appendix-data.md), 분석 방법·종합 미해결 목록은 [인덱스](paladog-00-index.md) 참조.

### A1. 패키지/버전/SDK
- [확인] package `com.Paladog.KorGG`, versionCode 25, versionName 2.2.0, minSdk 7 — 바이너리 매니페스트 직접 파싱(스크래치 `axml.py`, `AndroidManifest.xml`).
- [확인] 매니페스트에 `compileSdkVersion=36`, `platformBuildVersionCode=33` 기록 → 원본(2012~13년경) 이후 **재빌드/재서명된 APK**. [추정] 커뮤니티 패치판.
- [확인] 권한: BILLING, INTERNET, READ_PHONE_STATE, CHECK_LICENSE, VIBRATE, WRITE_EXTERNAL_STORAGE, C2DM(GCM), GET_ACCOUNTS, WAKE_LOCK.
- [확인] 액티비티: `.Paladog`(런처, 가로), `.MessageBoxActivity`, `.ServerSendMessageBoxActivity`, `.InputActivity`, `FaceBookActivity`; GCM 리시버 + `.GCMIntentService`.
- [확인] 코드상 버전 문자열 "2.2.0", 통신사 태그 "GG"(Google) — `com/Paladog/KorGG/Paladog.java:141-143`.
- [확인] `BuildConfig.DEBUG = true` — `com/Paladog/KorGG/BuildConfig.java`.

### A2. 엔진
- [확인] **cocos2d-android 0.99.4** (Java 포팅판, 순수 Java/GLSurfaceView) — `org/cocos2d/config/ccConfig.java:24` `cocos2dVersion = "cocos2d v0.99.4"`.
- [확인] 논리 해상도 480×320 고정, 60fps(`setAnimationInterval(0.0166…)`) — `Paladog.java:118-121,151-152`.
- [확인] 게임 로직 전부 Java. 네이티브 .so 는 게임 로직과 무관(아래 A4).
- 주요 클래스: `com/common/AppDelegate.java`(싱글턴 허브, 11,699줄), `com/my/Game/GameManager.java`(전투/스탯 공식), `com/my/Char/CharInfo.java`(캐릭터 행동/보상), `com/common/CM.java`(상수).

### A3. 액티비티 → 씬 흐름
- [확인] `Paladog.onCreate` → 세이브 로드 → `LoadingScene`(com/SPC/LoadingScene) 실행, `gmGameMode=26` — `Paladog.java:108-197`. (gmGameMode==16 이면 HellScene 직행 — `Paladog.java:183-189`)
- [확인] 씬 번호 테이블 `AppDelegate.ReplaceScene(int)` — `com/common/AppDelegate.java:4656-4730`:

| id | Scene | id | Scene |
|---|---|---|---|
| 0 | LoadingScene(허브) | 9 | RankingScene |
| 1 | MainMenuScene | 10 | AchieveScene |
| 2 | GameScene(전투) | 11 | EndingDarkScene |
| 3 | StageSelectScene | 14 | TencentProcScene |
| 4 | UnitUpgradeScene(유닛강화+상점+스킬) | 15/16 | CleanTestScene |
| 5 | LoadingScene2(전투 로딩) | 17 | EventSceneScene(컷신) |
| 6 | OpeningScene | 18 | HellScene |
| 7 | EndingScene | 19 | InviteScene |
| 8 | LoginScene | 20 | LineProcScene |

- [확인] 모든 전환은 `iReservedScene = N; ReplaceScene(0)` 패턴 → LoadingScene 이 저장 후 `ReplaceScene(iReservedScene)` — `com/SPC/LoadingLayer.java:465-511` (gmGameMode 9→13(저장)→10→전환).
- [확인] 메뉴 이동 목적지: MainMenu → 3/4/6/8/9/10 (`com/my/Layer/MainMenuLayer.java:2260,2263,2333,2644,2715,4253`), StageSelect → 1/2/4 (`StageSelectLayer.java:571,613,616`), UnitUpgrade → 2(서바이벌 복귀)/1 (`UnitUpgradeLayer.java:810,873`), 게임 종료 후 → 1/4/5/7/9/11/17 (`GameManager.java:2215-2235,2493`), LoadingScene2 → 2 (`LoadingLayer2.java:159`).
- 요약 흐름 [확인]: `Loading → (Opening/Login) → MainMenu → StageSelect → LoadingScene2 → GameScene → (결과) → MainMenu|UnitUpgrade|Ending|EventScene`.

### A4. 네이티브 라이브러리 역할
| lib | 로더 | 역할 | 게임 로직 사용 |
|---|---|---|---|
| libAppleJuice.so | `com/appleJuice/AppleJuice.java:168` | Tencent(QQ) "AppleJuice" 소셜/인증 SDK (AJAuthPackInterface: AuthWithAccount, Encrypt/Decrypt, GetUin… `com/appleJuice/network/AJAuthPackInterface.java:5-47`) | [확인] 게임 측 훅은 빈 스텁: `Paladog.AppleJuiceActivity(){}`, `AJViewProc(){}` — `Paladog.java:676-683` |
| libsimpleencryption.so | `com/kakao/api/util/SimpleEncryption.java:36` | Kakao SDK 내부 토큰 암호화 | [확인] com/my·com/common 에서 SimpleEncryption 호출 없음(Kakao 클래스 import만 존재: `CharInfo.java:7`, `GameManager.java:5`) |
| libdes3jni.so | `com/tenpay/android/des3/DES3.java:61` | Tenpay(QQ 결제) DES3 | [확인] applePay(텐페이) SDK 내부에서만 사용 |

- **결론 [확인]**: 세이브/에셋 암호화는 native 가 아니라 **Java(WCEncrypt + Base64 + 체크섬)** 로 처리됨. 리메이크 시 .so 는 불필요.

### A5. 에셋 포맷
- [확인] **.JA** (2,568개): 관절(본) 애니메이션 바이너리. `AniInfo.InitializeMJA` 가 통째로 읽어 `MJointAnimator.load()` 로 파싱 — `com/my/Char/AniInfo.java:46-79`. 평문(예: `b01_att.JA` 헤더 `03000000 02000000 … "Camera"` 문자열 노출). 리틀엔디언 int 기반(`Library.readInt`). 등록 예: `CacheMJA(410,"b01_wait.JA",33.0f)` — `AppDelegate.java:1967-2015`.
- [확인] **.mae/.mce**: 파츠 조립형 캐릭터(MAE=애니 헤더 `dwSecretCode,iVersion,iAniMax` — `com/my/CharStruct/MAEHEADER.java:21-25`; MCE=파츠/Z순서 — `CharInfo.java:6889 LoadMCE`, `:6952 LoadMAE`). 파일: `u01.mae/.mce`, `u0102…u0910`, `title_*.mae`, `d_ending.mae`. 헤더에 파일명 문자열 평문(`d_ending_01`).
- [확인] **.mje**: 점프 모드 타일맵(`dpj01~10.mje`) — `com/my/Char/TileManager.java:119 LoadMJE`, 호출 `GameLayer.java:216`.
- [확인] **.plist**: cocos2d 스프라이트 시트(zwoptex 형식, frame/offset/sourceSize). 예: `assets/achieve.plist`는 업적 UI 스프라이트 시트일 뿐 **업적 데이터 아님**. `-hd` 접미사 = 고해상도.
- [확인] **.xml DB**: `pdw_db.xml`(캐릭터/수치), `pdw_db_stage.xml`(스테이지/웨이브), `quest.xml`/`quest_d.xml`(팔라독/다크독 퀘스트), `questtype_*`, `questicon_*`, `string_*_{lang}_01.xml`(12개 언어 UI 문자열). 평문 UTF-8.
- **.gdt** (`dn.gdt` 117KB, `ds.gdt` 20KB): Java 소스에서 참조 없음 → 분석 불가 항목 참조.

### A6. DB 로딩
- [확인] `AppDelegate.StartLoadDB()` — `AppDelegate.java:4987-4999`: `parse()`(pdw_db.xml) → `parseS()`(stage) → `parseQ/QI/QT`(quest.xml, questicon_{lang}, questtype_{lang}) → `parseDQ/DQI/DQT`(quest_d…) → `DataControllerExt.Initialize()`(문자열 테이블).
- [확인] SAX 파서. `<Data>` 하나가 DBInfo 1행, 순서대로 리스트에 append → **행 번호가 곧 ID** — `com/my/DB/MyXMLReader.java:49-60`, `DBManager.java:32`.
- [확인] 컬럼 매핑 예: `iCost_→m_iLvUpCost`, `iNewHP→m_iLvUpNewHP`, `iNewAP→m_iLvUpNewAP` — `MyXMLReader.java:160-170`.
- [확인] 무결성 체크: `DBInfoCheckSum()` 바이트합 mod(-4096) == 2491(pdw_db.xml), 2905(pdw_db_stage.xml) — `AppDelegate.java:5277-5316`, 호출 `LineProcLayer.java:61`.
- [확인] `bUseDownloadedDB=false` 고정 — `Paladog.java:130`. `Downloader.java` 는 HTTP GET 유틸(배너/치트목록용).

### A7. 세이브 시스템
- [확인] 저장 위치: Android **SharedPreferences XML** (`/data/data/com.Paladog.KorGG/shared_prefs/`) — `AppDelegate.WriteSaveInfoXml()` `AppDelegate.java:5351-5377`.
  - `PDWXMLInfo.xml` = 계정 공통(GAMESAVEINFOETC), `PDWXMLSlot0~7.xml` = 슬롯 8개, `PDWXMLBattle`(전투 중단 저장), `PDWXMLLocalRank` — 상수 `com/common/CM.java:279-294`.
  - 레거시 바이너리 `PDWSave.sav`(30001/30002 바이트, XOR 0x54) / `PDWNewInfo.sav`+`PDWNewEach{N}.sav` 는 마이그레이션 경로 — `AppDelegate.java:5318-5349,5419-5455`, `com/common/Library.java:59-109`.
- [확인] 슬롯: 0~3 = 팔라독, 4~7 = 다크독 (`iCurSlot >= 4 → hkHeroKind = 2`) — `Paladog.java:172-174`. 슬롯 저장 v107.
- [확인] 인코딩 파이프라인 (`com/my/Struct/GAMESAVESLOTINFO.java:299-397`):
  1. 모든 필드를 `"%d,"` CSV 문자열로 직렬화
  2. `WCEncrypt.Encrypt(bytes, 561)` — 키 스트림 XOR, 상수 C1=74102, C2=12337 (`com/common/WCEncrypt.java:17-21,76-100`)
     ```java
     int i3 = (byte)(cSrc ^ (nKey2 / 256)); ...
     nKey2 = (m_nC1Key * (nFirstResult + nKey2)) + m_nC2Key;   // 결과는 HEX 문자열
     ```
  3. Base64 → `strSave64` 키, 체크섬 → `intCheck64` 키. 로드 시 체크섬 불일치면 무시.
  - 추가 안티치트: 골드/EXP/젬/스톤을 `iGoldForCalc[10]` 등 분산 배열에 이중 보관(`CalcForHack/CheckHack`) — `AppDelegate.java:6732-6797`. 실행 중 치트앱(gamecih 등) 프로세스 탐지 — `Paladog.java:695-745`.
- [확인] **슬롯(GAMESAVESLOTINFO) 주요 필드** (`GAMESAVESLOTINFO.java:205-255`): `iDifficulty, iCurGold, iCurExp, dwPlaySec, iSkillLevelCur[100], iUnitLevel[50], iStageStar[300], dwInven[200], dwEquip[20], iStagePlaySec[300], iTutorialState[20], cNeedSkillUp[1000], iLevel2Allow, dwCostume[20], iCostumeCur, iStartSlot, iNhskpt(미사용 스킬포인트), strUDID`.
- [확인] **계정 공통(GAMESAVEINFOETC)** (`GAMESAVEINFOETC.java:12-87`): `iCurGem, iCurStone, iCurRebirth, cAchieve[100], iDarkdogAllow, iUnlockEquipSlot(+Dark,02), cDarkStageAllow[40], iLastSlot, 볼륨/진동/품질 설정, 랭킹 캐시`. → **젬·스톤·부활·업적은 슬롯 간 공유, 골드·레벨·유닛은 슬롯별**.
- 리메이크 권장: Roblox DataStore에 위 2계층(Account/Slot) 그대로 매핑. 암호화 불필요(서버 권한).

### A8. 네트워크/수익화 (요약)
- [확인] IAP 상품코드 `pal001/pal003/pal004/pal005` → 젬 **1000 / 3600 / 13000 / 30000** — `com/SPC/SP.java:13-16,52-55`, 지급 `AppDelegate.purchaseOk(String)` `AppDelegate.java:7572-7590`.
- [확인] **이 빌드는 결제 우회**: `BuyItemActivity()` 가 Google Billing 없이 바로 `purchaseOk(PID)` 호출 — `Paladog.java:100-106`. (패치판 근거)
- [확인] 서버: `game.paladog.net/paladog_KorGG/*.php`(인증/FB로그인), `kakao.palamini-game.com/paladog/*`(배너, 치트목록) — `SP.java:41-59`, `CM.java:5297-5298`. 서버가 젬 지급 가능(`iGemFromServer`) — `LoginLayer.java:1421,2531`.
- [확인] 소셜: Facebook(친구 랭킹/초대), NHN LINE(`NHNLine*` 스텁 다수 `AppDelegate.java:6800-6886`), Tencent AppleJuice(스텁), GCM 푸시. 리메이크 범위 밖.
