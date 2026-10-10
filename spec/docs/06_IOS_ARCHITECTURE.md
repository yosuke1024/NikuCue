# 06. iOSアーキテクチャ / 実装契約

## 1. 採用技術

| 要素 | 決定 |
|---|---|
| UI | SwiftUI。NavigationStack + sheet。新規iOSネイティブ |
| 猫 | SpriteKitの2D rig。SwiftUIのSpriteViewで表示。[S01] |
| ローカルデータ | SwiftData。CloudKit同期を無効にした構成。[S02][S03] |
| 通知 | UserNotifications。ローカル通知のみ。[S04] |
| 課金 | StoreKit 2。広告削除の非消耗型1商品。[S06][S07] |
| 広告/同意 | Google Mobile Ads SDK + UMP。SPMで固定バージョン採用。[S09][S11] |
| ローカライズ | 同梱JSONからString Catalog相当へ変換、または型付きローカル辞書。下記契約を守る |
| テスト | 純粋DomainのUnit Test、保存層Integration Test、XCUITest、StoreKit Test |
| CI | まずローカル。GitHub Actionsの有料macOS runnerは自動追加しない |

iPhone先行を優先し、前段で候補だったFlutterは今回は採用しない。OS連携と2D描画の橋渡しを減らすための設計判断。AndroidへはUI/通知/広告層の作り直しが必要であり、「そのままAndroid対応」とは約束しない。仕様・文言・アート・データ形式は再利用可能にしておく。

Deployment TargetはiOS 17を初期値にする。これは使用可能な旧OSの下限。App Store提出時に必要なXcode/SDKのバージョンとは別で、実装/公開時に公式提出要件を確認する。確認時の公式資料は2026-04-28以降Xcode 26以降・iOS 26 SDKを要求している。[S16]

## 2. 推奨構成

```text
App/
  NikuCueApp.swift, AppContainer.swift, AppConfiguration.swift
Domain/
  Habit, HabitSchedule, HabitDayKey, DayStatus, CatEvent, CatState
  HabitService, CalendarService, CatReactionEngine, ProgressCalculator
Data/
  SwiftDataModels, HabitRepository, BackupService, MigrationPlan
Features/
  Onboarding, Home, HabitEditor, History, Settings, Purchase
Character/
  CatScene, CatRig, CharacterArtProvider, AnimationLibrary, CatSceneController
Services/
  LocalNotificationService, PurchaseService, AdConsentService, BannerService
Resources/
  Strings, Reactions, Character, PrivacyInfo.xcprivacy, StoreKitTest.storekit
Tests/
  DomainTests, RepositoryTests, ReactionTests, NotificationTests, PurchaseTests, UITests
```

DomainをSwift Packageに切り出してもよいが、依存を増やさない。広告・購入・猫の描画がDomainへimportされないことが重要。

## 3. データモデル

| Model | フィールド/制約 |
|---|---|
| Habit | UUID id、name、category、sortOrder、createdAtUTC、startDayKey |
| HabitScheduleVersion | UUID id、habitId、effectiveFromDayKey、isActive、weekdayMask（1〜7） |
| HabitDayRecord | unique recordKey=`habitId:dayKey`、habitId、dayKey、status(done/skipped)、recordedAtUTC、timeZoneID、revision |
| CompanionProfile | nickname、didCustomizeName、firstOpenedAt、lastHomeDayKey、seenMilestones Set<Int>、seenAllDoneDayKeys |
| UserPreferences | language(system/th/en/ja)、haptics、reduceMotion、onboardingStep、hasFinishedFirstSession |
| ReminderSlot | id、enabled、hour、minute、weekdays |
| DiagnosticBuffer | 明示opt-inの場合のみ端末内。イベント種別と相対時刻/集計。上限1,000件 |

HabitScheduleVersionはactive/inactiveを含む履歴。アーカイブ/再開/曜日変更は翌日からの版を追加。同じeffectiveFromDayKeyを編集中は版を置換し重複させない。最大5件は有効なHabit数で判定。アーカイブ予約後も当日は有効に数えるので、新規追加枠は翌日に空くことを表示する。

予定版は作成前に遡らない。habitIdの参照整合性を保証。名前の変更履歴は持たない。backupはこのモデルに対応したversioned DTOへ変換する。

## 4. 書込/並行性

Repositoryの書込は一つのactorへ集約。Domainから`setStatus(habitId, dayKey, desiredStatus, expectedRevision?)`を呼ぶ。idempotent upsertで、done→doneならnewlyCompleted=falseを返す。

保存層は「保存結果」「変更の有無」「変更後集計」「revision」を返す。UIは保存成功前に永続達成扱いしない。失敗時rollbackし、再試行できるエラーへ変換する。

同時操作・連打・日跨ぎでもunique recordKeyが壊れない。SwiftDataのunique属性だけに頼らずDomainの冪等性とRepositoryの直列化で守る。

## 5. サービス境界

- `Clock`: now / timezoneを注入可能。テストで実時計を使わない。
- `HabitRepository`: CRUD、予定版、記録、atomic backup replace。UIへModelContextを直接公開しない。
- `CatReactionEngine`: Snapshot + Event → ReactionIntent?。I/Oなし・テスト可能。
- `CatSceneController`: ReactionIntent → SKAction。DB書込禁止。
- `PurchaseService`: entitlementsのstream、loadProduct、purchase、restore。UIは価格を定数にしない。
- `AdConsentService`: UMPの状態と表示可否。自作のtrue/false同意で代用しない。
- `BannerService`: consent/purchase/UI eligibilityが全て許可した時だけrequest。
- `NotificationService`: 設定からrequest一覧を作り差分適用。

## 6. 起動順

ローカルDB/設定を読み込む → Home/Onboardingを表示。
並行してTransaction.updates監視と権利確認。
有料/不明なら広告は起動しない。初回一巡終了後の無料ユーザーのみUMP確認 → 許可状態で広告SDK初期化 → Homeバナーを要求。
どのネット処理が失敗しても猫と記録を止めない。購入状態・同意・Home可視性の三つが変わった時に広告gateを再計算する。

## 7. 開発/本番設定

`AppConfiguration`にbundle ID / product ID / AdMob app ID / ad unit ID / privacy URL / support URLを注入する。本番値はownerが確認して登録する。

未設定でもDebugはMockで起動。Releaseはプレースホルダが残っていれば明示的にビルド検証で失敗。Mockの権利を本番DBへ持ち込まない。実際のTestFlightはStoreKit Sandboxと公式test adsで試す。

SwiftPM dependenciesは固定しPackage.resolvedを記録。初回にSDKのmin OS、privacy manifest、必要Info.plist設定を現行公式資料で確認する。古いGADクラス名と新しいSwift名を混ぜて架空APIを書かない。

## 8. ローカル品質検証

Xcode存在確認、選択中developer directory、利用可能Simulator一覧、プロジェクトscheme一覧を確認してからxcodebuildを実行。既存のSimulator名/OSがあると決めつけない。
実行例は環境に合わせて正しいscheme/destinationへ置換し、実際のコマンドをログへ残す。

```sh
xcodebuild -version
xcrun simctl list devices available
xcodebuild -list -project NikuCue.xcodeproj
# 実在するschemeとSimulatorのUDIDを確認してから:
# xcodebuild test -project NikuCue.xcodeproj -scheme NikuCue \
#   -destination 'platform=iOS Simulator,id=<CONFIRMED_UDID>'
```

アプリのローカルデータを消してテストを通す処理をProductionコードに含めない。migration失敗はデータ保持優先。
