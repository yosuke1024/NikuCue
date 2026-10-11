# NikuCue 実装ログ

このファイルは `CLAUDE.md` の作業規約に従い、決定・変更ファイル・実行コマンド・結果・未実施項目を記録する。
「試せなかった項目」は成功扱いせず、**未実施: 理由** として残す。

## 0. 環境調査（2026-10-10, セッション開始時）

| 項目 | 結果 |
|---|---|
| 作業場所 | Claude Code クラウドコンテナ（Linux, Ubuntu 24.04, x86_64） |
| リポジトリ | `yosuke1024/NikuCue`、初期状態はコミットなし。作業ブランチ `claude/exciting-hypatia-ykvvz2`（セッションで指定されたブランチ） |
| 既存コード/未コミット変更 | なし（空リポジトリ。壊すものはない） |
| macOS / Xcode / xcodebuild / xcrun / Simulator | **なし**（Linux コンテナ。`xcode-select`・Simulator は存在しない） |
| Swift toolchain | 初期状態なし。`download.swift.org` / `static.swift.org` はネットワークポリシーで遮断（403）。Docker daemon なし。Docker Registry HTTP API 経由で公式 `swift` イメージのレイヤを取得して純Swiftロジックのテストを試みる（結果は後述） |
| 利用可能 | Python 3.13（Pillow あり）、Node 22 + Playwright 1.56 + Chromium、ImageMagick 6、ffmpeg、git |
| ネットワーク | GitHub API / PyPI / apt / Docker Registry / developer.apple.com は到達可。swift.org のダウンロードは不可 |

### この環境での方針（`00_START_HERE.md` 「開発環境がない場合」に従う）

- iOS ビルド・Simulator 実行・XCUITest・StoreKit Test・実機録画は **未実施** として残す。「ビルド成功」とは書かない。
- 移植可能な Swift ソース、純粋ロジック（Domain / ReactionEngine / 日付）の Unit Test、JSON 契約の検証、レビューを進める。
- 猫の見た目を今の環境で確認できるようにするため、同じ JSON 契約（`character_spec.json` / `animations.json` / 本リポジトリで追加したパス定義）から描画する **開発用ブラウザプレビュー**（`tools/rig-preview/`）を用意し、Playwright/Chromium で静止画と動画を記録する。これは iOS Simulator の記録ではない（ラベルを明記する）。描画ロジックの正本は Swift 側であり、プレビューは絵・pivot・タイミングの確認用で、出荷物ではない。
- Apple の公開要件（developer.apple.com/news/upcoming-requirements、2026-10-10 取得）: 2026-04-28 以降は **Xcode 26 以降・iOS 26 SDK** でのビルドが必須。Deployment Target は仕様どおり iOS 17 を初期値とする。

### git push について

`00_START_HERE.md` は「承認前の GitHub への push」を禁じている。一方、このセッションはオーナーが作業ブランチ `claude/exciting-hypatia-ykvvz2` を指定して開始しており、コンテナは一時的で push しないと成果が失われる。
→ **指定された作業ブランチにのみ push する**（`main` には触れない。Pull Request は作らない。公開・配信・課金設定の変更は一切行わない）。この解釈に問題があればオーナーが差し戻せるよう、ここに明記する。

## 1. 作業計画（P00 → P01 → バックログ順）

| タスク | 本環境でできること | 未実施として残すもの |
|---|---|---|
| P00 | リポジトリ構成、Xcode プロジェクト（手書き pbxproj、Xcode 16+ の同期フォルダ形式）、`AppConfiguration` のプレースホルダ + Mock 構成、ログ | `xcodebuild` 起動確認、Simulator 一覧 |
| P01 | SpriteKit rig（Swift）、`CharacterArtProvider`、`AnimationLibrary`、`CatSceneController`、デモ画面、ブラウザプレビューでの画像/動画記録 | Simulator / 実機の録画、Reduce Motion の OS 連携確認 |
| P02 | Gallery 画面、全8クリップ、JSON 参照検証テスト | 実機での継ぎ目確認 |
| P03 | Domain（日付・予定版・集計・反応選択）の Unit Test（Linux Swift で実行できれば実行する） | ― |
| P04 | SwiftData Repository、Backup DTO、検証ロジック（純粋部分はテスト） | SwiftData の実行テスト |
| P05〜P10 | SwiftUI 画面、通知、StoreKit 2、広告ゲート（Mock） | 画面・通知・購入・広告の実行確認 |
| P11〜P12 | QA シナリオの対応表、アイコン生成（editable source + 1024px PNG + 小サイズプレビュー） | 実機 QA、審査準備の人間確認 |

## 2. 変更履歴

（タスクごとに追記）

### P00 環境調査 / プロジェクト生成 / Mock 構成（2026-10-10）

**決定**

| ID | 決定 | 理由 |
|---|---|---|
| D-P00-1 | `NikuCue.xcodeproj` を Python スクリプト（`tools/xcodeproj/generate_pbxproj.py`）で生成する。Xcode 16 以降の `PBXFileSystemSynchronizedRootGroup` 形式 | Linux には Xcode がない。同期フォルダ形式ならファイル追加のたびに pbxproj を編集しなくてよい。`tools/xcodeproj/validate_pbxproj.py` で参照整合性を検査（Xcode で開く検証は未実施） |
| D-P00-2 | Domain を `Packages/NikuCueDomain`（ローカル SwiftPM、Foundation のみ）に分離 | docs/06 §2「広告・購入・猫の描画が Domain へ import されない」をコンパイル境界で保証し、Linux の Swift でも `swift test` できる |
| D-P00-3 | アプリ側は Swift 5 言語モード（`SWIFT_VERSION = 5.0`、`SWIFT_STRICT_CONCURRENCY = targeted`）、Deployment Target iOS 17.0、iPhone のみ・縦向き | Xcode でコンパイルできない環境で書くため、Swift 6 モードの厳格な Sendable 検査による未検証エラーを避ける。Domain は `StrictConcurrency` を有効にして警告ゼロを維持。macOS でビルドできたら Swift 6 モードへ切替を検討（TODO） |
| D-P00-4 | Swift toolchain として SwiftWasm 配布の `swift-wasm-6.0.3-RELEASE` (Ubuntu 22.04 向け Linux ホスト toolchain) を `/tmp/swift-toolchain` に展開して使用 | swift.org のダウンロードは遮断。Docker daemon なし。GitHub Releases は到達可能。ホスト toolchain は通常の Swift 6.0.3（`swift --version` で確認）。iOS SDK は含まれないので Domain パッケージのみビルド可能 |
| D-P00-5 | 本番 ID は `NikuCue/App/AppConfiguration.swift` の `REPLACE_WITH_` placeholder、bundle ID は `placeholder.nikucue.app` | 推測禁止（CLAUDE.md）。Release ビルドでは Run Script `scripts/check_release_config.sh` が placeholder を検出して失敗（QA Q36 の設計）。Debug は Mock で起動 |
| D-P00-6 | 同梱 JSON は `NikuCue/Resources/` に複製し、`scripts/check_resources.py` で `spec/` との同一性（文言・反応）と、記録済み差分（キャラ rig）を検証 | パックの JSON をビルド時入力として同梱する（CLAUDE.md 8）。差分は `docs/SPEC_REVISIONS.md` |

**作成ファイル**: `CLAUDE.md`（パックと同一）, `README.md`, `.gitignore`, `NikuCue.xcodeproj/`, `NikuCue/App/*`, `NikuCue/Resources/*`, `Packages/NikuCueDomain/*`, `NikuCueTests/*`, `scripts/*`, `tools/*`, `docs/*`, `spec/*`

**実行したコマンドと結果**

```text
python3 -I spec/scripts/validate_pack.py            → PASS（169 keys × 3, 26 nodes, 8 clips, 16 reactions, 40 QA）
sha256sum -c spec/SHA256SUMS.txt                    → 28 件 OK
python3 -I scripts/check_resources.py               → PASS
python3 -I tools/xcodeproj/generate_pbxproj.py      → wrote NikuCue.xcodeproj
python3 -I tools/xcodeproj/validate_pbxproj.py      → PASS（参照整合性のみ）
/tmp/swift-toolchain/.../swift --version            → Swift version 6.0.3 (swift-6.0.3-RELEASE) x86_64-unknown-linux-gnu
cd Packages/NikuCueDomain && swift build            → 成功（警告 0 を目標。Sendable 警告は修正済み）
cd Packages/NikuCueDomain && swift test             → 下記 P03 の節を参照
```

**未実施（理由: macOS / Xcode / Simulator がない）**: `xcodebuild -version`, `xcrun simctl list`, `xcodebuild -list`, アプリターゲットのビルド、`NikuCueTests` の実行、Xcode での pbxproj の読込確認。

### P01 猫 rig の縦切りデモ（2026-10-10）

**実装**（`NikuCue/Character/`, `NikuCue/Features/Demo/`）

- `RigSpec` / `ArtPaths` / `AnimationSpec`: 同梱 JSON のデコードと構造検証（`validate()`）。
- `CharacterArtProvider` protocol + `VectorArtProvider`: `mali_paths.json` の M/L/C/Q/Z パスを `CGPath` にして `UIGraphicsImageRenderer` で一度だけテクスチャ化（part × 表情 × 解像度でキャッシュ）。毎フレームのパス生成なし。承認済み PNG への差し替えは provider の差し替えで可能（state machine 無変更）。
- `CatRig`: `character_spec.json` の親子ノード（26 ノード、z-order は contract の値）。rest transform を保持し `resetToRest()`。目と口は 2 枚のスプライトで 100ms クロスフェード。
- `AnimationLibrary`: `animations.json` の keyframe tracks → キー付き `SKAction.customAction`。rest からの相対値で適用。瞬きは 4〜7 秒の seeded 間隔。
- `CatSceneController`（`@MainActor`、DB 書込なし）: `ReactionQueue`（実行 1 + 待機 1）、ambient（idle / doze）、pause / resume（離脱で待機破棄・古い反応を再生しない）、Reduce Motion（跳躍・ハート移動なし、表情クロスフェードのみ）、ハート最大 3 つ、吹き出しの dwell（動きの終了と独立）。
- `CatScene`（1 インスタンス、`resizeFill`）、`CatSceneView`（`SpriteView` 30fps、VoiceOver ボタン化）、`CatDemoView`（できた（デモ）/ 休む / なでる / Reduce Motion / 朝昼夜）。デモイベントは `isDemo = true` で統計・節目に影響しない。

**絵の反復（オーナー指摘「全然可愛くない」→ REV-007）**

1 回目: 仕様値のまま（胴 365×410、目 29×39、目の位置が顔の上半分）→ 硬い・人形的。
2 回目: 頭 540×430 / 胴 400×340 / 目 64×80 を顔の下寄りに、前足 96×150、頬・ひげ追加 → 胴が小さすぎる、眠い目が睨みに見える。
3 回目（現状）: 頭 510×400 / 胴 440×360 / 前足 100×160、眠い目を閉じた弧に、しっぽを外へ。`docs/SPEC_REVISIONS.md` REV-007。最終判定は G1（Yoh と最初の利用者）。

**記録物（ブラウザ描画。Simulator / 実機の記録ではない）**: `artifacts/P01/` — 待機・5 表情・celebrate の 10 フレーム・pet / greet / cheer / settle / doze / milestone・夜の部屋（PNG 23 枚）、`mali_rig_preview_30s.mp4`（30 秒: idle → greet → pet → celebrate → settle → milestone → doze）、`contact_sheet_64px.png` / `contact_sheet_180px.png`。
共有用プレビュー（同じ JSON をブラウザで描画、タップ・全クリップ・表情・Reduce Motion を操作可能）: https://claude.ai/artifact/S3rXqf6ReZcbdC3Nhamoqq

**受入基準との対応**

| 基準 | 状態 |
|---|---|
| idle / pet / celebrate | 実装・ブラウザ描画で確認。iOS 実行は未実施 |
| 3 表情（5 実装） | 実装・ブラウザ描画で確認 |
| pause / 復帰 | `CatSceneController.leaveScene / enterScene`、`scenePhase` 連動を実装。`NikuCueTests/CatSceneControllerTests` を用意（未実行） |
| Reduce Motion | app 設定 OR OS 設定で `reducedMotionTracks` を使用。ブラウザ描画で確認 |
| 30 秒録画 | `artifacts/P01/mali_rig_preview_30s.mp4`（ブラウザ） |

**未実施**: Simulator / 実機での描画・30fps 計測・pause 確認・VoiceOver。`NikuCueTests` の実行。

### P02 Character Gallery（2026-10-10, 実装のみ）

`NikuCue/Features/Gallery/CharacterGalleryView.swift`（Debug のみ到達可）: 8 クリップ・5 表情・Reduce Motion・action 数表示。JSON 参照検証は `scripts/check_resources.py` と `NikuCueTests/CharacterContractTests`。pivot / 継ぎ目の画像確認はブラウザ描画（`artifacts/P01`）で代替、実機は未実施。

### P03 Domain / 日付 / 予定版 / 集計（2026-10-10）

**実装**（`Packages/NikuCueDomain/Sources/NikuCueDomain/`）: `DayKey`（`YYYY-MM-DD` Gregorian ASCII のみ）、`CalendarService`（Calendar の日単位演算。`seconds/86400` 不使用）、`Clock` / `ManualClock`、`WeekdaySet`（ISO 月=1…日=7）、`Habit` / `HabitScheduleVersion` / `HabitDayRecord`（`recordKey = habitId:dayKey`）、`ScheduleResolver`（版の適用日）、`HabitValidation`（拡張書記素で 1〜40 / 1〜16）、`ProgressCalculator`（done / skipped 分離、`isAllDone` / `isAllResolved`、distinct done days、今日を含む 7 日の訂正窓）、`Milestones`（3/7/14）、`HabitRepository` protocol + `InMemoryHabitRepository`（直列化・冪等 upsert・失敗注入）、`HabitService` actor（検証 → 保存 → 集計 → `CatEvent`）、`CatReactionEngine`（docs/05 §4 の順序で 1 件、pet 2 秒 cooldown、直前 2 文言を回避、seed 可能）、`ReactionQueue`（実行 1 + 待機 1）、`StringCatalog`、`ReminderPlanner`（slot × 曜日 ≤ 14、identifier prefix、差分）、`AdGate`、`BackupDocument` / `BackupValidator`。

**テスト**（`Packages/NikuCueDomain/Tests/`、56 件）: QA シナリオ Q02–Q09, Q10–Q16, Q18, Q21, Q28, Q30, Q32–Q34, Q37, Q39 に対応する純粋ロジックのケース（ファイル内に Q 番号を注記）。

```text
cd Packages/NikuCueDomain && swift test   （Swift 6.0.3, Linux x86_64）
→ Executed 56 tests, with 0 failures (0 unexpected)   2026-10-10 15:38 UTC
```

途中で見つけて直した不具合: `DayProgress` の Hashable 欠落、`XCTAssert` 内の `try await`（Swift では autoclosure 不可 → ローカル変数へ）、履歴訂正テストが習慣作成前の日を対象にしていた、undo 後の revision（記録が消えるため 0 を返し、再登録は 1 から）、バックアップの未来日（仏暦年 2569 を Gregorian key として受理していた → 出力日 +1 日より後の記録は拒否）。

**未実施**: SwiftData 実装（P04）、Xcode での同一テスト実行（macOS で `swift test` を再実行すること）。

### P04 SwiftData Repository / 移行 / バックアップ（2026-10-10, 実装のみ）

- `NikuCue/Data/SwiftDataModels.swift`: `HabitModel` / `ScheduleVersionModel` / `DayRecordModel`（`recordKey` unique）/ `SingletonBlobModel`（CompanionProfile・UserPreferences を Codable JSON で保存。項目追加に強い）/ `ReminderSlotModel`、`NikuCueSchemaV1` + `NikuCueMigrationPlan`（段階なし）、`NikuCueStore.makeContainer`（Application Support、`cloudKitDatabase: .none`。失敗時にストアを削除しない）。
- `NikuCue/Data/SwiftDataHabitRepository.swift`: `@ModelActor` で直列化。全書込は `write { }` で 1 トランザクション、失敗時 `rollback()` → 元データ維持（QA Q03 / Q39）。冪等 upsert は `InMemoryHabitRepository.apply` と同じ決定表を共有。`replaceAll` は全削除 + 全挿入を 1 save。
- `NikuCue/Data/BackupService.swift`: `nikucue-backup-v1.json` の一時書き出し、5MB 超の事前拒否、検証（Domain）→ プレビュー → 置換。
- `AppContainer`: 起動時に永続コンテナを開き、失敗なら `databaseError` を保持して `DatabaseErrorView`（再試行 / 削除しない）。
- テスト: `NikuCueTests/SwiftDataRepositoryTests.swift`（CRUD、10 連打で 1 件、revision 競合、再オープンで保持、復元で通知 OFF、全削除）。**未実行**（Simulator がない）。

### P06 CatReactionEngine 統合（2026-10-10, 実装のみ）

`NikuCue/App/CatCoordinator.swift`: `WriteOutcome.event` → `CatReactionEngine` → `CatSceneController`。`completionUndone` は演出キャンセル（悲しませない）。反応開始時に `HabitService.markShown`（節目 / 当日 allDone）を記録、待機中の反応は開始前に「今日・同じ記録・同じ revision」で再検証。`HomeViewModel` が保存 → 集計 → UI → 猫イベントの順を守り、連打は `busyHabitIds` で 1 書込に抑える。

### P08 ローカル通知（2026-10-10, 実装のみ）

`NikuCue/Services/LocalNotificationService.swift`: slot × 曜日の `UNCalendarNotificationTrigger(repeats: true)` を最大 14、identifier `nikucue.reminder.v1.<slot>.weekday.<iso>`、prefix 内だけ差分適用（QA Q18）、文言変更は同 identifier で置換（Q21）、バッジ・音なし、foreground では banner を出さない delegate、tap は Home（自動完了なし）。Mock は `MockNotificationScheduler`。画面は `ReminderSettingsView`（並行実装中）。**未実行**。

### P09 StoreKit 2 広告削除（2026-10-10, 実装のみ）

`NikuCue/Services/PurchaseService.swift`: `Transaction.currentEntitlements` で初期状態（照会完了まで `unknown`）、`Transaction.updates` 常時監視、`.verified` かつ `revocationDate == nil` のみ owned、`AppStore.sync()` は明示復元のみ、cancel は静か、pending / unverified は権利なし、二重購入開始の禁止。`NikuCue/Resources/NikuCue.storekit`（placeholder product ID の非消耗型 1 商品、scheme に添付）。`PurchaseViewModel` + `MockPurchaseService`、テスト `NikuCueTests/MonetizationTests.swift`（Q24–Q27）。**未実行**。価格は常に StoreKit から取得し定数を置かない。

### P10 UMP / 広告 / privacy manifest（2026-10-10, 部分実装）

`NikuCue/Services/AdServices.swift`: `AdConsentServicing`（UMP 境界）、`BannerService`（`AdGate` を entitlement / consent / Home 可視 / scene active / 初回セッション / 設定有効 / SDK プライバシー確認の全条件で評価。owned / unknown / 未同意では request なし、バックグラウンドで破棄、演出ごとの reload なし）、Mock 群。`GoogleMobileAdsAdapter.swift` は `#if canImport(GoogleMobileAds)` で囲み、SDK を SPM で追加するまでコンパイル対象外。
**SDK のバージョン**: developers.google.com はこの環境のネットワークポリシーで遮断されており、現行の安定版を確認できない。CLAUDE.md「バージョン番号を創作しない」に従い、SPM 依存は追加していない（owner が公式資料で版を確認して追加 → `Package.resolved` を記録 → `sdkPrivacyConfigurationVerified` を true に）。それまで広告は一切出ない。

### P12 肉球 App アイコン（2026-10-10, 暫定）

`tools/icon/generate_app_icon.py`（編集可能な元データ、幾何は Python 定数）→ `AppIcon-1024.png`（1024×1024 sRGB 不透明、角丸なし）、`artifacts/icon/app_icon_source.svg`、`preview_sizes.png`（180/120/60/40）、`preview_home_light/dark.png`。文字・カメラモチーフなし、パッド 1 + 指球 4。**R14 未完了**（Yoh の視覚承認待ち）。

### 方針変更: 猫のビジュアルは画像アセット方式へ（2026-10-10, オーナー指示）

| ID | 決定 | 理由 |
|---|---|---|
| D-ART-1 | コード描画の猫（`VectorArtProvider` + `mali_paths.json`）は**開発用プレースホルダー**に限定し、これ以上作り込まない | オーナー判断: 動作検証には十分だがビジュアル品質が製品水準ではない |
| D-ART-2 | 製品用の猫は高品質 2D イラストの原画をパーツ分けした画像を SpriteKit で動かす。rig / キーフレーム / 状態遷移 / 習慣ロジックは維持 | docs/04 §2 の「絵を差し替える時は同じ node ID と pivot を保ち `CharacterArtProvider` を差し替える」に沿う |
| D-ART-3 | 正式な原画がオーナーから提供され Gallery で承認されるまで、猫のビジュアルは未完成（R02 継続）。manifest の `isProductionArt` が承認の印 | 「完成扱いしない」指示 |

設計: `docs/CHARACTER_ASSET_PIPELINE.md`（再利用できる部品の仕分け、座標系と原画の契約、イラストレーター向け制作仕様、ランタイム設計、移行手順、リスク、確認事項）。

実装した骨組み（S1）: `NikuCue/Character/TexturePackArtProvider.swift`（manifest デコード・検証・`SKTextureAtlas` / PNG からの `PartArt`・preload）、`CharacterArtSelection`（同梱 manifest があれば texture pack、なければ placeholder）、`CharacterArtProvider.artLabel`（Gallery / Demo に表示）、`tools/character/build_texture_pack.py`（原画の書き出し → manifest・atlas・`character_spec.json` の position 更新・合成チェック画像）、`tools/character/examples/layers_export.example.json`（納品形式の例）、`scripts/check_resources.py` の texture pack 検証、`NikuCueTests/TexturePackArtProviderTests.swift`（未実行）。
現時点では texture pack を同梱していないため、起動時は placeholder が選ばれる（`check_resources.py`: "texturePack": "absent"）。

**未実施**: 原画の制作（オーナー）、取り込み（S3）、Gallery / 実機での継ぎ目確認（S4）、キーフレーム調整（S5）。

### P05 / P07 / P08 画面（2026-10-10, 並行実装 + 整合性レビュー, 実装のみ）

4 つの実装エージェントが担当フォルダ内だけにファイルを作成し、1 つのレビューエージェントがシンボル・API・文言キー・仕様の整合性を確認した（Workflow `implement-nikucue-screens`、計 22 ファイル）。

| 画面 | ファイル | 要点 |
|---|---|---|
| Onboarding O01–O05 | `Features/Onboarding/*`（4） | 猫の自己紹介 → デモ（記録なし）→ 呼び名（16 書記素）→ 最初の習慣（テンプレート 5 種）→ 通知（OS 許諾は「設定する」のみ、拒否時は設定への導線）→ 完了。各ステップで `onboardingStep` を保存し、クラッシュ後に再開 |
| Home | `Features/Home/*`（6） | 日付・履歴/設定ボタン（44pt）・猫の部屋（220/160pt）・SwiftUI 吹き出し・今日の行（Done ボタンのみ書込、行タップは何もしない）・休む/編集/並び替えメニュー・進捗行・予定なし表示・追加ボタンと 5 件上限説明・10 秒 Undo トースト・予約バナー領域（高さ 0） |
| 習慣編集 | `Features/HabitEditor/HabitEditorSheet.swift` | 名前/カテゴリ（アイコン + ラベル）/毎日・曜日チップ、「曜日の変更は明日から」常時表示、アーカイブ/再開、二段階削除。版を `HabitService.scheduleVersions()` から読み現在の曜日と archived を表示 |
| 履歴 | `Features/History/*`（4） | 月カレンダー（形と記号で状態区別、赤の失敗表示なし、未来日は不可）、日別内訳（直近 7 日のみ訂正可、訂正は保存表示のみで猫は反応しない） |
| 設定 | `Features/Settings/*`（6） | 呼び名、言語（切替後に通知文言を reconcile）、触覚、動きを減らす、通知設定（2 枠・曜日・重複拒否・拒否時導線）、バックアップ（書き出し / 取り込みプレビュー / 二重確認 / 復元後通知 OFF）、プライバシー文、ヘルプ（placeholder URL は非表示）、診断トグル、全削除（二段階、購入は保持） |
| 購入 | `Features/Purchase/PurchaseView.swift` | `PurchaseViewModel` 駆動。価格は StoreKit、復元は明示操作、価格取得失敗時は再読み込み |

**整合性レビューの指摘と対応（8 件、すべて反映）**: 編集シートが版を読まず常に「毎日」表示 → `scheduleVersions()` を読む／今日の予定にない習慣とアーカイブ済み習慣に編集導線がない → Home に編集専用の行を追加／購入画面が無効のプレースホルダー → 実装に置換／並び替え未実装 → メニューに上へ/下へ（`habit.moveUp/moveDown` キー追加、REV-L10N-1）／カテゴリアイコンが onboarding と Home で不一致 → 共通化／Undo トーストが最下行を隠す → 余白 88pt／履歴の読み込み中に未来日がタップ可能 → 日付キーでも判定／Undo ボタンの幅 44pt 未満 → 修正。

**追加した文言キー**（3 言語、REV-L10N-1）: `habit.moveUp`, `habit.moveDown`, `common.more`, `history.previousMonth`, `history.nextMonth`, `home.otherHabits`, `home.archivedHabits`。タイ語はネイティブ確認対象（R03）。

**未実施**: アプリターゲットのコンパイル、Simulator 表示、XCUITest、タイ語レイアウト確認、通知の実機確認。レビューは静的（エージェントによる読み合わせ）であり、型検査の代わりにはならない。

### アプリ側コードのレビュー（2026-10-10, Workflow `review-nikucue-app-swift`、静的レビュー）

4 つの観点（コンパイル可否・猫仕様準拠・ライフサイクル/並行性・Xcode プロジェクト）で読み合わせ、各指摘を 3 名の反証担当が検証する構成。検証完了前に、コードを読んで明白だった指摘を先に修正した（コミット `e972780`）:

| 指摘 | 対応 |
|---|---|
| `CatRig.resetToRest()` が root ノードまで戻し、最初のクリップ後に scene のレイアウト（scale / 位置）が壊れる | root を除外 |
| Demo / Gallery / Onboarding / Home が同じ controller を onAppear / onDisappear で奪い合い、NavigationStack の順序で猫が止まる | scene の所有者（owner）を導入。他画面からの leave は無視 |
| pause が 1 つの bool で、モーダル中に background → foreground すると再開してしまう | pause 理由の集合（inactive / modal / sceneLeft）に変更 |
| undo で実行中の演出を止めると、待機中の有効な反応が取り残される | キャンセル後に待機を再検証して開始 |
| 吹き出し / VoiceOver 値が controller を observe していない（Demo / CatRoom / Gallery） | `@ObservedObject` に変更 |
| `SKAction.colorize` は SKScene には効かない | 背景色を補間する customAction |
| リソース読込失敗時の fallback が `try!` で同じ init を再実行し起動時にクラッシュ | `AppRoot` が失敗を保持し、エラー画面を表示 |
| `Localizer.loadBundled()` が MainActor 隔離で非同期でないテストから呼べない | `nonisolated static` |
| Release ゲートが `placeholderMarker` 定数自身に反応し、本番値を入れても失敗する | `REPLACE_WITH_[A-Z]` に変更 |
| sandbox 化された Run Script が宣言していない `.sh` を読めずビルドが失敗する | ゲートを shellScript に inline、入力は `AppConfiguration.swift` のみ |
| `.storekit` がアプリの Resources にコピーされる可能性 | `PBXFileSystemSynchronizedBuildFileExceptionSet` で除外 |
| `RigSpec.validate()` が重複 ID で trap | `uniquingKeysWith` |

検証担当の結論が揃った時点で残りの指摘（scheme の StoreKit 構成ファイルの相対パス等）を反映する。これらは静的レビューであり、Xcode での型検査・実行の代わりではない。

**レビューの検証結果（Workflow 完了）**: 生の指摘 29 件 → 重複除去後 27 件を各 3 名で反証。確定 3 件（sandbox 化 Run Script がスクリプトを読めない／`Localizer.loadBundled()` の MainActor 隔離／`try!` fallback）はいずれも上記の先行修正で解消済み。却下 24 件の大半は、検証時点で既に修正されたコードを読んだため「再現しない」と判定されたもの。先行修正の対象外で却下されたのは scheme の StoreKit 構成ファイルの相対パス（Xcode の慣例どおり `../../<folder>/<file>.storekit` のまま維持。macOS で要確認）と `UIScreen.main` によるテクスチャ密度（iOS 17 では利用可。将来 trait から取得に変更可）。

### 第 2 回レビュー（2026-10-10, Workflow `review-nikucue-screens-compile`、静的レビュー）

対象: 画面 22 ファイル、Services / Data / App、`CatSceneController` 以降の変更。3 観点 → 16 件 → 各 2 名の反証で確定 14 件（重複を含む）、却下 2 件。確定分はすべて反映した:

| 指摘 | 対応 |
|---|---|
| Home の表示/非表示で広告ゲートを再評価していない（docs/08 §2–§3） | `homeAppeared / homeDisappeared` で `reevaluateAdGate()` |
| UMP の同意確認 `gatherConsentIfNeeded()` に呼び出し元がない、同意変更でゲートが再評価されない | Home 表示時に起動ごと 1 回（権利 unknown では消費しない）、`adConsent.addObserver` でゲート再評価 |
| 初回セッション終了判定が「background 時に Home が画面上」に限定され、設定画面から background すると保存されない | `hasShownHome`（起動内で一度でも Home を表示）で判定 |
| 通知時刻を変えても identifier と文言が同じなら OS に反映されない | trigger の weekday / hour / minute も比較して再登録 |
| DB エラー画面の「再試行」が `exit(0)` | `AppRoot.retry()` でコンテナを再構築（ストアは削除しない）、サポート連絡先は実値設定後に表示 |
| 設定の読込失敗を「初回」とみなしてオンボーディングへ戻す | `AppState.loadError` を保持し再試行画面へ |
| 日跨ぎ処理が Home 非表示中に挨拶を消費する | 非表示中はデータ再読込のみ |
| アーカイブ済み習慣の曜日変更が保存されない | `!isArchived` 条件を削除（版は inactive のまま） |
| デモ画面の「動きを減らす」が別設定（`@AppStorage`） | アプリ設定（`UserPreferences.reduceMotion`）に束縛 |
| 時間帯の変化で部屋の色が更新されない | 毎分の tick で `refreshTimeOfDay()` |
| オンボーディングの曜日チップが 375pt 幅で 44pt 未満 | 間隔 6 → 4 |

却下（反証成立）: 編集シート表示中に猫を pause しない（モーダルは短時間で演出継続が仕様上問題なし）、`.inactive` でバナーを破棄する（仕様どおり）。

### Mali 原画 v1（全身 6 枚）の取り込み（2026-10-10, オーナー提供 `NikuCue_Mali_Assets_v1.zip`）

オーナーが承認済みコンセプト A の全身イラスト 6 枚（idle / happy / celebrate / pet / sleepy / sad、1024 × 1024 RGBA）と README・統合メモ・manifest を提供。コード描画の猫を置き換え、既存の SpriteKit 状態遷移と習慣ロジックは維持した。6 枚はボーンアニメーションではなく**ポーズ差し替え + 軽い動き**として扱う（アセット README §6 のとおり。瞬き・しっぽ・手足の動きは別レイヤーが来るまで作らない）。

| ID | 決定 | 根拠 |
|---|---|---|
| D-WB-1 | 全身テクスチャ用の rig を**別契約**（`mali_wholebody_spec.json` / `mali_wholebody_animations.json` / `mali_poses.json`）として同梱し、`character_spec.json` / `animations.json`（パーツ rig）は無変更で残す | パーツ分け原画が来たとき既存契約へ戻せる。`AppContainer` は `CharacterArtSelection` の順（全身 → テクスチャパック → placeholder）で rig と track を読む |
| D-WB-2 | rig の「表情」を「look」に一般化（パーツ rig = 表情名、全身 rig = ポーズ名）。既存の反応意図（`Expression`）は `expressionMap` でポーズへ写す（neutral→idle, softSmile/closedHappy/curious→happy, sleepy→sleepy） | `CatReactionEngine` / `ReactionQueue` / `CatSceneController` の API を変えずにポーズを切り替えるため |
| D-WB-3 | クリップ → ポーズ: idle→idle, greet→happy, pet→pet, celebrate→celebrate（1300 ms で happy）, cheer→happy, settle→idle, doze→sleepy, milestone→celebrate（1500 ms で happy）。`sad` はどのクリップにも割り当てず Debug Gallery でのみ表示 | アセット manifest の `clip_mapping` と README「skip / pause で sad を出さない」 |
| D-WB-4 | 動きは README の上限内: 呼吸 scaleY ≤ 1.2 %、celebrate は +34 units の持ち上げ（420 ms 上昇 / 680 ms 着地、影の縮小と淡化）、pet は 3° + scale 1.02、cross-fade 180 ms、瞬きなし（`ambient.blink.enabled=false`）、Reduce Motion はポーズ切替のみ | 一枚絵を伸縮させない（README §4） |
| D-WB-5 | 各ポーズは同じ 1024 フレームのまま、ポーズごとの alpha 下端を床（root）に合わせる `bounds` を持つ（celebrate は座りより 27 px 低い） | README「同じ座標空間・床の位置を安定させる・実行時に個別クロップしない」 |
| D-WB-6 | rig フレームを 1024 × 1066（root = (512, 60)、`designSize` = [908, 1066]）と定義。`CatScene` は designSize を画面の 92 % に収め root を下端 6 % に置くので、最も高い celebrate（床から 966）+ 持ち上げ 34 とハートがフレーム内に収まる | 最初のキャプチャで耳とハートが上端で切れた（下記の不具合 1） |

**取り込み結果**（`tools/character/import_wholebody_pack.py`）: 縁取りの掃除（alpha < 8、および不透明部の 4 px 膨張の外にある孤立画素を透明化。色は変更しない）で除去した画素は idle 4112 / happy 4279 / celebrate 4344 / pet 4193 / sleepy 4251 / sad 3920。原本は `docs/assets/mali_v1/` に保持し、掃除済みを `NikuCue/Resources/Assets.xcassets/Mali/Mali<Pose>.imageset` に生成。確認画像 `artifacts/mali-assets-v1/inspection_{light,dark}.png`。

**変更ファイル**: `NikuCue/Character/WholeBodyArtProvider.swift`（新規: `WholeBodyPosePack` デコード・検証、ポーズごとのテクスチャを遅延読込、anchor = bounds から算出、影とハートは placeholder provider に委譲、`purgeCache`）、`CharacterArtProvider.swift`（`art(for:look:pixelsPerUnit:)`）、`TexturePackArtProvider.swift`（`CharacterArtSelection.wholeBody`、`rigResourceName` / `animationResourceName`）、`RigSpec.swift`（`expressionMap`、`designSize`、node `scale`、`look(for:)`、clip `defaultLook`、blink `enabled`）、`CatRig.swift`（`look` / `setLook(_:blend:)` の 2 枚スプライト cross-fade、`designSize`、`hasEyeParts`）、`AnimationLibrary.swift`（expression track がポーズ名を運ぶ）、`CatSceneController.swift`（瞬きは目ノードがあり `blink.enabled != false` のときのみ）、`App/AppContainer.swift`（選択順と whole-body 検証）、`Features/Gallery/CharacterGalleryView.swift`（6 ポーズのボタン）、`NikuCueTests/WholeBodyArtProviderTests.swift`（新規: 契約検証・画像セット読込・cross-fade・選択順。未実行）、`CharacterContractTests` / `TexturePackArtProviderTests`（look 化）、`scripts/check_resources.py`（§5c: 画像セット・bounds・clipPoses・settle が guilt ポーズでない・expressionMap・可動域・**フレーム内に収まること**）、`tools/character/generate_wholebody_tracks.py`（新規）、`tools/rig-preview/`（全身モード、`CatScene.layoutRig` と同じ配置、瞬きガード、`?record=1` 録画レイアウト、サムネイルは画像デコード後に描画）。

**実行したコマンドと結果**:

```sh
python3 tools/character/import_wholebody_pack.py      # 6 imageset + mali_poses.json + mali_wholebody_spec.json（designSize [908, 1066]）
python3 tools/character/generate_wholebody_tracks.py  # mali_wholebody_animations.json（8 clips）
python3 -I scripts/check_resources.py                 # PASS, "wholeBodyPoses": "present (6 poses, 8 clips, frame 1024x1066)"
python3 -I tools/xcodeproj/validate_pbxproj.py        # PASS: 33 objects
cd Packages/NikuCueDomain && swift test               # Executed 56 tests, with 0 failures（Domain は無変更）
python3 tools/rig-preview/build.py && node tools/rig-preview/capture.mjs --out artifacts/mali-assets-v1/preview --video
```

**記録物（ブラウザ描画。Simulator / 実機ではない）**: `artifacts/mali-assets-v1/contact_sheet_{light,dark}.png`（6 ポーズ × 明暗）、`artifacts/mali-assets-v1/preview/*.png`（idle、celebrate 0 / 420 / 680 / 1300 ms、pet、greet、cheer、settle、doze、milestone のハート、夜の部屋）、`artifacts/mali-assets-v1/preview/browser_render_mali_v1_30s.mp4`（32 秒: 待機 → greet → なでる → できた → 休む → 節目 → 夜の部屋で doze → 暗い面で待機となでる）。対話プレビュー（非公開 Artifact、オーナーのみ閲覧可）: https://claude.ai/artifact/S3rXqf6ReZcbdC3Nhamoqq

**キャプチャ確認で見つけて直した不具合**: (1) 最初の配置では耳の先が上端に接し、節目のハート（y = 920）がフレーム外だった → rig フレームと designSize を再定義（D-WB-6）、ハートは celebrate の alpha を測って空いている角（[-360, 840], [320, 860], [440, 620]、上昇 80）へ。(2) ブラウザプレビューの瞬きが目ノードの無い rig で例外を投げ、4 秒で描画ループが止まった（録画の 1 回目で発覚）→ 目ノードと `blink.enabled` を確認してから瞬き。Swift 側は元から `hasEyeParts` で守られている。(3) 初期 look が `neutral` でポーズが引けず影だけ描かれた → 初期 look は `expressions[0]`。

**静的レビュー（エージェントによる読み合わせ、コンパイルの代わりではない）**: コンパイル上の指摘なし。確定して直したもの: (a) `playDemo(.celebrate)` 直後の `look` 検証が、expression track の `SKAction`（SKView 無しでは評価されない）に依存していた → クリップ開始時に t = 0 の look を同期的に適用（`setLook` は同じ look を無視するので二重 cross-fade にならない）。(b) `preload` に呼び出し元がなく、初回の cross-fade で 1024² PNG をメインスレッドで復号していた → `AppContainer` 初期化末尾で全身ポーズを preload（起動コストは未計測）。(c) cross-fade 中の再切替で半透明のテクスチャが alpha 1 に跳ねる → 現在の alpha を引き継ぎ、fade 後に back のテクスチャを解放。(d) `purgeCache` に呼び出し元がない → `didReceiveMemoryWarningNotification` で全 provider の cache を破棄。却下: 「各ポーズの alpha 重心（x ≈ 545–565）で横位置を補正する」は、重心がしっぽで右に寄っているだけで胴体は中央にあり、ポーズごとに補正すると cross-fade で横に跳ぶため不採用（README「同じ座標空間を保つ」）。

**オーナーに見てほしい点（R02 の判断材料）**: cross-fade のみなので、ポーズ間で頭の大きさ・体の向きが少し違い（例: celebrate は体が右へ回り頭が大きい、pet は首をかしげる）、切替時にシルエットが「跳ぶ」。これは一枚絵の宿命で、瞬き・しっぽ・耳などの追加レイヤーが来れば idle 中の動きを足せる。影は placeholder の楕円（#D7C9B8）のままで、暗い面では灰色の円盤に見える（原画の影を使うなら 1 枚追加）。縁取りの掃除は保守的なので、暗い面で薄い輪郭が残っていないか確認（`contact_sheet_dark.png`）。

**未実施（この環境に macOS がない）**: アプリターゲットのコンパイル、`WholeBodyArtProviderTests` を含む XCTest、Simulator / 実機での表示と画面録画、メモリ（1024² × 6 枚、ポーズごとに遅延読込、メモリ警告で `purgeCache`）、30 fps 確認。手順は `docs/OWNER_NEXT_STEPS.md` §4。「6 枚で高度なアニメーションが完成した」とは扱わない。`isProductionArt: false`、R02 は開いたまま。

### 待機中の呼吸と尻尾の揺れ（2026-10-11, オーナー要望「もっと生きてる感じに」）

| ID | 決定 | 根拠 |
|---|---|---|
| D-WB-7 | 待機（idle）に、見える呼吸（縦 +1.5 % / 横 −0.4 %、3.6 秒周期、sine）と尻尾の揺れ（±5°、4.8 秒周期）を入れる。ループは 14.4 秒（呼吸 4 回・揺れ 3 回）で、二つのリズムがずれ続けて機械的に見えない | アセット README §6: 呼吸は 1.5 % 以内、尻尾は**別レイヤー**でのみ動かす（一枚絵を伸縮させない） |
| D-WB-8 | 尻尾レイヤーはオーナーの idle 画像から切り出して派生させる（新規の絵は描かない）。上半分は頬と尻尾の間の透明な隙間、下半分は腰の輪郭線（手で読んだガイド `HIP_GUIDE` に ±8 px で線をスナップ）で切り、尻尾は体の**後ろ**に描く。付け根（画像 px (748, 828)）を軸に回す。切り口の下に 28 px 分尻尾の縁を延長して、揺れても腰に隙間が出ない | 原画の雰囲気を保ったまま今すぐ動かせる最小の手段。正式な尻尾レイヤーが納品されたら `MaliIdleTail` を差し替えるだけ |
| D-WB-9 | 反応が揺れの途中で始まるとき、クリップが動かさないプロパティ（尻尾の回転、呼吸の scale）は 180 ms でそっと戻し、クリップが動かすプロパティだけ即座に rest へ（`CatRig.settle`） | 揺れた尻尾が反応開始の瞬間に跳ねるのを防ぐ。プレビューも同じ規則（`rig.js` の settling） |

**データ契約**: `mali_poses.json` の `poses.idle.imageSet` は `MaliIdleBody`（尻尾を抜いた全身、1024 フレームのまま）、`poses.idle.layers.tail` = {`MaliIdleTail`（281 × 380 の切り出し）, 付け根基準の bounds, `pivot`（床中心基準 [236, 132]）}、`layerParts: ["tail"]`。rig には `tailPivot`（bodyPivot の子、z 1）と `tail`（tailPivot の子）を追加し、`pose`（z 2）の後ろに描く。他のポーズは描き込みの尻尾のまま（レイヤーなし）。`MaliIdle` 単体の画像セットは同梱しない（body + tail が静止時に同じ絵になる）。

**変更ファイル**: `tools/character/import_wholebody_pack.py`（`tail_cut` / `split_tail` / `largest_component` / 検査シート `artifacts/mali-assets-v1/tail_split_check.png`）、`generate_wholebody_tracks.py`（idle 14.4 秒、scaleX/scaleY/tailPivot rotation）、`WholeBodyArtProvider.swift`（`Layer` / `layerParts` / レイヤー部品の `art` と検証、preload）、`CatRig.swift`（`settle(toRestOver:controlled:)`、`restEaseKey`）、`CatSceneController.swift`（start 時に settle、stop の reset を選択制に）、`scripts/check_resources.py`（レイヤー画像セット・bounds・pivot 一致・z 順・tailPivot ≤ 8°）、`tools/rig-preview/`（レイヤー部品の strict variants、settle、`expressionBlendMs` を JSON から、idle の静止画 6 枚 + 反応直後 1 枚）、`NikuCueTests/WholeBodyArtProviderTests.swift`（ノード 6、レイヤー art、settle、未実行）。

**切り出しの検査**（`check_resources.py` PASS）: 尻尾の行 539〜913、切り口 x 735〜837、孤立断片 43 px を体へ戻し、延長 4844 px。静止時の合成は掃除済み idle と一致（体の縁の半透明画素の下に尻尾の延長が入る分だけ差。平均 0.50/255）。検査シートで −5° / +5° の合成と腰の拡大を確認。初回は中央値平滑化が頬と腰に切り口を引き込み、ひげの先が尻尾側に入った → 隙間行は「幅 10 px 以上の不透明 run」、腰はガイド線スナップ、最大連結成分のみ採用、に変更して解消。

**ブラウザ確認**: 待機 0 / 1.2 / 2.4 / 3.6 / 6.0 / 8.4 秒の静止画で揺れと呼吸、`12_greet_after_sway` で反応開始時に尻尾が跳ねないことを確認（`artifacts/mali-assets-v1/preview/`）。**未実施**: Simulator / 実機。

### sleepy の前足が 5 本に見える問題の修正（2026-10-11, オーナー報告）

| ID | 決定 | 根拠 |
|---|---|---|
| D-WB-10 | オーナー提供の `mali_sleepy.png`（あくびで片方の前足を口元に上げた姿勢）は床の列に前足 2 本 + 後ろ足 2 本が残り、上げた手と合わせて 5 本に見える。画面手前左の中央前足（x 344〜480, y 877〜958）を消し、胸〜腹の毛を左右反転して 100 px 下げた複製で埋め、後ろ足と残った前足をつなぐ腹の輪郭線と影を描く**コードのみのレタッチ**（`tools/character/retouch_sleepy.py`、Pillow + numpy、乱数は固定シード、生成 AI 不使用）を取り込み時に適用する | 原画の差し替えが来るまでの暫定。原本は `docs/assets/mali_v1` に残し、取り込みは再現可能（同じバイト列）。編集は x 343〜511 / y 850〜959 の内側に限定し、alpha の外接矩形は不変（床合わせを壊さない） |
| D-WB-11 | 3 つの戦略（A: 上の毛を複製して埋める、B: 反転複製、C: 残った前足を中央へ寄せる）を独立に生成し、3 つの観点（240 px での判読、原寸の継ぎ目、セットとの画風・解剖の整合）で採点、上位を 2 名が反証する審査で B を採用（B 21 / A 19 / C 17、いずれも床の足は 3 本） | 1 案だけで決めない（判断材料を残す）。反証で挙がった原寸の欠陥は取り込み前に修正した（下記） |

**反証で確定し修正した欠陥**: 上端の継ぎ目で alpha が 252 → 255 に立ち上がり暗い背景で 1 px の明るい横線になる → 体の alpha を超えないよう clamp、フェードを領域上端から開始。消した前足の白い縁が x=343 に残り後ろ足の輪郭が二重に見える → 343 は後ろ足輪郭のアンチエイリアスとして保持し、隣接列の暗化を弱めて単調な勾配にする。残った前足の左下のアンチエイリアス画素が削られて階段状 → V 字の切れ込みより右の半透明画素は消去対象から除外し、`assert` で保護。腹の輪郭線の芯が前足の底の線と途切れる → 接合部で暗い方を採る。反転複製した胸の折れ線が二本目の皺に見える → その帯を行の毛色平均へ 60 % 寄せる。輪郭線が均一でベクター的 → 線幅・濃さを固定シードで ±18 % 揺らし、色を既存の足の線の平均（168, 104, 62）に寄せる。残る既知の弱点: 原寸 3〜4 倍で見ると埋めた毛の筆致が周囲より滑らか、残った前足の左上の角が他の足より小さい丸み。240 px（アプリ表示）では判別できない。

**確認物**: `artifacts/mali-assets-v1/sleepy_retouch_check.png`（原本 / レタッチ、明暗、足元 4 倍）。`check_resources.py` PASS。これは**コードによる暫定修正**であり、オーナーの承認（または原画の再納品）が必要（R02）。

### 尻尾レイヤー変更の静的レビュー（2026-10-11, Workflow `review-tail-layer-change`、4 観点 → 各指摘を 2 名が反証）

指摘 17 件のうち確定 5 件、却下 12 件（2 名とも「実在」と判定したものだけ確定）。確定分の対応:

| 指摘 | 対応 |
|---|---|
| Gallery / Demo の `playDemo` が `stopInteraction()`（reset あり）で rig を rest に戻してから `start()` の settle を呼ぶため、オーナーが動きを確認する画面でだけ尻尾と呼吸が跳ねる | `stopInteraction(resetting: false)`。`start()` が reset なしで止めて settle する |
| settle のテストが scene 生成前に尻尾の回転を仕込んでおり、controller の初期化で rest に戻されて必ず失敗する | scene 生成後に仕込み、`playDemo(.greet)` で尻尾は ease・bodyPivot（greet が scale を駆動）は snap を検証 |
| `capture.mjs` の `idleLead` 付き静止画が、クリップ開始（仮想 1200 ms）より前の時刻でサンプリングされ settle の進行が負になる（尻尾 −396°） | サンプル時刻をリード分ずらし、cross-fade 中の前の look（尻尾レイヤー）を保持 |
| 「sleepy の前足 5 本が未対応」 | レビュー対象のコミット時点では未対応（その後 `678d4ef` で対応済み） |
| `capture.mjs` の同件（重複） | 上と同じ |

却下のうち、安価に塞げる 3 件も対応した: 切り口の延長（underlap）が最大連結成分で落とした断片の行にも書かれ、孤立した小片が +5° で体の外にはみ出す → 保持された行だけ延長（尻尾の切り出し範囲が [733, 536, 986, 893] に縮小）。静止時合成の差分指標が alpha 0 の画素の RGB まで比較して無意味 → premultiplied の色差と alpha 差を別々に記録。`check_resources.py` が全身用 track の時刻順・duration 内・ease 名・controls を検証していなかった → 追加。

